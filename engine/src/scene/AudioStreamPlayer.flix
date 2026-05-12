/// Godot AudioStreamPlayer 準拠のオーディオ再生モジュール
/// see: https://docs.godotengine.org/ja/4.x/classes/class_audiostreamplayer.html
///
/// GameEngine.Audio エフェクトを介してオーディオを再生・停止する。
/// 名前はサウンドマニフェスト（EngineConfig#soundManifest）で定義した論理名を使う。
///
/// 使い方:
///   AudioStreamPlayer.play("bgm")   // マニフェストで定義した "bgm" を再生
///   AudioStreamPlayer.stop("bgm")   // "bgm" を停止
mod AudioStreamPlayer {

    /// 指定した名前のオーディオを再生する（先頭から再生し直す）
    pub def play(name: String): Unit \ GameEngine.Audio =
        GameEngine.Audio.playAudio(name)

    /// 指定した名前のオーディオを停止する
    pub def stop(name: String): Unit \ GameEngine.Audio =
        GameEngine.Audio.stopAudio(name)

}
