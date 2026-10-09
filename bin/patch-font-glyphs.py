"""Copy missing glyphs from a symbol font into a monospaced TTF.

Usage:
    guix shell python python-fonttools -- \
        python3 -I bin/patch-font-glyphs.py TARGET.ttf SOURCE.ttf OUT.ttf CODEPOINT...

Each copied glyph is decomposed, scaled to the target's units-per-em,
and centred in the target's monospace advance width.

system/fonts/CascadiaMonoNF-Regular-patched.ttf was built with:
    TARGET  ttf/static/CascadiaMonoNF-Regular.ttf from Cascadia Code v2407.24
    SOURCE  NotoSansSymbols2-Regular.ttf (hinted ttf, notofonts)
    CODEPOINTS  23F4 23F5 23F6 23F7  (the ⏵⏵ in Claude Code's mode line)
Install it in Termux as ~/.termux/font.ttf, then run termux-reload-settings.
"""

import sys

from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


def copy_glyph(target, source, codepoint, advance_width):
    """Draw SOURCE's glyph for CODEPOINT into TARGET, scaled and centred."""
    source_name = source.getBestCmap()[codepoint]
    source_glyphs = source.getGlyphSet()
    scale = target["head"].unitsPerEm / source["head"].unitsPerEm

    # Measure the source outline so we can centre it horizontally.
    probe = TTGlyphPen(source_glyphs)
    source_glyphs[source_name].draw(probe)
    probe_glyph = probe.glyph()
    probe_glyph.recalcBounds(None)
    outline_width = (probe_glyph.xMax - probe_glyph.xMin) * scale
    x_offset = (advance_width - outline_width) / 2 - probe_glyph.xMin * scale

    pen = TTGlyphPen(None)
    source_glyphs[source_name].draw(
        TransformPen(pen, (scale, 0, 0, scale, x_offset, 0)))
    glyph = pen.glyph()
    glyph.recalcBounds(None)

    new_name = f"uni{codepoint:04X}"
    target.setGlyphOrder(target.getGlyphOrder() + [new_name])
    target["glyf"][new_name] = glyph
    target["hmtx"][new_name] = (advance_width, glyph.xMin)
    for subtable in target["cmap"].tables:
        if subtable.isUnicode():
            subtable.cmap[codepoint] = new_name


def main(target_path, source_path, out_path, *codepoints):
    """Patch every requested codepoint the target lacks and save OUT."""
    target, source = TTFont(target_path), TTFont(source_path)
    advance_width = target["hmtx"][target.getBestCmap()[ord("M")]][0]
    existing = target.getBestCmap()
    source_cmap = source.getBestCmap()
    for codepoint in (int(c, 16) for c in codepoints):
        if codepoint in existing:
            print(f"U+{codepoint:04X} already present, skipping")
        elif codepoint not in source_cmap:
            print(f"U+{codepoint:04X} missing from source, skipping")
        else:
            copy_glyph(target, source, codepoint, advance_width)
            print(f"U+{codepoint:04X} added")
    for stale_table in ("hdmx", "LTSH", "VDMX"):
        if stale_table in target:
            del target[stale_table]
    target.save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:])
