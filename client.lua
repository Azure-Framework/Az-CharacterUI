local firstSpawn = true
local nuiOpen = false
local RESOURCE_NAME = GetCurrentResourceName()

-- cached chars pushed from server (keeps latest list across server pushes)
local cachedChars = {}

local function sendNUI(msg)
  SendNUIMessage(msg)
end

local function cameraPanIntoPlayer(durationMs)
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end
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

-- open UI: optional initialChars argument (sent from server)
local function openAzfwUI(initialChars)
  if nuiOpen then return end
  nuiOpen = true

  print(('[azfw client] openAzfwUI called. initialChars=%s'):format(tostring((initialChars and #initialChars) or 0)))

  -- tell NUI which resource to POST back to
  SendNUIMessage({ type = 'azfw_set_resource', resource = RESOURCE_NAME })

  -- If server provided chars, use them and update cache
  local chars = nil
  if type(initialChars) == 'table' and #initialChars > 0 then
    chars = initialChars
    cachedChars = initialChars
  else
    -- try lib.callback first (synchronous-style), else fallback to server event
    if lib and lib.callback and lib.callback.await then
      local ok, result = pcall(function()
        return lib.callback.await('azfw:fetch_characters', 5000)
      end)
      if ok and type(result) == 'table' and #result > 0 then
        chars = result
      else
        if cachedChars and type(cachedChars) == 'table' and #cachedChars > 0 then
          chars = cachedChars
        else
          TriggerServerEvent('azfw_fetch_characters')
        end
      end
    else
      if cachedChars and type(cachedChars) == 'table' and #cachedChars > 0 then
        chars = cachedChars
      else
        TriggerServerEvent('azfw_fetch_characters')
      end
    end
  end

  -- hide player optionally while UI is open (if you prefer)
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, false, false)

  SetNuiFocus(true, true)
  SendNUIMessage({ type = 'azfw_open_ui', chars = chars or {} })
end

local function closeAzfwUI()
  if not nuiOpen then return end
  nuiOpen = false

  print('[azfw client] closeAzfwUI called')

  -- unfreeze/unhide player
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, false)
  SetEntityVisible(ped, true, false)

  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'azfw_close_ui' })
end

-- NUI callbacks
RegisterNUICallback('azfw_select_character', function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then
    print('azfw: select_character missing charid')
    return
  end

  print(('[azfw client] NUI callback azfw_select_character for charid=%s -> forwarding to az-fw-money:selectCharacter'):format(tostring(charid)))

  -- forward to server money selection flow; server will validate and reply with az-fw-money:characterSelected
  TriggerServerEvent('az-fw-money:selectCharacter', charid)
end)

RegisterNUICallback('azfw_create_character', function(data, cb)
  cb({ ok = true })
  local first = data and data.first or ''
  local last  = data and data.last or ''
  if first == '' then return end
  TriggerServerEvent('azfw_register_character', first, last)
  -- server will send azfw:characters_updated back
end)

RegisterNUICallback('azfw_delete_character', function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end
  TriggerServerEvent('azfw_delete_character', charid)
end)

-- allow NUI fetch close to call same close flow
RegisterNUICallback('azfw_close_ui', function(data, cb)
  cb({ ok = true })
  closeAzfwUI()
end)

-- handle server pushes: always update cachedChars, and update NUI if open
RegisterNetEvent('azfw:characters_updated', function(chars)
  print(('[azfw client] received azfw:characters_updated, count=%s'):format(tostring((chars and #chars) or 0)))
  cachedChars = chars or {}
  if nuiOpen then
    SendNUIMessage({ type = 'azfw_update_chars', chars = cachedChars })
  end
end)

-- Server confirms character selection via the az-fw-money flow
RegisterNetEvent('az-fw-money:characterSelected', function(charid)
  print(('[azfw client] received az-fw-money:characterSelected charid=%s'):format(tostring(charid)))

  -- Play camera pan then close UI (UI should hide before camera pan to avoid showing the UI)
  Citizen.CreateThread(function()
    -- close UI immediately to hide the body/background
    closeAzfwUI()
    Wait(80)
    cameraPanIntoPlayer(2200)
  end)
end)

RegisterNetEvent('azfw:character_confirmed', function(charid)
  -- legacy support (if some other code triggers this)
  print(('[azfw client] character_confirmed -> %s'):format(tostring(charid)))
end)

-- accept optional chars when server asks client to open UI
RegisterNetEvent('azfw:open_ui', function(chars)
  print(('[azfw client] received azfw:open_ui initialChars=%s nuiOpen=%s'):format(tostring((chars and #chars) or 0), tostring(nuiOpen)))
  if type(chars) == 'table' and #chars > 0 then
    cachedChars = chars
  end
  openAzfwUI(chars)
end)

-- Open on first spawn
AddEventHandler('playerSpawned', function()
  if firstSpawn then
    firstSpawn = false
    Citizen.SetTimeout(700, function()
      openAzfwUI()
    end)
  end
end)

-- keyboard toggle (F10 default in earlier code; keep 121)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if IsControlJustReleased(0, 121) then
      if nuiOpen then
        closeAzfwUI()
      else
        openAzfwUI()
      end
    end
  end
end)

RegisterCommand('charmenu', function()
  openAzfwUI()
end, false)

Citizen.CreateThread(function()
  Wait(3000)
  if RegisterCommand then
    pcall(function()
      TriggerEvent('chat:addSuggestion', '/charmenu', 'Open the character selection menu')
    end)
  end
end)

print("[azfw client] loaded. Resource name:", RESOURCE_NAME)






--------------------
---Spawn Selector---
--------------------
-- client.lua
-- Handles NUI lifecycle, NUI->client endpoints, and client-server events.

local RESOURCE = GetCurrentResourceName()

-- Open command to request spawns from server
RegisterCommand('spawnsel', function()
  TriggerServerEvent('spawn_selector:requestSpawns')
end, false)

-- When server sends spawns -> open NUI and pass spawns + bounds
RegisterNetEvent('spawn_selector:sendSpawns')
AddEventHandler('spawn_selector:sendSpawns', function(spawns, mapBounds)
  -- ensure NUI focus and send data to HTML
  SetNuiFocus(true, true)
  SendNUIMessage({
    type = 'spawn_data',
    spawns = spawns or {},
    mapBounds = mapBounds or {},
    resourceName = RESOURCE
  })
end)

-- When server broadcasts updated spawns while UI open
RegisterNetEvent('spawn_selector:spawnsUpdated')
AddEventHandler('spawn_selector:spawnsUpdated', function(spawns)
  SendNUIMessage({
    type = 'spawn_update',
    spawns = spawns or {}
  })
end)

-- When server notifies save result
RegisterNetEvent('spawn_selector:spawnsSaved')
AddEventHandler('spawn_selector:spawnsSaved', function(ok, err)
  SendNUIMessage({
    type = 'saveResult',
    ok = ok and true or false,
    err = err or nil
  })
end)

-- Admin check result forwarded from server; client will already be listening for this event when NUI requested permission
RegisterNetEvent('spawn_selector:adminCheckResult')
AddEventHandler('spawn_selector:adminCheckResult', function(isAdmin)
  -- forward to NUI immediately so UI callback can be resolved
  SendNUIMessage({ type = 'adminCheckResult', isAdmin = isAdmin and true or false })
end)

-- NUI callbacks (these are endpoints that index.html's postToLua will fetch)
RegisterNUICallback('request_spawns', function(data, cb)
  -- ask server for spawns; server will respond with spawn_selector:sendSpawns event
  TriggerServerEvent('spawn_selector:requestSpawns')
  cb('ok')
end)

RegisterNUICallback('getResourceName', function(_, cb)
  cb({ resource = RESOURCE })
end)

RegisterNUICallback('closeSpawnMenu', function(_, cb)
  cb('ok')
  SetNuiFocus(false, false)
end)

RegisterNUICallback('selectSpawn', function(data, cb)
  cb('ok')
  -- NUI might pass full spawn object, prefer that
  if type(data) == 'table' and data.spawn and data.spawn.coords then
    local spawn = data.spawn
    local ped = PlayerPedId()
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Citizen.Wait(0) end
    SetEntityCoords(ped, spawn.coords.x, spawn.coords.y, spawn.coords.z, false, false, false, true)
    SetEntityHeading(ped, spawn.heading or 0.0)
    Citizen.Wait(250)
    DoScreenFadeIn(300)
    return
  end

  -- fallback: ask server for spawns to find id (less efficient)
  if type(data) == 'table' and data.id then
    -- request spawns, then teleport if found
    TriggerServerEvent('spawn_selector:requestSpawns')
    -- wait for server response; handled by spawn_selector:sendSpawns event — we can optionally store last requested and auto-teleport
    -- For simplicity the UI should send full spawn objects; encourage that in NUI.
  end
end)

-- NUI asks if local player can edit -> client asks server and waits for server reply
RegisterNUICallback('request_edit_permission', function(_, cb)
  -- We'll register a temporary handler to call the callback once server responds.
  local responded = false

  local function tmpHandler(isAdmin)
    if responded then return end
    responded = true
    cb({ isAdmin = isAdmin and true or false })
    -- remove handler
    RemoveEventHandler('spawn_selector:adminCheckResult', tmpHandler)
  end

  -- register net event and attach temporary handler
  RegisterNetEvent('spawn_selector:adminCheckResult')
  AddEventHandler('spawn_selector:adminCheckResult', tmpHandler)

  -- ask server
  TriggerServerEvent('spawn_selector:checkAdmin')

  -- safety timeout in case server never replies
  Citizen.SetTimeout(3000, function()
    if not responded then
      responded = true
      cb({ isAdmin = false })
      -- best effort cleanup (the handler may still be active but will no-op)
      RemoveEventHandler('spawn_selector:adminCheckResult', tmpHandler)
    end
  end)
end)

-- NUI asks to save spawns (editor) -> forward to server
RegisterNUICallback('saveSpawns', function(data, cb)
  cb('ok')
  if type(data) == 'table' and type(data.spawns) == 'table' then
    TriggerServerEvent('spawn_selector:saveSpawns', data.spawns)
  end
end)
