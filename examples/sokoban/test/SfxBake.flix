// SfxBake — the four sound effects are generated assets, like the gallery:
// flix test writes them to assets/sfx/ as plain 16-bit mono PCM WAV files
// (44-byte header + samples), and project.json's sound manifest loads them
// at launch. No sample packs, no recording — a square wave, a noise burst
// and an envelope are enough vocabulary for a robot pushing boxes.
mod SfxBake {
    import java.io.BufferedOutputStream
    import java.io.File
    import java.io.FileOutputStream

    def sampleRate(): Int32 = 22050

    def sr(): Float64 = 22050.0

    // ── Synthesis: every sample is a pure function of its index ──

    def fract(x: Float64): Float64 = x - Float64.floor(x)

    /// A square wave at freq Hz, amp in [0,1], fading linearly over len
    /// samples. The workhorse: blips, ticks and fanfare notes are all this.
    def square(freq: Float64, amp: Float64, len: Int32): List[Float64] =
        List.map(n -> {
            let t = Int32.toFloat64(n) / sr();
            let wave = if (fract(t * freq) < 0.5) 1.0 else -1.0;
            let env = 1.0 - Int32.toFloat64(n) / Int32.toFloat64(len);
            amp * env * wave
        }, List.range(0, len))

    /// A noise burst: a hashed pseudo-random sample per index, with the same
    /// fade. Deterministic — the thud sounds identical on every bake.
    def noise(amp: Float64, len: Int32): List[Float64] =
        List.map(n -> {
            let h = n * 374761393 + 668265263;
            let r = Int32.toFloat64(Int32.modulo(h * (h + 30011), 20001) - 10000) / 10000.0;
            let env = 1.0 - Int32.toFloat64(n) / Int32.toFloat64(len);
            amp * env * env * r
        }, List.range(0, len))

    def mix(a: List[Float64], b: List[Float64]): List[Float64] =
        List.zipWith((x, y) -> x + y, a, b)

    def ms(m: Int32): Int32 = sampleRate() * m / 1000

    // ── The four sounds ──

    /// Walking: a short mid blip.
    def moveBlip(): List[Float64] = square(660.0, 0.22, ms(45))

    /// Pushing: a low square under a noise burst — wood scraping floor.
    def pushThud(): List[Float64] =
        mix(square(98.0, 0.3, ms(90)), noise(0.22, ms(90)))

    /// Rewinding: one high tick per move taken back, in the clock's voice.
    def undoTick(): List[Float64] = square(1568.0, 0.16, ms(22))

    /// CLEAR: four rising square notes — C5, E5, G5, C6.
    def clearFanfare(): List[Float64] =
        List.flatten(
            square(523.25, 0.2, ms(90)) :: square(659.25, 0.2, ms(90)) ::
            square(783.99, 0.2, ms(90)) :: square(1046.5, 0.22, ms(240)) :: Nil)

    // ── WAV writing: 44 header bytes, then little-endian 16-bit samples ──

    def clip16(x: Float64): Int32 =
        let v = Float64.tryToInt32(x * 32767.0) |> Option.getWithDefault(0);
        Int32.max(-32768, Int32.min(32767, v))

    def put16(out: BufferedOutputStream, v: Int32): Unit \ IO =
        let u = if (v < 0) v + 65536 else v;
        out.write(Int32.modulo(u, 256));
        out.write(u / 256)

    def put32(out: BufferedOutputStream, v: Int32): Unit \ IO =
        put16(out, Int32.modulo(v, 65536));
        put16(out, v / 65536)

    def putTag(out: BufferedOutputStream, a: Int32, b: Int32, c: Int32, d: Int32): Unit \ IO =
        out.write(a); out.write(b); out.write(c); out.write(d)

    /// One mono 16-bit PCM WAV. The header is the whole file format: RIFF
    /// size, "fmt " block (format 1 = PCM), then the "data" block.
    def writeWav(path: String, samples: List[Float64]): Unit \ IO =
        let dataSize = List.length(samples) * 2;
        let out = new BufferedOutputStream(new FileOutputStream(path));
        putTag(out, 82, 73, 70, 70);              // "RIFF"
        put32(out, 36 + dataSize);
        putTag(out, 87, 65, 86, 69);              // "WAVE"
        putTag(out, 102, 109, 116, 32);           // "fmt "
        put32(out, 16);                           // PCM block size
        put16(out, 1);                            // format 1 = PCM
        put16(out, 1);                            // mono
        put32(out, sampleRate());
        put32(out, sampleRate() * 2);             // byte rate
        put16(out, 2);                            // block align
        put16(out, 16);                           // bits per sample
        putTag(out, 100, 97, 116, 97);            // "data"
        put32(out, dataSize);
        List.forEach(s -> put16(out, clip16(s)), samples);
        out.close()

    @Test
    def testBakeSfx(): Unit \ {Assert, IO} =
        discard (new File("assets/sfx")).mkdirs();
        writeWav("assets/sfx/move.wav", moveBlip());
        writeWav("assets/sfx/push.wav", pushThud());
        writeWav("assets/sfx/undo.wav", undoTick());
        writeWav("assets/sfx/clear.wav", clearFanfare());
        Assert.assertEq(expected = (true, true, true, true),
            ((new File("assets/sfx/move.wav")).exists(),
             (new File("assets/sfx/push.wav")).exists(),
             (new File("assets/sfx/undo.wav")).exists(),
             (new File("assets/sfx/clear.wav")).exists()))
}
