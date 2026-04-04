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

Place `bezier.lua`, `bentley_ottmann.lua` and the
generated Lua file in a Compy project. From the
console:

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
  via Bentley-Ottmann sweep line algorithm, polygon
  decomposition (shared with runtime)

### Runtime (Compy)

- `bezier.lua` — renders paths with love.graphics,
  approximates cubic Bezier at draw time via
  de Casteljau subdivision, caches flattened
  coordinates and triangulation between frames
- `bentley_ottmann.lua` — decomposes self-intersecting
  polygons into simple sub-polygons at runtime
  (shared with transpiler)

## Path Classification

Each subpath is classified at transpile time into
one of three categories:

- **convex** — all interior angles < 180 degrees,
  no self-intersection. Filled with
  `gfx.polygon` directly.
- **concave** — non-convex but no self-intersection.
  Triangulated via `love.math.triangulate` once on
  first frame, cached for subsequent frames.
- **selfx** — self-intersecting path (edges cross
  each other). Decomposed into simple sub-polygons
  via Bentley-Ottmann sweep line and planar graph
  face extraction, then each sub-polygon filled as
  convex or concave.

### Self-Intersection Handling

Self-intersecting paths (e.g. bowtie shapes, star
polygons) are detected at transpile time using the
Bentley-Ottmann sweep line algorithm. The generated
code calls `selfx_fill()` which at runtime:

1. Flattens the path (cached in `flat_cache`)
2. Runs Bentley-Ottmann sweep to find all
   edge-edge intersections
3. Builds a planar graph with intersection vertices
4. Extracts interior faces via CCW half-edge tracing
5. Classifies each face as convex or concave
6. Fills each face independently (cached in
   `selfx_cache`)

## Runtime Optimization

All paths: flatten once on first frame, cached in
`flat_cache`.

Convex paths: `gfx.polygon` directly, no
triangulation.

Concave paths: `love.math.triangulate` once on
first frame, cached in `tri_cache`.

Self-intersecting paths: Bentley-Ottmann decompose
once on first frame, cached in `selfx_cache`. Each
sub-polygon filled with the appropriate method.

## Bezier API

The generated Lua files call these functions from
`bezier.lua` and `bentley_ottmann.lua`:

    convex_fill(subpath) — draw convex polygon
    concave_fill(subpath) — triangulate + draw
    selfx_fill(subpath) — decompose + draw
    bezier_stroke(subpath) — stroke path as line

Each subpath is an array of commands:

    { "M", x, y } — move to
    { "L", x, y } — line to
    { "C", x1,y1, x2,y2, x,y } — cubic Bezier
    { "Z" } — close path

## Supported SVG Elements

- `path` (M, L, H, V, C, S, A, Z — absolute and
  relative)
- `rect`
- `circle`
- `polygon`
- `g` (groups, nested)
- `linearGradient` — averaged to solid color
- `viewBox` — scaled at transpile time
- `fill - rule` — always evenodd

## Not Supported

- `fill-rule = "nonzero"`
- `text`, `image`, `use`, `clipPath`, `mask`
- `stroke-dasharray`, `opacity`
- `transform` on elements
- `style` attribute, inline CSS
- `rgb()` color syntax, CSS system colors

## Examples

Test SVG files included:

- `city-car.svg` — single path with many subpaths
- `sailboat-silhouette.svg` — multiple filled paths
- `lego-man2x.svg` — paths, rects, circles, polygons,
  gradients. Contains 3 self-intersecting subpaths
  correctly handled by Bentley-Ottmann decomposition.
- `pentagram-selfx.svg` — five-pointed star drawn as
  a single self-intersecting polygon (5 vertices,
  5 edge crossings). Demonstrates Bentley-Ottmann
  decomposition into 6 simple sub-polygons for
  correct evenodd fill rendering.
  