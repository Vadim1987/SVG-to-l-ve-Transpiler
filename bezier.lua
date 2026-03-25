-- bezier.lua

-- Render one SVG subpath via love.graphics.

-- Cubic Bezier by de Casteljau subdivision.

gfx = love.graphics

MAX_DEPTH = 6
FLAT_TOL = 0.5
DEGEN_TOL = 0.001
HALF = 0.5
MIN_POLY_COORDS = 6
MIN_LINE_COORDS = 4

-- Flat coordinate buffer, reused across calls

flat = { }
flat_len = 0

-- Append a point to the flat buffer

function flat_push(x, y)
  flat[flat_len + 1] = x
  flat[flat_len + 2] = y
  flat_len = flat_len + 2
end

-- Trim array tail beyond given length

function trim_tail(arr, len)
  for i = len + 1, #arr do
    arr[i] = nil
  end
end

-- Flatness test for subdivision

function is_flat(c)
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

function buf8()
  return {
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  }
end

-- Preallocated split buffers per depth

split_l = { }
split_r = { }
for sd = 1, MAX_DEPTH do
  split_l[sd] = buf8()
  split_r[sd] = buf8()
end

-- Reusable midpoint storage for split

sp_mid = buf8()

-- Compute split midpoints

function split_mids(p)
  local bx = (p[3] + p[5]) * HALF
  local by = (p[4] + p[6]) * HALF
  sp_mid[1] = (p[1] + p[3]) * HALF
  sp_mid[2] = (p[2] + p[4]) * HALF
  sp_mid[3] = (sp_mid[1] + bx) * HALF
  sp_mid[4] = (sp_mid[2] + by) * HALF
  sp_mid[5] = (bx + (p[5] + p[7]) * HALF) * HALF
  sp_mid[6] = (by + (p[6] + p[8]) * HALF) * HALF
  sp_mid[7] = (sp_mid[3] + sp_mid[5]) * HALF
  sp_mid[8] = (sp_mid[4] + sp_mid[6]) * HALF
end

-- Fill left and right buffers from midpoints

function split_fill(p, depth)
  local l, r = split_l[depth], split_r[depth]
  l[1], l[2] = p[1], p[2]
  l[3], l[4] = sp_mid[1], sp_mid[2]
  l[5], l[6] = sp_mid[3], sp_mid[4]
  l[7], l[8] = sp_mid[7], sp_mid[8]
  r[1], r[2] = sp_mid[7], sp_mid[8]
  r[3], r[4] = sp_mid[5], sp_mid[6]
  r[5] = (p[5] + p[7]) * HALF
  r[6] = (p[6] + p[8]) * HALF
  r[7], r[8] = p[7], p[8]
  return l, r
end

-- Recursive de Casteljau subdivision

function subdivide(p, depth)
  if MAX_DEPTH <= depth or is_flat(p) then
    flat_push(p[7], p[8])
    return 
  end
  local next = depth + 1
  split_mids(p)
  local l, r = split_fill(p, next)
  subdivide(l, next)
  subdivide(r, next)
end

-- Path command dispatch

PATH_CMD = { }

function PATH_CMD.L(cmd, st)
  st[1], st[2] = cmd[2], cmd[3]
  flat_push(cmd[2], cmd[3])
end

function PATH_CMD.M(cmd, st)
  PATH_CMD.L(cmd, st)
  st[3], st[4] = cmd[2], cmd[3]
end

-- Input curve buffer, reused for each C command

input_curve = buf8()

function PATH_CMD.C(cmd, st)
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

function PATH_CMD.Z(_, st)
  if st[1] ~= st[3] or st[2] ~= st[4] then
    flat_push(st[3], st[4])
  end
  st[1], st[2] = st[3], st[4]
end

-- Flatten one subpath into flat buffer

-- Path state: curX curY startX startY

path_state = {
  0,
  0,
  0,
  0
}

function flatten(path)
  flat_len = 0
  path_state[1] = 0
  path_state[2] = 0
  path_state[3] = 0
  path_state[4] = 0
  for _, cmd in ipairs(path) do
    PATH_CMD[cmd[1]](cmd, path_state)
  end
  trim_tail(flat, flat_len)
end

-- Fill one subpath as polygon

function bezier_fill(path)
  flatten(path)
  if flat_len < MIN_POLY_COORDS then
    return 
  end
  local ok, tris = pcall(love.math.triangulate, flat)
  if ok then
    for _, tri in ipairs(tris) do
      gfx.polygon("fill", tri)
    end
    return 
  end
  gfx.polygon("fill", flat)
end

-- Stroke one subpath as line

function bezier_stroke(path)
  flatten(path)
  if flat_len < MIN_LINE_COORDS then
    return 
  end
  gfx.line(flat)
end
