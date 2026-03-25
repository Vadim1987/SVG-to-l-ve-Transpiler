-- transpile.lua

-- SVG to love.graphics Lua transpiler.

require("svgxml")
require("svgpath")

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
    return hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:
        sub(3, 3):rep(2)
  end
  return hex
end

-- Parse 6-char hex to RGBA table

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

-- Average gradient stop colors into one solid

function average_stops(stops)
  local r, g, b, n = 0, 0, 0, 0
  for _, hex in ipairs(stops) do
    local color = parse_hex(hex)
    r = r + color[1]
    g = g + color[2]
    b = b + color[3]
    n = n + 1
  end
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
  for _, child in ipairs(node.children) do
    if child.tag == "stop" and child.attr["stop-color"] then
      stops[#stops + 1] = child.attr["stop-color"]
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
  if not fill then
    return BLACK
  end
  if fill == "none" then
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
  return fmt(tonumber(val))
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

-- Emit one path command as Lua table literal

function emit_cmd(cmd)
  local nums = { }
  for i = 1, #cmd do
    nums[#nums + 1] = fmt(cmd[i])
  end
  if 0 < #nums then
    emit("  { \"" .. cmd.cmd .. "\", " .. table.concat(
      nums,
      ", "
    ) .. " },")
  else
    emit("  { \"" .. cmd.cmd .. "\" },")
  end
end

-- Emit one subpath as a named variable

function emit_one_subpath(subpath)
  shape_n = shape_n + 1
  local name = "p" .. shape_n
  emit("local " .. name .. " = {")
  for _, cmd in ipairs(subpath) do
    emit_cmd(cmd)
  end
  emit("}")
  return name
end

-- Emit all subpaths as separate variables

function emit_all_subpaths(subpaths)
  local names = { }
  for _, sp in ipairs(subpaths) do
    names[#names + 1] = emit_one_subpath(sp)
  end
  return names
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

-- Emit stencil function body

function emit_stencil_body(names)
  emit("gfx.stencil(function()")
  for _, name in ipairs(names) do
    emit("  bezier_fill(" .. name .. ")")
  end
  emit("end, \"invert\", 1)")
  emit("gfx.setStencilTest(\"greater\", 0)")
end

-- Emit stencil rectangle from bbox

function emit_stencil_rect(fill, abs)
  local x1, y1, x2, y2 = bbox_from_abs(abs)
  x1 = x1 - BBOX_PAD
  y1 = y1 - BBOX_PAD
  emit_color(fill)
  local w = fmt((x2 - x1) + BBOX_PAD * 2)
  local h = fmt((y2 - y1) + BBOX_PAD * 2)
  emit(string.format(
    "gfx.rectangle(\"fill\", %s, %s, %s, %s)",
    fmt(x1),
    fmt(y1),
    w,
    h
  ))
  emit("gfx.setStencilTest()")
end

-- Emit stencil fill for multi-subpath path

function emit_stencil(names, fill, abs)
  emit_stencil_body(names)
  emit_stencil_rect(fill, abs)
end

-- Emit single subpath fill

function emit_single_fill(name, fill)
  emit_color(fill)
  emit("bezier_fill(" .. name .. ")")
end

-- Emit stroke for all subpath names

function emit_stroke(names, stroke_hex, stroke_w)
  emit_color(parse_hex(stroke_hex))
  if stroke_w then
    emit("gfx.setLineWidth(" .. fmt(stroke_w) .. ")")
  end
  for _, name in ipairs(names) do
    emit("bezier_stroke(" .. name .. ")")
  end
end

-- Element emitters by tag name

EMIT = { }

-- Emit fill for path subpaths

function emit_path_fill(names, fill, abs)
  if not fill then
    return 
  end
  if 1 < #names then
    emit_stencil(names, fill, abs)
  else
    emit_single_fill(names[1], fill)
  end
end

-- Emit SVG path element

function EMIT.path(node)
  local fill = resolve_fill(node.attr)
  local cmds = parse_path(node.attr.d)
  local abs = to_absolute(cmds)
  local subpaths = to_subpaths(abs)
  local names = emit_all_subpaths(subpaths)
  emit_path_fill(names, fill, abs)
  if node.attr.stroke then
    emit_stroke(
      names,
      node.attr.stroke,
      tonumber(node.attr["stroke-width"])
    )
  end
  emit("")
end

-- Emit a simple filled shape

function emit_simple(node, draw_cmd)
  local fill = resolve_fill(node.attr)
  if not fill then
    return 
  end
  emit_color(fill)
  emit(draw_cmd(node.attr))
  emit("")
end

-- Draw command for rect

function rect_cmd(attr)
  return string.format(
    "gfx.rectangle(\"fill\", %s, %s, %s, %s)",
    fmt_attr(attr.x),
    fmt_attr(attr.y),
    fmt_attr(attr.width),
    fmt_attr(attr.height)
  )
end

-- Draw command for circle

function circle_cmd(attr)
  return string.format(
    "gfx.circle(\"fill\", %s, %s, %s)",
    fmt_attr(attr.cx),
    fmt_attr(attr.cy),
    fmt_attr(attr.r)
  )
end

-- Draw command for polygon

function polygon_cmd(attr)
  local coords = { }
  for n in attr.points:gmatch("[%d%.%-]+") do
    coords[#coords + 1] = fmt_attr(n)
  end
  return "gfx.polygon(\"fill\", " .. table.concat(coords, ", ")
       .. ")"
end

-- Simple shape emitters

SHAPE_CMD = {
  rect = rect_cmd,
  circle = circle_cmd,
  polygon = polygon_cmd
}

function emit_shape(node)
  emit_simple(node, SHAPE_CMD[node.tag])
end

EMIT.rect = emit_shape
EMIT.circle = emit_shape
EMIT.polygon = emit_shape

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

-- Parse viewBox attribute

function parse_viewbox(attr)
  local vb = attr.viewBox
  if not vb then
    return nil
  end
  local x, y, w, h = vb:match(
    "([%d%.%-]+)%s+([%d%.%-]+)%s+" .. 
        "([%d%.%-]+)%s+([%d%.%-]+)"
  )
  if not x then
    return nil
  end
  return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end

-- Emit translate if viewBox has nonzero origin

function emit_translate(vx, vy)
  if vx ~= 0 or vy ~= 0 then
    emit(string.format(
      "gfx.translate(%s * scale, %s * scale)",
      fmt(-vx),
      fmt(-vy)
    ))
  end
end

-- Emit scale from viewBox dimensions

function emit_scale(vw, vh)
  emit("local w, h = gfx.getDimensions()")
  emit(string.format(
    "local scale = math.min(w / %s, h / %s)",
    fmt(vw),
    fmt(vh)
  ))
end

-- Emit viewBox scaling preamble

function emit_viewbox(svg)
  local vx, vy, vw, vh = parse_viewbox(svg.attr)
  if not vx then
    return false
  end
  emit_scale(vw, vh)
  emit("gfx.push()")
  emit_translate(vx, vy)
  emit("gfx.scale(scale)")
  emit("")
  return true
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
  emit("require(\"bezier\")")
  emit("local gfx = love.graphics")
  emit("")
  init_gradients(svg)
  local has_vb = emit_viewbox(svg)
  walk(svg)
  if has_vb then
    emit("gfx.pop()")
  end
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
    "Usage: lua transpile.lua input.svg [output.lua]\n"
  )
  os.exit(1)
end

output = output_path(input, arg[2])
local svg = load_svg(input)
local code = generate(svg, input)
write_output(code, output)
io.stderr:write("OK: " .. input .. " -> " .. output .. "\n")
