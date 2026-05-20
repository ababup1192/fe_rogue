/// Godot AudioStreamPlayer 準拠のオーディオ再生モジュール
/// see: https://docs.godotengine.org/ja/4.x/classes/class_audiostreamplayer.html
///
/// GameEngine.Audio エフェクトを介してオーディオを再生・停止する。
/// 名前はサウンドマニフェスト（EngineConfig#soundManifest）で定義した論理名を使う。
///
/// 使い方:
///   AudioStreamPlayer.play("bgm")          // マニフェストで定義した "bgm" を再生
///   AudioStreamPlayer.stop("bgm")          // "bgm" を停止
///   AudioStreamPlayer.setVolume("bgm", 0.5f32)  // "bgm" の音量を 50% に設定
mod AudioStreamPlayer {

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

}
