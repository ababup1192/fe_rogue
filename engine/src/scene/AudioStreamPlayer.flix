/// Godot AudioStreamPlayer 準拠のオーディオ再生モジュール
/// see: https://docs.godotengine.org/ja/4.x/classes/class_audiostreamplayer.html
///
/// 2 つの利用形態がある:
///   - **モジュール関数** (`AudioStreamPlayer.play` 等) — `GameEngine.Audio` effect 経由で
///     サウンドマニフェスト (EngineConfig#soundManifest) の論理名をキーに鳴らす
///   - **Scene Node** (`AudioStreamPlayer` enum + `EngineNode.AudioStreamPlayerWithState`) —
///     scene.json に書ける Node 化されたバージョン。Inspector で stream / autoplay / loop /
///     volume を編集できる。SceneLoader が attach 時に autoplay を実行する
///
/// 使い方 (モジュール関数):
///   AudioStreamPlayer.play("bgm")
///   AudioStreamPlayer.stop("bgm")
///   AudioStreamPlayer.setVolume("bgm", 0.5f32)
///   AudioStreamPlayer.setLooping("bgm", true)
///
/// 使い方 (Scene Node, scene.json):
///   {"type": "AudioStreamPlayer", "name": "BGM",
///    "stream": "bgm", "autoplay": true, "loop": true, "volume": 0.5}
pub enum AudioStreamPlayer {
    case AudioStreamPlayer({
        stream   = String,    // サウンドマニフェスト (project.json#sounds) の論理名
        autoplay = Bool,      // scene attach 時に自動再生する
        loop     = Bool,      // 再生時に AL_LOOPING を ON にする
        volume   = Float32    // 音量 (gain), 0.0–1.0
    })
}

mod AudioStreamPlayer {

    /// デフォルト値で AudioStreamPlayer を生成する
    pub def make(stream: String): AudioStreamPlayer =
        AudioStreamPlayer.AudioStreamPlayer({
            stream   = stream,
            autoplay = false,
            loop     = false,
            volume   = 1.0f32
        })

    /// stream (サウンド論理名) を取得する
    pub def getStream(player: AudioStreamPlayer): String =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        r#stream

    /// stream を差し替える
    pub def setStream(stream: String, player: AudioStreamPlayer): AudioStreamPlayer =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        AudioStreamPlayer.AudioStreamPlayer({ stream = stream | r })

    /// autoplay フラグを取得する
    pub def isAutoplay(player: AudioStreamPlayer): Bool =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        r#autoplay

    /// autoplay フラグを設定する
    pub def setAutoplay(autoplay: Bool, player: AudioStreamPlayer): AudioStreamPlayer =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        AudioStreamPlayer.AudioStreamPlayer({ autoplay = autoplay | r })

    /// loop フラグを取得する
    pub def isLoop(player: AudioStreamPlayer): Bool =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        r#loop

    /// loop フラグを設定する
    pub def setLoop(loop: Bool, player: AudioStreamPlayer): AudioStreamPlayer =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        AudioStreamPlayer.AudioStreamPlayer({ loop = loop | r })

    /// volume を取得する
    pub def getVolume(player: AudioStreamPlayer): Float32 =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        r#volume

    /// volume を設定する (Node 自身の volume フィールド、ホスト側 OpenAL は別途反映が必要)
    pub def setVolumeField(volume: Float32, player: AudioStreamPlayer): AudioStreamPlayer =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        AudioStreamPlayer.AudioStreamPlayer({ volume = volume | r })

    /// 指定した名前のオーディオを再生する（先頭から再生し直す）
    pub def play(name: String): Unit \ GameEngine.Audio =
        GameEngine.Audio.playAudio(name)

    /// 指定した名前のオーディオを停止する
    pub def stop(name: String): Unit \ GameEngine.Audio =
        GameEngine.Audio.stopAudio(name)

    /// 指定した名前のオーディオの音量（gain）を 0.0〜1.0 で設定する。
    /// 再生中・停止中のいずれでも反映され、次回 play 後も維持される。
    pub def setVolume(name: String, volume: Float32): Unit \ GameEngine.Audio =
        GameEngine.Audio.setVolume(name, volume)

    /// 指定した名前のオーディオの loop フラグ (AL_LOOPING) を実行時に切り替える。
    /// 次回 play 後はもちろん、現在再生中の音にも即座に反映される。
    pub def setLooping(name: String, loop: Bool): Unit \ GameEngine.Audio =
        GameEngine.Audio.setLooping(name, loop)

    /// Scene attach 時に呼ぶライフサイクル関数。volume → looping → (autoplay なら play) を順に適用する。
    pub def applyAttach(player: AudioStreamPlayer): Unit \ GameEngine.Audio =
        let AudioStreamPlayer.AudioStreamPlayer(r) = player;
        GameEngine.Audio.setVolume(r#stream, r#volume);
        GameEngine.Audio.setLooping(r#stream, r#loop);
        if (r#autoplay) GameEngine.Audio.playAudio(r#stream) else ()

}
