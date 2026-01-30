local RES = GetCurrentResourceName()

Config = Config or {}
local json = json or require("json")

local World = { pots = {}, lamps = {}, tables = {} }
local PlayerData = nil

local Spawned = { pots = {}, lamps = {}, tables = {}, dirt = {} }

local nuiOpen = false
local currentContext = nil
local currentPotId = nil
local currentTableId = nil

local placing = { active=false, kind=nil, ghost=nil, heading=0.0 }

local duiObj, duiHandle
local txdName, txnName
local mixTvEntity = nil
local mixRtId = nil

local bagCam = nil
local bagScene = { table=nil, buds={}, bags={}, held=nil, heldType=nil, heldKey=nil }
local mouse = { x=0, y=0, down=false }

local function dbg(fmt, ...)
  if not Config.Debug then return end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then print(("[Az-Schedule1:CLIENT] %s"):format(msg)) end
end

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end
RegisterNetEvent("azs1:notify", function(msg) notify(msg) end)

local function ensureModel(model)
  local m = type(model) == "string" and GetHashKey(model) or model
  if not IsModelInCdimage(m) then return false end
  RequestModel(m)
  local t = GetGameTimer() + 5000
  while not HasModelLoaded(m) and GetGameTimer() < t do Wait(0) end
  return HasModelLoaded(m)
end

local function deleteEntitySafe(ent)
  if ent and DoesEntityExist(ent) then
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
  end
end

local function DrawText3D(x, y, z, text)
  local on, _x, _y = World3dToScreen2d(x, y, z)
  if not on then return end
  SetTextScale(0.35, 0.35)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255,255,255,215)
  SetTextEntry("STRING")
  SetTextCentre(1)
  AddTextComponentString(text)
  DrawText(_x, _y)
end

local function rotStep(dir)
  placing.heading = (placing.heading + (Config.Place.RotateStep or 5.0) * dir) % 360.0
end

local function raycastFromCamera(dist)
  local camCoord = GetGameplayCamCoord()
  local camRot = GetGameplayCamRot(2)
  local rx, rz = math.rad(camRot.x), math.rad(camRot.z)
  local dx = -math.sin(rz) * math.abs(math.cos(rx))
  local dy =  math.cos(rz) * math.abs(math.cos(rx))
  local dz =  math.sin(rx)
  local dest = camCoord + vector3(dx, dy, dz) * dist

  local flags = 1 + 8
  local ray = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, flags, PlayerPedId(), 0)
  local _, hit, endCoords, _, _ = GetShapeTestResult(ray)

  if hit == 1 then
    return true, endCoords, nil
  end

  local ped = PlayerPedId()
  local fwd = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
  local ok, gz = GetGroundZFor_3dCoord(fwd.x, fwd.y, fwd.z + 5.0, 0)
  if ok then
    return true, vector3(fwd.x, fwd.y, gz), nil
  end

  return false, dest, nil
end

local function nuiSend(action, data)
  SendNUIMessage({ action = action, data = data })
end

local function openNui(ctx, payload)
  nuiOpen = true
  currentContext = ctx
  SetNuiFocus(true, true)
  nuiSend("open", { context = ctx, payload = payload or {} })
end

local function closeNui()
  nuiOpen = false
  currentContext = nil
  currentPotId = nil
  currentTableId = nil
  if currentContext == "bag_scene" then destroyBagScene() end
  SetNuiFocus(false, false)
  nuiSend("close", {})
end

RegisterNUICallback("close", function(_, cb)
  closeNui()
  cb({ ok = true })
end)

RegisterNUICallback("shop_buy", function(data, cb)
  TriggerServerEvent("azs1:shop:buy", data.item)
  cb({ ok = true })
end)

RegisterNUICallback("place_start", function(data, cb)
  local kind = tostring(data.kind or "")
  if kind == "pots" or kind == "lamps" or kind == "tables" then
    placing.active = true
    placing.kind = kind
    placing.heading = GetEntityHeading(PlayerPedId())
    cb({ ok = true })
  else
    cb({ ok = false })
  end
end)

RegisterNUICallback("pot_plant", function(data, cb)
  TriggerServerEvent("azs1:pot:plant", data.potId, data.strainKey)
  cb({ ok = true })
end)
RegisterNUICallback("pot_water", function(data, cb)
  TriggerServerEvent("azs1:pot:water", data.potId)
  cb({ ok = true })
end)
RegisterNUICallback("pot_fert", function(data, cb)
  TriggerServerEvent("azs1:pot:fert", data.potId)
  cb({ ok = true })
end)

RegisterNUICallback("pot_add_dirt", function(data, cb)
  TriggerServerEvent("azs1:pot:addDirt", data.potId)
  cb({ ok = true })
end)
RegisterNUICallback("pot_trim", function(data, cb)
  TriggerServerEvent("azs1:pot:trim", data.potId)
  cb({ ok = true })
end)
RegisterNUICallback("pot_harvest", function(data, cb)
  TriggerServerEvent("azs1:pot:harvest", data.potId)
  cb({ ok = true })
end)

RegisterNUICallback("bag_one", function(data, cb)
  TriggerServerEvent("azs1:bag:one", data.strainKey)
  cb({ ok = true })
end)

local function spawnPot(pot)
  local id = pot.id
  if Spawned.pots[id] and DoesEntityExist(Spawned.pots[id]) then return end

  local model = Config.Props and Config.Props.pot or "prop_pot_plant_05a"
  if ensureModel(model) then
    local ent = CreateObject(GetHashKey(model), pot.x, pot.y, pot.z, false, false, false)
    SetEntityHeading(ent, pot.h or 0.0)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    Spawned.pots[id] = ent

    if pot.hasDirt then
      local dirtModel = Config.Props and Config.Props.dirt or "prop_cs_sack_01"
    if ensureModel(dirtModel) then
      local d = CreateObject(GetHashKey(dirtModel), pot.x, pot.y, pot.z + 0.10, false, false, false)
      SetEntityHeading(d, pot.h or 0.0)
      SetEntityCollision(d, false, false)
      FreezeEntityPosition(d, true)
      SetEntityInvincible(d, true)
      SetEntityAsMissionEntity(d, true, true)
      SetEntityAlpha(d, 210, false)
      Spawned.dirt[id] = d
      end
    end
  end
end

local function despawnMissing(kind, map)
  for id, ent in pairs(map) do
    if not World[kind][id] then
      deleteEntitySafe(ent)
      map[id] = nil
      if kind == "pots" and Spawned.dirt[id] then
        deleteEntitySafe(Spawned.dirt[id])
        Spawned.dirt[id] = nil
      end
    end
  end
end

local function refreshPlantsOnPots()

  for id, pot in pairs(World.pots) do
    local entPot = Spawned.pots[id]
    if entPot and DoesEntityExist(entPot) then

      if Spawned["plant_"..id] and DoesEntityExist(Spawned["plant_"..id]) then
        deleteEntitySafe(Spawned["plant_"..id])
        Spawned["plant_"..id] = nil
      end

      if pot.strain and not pot.dead then
        local growth = tonumber(pot.growth or 0) or 0
        local stage = 1
        if growth < 34 then stage = 1 elseif growth < 75 then stage = 2 else stage = 3 end
        local model = (Config.PlantModels and (stage==1 and Config.PlantModels.stage1 or stage==2 and Config.PlantModels.stage2 or Config.PlantModels.stage3))
          or "bkr_prop_weed_01_small_01c"
        if ensureModel(model) then
          local plant = CreateObject(GetHashKey(model), pot.x, pot.y, pot.z + 0.15, false, false, false)
          SetEntityHeading(plant, pot.h or 0.0)
          FreezeEntityPosition(plant, true)
          SetEntityInvincible(plant, true)
          SetEntityAsMissionEntity(plant, true, true)
          Spawned["plant_"..id] = plant
        end
      end

      if pot.dead then

      end
    end
  end
end

local function spawnLamp(lamp)
  local id = lamp.id
  if Spawned.lamps[id] and DoesEntityExist(Spawned.lamps[id]) then return end
  local model = Config.Props and Config.Props.growLamp or "prop_worklight_03b"
  if ensureModel(model) then
    local ent = CreateObject(GetHashKey(model), lamp.x, lamp.y, lamp.z, false, false, false)
    SetEntityHeading(ent, lamp.h or 0.0)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    Spawned.lamps[id] = ent
  end
end

local function spawnTable(t)
  local id = t.id
  if Spawned.tables[id] and DoesEntityExist(Spawned.tables[id]) then return end
  local model = Config.Props and Config.Props.bagTable or "prop_table_03"
  if ensureModel(model) then
    local ent = CreateObject(GetHashKey(model), t.x, t.y, t.z, false, false, false)
    SetEntityHeading(ent, t.h or 0.0)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    Spawned.tables[id] = ent
  end
end

RegisterNetEvent("azs1:world:sync", function(w)
  World = w or { pots = {}, lamps = {}, tables = {} }

  for _, pot in pairs(World.pots) do spawnPot(pot) end
  for _, lamp in pairs(World.lamps) do spawnLamp(lamp) end
  for _, t in pairs(World.tables) do spawnTable(t) end

  despawnMissing("pots", Spawned.pots)
  despawnMissing("lamps", Spawned.lamps)
  despawnMissing("tables", Spawned.tables)

  refreshPlantsOnPots()

  if nuiOpen and currentContext == "plant" and currentPotId then
    nuiSend("pot_update", World.pots[currentPotId])
  end
end)

RegisterNetEvent("azs1:player:sync", function(pdata)
  PlayerData = pdata
  if nuiOpen then nuiSend("player", PlayerData) end
end)

local function openPlantSidebar(potId)
  currentPotId = potId
  openNui("plant_sidebar", {
    potId = potId,
    pot = World.pots[potId],
    strains = Config.Strains,
    seeds = (PlayerData and PlayerData.seeds) or {}
  })
end

local function destroyBagScene()
  if bagCam then
    RenderScriptCams(false, true, 250, true, true)
    DestroyCam(bagCam, false)
    bagCam = nil
  end
  for _, e in ipairs(bagScene.buds) do deleteEntitySafe(e) end
  for _, e in ipairs(bagScene.bags) do deleteEntitySafe(e) end
  bagScene.buds, bagScene.bags = {}, {}
  if bagScene.held then deleteEntitySafe(bagScene.held) end
  bagScene.held, bagScene.heldType, bagScene.heldKey = nil, nil, nil
end

local function createBagScene(tableId)
  destroyBagScene()
  currentTableId = tableId

  local t = World.tables[tableId]
  if not t then return end

  local camPos = vector3(t.x, t.y, t.z + 1.3)
  bagCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  SetCamCoord(bagCam, camPos.x, camPos.y, camPos.z)
  PointCamAtCoord(bagCam, t.x, t.y, t.z + 0.75)
  SetCamFov(bagCam, 50.0)
  SetCamActive(bagCam, true)
  RenderScriptCams(true, true, 250, true, true)

  local budModel = Config.Props.weedBud or "prop_weed_bud_02"
  local bagModel = Config.Props.weedBag or "prop_weed_bag_01"
  ensureModel(budModel); ensureModel(bagModel)

  local buds = (PlayerData and PlayerData.buds) or {}
  local sx = -0.32; local sy = -0.05
  local idx = 0

  for strain, count in pairs(buds) do
    for i=1, math.min(count, 10) do
      idx = idx + 1
      local px = t.x + sx + (idx % 5) * 0.10
      local py = t.y + sy + math.floor(idx / 5) * 0.10
      local ent = CreateObject(GetHashKey(budModel), px, py, t.z + 0.78, false, false, false)
      FreezeEntityPosition(ent, true)
      SetEntityInvincible(ent, true)
      SetEntityAsMissionEntity(ent, true, true)
      Entity(ent).state.azs1_type = "bud"
      Entity(ent).state.azs1_strain = strain
      table.insert(bagScene.buds, ent)
    end
  end

  for i=1, math.min((PlayerData and PlayerData.bags) or 0, 5) do
    local ent = CreateObject(GetHashKey(bagModel), t.x + 0.35, t.y - 0.05 + (i*0.02), t.z + 0.78, false, false, false)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    table.insert(bagScene.bags, ent)
  end

  openNui("bag_scene", { buds = buds, bags = (PlayerData and PlayerData.bags) or 0 })
end

local function mouseToTablePoint(tableId, mx, my)
  local t = World.tables[tableId]
  if not t then return nil end

  local camCoord = GetCamCoord(bagCam)
  local camRot = GetCamRot(bagCam, 2)
  local fov = GetCamFov(bagCam)
  local rx, ry, rz = math.rad(camRot.x), math.rad(camRot.y), math.rad(camRot.z)

  local nx = (mx - 0.5) * 2.0
  local ny = (my - 0.5) * 2.0
  local fx = nx * math.tan(math.rad(fov) / 2.0)
  local fy = -ny * math.tan(math.rad(fov) / 2.0)

  local function rotToDir(r)
    local z = math.rad(r.z); local x = math.rad(r.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
  end
  local forward = rotToDir(camRot)
  local right = vector3(math.cos(rz), math.sin(rz), 0.0)
  local up = vector3(0.0, 0.0, 1.0)

  local dir = forward + right * fx + up * fy
  local from = camCoord
  local to = from + dir * 10.0

  local planeZ = t.z + 0.78
  local denom = (to.z - from.z)
  if math.abs(denom) < 0.0001 then return nil end
  local tt = (planeZ - from.z) / denom
  if tt < 0 then return nil end
  local p = from + (to - from) * tt
  return p
end

local function startGhost(kind)
  if placing.ghost then deleteEntitySafe(placing.ghost) placing.ghost=nil end
  local model = (kind=="pots" and Config.Props.pot) or (kind=="lamps" and Config.Props.growLamp) or (kind=="tables" and Config.Props.bagTable)
  if not model then return end
  if ensureModel(model) then
    placing.ghost = CreateObject(GetHashKey(model), 0.0,0.0,0.0, false, false, false)
    SetEntityCollision(placing.ghost, false, false)
    SetEntityAlpha(placing.ghost, 160, false)
    SetEntityInvincible(placing.ghost, true)
    FreezeEntityPosition(placing.ghost, true)
  end
end

local function stopGhost()
  if placing.ghost then deleteEntitySafe(placing.ghost) end
  placing = { active=false, kind=nil, ghost=nil, heading=0.0 }
end

CreateThread(function()
  Wait(1200)
  TriggerServerEvent("azs1:player:requestSync")
end)

RegisterCommand("weedinv", function()
  TriggerServerEvent("azs1:inventory:request")
  if PlayerData then
    openNui("inventory", { player = PlayerData, strains = Config.Strains })
  else
    notify("No player data yet.")
  end
end, false)

RegisterCommand("usepot", function()
  placing.active = true
  placing.kind = "pots"
  placing.heading = GetEntityHeading(PlayerPedId())
  notify("Placement: Pot")
end, false)

RegisterCommand("uselamp", function()
  placing.active = true
  placing.kind = "lamps"
  placing.heading = GetEntityHeading(PlayerPedId())
  notify("Placement: Lamp")
end, false)

RegisterCommand("usetable", function()
  placing.active = true
  placing.kind = "tables"
  placing.heading = GetEntityHeading(PlayerPedId())
  notify("Placement: Bagging Table")
end, false)

CreateThread(function()
  while true do
    Wait(0)

    if placing.active then
      if not placing.ghost then startGhost(placing.kind) end

      local hit, endCoords = raycastFromCamera(Config.Place.MaxDistance or 3.0)
      if hit and placing.ghost then
        SetEntityCoordsNoOffset(placing.ghost, endCoords.x, endCoords.y, endCoords.z, false, false, false)
        SetEntityHeading(placing.ghost, placing.heading)

        DrawText3D(endCoords.x, endCoords.y, endCoords.z + 0.35, "[E] Place  [←/→] Rotate  [Backspace] Cancel")
        DrawMarker(0, endCoords.x, endCoords.y, endCoords.z + 0.03, 0,0,0, 0,0,0, 0.35,0.35,0.35, 0,255,0,120, false,true,2,false,nil,nil,false)

        if IsControlJustPressed(0, Config.Place.RotateLeftKey) then rotStep(-1) end
        if IsControlJustPressed(0, Config.Place.RotateRightKey) then rotStep(1) end

        if IsControlJustPressed(0, Config.Place.CancelKey) then
          stopGhost()
        end

        if IsControlJustPressed(0, Config.Place.ConfirmKey) then
          TriggerServerEvent("azs1:world:place", placing.kind, { x=endCoords.x, y=endCoords.y, z=endCoords.z }, placing.heading)
          stopGhost()
        end
      end
      goto continue
    end

    if nuiOpen and currentContext == "bag_scene" and bagCam then
      DisableControlAction(0, 1, true)
      DisableControlAction(0, 2, true)
      DisableControlAction(0, 24, true)
      DisableControlAction(0, 25, true)
      DisableControlAction(0, 200, true)

      if mouse.down and bagScene.held and currentTableId then
        local p = mouseToTablePoint(currentTableId, mouse.x, mouse.y)
        if p then
          SetEntityCoordsNoOffset(bagScene.held, p.x, p.y, p.z, false, false, false)
        end
      end
      goto continue
    end

    if IsControlJustPressed(0, (Config.Keys and Config.Keys.OpenInventory) or 47) then
      ExecuteCommand("weedinv")
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)

    if #(pos - Config.Shop.coords) < Config.DrawDistance then
      DrawMarker(2, Config.Shop.coords.x, Config.Shop.coords.y, Config.Shop.coords.z+0.1, 0,0,0, 0,0,0, 0.25,0.25,0.25, 0,200,120, 180, false,true,2,false,nil,nil,false)
      DrawText3D(Config.Shop.coords.x, Config.Shop.coords.y, Config.Shop.coords.z+0.35, Config.Text.shop .. " (Buy seeds/pots/lamps/tables)")
      if #(pos - Config.Shop.coords) < Config.InteractDistance and IsControlJustPressed(0, Config.InteractKey) then
        openNui("shop", { items = Config.ShopItems, moneySystem = Config.MoneySystem, canPlace = true })
      end
    end

    local closestPot, closestDist
    for id, pot in pairs(World.pots) do
      local d = #(pos - vector3(pot.x, pot.y, pot.z))
      if d < (closestDist or 999.0) then
        closestDist = d
        closestPot = id
      end
    end

    if closestPot and closestDist and closestDist < 2.0 then
      local pot = World.pots[closestPot]
      local label = "[E] Plant"
      if pot.dead then
        label = "Dead Plant"
      elseif pot.strain then
        label = ("[E] Plant (%s)"):format(pot.strain)
      end
      DrawText3D(pot.x, pot.y, pot.z + 0.55, label)
      if IsControlJustPressed(0, Config.InteractKey) then
        openPlantSidebar(closestPot)
      end
    end

    local closestTable, td
    for id, t in pairs(World.tables) do
      local d = #(pos - vector3(t.x, t.y, t.z))
      if d < (td or 999.0) then td = d; closestTable = id end
    end
    if closestTable and td and td < 2.0 then
      local t = World.tables[closestTable]
      DrawText3D(t.x, t.y, t.z + 0.95, "[E] Bagging Table")
      if IsControlJustPressed(0, Config.InteractKey) then
        createBagScene(closestTable)
      end
    end

    ::continue::
  end
end)

RegisterNUICallback("mouse", function(data, cb)
  mouse.x = tonumber(data.x or 0.5) or 0.5
  mouse.y = tonumber(data.y or 0.5) or 0.5
  mouse.down = data.down == true
  if data.action == "pick" then

    if currentTableId then
      local p = mouseToTablePoint(currentTableId, mouse.x, mouse.y)
      if p then
        local best, bd
        for _, ent in ipairs(bagScene.buds) do
          if DoesEntityExist(ent) then
            local epos = GetEntityCoords(ent)
            local d = #(epos - p)
            if d < (bd or 999.0) then bd = d; best = ent end
          end
        end
        if best and bd and bd < 0.15 then
          bagScene.held = best
          bagScene.heldType = "bud"
          bagScene.heldKey = Entity(best).state.azs1_strain
          SetEntityCollision(best, false, false)
        end
      end
    end
  elseif data.action == "drop" then
    if bagScene.held and bagScene.heldType == "bud" and bagScene.heldKey then

      local t = World.tables[currentTableId]
      local p = mouseToTablePoint(currentTableId, mouse.x, mouse.y)
      if t and p and p.x > (t.x + 0.05) then
        TriggerServerEvent("azs1:bag:one", bagScene.heldKey)
        deleteEntitySafe(bagScene.held)

        local new = {}
        for _, e in ipairs(bagScene.buds) do
          if e ~= bagScene.held then table.insert(new, e) end
        end
        bagScene.buds = new
        notify("Bagged 1.")
      end
    end
    bagScene.held, bagScene.heldType, bagScene.heldKey = nil, nil, nil
  end
  cb({ ok = true })
end)

RegisterNUICallback("bag_close", function(_, cb)
  destroyBagScene()
  closeNui()
  cb({ ok = true })
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= RES then return end
  closeNui()
  destroyBagScene()
  stopGhost()
  for _, ent in pairs(Spawned.pots) do deleteEntitySafe(ent) end
  for _, ent in pairs(Spawned.dirt) do deleteEntitySafe(ent) end
  for _, ent in pairs(Spawned.lamps) do deleteEntitySafe(ent) end
  for _, ent in pairs(Spawned.tables) do deleteEntitySafe(ent) end
end)

RegisterNUICallback("use_item", function(data, cb)
  local item = tostring(data.item or "")
  if item == "pot" then
    if (PlayerData and (PlayerData.pots or 0) > 0) then
      placing.active = true
      placing.kind = "pots"
      placing.heading = GetEntityHeading(PlayerPedId())
      notify("Placement: Pot")
      cb({ ok = true })
      return
    end
    notify("You don't have a pot.")
  elseif item == "lamp" then
    if (PlayerData and (PlayerData.lamps or 0) > 0) then
      placing.active = true
      placing.kind = "lamps"
      placing.heading = GetEntityHeading(PlayerPedId())
      notify("Placement: Lamp")
      cb({ ok = true })
      return
    end
    notify("You don't have a lamp.")
  elseif item == "bag_table" then
    if (PlayerData and (PlayerData.tables or 0) > 0) then
      placing.active = true
      placing.kind = "tables"
      placing.heading = GetEntityHeading(PlayerPedId())
      notify("Placement: Bagging Table")
      cb({ ok = true })
      return
    end
    notify("You don't have a bagging table.")
  end
  cb({ ok = false })
end)

RegisterNUICallback("open_inventory", function(_, cb)
  TriggerServerEvent("azs1:inventory:request")
  openNui("inventory", { player = PlayerData or {}, strains = Config.Strains })
  cb({ ok = true })
end)