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

    lua5.1 transpile.lua input.svg output.lua

If output path is omitted, writes to `input.lua`.

### Run on Compy

Place `bezier.lua` and the generated Lua file in a
Compy project. From the console:

    project("svg")
    dofile("city-car.lua")

## Files

### Transpiler (desktop)

- `transpile.lua` — main script, reads SVG, generates Lua
- `svgxml.lua` — XML parser, preserves element order
- `svgpath.lua` — SVG path parser, converts arcs to cubics

### Runtime (Compy)

- `bezier.lua` — renders paths with love.graphics,
  approximates cubic Bezier at draw time via
  de Casteljau subdivision, triangulates concave
  polygons, uses stencil for evenodd fill rule

## Bezier API

The generated Lua files call two functions:

    bezier.fill(subpaths)
    bezier.stroke(subpaths)

`subpaths` is an array of subpaths. Each subpath is an
array of commands. Each command is a table:

    { "M", x, y }              — move to
    { "L", x, y }              — line to
    { "C", x1,y1, x2,y2, x,y } — cubic Bezier
    { "Z" }                    — close path

Example:

    local p = {
      {
        { "M", 10, 20 },
        { "L", 30, 40 },
        { "C", 50, 60, 70, 80, 90, 100 },
        { "Z" },
      },
    }
    bezier.fill(p)

For paths with multiple subpaths (holes, cutouts),
bezier.fill uses stencil with evenodd rule.

## Supported SVG Elements

- `path` (M, L, H, V, C, S, A, Z — absolute and
  relative)
- `rect`
- `circle`
- `polygon`
- `g` (groups, nested)
- `linearGradient` — averaged to solid color
- `viewBox` — scaled to fit window
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
  