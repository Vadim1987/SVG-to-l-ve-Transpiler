-- bentley_ottmann.lua

-- Self-intersection detection and decomposition.

-- Shared between transpiler and runtime.

-- Uses Bentley-Ottmann sweep line algorithm.

PAIR = 2
BO_EPS = 1e-9
BO_T_EPS = 0.01
TWO_PI = 2 * math.pi
MIN_SELFX = 8
MIN_VERTS = 3
KEY_MULT = 10000
BO_SNAP = 1e-4

-- Build one segment from vertex indices

function bo_one_seg(pts, i, i2)
  return {
    pts[i * PAIR - 1],
    pts[i * PAIR],
    pts[i2 * PAIR - 1],
    pts[i2 * PAIR],
    i
  }
end

-- Build segment array from flat coords

function bo_make_segs(pts, n)
  local segs = { }
  local nv = n / PAIR
  for i = 1, nv do
    segs[i] = bo_one_seg(pts, i, (i % nv) + 1)
  end
  return segs
end

-- Orient segment so x1 <= x2

function bo_orient(s)
  if s[1] < s[3] then
    return s[1], s[2], s[3], s[4]
  end
  if s[1] > s[3] then
    return s[3], s[4], s[1], s[2]
  end
  if s[2] <= s[4] then
    return s[1], s[2], s[3], s[4]
  end
  return s[3], s[4], s[1], s[2]
end

-- Compute y on segment at given x

function bo_y_at_x(s, x)
  local x1, y1, x2, y2 = bo_orient(s)
  local dx = x2 - x1
  if math.abs(dx) < BO_EPS then
    return (y1 + y2) * 0.5
  end
  local t = (x - x1) / dx
  return y1 + t * (y2 - y1)
end

-- Cross product: seg s against point (px, py)

function bo_seg_cross(s, px, py)
  local dx = s[3] - s[1]
  local dy = s[4] - s[2]
  return dx * (py - s[2]) - dy * (px - s[1])
end

-- Distance squared between two points

function bo_dist2(ax, ay, bx, by)
  local dx = ax - bx
  local dy = ay - by
  return dx * dx + dy * dy
end

-- Check if point matches any endpoint of segment

function bo_ep_match(ax, ay, b)
  if bo_dist2(ax, ay, b[1], b[2]) < BO_EPS then
    return true
  end
  return bo_dist2(ax, ay, b[3], b[4]) < BO_EPS
end

-- Test if two segments share an endpoint

function bo_shared_ep(a, b)
  if bo_ep_match(a[1], a[2], b) then
    return true
  end
  return bo_ep_match(a[3], a[4], b)
end

-- Reusable cross-product buffer

bo_d = {
  0,
  0,
  0,
  0
}

-- Compute four cross products for straddle test

function bo_cross_4(a, b)
  bo_d[1] = bo_seg_cross(a, b[1], b[2])
  bo_d[2] = bo_seg_cross(a, b[3], b[4])
  bo_d[3] = bo_seg_cross(b, a[1], a[2])
  bo_d[4] = bo_seg_cross(b, a[3], a[4])
end

-- Check if cross products indicate straddle

function bo_straddle()
  if bo_d[1] * bo_d[2] > BO_EPS then
    return false
  end
  if bo_d[3] * bo_d[4] > BO_EPS then
    return false
  end
  return true
end

-- Compute intersection coords from bo_d buffer

function bo_xpt_coords(b)
  local denom = bo_d[1] - bo_d[2]
  if math.abs(denom) < BO_EPS then
    return nil
  end
  local t = bo_d[1] / denom
  local ix = b[1] + t * (b[3] - b[1])
  local iy = b[2] + t * (b[4] - b[2])
  return ix, iy
end

-- Compute intersection point of segments a, b

function bo_intersect(a, b)
  bo_cross_4(a, b)
  if not bo_straddle() then
    return nil
  end
  return bo_xpt_coords(b)
end

-- Event types

BO_LEFT = 1
BO_RIGHT = 2
BO_CROSS = 3

-- Create endpoint event (left or right)

function bo_endpoint_ev(s, kind)
  local x1, y1, x2, y2 = bo_orient(s)
  local ev = { }
  ev.kind = kind
  ev.seg = s
  if kind == BO_LEFT then
    ev.x, ev.y = x1, y1
  else
    ev.x, ev.y = x2, y2
  end
  return ev
end

-- Create crossing event

function bo_cross_ev(x, y, sa, sb)
  return {
    x = x,
    y = y,
    kind = BO_CROSS,
    sa = sa,
    sb = sb
  }
end

-- Compare events by (x, y, kind)

function bo_ev_lt(a, b)
  if a.x ~= b.x then
    return a.x < b.x
  end
  if a.y ~= b.y then
    return a.y < b.y
  end
  return a.kind < b.kind
end

-- Insert event into sorted event queue

function bo_ev_insert(q, ev)
  local pos = #q + 1
  for i = 1, #q do
    if bo_ev_lt(ev, q[i]) then
      pos = i
      break
    end
  end
  table.insert(q, pos, ev)
end

-- Build initial event queue from segments

function bo_init_events(segs)
  local q = { }
  for _, s in ipairs(segs) do
    bo_ev_insert(q, bo_endpoint_ev(s, BO_LEFT))
    bo_ev_insert(q, bo_endpoint_ev(s, BO_RIGHT))
  end
  return q
end

-- Insert segment into status at correct y

function bo_status_add(status, s, x)
  local sy = bo_y_at_x(s, x)
  local pos = #status + 1
  for i = 1, #status do
    if sy < bo_y_at_x(status[i], x) then
      pos = i
      break
    end
  end
  table.insert(status, pos, s)
  return pos
end

-- Remove segment from status

function bo_status_rm(status, s)
  for i = 1, #status do
    if status[i] == s then
      table.remove(status, i)
      return 
    end
  end
end

-- Find position of segment in status

function bo_status_pos(status, s)
  for i = 1, #status do
    if status[i] == s then
      return i
    end
  end
  return nil
end

-- Sweep state

bo_q = { }
bo_sweep_x = 0

-- Check pair for intersection, add event

function bo_check_pair(a, b)
  if not a or not b then
    return 
  end
  if bo_shared_ep(a, b) then
    return 
  end
  local ix, iy = bo_intersect(a, b)
  if not ix or ix < bo_sweep_x - BO_EPS then
    return 
  end
  bo_ev_insert(bo_q, bo_cross_ev(ix, iy, a, b))
end

-- Check segment against all status below pos

function bo_check_below(s, status, pos)
  for i = pos - 1, 1, -1 do
    bo_check_pair(s, status[i])
  end
end

-- Check segment against all status above pos

function bo_check_above(s, status, pos)
  for i = pos + 1, #status do
    bo_check_pair(s, status[i])
  end
end

-- Handle left-endpoint event

function bo_handle_left(ev, status)
  local s = ev.seg
  local pos = bo_status_add(status, s, ev.x)
  bo_check_below(s, status, pos)
  bo_check_above(s, status, pos)
end

-- Handle right-endpoint event

function bo_handle_right(ev, status)
  local s = ev.seg
  local pos = bo_status_pos(status, s)
  if not pos then
    return 
  end
  local above = status[pos - 1]
  local below = status[pos + 1]
  bo_status_rm(status, s)
  bo_check_pair(above, below)
end

-- Swap and check new neighbors

function bo_do_swap(ctx, pa, pb)
  local st = ctx.status
  st[pa], st[pb] = st[pb], st[pa]
  local lo = math.min(pa, pb)
  local hi = math.max(pa, pb)
  bo_check_below(st[lo], st, lo)
  bo_check_above(st[hi], st, hi)
end

-- Crossing key for dedup

function bo_cross_key(sa, sb)
  local lo = math.min(sa[5], sb[5])
  local hi = math.max(sa[5], sb[5])
  return lo * KEY_MULT + hi
end

-- Build crossing record

function bo_make_xpt(ev)
  return {
    ev.x,
    ev.y,
    ev.sa[5],
    ev.sb[5]
  }
end

-- Record crossing if not duplicate

function bo_record_cross(ev, ctx)
  local key = bo_cross_key(ev.sa, ev.sb)
  if ctx.seen[key] then
    return false
  end
  ctx.seen[key] = true
  ctx.xpts[#ctx.xpts + 1] = bo_make_xpt(ev)
  return true
end

-- Handle crossing event

function bo_handle_cross(ev, ctx)
  if not bo_record_cross(ev, ctx) then
    return 
  end
  local pa = bo_status_pos(ctx.status, ev.sa)
  local pb = bo_status_pos(ctx.status, ev.sb)
  if not pa or not pb then
    return 
  end
  bo_do_swap(ctx, pa, pb)
end

-- Dispatch event handler

BO_HANDLER = { }
BO_HANDLER[BO_LEFT] = bo_handle_left
BO_HANDLER[BO_RIGHT] = bo_handle_right

-- Main sweep loop

function bo_sweep_loop(ctx)
  while 0 < #ctx.q do
    local ev = table.remove(ctx.q, 1)
    bo_sweep_x = ev.x
    if ev.kind == BO_CROSS then
      bo_handle_cross(ev, ctx)
    else
      BO_HANDLER[ev.kind](ev, ctx.status)
    end
  end
end

-- Run Bentley-Ottmann sweep

function bo_sweep(segs)
  local ctx = { }
  ctx.q = bo_init_events(segs)
  bo_q = ctx.q
  ctx.status = { }
  ctx.xpts = { }
  ctx.seen = { }
  bo_sweep_x = 0
  bo_sweep_loop(ctx)
  return ctx.xpts
end

-- Detect self-intersections in flat polygon

function bo_has_selfx(pts, n)
  if n < MIN_SELFX then
    return false
  end
  local segs = bo_make_segs(pts, n)
  local xpts = bo_sweep(segs)
  return 0 < #xpts
end

-- Count self-intersection points

function bo_count_selfx(pts, n)
  if n < MIN_SELFX then
    return 0
  end
  local segs = bo_make_segs(pts, n)
  local xpts = bo_sweep(segs)
  return #xpts
end

-- Polygon decomposition at intersection points

-- Insert intersection point into edge list

function bo_split_edge(edges, ei, ix, iy)
  local e = edges[ei]
  local new_e = {
    ix,
    iy,
    e[3],
    e[4],
    e[5]
  }
  e[3], e[4] = ix, iy
  table.insert(edges, ei + 1, new_e)
end

-- Check if point is strictly interior to edge

function bo_pt_on_edge(e, px, py)
  local dx = e[3] - e[1]
  local dy = e[4] - e[2]
  local len_sq = dx * dx + dy * dy
  if len_sq < BO_EPS then
    return false
  end
  local dpx, dpy = px - e[1], py - e[2]
  local t = (dpx * dx + dpy * dy) / len_sq
  return BO_T_EPS < t and t < 1 - BO_T_EPS
end

-- Find edge by original index and split it

function bo_find_and_split(edges, orig_idx, ix, iy)
  for i = 1, #edges do
    if edges[i][5] == orig_idx then
      if bo_pt_on_edge(edges[i], ix, iy) then
        bo_split_edge(edges, i, ix, iy)
        return 
      end
    end
  end
end

-- Insert one intersection into matching edges

function bo_insert_one_xpt(edges, xp)
  local ix, iy = xp[1], xp[2]
  bo_find_and_split(edges, xp[3], ix, iy)
  bo_find_and_split(edges, xp[4], ix, iy)
end

-- Insert all intersection points into edges

function bo_insert_xpts(edges, xpts)
  for _, xp in ipairs(xpts) do
    bo_insert_one_xpt(edges, xp)
  end
end

-- Collect vertices from flat coords

function bo_collect_verts(pts, n)
  local verts = { }
  local nv = n / PAIR
  for i = 1, nv do
    verts[i] = {
      pts[i * PAIR - 1],
      pts[i * PAIR]
    }
  end
  return verts
end

-- Build one edge from vertex pair

function bo_make_edge(verts, i, i2)
  return {
    verts[i][1],
    verts[i][2],
    verts[i2][1],
    verts[i2][2],
    i
  }
end

-- Build edge list from vertex list

function bo_collect_edges(verts)
  local edges = { }
  local nv = #verts
  for i = 1, nv do
    local i2 = (i % nv) + 1
    edges[i] = bo_make_edge(verts, i, i2)
  end
  return edges
end

-- Rebuild ordered vertex list from edges

function bo_rebuild_verts(edges)
  local verts = { }
  for _, e in ipairs(edges) do
    verts[#verts + 1] = { e[1], e[2] }
  end
  return verts
end

-- Build vertex graph from edges with crossings

function bo_build_graph(pts, n, xpts)
  local verts = bo_collect_verts(pts, n)
  local edges = bo_collect_edges(verts)
  bo_insert_xpts(edges, xpts)
  return bo_rebuild_verts(edges)
end

-- Planar graph face extraction

-- Snap vertex to grid for identity

function bo_snap(v)
  local kx = math.floor(v[1] / BO_SNAP + 0.5)
  local ky = math.floor(v[2] / BO_SNAP + 0.5)
  return kx * BO_SNAP, ky * BO_SNAP
end

-- Vertex key from snapped coordinates

function bo_vkey(v)
  local sx, sy = bo_snap(v)
  return sx .. "," .. sy
end

-- Ensure adjacency node exists

function bo_ensure_node(adj, key, vert)
  if not adj[key] then
    adj[key] = {
      v = vert,
      out = { }
    }
  end
end

-- Add one directed edge to node's out-list

function bo_add_directed(adj, key, tgt_key, tgt_v)
  local out = adj[key].out
  out[#out + 1] = {
    key = tgt_key,
    v = tgt_v,
    used = false
  }
end

-- Add directed edge pair to adjacency

function bo_add_edge_pair(adj, vi, vj)
  local ki = bo_vkey(vi)
  local kj = bo_vkey(vj)
  bo_ensure_node(adj, ki, vi)
  bo_ensure_node(adj, kj, vj)
  bo_add_directed(adj, ki, kj, vj)
  bo_add_directed(adj, kj, ki, vi)
end

-- Build adjacency from vertex list

function bo_build_adj(verts)
  local adj = { }
  local nv = #verts
  for i = 1, nv do
    local i2 = (i % nv) + 1
    bo_add_edge_pair(adj, verts[i], verts[i2])
  end
  return adj
end

-- Angle of edge from node to target

function bo_edge_angle(from, to)
  local dx = to[1] - from[1]
  local dy = to[2] - from[2]
  return math.atan2(dy, dx)
end

-- Sort one node's out-edges by angle

function bo_sort_out(node)
  local v = node.v
  table.sort(node.out, function(a, b)
    local aa = bo_edge_angle(v, a.v)
    local ab = bo_edge_angle(v, b.v)
    return aa < ab
  end)
end

-- Sort all adjacency out-edges by angle

function bo_sort_adj(adj)
  for _, node in pairs(adj) do
    bo_sort_out(node)
  end
end

-- Normalize angle to [0, 2*pi)

function bo_norm_angle(a)
  a = a % TWO_PI
  if a < 0 then
    a = a + TWO_PI
  end
  return a
end

-- Pick first unused edge CCW after rev angle

function bo_pick_ccw(node, rev)
  local best = nil
  local best_da = TWO_PI + 1
  for _, e in ipairs(node.out) do
    if not e.used then
      local ea = bo_edge_angle(node.v, e.v)
      local da = bo_norm_angle(ea - rev)
      if BO_EPS < da and da < best_da then
        best = e
        best_da = da
      end
    end
  end
  return best
end

-- Find next half-edge: first CCW from reverse

function bo_next_edge(adj, from_key, arr)
  local node = adj[from_key]
  if not node then
    return nil
  end
  local rev = bo_norm_angle(arr + math.pi)
  return bo_pick_ccw(node, rev)
end

-- Begin face trace: consume first edge

function bo_trace_face(adj, start_key, edge, n)
  edge.used = true
  local node = adj[start_key]
  local arr = bo_edge_angle(node.v, edge.v)
  local st = { }
  st.adj = adj
  st.start = start_key
  st.face = { node.v }
  st.limit = n
  return bo_trace_rest(st, edge.key, arr)
end

-- Continue tracing until face closes

function bo_trace_rest(st, cur_key, arr)
  for step = 1, st.limit do
    if cur_key == st.start then
      return st.face
    end
    local e = bo_next_edge(st.adj, cur_key, arr)
    if not e or e.used then
      return st.face
    end
    e.used = true
    st.face[#st.face + 1] = st.adj[cur_key].v
    arr = bo_edge_angle(st.adj[cur_key].v, e.v)
    cur_key = e.key
  end
  return st.face
end

-- Count nodes in adjacency graph

function bo_adj_size(adj)
  local n = 0
  for _ in pairs(adj) do
    n = n + 1
  end
  return n
end

-- Extract all faces from planar graph

function bo_extract_faces(adj)
  local faces = { }
  local n = bo_adj_size(adj)
  for key, node in pairs(adj) do
    for _, e in ipairs(node.out) do
      if not e.used then
        local f = bo_trace_face(adj, key, e, n)
        if 2 < #f then
          faces[#faces + 1] = f
        end
      end
    end
  end
  return faces
end

-- Convert face (vertex list) to flat coords

function bo_face_to_flat(face)
  local pts = { }
  for _, v in ipairs(face) do
    pts[#pts + 1] = v[1]
    pts[#pts + 1] = v[2]
  end
  return pts
end

-- Signed area shoelace step

function bo_area_step(pts, i, i2)
  local x1 = pts[i * PAIR - 1]
  local y1 = pts[i * PAIR]
  local x2 = pts[i2 * PAIR - 1]
  local y2 = pts[i2 * PAIR]
  return x1 * y2 - x2 * y1
end

-- Signed area of polygon 

function bo_signed_area(pts)
  local n = #pts / PAIR
  local area = 0
  for i = 1, n do
    area = area + bo_area_step(pts, i, (i % n) + 1)
  end
  return area * 0.5
end

-- Build face record from vertex list

function bo_face_record(face)
  local pts = bo_face_to_flat(face)
  local area = bo_signed_area(pts)
  return { pts = pts, area = area }
end

-- Measure faces and find outer boundary

function bo_measure_faces(faces)
  local all = { }
  local max_a, max_i = -1, 0
  for i, face in ipairs(faces) do
    all[i] = bo_face_record(face)
    if math.abs(all[i].area) > max_a then
      max_a = math.abs(all[i].area)
      max_i = i
    end
  end
  return all, max_i
end

-- Collect all faces except the outer boundary

function bo_collect_interior(all, outer_idx)
  local kept = { }
  for i, f in ipairs(all) do
    if i ~= outer_idx then
      kept[#kept + 1] = f.pts
    end
  end
  return kept
end

-- Filter faces: keep interior, drop outer

function bo_filter_faces(faces)
  local all, outer = bo_measure_faces(faces)
  return bo_collect_interior(all, outer)
end

-- Decompose self-intersecting polygon

function bo_decompose(pts, n)
  local segs = bo_make_segs(pts, n)
  local xpts = bo_sweep(segs)
  if #xpts == 0 then
    return { pts }
  end
  local verts = bo_build_graph(pts, n, xpts)
  local adj = bo_build_adj(verts)
  bo_sort_adj(adj)
  local faces = bo_extract_faces(adj)
  return bo_filter_faces(faces)
end

-- Cross product at vertex i for convexity

function bo_cross_at(pts, i, n)
  local i2 = (i % n) + 1
  local i3 = (i2 % n) + 1
  local ax = pts[i2 * PAIR - 1] - pts[i * PAIR - 1]
  local ay = pts[i2 * PAIR] - pts[i * PAIR]
  local bx = pts[i3 * PAIR - 1] - pts[i2 * PAIR - 1]
  local by = pts[i3 * PAIR] - pts[i2 * PAIR]
  return ax * by - ay * bx
end

-- Check sign consistency for convexity

function bo_check_csign(cp, sign)
  if cp == 0 then
    return true
  end
  if sign == 0 then
    return true
  end
  return (0 < sign) == (0 < cp)
end

-- Update convexity sign accumulator

function bo_update_sign(cp, sign)
  if cp ~= 0 and sign == 0 then
    return cp
  end
  return sign
end

-- Check polygon convexity

function bo_is_convex(pts)
  local n = #pts / PAIR
  if n < MIN_VERTS then
    return true
  end
  local sign = 0
  for i = 1, n do
    local cp = bo_cross_at(pts, i, n)
    if not bo_check_csign(cp, sign) then
      return false
    end
    sign = bo_update_sign(cp, sign)
  end
  return true
end

-- Decompose + classify each sub-polygon

function bo_decompose_classified(pts, n)
  local polys = bo_decompose(pts, n)
  local result = { }
  for _, poly in ipairs(polys) do
    result[#result + 1] = {
      pts = poly,
      convex = bo_is_convex(poly)
    }
  end
  return result
end
