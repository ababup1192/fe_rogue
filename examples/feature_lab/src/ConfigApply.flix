// ConfigApply — settings を実機（GameEngine）へ反映し、ディスクへ保存する唯一の口。
// キー入力（Controls.audioStep/windowStep）とコンフィグ画面（ConfigMenuUi）はどちらも
// World#settings の値を書き換えるだけにとどめ、setMasterVolume 等の副作用と保存はここへ集める。
// 反映口を 1 箇所にすることで「変化した時だけ呼ぶ」を入力手段によらず徹底できる
// （2 箇所に反映ロジックがあると、どちらかが変化検出を取りこぼす事故が起きやすい）。
mod ConfigApply {

    /// 設定ファイルの置き場所。SaveManager のスロット規約（saves/slot{N}.json）とは別物なので
    /// Persistence を直接使う。
    pub def settingsPath(): String = "saves/settings.json"

    /// 保存済み設定を読む。ファイル不在・壊れている場合は defaultSettings（fail-open —
    /// 設定ファイルが無くても起動を止めない）。
    pub def loadSettings(): World.Settings \ Fs.FileRead =
        (Persistence.load(settingsPath()): Option[SettingsCodec.Save])
            |> Option.map(SettingsCodec.unwrap)
            |> Option.getWithDefault(World.defaultSettings())

    /// 前フレームに反映した値（appliedSettings）と今の settings を見比べ、
    /// 変わったフィールドだけ実機へ反映する。settings 全体が変わっていればディスクへも保存する
    /// （保存タイミングを実機反映と同じ「変化検出」に相乗りさせ、判定を 2 重に持たない）。
    pub def step(_frame: App.Frame, world: World.World): World.World \ {GameEngine.Audio, GameEngine.Game, Fs.FileWrite} =
        let settings = world#settings;
        let applied = world#appliedSettings;
        if (settings#masterVolume != applied#masterVolume)
            GameEngine.Audio.setMasterVolume(RenderUtil.f32(settings#masterVolume))
        else ();
        if (settings#fullscreen != applied#fullscreen)
            GameEngine.Game.setFullscreen(settings#fullscreen)
        else ();
        if (settings#cursorVisible != applied#cursorVisible)
            GameEngine.Game.setCursorVisible(settings#cursorVisible)
        else ();
        if (settings#bgmOn != applied#bgmOn)
            (if (settings#bgmOn) GameEngine.Audio.playAudio("bgm") else GameEngine.Audio.stopAudio("bgm"))
        else ();
        // 保存失敗（saves/ 不在等）は握り潰す（実験場の設定保存でランタイムを止めない）。
        if (not World.settingsEqual(settings, applied))
            (match Persistence.save(settingsPath(), SettingsCodec.wrap(settings)) {
                case Ok(_)  => ()
                case Err(_) => ()
            })
        else ();
        { appliedSettings = settings | world }
}
