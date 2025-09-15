-- server.lua
-- Azure Framework Character UI server (integrated with az-fw-money selection)

local DEBUG = true
local activeCharacters = {} -- [source] = charid

local function debugPrint(fmt, ...)
  if not DEBUG then return end
  local ok, msg = pcall(string.format, fmt, ...)
  if not ok then
    print("[azfw DEBUG] (format error) - raw args follow:")
    print(...)
    return
  end
  print("[azfw DEBUG] " .. msg)
end

local function safeEncode(obj)
  if not obj then return "<nil>" end
  if type(obj) == "string" then return obj end
  if type(obj) == "number" then return tostring(obj) end
  if type(obj) == "table" then
    if json and type(json.encode) == "function" then
      local ok, res = pcall(json.encode, obj)
      if ok then return res end
    end
    local parts = {}
    for k, v in pairs(obj) do
      parts[#parts + 1] = tostring(k) .. ":" .. (type(v) == "table" and "<table>" or tostring(v))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(obj)
end

-- Normalize DB "affected" callback values to a number (or nil)
local function parseAffected(affected)
  if type(affected) == "number" then
    return affected
  end
  if type(affected) == "string" then
    local n = tonumber(affected)
    if n then return n end
  end
  if type(affected) == "table" then
    -- try common numeric fields oxmysql might return
    local candidates = {
      "affectedRows", "affected", "rowsAffected", "changedRows", "affected_rows", "affected_rows_count"
    }
    for _, k in ipairs(candidates) do
      if affected[k] ~= nil then
        local n = tonumber(affected[k])
        if n then return n end
      end
    end
    -- if table non-empty assume success (1) — prevents false negative on odd returns
    if next(affected) ~= nil then
      return 1
    end
  end
  return nil
end

local function getDiscordID(src)
  local ids = GetPlayerIdentifiers(src) or {}
  debugPrint("getDiscordID called for src=%s. Identifiers: %s", tostring(src), safeEncode(ids))
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1,8) == "discord:" then
      local raw = id:sub(9)
      debugPrint("-> Found discord prefix. Returning raw id '%s' (from '%s')", raw, id)
      return raw
    end
  end
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:match("^%d+$") then
      debugPrint("-> Found numeric identifier without prefix. Returning '%s'", id)
      return id
    end
  end
  debugPrint("-> No discord identifier found for src=%s", tostring(src))
  return ''
end

-- fetch characters function (used for pushes) — works with mysql-async (Sync) or oxmysql (async)
local function fetchCharactersForSource(src)
  debugPrint("fetchCharactersForSource() start for src=%s", tostring(src))
  local discordID = getDiscordID(src)
  debugPrint("fetchCharactersForSource: derived discordID='%s' for src=%s", tostring(discordID), tostring(src))

  if discordID == '' then
    debugPrint("fetchCharactersForSource: empty discordID, returning empty list")
    return {}
  end

  -- Preferred: if MySQL.Sync.fetchAll exists (mysql-async), use it
  if MySQL and MySQL.Sync and type(MySQL.Sync.fetchAll) == "function" then
    local ok, rowsOrErr = pcall(function()
      return MySQL.Sync.fetchAll([[
        SELECT
          uc.charid,
          uc.name,
          uc.active_department,
          uc.license_status,
          IFNULL(eum.cash, 0) AS cash,
          IFNULL(eum.bank, 0) AS bank
        FROM user_characters uc
        LEFT JOIN econ_user_money eum
          ON eum.discordid = uc.discordid AND eum.charid = uc.charid
        WHERE uc.discordid = ?
        ORDER BY uc.id ASC
      ]], { discordID })
    end)
    if not ok then
      debugPrint("fetchCharactersForSource: MySQL.Sync.fetchAll pcall failed. Error: %s", tostring(rowsOrErr))
      return {}
    end
    debugPrint("fetchCharactersForSource: Query returned %s rows for discord=%s", tostring(#rowsOrErr), tostring(discordID))
    debugPrint("fetchCharactersForSource: rows content: %s", safeEncode(rowsOrErr))
    return rowsOrErr or {}
  end

  -- Fallback: if oxmysql is available via exports.oxmysql:query, use it (async -> wait loop)
  if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
    local done = false
    local result = {}
    local ok, err = pcall(function()
      exports.oxmysql:query([[
        SELECT
          uc.charid,
          uc.name,
          uc.active_department,
          uc.license_status,
          IFNULL(eum.cash, 0) AS cash,
          IFNULL(eum.bank, 0) AS bank
        FROM user_characters uc
        LEFT JOIN econ_user_money eum
          ON eum.discordid = uc.discordid AND eum.charid = uc.charid
        WHERE uc.discordid = ?
        ORDER BY uc.id ASC
      ]], { discordID }, function(rows)
        result = rows or {}
        done = true
      end)
    end)
    if not ok then
      debugPrint("fetchCharactersForSource: exports.oxmysql:query pcall failed. Error: %s", tostring(err))
      return {}
    end
    -- wait for the async callback (short timeout)
    local waitTicks = 0
    while not done and waitTicks < 6000 do -- wait up to ~6s
      Citizen.Wait(1)
      waitTicks = waitTicks + 1
    end
    if not done then
      debugPrint("fetchCharactersForSource: oxmysql query did not complete in time for discord=%s", tostring(discordID))
      return {}
    end
    debugPrint("fetchCharactersForSource (oxmysql): Query returned %s rows for discord=%s", tostring(#result), tostring(discordID))
    debugPrint("fetchCharactersForSource: rows content: %s", safeEncode(result))
    return result or {}
  end

  debugPrint("fetchCharactersForSource: MySQL lib not found (neither mysql-async nor oxmysql). MySQL object: %s", safeEncode(MySQL))
  return {}
end

-- lib.callback registration (if available)
if lib and lib.callback and type(lib.callback.register) == "function" then
  debugPrint("lib.callback available. Registering 'azfw:fetch_characters' callback")
  lib.callback.register('azfw:fetch_characters', function(source, _)
    debugPrint("lib.callback 'azfw:fetch_characters' invoked from source=%s", tostring(source))
    local rows = fetchCharactersForSource(source)
    debugPrint("lib.callback returning %s rows to source=%s", tostring(#rows), tostring(source))
    return rows
  end)
else
  debugPrint("lib.callback NOT available. Skipping callback registration.")
end

-- Primary fallback event
RegisterNetEvent('azfw_fetch_characters', function()
  local src = source
  debugPrint("Event 'azfw_fetch_characters' triggered by src=%s", tostring(src))
  local rows = fetchCharactersForSource(src)
  debugPrint("Triggering client event 'azfw:characters_updated' for src=%s with %s rows", tostring(src), tostring(#rows))
  TriggerClientEvent('azfw:characters_updated', src, rows or {})
end)

-- Alias for older client names (backwards compatibility)
RegisterNetEvent('azfw:request_characters', function()
  local src = source
  debugPrint("Alias 'azfw:request_characters' triggered by src=%s - forwarding to fetchCharactersForSource", tostring(src))
  local rows = fetchCharactersForSource(src)
  TriggerClientEvent('azfw:characters_updated', src, rows or {})
end)

-- Create character + ensure econ row (robust with mysql-async or oxmysql)
RegisterNetEvent('azfw_register_character', function(firstName, lastName, dept, license)
  local src = source
  debugPrint("Event 'azfw_register_character' triggered by src=%s with args firstName=%s lastName=%s dept=%s license=%s", tostring(src), tostring(firstName), tostring(lastName), tostring(dept), tostring(license))
  local identifiers = GetPlayerIdentifiers(src) or {}
  debugPrint("Player identifiers for src=%s: %s", tostring(src), safeEncode(identifiers))
  local discordID = getDiscordID(src)
  if discordID == '' then
    debugPrint("azfw_register_character: No discord ID for src=%s - aborting", tostring(src))
    TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Could not register character: no Discord ID found.' } })
    return
  end

  local charID = tostring(os.time()) .. tostring(math.random(1000,9999))
  local fullName = tostring(firstName or '') .. (lastName and (' ' .. tostring(lastName)) or '')
  local active_department = tostring(dept or '')
  local license_status = tostring(license or 'UNKNOWN')

  debugPrint("Inserting new character: discord=%s charID=%s name=%s dept=%s license=%s", tostring(discordID), tostring(charID), tostring(fullName), tostring(active_department), tostring(license_status))

  -- Option A: mysql-async (MySQL.Async.execute)
  if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
    MySQL.Async.execute([[
      INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
      VALUES (@discordid, @charid, @name, @active_department, @license_status)
    ]], {
      ['@discordid'] = discordID,
      ['@charid']   = charID,
      ['@name']     = fullName,
      ['@active_department'] = active_department,
      ['@license_status'] = license_status
    }, function(affected)
      local numAffected = parseAffected(affected)
      debugPrint("INSERT user_characters callback fired. rawAffected=%s parsed=%s", safeEncode(affected), tostring(numAffected))
      if not numAffected or numAffected < 1 then
        debugPrint("INSERT failed for discord=%s charID=%s", tostring(discordID), tostring(charID))
        TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Failed to register character. Check server logs.' } })
        return
      end

      MySQL.Async.execute([[
        INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
        VALUES (@discordid, @charid, @firstname, @lastname, 0, 0, 0, 'active')
      ]], {
        ['@discordid'] = discordID,
        ['@charid']   = charID,
        ['@firstname'] = firstName or '',
        ['@lastname']  = lastName or ''
      }, function(aff2)
        local num2 = parseAffected(aff2)
        debugPrint("econ_user_money INSERT IGNORE callback raw=%s parsed=%s", safeEncode(aff2), tostring(num2))
        if not num2 or num2 < 1 then
          debugPrint("econ_user_money insert returned 0/ignored (discord=%s charid=%s). Continuing.", tostring(discordID), tostring(charID))
        end

        activeCharacters[src] = charID
        debugPrint("Marked activeCharacters[%s] = %s", tostring(src), tostring(charID))
        local rows = fetchCharactersForSource(src)
        debugPrint("After create, sending %s rows to client %s", tostring(#rows), tostring(src))
        TriggerClientEvent('azfw:characters_updated', src, rows or {})
        TriggerClientEvent('chat:addMessage', src, {
          args = { '^2SYSTEM', ('Character "%s" registered (ID %s).'):format(fullName, charID) }
        })
      end)
    end)
    return
  end

  -- Option B: oxmysql (exports.oxmysql:execute)
  if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
    exports.oxmysql:execute([[
      INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
      VALUES (?, ?, ?, ?, ?)
    ]], { discordID, charID, fullName, active_department, license_status }, function(affected)
      local numAffected = parseAffected(affected)
      debugPrint("INSERT user_characters (oxmysql) callback fired. rawAffected=%s parsed=%s", safeEncode(affected), tostring(numAffected))
      if not numAffected or numAffected < 1 then
        debugPrint("INSERT failed for discord=%s charID=%s", tostring(discordID), tostring(charID))
        TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Failed to register character. Check server logs.' } })
        return
      end

      exports.oxmysql:execute([[
        INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
        VALUES (?, ?, ?, ?, 0, 0, 0, 'active')
      ]], { discordID, charID, firstName or '', lastName or '' }, function(aff2)
        local num2 = parseAffected(aff2)
        debugPrint("econ_user_money INSERT IGNORE callback raw=%s parsed=%s", safeEncode(aff2), tostring(num2))
        if not num2 or num2 < 1 then
          debugPrint("econ_user_money insert returned 0/ignored (discord=%s charid=%s). Continuing.", tostring(discordID), tostring(charID))
        end

        activeCharacters[src] = charID
        debugPrint("Marked activeCharacters[%s] = %s", tostring(src), tostring(charID))
        local rows = fetchCharactersForSource(src)
        debugPrint("After create, sending %s rows to client %s", tostring(#rows), tostring(src))
        TriggerClientEvent('azfw:characters_updated', src, rows or {})
        TriggerClientEvent('chat:addMessage', src, {
          args = { '^2SYSTEM', ('Character "%s" registered (ID %s).'):format(fullName, charID) }
        })
      end)
    end)
    return
  end

  -- No DB API available
  debugPrint("azfw_register_character: No supported DB API found (MySQL.Async.execute or exports.oxmysql.execute). MySQL object: %s", safeEncode(MySQL))
  TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Database not available.' } })
end)

-- Delete character
RegisterNetEvent('azfw_delete_character', function(charid)
  local src = source
  debugPrint("Event 'azfw_delete_character' triggered by src=%s charid=%s", tostring(src), tostring(charid))
  if not charid then
    debugPrint("azfw_delete_character: missing charid from src=%s", tostring(src))
    TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Invalid delete request.' } })
    return
  end
  local discordID = getDiscordID(src)
  if discordID == '' then
    debugPrint("azfw_delete_character: no discord id for src=%s", tostring(src))
    TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Invalid delete request.' } })
    return
  end
  debugPrint("Attempting DELETE for discord=%s charid=%s", tostring(discordID), tostring(charid))

  -- prefer mysql-async if available
  if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
    MySQL.Async.execute([[ 
      DELETE FROM user_characters
      WHERE discordid = @discordid AND charid = @charid
    ]], {
      ['@discordid'] = discordID,
      ['@charid'] = charid
    }, function(affected)
      local numAffected = parseAffected(affected)
      debugPrint("DELETE callback fired. rawAffected=%s parsed=%s", safeEncode(affected), tostring(numAffected))
      if numAffected and numAffected > 0 then
        local rows = fetchCharactersForSource(src)
        debugPrint("After DELETE, fetched %s rows to send back to client %s", tostring(#rows), tostring(src))
        TriggerClientEvent('azfw:characters_updated', src, rows or {})
        TriggerClientEvent('chat:addMessage', src, { args = { '^2SYSTEM', 'Character deleted.' } })
        if activeCharacters[src] == charid then
          debugPrint("Clearing activeCharacters for src=%s (was charid=%s)", tostring(src), tostring(charid))
          activeCharacters[src] = nil
        end
      else
        debugPrint("DELETE affected 0 rows for discord=%s charid=%s", tostring(discordID), tostring(charid))
        TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Failed to delete character.' } })
      end
    end)
    return
  end

  -- fallback to oxmysql
  if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
    exports.oxmysql:execute([[ 
      DELETE FROM user_characters
      WHERE discordid = ? AND charid = ?
    ]], { discordID, charid }, function(affected)
      local numAffected = parseAffected(affected)
      debugPrint("DELETE (oxmysql) callback fired. rawAffected=%s parsed=%s", safeEncode(affected), tostring(numAffected))
      if numAffected and numAffected > 0 then
        local rows = fetchCharactersForSource(src)
        debugPrint("After DELETE, fetched %s rows to send back to client %s", tostring(#rows), tostring(src))
        TriggerClientEvent('azfw:characters_updated', src, rows or {})
        TriggerClientEvent('chat:addMessage', src, { args = { '^2SYSTEM', 'Character deleted.' } })
        if activeCharacters[src] == charid then
          debugPrint("Clearing activeCharacters for src=%s (was charid=%s)", tostring(src), tostring(charid))
          activeCharacters[src] = nil
        end
      else
        debugPrint("DELETE affected 0 rows for discord=%s charid=%s", tostring(discordID), tostring(charid))
        TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Failed to delete character.' } })
      end
    end)
    return
  end

  debugPrint("azfw_delete_character: No supported DB API found (MySQL.Async.execute or exports.oxmysql.execute). MySQL object: %s", safeEncode(MySQL))
  TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Database not available.' } })
end)

-- handleSelectCharacter: implements your az-fw-money selection snippet safely
local function handleSelectCharacter(src, charID)
  if not src then return end
  debugPrint("handleSelectCharacter called for src=%s charID=%s", tostring(src), tostring(charID))
  local did = getDiscordID(src)
  if not did or did == '' then
    debugPrint("handleSelectCharacter: no discord id for src=%s", tostring(src))
    return
  end

  -- run the same oxmysql query you provided
  -- NOTE: this uses exports.oxmysql:query as in your snippet
  if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
    exports.oxmysql:query(
      "SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ?",
      { did, charID },
      function(rows)
        if rows and #rows > 0 then
          activeCharacters[src] = charID

          -- send money HUD if function exists
          if type(sendMoneyToClient) == 'function' then
            pcall(function() sendMoneyToClient(src) end)
          end

          -- fetch active_department using whichever DB API we have
          if MySQL and MySQL.Async and type(MySQL.Async.fetchScalar) == "function" then
            MySQL.Async.fetchScalar([[ 
              SELECT active_department
              FROM user_characters
              WHERE discordid = @discordid AND charid = @charid
              LIMIT 1
            ]], {
              ['@discordid'] = did,
              ['@charid']    = charID
            }, function(active_dept)
              TriggerClientEvent('hud:setDepartment', src, active_dept or '')
            end)
          elseif exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
            exports.oxmysql:query([[
              SELECT active_department
              FROM user_characters
              WHERE discordid = ? AND charid = ?
              LIMIT 1
            ]], { did, charID }, function(rows2)
              local active_dept = nil
              if rows2 and #rows2 > 0 then active_dept = rows2[1].active_department end
              TriggerClientEvent('hud:setDepartment', src, active_dept or '')
            end)
          else
            debugPrint("handleSelectCharacter: no DB API to fetch active_department")
            TriggerClientEvent('hud:setDepartment', src, '')
          end

          TriggerClientEvent('az-fw-money:characterSelected', src, charID)
        else
          debugPrint("handleSelectCharacter: validation failed for src=%s charID=%s", tostring(src), tostring(charID))
        end
      end
    )
  else
    -- if oxmysql isn't present, try mysql-async path
    if MySQL and MySQL.Sync and type(MySQL.Sync.fetchAll) == "function" then
      local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll("SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", { did, charID })
      end)
      if ok and rows and #rows > 0 then
        activeCharacters[src] = charID
        if type(sendMoneyToClient) == 'function' then pcall(function() sendMoneyToClient(src) end) end
        local active_dept = MySQL.Sync.fetchScalar([[ 
          SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1
        ]], { did, charID })
        TriggerClientEvent('hud:setDepartment', src, active_dept or '')
        TriggerClientEvent('az-fw-money:characterSelected', src, charID)
      else
        debugPrint("handleSelectCharacter: validation failed (mysql-sync) for src=%s charID=%s", tostring(src), tostring(charID))
      end
    else
      debugPrint("handleSelectCharacter: no DB API available to validate character selection")
    end
  end
end

-- Register the az-fw-money event (as you provided)
RegisterNetEvent('az-fw-money:selectCharacter', function(charID)
  handleSelectCharacter(source, charID)
end)

-- Backwards-compat: allow old event name to call the same handler
RegisterNetEvent('azfw:set_active_character', function(charid)
  handleSelectCharacter(source, charid)
end)

AddEventHandler('playerDropped', function(reason)
  debugPrint("playerDropped called for src=%s reason=%s", tostring(source), tostring(reason))
  if activeCharacters[source] ~= nil then
    debugPrint("Clearing activeCharacters for src=%s (was=%s)", tostring(source), tostring(activeCharacters[source]))
  end
  activeCharacters[source] = nil
end)

-- NEW: send characters + open UI when player joins (with slight delay so client can initialize)
AddEventHandler('playerJoining', function()
  local src = source
  debugPrint("playerJoining: src=%s", tostring(src))

  local ok, rows = pcall(function() return fetchCharactersForSource(src) end)
  if not ok then
    debugPrint("playerJoining: fetchCharactersForSource errored for src=%s: %s", tostring(src), tostring(rows))
    rows = {}
  end

  -- Delay sending so client has time to register its events
  SetTimeout(800, function()
    debugPrint("playerJoining: delayed send of %s rows to src=%s", tostring(#rows), tostring(src))
    TriggerClientEvent('azfw:characters_updated', src, rows or {})
    TriggerClientEvent('azfw:open_ui', src, rows or {})
  end)
end)

-- NEW: Re-push characters to players when resource starts; also request client to open UI (with delay)
AddEventHandler('onResourceStart', function(resourceName)
  local thisName = GetCurrentResourceName()
  if resourceName ~= thisName then return end
  debugPrint("onResourceStart: resource '%s' started. Refreshing characters for connected players.", tostring(resourceName))

  local players = GetPlayers() or {}
  for _, ply in ipairs(players) do
    local src = tonumber(ply) or ply
    debugPrint("onResourceStart: fetching characters for src=%s", tostring(src))
    local ok, rows = pcall(function() return fetchCharactersForSource(src) end)
    if not ok then
      debugPrint("onResourceStart: fetchCharactersForSource errored for src=%s: %s", tostring(src), tostring(rows))
      rows = {}
    end

    -- Delay sending so client has time to initialize NUI + events
    SetTimeout(900, function()
      debugPrint("onResourceStart: delayed send %s rows to src=%s", tostring(#rows), tostring(src))
      TriggerClientEvent('azfw:characters_updated', src, rows or {})
      TriggerClientEvent('azfw:open_ui', src, rows or {})
    end)
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  local thisName = GetCurrentResourceName()
  if resourceName ~= thisName then return end
  debugPrint("onResourceStop: resource '%s' stopping. Clearing activeCharacters map.", tostring(resourceName))
  activeCharacters = {}
end)

RegisterNetEvent('azfw_debug_dump_state', function()
  local src = source
  debugPrint("azfw_debug_dump_state requested by src=%s", tostring(src))
  debugPrint("Current activeCharacters map: %s", safeEncode(activeCharacters))
  TriggerClientEvent('chat:addMessage', src, { args = { '^2AZFW DEBUG', 'Server state dumped to server console.' } })
end)

debugPrint("server.lua loaded (DEBUG mode = %s). Ready to handle events. MySQL object: %s", tostring(DEBUG), safeEncode(MySQL))






-- server.lua
-- Server-side: load & save spawns, admin checks via Az-Framework export, and events for clients.

-- ensure config.lua is loaded (fxmanifest lists config.lua)
Config = Config or {}
local json = json

-- safe helper for current resource name
local function safeGetResourceName()
  local ok, name = pcall(GetCurrentResourceName)
  if not ok or type(name) ~= "string" or name == "" then
    print("^1[spawn_selector]^7 GetCurrentResourceName returned invalid value")
    return nil
  end
  return name
end

-- load spawns, robust with logging, returns table (array) or {}
local function loadSpawns()
  if type(Config) ~= "table" or type(Config.SpawnFile) ~= "string" then
    print("^1[spawn_selector]^7 Config.SpawnFile missing or not a string. Using empty spawns.")
    return {}
  end

  local resource = safeGetResourceName()
  if not resource then
    print("^1[spawn_selector]^7 Unable to determine resource name; returning empty spawns.")
    return {}
  end

  local filename = Config.SpawnFile
  local raw = nil
  local ok, err = pcall(function()
    raw = LoadResourceFile(resource, filename)
  end)
  if not ok then
    print(("^1[spawn_selector]^7 LoadResourceFile threw an error for %s/%s: %s"):format(resource, filename, tostring(err)))
    return {}
  end

  if not raw then
    -- If file is missing, create a default [] file so next loads succeed
    print(("^3[spawn_selector]^7 %s not found in resource %s — creating default empty file"):format(filename, resource))
    local created, createErr = pcall(function()
      SaveResourceFile(resource, filename, "[]", -1)
    end)
    if not created then
      print(("^1[spawn_selector]^7 Failed to create default %s in %s: %s"):format(filename, resource, tostring(createErr)))
    end
    return {}
  end

  local ok2, decoded = pcall(json.decode, raw)
  if not ok2 or type(decoded) ~= "table" then
    print(("^1[spawn_selector]^7 failed to decode %s — returning empty table"):format(filename))
    return {}
  end

  return decoded
end

-- save spawns table to file (returns true/false, err)
local function saveSpawns(tbl)
  if type(tbl) ~= "table" then
    return false, "invalid_table"
  end
  if type(Config) ~= "table" or type(Config.SpawnFile) ~= "string" then
    return false, "bad_config"
  end

  local resource = safeGetResourceName()
  if not resource then
    return false, "no_resource_name"
  end

  local ok, encoded = pcall(json.encode, tbl)
  if not ok or type(encoded) ~= "string" then
    return false, "encode_failed"
  end

  local saved, saveErr = pcall(function()
    SaveResourceFile(resource, Config.SpawnFile, encoded, -1)
  end)
  if not saved then
    return false, "save_failed"
  end

  return true
end

-- Provide spawns to a client on request
RegisterServerEvent('spawn_selector:requestSpawns')
AddEventHandler('spawn_selector:requestSpawns', function()
  local src = source
  local spawns = loadSpawns() or {}
  TriggerClientEvent('spawn_selector:sendSpawns', src, spawns, Config.MapBounds or {})
end)

-- Admin check: client asks server; server calls Az-Framework export and replies to the requesting client
RegisterServerEvent('spawn_selector:checkAdmin')
AddEventHandler('spawn_selector:checkAdmin', function()
  local src = source
  if Config.RequireAzAdminForEdit and exports['Az-Framework'] and exports['Az-Framework'].isAdmin then
    -- Az-Framework has a server-side isAdmin export with callback style
    exports['Az-Framework']:isAdmin(src, function(isAdmin)
      TriggerClientEvent('spawn_selector:adminCheckResult', src, isAdmin and true or false)
    end)
  else
    -- fallback: either not required or export missing
    TriggerClientEvent('spawn_selector:adminCheckResult', src, false)
  end
end)

-- save spawns (only admins allowed)
RegisterServerEvent('spawn_selector:saveSpawns')
AddEventHandler('spawn_selector:saveSpawns', function(spawns)
  local src = source
  if type(spawns) ~= "table" then
    TriggerClientEvent('spawn_selector:spawnsSaved', src, false, "invalid_payload")
    return
  end

  -- verify admin via Az-Framework if required
  if Config.RequireAzAdminForEdit and exports['Az-Framework'] and exports['Az-Framework'].isAdmin then
    exports['Az-Framework']:isAdmin(src, function(isAdmin)
      if not isAdmin then
        TriggerClientEvent('spawn_selector:spawnsSaved', src, false, "not_admin")
        return
      end

      local ok, err = saveSpawns(spawns)
      if not ok then
        TriggerClientEvent('spawn_selector:spawnsSaved', src, false, err or "save_failed")
        return
      end

      TriggerClientEvent('spawn_selector:spawnsSaved', src, true)
      -- broadcast updated spawns so other clients can refresh
      TriggerClientEvent('spawn_selector:spawnsUpdated', -1, spawns)
    end)
  else
    -- if editing not restricted or Az-Framework export missing, allow save (or deny depending on config)
    if not Config.RequireAzAdminForEdit then
      local ok, err = saveSpawns(spawns)
      if not ok then
        TriggerClientEvent('spawn_selector:spawnsSaved', src, false, err or "save_failed")
        return
      end
      TriggerClientEvent('spawn_selector:spawnsSaved', src, true)
      TriggerClientEvent('spawn_selector:spawnsUpdated', -1, spawns)
    else
      -- export missing -> deny
      TriggerClientEvent('spawn_selector:spawnsSaved', src, false, "no_export")
    end
  end
end)
