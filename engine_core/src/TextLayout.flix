// TextLayout — pure functions for text layout calculations

mod TextLayout {

    /// Convert a Char to its unsigned Unicode codepoint.
    /// Flix's Char.toBmpCodePoint returns signed Int32, so chars >= U+8000
    /// become negative. This function masks to 16-bit unsigned.
    pub def charToCodePoint(ch: Char): Int32 =
        Int32.bitwiseAnd(Char.toBmpCodePoint(ch), 0xFFFF)

    /// Line height multiplier (1.2x font size, standard for single-spaced text).
    pub def lineHeightMultiplier(): Float64 = 1.2

    /// Calculate the horizontal offset for centering single-line text.
    pub def centerOffset(totalAdvance: Float64, scale: Float64): Float64 =
        -1.0 * totalAdvance * scale / 2.0

    /// Sum of glyph advances (total text width in bake-scale units).
    pub def totalAdvance(advances: List[Float64]): Float64 =
        List.foldLeft((acc, a) -> acc + a, 0.0, advances)

    /// Split text into lines at newline characters (codepoint 10).
    pub def splitLines(text: String): List[List[Char]] =
        let chars = String.toList(text);
        let result = List.foldLeft((acc, ch) -> {
            if (Char.toBmpCodePoint(ch) == 10)
                {lines = List.reverse(acc#current) :: acc#lines, current = (Nil: List[Char])}
            else
                {lines = acc#lines, current = ch :: acc#current}
        }, {lines = (Nil: List[List[Char]]), current = (Nil: List[Char])}, chars);
        List.reverse(List.reverse(result#current) :: result#lines)

    /// Compute pen positions for each character with word-wrap support.
    pub def layoutPositions(advances: List[Float64], wrapWidth: Float64,
                            scale: Float64, lineHeight: Float64): List[(Float64, Float64)] =
        if (wrapWidth <= 0.0) {
            let result = List.foldLeft((acc, adv) -> {
                let penX = acc#penX;
                {positions = (penX, 0.0) :: acc#positions, penX = penX + adv}
            }, {positions = (Nil: List[(Float64, Float64)]), penX = 0.0}, advances);
            List.reverse(result#positions)
        } else {
            let result = List.foldLeft((acc, adv) -> {
                let penX = acc#penX;
                let penY = acc#penY;
                let nextX = penX + adv;
                let px = if (penX > 0.0 and nextX * scale > wrapWidth) 0.0 else penX;
                let py = if (penX > 0.0 and nextX * scale > wrapWidth) penY + lineHeight else penY;
                {positions = (px, py) :: acc#positions, penX = px + adv, penY = py}
            }, {positions = (Nil: List[(Float64, Float64)]), penX = 0.0, penY = 0.0}, advances);
            List.reverse(result#positions)
        }

    /// Glyph metrics and atlas UV coordinates.
    pub type alias GlyphMetrics = {
        xOff = Float64, yOff = Float64,
        glyphW = Float64, glyphH = Float64,
        advance = Float64,
        s0 = Float64, t0 = Float64, s1 = Float64, t1 = Float64
    }

    /// Screen-space quad bounds for a single glyph.
    pub type alias QuadBounds = {
        x0 = Float64, y0 = Float64, x1 = Float64, y1 = Float64
    }

    /// Calculate screen-space quad bounds for a glyph at a given pen position.
    /// penPos: (penX, penY) in bake-scale coordinates from layoutPositions
    /// glyph: glyph metrics (xOff, yOff, glyphW, glyphH)
    /// scale: fontSize / fontBakeSize
    /// basePos: label's screen position
    /// offsetX: centering offset (0 if not centered)
    pub def glyphQuadBounds(penPos: (Float64, Float64), glyph: GlyphMetrics,
                            scale: Float64, basePos: Vec2.Vec2,
                            offsetX: Float64): QuadBounds =
        let (penX, penY) = penPos;
        let x0 = (penX + glyph#xOff) * scale + basePos#x + offsetX;
        let y0 = (penY + glyph#yOff) * scale + basePos#y;
        let x1 = x0 + glyph#glyphW * scale;
        let y1 = y0 + glyph#glyphH * scale;
        {x0 = x0, y0 = y0, x1 = x1, y1 = y1}

    /// Count the number of lines in a wrapped layout.
    pub def lineCount(advances: List[Float64], wrapWidth: Float64,
                      scale: Float64, lineHeight: Float64): Int32 =
        let positions = layoutPositions(advances, wrapWidth, scale, lineHeight);
        match positions {
            case Nil => 0
            case _ =>
                let ys = List.map(p -> snd(p), positions);
                let result = List.foldLeft((acc, y) -> {
                    let count = fst(acc);
                    let prevY = snd(acc);
                    if (Float64.abs(y - prevY) > 0.001) (count + 1, y) else (count, prevY)
                }, (1, 0.0), ys);
                fst(result)
        }
}
