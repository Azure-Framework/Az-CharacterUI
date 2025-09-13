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

-- fetch characters function (used for pushes)
local function fetchCharactersForSource(src)
  debugPrint("fetchCharactersForSource() start for src=%s", tostring(src))
  local discordID = getDiscordID(src)
  debugPrint("fetchCharactersForSource: derived discordID='%s' for src=%s", tostring(discordID), tostring(src))

  if discordID == '' then
    debugPrint("fetchCharactersForSource: empty discordID, returning empty list")
    return {}
  end

  if not MySQL or not MySQL.Sync or type(MySQL.Sync.fetchAll) ~= "function" then
    debugPrint("fetchCharactersForSource: MySQL.Sync.fetchAll NOT AVAILABLE. MySQL object: %s", safeEncode(MySQL))
    return {}
  end

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

-- Create character + ensure econ row
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

  if not MySQL or not MySQL.Async or type(MySQL.Async.execute) ~= "function" then
    debugPrint("MySQL.Async.execute not available. Aborting insert.")
    TriggerClientEvent('chat:addMessage', src, { args = { '^1SYSTEM', 'Database not available.' } })
    return
  end

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
    debugPrint("INSERT user_characters callback fired. affected=%s", tostring(affected))
    if not affected or affected < 1 then
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
      debugPrint("econ_user_money INSERT IGNORE callback affected=%s", tostring(aff2))
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
  MySQL.Async.execute([[
    DELETE FROM user_characters
    WHERE discordid = @discordid AND charid = @charid
  ]], {
    ['@discordid'] = discordID,
    ['@charid'] = charid
  }, function(affected)
    debugPrint("DELETE callback fired. affected=%s", tostring(affected))
    if affected and affected > 0 then
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

        -- send the client the department for this character (clears previous char's job)
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

        TriggerClientEvent('az-fw-money:characterSelected', src, charID)
      else
        debugPrint("handleSelectCharacter: validation failed for src=%s charID=%s", tostring(src), tostring(charID))
      end
    end
  )
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
