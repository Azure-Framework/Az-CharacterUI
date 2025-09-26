local firstSpawn = true
local nuiOpen = false
local spawnNuiOpen = false
local nuiOwner = nil
local RESOURCE_NAME = GetCurrentResourceName()

local cachedChars = {}

local function sendNUI(msg)
    SendNUIMessage(msg)
end

local function setNuiFocusOwner(owner)
    if owner then
        nuiOwner = owner
        SetNuiFocus(true, true)
    else
        nuiOwner = nil
        SetNuiFocus(false, false)
    end
end

local function cameraPanIntoPlayer(durationMs)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return
    end
    local px, py, pz = table.unpack(GetEntityCoords(ped, true))
    local headZ = pz + 0.9
    local startX, startY, startZ = px, py - 80.0, headZ + 28.0
    local endX, endY, endZ = px, py, headZ + 1.6
    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(cam, startX, startY, startZ)
    PointCamAtCoord(cam, px, py, headZ)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    DoScreenFadeOut(120)
    Wait(140)
    DoScreenFadeIn(400)
    local steps = math.max(30, math.floor(durationMs / 16))
    for i = 1, steps do
        local t = i / steps
        local tt = t * t * (3 - 2 * t)
        local cx = startX + (endX - startX) * tt
        local cy = startY + (endY - startY) * tt
        local cz = startZ + (endZ - startZ) * tt
        SetCamCoord(cam, cx, cy, cz)
        PointCamAtCoord(cam, px, py, headZ)
        Wait(16)
    end
    Wait(300)
    RenderScriptCams(false, false, 500, true, true)
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
end

local function openAzfwUI(initialChars)
    if nuiOpen then
        return
    end

    if nuiOwner == "spawn" or spawnNuiOpen then
        print("[azfw client] openAzfwUI aborted: spawn UI already owns focus")
        return
    end

    nuiOpen = true

    print(("[azfw client] openAzfwUI called. initialChars=%s"):format(tostring((initialChars and #initialChars) or 0)))

    if type(initialChars) == "table" and #initialChars > 0 then
        cachedChars = initialChars
    end

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    setNuiFocusOwner("azfw")

    Citizen.SetTimeout(
        200,
        function()
            SendNUIMessage({type = "azfw_set_resource", resource = RESOURCE_NAME})

            local charsToSend = nil
            if type(cachedChars) == "table" and #cachedChars > 0 then
                charsToSend = cachedChars
            elseif type(initialChars) == "table" and #initialChars > 0 then
                charsToSend = initialChars
            else
                if lib and lib.callback and lib.callback.await then
                    local ok, result =
                        pcall(
                        function()
                            return lib.callback.await("azfw:fetch_characters", 5000)
                        end
                    )
                    if ok and type(result) == "table" and #result > 0 then
                        charsToSend = result
                        cachedChars = result
                    end
                end
            end

            SendNUIMessage({type = "azfw_open_ui", chars = charsToSend or {}})

            Citizen.SetTimeout(
                600,
                function()
                    if (not cachedChars) or (type(cachedChars) ~= "table") or (#cachedChars == 0) then
                        TriggerServerEvent("azfw_fetch_characters")
                    else
                        if nuiOpen then
                            SendNUIMessage({type = "azfw_update_chars", chars = cachedChars})
                        end
                    end
                end
            )
        end
    )
end

local function closeAzfwUI()
    if not nuiOpen then
        return
    end
    nuiOpen = false

    print("[azfw client] closeAzfwUI called")

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)

    if nuiOwner == "azfw" then
        setNuiFocusOwner(nil)
    else
        print("[azfw client] closeAzfwUI: did not clear focus because owner=" .. tostring(nuiOwner))
    end

    SendNUIMessage({type = "azfw_close_ui"})
end

RegisterNUICallback(
    "azfw_select_character",
    function(data, cb)
        cb({ok = true})
        local charid = data and data.charid
        if not charid then
            print("azfw: select_character missing charid")
            return
        end
        TriggerServerEvent("az-fw-money:selectCharacter", charid)
    end
)

RegisterNUICallback(
    "azfw_create_character",
    function(data, cb)
        cb({ok = true})
        local first = data and data.first or ""
        local last = data and data.last or ""
        if first == "" then
            return
        end
        TriggerServerEvent("azfw_register_character", first, last)
    end
)

RegisterNUICallback(
    "azfw_delete_character",
    function(data, cb)
        cb({ok = true})
        local charid = data and data.charid
        if not charid then
            return
        end
        TriggerServerEvent("azfw_delete_character", charid)
    end
)

RegisterNUICallback(
    "azfw_close_ui",
    function(data, cb)
        cb({ok = true})
        closeAzfwUI()
    end
)

RegisterNetEvent(
    "azfw:characters_updated",
    function(chars)
        cachedChars = chars or {}
        if nuiOpen then
            SendNUIMessage({type = "azfw_update_chars", chars = cachedChars})
        end
    end
)

RegisterNetEvent(
    "az-fw-money:characterSelected",
    function(charid)
        Citizen.CreateThread(
            function()
                closeAzfwUI()
                Wait(80)
                cameraPanIntoPlayer(2200)
            end
        )
    end
)

RegisterNetEvent(
    "azfw:character_confirmed",
    function(charid)
        print(("[azfw client] character_confirmed -> %s"):format(tostring(charid)))
    end
)

RegisterNetEvent(
    "azfw:open_ui",
    function(chars)
        if type(chars) == "table" and #chars > 0 then
            cachedChars = chars
        end
        openAzfwUI(chars)
    end
)

AddEventHandler(
    "playerSpawned",
    function()
        if firstSpawn then
            firstSpawn = false
            Citizen.SetTimeout(
                700,
                function()
                    openAzfwUI()
                end
            )
        end
    end
)

local function toggleAzfwUI()
    if nuiOpen then
        closeAzfwUI()
    else
        openAzfwUI()
    end
end

local Keys = {
    ["F1"] = 288,
    ["F2"] = 289,
    ["F3"] = 170,
    ["F5"] = 166,
    ["F6"] = 167,
    ["F7"] = 168,
    ["F9"] = 56,
    ["F10"] = 57,
    ["~"] = 243,
    ["1"] = 157,
    ["2"] = 158,
    ["3"] = 160,
    ["4"] = 164,
    ["5"] = 165,
    ["6"] = 159,
    ["7"] = 161,
    ["8"] = 162,
    ["9"] = 163,
    ["K"] = 311,
    ["G"] = 47,
    ["H"] = 74,
    ["HOME"] = 213,
    ["INSERT"] = 121
}

Citizen.CreateThread(
    function()
        Wait(200)
        print(
            ("^2[azfw] loaded. resource=%s, Config.UIKeybind=%s^7"):format(
                tostring(RESOURCE_NAME),
                tostring(Config and Config.UIKeybind)
            )
        )
    end
)

RegisterCommand(
    "charmenu",
    function()
        print("[azfw] /charmenu command fired")
        toggleAzfwUI()
    end,
    false
)

if type(Config) == "table" and type(Config.UIKeybind) == "string" then
    local ok, err =
        pcall(
        function()
            RegisterKeyMapping("charmenu", "Open Character Menu", "keyboard", Config.UIKeybind)
        end
    )
    if ok then
        print(('[azfw] RegisterKeyMapping set to "%s" (string)'):format(Config.UIKeybind))
    else
        print(("[azfw] RegisterKeyMapping failed: %s"):format(tostring(err)))
    end
end

Citizen.CreateThread(
    function()
        while true do
            Citizen.Wait(0)

            if type(Config) == "table" and type(Config.UIKeybind) == "number" then
                if IsControlJustReleased(0, Config.UIKeybind) then
                    print(("[azfw] numeric keybind (%s) pressed"):format(tostring(Config.UIKeybind)))
                    toggleAzfwUI()
                end
            end

            if type(Config) == "table" and type(Config.UIKeybind) == "string" then
                local mapped = Keys[Config.UIKeybind] or Keys[string.upper(Config.UIKeybind)]
                if mapped then
                    if IsControlJustReleased(0, mapped) then
                        print(
                            ('[azfw] fallback detected key press for "%s" (mapped to %s)'):format(
                                tostring(Config.UIKeybind),
                                tostring(mapped)
                            )
                        )
                        toggleAzfwUI()
                    end
                end
            end

            if nuiOpen and IsControlJustReleased(0, 200) then
                print("[azfw] ESC pressed - closing UI")
                closeAzfwUI()
            end
        end
    end
)

Citizen.CreateThread(
    function()
        Wait(3000)
        if RegisterCommand then
            pcall(
                function()
                    TriggerEvent("chat:addSuggestion", "/charmenu", "Open the character selection menu")
                end
            )
        end
    end
)

print(("^2[azfw client] loaded. Resource name: %s^7"):format(RESOURCE_NAME))

local RESOURCE = GetCurrentResourceName()

RegisterCommand(
    "spawnsel",
    function()
        TriggerServerEvent("spawn_selector:requestSpawns")
    end,
    false
)

RegisterNetEvent("spawn_selector:sendSpawns")
AddEventHandler(
    "spawn_selector:sendSpawns",
    function(spawns, mapBounds)
        if not nuiOpen and nuiOwner ~= "azfw" then
            spawnNuiOpen = true
            setNuiFocusOwner("spawn")
        else
            print("[azfw] spawn_selector: not taking NUI focus because azfw UI is open")
        end

        SendNUIMessage(
            {
                type = "spawn_data",
                spawns = spawns or {},
                mapBounds = mapBounds or {},
                resourceName = RESOURCE
            }
        )
    end
)

RegisterNetEvent("spawn_selector:spawnsUpdated")
AddEventHandler(
    "spawn_selector:spawnsUpdated",
    function(spawns)
        SendNUIMessage({type = "spawn_update", spawns = spawns or {}})
    end
)

RegisterNetEvent("spawn_selector:spawnsSaved")
AddEventHandler(
    "spawn_selector:spawnsSaved",
    function(ok, err)
        SendNUIMessage({type = "saveResult", ok = ok and true or false, err = err or nil})
    end
)

RegisterNetEvent("spawn_selector:adminCheckResult")
AddEventHandler(
    "spawn_selector:adminCheckResult",
    function(isAdmin)
        SendNUIMessage({type = "adminCheckResult", isAdmin = isAdmin and true or false})
    end
)

RegisterNUICallback(
    "request_spawns",
    function(data, cb)
        TriggerServerEvent("spawn_selector:requestSpawns")
        cb("ok")
    end
)

RegisterNUICallback(
    "getResourceName",
    function(_, cb)
        cb({resource = RESOURCE})
    end
)

RegisterNUICallback(
    "closeSpawnMenu",
    function(_, cb)
        cb("ok")
        if spawnNuiOpen then
            if nuiOwner == "spawn" then
                setNuiFocusOwner(nil)
            end
            spawnNuiOpen = false
        else
        end
    end
)

RegisterNUICallback(
    "selectSpawn",
    function(data, cb)
        cb("ok")
        if type(data) == "table" and data.spawn and data.spawn.coords then
            local spawn = data.spawn
            local ped = PlayerPedId()
            DoScreenFadeOut(300)
            while not IsScreenFadedOut() do
                Citizen.Wait(0)
            end
            SetEntityCoords(ped, spawn.coords.x, spawn.coords.y, spawn.coords.z, false, false, false, true)
            SetEntityHeading(ped, spawn.heading or 0.0)
            Citizen.Wait(250)
            DoScreenFadeIn(300)
            return
        end
    end
)

RegisterNUICallback(
    "request_edit_permission",
    function(_, cb)
        local responded = false
        local function tmpHandler(isAdmin)
            if responded then
                return
            end
            responded = true
            cb({isAdmin = isAdmin and true or false})
            RemoveEventHandler("spawn_selector:adminCheckResult", tmpHandler)
        end
        RegisterNetEvent("spawn_selector:adminCheckResult")
        AddEventHandler("spawn_selector:adminCheckResult", tmpHandler)
        TriggerServerEvent("spawn_selector:checkAdmin")
        Citizen.SetTimeout(
            3000,
            function()
                if not responded then
                    responded = true
                    cb({isAdmin = false})
                    RemoveEventHandler("spawn_selector:adminCheckResult", tmpHandler)
                end
            end
        )
    end
)

RegisterNUICallback(
    "saveSpawns",
    function(data, cb)
        cb("ok")
        if type(data) == "table" and type(data.spawns) == "table" then
            TriggerServerEvent("spawn_selector:saveSpawns", data.spawns)
        end
    end
)

RegisterNUICallback(
    "request_player_coords",
    function(_, cb)
        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then
            cb({})
            return
        end
        local x, y, z = table.unpack(GetEntityCoords(ped, true))
        local h = GetEntityHeading(ped)
        cb({x = tonumber(x), y = tonumber(y), z = tonumber(z), h = tonumber(h)})
    end
)

RegisterCommand(
    "azfw_debug_focus",
    function()
        print(
            ("azfw debug: nuiOpen=%s spawnNuiOpen=%s nuiOwner=%s"):format(
                tostring(nuiOpen),
                tostring(spawnNuiOpen),
                tostring(nuiOwner)
            )
        )
    end,
    false
)

local pending_admin_cb = nil
local pending_timeout_id = nil

RegisterNetEvent("spawn_selector:adminCheckResult")
AddEventHandler(
    "spawn_selector:adminCheckResult",
    function(isAdmin)
        if pending_admin_cb then
            local cb = pending_admin_cb
            pending_admin_cb = nil

            if pending_timeout_id then
                ClearTimeout(pending_timeout_id)
                pending_timeout_id = nil
            end
            cb({isAdmin = (isAdmin and true or false)})
        end
    end
)

RegisterNUICallback(
    "request_edit_permission",
    function(data, cb)
        if pending_admin_cb then
            cb({isAdmin = false})
            return
        end

        pending_admin_cb = cb

        TriggerServerEvent("spawn_selector:checkAdmin")

        pending_timeout_id = SetTimeout or Citizen.SetTimeout
        if pending_timeout_id then
            pending_timeout_id =
                SetTimeout(
                3000,
                function()
                    if pending_admin_cb then
                        pending_admin_cb({isAdmin = false})
                        pending_admin_cb = nil
                    end
                    pending_timeout_id = nil
                end
            )
        end
    end
)
