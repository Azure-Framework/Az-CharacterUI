\\local json = json -- FiveM JSON helper (same as your other client)

local RESOURCE_NAME = GetCurrentResourceName()

local Config = {
    UseAppearance = true,               -- master toggle
    Price = 250,                        -- cost per clothing session
    Key = 38,                           -- E
    InteractDistance = 2.0,
    MarkerDistance = 25.0,
    MarkerType = 1,
    MarkerScale = vector3(1.0, 1.0, 1.0),
    MarkerColor = { r = 0, g = 150, b = 255, a = 180 },
    TextZOffset = 1.0,

    Blips = {
        Enabled = true,
        Sprite = 73,   -- clothing store icon
        Color  = 47,   -- light blue-ish
        Scale  = 0.8
    },

    Shops = {
        -- Some common GTA5 clothing store locations
        { label = "Clothing Store", coords = vector3(72.3, -1399.1, 29.4) },   -- Strawberry
        { label = "Clothing Store", coords = vector3(-703.8, -152.3, 37.4) },  -- Hawick Ave
        { label = "Clothing Store", coords = vector3(-167.9, -299.0, 39.7) },  -- Del Perro
        { label = "Clothing Store", coords = vector3(425.6, -806.3, 29.5) },   -- Vinewood
        { label = "Clothing Store", coords = vector3(-822.4, -1073.7, 11.3) }, -- Vespucci
        { label = "Clothing Store", coords = vector3(-1193.4, -772.3, 17.3) }, -- Puerto Del Sol
        { label = "Clothing Store", coords = vector3(11.6, 6514.2, 31.9) },    -- Paleto Bay
        { label = "Clothing Store", coords = vector3(1696.3, 4829.3, 42.1) },  -- Grapeseed
        { label = "Clothing Store", coords = vector3(125.8, -223.8, 54.6) },   -- Downtown Vinewood
        { label = "Clothing Store", coords = vector3(614.2, 2761.1, 42.1) },   -- Harmony
        { label = "Clothing Store", coords = vector3(1190.6, 2713.4, 38.2) },  -- Route 68
    }
}

-------------------------------------------------
-- Active character tracking (charid from AzFW)
-------------------------------------------------

local currentCharId = nil

-- Same KVP naming as your spawn script: "azfw_char_appearance_<charid>"
local function getAppearanceKvpKey(charId)
    if not charId then return nil end
    return ("azfw_char_appearance_%s"):format(tostring(charId))
end

local function saveAppearanceForCurrentChar(appearance)
    if not appearance then
        print(("[%s][clothing] saveAppearanceForCurrentChar: no appearance passed"):format(RESOURCE_NAME))
        return
    end
    if not currentCharId then
        print(("[%s][clothing] currentCharId is nil, cannot save outfit"):format(RESOURCE_NAME))
        return
    end

    local key = getAppearanceKvpKey(currentCharId)
    if not key then
        print(("[%s][clothing] failed to build KVP key"):format(RESOURCE_NAME))
        return
    end

    local ok, encoded = pcall(function()
        return json.encode(appearance)
    end)

    if not ok or type(encoded) ~= "string" then
        print(("[%s][clothing] json.encode failed: %s"):format(RESOURCE_NAME, tostring(encoded)))
        return
    end

    SetResourceKvp(key, encoded)
    print(("[%s][clothing] KVP outfit saved for charid=%s key=%s"):format(
        RESOURCE_NAME, tostring(currentCharId), key
    ))
end

local function hasSavedAppearanceForCurrentChar()
    if not currentCharId then
        return false
    end

    local key = getAppearanceKvpKey(currentCharId)
    if not key then
        return false
    end

    local stored = GetResourceKvpString(key)
    return (stored and stored ~= "")
end

local function applySavedAppearanceForCurrentChar()
    if not currentCharId then
        return false
    end

    local key = getAppearanceKvpKey(currentCharId)
    if not key then
        return false
    end

    local stored = GetResourceKvpString(key)
    if not stored or stored == "" then
        print(("[%s][clothing] No saved appearance KVP for key %s (charid %s)"):format(
            RESOURCE_NAME, key, tostring(currentCharId)
        ))
        return false
    end

    local ok, appearance = pcall(function()
        return json.decode(stored)
    end)

    if not ok or type(appearance) ~= "table" then
        print(("[%s][clothing] Failed to decode appearance KVP for key %s: %s"):format(
            RESOURCE_NAME, key, tostring(appearance)
        ))
        return false
    end

    local success = pcall(function()
        exports['fivem-appearance']:setPlayerAppearance(appearance)
    end)

    if success then
        print(("[%s][clothing] Applied saved appearance from KVP key %s for charid %s"):format(
            RESOURCE_NAME, key, tostring(currentCharId)
        ))
    else
        print(("[%s][clothing] Failed to apply appearance via fivem-appearance for charid %s"):format(
            RESOURCE_NAME, tostring(currentCharId)
        ))
    end

    return true
end

-------------------------------------------------
-- Character events from your framework
-------------------------------------------------

RegisterNetEvent("az-fw-money:characterSelected")
AddEventHandler("az-fw-money:characterSelected", function(charid)
    if charid then
        currentCharId = tostring(charid)
        print(("[%s][clothing] characterSelected -> currentCharId=%s"):format(RESOURCE_NAME, currentCharId))
    end
end)

RegisterNetEvent("azfw:character_confirmed")
AddEventHandler("azfw:character_confirmed", function(charid)
    if charid then
        currentCharId = tostring(charid)
        print(("[%s][clothing] character_confirmed -> currentCharId=%s"):format(RESOURCE_NAME, currentCharId))
    end
end)

RegisterNetEvent("azfw:receive_active_character")
AddEventHandler("azfw:receive_active_character", function(charid)
    if charid then
        currentCharId = tostring(charid)
        print(("[%s][clothing] receive_active_character -> currentCharId=%s"):format(RESOURCE_NAME, currentCharId))
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(2500)
    if currentCharId == nil then
        print(("[%s][clothing] requesting active character from server"):format(RESOURCE_NAME))
        TriggerServerEvent("azfw:request_active_character")
    end
end)

-------------------------------------------------
-- Helper: 3D text
-------------------------------------------------

local function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()

    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(_x, _y)
end

-------------------------------------------------
-- Blips for shops
-------------------------------------------------

Citizen.CreateThread(function()
    if not Config.Blips or not Config.Blips.Enabled then
        print(("[%s][clothing] Blips disabled in config"):format(RESOURCE_NAME))
        return
    end

    for _, shop in ipairs(Config.Shops) do
        local blip = AddBlipForCoord(shop.coords.x, shop.coords.y, shop.coords.z)
        SetBlipSprite(blip, Config.Blips.Sprite or 73)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.Blips.Scale or 0.8)
        SetBlipColour(blip, Config.Blips.Color or 47)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(shop.label or "Clothing Store")
        EndTextCommandSetBlipName(blip)
    end

    print(("[%s][clothing] Created %d clothing store blips"):format(RESOURCE_NAME, #Config.Shops))
end)

-------------------------------------------------
-- Open clothing editor at a shop
-------------------------------------------------

local function openClothingEditor(shop)
    if not Config.UseAppearance then
        print(("[%s][clothing] Config.UseAppearance=false, aborting shop open"):format(RESOURCE_NAME))
        return
    end

    if not currentCharId then
        print(("[%s][clothing] no currentCharId; ignoring clothing store"):format(RESOURCE_NAME))
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName("~r~No character active.~s~ You must select a character first.")
        EndTextCommandThefeedPostTicker(false, true)
        return
    end

    local appearanceConfig = {
        ped = true,
        headBlend = true,
        faceFeatures = true,
        headOverlays = true,
        components = true,
        props = true,
        tattoos = true,
        allowExit = true
    }

    print(("[%s][clothing] Opening fivem-appearance at shop '%s' for charid=%s (price $%d)")
        :format(RESOURCE_NAME, shop.label or "Clothing Store", tostring(currentCharId), Config.Price))

    exports["fivem-appearance"]:startPlayerCustomization(function(appearance)
        if appearance then
            print(("[%s][clothing] customization saved, attempting charge + KVP save"):format(RESOURCE_NAME))

            -- 1) Save appearance to KVP locally (so spawn script uses the new outfit)
            saveAppearanceForCurrentChar(appearance)

            -- 2) Charge money via your economy system (server-side must implement this)
            TriggerServerEvent("az_clothing:purchaseOutfit", Config.Price, appearance)

            -- Optional: apply appearance again for sanity
            pcall(function()
                exports["fivem-appearance"]:setPlayerAppearance(appearance)
            end)
        else
            print(("[%s][clothing] customization canceled; no money taken, no KVP changed"):format(RESOURCE_NAME))
        end
    end, appearanceConfig)
end

-------------------------------------------------
-- Main loop: markers + E to open
-------------------------------------------------

Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)

        local closestShopIndex = nil
        local closestDist = 9999.0

        for i, shop in ipairs(Config.Shops) do
            local dist = #(pCoords - shop.coords)

            if dist < Config.MarkerDistance then
                sleep = 0

                -- Marker
                DrawMarker(
                    Config.MarkerType,
                    shop.coords.x, shop.coords.y, shop.coords.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    Config.MarkerScale.x, Config.MarkerScale.y, Config.MarkerScale.z,
                    Config.MarkerColor.r, Config.MarkerColor.g, Config.MarkerColor.b, Config.MarkerColor.a,
                    false, true, 2, nil, nil, false
                )
            end

            if dist < Config.InteractDistance and dist < closestDist then
                closestDist = dist
                closestShopIndex = i
            end
        end

        if closestShopIndex then
            local shop = Config.Shops[closestShopIndex]
            local textZ = shop.coords.z + Config.TextZOffset

            local prompt = ("~w~Press ~y~[E]~w~ to change clothes ~c~($%d)"):format(Config.Price)
            DrawText3D(shop.coords.x, shop.coords.y, textZ, prompt)

            if IsControlJustReleased(0, Config.Key) then
                openClothingEditor(shop)
            end
        end

        Citizen.Wait(sleep)
    end
end)

print(("^2[%s][clothing] Clothing store client loaded.^7"):format(RESOURCE_NAME))
