-- bezier.lua

-- Runtime SVG path renderer for Compy.

-- Flatten once, cache. Convex/concave/selfx dispatch.

require("bentley_ottmann")

gfx = love.graphics

local MAX_DEPTH = 6
local FLAT_TOL = 0.5
local DEGEN_TOL = 0.001
local MIN_POLY = 6
local MIN_LINE = 4

-- Flat coordinate buffer, reused across calls

flat = { }
flat_len = 0

-- Append a point to the flat buffer

function flat_push(x, y)
  flat[flat_len + 1] = x
  flat[flat_len + 2] = y
  flat_len = flat_len + 2
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
  local b = {
    0,
    0,
    0,
    0
  }
  b[5], b[6], b[7], b[8] = 0, 0, 0, 0
  return b
end

-- Preallocated split buffers per depth

split_l = { }
split_r = { }
for sd = 1, MAX_DEPTH do
  split_l[sd] = buf8()
  split_r[sd] = buf8()
end

-- Reusable midpoint storage

sp_mid = { }
sp_mid[1], sp_mid[2] = 0, 0
sp_mid[3], sp_mid[4] = 0, 0
sp_mid[5], sp_mid[6] = 0, 0

-- Compute split midpoints

function split_mids(p)
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

function fill_left(p, l, mx, my)
  l[1], l[2] = p[1], p[2]
  l[3], l[4] = sp_mid[1], sp_mid[2]
  l[5], l[6] = sp_mid[3], sp_mid[4]
  l[7], l[8] = mx, my
end

-- Fill right half from curve and midpoint

function fill_right(p, r, mx, my)
  r[1], r[2] = mx, my
  r[3], r[4] = sp_mid[5], sp_mid[6]
  r[5] = (p[5] + p[7]) * 0.5
  r[6] = (p[6] + p[8]) * 0.5
  r[7], r[8] = p[7], p[8]
end

-- Split curve into two halves at depth

function split_at(p, depth)
  local l, r = split_l[depth], split_r[depth]
  local mx = (sp_mid[3] + sp_mid[5]) * 0.5
  local my = (sp_mid[4] + sp_mid[6]) * 0.5
  fill_left(p, l, mx, my)
  fill_right(p, r, mx, my)
  return l, r
end

-- Recursive de Casteljau subdivision

function subdivide(p, depth)
  if MAX_DEPTH <= depth or is_flat(p) then
    flat_push(p[7], p[8])
    return 
  end
  local nd = depth + 1
  split_mids(p)
  local l, r = split_at(p, nd)
  subdivide(l, nd)
  subdivide(r, nd)
end

-- Path command dispatch

PATH_CMD = { }

function PATH_CMD.L(cmd, st)
  st[1], st[2] = cmd[2], cmd[3]
  flat_push(cmd[2], cmd[3])
end

function PATH_CMD.M(cmd, st)
  st[1], st[2] = cmd[2], cmd[3]
  flat_push(cmd[2], cmd[3])
  st[3], st[4] = cmd[2], cmd[3]
end

-- Input curve buffer

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

-- Path state: curX curY startX startY

path_state = {
  0,
  0,
  0,
  0
}

-- Flatten one subpath into flat buffer

function do_flatten(path)
  flat_len = 0
  path_state[1] = 0
  path_state[2] = 0
  path_state[3] = 0
  path_state[4] = 0
  for _, cmd in ipairs(path) do
    PATH_CMD[cmd[1]](cmd, path_state)
  end
end

-- Flatten cache: path table -> copy of flat coords

flat_cache = { }

-- Get flat coords, flatten once on first call

function get_flat(path)
  local cached = flat_cache[path]
  if cached then
    return cached, #cached
  end
  do_flatten(path)
  local copy = { }
  for i = 1, flat_len do
    copy[i] = flat[i]
  end
  flat_cache[path] = copy
  return copy, flat_len
end

-- Draw array of triangles

function draw_tris(tris)
  for _, tri in ipairs(tris) do
    gfx.polygon("fill", tri)
  end
end

-- Triangle cache

tri_cache = { }

-- Fill convex polygon: flatten + draw

function convex_fill(path)
  local pts, n = get_flat(path)
  if n < MIN_POLY then
    return 
  end
  gfx.polygon("fill", pts)
end

-- Triangulate and cache result

function cache_tris(path, pts)
  local ok, tris = pcall(love.math.triangulate, pts)
  if not ok then
    return nil
  end
  tri_cache[path] = tris
  return tris
end

-- Fill concave polygon: triangulate + cache

function concave_fill(path)
  local pts, n = get_flat(path)
  if n < MIN_POLY then
    return 
  end
  local tris = tri_cache[path]
  if not tris then
    tris = cache_tris(path, pts)
  end
  if tris then
    draw_tris(tris)
  else
    gfx.polygon("fill", pts)
  end
end

-- Self-intersection decomposition cache

selfx_cache = { }

-- Fill one decomposed sub-polygon

function fill_sub_poly(p)
  if #p.pts < MIN_POLY then
    return 
  end
  if p.convex then
    gfx.polygon("fill", p.pts)
    return 
  end
  local ok, t = pcall(love.math.triangulate, p.pts)
  if ok then
    draw_tris(t)
  end
end

-- Get cached decomposition or compute

function get_selfx_polys(path, pts, n)
  local polys = selfx_cache[path]
  if polys then
    return polys
  end
  polys = bo_decompose_classified(pts, n)
  selfx_cache[path] = polys
  return polys
end

-- Fill self-intersecting path: decompose + fill

function selfx_fill(path)
  local pts, n = get_flat(path)
  if n < MIN_POLY then
    return 
  end
  local polys = get_selfx_polys(path, pts, n)
  for _, p in ipairs(polys) do
    fill_sub_poly(p)
  end
end

-- Stroke path: flatten + draw line

function bezier_stroke(path)
  local pts, n = get_flat(path)
  if n < MIN_LINE then
    return 
  end
  gfx.line(pts)
end
