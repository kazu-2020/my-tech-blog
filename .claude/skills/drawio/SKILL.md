---
name: drawio
description: Always use when user asks to create, generate, draw, or design a diagram, flowchart, architecture diagram, ER diagram, sequence diagram, class diagram, network diagram, mockup, wireframe, or UI sketch, or mentions draw.io, drawio, drawoi, .drawio files, or diagram export to PNG/SVG/PDF.
---

# Draw.io Diagram Skill

Generate diagrams as native `.drawio` files (mxGraphModel XML), optionally exported to PNG/SVG/PDF with the XML embedded so the export stays editable in draw.io.

Written for macOS. On another platform only the CLI path and the open command differ — the rest applies unchanged.

## Workflow

1. Write the mxGraphModel XML to `<descriptive-name>.drawio` in the current working directory. Name it after the diagram content, lowercase with hyphens: `login-flow`, `database-schema`.
2. If `npx @drawio/postprocess` is available, run it on the file to clean up edge routing. Skip silently if it isn't — don't install it or ask about it.
3. If the user asked for png / svg / pdf, export it (below), then delete the source `.drawio` — the export carries the full XML.
4. Open the result with `open <file>`. If that fails, print the absolute path so the user can open it manually.

With no format mentioned, stop at the `.drawio` file. The user can ask to export later.

## Exporting

The CLI ships with the desktop app at `/Applications/draw.io.app/Contents/MacOS/draw.io`. Check `which drawio` first in case it's already on PATH.

```bash
drawio -x -f png -e -b 10 -o login-flow.drawio.png login-flow.drawio
```

`-e` embeds the diagram XML, which png, svg, and pdf all support. That's what the double extension in `name.drawio.png` signals: the file is a picture *and* still an editable diagram. jpg can't embed anything, so avoid it unless the user asks for jpg specifically.

Other flags worth knowing: `-t` transparent background (png only), `-s` scale, `--width` / `--height` to fit a size, `-a` all pages (pdf), `-p` page index.

If the CLI isn't installed, keep the `.drawio` file and tell the user they can install the draw.io desktop app to enable export, or open the file directly.

## XML

Every diagram needs this skeleton. Cell `0` is the root layer and cell `1` the default parent; everything you draw hangs off `parent="1"`.

```xml
<mxGraphModel adaptiveColors="auto">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
  </root>
</mxGraphModel>
```

Generate this XML directly. Mermaid and CSV need server-side conversion and can't be written as native files.

For styles, edge routing, containers, layers, metadata, and dark-mode colors, fetch and follow:
https://raw.githubusercontent.com/jgraph/drawio-mcp/main/shared/xml-reference.md

### Failure modes worth avoiding up front

These produce a file that looks fine until it's opened, so they're cheap to prevent and annoying to debug.

- **No XML comments.** They serve no purpose in generated diagram XML, and a `--` inside one makes the whole file unparseable. Pure downside.
- Escape `&amp;` `&lt;` `&gt;` `&quot;` in attribute values, and keep every `mxCell` id unique.
- Give every edge a child `<mxGeometry relative="1" as="geometry" />`. A self-closing edge cell renders as nothing at all.
- A diagram that opens blank is almost always missing the `0` / `1` root cells; an empty or corrupt export means the XML wasn't well-formed.
