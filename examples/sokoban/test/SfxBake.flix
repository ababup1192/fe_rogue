// SfxBake — the four sound effects are generated assets, like the gallery:
// flix test writes them to assets/sfx/ as plain 16-bit mono PCM WAV files, and
// project.json's sound manifest loads them at launch. No sample packs, no
// recording — SfxSynth's square wave, noise burst and fade are enough
// vocabulary for a robot pushing boxes. This file keeps only the sound design;
// the synthesis and WAV encoding live in engine_tools.
mod SfxBake {
    import java.io.File

    /// 22050 Hz mono: small files, plenty for these blips.
    def cfg(): SfxSynth.Config = { sampleRate = 22050 }

    // ── The four sounds: each a design over SfxSynth's vocabulary ──

    /// Walking: a short mid blip.
    def moveBlip(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 660.0, 0.22, 45))

    /// Pushing: a low square under a sharply decaying noise burst — wood
    /// scraping floor. The noise fades twice, so it dies faster than the tone.
    def pushThud(): List[Float64] =
        SfxSynth.blend(
            SfxSynth.fade(SfxSynth.tone(cfg(), 98.0, 0.3, 90)),
            SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.22, 90))))

    /// Rewinding: one high tick per move taken back, in the clock's voice.
    def undoTick(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 1568.0, 0.16, 22))

    /// CLEAR: four rising square notes — C5, E5, G5, C6.
    def clearFanfare(): List[Float64] =
        SfxSynth.sequence(
            SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.2, 90)) ::
            SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.22, 240)) :: Nil)

    def bake(path: String, samples: List[Float64]): Unit \ IO =
        SfxSynth.writeBytes(path, SfxSynth.wavBytes(cfg(), samples))

    @Test
    def testBakeSfx(): Unit \ {Assert, IO} =
        discard (new File("assets/sfx")).mkdirs();
        bake("assets/sfx/move.wav", moveBlip());
        bake("assets/sfx/push.wav", pushThud());
        bake("assets/sfx/undo.wav", undoTick());
        bake("assets/sfx/clear.wav", clearFanfare());
        Assert.assertEq(expected = (true, true, true, true),
            ((new File("assets/sfx/move.wav")).exists(),
             (new File("assets/sfx/push.wav")).exists(),
             (new File("assets/sfx/undo.wav")).exists(),
             (new File("assets/sfx/clear.wav")).exists()))
}
