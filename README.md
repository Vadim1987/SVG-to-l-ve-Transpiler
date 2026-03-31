# SVG to LÖVE Transpiler

Converts SVG vector images into Lua source that draws
the same image using love.graphics primitives.

## Requirements

Lua 5.1 on the desktop for running the transpiler.
LÖVE2D (Compy) for running the output files.

## Usage

### Transpile

Place `transpile.lua`, `svgxml.lua`, `svgpath.lua` and
your SVG file in the same directory. Run:

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

Place `bezier.lua` and the generated Lua file in a
Compy project. From the console:

    project("svg")
    dofile("city-car.lua")

## Files

### Transpiler (desktop)

- `transpile.lua` — main script, reads SVG, generates
  Lua with coordinates pre-scaled to target size
- `svgxml.lua` — XML parser, preserves element order
- `svgpath.lua` — SVG path parser, converts arcs to
  cubics

### Runtime (Compy)

- `bezier.lua` — renders paths with love.graphics,
  approximates cubic Bezier at draw time via
  de Casteljau subdivision, caches flattened
  coordinates and triangulation between frames,
  uses stencil for evenodd fill rule

## Runtime Optimization

Convexity is checked at transpile time. Each subpath
is tagged as convex or concave in the generated code.

- Convex paths: `gfx.polygon` directly, no
  triangulation
- Concave paths: `love.math.triangulate` once on
  first frame, cached for subsequent frames
- All paths: flatten once on first frame, cached in
  `flat_cache`

## Bezier API

The generated Lua files call these functions from
`bezier.lua`:

    convex_fill(subpath) — draw convex polygon
    concave_fill(subpath) — triangulate + draw
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
- `fill-rule` — always evenodd

## Not Supported

- `fill-rule="nonzero"`
- `text`, `image`, `use`, `clipPath`, `mask`
- `stroke-dasharray`, `opacity`
- `transform` on elements
- CSS styling, `style` attribute

## Examples

Three example SVG files for testing:

- `city-car.svg` — single path with many subpaths
- `sailboat-silhouette.svg` — multiple filled paths
- `lego-man2x.svg` — paths, rects, circles, polygons,
  gradients
