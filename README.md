# SVG to LÖVE Transpiler

Converts SVG vector images into Lua source that draws
the same image using love.graphics primitives.

## Requirements

Lua 5.1 on the desktop for running the transpiler.
LÖVE2D (Compy) for running the output files.

## Usage

### Transpile

Place `transpile.lua`, `svgxml.lua`, `svgpath.lua`,
`bentley_ottmann.lua` and your SVG file in the same
directory. Run:

    lua transpile.lua input.svg output.lua 800 480

Arguments:

- `input.svg` — source SVG file (required)
- `output.lua` — output file (default: `input.lua`)
- `800` — target width (default: 800)
- `480` — target height (default: 480)

Coordinates are scaled at transpile time to fit the
target size. The scale factor is computed from the
SVG viewBox attribute: `min(w/vw, h/vh)`.

### Run on Compy

Place the generated Lua file in a Compy project.
The platform loads the runtime libraries
automatically. From the console:

    project("svg")
    dofile("city-car.lua")

## Files

### Transpiler (desktop)

- `transpile.lua` — main script, reads SVG, generates
  Lua with coordinates pre-scaled to target size
- `svgxml.lua` — XML parser, preserves element order
- `svgpath.lua` — SVG path parser, converts arcs to
  cubics
- `bentley_ottmann.lua` — self-intersection detection
  and polygon decomposition (shared with runtime)

### Runtime (Compy)

- `bezier.lua` — cubic Bezier polygonization via
  de Casteljau subdivision, flattens path commands
  into coordinate arrays
- `shape2d.lua` — 2D shape rendering, fills and
  strokes paths using flattened coordinates from
  bezier.lua and decomposition from
  bentley_ottmann.lua
- `bentley_ottmann.lua` — Bentley-Ottmann sweep line
  for self-intersection detection and polygon
  decomposition (shared with transpiler)

## compy.graphics.shape2d API

All public symbols are in the
`compy.graphics.shape2d` table on the platform.
Generated Lua files assign frequently used functions
to locals in their preamble for efficiency.

### bezier.lua

`compy.graphics.shape2d.flatten_path(path)` — Flatten a path
(array of command tables) into a coordinate array
via de Casteljau subdivision of cubic Bezier curves.
Returns a new flat coordinate array and its length.
Pure polygonization, no caching.

Path command format:

    { "M", x, y } — move to
    { "L", x, y } — line to
    { "C", x1,y1, x2,y2, x,y } — cubic Bezier
    { "Z" } — close path

### shape2d.lua

`compy.graphics.shape2d.convex_fill(path)` — Fill a convex
polygon. Flattens the path (cached) and draws with
love.graphics.polygon directly. No triangulation.

`compy.graphics.shape2d.concave_fill(path)` — Fill a concave
(non-convex, non-self-intersecting) polygon.
Flattens the path, triangulates via
love.math.triangulate, caches the triangulation
for subsequent frames.

`compy.graphics.shape2d.selfx_fill(path)` — Fill a
self-intersecting polygon. Flattens the path,
decomposes into simple sub-polygons via
Bentley-Ottmann sweep line, classifies each as
convex or concave, fills each independently.
Decomposition cached for subsequent frames.

`compy.graphics.shape2d.bezier_stroke(path)` — Stroke a
path as a polyline. Flattens the path and draws
with love.graphics.line.

### bentley_ottmann.lua

`compy.graphics.shape2d.bo_is_convex(pts)` — Check whether
a polygon (flat coordinate array) is convex. Returns
true if all interior angles have the same sign.

`compy.graphics.shape2d.bo_count_selfx(pts, n)` — Count
self-intersection points in a polygon. pts is a flat
coordinate array, n is its length. Returns the
number of edge-edge crossings found by
Bentley-Ottmann sweep.

`compy.graphics.shape2d.bo_decompose_classified(pts, n)` —
Decompose a self-intersecting polygon into simple
sub-polygons. Returns an array of tables, each with
fields pts (flat coordinate array) and convex
(boolean). Uses Bentley-Ottmann sweep to find
crossings, builds a planar graph, extracts interior
faces via CCW half-edge tracing.

## Path Classification

Each subpath is classified at transpile time into
one of three categories:

- **convex** — all interior angles < 180 degrees,
  no self-intersection. Filled with
  love.graphics.polygon directly.
- **concave** — non-convex but no self-intersection.
  Triangulated via love.math.triangulate once on
  first frame, cached for subsequent frames.
- **selfx** — self-intersecting path with 2 or more
  edge crossings. Decomposed into simple sub-polygons
  via Bentley-Ottmann sweep line, then each filled
  as convex or concave. Paths with a single crossing
  are classified as concave since triangulation
  handles them correctly.

## Runtime Optimization

All paths: flatten once on first frame, cached in
get_flat.

Convex paths: love.graphics.polygon directly, no
triangulation.

Concave paths: love.math.triangulate once on first
frame, cached.

Self-intersecting paths: Bentley-Ottmann decompose
once on first frame, cached. Each sub-polygon filled
with the appropriate method.

## Supported SVG Elements

- `path` (M, L, H, V, C, S, A, Z — absolute and
  relative)
- `rect` (with optional rx/ry for rounded corners)
- `circle`
- `ellipse`
- `polygon`
- `line`
- `g` (groups, nested)
- `linearGradient` — averaged to solid color
- `viewBox` — scaled at transpile time
- `fill-rule` — evenodd via stencil (nonzero treated
  as evenodd)

## Supported CSS and Styling

- `<style>` blocks in `<defs>` with class selectors
  (e.g. `.fil0 {fill:#F08466}`)
- `class` attribute on elements, multiple classes
- `fill`, `fill-opacity`, `fill-rule` from CSS
- `stroke`, `stroke-width` from CSS
- Named SVG colors: white, black, red, green, blue,
  lime, yellow, cyan
- Hex colors: 3-char and 6-char 

## Transforms

- `transform="matrix(a,b,c,d,e,f)"` on `rect` and
  `ellipse` elements. The element is sampled into
  a polygon, transformed, and emitted as
  `gfx.polygon`. Rounded rects are sampled along
  their corner arcs.

## Not Supported

- `text`, `image`, `use`, `clipPath`, `mask`
- `stroke-dasharray`, `opacity` (element-level)
- `transform` on `path`, `g`, or other elements
- `rgb()` color syntax
- CSS selectors other than class (id, tag, etc.)

## Examples

Test SVG files included:

- `city-car.svg` — single path with many subpaths
- `sailboat-silhouette.svg` — multiple filled paths
- `lego-man2x.svg` — paths, rects, circles, polygons,
  gradients
- `pentagram-selfx.svg` — five-pointed star drawn as
  a single self-intersecting polygon (5 vertices,
  5 edge crossings). Demonstrates Bentley-Ottmann
  decomposition.
- `bowtie.svg` — self-intersecting quadrilateral
  (4 vertices, 1 crossing). Handled as concave.
- `double-bowtie.svg` — 5-vertex polygon with
  2 edge crossings. Demonstrates Bentley-Ottmann
  decomposition with minimal crossing count.
