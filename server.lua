local RESOURCE_NAME = GetCurrentResourceName()
local json = json

Config = Config or {}
Config.Debug = (Config.Debug ~= false)
local DEBUG = Config.Debug

-- Core toggles
Config.EnableLastLocation   = (Config.EnableLastLocation ~= false)
Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)

-- Spawn editor
Config.SpawnFile   = Config.SpawnFile or "spawns.json"
Config.MapBounds   = Config.MapBounds or { minX = -3000, maxX = 3000, minY = -6300, maxY = 7000 }
Config.RequireAzAdminForEdit = (Config.RequireAzAdminForEdit == true)
Config.AdminAcePermission = Config.AdminAcePermission or "azfw.spawns.edit"
Config.SpawnMenuCommand = Config.SpawnMenuCommand or "spawnmenu"

-- Starting money (optional)
Config.StartingCash = tonumber(Config.StartingCash) or 0

-- Housing integration (optional)
Config.Housing = Config.Housing or {}
Config.Housing.Enabled = (Config.Housing.Enabled ~= false)
Config.Housing.Table = tostring(Config.Housing.Table or "az_houses")
Config.Housing.OwnerColumn = tostring(Config.Housing.OwnerColumn or "owner_identifier")
Config.Housing.DoorsTable = tostring(Config.Housing.DoorsTable or "az_house_doors")
Config.Housing.EnableHomePill = (Config.Housing.EnableHomePill ~= false)
Config.Housing.EnableHomeSpawn = (Config.Housing.EnableHomeSpawn ~= false)
Config.Housing.HomeSpawnLocked = (Config.Housing.HomeSpawnLocked == true)
Config.Housing.ShowInCharacterUI = (Config.Housing.EnableHomePill ~= false)
Config.Housing.ShowAsSpawnOption = (Config.Housing.EnableHomeSpawn ~= false)
Config.Housing.SpawnCoordsByInterior = Config.Housing.SpawnCoordsByInterior or Config.Housing.InteriorSpawns or {}
Config.Housing.FallbackSpawn = Config.Housing.FallbackSpawn or { x = 215.76, y = -810.12, z = 30.73, h = 157.0 }

-- Framework export (optional, used for GetPlayerCharacter + isAdmin)
local fw = exports["Az-Framework"]

-- Runtime state
local activeCharacters = {}   -- [src]=charid
local prevBuckets = {}        -- [src]=bucket
local lastLoc = {}            -- [src]={charid,x,y,z,h,at}
local adminCache = {}         -- [src]=bool
local appearanceCache = {}    -- ["did|charid"]={appearance=string,at=os.time()}

-- ✅ forward declare so txAdmin/monitor handlers never hit a nil global
local hardSaveCachedLastPosForAll

local function iprint(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, ok and msg or tostring(fmt)))
end

local function dprint(fmt, ...)
  if not DEBUG then return end
  iprint("[DEBUG] " .. tostring(fmt), ...)
end

iprint("^2server.lua BOOT (Debug=%s)^7", tostring(DEBUG))

-- ------------------------------------------------------------
-- DB helpers (oxmysql OR mysql-async)
-- ------------------------------------------------------------
local HAS_OX = (exports and exports.oxmysql and (type(exports.oxmysql.query) == "function" or type(exports.oxmysql.execute) == "function"))
local HAS_MY = (MySQL and (MySQL.Async or MySQL.Sync))

local function dbDriver()
  if HAS_OX then return "ox" end
  if HAS_MY then return "mysql" end
  return "none"
end

local function awaitPromise(fn)
  local p = promise.new()
  fn(function(res) p:resolve(res) end)
  return Citizen.Await(p)
end

local function oxQuery(sql, params)
  if type(exports.oxmysql.query) == "function" then
    return awaitPromise(function(done)
      exports.oxmysql:query(sql, params or {}, function(rows) done(rows or {}) end)
    end)
  end
  if type(exports.oxmysql.execute) == "function" then
    return awaitPromise(function(done)
      exports.oxmysql:execute(sql, params or {}, function(rows) done(rows or {}) end)
    end)
  end
  return {}
end

local function oxExec(sql, params)
  return awaitPromise(function(done)
    exports.oxmysql:execute(sql, params or {}, function(affected) done(affected) end)
  end)
end

local function myFetchAll(sql, paramsNamed)
  if MySQL.Async and MySQL.Async.fetchAll then
    return awaitPromise(function(done)
      MySQL.Async.fetchAll(sql, paramsNamed or {}, function(rows) done(rows or {}) end)
    end)
  end
  if MySQL.Sync and MySQL.Sync.fetchAll then
    return MySQL.Sync.fetchAll(sql, paramsNamed or {}) or {}
  end
  return {}
end

local function myExecute(sql, paramsNamed)
  if MySQL.Async and MySQL.Async.execute then
    return awaitPromise(function(done)
      MySQL.Async.execute(sql, paramsNamed or {}, function(affected) done(affected) end)
    end)
  end
  if MySQL.Sync and MySQL.Sync.execute then
    return MySQL.Sync.execute(sql, paramsNamed or {})
  end
  return 0
end

local function getDiscordID(src)
  src = tonumber(src)
  if not src or src <= 0 then return "" end

  local ping = GetPlayerPing(src)
  if not ping or ping <= 0 then return "" end

  local ids = GetPlayerIdentifiers(src)
  if type(ids) ~= "table" then return "" end

  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1, 8) == "discord:" then
      return id:sub(9)
    end
  end

  for _, id in ipairs(ids) do
    if type(id) == "string" and id:match("^%d+$") then
      return id
    end
  end

  return ""
end

local function _fwIsAdmin(src)
  src = tonumber(src)
  local ok, res

  local fwGlobal = rawget(_G, "fw")
  if fwGlobal and type(fwGlobal.isAdmin) == "function" then
    ok, res = pcall(function() return fwGlobal:isAdmin(src) end)
    if ok then return res end
  end

  local az = exports and exports["Az-Framework"] or nil
  if az and type(az.isAdmin) == "function" then
    ok, res = pcall(function() return az:isAdmin(src) end)
    if ok then return res end
  end

  return nil
end

local function isAdmin(src)
  if not src then return false end

  if Config.RequireAzAdminForEdit then
    local v = _fwIsAdmin(src)
    if v ~= nil and v == true then return true end
  end

  if IsPlayerAceAllowed(src, Config.AdminAcePermission) == true then return true end
  if IsPlayerAceAllowed(src, "azadmin.use") == true then return true end
  if IsPlayerAceAllowed(src, "command") == true then return true end

  return false
end

local function computeAndSendAdmin(src, reason)
  local ok = isAdmin(src)
  adminCache[src] = ok and true or false
  dprint("adminCache set src=%s ok=%s reason=%s", tostring(src), tostring(adminCache[src]), tostring(reason or ""))
  TriggerClientEvent("spawn_selector:adminCheckResult", src, adminCache[src])
  return adminCache[src]
end

RegisterNetEvent("spawn_selector:checkAdmin", function()
  computeAndSendAdmin(source, "client_request")
end)

local SQL_VERIFY_OX = "SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1"
local SQL_VERIFY_MY = "SELECT 1 FROM user_characters WHERE discordid = @d AND charid = @c LIMIT 1"

local function verifyCharOwner(did, charid)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return false end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_VERIFY_OX, { did, charid })
    return (rows and #rows > 0) and true or false
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_VERIFY_MY, { ["@d"] = did, ["@c"] = charid })
    return (rows and #rows > 0) and true or false
  end
  return false
end

local function getActiveCharIdForSource(src, did, optionalCharId)
  local cid = tostring(optionalCharId or "")
  if cid ~= "" and did ~= "" and verifyCharOwner(did, cid) then
    return cid
  end

  if fw and fw.GetPlayerCharacter then
    local fcid = tostring(fw:GetPlayerCharacter(src) or "")
    if fcid ~= "" and did ~= "" and verifyCharOwner(did, fcid) then
      return fcid
    end
  end

  local ac = tostring(activeCharacters[tostring(src)] or "")
  if ac ~= "" and did ~= "" and verifyCharOwner(did, ac) then
    return ac
  end

  return ""
end

RegisterNetEvent("azfw:preview:enter", function()
  local src = source
  if prevBuckets[src] then return end
  local b = (src + 1000)
  prevBuckets[src] = b
  SetPlayerRoutingBucket(src, b)
  dprint("preview enter src=%s bucket=%s", tostring(src), tostring(b))
end)

RegisterNetEvent("azfw:preview:exit", function()
  local src = source
  local b = prevBuckets[src]
  prevBuckets[src] = nil
  SetPlayerRoutingBucket(src, 0)
  dprint("preview exit src=%s prevBucket=%s", tostring(src), tostring(b))
end)

local function apKey(did, charid) return tostring(did) .. "|" .. tostring(charid) end

local function cacheAppearance(did, charid, appearanceJson)
  appearanceCache[apKey(did, charid)] = { appearance = appearanceJson, at = os.time() }
end

local function getCachedAppearance(did, charid)
  local v = appearanceCache[apKey(did, charid)]
  if not v then return nil end
  if (os.time() - (v.at or 0)) > 600 then
    appearanceCache[apKey(did, charid)] = nil
    return nil
  end
  return v.appearance
end

local SQL_AP_FETCH_OX = "SELECT appearance FROM azfw_appearance WHERE discordid = ? AND charid = ? LIMIT 1"
local SQL_AP_FETCH_MY = "SELECT appearance FROM azfw_appearance WHERE discordid = @d AND charid = @c LIMIT 1"

local function dbFetchAppearance(did, charid)
  if not Config.EnableFiveAppearance then return nil end
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return nil end

  local cached = getCachedAppearance(did, charid)
  if cached then return cached end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_AP_FETCH_OX, { did, charid })
    local a = (rows and rows[1] and rows[1].appearance) or nil
    if a then cacheAppearance(did, charid, a) end
    return a
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_AP_FETCH_MY, { ["@d"] = did, ["@c"] = charid })
    local a = (rows and rows[1] and rows[1].appearance) or nil
    if a then cacheAppearance(did, charid, a) end
    return a
  end

  return nil
end

local SQL_AP_FETCH_ALL_OX = "SELECT charid, appearance FROM azfw_appearance WHERE discordid = ?"
local SQL_AP_FETCH_ALL_MY = "SELECT charid, appearance FROM azfw_appearance WHERE discordid = @d"

local function dbFetchAllAppearances(did)
  if not Config.EnableFiveAppearance then return {} end
  did = tostring(did or "")
  if did == "" then return {} end

  local out = {}
  local drv = dbDriver()

  if drv == "ox" then
    local rows = oxQuery(SQL_AP_FETCH_ALL_OX, { did })
    for i = 1, #(rows or {}) do
      local r = rows[i]
      if r and r.charid ~= nil and type(r.appearance) == "string" and r.appearance ~= "" then
        out[tostring(r.charid)] = r.appearance
        cacheAppearance(did, tostring(r.charid), r.appearance)
      end
    end
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_AP_FETCH_ALL_MY, { ["@d"] = did })
    for i = 1, #(rows or {}) do
      local r = rows[i]
      if r and r.charid ~= nil and type(r.appearance) == "string" and r.appearance ~= "" then
        out[tostring(r.charid)] = r.appearance
        cacheAppearance(did, tostring(r.charid), r.appearance)
      end
    end
  end

  return out
end

local function countPairs(t)
  local c = 0
  for _ in pairs(t or {}) do c = c + 1 end
  return c
end

local function pushAllAppearances(src)
  if not Config.EnableFiveAppearance then return end
  local did = getDiscordID(src)
  if did == "" then return end
  local map = dbFetchAllAppearances(did)
  dprint("appearance bulk push src=%s entries=%d", tostring(src), countPairs(map))
  TriggerClientEvent("azfw:appearance:bulk", src, map or {})
end

RegisterNetEvent("azfw:appearance:bulkRequest", function()
  pushAllAppearances(source)
end)

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:appearance:get", function(source, charid)
    if not Config.EnableFiveAppearance then
      return { ok = true, exists = false }
    end

    local did = getDiscordID(source)
    if did == "" then return { ok = false, err = "no_discord" } end

    charid = tostring(charid or "")
    if charid == "" then return { ok = false, err = "no_charid" } end

    if not verifyCharOwner(did, charid) then
      return { ok = false, err = "not_owner" }
    end

    local ap = dbFetchAppearance(did, charid)
    if ap and type(ap) == "string" and ap ~= "" then
      return { ok = true, exists = true, appearance = ap }
    end
    return { ok = true, exists = false }
  end)
end

local SQL_AP_UPSERT_OX = [[
  INSERT INTO azfw_appearance (discordid, charid, appearance)
  VALUES (?, ?, ?)
  ON DUPLICATE KEY UPDATE appearance = VALUES(appearance)
]]

local SQL_AP_UPSERT_MY = [[
  INSERT INTO azfw_appearance (discordid, charid, appearance)
  VALUES (@d, @c, @a)
  ON DUPLICATE KEY UPDATE appearance = VALUES(appearance)
]]

local function dbSaveAppearance(did, charid, appearanceJson)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return false end
  if type(appearanceJson) ~= "string" or appearanceJson == "" then return false end

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_AP_UPSERT_OX, { did, charid, appearanceJson })
    cacheAppearance(did, charid, appearanceJson)
    return true
  elseif drv == "mysql" then
    myExecute(SQL_AP_UPSERT_MY, { ["@d"] = did, ["@c"] = charid, ["@a"] = appearanceJson })
    cacheAppearance(did, charid, appearanceJson)
    return true
  end
  return false
end

RegisterNetEvent("azfw:appearance:save", function(charid, appearanceJson)
  if not Config.EnableFiveAppearance then return end

  local src = source
  local did = getDiscordID(src)
  if did == "" then return end

  charid = tostring(charid or "")
  if charid == "" then return end

  if not verifyCharOwner(did, charid) then
    dprint("appearance:save denied not_owner src=%s did=%s charid=%s", tostring(src), tostring(did), tostring(charid))
    return
  end

  if type(appearanceJson) ~= "string" or appearanceJson == "" then return end

  local okSaved = dbSaveAppearance(did, charid, appearanceJson)
  dprint("appearance:save ok=%s src=%s charid=%s", tostring(okSaved), tostring(src), tostring(charid))

  if okSaved then
    TriggerClientEvent("azfw:activeAppearance", src, charid, appearanceJson)
    pushAllAppearances(src)
  end
end)

local function _colExists(tbl, col)
  local drv = dbDriver()
  if drv == "none" then return false end

  if drv == "ox" then
    local rows = oxQuery([[
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
      LIMIT 1
    ]], { tbl, col })
    return rows and rows[1] ~= nil
  else
    local rows = myFetchAll([[
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = @t
        AND COLUMN_NAME = @c
      LIMIT 1
    ]], { ["@t"] = tbl, ["@c"] = col })
    return rows and rows[1] ~= nil
  end
end

local function _pkExists(tbl)
  local drv = dbDriver()
  if drv == "none" then return false end

  if drv == "ox" then
    local rows = oxQuery([[
      SELECT 1
      FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND CONSTRAINT_TYPE = 'PRIMARY KEY'
      LIMIT 1
    ]], { tbl })
    return rows and rows[1] ~= nil
  else
    local rows = myFetchAll([[
      SELECT 1
      FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = @t
        AND CONSTRAINT_TYPE = 'PRIMARY KEY'
      LIMIT 1
    ]], { ["@t"] = tbl })
    return rows and rows[1] ~= nil
  end
end

local function ensureLastPosTable()
  if not Config.EnableLastLocation then return end
  local drv = dbDriver()
  if drv == "none" then return end

  local createSql = [[
    CREATE TABLE IF NOT EXISTS `azfw_lastpos` (
      `discordid` varchar(32) NOT NULL,
      `charid` varchar(32) NOT NULL,
      `x` double NOT NULL,
      `y` double NOT NULL,
      `z` double NOT NULL,
      `heading` double NOT NULL DEFAULT 0,
      `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
      PRIMARY KEY (`discordid`,`charid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]

  if drv == "ox" then
    oxExec(createSql)
  else
    myExecute(createSql)
  end

  if not _colExists("azfw_lastpos", "updated_at") then
    local alter = "ALTER TABLE `azfw_lastpos` ADD COLUMN `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()"
    if drv == "ox" then oxExec(alter) else myExecute(alter) end
  end

  if not _pkExists("azfw_lastpos") then
    local alter = "ALTER TABLE `azfw_lastpos` ADD PRIMARY KEY (`discordid`,`charid`)"
    if drv == "ox" then oxExec(alter) else myExecute(alter) end
  end
end

ensureLastPosTable()

local SQL_LASTPOS_UPSERT_OX = [[
  INSERT INTO azfw_lastpos (discordid, charid, x, y, z, heading)
  VALUES (?, ?, ?, ?, ?, ?)
  ON DUPLICATE KEY UPDATE
    x = VALUES(x),
    y = VALUES(y),
    z = VALUES(z),
    heading = VALUES(heading),
    updated_at = CURRENT_TIMESTAMP
]]

local SQL_LASTPOS_UPSERT_MY = [[
  INSERT INTO azfw_lastpos (discordid, charid, x, y, z, heading)
  VALUES (@d, @c, @x, @y, @z, @h)
  ON DUPLICATE KEY UPDATE
    x = VALUES(x),
    y = VALUES(y),
    z = VALUES(z),
    heading = VALUES(heading),
    updated_at = CURRENT_TIMESTAMP
]]

local SQL_LASTPOS_GET_OX = [[
  SELECT x, y, z, heading
  FROM azfw_lastpos
  WHERE discordid = ? AND charid = ?
  LIMIT 1
]]

local SQL_LASTPOS_GET_MY = [[
  SELECT x, y, z, heading
  FROM azfw_lastpos
  WHERE discordid = @d AND charid = @c
  LIMIT 1
]]

local function dbSaveLastPosByChar(did, charid, x, y, z, h)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return end

  x = tonumber(x); y = tonumber(y); z = tonumber(z)
  h = tonumber(h) or 0.0
  if not x or not y or not z then return end

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_LASTPOS_UPSERT_OX, { did, charid, x, y, z, h })
  elseif drv == "mysql" then
    myExecute(SQL_LASTPOS_UPSERT_MY, { ["@d"]=did, ["@c"]=charid, ["@x"]=x, ["@y"]=y, ["@z"]=z, ["@h"]=h })
  end
end

local function dbGetLastPos(did, charid)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return nil end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_LASTPOS_GET_OX, { did, charid })
    local r = rows and rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_LASTPOS_GET_MY, { ["@d"] = did, ["@c"] = charid })
    local r = rows and rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  end

  return nil
end

local function saveLastPosForSource(src, optionalCharId, x, y, z, h, reason)
  if not Config.EnableLastLocation then
    return { ok = false, err = "disabled" }
  end

  local did = getDiscordID(src)
  if did == "" then
    return { ok = false, err = "no_discord" }
  end

  x = tonumber(x); y = tonumber(y); z = tonumber(z)
  h = tonumber(h) or 0.0
  if not x or not y or not z then
    return { ok = false, err = "bad_coords" }
  end

  local charid = getActiveCharIdForSource(src, did, optionalCharId)
  charid = tostring(charid or "")
  if charid == "" then
    return { ok = false, err = "no_charid" }
  end

  dbSaveLastPosByChar(did, charid, x, y, z, h)
  lastLoc[src] = { charid = charid, x = x, y = y, z = z, h = h, at = os.time() }

  dprint("LASTPOS save src=%s did=%s charid=%s reason=%s x=%.2f y=%.2f z=%.2f h=%.1f",
    tostring(src), tostring(did), tostring(charid), tostring(reason or ""),
    x, y, z, h
  )

  return { ok = true, charid = charid }
end

RegisterNetEvent("azfw:lastloc:update", function(clientCharid, x, y, z, heading)
  saveLastPosForSource(source, clientCharid, x, y, z, heading, "event_update")
end)

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:lastloc:get", function(source, charid)
    if not Config.EnableLastLocation then return nil end

    local did = getDiscordID(source)
    if did == "" then return nil end

    charid = tostring(charid or "")
    if charid == "" and fw and fw.GetPlayerCharacter then
      charid = tostring(fw:GetPlayerCharacter(source) or "")
    end
    if charid == "" then return nil end

    if not verifyCharOwner(did, charid) then return nil end

    local v = lastLoc[source]
    if v and v.charid == charid and (os.time() - (v.at or 0)) <= 10 then
      return { x = v.x, y = v.y, z = v.z, h = v.h, at = v.at }
    end

    local dbv = dbGetLastPos(did, charid)
    if not dbv then return nil end

    lastLoc[source] = { charid = charid, x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h, at = os.time() }
    return { x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h, at = os.time() }
  end)
end

hardSaveCachedLastPosForAll = function(reason)
  if not Config.EnableLastLocation then return end

  for _, sid in ipairs(GetPlayers()) do
    local src = tonumber(sid)
    local did = getDiscordID(src)
    local v = lastLoc[src]

    if did ~= "" and v and v.charid and v.x and v.y and v.z then
      dbSaveLastPosByChar(did, v.charid, v.x, v.y, v.z, v.h or 0.0)
      dprint("HARD-SAVE ALL reason=%s src=%s charid=%s", tostring(reason), tostring(src), tostring(v.charid))
    end
  end
end

-- ✅ expose globally too (covers monitor/txAdmin wrappers that call global)
_G.hardSaveCachedLastPosForAll = hardSaveCachedLastPosForAll

local SQL_CHARS_OX = [[
  SELECT
    uc.charid,
    uc.name,
    uc.active_department,
    uc.license_status,
    IFNULL(eum.firstname,'') AS firstname,
    IFNULL(eum.lastname,'')  AS lastname,
    IFNULL(eum.cash, 0)      AS cash,
    IFNULL(eum.bank, 0)      AS bank
  FROM user_characters uc
  LEFT JOIN econ_user_money eum
    ON eum.discordid = uc.discordid AND eum.charid = uc.charid
  WHERE uc.discordid = ?
  ORDER BY uc.id ASC
]]

local SQL_CHARS_MY = [[
  SELECT
    uc.charid,
    uc.name,
    uc.active_department,
    uc.license_status,
    IFNULL(eum.firstname,'') AS firstname,
    IFNULL(eum.lastname,'')  AS lastname,
    IFNULL(eum.cash, 0)      AS cash,
    IFNULL(eum.bank, 0)      AS bank
  FROM user_characters uc
  LEFT JOIN econ_user_money eum
    ON eum.discordid = uc.discordid AND eum.charid = uc.charid
  WHERE uc.discordid = @discordid
  ORDER BY uc.id ASC
]]

-- Housing: basic helpers (DB-only)
local function _vec4ToCoords(v)
  if type(v) ~= "table" then return nil end
  local x = tonumber(v.x or v[1])
  local y = tonumber(v.y or v[2])
  local z = tonumber(v.z or v[3])
  local h = tonumber(v.w or v.h or v[4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z, h = h or 0.0 }
end

local function _anyToCoords(v)
  if type(v) ~= "table" then return nil end
  if v.coords and type(v.coords) == "table" then
    return _anyToCoords(v.coords)
  end
  local x = tonumber(v.x or v[1])
  local y = tonumber(v.y or v[2])
  local z = tonumber(v.z or v[3])
  local h = tonumber(v.w or v.h or v.heading or v[4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z, h = h or 0.0 }
end

local function houseRowToHomeObject(r)
  if type(r) ~= "table" then return nil end
  local nm = r.label
  if nm == nil or nm == "" then nm = r.name end
  return {
    houseId = tonumber(r.id) or nil,
    kind = (r.tenant_identifier and tostring(r.tenant_identifier) ~= "" and "rented" or "owned"),
    name = nm,
    interior = r.interior,
    price = tonumber(r.price) or nil,
    locked = (tonumber(r.locked) == 1)
  }
end

local function resolveHomeSpawnCoords(homeObj)
  if not (Config.Housing and Config.Housing.ShowAsSpawnOption) then return nil end
  if type(homeObj) ~= "table" then return nil end

  local interior = tostring(homeObj.interior or "")
  local byInterior = Config.Housing.SpawnCoordsByInterior or {}
  local c = _vec4ToCoords(byInterior[interior])
  if c then return c end

  return _vec4ToCoords(Config.Housing.FallbackSpawn)
end

local function dbFetchPrimaryHouseByCharId(charid)
  charid = tostring(charid or "")
  if charid == "" then return nil end

  local housesTbl = Config.Housing.Table
  local ownerCol  = Config.Housing.OwnerColumn
  local ownerKey  = "charid:" .. charid

  local drv = dbDriver()
  if drv == "ox" then
    local sql = string.format(
      "SELECT id, name, label, price, interior, locked, `%s` AS owner_identifier FROM `%s` WHERE `%s` = ? ORDER BY id ASC LIMIT 1",
      ownerCol, housesTbl, ownerCol
    )
    local rows = oxQuery(sql, { ownerKey }) or {}
    return rows[1]
  elseif drv == "mysql" then
    local sql = string.format(
      "SELECT id, name, label, price, interior, locked, `%s` AS owner_identifier FROM `%s` WHERE `%s` = @o ORDER BY id ASC LIMIT 1",
      ownerCol, housesTbl, ownerCol
    )
    local rows = myFetchAll(sql, { ["@o"] = ownerKey }) or {}
    return rows[1]
  end

  return nil
end

local function dbFetchHouseDoorCoords(houseId)
  houseId = tonumber(houseId or 0)
  if not houseId or houseId <= 0 then return nil end

  local doorsTbl = Config.Housing.DoorsTable
  local drv = dbDriver()

  if drv == "ox" then
    local sql = string.format(
      "SELECT x, y, z, heading, radius, label FROM `%s` WHERE house_id = ? ORDER BY id ASC LIMIT 1",
      doorsTbl
    )
    local rows = oxQuery(sql, { houseId }) or {}
    local r = rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  elseif drv == "mysql" then
    local sql = string.format(
      "SELECT x, y, z, heading, radius, label FROM `%s` WHERE house_id = @hid ORDER BY id ASC LIMIT 1",
      doorsTbl
    )
    local rows = myFetchAll(sql, { ["@hid"] = houseId }) or {}
    local r = rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  end

  return nil
end

local function tryResolveHouseDoorCoords_DB_ONLY(houseRow)
  if type(houseRow) ~= "table" then return nil end
  local houseId = tonumber(houseRow.id or 0)
  if not houseId or houseId <= 0 then return nil end

  if Config.Housing and type(Config.Housing.DoorCoordsByHouseId) == "table" then
    local mapped = Config.Housing.DoorCoordsByHouseId[houseId]
    local c = _anyToCoords(mapped)
    if c then return c end
  end

  local door = dbFetchHouseDoorCoords(houseId)
  if door and door.x and door.y and door.z then return door end

  local homeObj = houseRowToHomeObject(houseRow)
  local spawn = resolveHomeSpawnCoords(homeObj)
  if spawn then return spawn end

  return nil
end

local function fetchCharactersForSource(src)
  local did = getDiscordID(src)
  if did == "" then return {} end

  local drv = dbDriver()
  local rows = {}

  if drv == "ox" then
    rows = oxQuery(SQL_CHARS_OX, { did }) or {}
  elseif drv == "mysql" then
    rows = myFetchAll(SQL_CHARS_MY, { ["@discordid"] = did }) or {}
  else
    rows = {}
  end

  -- attach home pill info (optional)
  if Config.Housing and Config.Housing.Enabled and Config.Housing.ShowInCharacterUI then
    for _, r in ipairs(rows or {}) do
      local cid = tostring(r.charid or "")
      if cid ~= "" then
        local house = dbFetchPrimaryHouseByCharId(cid)
        if house then
          r.home = houseRowToHomeObject(house)
        end
      end
    end
  end

  return rows or {}
end

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:fetch_characters", function(source)
    return fetchCharactersForSource(source)
  end)
end

RegisterNetEvent("azfw:request_characters", function()
  local src = source
  TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
end)

RegisterNetEvent("azfw:set_active_character", function(charid)
  local src = source
  local did = getDiscordID(src)
  charid = tostring(charid or "")

  if did == "" or charid == "" then return end
  if not verifyCharOwner(did, charid) then
    dprint("set_active_character denied not_owner src=%s did=%s charid=%s", tostring(src), tostring(did), tostring(charid))
    return
  end

  activeCharacters[tostring(src)] = charid
  dprint("activeCharacters[%s]=%s", tostring(src), tostring(charid))

  -- push appearance map so preview is instant
  pushAllAppearances(src)
end)

local function defaultSpawns()
  return {
    {
      id = "legion",
      label = "Legion Square",
      x = 215.76, y = -810.12, z = 30.73, h = 157.0,
      icon = "fa-solid fa-city",
      desc = "Downtown, close to everything."
    },
    {
      id = "airport",
      label = "LSIA Airport",
      x = -1037.74, y = -2738.08, z = 20.17, h = 330.0,
      icon = "fa-solid fa-plane",
      desc = "Arrivals terminal."
    },
    {
      id = "sandy",
      label = "Sandy Shores",
      x = 1850.92, y = 3683.14, z = 34.27, h = 30.0,
      icon = "fa-solid fa-mountain",
      desc = "Out in Blaine County."
    },
    {
      id = "paleto",
      label = "Paleto Bay",
      x = -128.46, y = 6435.16, z = 31.49, h = 45.0,
      icon = "fa-solid fa-tree",
      desc = "Quiet coastal town."
    }
  }
end

local SpawnData = {
  spawns = defaultSpawns(),
  mapBounds = Config.MapBounds
}

local function loadSpawnsFile()
  local raw = LoadResourceFile(RESOURCE_NAME, Config.SpawnFile)
  if not raw or raw == "" then
    dprint("spawns file missing -> writing defaults")
    SaveResourceFile(RESOURCE_NAME, Config.SpawnFile, json.encode(SpawnData, { indent = true }), -1)
    return
  end

  local ok, decoded = pcall(function() return json.decode(raw) end)
  if not ok or type(decoded) ~= "table" then
    iprint("^1spawns.json invalid JSON -> writing defaults^7")
    SaveResourceFile(RESOURCE_NAME, Config.SpawnFile, json.encode(SpawnData, { indent = true }), -1)
    return
  end

  if type(decoded.spawns) == "table" then
    SpawnData.spawns = decoded.spawns
  end
  if type(decoded.mapBounds) == "table" then
    SpawnData.mapBounds = decoded.mapBounds
  else
    SpawnData.mapBounds = Config.MapBounds
  end

  dprint("spawns loaded count=%d", tonumber(#(SpawnData.spawns or {})) or 0)
end

local function saveSpawnsFile(newSpawns)
  SpawnData.spawns = newSpawns or SpawnData.spawns or {}
  SpawnData.mapBounds = SpawnData.mapBounds or Config.MapBounds
  SaveResourceFile(RESOURCE_NAME, Config.SpawnFile, json.encode(SpawnData, { indent = true }), -1)
end

loadSpawnsFile()

local function normalizeSpawnEntry(s)
  if type(s) ~= "table" then return nil end
  local x = tonumber(s.x)
  local y = tonumber(s.y)
  local z = tonumber(s.z)
  local h = tonumber(s.h or s.heading) or 0.0
  if not x or not y or not z then return nil end

  return {
    id = tostring(s.id or ("spawn_" .. math.random(100000, 999999))),
    label = tostring(s.label or s.name or "Spawn"),
    x = x, y = y, z = z, h = h,
    icon = tostring(s.icon or "fa-solid fa-location-dot"),
    desc = tostring(s.desc or s.description or "")
  }
end

local function normalizeSpawnList(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for i = 1, #list do
    local n = normalizeSpawnEntry(list[i])
    if n then out[#out + 1] = n end
  end
  return out
end

local function getLastLocationSpawn(src, did, charid)
  if not Config.EnableLastLocation then return nil end

  local v = lastLoc[src]
  if v and v.charid == charid and v.x and v.y and v.z then
    return {
      id = "lastloc",
      label = "Last Location",
      x = v.x, y = v.y, z = v.z, h = v.h or 0.0,
      icon = "fa-solid fa-location-crosshairs",
      desc = "Continue from where you last were."
    }
  end

  local dbv = dbGetLastPos(did, charid)
  if dbv and dbv.x and dbv.y and dbv.z then
    -- cache it for hard-save
    lastLoc[src] = { charid = charid, x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h or 0.0, at = os.time() }
    return {
      id = "lastloc",
      label = "Last Location",
      x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h or 0.0,
      icon = "fa-solid fa-location-crosshairs",
      desc = "Continue from where you last were."
    }
  end

  return nil
end

local function getHomeSpawnForChar(charid)
  if not (Config.Housing and Config.Housing.Enabled and Config.Housing.ShowAsSpawnOption) then return nil end

  local house = dbFetchPrimaryHouseByCharId(charid)
  if not house then return nil end

  local homeObj = houseRowToHomeObject(house)
  if not homeObj then return nil end

  local coords = tryResolveHouseDoorCoords_DB_ONLY(house)
  if not coords then coords = resolveHomeSpawnCoords(homeObj) end
  if not coords then return nil end

  local locked = (Config.Housing.HomeSpawnLocked == true) and true or false
  return {
    id = "home",
    label = (homeObj.name and homeObj.name ~= "" and ("Home: " .. tostring(homeObj.name)) or "Home"),
    x = coords.x, y = coords.y, z = coords.z, h = coords.h or 0.0,
    icon = "fa-solid fa-house",
    desc = locked and "Home spawn is locked." or "Spawn at your property.",
    locked = locked
  }, homeObj
end

RegisterNetEvent("spawn_selector:requestSpawns", function(optionalCharId)
  local src = source
  local did = getDiscordID(src)
  if did == "" then return end

  local cid = getActiveCharIdForSource(src, did, optionalCharId)
  if cid == "" then
    dprint("requestSpawns: no active charid src=%s", tostring(src))
    TriggerClientEvent("spawn_selector:sendSpawns", src, normalizeSpawnList(SpawnData.spawns), SpawnData.mapBounds or Config.MapBounds, false)
    return
  end

  -- build list:
  local spawns = normalizeSpawnList(SpawnData.spawns)

  -- last location first if available
  local last = getLastLocationSpawn(src, did, cid)
  if last then table.insert(spawns, 1, last) end

  -- home spawn (optional) just below lastloc
  if Config.Housing and Config.Housing.Enabled and Config.Housing.ShowAsSpawnOption then
    local homeSpawn = getHomeSpawnForChar(cid)
    if homeSpawn then
      local insertAt = last and 2 or 1
      table.insert(spawns, insertAt, homeSpawn)
    end
  end

  local admin = computeAndSendAdmin(src, "requestSpawns")
  TriggerClientEvent("spawn_selector:sendSpawns", src, spawns, SpawnData.mapBounds or Config.MapBounds, admin)
end)

RegisterNetEvent("spawn_selector:saveSpawns", function(spawns)
  local src = source
  if not isAdmin(src) then
    dprint("saveSpawns denied src=%s", tostring(src))
    TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "not_admin")
    return
  end

  local normalized = normalizeSpawnList(spawns)
  saveSpawnsFile(normalized)

  dprint("saveSpawns OK src=%s count=%d", tostring(src), #normalized)
  TriggerClientEvent("spawn_selector:spawnsSaved", src, true, nil)

  -- notify everyone (live update)
  TriggerClientEvent("spawn_selector:spawnsUpdated", -1, normalized)
end)

-- optional: command to open spawn selector
RegisterCommand(Config.SpawnMenuCommand or "spawnmenu", function(src)
  src = tonumber(src)
  if not src or src <= 0 then return end
  TriggerClientEvent("spawn_selector:sendSpawns", src, normalizeSpawnList(SpawnData.spawns), SpawnData.mapBounds or Config.MapBounds, computeAndSendAdmin(src, "command"))
end, false)


RegisterNetEvent("azfw:finalSave:done", function(payload)
  local src = source
  payload = payload or {}
  dprint("finalSave:done src=%s payload=%s", tostring(src), type(payload) == "table" and json.encode(payload) or tostring(payload))
end)

local function requestFinalSaveForPlayer(src, reason)
  reason = tostring(reason or "request")
  local payload = {
    reason = reason,
    discordid = getDiscordID(src),
    charid = tostring(activeCharacters[tostring(src)] or "")
  }
  TriggerClientEvent("azfw:finalSave:request", src, payload)
end

AddEventHandler("playerDropped", function()
  local src = source
  local reason = "playerDropped"
  dprint("playerDropped src=%s", tostring(src))

  -- Best effort: hard-save cached lastLoc
  local did = getDiscordID(src)
  local v = lastLoc[src]
  if did ~= "" and v and v.charid and v.x and v.y and v.z then
    dbSaveLastPosByChar(did, v.charid, v.x, v.y, v.z, v.h or 0.0)
    dprint("playerDropped hard-saved lastLoc src=%s charid=%s", tostring(src), tostring(v.charid))
  end

  activeCharacters[tostring(src)] = nil
  prevBuckets[src] = nil
  adminCache[src] = nil
  lastLoc[src] = nil
end)

local function doShutdownSave(reason)
  reason = tostring(reason or "shutdown")
  dprint("doShutdownSave reason=%s", reason)

  -- Ask clients to push their final save (if they still exist)
  for _, sid in ipairs(GetPlayers()) do
    local src = tonumber(sid)
    requestFinalSaveForPlayer(src, reason)
  end

  -- also hard-save server cache immediately (no waiting on clients)
  if type(hardSaveCachedLastPosForAll) == "function" then
    hardSaveCachedLastPosForAll(reason)
  else
    dprint("HARD-SAVE missing (should never happen) reason=%s", tostring(reason))
  end
end

AddEventHandler("onResourceStop", function(res)
  if res ~= RESOURCE_NAME then return end
  doShutdownSave("resourceStop")
end)

-- txAdmin event names differ between versions; we register multiple safely.
local function safeTxHandler(evtName)
  RegisterNetEvent(evtName, function(...)
    dprint("txAdmin event %s fired", evtName)
    doShutdownSave(evtName)
  end)
end

safeTxHandler("txAdmin:events:scheduledRestart")
safeTxHandler("txAdmin:events:serverShuttingDown")
safeTxHandler("txAdmin:events:restart")
safeTxHandler("txAdmin:events:shutdown")


-- If your economy script sends this, it helps keep activeCharacters synced.
RegisterNetEvent("az-fw-money:selectCharacter", function(charid)
  local src = source
  local did = getDiscordID(src)
  charid = tostring(charid or "")
  if did == "" or charid == "" then return end
  if not verifyCharOwner(did, charid) then return end
  activeCharacters[tostring(src)] = charid
  dprint("az-fw-money:selectCharacter src=%s charid=%s", tostring(src), tostring(charid))
end)

iprint("^2server.lua READY^7")
