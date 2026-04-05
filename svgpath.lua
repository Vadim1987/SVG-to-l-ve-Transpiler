-- svgpath.lua

-- Parse SVG path "d" attribute into command lists.

-- Converts arcs to cubic Bezier at transpile time.

DOUBLE = 2
DEG_TO_RAD = math.pi / 180
QUARTER_TURN = math.pi / 2
BEZ_ARC_K1 = 4
BEZ_ARC_K2 = 3

-- Parameter count per SVG path command

PARAMS = { }
PARAMS.M, PARAMS.m = 2, 2
PARAMS.L, PARAMS.l = 2, 2
PARAMS.H, PARAMS.h = 1, 1
PARAMS.V, PARAMS.v = 1, 1
PARAMS.C, PARAMS.c = 6, 6
PARAMS.S, PARAMS.s = 4, 4
PARAMS.A, PARAMS.a = 7, 7
PARAMS.Z, PARAMS.z = 0, 0

-- Implicit repeat command after first set

IMPLICIT_NEXT = {
  M = "L",
  m = "l"
}

-- Classify and scan one token

function scan_token(d, i, len, tokens)
  local char = d:sub(i, i)
  if char:match("[A-Za-z]") then
    tokens[#tokens + 1] = char
    return i + 1
  elseif char:match("[%d%.%-+]") then
    return scan_number(d, i, len, tokens)
  end
  return i + 1
end

-- Tokenize path string

function tokenize_path(d)
  local tokens = { }
  local i, len = 1, #d
  while i <= len do
    i = scan_token(d, i, len, tokens)
  end
  return tokens
end

-- Skip digits at position i

function skip_digits(d, i, len)
  while i <= len and d:sub(i, i):match("%d") do
    i = i + 1
  end
  return i
end

-- Read one number

function scan_number(d, i, len, tokens)
  local start = i
  if d:sub(i, i) == "-" or d:sub(i, i) == "+" then
    i = i + 1
  end
  i = skip_digits(d, i, len)
  if i <= len and d:sub(i, i) == "." then
    i = skip_digits(d, i + 1, len)
  end
  tokens[#tokens + 1] = tonumber(d:sub(start, i - 1))
  return i
end

-- Advance to next implicit command

function next_cmd(tokens, i, cur)
  if i <= #tokens and type(tokens[i]) == "number" then
    return IMPLICIT_NEXT[cur] or cur
  end
  return nil
end

-- Read next command letter

function read_cmd_letter(tokens, i, cur)
  if type(tokens[i]) == "string" then
    return tokens[i], i + 1
  end
  return cur, i
end

-- Parse path string into command tables

function parse_path(d)
  local tokens = tokenize_path(d)
  local cmds = { }
  local i, cur = 1, nil
  while i <= #tokens do
    cur, i = read_cmd_letter(tokens, i, cur)
    if not cur or not PARAMS[cur] then
      break
    end
    i = read_one_cmd(tokens, i, cur, cmds)
    cur = next_cmd(tokens, i, cur)
  end
  return cmds
end

-- Read parameters for one command

function read_one_cmd(tokens, i, cur, cmds)
  local cmd = { cmd = cur }
  for p = 1, PARAMS[cur] do
    cmd[p] = tokens[i]
    i = i + 1
  end
  cmds[#cmds + 1] = cmd
  return i
end

-- Absolute conversion handlers

ABS = { }

-- Reflect last control point for smooth curves

function reflect_ctrl(state)
  if state.last_ctrl then
    local lc = state.last_ctrl
    local cx, cy = state.cx, state.cy
    return DOUBLE * cx - lc[1],
      DOUBLE * cy - lc[2]
  end
  return state.cx, state.cy
end

-- Move to absolute position

function ABS.M(data, state)
  local x, y = data[1] + state.ox, data[2] + state.oy
  state.cx, state.cy, state.sx, state.sy = x, y, x, y
  return {
    cmd = "M",
    x,
    y
  }
end

-- Build a line output command from state

function make_line(state)
  return {
    cmd = "L",
    state.cx,
    state.cy
  }
end

-- Line to absolute position

function ABS.L(data, state)
  state.cx = data[1] + state.ox
  state.cy = data[2] + state.oy
  return make_line(state)
end

-- Horizontal line

function ABS.H(data, state)
  state.cx = data[1] + (state.rel and state.cx or 0)
  return make_line(state)
end

-- Vertical line

function ABS.V(data, state)
  state.cy = data[1] + (state.rel and state.cy or 0)
  return make_line(state)
end

-- Create a cubic Bezier command table

function new_cubic()
  return { cmd = "C" }
end

-- Set state endpoint and last control point

function set_ctrl(state, cmd)
  state.cx, state.cy = cmd[5], cmd[6]
  state.last_ctrl = { cmd[3], cmd[4] }
end

-- Cubic Bezier

function ABS.C(data, state)
  local ox, oy = state.ox, state.oy
  local r = new_cubic()
  r[1], r[2] = data[1] + ox, data[2] + oy
  r[3], r[4] = data[3] + ox, data[4] + oy
  r[5], r[6] = data[5] + ox, data[6] + oy
  set_ctrl(state, r)
  return r
end

-- Smooth cubic Bezier

function ABS.S(data, state)
  local ox, oy = state.ox, state.oy
  local rx, ry = reflect_ctrl(state)
  local r = new_cubic()
  r[1], r[2] = rx, ry
  r[3], r[4] = data[1] + ox, data[2] + oy
  r[5], r[6] = data[3] + ox, data[4] + oy
  set_ctrl(state, r)
  return r
end

-- Close path

function ABS.Z(_, state)
  state.cx, state.cy = state.sx, state.sy
  return { cmd = "Z" }
end

-- Build arc parameter table from data and state

function make_arc(data, state)
  local a = { }
  a.x1, a.y1 = state.cx, state.cy
  a.rx, a.ry = data[1], data[2]
  a.phi, a.fa, a.fs = data[3], data[4], data[5]
  a.x2 = data[6] + state.ox
  a.y2 = data[7] + state.oy
  return a
end

-- Arc: build arc table and convert to cubics

function ABS.A(data, state)
  local arc = make_arc(data, state)
  state.cx, state.cy = arc.x2, arc.y2
  return arc_to_cubics(arc)
end

-- Convert one command to absolute

function convert_cmd(cmd, state)
  local upper = cmd.cmd:upper()
  state.rel = (cmd.cmd ~= upper)
  state.ox = state.rel and state.cx or 0
  state.oy = state.rel and state.cy or 0
  local result = ABS[upper](cmd, state)
  if upper ~= "C" and upper ~= "S" then
    state.last_ctrl = nil
  end
  return result
end

-- Append single command or array

function append_result(abs, result)
  if result.cmd then
    abs[#abs + 1] = result
  else
    for _, item in ipairs(result) do
      abs[#abs + 1] = item
    end
  end
end

-- Initial absolute conversion state

function abs_state()
  return {
    cx = 0,
    cy = 0,
    sx = 0,
    sy = 0
  }
end

-- Convert all commands to absolute

function to_absolute(cmds)
  local abs = { }
  local state = abs_state()
  for _, cmd in ipairs(cmds) do
    append_result(abs, convert_cmd(cmd, state))
  end
  return abs
end

-- Split into subpaths

function to_subpaths(abs)
  local subpaths = { }
  local cur
  for _, cmd in ipairs(abs) do
    if cmd.cmd == "M" then
      cur = { cmd }
      subpaths[#subpaths + 1] = cur
    elseif cur then
      cur[#cur + 1] = cmd
    end
  end
  return subpaths
end

-- Length of 2D vector

function vec_len(x, y)
  return math.sqrt(x * x + y * y)
end

-- Angle between two vectors

function arc_angle(ux, uy, vx, vy)
  local dot = ux * vx + uy * vy
  local len = vec_len(ux, uy) * vec_len(vx, vy)
  if len == 0 then 
    return 0 
 end
  local cl = math.max(-1, math.min(1, dot / len))
  local a = math.acos(cl)
  if ux * vy - uy * vx < 0 then a = -a 
 end
  return a
end

-- Scale radii if too small

function fix_radii(arc)
  local xp = arc.x1p * arc.x1p
  local yp = arc.y1p * arc.y1p
  local rx2 = arc.rx * arc.rx
  local ry2 = arc.ry * arc.ry
  local lam = xp / rx2 + yp / ry2
  if 1 < lam then
    local sl = math.sqrt(lam)
    arc.rx = arc.rx * sl
    arc.ry = arc.ry * sl
  end
end

-- Square root ratio for arc center

function sq_ratio(rx2, ry2, xp, yp)
  local num = rx2 * ry2 - rx2 * yp - ry2 * xp
  local den = rx2 * yp + ry2 * xp
  if 0 < den and 0 < num then
    return math.sqrt(num / den)
  end
  return 0
end

-- Compute sign factor for center

function arc_sq(arc)
  local rx, ry = arc.rx, arc.ry
  local xp = arc.x1p * arc.x1p
  local yp = arc.y1p * arc.y1p
  local sq = sq_ratio(rx * rx, ry * ry, xp, yp)
  if arc.fa == arc.fs then sq = -sq end
  return sq
end

-- Compute rotated midpoint

function arc_rot_mid(arc)
  local dx = (arc.x1 - arc.x2) * 0.5
  local dy = (arc.y1 - arc.y2) * 0.5
  arc.x1p = arc.cp * dx + arc.sp * dy
  arc.y1p = -arc.sp * dx + arc.cp * dy
  fix_radii(arc)
end

-- Compute center from rotated midpoint

function arc_find_center(arc)
  arc_rot_mid(arc)
  local sq = arc_sq(arc)
  arc.cxp = sq * arc.rx * arc.y1p / arc.ry
  arc.cyp = -sq * arc.ry * arc.x1p / arc.rx
  local mx = (arc.x1 + arc.x2) * 0.5
  local my = (arc.y1 + arc.y2) * 0.5
  local cp, sp = arc.cp, arc.sp
  arc.cx = (cp * arc.cxp - sp * arc.cyp) + mx
  arc.cy = sp * arc.cxp + cp * arc.cyp + my
end

-- Correct sweep angle sign per SVG spec

function fix_sweep(arc)
  if arc.fs == 0 and arc.dth > 0 then
    arc.dth = arc.dth - DOUBLE * math.pi
  end
  if arc.fs == 1 and arc.dth < 0 then
    arc.dth = arc.dth + DOUBLE * math.pi
  end
end

-- Compute start angle and sweep

function arc_find_angles(arc)
  local rx, ry = arc.rx, arc.ry
  local ux = (arc.x1p - arc.cxp) / rx
  local uy = (arc.y1p - arc.cyp) / ry
  arc.th1 = arc_angle(1, 0, ux, uy)
  arc.dth = arc_angle(
    ux,
    uy,
    -ux - DOUBLE * arc.cxp / rx,
    -uy - DOUBLE * arc.cyp / ry
  )
  fix_sweep(arc)
end

-- Compute endpoint at angle th

function arc_point(arc, th)
  local ct = math.cos(th)
  local st = math.sin(th)
  local rx, ry = arc.rx, arc.ry
  local cp, sp = arc.cp, arc.sp
  local x = arc.cx + cp * rx * ct - sp * ry * st
  local y = arc.cy + sp * rx * ct + cp * ry * st
  return x, y, -rx * st, ry * ct
end

-- Rotated control point offset

function arc_cp(arc, t, dx, dy)
  local cx = arc.cp * t * dx - arc.sp * t * dy
  local cy = arc.sp * t * dx + arc.cp * t * dy
  return cx, cy
end

-- One cubic segment from th to th+step

function arc_one_seg(arc, th, step, t)
  local x1, y1, dx1, dy1 = arc_point(arc, th)
  local x2, y2, dx2, dy2 = arc_point(
    arc, th + step)
  local c1x, c1y = arc_cp(arc, t, dx1, dy1)
  local c2x, c2y = arc_cp(arc, t, dx2, dy2)
  local r = new_cubic()
  r[1], r[2] = x1 + c1x, y1 + c1y
  r[3], r[4] = x2 - c2x, y2 - c2y
  r[5], r[6] = x2, y2
  return r
end

-- Bezier approximation coefficient for arc step

function arc_tan_coeff(step)
  local half = step / BEZ_ARC_K1
  return BEZ_ARC_K1 * math.tan(half) / BEZ_ARC_K2
end

-- Generate all cubic segments for arc

function arc_emit_segments(arc)
  local dth = math.abs(arc.dth)
  local segs = math.ceil(dth / QUARTER_TURN)
  local step = arc.dth / segs
  local t = arc_tan_coeff(step)
  local result = { }
  local th = arc.th1
  for i = 1, segs do
    result[#result + 1] = arc_one_seg(arc, th, step, t)
    th = th + step
  end
  return result
end

-- Prepare arc trigonometry and geometry

function arc_prepare(arc)
  arc.rx, arc.ry = math.abs(arc.rx), math.abs(arc.ry)
  local rad = arc.phi * DEG_TO_RAD
  arc.cp, arc.sp = math.cos(rad), math.sin(rad)
  arc_find_center(arc)
  arc_find_angles(arc)
end

-- Convert arc to cubic Bezier segments

function arc_to_cubics(arc)
  if arc.x1 == arc.x2 and arc.y1 == arc.y2 then
    return { }
  end
  if arc.rx == 0 or arc.ry == 0 then
    local l = { cmd = "L", arc.x2, arc.y2 }
    return { l }
  end
  arc_prepare(arc)
  return arc_emit_segments(arc)
end
