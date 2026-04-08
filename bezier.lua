-- bezier.lua

-- Cubic Bezier curve polygonization via de Casteljau
-- subdivision. Converts path commands (M, L, C, Z)
-- into flat coordinate arrays for rendering.

compy = compy or { }
compy.graphics = compy.graphics or { }

local MAX_DEPTH = 6
local FLAT_TOL = 0.5
local DEGEN_TOL = 0.001

-- Flat coordinate buffer, reused across calls

local flat = { }
local flat_len = 0

-- Append a point to the flat buffer

local function flat_push(x, y)
  flat[flat_len + 1] = x
  flat[flat_len + 2] = y
  flat_len = flat_len + 2
end

-- Flatness test for subdivision

local function is_flat(c)
  local dx = c[7] - c[1]
  local dy = c[8] - c[2]
  local d_sq = dx * dx + dy * dy
  if d_sq < DEGEN_TOL then
    return true
  end
  local d1 = (c[3] - c[7]) * dy - (c[4] - c[8]) * dx
  local d2 = (c[5] - c[7]) * dy - (c[6] - c[8]) * dx
  local s = math.abs(d1) + math.abs(d2)
  return s * s < FLAT_TOL * d_sq
end

-- Create zero-filled 8-element buffer

local function buf8()
  local b = { 0, 0, 0, 0 }
  b[5], b[6], b[7], b[8] = 0, 0, 0, 0
  return b
end

-- Preallocated split buffers per depth

local split_l = { }
local split_r = { }
for sd = 1, MAX_DEPTH do
  split_l[sd] = buf8()
  split_r[sd] = buf8()
end

-- Reusable midpoint storage

local sp_mid = { }
sp_mid[1], sp_mid[2] = 0, 0
sp_mid[3], sp_mid[4] = 0, 0
sp_mid[5], sp_mid[6] = 0, 0

-- Compute split midpoints

local function split_mids(p)
  local bx = (p[3] + p[5]) * 0.5
  local by = (p[4] + p[6]) * 0.5
  sp_mid[1] = (p[1] + p[3]) * 0.5
  sp_mid[2] = (p[2] + p[4]) * 0.5
  sp_mid[3] = (sp_mid[1] + bx) * 0.5
  sp_mid[4] = (sp_mid[2] + by) * 0.5
  sp_mid[5] = (bx + (p[5] + p[7]) * 0.5) * 0.5
  sp_mid[6] = (by + (p[6] + p[8]) * 0.5) * 0.5
end

-- Fill left half from curve and midpoint

local function fill_left(p, l, mx, my)
  l[1], l[2] = p[1], p[2]
  l[3], l[4] = sp_mid[1], sp_mid[2]
  l[5], l[6] = sp_mid[3], sp_mid[4]
  l[7], l[8] = mx, my
end

-- Fill right half from curve and midpoint

local function fill_right(p, r, mx, my)
  r[1], r[2] = mx, my
  r[3], r[4] = sp_mid[5], sp_mid[6]
  r[5] = (p[5] + p[7]) * 0.5
  r[6] = (p[6] + p[8]) * 0.5
  r[7], r[8] = p[7], p[8]
end

-- Split curve into two halves at depth

local function split_at(p, depth)
  local l, r = split_l[depth], split_r[depth]
  local mx = (sp_mid[3] + sp_mid[5]) * 0.5
  local my = (sp_mid[4] + sp_mid[6]) * 0.5
  fill_left(p, l, mx, my)
  fill_right(p, r, mx, my)
  return l, r
end

-- Recursive de Casteljau subdivision

local function subdivide(p, depth)
  if MAX_DEPTH <= depth or is_flat(p) then
    flat_push(p[7], p[8])
  else
    local nd = depth + 1
    split_mids(p)
    local l, r = split_at(p, nd)
    subdivide(l, nd)
    subdivide(r, nd)
  end
end

-- Path command dispatch

local PATH_CMD = { }

PATH_CMD.L = function(cmd, st)
  st[1], st[2] = cmd[2], cmd[3]
  flat_push(cmd[2], cmd[3])
end

PATH_CMD.M = function(cmd, st)
  st[1], st[2] = cmd[2], cmd[3]
  flat_push(cmd[2], cmd[3])
  st[3], st[4] = cmd[2], cmd[3]
end

-- Input curve buffer

local input_curve = buf8()

PATH_CMD.C = function(cmd, st)
  input_curve[1] = st[1]
  input_curve[2] = st[2]
  input_curve[3] = cmd[2]
  input_curve[4] = cmd[3]
  input_curve[5] = cmd[4]
  input_curve[6] = cmd[5]
  input_curve[7] = cmd[6]
  input_curve[8] = cmd[7]
  subdivide(input_curve, 0)
  st[1], st[2] = cmd[6], cmd[7]
end

PATH_CMD.Z = function(_, st)
  if st[1] ~= st[3] or st[2] ~= st[4] then
    flat_push(st[3], st[4])
  end
  st[1], st[2] = st[3], st[4]
end

-- Path state: curX curY startX startY

local path_state = { 0, 0, 0, 0 }

-- Flatten one subpath into flat buffer

local function do_flatten(path)
  flat_len = 0
  path_state[1] = 0
  path_state[2] = 0
  path_state[3] = 0
  path_state[4] = 0
  for _, cmd in ipairs(path) do
    PATH_CMD[cmd[1]](cmd, path_state)
  end
end

-- Flatten path to coordinate array.
-- Converts path commands (M, L, C, Z) into a flat
-- array of x,y coordinates via de Casteljau
-- subdivision of cubic Bezier curves.
-- path: array of {cmd, ...} tables
-- Returns: coords {x1,y1,x2,y2,...}, length

local function flatten_path(path)
  do_flatten(path)
  local copy = { }
  for i = 1, flat_len do
    copy[i] = flat[i]
  end
  return copy, flat_len
end

compy.graphics.flatten_path = flatten_path
