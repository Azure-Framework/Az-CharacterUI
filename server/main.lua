local RES = GetCurrentResourceName()

Config = Config or {}
local json = json or require("json")

local function kvpKeyWorld() return "azs1:world:v1" end
local function kvpKeyPlayer(license) return ("azs1:player:v1:%s"):format(license) end

local function getLicense(src)
  local best = nil
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:sub(1,9) == "license2:" then best = best or id end
    if id:sub(1,8) == "license:"  then best = best or id end
    if id:sub(1,6) == "fivem:"    then best = best or id end
    if id:sub(1,6) == "steam:"    then best = best or id end
  end
  return best or ("license:unknown:%d"):format(src)
end

local function kvpGetJson(key, fallback)
  local raw = GetResourceKvpString(key)
  if not raw or raw == "" then return fallback end
  local ok, data = pcall(json.decode, raw)
  if ok and data ~= nil then return data end
  return fallback
end

local function kvpSetJson(key, data)
  SetResourceKvp(key, json.encode(data))
end

local world = kvpGetJson(kvpKeyWorld(), { pots = {}, lamps = {}, tables = {} })

local players = {}

local function defaultPlayerData()
  return {
    buds = {},
    bags = 0,
    mixers = {},
    seeds = {},
    money = 0,

    pots = 0,
    lamps = 0,
    tables = 0,
    dirt = 0,
    fertilizer = 0,
  }
end

local function loadPlayer(src)
  local lic = getLicense(src)
  local pdata = kvpGetJson(kvpKeyPlayer(lic), defaultPlayerData())
  players[src] = { lic = lic, data = pdata }
  return players[src]
end

local function savePlayer(src)
  local p = players[src]
  if not p then return end
  kvpSetJson(kvpKeyPlayer(p.lic), p.data)
end

local function saveWorld()
  kvpSetJson(kvpKeyWorld(), world)
end

local function notify(src, msg)
  TriggerClientEvent("azs1:notify", src, msg)
end

local function broadcastWorld()
  TriggerClientEvent("azs1:world:sync", -1, world)
end

local function broadcastPlayer(src)
  local p = players[src]
  if not p then return end
  TriggerClientEvent("azs1:player:sync", src, p.data)
end

local function getPrice(itemKey)
  local it = Config.ShopItems and Config.ShopItems[itemKey]
  return it and (it.price or 0) or 0
end

local function canAfford(src, cost)
  if Config.MoneySystem == "none" then return true end
  local p = players[src]; if not p then return false end
  return (p.data.money or 0) >= cost
end

local function takeMoney(src, cost)
  if Config.MoneySystem == "none" then return true end
  local p = players[src]; if not p then return false end
  p.data.money = math.max(0, (p.data.money or 0) - cost)
  return true
end

RegisterNetEvent("azs1:shop:buy", function(itemKey)
  local src = source
  local p = players[src] or loadPlayer(src)
  local price = getPrice(itemKey)
  if not canAfford(src, price) then return notify(src, "Not enough money") end
  takeMoney(src, price)

  if itemKey:find("^seed:") then
    local strain = itemKey:gsub("^seed:", "")
    p.data.seeds[strain] = (p.data.seeds[strain] or 0) + 1
    notify(src, ("Bought 1 seed (%s)"):format(strain))
  elseif itemKey == "empty_bag" then
    local it = (Config.ShopItems and Config.ShopItems[itemKey]) or {}
    local amt = tonumber(it.amount or 10) or 10
    p.data.bags = (p.data.bags or 0) + amt
    notify(src, ("Bought %d empty bags"):format(amt))
  elseif itemKey:find("^mixer:") then
    local mk = itemKey:gsub("^mixer:", "")
    p.data.mixers[mk] = (p.data.mixers[mk] or 0) + 1
    notify(src, ("Bought 1 mixer (%s)"):format(mk))
  elseif itemKey == "mixer:basic" then
    p.data.mixers["basic"] = (p.data.mixers["basic"] or 0) + 1
    notify(src, "Bought 1 mixer (basic)")
  elseif itemKey == "dirt" then
    p.data.dirt = (p.data.dirt or 0) + 1
    notify(src, "Bought 1 bag of dirt")
  elseif itemKey == "fertilizer" then
    p.data.fertilizer = (p.data.fertilizer or 0) + 1
    notify(src, "Bought 1 fertilizer")
  elseif itemKey == "pot" then
    p.data.pots = (p.data.pots or 0) + 1
    notify(src, "Bought 1 pot")
  elseif itemKey == "lamp" then
    p.data.lamps = (p.data.lamps or 0) + 1
    notify(src, "Bought 1 grow lamp")
  elseif itemKey == "bag_table" then
    p.data.tables = (p.data.tables or 0) + 1
    notify(src, "Bought 1 bagging table")
  else
    notify(src, "Unknown item")
  end

  savePlayer(src)
  broadcastPlayer(src)
end)

local function countOwned(kind, license)
  local t = world[kind] or {}
  local c = 0
  for _, obj in pairs(t) do
    if obj.owner == license then c = c + 1 end
  end
  return c
end

local function newId(prefix)
  return ("%s_%d_%d"):format(prefix, os.time(), math.random(1000,9999))
end

RegisterNetEvent("azs1:world:place", function(kind, coords, heading)
  local src = source
  local p = players[src] or loadPlayer(src)
  kind = tostring(kind or "")
  if type(coords) ~= "table" then return end
  heading = tonumber(heading or 0.0) or 0.0

  if kind == "pots" then
    if (p.data.pots or 0) <= 0 then return notify(src, "You don't have a pot. Buy one at the shop.") end
    if countOwned("pots", p.lic) >= (Config.World.MaxPotsPerPlayer or 20) then return notify(src, "Pot limit reached.") end
    p.data.pots = (p.data.pots or 0) - 1

    local id = newId("pot")
    world.pots[id] = {
      id=id, owner=p.lic,
      x=coords.x, y=coords.y, z=coords.z,
      h=heading,
      strain=nil,
      growth=0.0,
      water=0.0,
      fert=0.0,
      stage=0,
      dead=false,
      hasDirt=false,
      dirtTicks=0,
      belowTicks=0
    }
    saveWorld(); savePlayer(src)
    broadcastWorld(); broadcastPlayer(src)
    notify(src, "Pot placed.")
    return
  end

  if kind == "lamps" then
    if (p.data.lamps or 0) <= 0 then return notify(src, "You don't have a lamp. Buy one at the shop.") end
    if countOwned("lamps", p.lic) >= (Config.World.MaxLampsPerPlayer or 10) then return notify(src, "Lamp limit reached.") end
    p.data.lamps = (p.data.lamps or 0) - 1

    local id = newId("lamp")
    world.lamps[id] = { id=id, owner=p.lic, x=coords.x, y=coords.y, z=coords.z, h=heading }
    saveWorld(); savePlayer(src)
    broadcastWorld(); broadcastPlayer(src)
    notify(src, "Lamp placed.")
    return
  end

  if kind == "tables" then
    if (p.data.tables or 0) <= 0 then return notify(src, "You don't have a table. Buy one at the shop.") end
    if countOwned("tables", p.lic) >= (Config.World.MaxBagTablesPerPlayer or 3) then return notify(src, "Table limit reached.") end
    p.data.tables = (p.data.tables or 0) - 1

    local id = newId("table")
    world.tables[id] = { id=id, owner=p.lic, x=coords.x, y=coords.y, z=coords.z, h=heading }
    saveWorld(); savePlayer(src)
    broadcastWorld(); broadcastPlayer(src)
    notify(src, "Bagging table placed.")
    return
  end
end)

RegisterNetEvent("azs1:pot:addDirt", function(potId)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  local pot = world.pots[potId]
  if not pot then return end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.dead then return notify(src, "Plant is dead.") end
  if pot.strain then return notify(src, "Already planted.") end
  if pot.hasDirt then return notify(src, "Pot already has dirt.") end
  if (p.data.dirt or 0) <= 0 then return notify(src, "You need dirt. Buy it at the shop.") end

  p.data.dirt = (p.data.dirt or 0) - 1
  pot.hasDirt = true
  pot.water = 0.0
  pot.fert  = 0.0

  saveWorld(); savePlayer(src)
  broadcastWorld(); broadcastPlayer(src)
  notify(src, "Added dirt to pot.")
end)

RegisterNetEvent("azs1:pot:plant", function(potId, strainKey)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  strainKey = tostring(strainKey or "")

  local pot = world.pots[potId]
  if not pot then return end
  if pot.dead then return notify(src, "This plant is dead.") end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.strain ~= nil then return notify(src, "Already planted.") end
  if not pot.hasDirt then return notify(src, "This pot needs dirt first.") end

  if (p.data.seeds[strainKey] or 0) <= 0 then return notify(src, "You don't have that seed.") end
  p.data.seeds[strainKey] = (p.data.seeds[strainKey] or 0) - 1
  pot.strain = strainKey
  pot.growth = 0.0
  pot.water = 50.0
  pot.fert  = 50.0
  pot.belowTicks = 0
  pot.dead = false

  saveWorld(); savePlayer(src)
  broadcastWorld(); broadcastPlayer(src)
  notify(src, ("Planted %s."):format(strainKey))
end)

RegisterNetEvent("azs1:pot:water", function(potId)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  local pot = world.pots[potId]
  if not pot then return end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.dead then return notify(src, "Plant is dead.") end
  if not pot.strain then return notify(src, "Nothing planted.") end

  pot.water = math.min(100.0, (pot.water or 0) + 25.0)
  saveWorld()
  broadcastWorld()
  notify(src, "Watered (+25).")
end)

RegisterNetEvent("azs1:pot:fert", function(potId)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  local pot = world.pots[potId]
  if not pot then return end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.dead then return notify(src, "Plant is dead.") end
  if not pot.strain then return notify(src, "Nothing planted.") end

  if (p.data.fertilizer or 0) <= 0 then return notify(src, "You need fertilizer. Buy it at the shop.") end
  p.data.fertilizer = (p.data.fertilizer or 0) - 1
  pot.fert = math.min(100.0, (pot.fert or 0) + 25.0)
  saveWorld()
  broadcastWorld()
  notify(src, "Fertilized (+25).")
end)

RegisterNetEvent("azs1:pot:trim", function(potId)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  local pot = world.pots[potId]
  if not pot then return end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.dead then return notify(src, "Plant is dead.") end
  if not pot.strain then return notify(src, "Nothing planted.") end
  if (pot.growth or 0) < 35.0 then return notify(src, "Too early to trim.") end

  pot.growth = math.min(100.0, (pot.growth or 0) + 3.0)
  saveWorld()
  broadcastWorld()
  notify(src, "Trimmed (+3% growth).")
end)

RegisterNetEvent("azs1:pot:harvest", function(potId)
  local src = source
  local p = players[src] or loadPlayer(src)
  potId = tostring(potId or "")
  local pot = world.pots[potId]
  if not pot then return end
  if pot.owner ~= p.lic then return notify(src, "Not your pot.") end
  if pot.dead then return notify(src, "Plant is dead.") end
  if not pot.strain then return notify(src, "Nothing planted.") end
  if (pot.growth or 0) < 100.0 then return notify(src, "Not ready.") end

  local yield = 6
  local strain = pot.strain
  p.data.buds[strain] = (p.data.buds[strain] or 0) + yield

  pot.strain = nil
  pot.growth = 0.0
  pot.water = 0.0
  pot.fert  = 0.0
  pot.hasDirt = true
  pot.belowTicks = 0
  pot.dead = false

  saveWorld(); savePlayer(src)
  broadcastWorld(); broadcastPlayer(src)
  notify(src, ("Harvested %d buds (%s)."):format(yield, strain))
end)

RegisterNetEvent("azs1:bag:one", function(strainKey)
  local src = source
  local p = players[src] or loadPlayer(src)
  strainKey = tostring(strainKey or "")
  if (p.data.buds[strainKey] or 0) <= 0 then return notify(src, "No buds.") end
  if (p.data.bags or 0) <= 0 then return notify(src, "No empty bags.") end

  p.data.buds[strainKey] = (p.data.buds[strainKey] or 0) - 1
  p.data.bags = (p.data.bags or 0) - 1
  p.data.bagged = p.data.bagged or {}
  p.data.bagged[strainKey] = (p.data.bagged[strainKey] or 0) + 1

  savePlayer(src)
  broadcastPlayer(src)
  notify(src, "Bagged 1.")
end)

RegisterNetEvent("azs1:mix:do", function(inStrain, mixerKey)
  local src = source
  local p = players[src] or loadPlayer(src)
  inStrain = tostring(inStrain or "")
  mixerKey = tostring(mixerKey or "")
  if (p.data.buds[inStrain] or 0) <= 0 then return notify(src, "No buds.") end
  if (p.data.mixers[mixerKey] or 0) <= 0 then return notify(src, "No mixer.") end

  local recipe = Config.MixRecipes and Config.MixRecipes[inStrain] and Config.MixRecipes[inStrain][mixerKey]
  if not recipe then return notify(src, "No recipe.") end

  p.data.buds[inStrain] = (p.data.buds[inStrain] or 0) - 1
  p.data.mixers[mixerKey] = (p.data.mixers[mixerKey] or 0) - 1

  local out = recipe.outStrain
  local outBuds = recipe.outBuds or 2
  p.data.buds[out] = (p.data.buds[out] or 0) + outBuds
  if recipe.bonusSeeds then
    p.data.seeds[out] = (p.data.seeds[out] or 0) + (recipe.bonusSeeds or 0)
  end

  savePlayer(src)
  broadcastPlayer(src)
  notify(src, ("Mixed into %s (+%d buds)."):format(out, outBuds))
end)

RegisterNetEvent("azs1:player:requestSync", function()
  local src = source
  loadPlayer(src)
  TriggerClientEvent("azs1:world:sync", src, world)
  broadcastPlayer(src)
end)

AddEventHandler("playerDropped", function()
  local src = source
  savePlayer(src)
  players[src] = nil
end)

local function lampNearPot(pot)
  local r = Config.World.LampRadius or 2.5
  for _, lamp in pairs(world.lamps) do
    local dx = (lamp.x - pot.x); local dy = (lamp.y - pot.y); local dz = (lamp.z - pot.z)
    local d = math.sqrt(dx*dx + dy*dy + dz*dz)
    if d <= r then return true end
  end
  return false
end

CreateThread(function()
  Wait(2000)
  while true do
    Wait((Config.World.TickSeconds or 10) * 1000)

    local changed = false
    for _, pot in pairs(world.pots) do
      if pot.strain and not pot.dead then
        pot.water = math.max(0.0, (pot.water or 0) - (Config.World.WaterDecayPerTick or 0.8))
        pot.fert  = math.max(0.0, (pot.fert or 0) - (Config.World.FertDecayPerTick  or 0.6))

        local waterFactor = math.min(1.0, (pot.water or 0) / 50.0)
        local fertFactor  = math.min(1.0, (pot.fert  or 0) / 50.0)
        local mult = (0.15 + 0.85 * ((waterFactor + fertFactor) / 2.0))

        if lampNearPot(pot) then
          mult = mult * (Config.World.LampGrowthMultiplier or 1.35)
        end

        pot.growth = math.min(100.0, (pot.growth or 0) + (Config.World.BaseGrowthPerTick or 1.2) * mult)

        if (pot.water or 0) < (Config.World.DieIfWaterBelow or 2.0) then
          pot.belowTicks = (pot.belowTicks or 0) + 1
          if pot.belowTicks >= (Config.World.DieGraceTicks or 30) then
            pot.dead = true
          end
        else
          pot.belowTicks = 0
        end

        changed = true
      end
    end

    if changed then
      saveWorld()
      broadcastWorld()
    end
  end
end)

RegisterNetEvent("azs1:inventory:request", function()
  local src = source
  local p = players[src] or loadPlayer(src)
  broadcastPlayer(src)
end)