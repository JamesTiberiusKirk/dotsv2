if not hl then return end
local T = { ["general.gaps_in"]="int", ["general.gaps_out"]="int", ["general.border_size"]="int",
  ["decoration.rounding"]="int", ["decoration.blur.enabled"]="bool",
  ["decoration.shadow.enabled"]="bool", ["animations.enabled"]="bool" }
local S = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local f = io.open(S .. "/lcars/overrides")
if not f then return end            -- missing file = no overrides
local cfg = {}
for line in f:lines() do
  local k, v = line:match("^([%w_.]+)=(%S+)$")
  local t, val = k and T[k], nil
  if t == "bool" then if v == "true" then val = true elseif v == "false" then val = false end
  elseif t == "int" then local n = tonumber(v); if n then val = math.max(0, math.min(40, math.floor(n))) end end
  if val ~= nil then
    local node, parts = cfg, {}
    for p in k:gmatch("[^.]+") do parts[#parts + 1] = p end
    for i = 1, #parts - 1 do node[parts[i]] = node[parts[i]] or {}; node = node[parts[i]] end
    node[parts[#parts]] = val
  end
end
f:close()
if next(cfg) then pcall(hl.config, cfg) end
