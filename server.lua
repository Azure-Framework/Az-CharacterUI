local DEBUG = true
local activeCharacters = {}
Config = Config or {}
local json = json

Config.EnableLastLocation = (Config.EnableLastLocation ~= false)
Config.LastLocationUpdateIntervalMs = tonumber(Config.LastLocationUpdateIntervalMs) or 10000

Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)

local function debugPrint(fmt, ...)
    if not DEBUG then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        print("[azfw DEBUG] (format error)")
        print(...)
        return
    end
    print("[azfw DEBUG] " .. msg)
end

local function safeEncode(obj)
    if not obj then return "<nil>" end
    if type(obj) == "string" or type(obj) == "number" then return tostring(obj) end
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

local function parseAffected(affected)
    if type(affected) == "number" then return affected end
    if type(affected) == "string" then
        local n = tonumber(affected)
        if n then return n end
    end
    if type(affected) == "table" then
        local keys = {"affectedRows","affected","rowsAffected","changedRows","affected_rows","affected_rows_count"}
        for _, k in ipairs(keys) do
            if affected[k] ~= nil then
                local n = tonumber(affected[k])
                if n then return n end
            end
        end
        if next(affected) ~= nil then return 1 end
    end
    return nil
end




local function getDiscordID(src)
    local ids = GetPlayerIdentifiers(src) or {}
    debugPrint("getDiscordID src=%s ids=%s", tostring(src), safeEncode(ids))
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




local function fetchCharactersForSource(src)
    local discordID = getDiscordID(src)
    if discordID == "" then return {} end

    local sql = [[
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
    ]]

    if MySQL and MySQL.Sync and type(MySQL.Sync.fetchAll) == "function" then
        local ok, rowsOrErr = pcall(function()
            return MySQL.Sync.fetchAll(sql, {discordID})
        end)
        if not ok then
            debugPrint("fetchCharactersForSource MySQL.Sync.fetchAll failed: %s", tostring(rowsOrErr))
            return {}
        end
        return rowsOrErr or {}
    end

    if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
        local done, result = false, {}
        local ok, err = pcall(function()
            exports.oxmysql:query(sql, {discordID}, function(rows)
                result = rows or {}
                done = true
            end)
        end)
        if not ok then
            debugPrint("fetchCharactersForSource oxmysql query failed: %s", tostring(err))
            return {}
        end
        local ticks = 0
        while not done and ticks < 6000 do Citizen.Wait(1); ticks = ticks + 1 end
        return result or {}
    end

    return {}
end

if lib and lib.callback and type(lib.callback.register) == "function" then
    lib.callback.register("azfw:fetch_characters", function(source, _)
        return fetchCharactersForSource(source)
    end)
end

RegisterNetEvent("azfw_fetch_characters", function()
    local src = source
    TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
end)

RegisterNetEvent("azfw:request_characters", function()
    local src = source
    TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
end)




RegisterNetEvent("azfw_register_character", function(firstName, lastName, dept, license)
    local src = source
    local discordID = getDiscordID(src)
    if discordID == "" then
        TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Could not register character: no Discord ID found."}})
        return
    end

    local charID = tostring(os.time()) .. tostring(math.random(1000, 9999))
    local fullName = tostring(firstName or "") .. (lastName and (" " .. tostring(lastName)) or "")
    local active_department = tostring(dept or "")
    local license_status = tostring(license or "UNKNOWN")
    local startingCash = tonumber(Config and Config.StartingCash) or 0

    if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
        MySQL.Async.execute([[
            INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
            VALUES (@discordid, @charid, @name, @active_department, @license_status)
        ]], {
            ["@discordid"]=discordID,
            ["@charid"]=charID,
            ["@name"]=fullName,
            ["@active_department"]=active_department,
            ["@license_status"]=license_status
        }, function(affected)
            local num = parseAffected(affected)
            if not num or num < 1 then
                TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Failed to register character. Check server logs."}})
                return
            end
            MySQL.Async.execute([[
                INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
                VALUES (@discordid, @charid, @firstname, @lastname, @cash, @bank, 0, 'active')
            ]], {
                ["@discordid"]=discordID,
                ["@charid"]=charID,
                ["@firstname"]=firstName or "",
                ["@lastname"]=lastName or "",
                ["@cash"]=startingCash,
                ["@bank"]=0
            }, function(_)
                activeCharacters[tostring(src)] = charID
                TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
                TriggerClientEvent("chat:addMessage", src, {args={"^2SYSTEM", ('Character "%s" registered (ID %s).'):format(fullName, charID)}})
            end)
        end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
        exports.oxmysql:execute([[
            INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
            VALUES (?, ?, ?, ?, ?)
        ]], {discordID, charID, fullName, active_department, license_status}, function(affected)
            local num = parseAffected(affected)
            if not num or num < 1 then
                TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Failed to register character. Check server logs."}})
                return
            end
            exports.oxmysql:execute([[
                INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
                VALUES (?, ?, ?, ?, ?, ?, 0, 'active')
            ]], {discordID, charID, firstName or "", lastName or "", startingCash, 0}, function(_)
                activeCharacters[tostring(src)] = charID
                TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
                TriggerClientEvent("chat:addMessage", src, {args={"^2SYSTEM", ('Character "%s" registered (ID %s).'):format(fullName, charID)}})
            end)
        end)
        return
    end
end)

RegisterNetEvent("azfw_delete_character", function(charid)
    local src = source
    local discordID = getDiscordID(src)
    if not charid or discordID == "" then
        TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Invalid delete request."}})
        return
    end

    if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
        MySQL.Async.execute([[
            DELETE FROM user_characters WHERE discordid = @discordid AND charid = @charid
        ]], {["@discordid"]=discordID, ["@charid"]=charid}, function(affected)
            local num = parseAffected(affected)
            if num and num > 0 then
                TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
                TriggerClientEvent("chat:addMessage", src, {args={"^2SYSTEM","Character deleted."}})
                if activeCharacters[tostring(src)] == charid then activeCharacters[tostring(src)] = nil end
            else
                TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Failed to delete character."}})
            end
        end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
        exports.oxmysql:execute([[
            DELETE FROM user_characters WHERE discordid = ? AND charid = ?
        ]], {discordID, charid}, function(affected)
            local num = parseAffected(affected)
            if num and num > 0 then
                TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
                TriggerClientEvent("chat:addMessage", src, {args={"^2SYSTEM","Character deleted."}})
                if activeCharacters[tostring(src)] == charid then activeCharacters[tostring(src)] = nil end
            else
                TriggerClientEvent("chat:addMessage", src, {args={"^1SYSTEM","Failed to delete character."}})
            end
        end)
    end
end)

local function handleSelectCharacter(src, charID)
    if not src then return end
    local did = getDiscordID(src)
    if not did or did == "" then return end

    if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
        exports.oxmysql:query("SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {did, charID}, function(rows)
            if rows and #rows > 0 then
                activeCharacters[tostring(src)] = charID
                TriggerClientEvent("az-fw-money:characterSelected", src, charID)
            end
        end)
        return
    end

    if MySQL and MySQL.Sync and type(MySQL.Sync.fetchAll) == "function" then
        local ok, rows = pcall(function()
            return MySQL.Sync.fetchAll("SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {did, charID})
        end)
        if ok and rows and #rows > 0 then
            activeCharacters[tostring(src)] = charID
            TriggerClientEvent("az-fw-money:characterSelected", src, charID)
        end
    end
end

RegisterNetEvent("az-fw-money:selectCharacter", function(charID)
    handleSelectCharacter(source, charID)
end)

RegisterNetEvent("azfw:set_active_character", function(charid)
    handleSelectCharacter(source, charid)
end)

AddEventHandler("playerDropped", function(reason)
    debugPrint("playerDropped src=%s reason=%s", tostring(source), tostring(reason))
    activeCharacters[tostring(source)] = nil
end)




local lastPosCache = {} 

local function lpKey(did, charid)
    return tostring(did) .. "|" .. tostring(charid)
end

local function cacheLastPos(did, charid, x,y,z,h)
    lastPosCache[lpKey(did, charid)] = {
        x = tonumber(x) or 0.0,
        y = tonumber(y) or 0.0,
        z = tonumber(z) or 0.0,
        h = tonumber(h) or 0.0,
        updated = os.time()
    }
end

local function getCachedLastPos(did, charid)
    return lastPosCache[lpKey(did, charid)]
end

local function dbUpsertLastPos(did, charid, x,y,z,h)
    if not Config.EnableLastLocation then return end

    x = tonumber(x) or 0.0
    y = tonumber(y) or 0.0
    z = tonumber(z) or 0.0
    h = tonumber(h) or 0.0

    if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
        MySQL.Async.execute([[
            INSERT INTO azfw_lastpos (discordid, charid, x, y, z, heading)
            VALUES (@d, @c, @x, @y, @z, @h)
            ON DUPLICATE KEY UPDATE x=@x, y=@y, z=@z, heading=@h, updated_at=CURRENT_TIMESTAMP
        ]], {
            ["@d"]=did, ["@c"]=charid,
            ["@x"]=x, ["@y"]=y, ["@z"]=z, ["@h"]=h
        }, function(_) end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
        exports.oxmysql:execute([[
            INSERT INTO azfw_lastpos (discordid, charid, x, y, z, heading)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE x=VALUES(x), y=VALUES(y), z=VALUES(z), heading=VALUES(heading), updated_at=CURRENT_TIMESTAMP
        ]], {did, charid, x, y, z, h}, function(_) end)
    end
end

local function dbFetchLastPos(did, charid, cb)
    if not Config.EnableLastLocation then cb(nil); return end

    local c = getCachedLastPos(did, charid)
    if c then cb(c); return end

    if MySQL and MySQL.Async and type(MySQL.Async.fetchAll) == "function" then
        MySQL.Async.fetchAll([[
            SELECT x,y,z,heading FROM azfw_lastpos
            WHERE discordid=@d AND charid=@c
            LIMIT 1
        ]], {["@d"]=did, ["@c"]=charid}, function(rows)
            if rows and rows[1] then
                cacheLastPos(did, charid, rows[1].x, rows[1].y, rows[1].z, rows[1].heading)
                cb(getCachedLastPos(did, charid))
            else
                cb(nil)
            end
        end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
        exports.oxmysql:query([[
            SELECT x,y,z,heading FROM azfw_lastpos
            WHERE discordid = ? AND charid = ?
            LIMIT 1
        ]], {did, charid}, function(rows)
            if rows and rows[1] then
                cacheLastPos(did, charid, rows[1].x, rows[1].y, rows[1].z, rows[1].heading)
                cb(getCachedLastPos(did, charid))
            else
                cb(nil)
            end
        end)
        return
    end

    cb(nil)
end

RegisterNetEvent("azfw:lastpos:update", function(charid, pos)
    local src = source
    if not Config.EnableLastLocation then return end
    if not charid or type(pos) ~= "table" then return end

    local did = getDiscordID(src)
    if did == "" then return end

    local active = activeCharacters[tostring(src)]
    if not active or tostring(active) ~= tostring(charid) then
        debugPrint("lastpos update denied src=%s expectedActive=%s got=%s", tostring(src), tostring(active), tostring(charid))
        return
    end

    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z)
    local h = tonumber(pos.h)

    if not x or not y or not z then return end
    h = h or 0.0

    cacheLastPos(did, charid, x,y,z,h)
    dbUpsertLastPos(did, charid, x,y,z,h)
end)




local appearanceCache = {} 

local function apKey(did, charid)
    return tostring(did) .. "|" .. tostring(charid)
end

local function cacheAppearance(did, charid, appearanceJson)
    appearanceCache[apKey(did, charid)] = {
        appearance = appearanceJson,
        updated = os.time()
    }
end

local function getCachedAppearance(did, charid)
    local v = appearanceCache[apKey(did, charid)]
    return v and v.appearance or nil
end

local function dbUpsertAppearance(did, charid, appearanceJson)
    if not Config.EnableFiveAppearance then return end
    if type(appearanceJson) ~= "string" or appearanceJson == "" then return end

    cacheAppearance(did, charid, appearanceJson)

    if MySQL and MySQL.Async and type(MySQL.Async.execute) == "function" then
        MySQL.Async.execute([[
            INSERT INTO azfw_appearance (discordid, charid, appearance)
            VALUES (@d, @c, @a)
            ON DUPLICATE KEY UPDATE appearance=@a, updated_at=CURRENT_TIMESTAMP
        ]], {["@d"]=did, ["@c"]=charid, ["@a"]=appearanceJson}, function(_) end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.execute) == "function" then
        exports.oxmysql:execute([[
            INSERT INTO azfw_appearance (discordid, charid, appearance)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE appearance=VALUES(appearance), updated_at=CURRENT_TIMESTAMP
        ]], {did, charid, appearanceJson}, function(_) end)
    end
end

local function dbFetchAppearance(did, charid, cb)
    if not Config.EnableFiveAppearance then cb(nil); return end

    local cached = getCachedAppearance(did, charid)
    if cached then cb(cached); return end

    if MySQL and MySQL.Async and type(MySQL.Async.fetchAll) == "function" then
        MySQL.Async.fetchAll([[
            SELECT appearance FROM azfw_appearance
            WHERE discordid=@d AND charid=@c
            LIMIT 1
        ]], {["@d"]=did, ["@c"]=charid}, function(rows)
            if rows and rows[1] and rows[1].appearance then
                cacheAppearance(did, charid, rows[1].appearance)
                cb(rows[1].appearance)
            else
                cb(nil)
            end
        end)
        return
    end

    if exports and exports.oxmysql and type(exports.oxmysql.query) == "function" then
        exports.oxmysql:query([[
            SELECT appearance FROM azfw_appearance
            WHERE discordid = ? AND charid = ?
            LIMIT 1
        ]], {did, charid}, function(rows)
            if rows and rows[1] and rows[1].appearance then
                cacheAppearance(did, charid, rows[1].appearance)
                cb(rows[1].appearance)
            else
                cb(nil)
            end
        end)
        return
    end

    cb(nil)
end


RegisterNetEvent("azfw:appearance:save", function(charid, appearanceJson)
    local src = source
    if not Config.EnableFiveAppearance then return end
    if not charid then return end
    if type(appearanceJson) ~= "string" or appearanceJson == "" then return end

    local did = getDiscordID(src)
    if did == "" then return end

    
    local active = activeCharacters[tostring(src)]
    if not active or tostring(active) ~= tostring(charid) then
        debugPrint("appearance save denied src=%s expectedActive=%s got=%s", tostring(src), tostring(active), tostring(charid))
        return
    end

    dbUpsertAppearance(did, charid, appearanceJson)
end)


if lib and lib.callback and type(lib.callback.register) == "function" then
    lib.callback.register("azfw:appearance:get", function(source, charid)
        local src = source
        if not Config.EnableFiveAppearance then return nil end
        if not charid then return nil end

        local did = getDiscordID(src)
        if did == "" then return nil end

        local p = promise.new()
        dbFetchAppearance(did, tostring(charid), function(a)
            p:resolve(a)
        end)
        return Citizen.Await(p)
    end)
end




local function safeGetResourceName()
    local ok, name = pcall(GetCurrentResourceName)
    if not ok or type(name) ~= "string" or name == "" then
        print("^1[spawn_selector]^7 GetCurrentResourceName invalid")
        return nil
    end
    return name
end

local function loadSpawns()
    if type(Config) ~= "table" or type(Config.SpawnFile) ~= "string" then
        print("^1[spawn_selector]^7 Config.SpawnFile missing; using []")
        return {}
    end

    local resource = safeGetResourceName()
    if not resource then return {} end

    local raw = nil
    local ok, err = pcall(function()
        raw = LoadResourceFile(resource, Config.SpawnFile)
    end)
    if not ok then
        print(("^1[spawn_selector]^7 LoadResourceFile error %s/%s: %s"):format(resource, Config.SpawnFile, tostring(err)))
        return {}
    end
    if not raw then
        pcall(function() SaveResourceFile(resource, Config.SpawnFile, "[]", -1) end)
        return {}
    end

    local ok2, decoded = pcall(json.decode, raw)
    if not ok2 or type(decoded) ~= "table" then
        print(("^1[spawn_selector]^7 bad json in %s"):format(Config.SpawnFile))
        return {}
    end
    return decoded
end

local function saveSpawns(tbl)
    if type(tbl) ~= "table" then return false, "invalid_table" end
    if type(Config) ~= "table" or type(Config.SpawnFile) ~= "string" then return false, "bad_config" end
    local resource = safeGetResourceName()
    if not resource then return false, "no_resource_name" end

    local ok, encoded = pcall(json.encode, tbl)
    if not ok or type(encoded) ~= "string" then return false, "encode_failed" end

    local saved = pcall(function()
        SaveResourceFile(resource, Config.SpawnFile, encoded, -1)
    end)
    if not saved then return false, "save_failed" end
    return true
end


local function _azfw_getActiveCharacter(src)
    return activeCharacters[tostring(src)]
end
exports("getActiveCharacter", _azfw_getActiveCharacter)

RegisterServerEvent("spawn_selector:requestSpawns")
AddEventHandler("spawn_selector:requestSpawns", function()
    local src = source
    local spawns = loadSpawns() or {}
    local bounds = Config.MapBounds or {}

    
    if Config.EnableLastLocation then
        local did = getDiscordID(src)
        local charid = _azfw_getActiveCharacter(src)

        if did ~= "" and charid then
            dbFetchLastPos(did, charid, function(lp)
                local out = spawns

                if lp and lp.x and lp.y and lp.z then
                    local lastSpawn = {
                        id = "azfw_last_location",
                        name = "Last Location",
                        description = "Spawn where you last logged out.",
                        locked = true, 
                        spawn = { coords = { x = lp.x, y = lp.y, z = lp.z }, heading = lp.h or 0.0 },
                        coords = { x = lp.x, y = lp.y, z = lp.z },
                        heading = lp.h or 0.0,
                        pin = { x = lp.x, y = lp.y }
                    }
                    out = { lastSpawn }
                    for i=1, #spawns do out[#out+1] = spawns[i] end
                end

                TriggerClientEvent("spawn_selector:sendSpawns", src, out, bounds)
            end)
            return
        end
    end

    TriggerClientEvent("spawn_selector:sendSpawns", src, spawns, bounds)
end)

RegisterServerEvent("spawn_selector:checkAdmin")
AddEventHandler("spawn_selector:checkAdmin", function()
    local src = source
    if Config.RequireAzAdminForEdit and exports["Az-Framework"] and exports["Az-Framework"].isAdmin then
        exports["Az-Framework"]:isAdmin(src, function(isAdmin)
            TriggerClientEvent("spawn_selector:adminCheckResult", src, isAdmin and true or false)
        end)
    else
        TriggerClientEvent("spawn_selector:adminCheckResult", src, false)
    end
end)

RegisterServerEvent("spawn_selector:saveSpawns")
AddEventHandler("spawn_selector:saveSpawns", function(spawns)
    local src = source
    if type(spawns) ~= "table" then
        TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "invalid_payload")
        return
    end

    
    local filtered = {}
    for _, s in ipairs(spawns) do
        if type(s) == "table" and not s.locked and s.id ~= "azfw_last_location" then
            filtered[#filtered+1] = s
        end
    end

    if Config.RequireAzAdminForEdit and exports["Az-Framework"] and exports["Az-Framework"].isAdmin then
        exports["Az-Framework"]:isAdmin(src, function(isAdmin)
            if not isAdmin then
                TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "not_admin")
                return
            end
            local ok, err = saveSpawns(filtered)
            if not ok then
                TriggerClientEvent("spawn_selector:spawnsSaved", src, false, err or "save_failed")
                return
            end
            TriggerClientEvent("spawn_selector:spawnsSaved", src, true)
            TriggerClientEvent("spawn_selector:spawnsUpdated", -1, filtered)
        end)
    else
        if not Config.RequireAzAdminForEdit then
            local ok, err = saveSpawns(filtered)
            if not ok then
                TriggerClientEvent("spawn_selector:spawnsSaved", src, false, err or "save_failed")
                return
            end
            TriggerClientEvent("spawn_selector:spawnsSaved", src, true)
            TriggerClientEvent("spawn_selector:spawnsUpdated", -1, filtered)
        else
            TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "no_export")
        end
    end
end)

debugPrint("server.lua loaded. DEBUG=%s EnableLastLocation=%s EnableFiveAppearance=%s",
    tostring(DEBUG), tostring(Config.EnableLastLocation), tostring(Config.EnableFiveAppearance))
