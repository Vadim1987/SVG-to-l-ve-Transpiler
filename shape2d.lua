-- shape2d.lua

-- 2D shape rendering for Compy.
-- Fill and stroke paths using flattened coordinates
-- from bezier.lua and polygon decomposition from
-- bentley_ottmann.lua.

-- Public API in compy.graphics:
-- convex_fill(path) - fill convex polygon
-- concave_fill(path) - triangulate and fill
-- selfx_fill(path) - decompose and fill
-- bezier_stroke(path) - stroke path as line

require("bezier")
require("bentley_ottmann")


compy = compy or { }
compy.graphics = compy.graphics or { }

local gfx = love.graphics
local flatten_path = compy.graphics.flatten_path
local bo_decompose = compy.graphics.bo_decompose_classified

local MIN_POLY = 6
local MIN_LINE = 4

-- Flatten cache: path table -> flat coords

local flat_cache = { }

-- Get flat coords, flatten once on first call

local function get_flat(path)
  local cached = flat_cache[path]
  if cached then
    return cached, #cached
  end
  local copy, n = flatten_path(path)
  flat_cache[path] = copy
  return copy, n
end

-- Draw array of triangles

local function draw_tris(tris)
  for _, tri in ipairs(tris) do
    gfx.polygon("fill", tri)
  end
end

-- Triangle cache

local tri_cache = { }

-- Fill convex polygon: flatten + draw

local function convex_fill(path)
  local pts, n = get_flat(path)
  if MIN_POLY <= n then
    gfx.polygon("fill", pts)
  end
end

-- Triangulate and cache result

local function cache_tris(path, pts)
  local ok, tris = pcall(love.math.triangulate, pts)
  if ok then
    tri_cache[path] = tris
    return tris
  end
  return nil
end

-- Fill concave polygon: triangulate + cache

local function concave_fill(path)
  local pts, n = get_flat(path)
  if n >= MIN_POLY then
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
end

-- Self-intersection decomposition cache

local selfx_cache = { }

-- Fill one decomposed sub-polygon

local function fill_sub_poly(p)
  if #p.pts >= MIN_POLY then
    if p.convex then
      gfx.polygon("fill", p.pts)
    else
      local ok, t = pcall(love.math.triangulate, p.pts)
      if ok then
        draw_tris(t)
      end
    end
  end
end

-- Get cached decomposition or compute

local function get_selfx_polys(path, pts, n)
  local polys = selfx_cache[path]
  if not polys then
    polys = bo_decompose(pts, n)
    selfx_cache[path] = polys
  end
  return polys
end

-- Fill self-intersecting path: decompose + fill

local function selfx_fill(path)
  local pts, n = get_flat(path)
  if n >= MIN_POLY then
    local polys = get_selfx_polys(path, pts, n)
    for _, p in ipairs(polys) do
      fill_sub_poly(p)
    end
  end
end

-- Stroke path: flatten + draw line

local function bezier_stroke(path)
  local pts, n = get_flat(path)
  if MIN_LINE <= n then
    gfx.line(pts)
  end
end

compy.graphics.convex_fill = convex_fill
compy.graphics.concave_fill = concave_fill
compy.graphics.selfx_fill = selfx_fill
compy.graphics.bezier_stroke = bezier_stroke
