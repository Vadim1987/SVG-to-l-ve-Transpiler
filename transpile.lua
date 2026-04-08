-- transpile.lua

-- SVG to love.graphics Lua transpiler.

compy = { }
compy.graphics = { }

require("svgxml")
require("svgpath")
require("bentley_ottmann")
local bo = compy.graphics

-- Transpile-time flatten for convexity check

FLAT_TOL = 0.5
DEGEN_TOL = 0.001
T_MAX_DEPTH = 6

-- Flatness test

function t_is_flat(c)
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

-- Midpoint buffer

sd_mid = { }
sd_mid[1], sd_mid[2] = 0, 0
sd_mid[3], sd_mid[4] = 0, 0
sd_mid[5], sd_mid[6] = 0, 0

-- Compute de Casteljau midpoints

function sd_mids(c)
  local bx = (c[3] + c[5]) * 0.5
  local by = (c[4] + c[6]) * 0.5
  sd_mid[1] = (c[1] + c[3]) * 0.5
  sd_mid[2] = (c[2] + c[4]) * 0.5
  sd_mid[3] = (sd_mid[1] + bx) * 0.5
  sd_mid[4] = (sd_mid[2] + by) * 0.5
  sd_mid[5] = (bx + (c[5] + c[7]) * 0.5) * 0.5
  sd_mid[6] = (by + (c[6] + c[8]) * 0.5) * 0.5
end

-- Fill left and right curve halves

function sd_left(c, lc, mx, my)
  lc[1], lc[2] = c[1], c[2]
  lc[3], lc[4] = sd_mid[1], sd_mid[2]
  lc[5], lc[6] = sd_mid[3], sd_mid[4]
  lc[7], lc[8] = mx, my
end

function sd_right(c, rc, mx, my)
  rc[1], rc[2] = mx, my
  rc[3], rc[4] = sd_mid[5], sd_mid[6]
  rc[5] = (c[5] + c[7]) * 0.5
  rc[6] = (c[6] + c[8]) * 0.5
  rc[7], rc[8] = c[7], c[8]
end

function sd_halves(c, lc, rc)
  local mx = (sd_mid[3] + sd_mid[5]) * 0.5
  local my = (sd_mid[4] + sd_mid[6]) * 0.5
  sd_left(c, lc, mx, my)
  sd_right(c, rc, mx, my)
end

-- Preallocated split buffers per depth

sd_lc = { }
sd_rc = { }
for sd_i = 1, T_MAX_DEPTH do
  sd_lc[sd_i] = { }
  sd_rc[sd_i] = { }
end

-- Recursive subdivision into pts array

function t_subdivide(c, depth, pts)
  if T_MAX_DEPTH <= depth or t_is_flat(c) then
    pts[#pts + 1] = c[7]
    pts[#pts + 1] = c[8]
  else
    local nd = depth + 1
    sd_mids(c)
    sd_halves(c, sd_lc[nd], sd_rc[nd])
    t_subdivide(sd_lc[nd], nd, pts)
    t_subdivide(sd_rc[nd], nd, pts)
  end
end

-- Flatten command dispatch

TFLAT = { }
tfs = {
  0,
  0,
  0,
  0
}

function TFLAT.L(cmd, pts)
  tfs[1], tfs[2] = cmd[1], cmd[2]
  pts[#pts + 1] = tfs[1]
  pts[#pts + 1] = tfs[2]
end

function TFLAT.M(cmd, pts)
  tfs[1], tfs[2] = cmd[1], cmd[2]
  pts[#pts + 1] = tfs[1]
  pts[#pts + 1] = tfs[2]
  tfs[3], tfs[4] = tfs[1], tfs[2]
end

-- Curve buffer for TFLAT.C

t_curve = {
  0,
  0,
  0,
  0
}

function TFLAT.C(cmd, pts)
  t_curve[1], t_curve[2] = tfs[1], tfs[2]
  t_curve[3], t_curve[4] = cmd[1], cmd[2]
  t_curve[5], t_curve[6] = cmd[3], cmd[4]
  t_curve[7], t_curve[8] = cmd[5], cmd[6]
  t_subdivide(t_curve, 0, pts)
  tfs[1], tfs[2] = cmd[5], cmd[6]
end

function TFLAT.Z(_, pts)
  if tfs[1] ~= tfs[3] or tfs[2] ~= tfs[4] then
    pts[#pts + 1] = tfs[3]
    pts[#pts + 1] = tfs[4]
  end
  tfs[1], tfs[2] = tfs[3], tfs[4]
end

-- Flatten one subpath to coordinate array

function flatten_subpath(subpath)
  local pts = { }
  tfs[1], tfs[2], tfs[3], tfs[4] = 0, 0, 0, 0
  for _, cmd in ipairs(subpath) do
    TFLAT[cmd.cmd](cmd, pts)
  end
  return pts
end

-- Classify subpath: flatten, check selfx/convex

MIN_SELFX_COUNT = 2

function classify_subpath(subpath)
  local pts = flatten_subpath(subpath)
  local xc = bo.bo_count_selfx(pts, #pts)
  if MIN_SELFX_COUNT <= xc then
    return "selfx"
  end
  if bo.bo_is_convex(pts) then
    return "convex"
  end
  return "concave"
end

-- Scale factor for transpile-time scaling

scale_factor = 1
DEFAULT_W = 800
DEFAULT_H = 480

-- Compute scale from viewBox and target

function compute_scale(svg, tw, th)
  local vx, vy, vw, vh = parse_viewbox(svg.attr)
  if vx then
    scale_factor = math.min(tw / vw, th / vh)
  end
end

-- Scale coordinates in one command

function scale_cmd(cmd)
  if scale_factor ~= 1 then
    for i = 1, #cmd do
      cmd[i] = cmd[i] * scale_factor
    end
  end
end

-- Color parsing

HEX_BASE = 16
COLOR_MAX = 255
BBOX_PAD = 2

BLACK = {
  0,
  0,
  0,
  1
}

-- Expand 3-char hex to 6-char

function expand_hex(hex)
  hex = hex:gsub("^#", "")
  if #hex == 3 then
    local a = hex:sub(1, 1):rep(2)
    local b = hex:sub(2, 2):rep(2)
    local c = hex:sub(3, 3):rep(2)
    return a .. b .. c
  end
  return hex
end

-- Parse hex color to RGBA table

function parse_hex(hex)
  hex = expand_hex(hex)
  local r = tonumber(hex:sub(1, 2), HEX_BASE)
  local g = tonumber(hex:sub(3, 4), HEX_BASE)
  local b = tonumber(hex:sub(5, 6), HEX_BASE)
  return {
    r / COLOR_MAX,
    g / COLOR_MAX,
    b / COLOR_MAX,
    1
  }
end

-- Sum gradient stop RGB values

function sum_stops(stops)
  local r, g, b = 0, 0, 0
  for _, hex in ipairs(stops) do
    local c = parse_hex(hex)
    r = r + c[1]
    g = g + c[2]
    b = b + c[3]
  end
  return r, g, b
end

-- Average gradient stops into one solid

function average_stops(stops)
  local r, g, b = sum_stops(stops)
  local n = #stops
  return {
    r / n,
    g / n,
    b / n,
    1
  }
end

-- Gradient collection from defs

gradients = { }

function collect_stops(node)
  local stops = { }
  for _, ch in ipairs(node.children) do
    local sc = ch.attr["stop-color"]
    if ch.tag == "stop" and sc then
      stops[#stops + 1] = sc
    end
  end
  return stops
end

function collect_gradients(defs)
  for _, node in ipairs(defs.children) do
    if node.attr.id then
      gradients[node.attr.id] = {
        stops = collect_stops(node),
        href = node.attr["xlink:href"]
      }
    end
  end
  resolve_gradient_refs()
end

-- Resolve xlink:href references between gradients

function resolve_gradient_refs()
  for _, grad in pairs(gradients) do
    if #(grad.stops) == 0 and grad.href then
      local ref = gradients[grad.href:gsub("^#", "")]
      if ref then
        grad.stops = ref.stops
      end
    end
  end
end

-- Resolve fill attribute to color table

function resolve_fill(attr)
  local fill = attr.fill
  if not fill or fill == "currentColor" then
    return BLACK
  end
  if fill == "none" or fill == "inherit" then
    return nil
  end
  local ref = fill:match("url%(#(.-)%)")
  if ref and gradients[ref] then
    return average_stops(gradients[ref].stops)
  end
  return parse_hex(fill)
end

-- Number formatting

function fmt(n)
  local s = string.format("%.2f", n)
  s = s:gsub("%.?0+$", "")
  if s == "" or s == "-" then
    s = "0"
  end
  return s
end

-- Format a numeric attribute value

function fmt_attr(val)
  return fmt(tonumber(val) * scale_factor)
end

-- Color formatting

function fmt_color(color)
  return string.format(
    "%.3f, %.3f, %.3f, %.3f",
    color[1],
    color[2],
    color[3],
    color[4]
  )
end

-- Output buffer

out = { }

function emit(s)
  out[#out + 1] = s
end

function emit_color(color)
  emit("gfx.setColor(" .. fmt_color(color) .. ")")
end

-- Shape counter for variable names

shape_n = 0

-- Format command numbers as string

function fmt_nums(cmd)
  local nums = { }
  for i = 1, #cmd do
    nums[i] = fmt(cmd[i])
  end
  return table.concat(nums, ", ")
end

-- Emit one path command as Lua table literal

function emit_cmd(cmd)
  local s = "  { \"" .. cmd.cmd .. "\""
  if 0 < #cmd then
    s = s .. ", " .. fmt_nums(cmd)
  end
  emit(s .. " },")
end

-- Emit scaled commands for subpath

function emit_scaled_cmds(subpath)
  for _, cmd in ipairs(subpath) do
    scale_cmd(cmd)
    emit_cmd(cmd)
  end
end

-- Emit one subpath with classification tag

function emit_one_subpath(subpath)
  shape_n = shape_n + 1
  local name = "p" .. shape_n
  local kind = classify_subpath(subpath)
  emit("local " .. name .. " = { -- " .. kind)
  emit_scaled_cmds(subpath)
  emit("}")
  return name, kind
end

-- Emit all subpaths as separate variables

function emit_all_subpaths(subpaths)
  local names = { }
  local kinds = { }
  for _, sp in ipairs(subpaths) do
    local name, kind = emit_one_subpath(sp)
    names[#names + 1] = name
    kinds[#kinds + 1] = kind
  end
  return names, kinds
end

-- Bounding box accumulator

bb = {
  0,
  0,
  0,
  0
}

-- Update bbox with one coordinate pair

function bbox_update(x, y)
  if x < bb[1] then
    bb[1] = x
  end
  if bb[3] < x then
    bb[3] = x
  end
  if y < bb[2] then
    bb[2] = y
  end
  if bb[4] < y then
    bb[4] = y
  end
end

-- Compute bounding box from absolute commands

function bbox_from_abs(abs)
  bb[1], bb[2] = math.huge, math.huge
  bb[3], bb[4] = -math.huge, -math.huge
  for _, cmd in ipairs(abs) do
    for i = 1, #cmd, 2 do
      bbox_update(cmd[i], cmd[i + 1])
    end
  end
  return bb[1], bb[2], bb[3], bb[4]
end

-- Fill call for subpath by kind

FILL_FN = {
  convex = "convex_fill",
  concave = "concave_fill",
  selfx = "selfx_fill"
}

-- Emit stencil function body

function emit_stencil_body(names, kinds)
  emit("gfx.stencil(function()")
  for i, name in ipairs(names) do
    local fn = FILL_FN[kinds[i]]
    emit("  " .. fn .. "(" .. name .. ")")
  end
  emit("end, \"invert\", 1)")
  emit("gfx.setStencilTest(\"greater\", 0)")
end

-- Emit padded bbox rectangle

function emit_bbox_rect(x1, y1, x2, y2)
  local w = fmt((x2 - x1) + BBOX_PAD * 2)
  local h = fmt((y2 - y1) + BBOX_PAD * 2)
  emit(string.format(
    "gfx.rectangle(\"fill\", %s, %s, %s, %s)",
    fmt(x1 - BBOX_PAD),
    fmt(y1 - BBOX_PAD),
    w,
    h
  ))
end

-- Emit stencil rectangle from bbox

function emit_stencil_rect(fill, abs)
  local x1, y1, x2, y2 = bbox_from_abs(abs)
  emit_color(fill)
  emit_bbox_rect(x1, y1, x2, y2)
  emit("gfx.setStencilTest()")
end

-- Emit single subpath fill

function emit_single_fill(name, fill, kind)
  emit_color(fill)
  local fn = FILL_FN[kind]
  emit(fn .. "(" .. name .. ")")
end

-- Emit stroke for all subpath names

function emit_stroke(names, stroke_hex, stroke_w)
  emit_color(parse_hex(stroke_hex))
  if stroke_w then
    local sw = stroke_w * scale_factor
    emit("gfx.setLineWidth(" .. fmt(sw) .. ")")
  end
  for _, name in ipairs(names) do
    emit("bezier_stroke(" .. name .. ")")
  end
end

-- Element emitters by tag name

EMIT = { }

-- Emit fill for path subpaths

function emit_path_fill(names, fill, abs, kinds)
  if fill then
    if 1 < #names then
      emit_stencil_body(names, kinds)
      emit_stencil_rect(fill, abs)
    else
      emit_single_fill(names[1], fill, kinds[1])
    end
  end
end

-- Parse path d-attr into subpaths

function parse_subpaths(d)
  local cmds = parse_path(d)
  local abs = to_absolute(cmds)
  return to_subpaths(abs), abs
end

-- Emit SVG path element

function EMIT.path(node)
  local a = node.attr
  local fill = resolve_fill(a)
  local subs, abs = parse_subpaths(a.d)
  local names, kinds = emit_all_subpaths(subs)
  emit_path_fill(names, fill, abs, kinds)
  if a.stroke then
    local sw = tonumber(a["stroke-width"])
    emit_stroke(names, a.stroke, sw)
  end
  emit("")
end

-- Emit SVG rect element

function EMIT.rect(node)
  local fill = resolve_fill(node.attr)
  if fill then
    local a = node.attr
    emit_color(fill)
    emit(string.format(
      "gfx.rectangle(\"fill\", %s, %s, %s, %s)",
      fmt_attr(a.x),
      fmt_attr(a.y),
      fmt_attr(a.width),
      fmt_attr(a.height)
    ))
    emit("")
  end
end

-- Emit SVG circle element

function EMIT.circle(node)
  local fill = resolve_fill(node.attr)
  if fill then
    local a = node.attr
    emit_color(fill)
    emit(string.format(
      "gfx.circle(\"fill\", %s, %s, %s)",
      fmt_attr(a.cx),
      fmt_attr(a.cy),
      fmt_attr(a.r)
    ))
    emit("")
  end
end

-- Parse polygon points to number array

function parse_pts(attr)
  local nums = { }
  for n in attr.points:gmatch("[%d%.%-]+") do
    nums[#nums + 1] = tonumber(n)
  end
  return nums
end

-- Make a path command from type and two coords

function make_cmd(t, x, y)
  local c = { cmd = t }
  c[1], c[2] = x, y
  return c
end

-- Convert number array to path commands

function pts_to_cmds(nums)
  local cmds = { }
  cmds[1] = make_cmd("M", nums[1], nums[2])
  for i = 3, #nums, 2 do
    cmds[#cmds + 1] = make_cmd("L", nums[i], nums[i + 1])
  end
  cmds[#cmds + 1] = { cmd = "Z" }
  return cmds
end

-- Emit SVG polygon as path with classification

function emit_polygon_el(node)
  local fill = resolve_fill(node.attr)
  local a = node.attr
  local nums = parse_pts(a)
  local cmds = pts_to_cmds(nums)
  local name, kind = emit_one_subpath(cmds)
  if fill then
    emit_single_fill(name, fill, kind)
  end
  if a.stroke then
    local sw = tonumber(a["stroke-width"])
    emit_stroke({ name }, a.stroke, sw)
  end
  emit("")
end

EMIT.polygon = emit_polygon_el

-- Emit SVG line element as stroke

function EMIT.line(node)
  local a = node.attr
  local cmds = { }
  cmds[1] = make_cmd("M", tonumber(a.x1), tonumber(a.y1))
  cmds[2] = make_cmd("L", tonumber(a.x2), tonumber(a.y2))
  local name = emit_one_subpath(cmds)
  if a.stroke then
    local sw = tonumber(a["stroke-width"])
    emit_stroke({ name }, a.stroke, sw)
  end
  emit("")
end

-- Walk SVG tree in document order

function walk(node)
  local handler = EMIT[node.tag]
  if handler then
    handler(node)
  end
  for _, child in ipairs(node.children) do
    walk(child)
  end
end

-- ViewBox pattern

VB_PAT = "([%d%.%-]+)%s+([%d%.%-]+)" .. 
    "%s+([%d%.%-]+)%s+([%d%.%-]+)"

-- Parse viewBox attribute

function parse_viewbox(attr)
  local vb = attr.viewBox
  if not vb then
    return nil
  end
  local x, y, w, h = vb:match(VB_PAT)
  if not x then
    return nil
  end
  return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end

-- Read SVG file

function load_svg(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("Cannot open: " .. path .. "\n")
    os.exit(1)
  end
  local xml = f:read("*a")
  f:close()
  local root = parse_xml(xml)
  return find_child(root, "svg")
end

-- Initialize gradients from defs

function init_gradients(svg)
  local defs = find_child(svg, "defs")
  if defs then
    collect_gradients(defs)
  end
end

-- Generate output Lua code

function generate(svg, source_name)
  emit("-- Generated from " .. source_name)
  emit("require(\"shape2d\")")
  emit("local gfx = love.graphics")
  emit("local convex_fill = compy.graphics.convex_fill")
  emit("local concave_fill = compy.graphics.concave_fill")
  emit("local selfx_fill = compy.graphics.selfx_fill")
  emit("local bezier_stroke = compy.graphics.bezier_stroke")
  emit("")
  init_gradients(svg)
  walk(svg)
  return table.concat(out, "\n") .. "\n"
end

-- Derive output path from input if not given

function output_path(input, given)
  if given then
    return given
  end
  return input:gsub("%.svg$", "") .. ".lua"
end

-- Write output to file

function write_output(code, path)
  local f = io.open(path, "w")
  f:write(code)
  f:close()
end

-- Entry point

input = arg[1]
if not input then
  io.stderr:write(
    "Usage: lua transpile.lua in.svg [out.lua w h]\n"
  )
  os.exit(1)
end

output = output_path(input, arg[2])
local tw = tonumber(arg[3]) or DEFAULT_W
local th = tonumber(arg[4]) or DEFAULT_H
local svg = load_svg(input)
compute_scale(svg, tw, th)
local code = generate(svg, input)
write_output(code, output)
local msg = "OK: " .. input .. " -> " .. output
io.stderr:write(msg .. "\n")
