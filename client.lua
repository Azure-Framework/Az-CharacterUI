-- Az-CharacterUI/client.lua
-- Adds back:
-- ✅ FiveAppearance (fivem-appearance) load/save/customize per character
-- ✅ Camera transition on spawn selection (smooth interp + fade)
-- Keeps:
-- ✅ Hard focus fix / watchdog
-- ✅ Last Location updates
-- ✅ Spawn modal + NUI endpoints (selectSpawn/saveSpawns/admin/coords)

local firstSpawn = true
local nuiOpen = false
local spawnNuiOpen = false
local nuiOwner = nil
local RESOURCE_NAME = GetCurrentResourceName()

local cachedChars = {}
local currentCharId = nil

local selectionLockUntil = 0
local SELECTION_LOCK_TIME = 5000

Config = Config or {}
Config.EnableLastLocation = (Config.EnableLastLocation ~= false)
Config.LastLocationUpdateIntervalMs = tonumber(Config.LastLocationUpdateIntervalMs) or 10000

Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)

-- Forward declarations
local openAzfwUI
local closeAzfwUI

-- -----------------------------
-- HARD focus system
-- -----------------------------
local nuiReady = false
local focusAssertUntil = 0
local function ms() return GetGameTimer() end

local function focusOff()
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
end

local function focusOn()
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  SetCursorLocation(0.5, 0.5)
end

local function hardResetFocus()
  focusOff()
  Citizen.Wait(0)
  focusOn()
  Citizen.Wait(0)
  focusOn()
  Citizen.SetTimeout(80, function()
    if nuiOpen and nuiOwner == "azfw" and not spawnNuiOpen then focusOn() end
  end)
  Citizen.SetTimeout(180, function()
    if nuiOpen and nuiOwner == "azfw" and not spawnNuiOpen then focusOn() end
  end)
  Citizen.SetTimeout(350, function()
    if nuiOpen and nuiOwner == "azfw" and not spawnNuiOpen then focusOn() end
  end)
end

local function setNuiFocusOwner(owner)
  if owner then
    nuiOwner = owner
    hardResetFocus()
  else
    nuiOwner = nil
    focusOff()
  end
end

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(100)
    if nuiOpen and nuiOwner == "azfw" and not spawnNuiOpen then
      if (ms() < focusAssertUntil) or (not nuiReady) then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
      end
    else
      Citizen.Wait(250)
    end
  end
end)

Citizen.CreateThread(function()
  while true do
    if nuiOpen or spawnNuiOpen then
      Citizen.Wait(0)
      DisableAllControlActions(0)
      EnableControlAction(0, 200, true) -- ESC
      EnableControlAction(0, 322, true) -- ESC alt
      EnableControlAction(0, 245, true) -- chat
    else
      Citizen.Wait(250)
    end
  end
end)

RegisterCommand("fixui", function()
  if nuiOpen then
    print("^3[Az-CharacterUI]^7 /fixui -> reassert focus")
    nuiReady = false
    focusAssertUntil = ms() + 6000
    setNuiFocusOwner("azfw")
  end
end, false)

-- -----------------------------
-- Utilities
-- -----------------------------
local function resStarted(name)
  local st = GetResourceState(name)
  return st == "started" or st == "starting"
end

local function isFiveAppearanceRunning()
  -- common names people use
  if resStarted("fivem-appearance") then return "fivem-appearance" end
  if resStarted("fiveappearance") then return "fiveappearance" end
  if resStarted("five-appearance") then return "five-appearance" end
  return nil
end

-- -----------------------------
-- FiveAppearance
-- -----------------------------
local function applyAppearanceFromJson(appearanceJson)
  if not Config.EnableFiveAppearance then return false end

  local res = isFiveAppearanceRunning()
  if not res then return false end

  local ok, appearance = pcall(function()
    return json.decode(appearanceJson)
  end)
  if not ok or type(appearance) ~= "table" then return false end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return false end

  local applied = false

  -- Try common export names
  if exports[res] and exports[res].setPedAppearance then
    local ok2 = pcall(function()
      exports[res]:setPedAppearance(ped, appearance)
    end)
    applied = ok2 and true or false
  elseif exports[res] and exports[res].setPlayerAppearance then
    local ok2 = pcall(function()
      exports[res]:setPlayerAppearance(appearance)
    end)
    applied = ok2 and true or false
  end

  return applied
end

local function getCurrentPedAppearance()
  if not Config.EnableFiveAppearance then return nil end
  local res = isFiveAppearanceRunning()
  if not res then return nil end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return nil end

  if exports[res] and exports[res].getPedAppearance then
    local ok, ap = pcall(function()
      return exports[res]:getPedAppearance(ped)
    end)
    if ok and type(ap) == "table" then return ap end
  end

  return nil
end

local function startFiveAppearanceCustomization(cb)
  if not Config.EnableFiveAppearance then cb(nil) return end
  local res = isFiveAppearanceRunning()
  if not res then cb(nil) return end

  -- close NUI focus while customizing
  setNuiFocusOwner(nil)

  local function safeCb(app)
    Citizen.SetTimeout(0, function()
      cb(app)
    end)
  end

  local config = {
    ped = true,
    headBlend = true,
    faceFeatures = true,
    headOverlays = true,
    components = true,
    props = true,
    tattoos = true
  }

  if exports[res] and exports[res].startPlayerCustomization then
    local ok = pcall(function()
      exports[res]:startPlayerCustomization(function(appearance)
        safeCb(appearance)
      end, config)
    end)
    if ok then return end
  end

  -- fallback: some forks use StartPlayerCustomization
  if exports[res] and exports[res].StartPlayerCustomization then
    local ok = pcall(function()
      exports[res]:StartPlayerCustomization(function(appearance)
        safeCb(appearance)
      end, config)
    end)
    if ok then return end
  end

  cb(nil)
end

local function fetchAppearanceForChar(charid)
  if not (lib and lib.callback and lib.callback.await) then return nil end
  local ok, res = pcall(function()
    return lib.callback.await("azfw:appearance:get", 6000, tostring(charid))
  end)
  if not ok then return nil end
  return res
end

local function ensureAppearanceLoadedOrCreated(charid)
  if not Config.EnableFiveAppearance then return end
  if not isFiveAppearanceRunning() then return end
  if not charid then return end

  local appearanceJson = fetchAppearanceForChar(charid)
  if appearanceJson and type(appearanceJson) == "string" and appearanceJson ~= "" then
    local applied = applyAppearanceFromJson(appearanceJson)
    if applied then return end
  end

  -- If no saved appearance (or failed), open creator once and save
  startFiveAppearanceCustomization(function(appearance)
    if type(appearance) ~= "table" then
      -- user cancelled
      return
    end

    -- Save to DB
    local ok, appearanceJson2 = pcall(function()
      return json.encode(appearance)
    end)
    if ok and type(appearanceJson2) == "string" and appearanceJson2 ~= "" then
      TriggerServerEvent("azfw:appearance:save", tostring(charid), appearanceJson2)
    end

    -- Apply immediately as well (some forks don't auto-apply)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
      if isFiveAppearanceRunning() and exports[isFiveAppearanceRunning()].setPedAppearance then
        pcall(function()
          exports[isFiveAppearanceRunning()]:setPedAppearance(ped, appearance)
        end)
      end
    end
  end)
end

-- Optional: allow NUI "Edit" to open appearance editor for current active char
RegisterNUICallback("azfw_open_appearance", function(_, cb)
  cb({ ok = true })
  if not currentCharId then return end
  if not isFiveAppearanceRunning() then return end
  startFiveAppearanceCustomization(function(appearance)
    if type(appearance) ~= "table" then return end
    local ok, appearanceJson = pcall(function() return json.encode(appearance) end)
    if ok and appearanceJson and appearanceJson ~= "" then
      TriggerServerEvent("azfw:appearance:save", tostring(currentCharId), appearanceJson)
    end
  end)
end)

-- -----------------------------
-- LAST LOCATION
-- -----------------------------
local lastSendAt = 0

local function sendLastPosNow()
  if not Config.EnableLastLocation then return end
  if not currentCharId then return end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  local coords = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)

  TriggerServerEvent("azfw:lastpos:update", tostring(currentCharId), {
    x = coords.x, y = coords.y, z = coords.z, h = h
  })
end

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(500)
    if Config.EnableLastLocation and currentCharId and (not nuiOpen) and (not spawnNuiOpen) then
      local t = ms()
      if t - lastSendAt >= Config.LastLocationUpdateIntervalMs then
        lastSendAt = t
        sendLastPosNow()
      end
    end
  end
end)

-- -----------------------------
-- Boot flow
-- -----------------------------
local booted = false

local function bootCharacterUI()
  if booted then return end
  booted = true

  Citizen.CreateThread(function()
    while not NetworkIsSessionStarted() do
      Citizen.Wait(200)
    end

    Citizen.Wait(1200)

    TriggerServerEvent("azfw:request_characters")

    if not nuiOpen and not spawnNuiOpen then
      openAzfwUI(cachedChars)
    end
  end)
end

AddEventHandler("onClientResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
      Citizen.Wait(200)
    end
    Citizen.Wait(400)
    booted = false
    bootCharacterUI()
  end)
end)

AddEventHandler("playerSpawned", function()
  if firstSpawn then
    firstSpawn = false
    booted = false
    Citizen.SetTimeout(400, function()
      bootCharacterUI()
    end)
  end
end)

-- -----------------------------
-- UI open/close
-- -----------------------------
openAzfwUI = function(initialChars)
  if nuiOpen then return end
  if nuiOwner == "spawn" or spawnNuiOpen then
    print("[azfw client] openAzfwUI aborted: spawn UI owns focus")
    return
  end

  nuiOpen = true
  nuiReady = false
  focusAssertUntil = ms() + 9000

  if type(initialChars) == "table" and #initialChars > 0 then
    cachedChars = initialChars
  end

  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, false, false)

  setNuiFocusOwner("azfw")

  Citizen.SetTimeout(150, function()
    SendNUIMessage({ type = "azfw_set_resource", resource = RESOURCE_NAME })

    local charsToSend
    if type(cachedChars) == "table" and #cachedChars > 0 then
      charsToSend = cachedChars
    elseif type(initialChars) == "table" and #initialChars > 0 then
      charsToSend = initialChars
    else
      if lib and lib.callback and lib.callback.await then
        local ok, result = pcall(function()
          return lib.callback.await("azfw:fetch_characters", 5000)
        end)
        if ok and type(result) == "table" then
          charsToSend = result
          cachedChars = result
        end
      end
    end

    SendNUIMessage({ type = "azfw_open_ui", chars = charsToSend or {} })

    Citizen.CreateThread(function()
      hardResetFocus()
    end)

    Citizen.SetTimeout(700, function()
      if nuiOpen then
        if (not cachedChars) or (type(cachedChars) ~= "table") or (#cachedChars == 0) then
          TriggerServerEvent("azfw_fetch_characters")
        else
          SendNUIMessage({ type = "azfw_update_chars", chars = cachedChars })
        end
      end
    end)
  end)
end

closeAzfwUI = function(force)
  if not nuiOpen then return end
  nuiOpen = false

  local ped = PlayerPedId()
  FreezeEntityPosition(ped, false)
  SetEntityVisible(ped, true, false)

  if force then
    setNuiFocusOwner(nil)
  else
    if nuiOwner == "azfw" or (nuiOwner == nil and not spawnNuiOpen) then
      setNuiFocusOwner(nil)
    end
  end

  SendNUIMessage({ type = "azfw_close_ui" })
end

-- -----------------------------
-- NUI "ready" handshake
-- -----------------------------
RegisterNUICallback("azfw_nui_ready", function(_, cb)
  nuiReady = true
  if nuiOpen and nuiOwner == "azfw" and not spawnNuiOpen then
    hardResetFocus()
  end
  cb({ ok = true })
end)

-- -----------------------------
-- NUI callbacks (character)
-- -----------------------------
RegisterNUICallback("azfw_select_character", function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end

  currentCharId = tostring(charid)

  selectionLockUntil = ms() + SELECTION_LOCK_TIME
  Citizen.SetTimeout(SELECTION_LOCK_TIME + 200, function()
    if selectionLockUntil > 0 and selectionLockUntil <= ms() then
      selectionLockUntil = 0
    end
  end)

  TriggerServerEvent("az-fw-money:selectCharacter", charid)
end)

RegisterNUICallback("azfw_create_character", function(data, cb)
  cb({ ok = true })
  local first = (data and data.first) or ""
  local last = (data and data.last) or ""
  if first == "" then return end
  TriggerServerEvent("azfw_register_character", first, last)
end)

RegisterNUICallback("azfw_delete_character", function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end
  TriggerServerEvent("azfw_delete_character", charid)
end)

RegisterNUICallback("azfw_close_ui", function(_, cb)
  cb({ ok = true })
  closeAzfwUI(true)
end)

-- -----------------------------
-- Server -> client updates
-- -----------------------------
RegisterNetEvent("azfw:characters_updated")
AddEventHandler("azfw:characters_updated", function(chars)
  cachedChars = chars or {}
  if nuiOpen then
    SendNUIMessage({ type = "azfw_update_chars", chars = cachedChars })
  end
end)

-- =====================================================
-- SPAWN CAMERA TRANSITION
-- =====================================================
local spawnCamActive = false
local camFrom, camTo = nil, nil

local function destroySpawnCams()
  if camFrom then DestroyCam(camFrom, false); camFrom = nil end
  if camTo then DestroyCam(camTo, false); camTo = nil end
  if spawnCamActive then
    RenderScriptCams(false, true, 500, true, true)
    spawnCamActive = false
  end
end

local function makeCamAt(pos, lookAt, fov)
  local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  SetCamCoord(cam, pos.x, pos.y, pos.z)
  SetCamFov(cam, fov or 60.0)
  PointCamAtCoord(cam, lookAt.x, lookAt.y, lookAt.z)
  return cam
end

local function doSpawnTransition(targetCoords, targetHeading)
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  local fromCoords = GetEntityCoords(ped)
  local fromLook = vector3(fromCoords.x, fromCoords.y, fromCoords.z + 0.8)
  local toLook = vector3(targetCoords.x, targetCoords.y, targetCoords.z + 0.8)

  -- build two cams: from + to
  local fromCamPos = vector3(fromCoords.x + 0.0, fromCoords.y - 2.8, fromCoords.z + 1.2)
  local toCamPos   = vector3(targetCoords.x + 0.0, targetCoords.y - 2.8, targetCoords.z + 1.2)

  destroySpawnCams()

  camFrom = makeCamAt(fromCamPos, fromLook, 60.0)
  camTo   = makeCamAt(toCamPos, toLook, 60.0)

  SetCamActive(camFrom, true)
  RenderScriptCams(true, false, 0, true, true)
  spawnCamActive = true

  -- fade out before teleport for cleaner streaming
  DoScreenFadeOut(220)
  local t0 = GetGameTimer()
  while not IsScreenFadedOut() and (GetGameTimer() - t0) < 1200 do
    Citizen.Wait(0)
  end

  -- teleport + stream
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, false, false)

  SetEntityCoordsNoOffset(ped, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false)
  SetEntityHeading(ped, tonumber(targetHeading) or 0.0)

  RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)
  local t1 = GetGameTimer()
  while not HasCollisionLoadedAroundEntity(ped) and (GetGameTimer() - t1) < 2000 do
    Citizen.Wait(0)
  end

  -- interpolate cam to destination
  SetCamActiveWithInterp(camTo, camFrom, 1100, true, true)
  Citizen.Wait(1150)

  -- fade in and restore player
  DoScreenFadeIn(420)
  Citizen.Wait(200)

  SetEntityVisible(ped, true, false)
  FreezeEntityPosition(ped, false)

  destroySpawnCams()
end

-- When server confirms character selected:
RegisterNetEvent("az-fw-money:characterSelected")
AddEventHandler("az-fw-money:characterSelected", function(charid)
  if charid then currentCharId = tostring(charid) end

  -- Close UI
  closeAzfwUI(true)

  Citizen.SetTimeout(0, function()
    -- ✅ FiveAppearance no longer happens here
    -- ✅ Open spawn selector
    Citizen.SetTimeout(200, function()
      TriggerServerEvent("spawn_selector:requestSpawns")
    end)
  end)
end)

RegisterNetEvent("azfw:open_ui")
AddEventHandler("azfw:open_ui", function(chars)
  if type(chars) == "table" and #chars > 0 then cachedChars = chars end
  openAzfwUI(chars)
end)

-- -----------------------------
-- Spawn selector (NUI + server bridge)
-- -----------------------------
RegisterNetEvent("spawn_selector:sendSpawns")
AddEventHandler("spawn_selector:sendSpawns", function(spawns, mapBounds)
  spawnNuiOpen = true
  setNuiFocusOwner("spawn")

  SendNUIMessage({
    type = "spawn_data",
    spawns = spawns or {},
    mapBounds = mapBounds or {},
    resourceName = RESOURCE_NAME
  })
end)

RegisterNetEvent("spawn_selector:adminCheckResult")
AddEventHandler("spawn_selector:adminCheckResult", function(isAdmin)
  SendNUIMessage({ type = "adminCheckResult", isAdmin = isAdmin and true or false })
end)

RegisterNetEvent("spawn_selector:spawnsSaved")
AddEventHandler("spawn_selector:spawnsSaved", function(ok, err)
  SendNUIMessage({ type = "saveResult", ok = ok and true or false, err = err })
end)

RegisterNetEvent("spawn_selector:spawnsUpdated")
AddEventHandler("spawn_selector:spawnsUpdated", function(spawns)
  SendNUIMessage({ type = "spawn_update", spawns = spawns or {} })
end)

-- NUI endpoint: close spawn menu
RegisterNUICallback("closeSpawnMenu", function(_, cb)
  cb("ok")
  spawnNuiOpen = false
  setNuiFocusOwner(nil)
  focusOff()
end)

-- NUI endpoint: request spawns (manual refresh)
RegisterNUICallback("request_spawns", function(_, cb)
  TriggerServerEvent("spawn_selector:requestSpawns")
  cb({ ok = true })
end)

-- NUI endpoint: request edit permission (admin)
RegisterNUICallback("request_edit_permission", function(_, cb)
  TriggerServerEvent("spawn_selector:checkAdmin")
  -- JS expects { isAdmin = bool } sometimes; but we push result via SendNUIMessage.
  -- Return a neutral response now.
  cb({ ok = true })
end)

-- NUI endpoint: save spawns
RegisterNUICallback("saveSpawns", function(data, cb)
  local spawns = data and data.spawns
  if type(spawns) ~= "table" then
    cb({ ok = false, err = "invalid_spawns" })
    return
  end
  TriggerServerEvent("spawn_selector:saveSpawns", spawns)
  cb({ ok = true })
end)

-- NUI endpoint: copy player coords for editor
RegisterNUICallback("request_player_coords", function(_, cb)
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then
    cb({ ok = false })
    return
  end
  local c = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  cb({ x = c.x, y = c.y, z = c.z, h = h })
end)

-- NUI endpoint: select spawn (THIS IS WHERE CAMERA TRANSITION HAPPENS)
RegisterNUICallback("selectSpawn", function(data, cb)
  cb({ ok = true })

  local spawn = data and data.spawn
  if type(spawn) ~= "table" then return end

  local coords = nil
  local heading = 0.0

  if spawn.spawn and spawn.spawn.coords then
    coords = spawn.spawn.coords
    heading = tonumber(spawn.spawn.heading) or 0.0
  elseif spawn.coords then
    coords = spawn.coords
    heading = tonumber(spawn.heading) or 0.0
  end

  if not coords or coords.x == nil or coords.y == nil or coords.z == nil then return end

  -- close spawn menu focus first
  spawnNuiOpen = false
  setNuiFocusOwner(nil)
  focusOff()

  -- do transition + teleport
  Citizen.CreateThread(function()
    doSpawnTransition(vector3(coords.x, coords.y, coords.z), heading)

    -- ✅ FiveAppearance now happens AFTER spawn transition is done
    ensureAppearanceLoadedOrCreated(currentCharId)
  end)
end)

-- ESC close for character UI
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if nuiOpen and IsControlJustReleased(0, 200) then
      closeAzfwUI(true)
    end
  end
end)

print(("^2[azfw client] loaded. Resource=%s^7"):format(RESOURCE_NAME))
