Utils = {}

function Utils.dbg(fmt, ...)
  if not Config or not Config.Debug then return end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then
    print(("[Az-Schedule1] %s"):format(msg))
  else
    print(("[Az-Schedule1] (format error) %s"):format(tostring(fmt)))
  end
end

function Utils.clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

function Utils.now()
  return os.time()
end

function Utils.round(x)
  return math.floor(x + 0.5)
end

function Utils.table_copy(t)
  local o = {}
  for k,v in pairs(t or {}) do
    if type(v) == 'table' then o[k] = Utils.table_copy(v) else o[k] = v end
  end
  return o
end

function Utils.vec3_to_table(v)
  return { x = v.x, y = v.y, z = v.z }
end

function Utils.table_to_vec3(t)
  return vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0)
end
