// AudioSystem — Worldの速度を、鳴り続ける駆動音2本の音量へ流す唯一の副作用境界。
// 再生開始の判断はAudioView、音量の値はここ、波形の意匠はSfxBakeへ分ける。
mod AudioSystem {

    /// 低回転と高回転を速度で交差させる。Worldは読み取るだけで変更しない。
    pub def step(_frame: App.Frame, world: World.World): World.World \ GameEngine.Audio =
        let speedRatio = clamp(
            0.0, 1.0, world#speed / world#tuning#boostMaxSpeed);
        let racing = world#phase == World.Phase.Racing;
        let countdown = world#phase == World.Phase.Countdown;
        let (slowMix, fastMix) = AudioFade.crossfadeOf(speedRatio);
        let lowVolume =
            if (racing) 0.20 + 0.50 * slowMix
            else if (countdown) 0.12
            else 0.0;
        let highVolume =
            if (racing) 0.08 + 0.92 * fastMix
            else 0.0;
        GameEngine.Audio.setVolume(
            "engine_low", Float64.truncateToFloat32(lowVolume));
        GameEngine.Audio.setVolume(
            "engine_high", Float64.truncateToFloat32(highVolume));
        GameEngine.Audio.setVolume("bgm", 0.58f32);
        world

    def clamp(lower: Float64, upper: Float64, value: Float64): Float64 =
        Float64.max(lower, Float64.min(upper, value))
}
