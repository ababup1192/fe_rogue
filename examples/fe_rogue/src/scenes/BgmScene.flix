/// BgmScene — ゲーム全体に常駐する BGM 用 AudioStreamPlayer ノード
///
/// 従来は `Game.start` 内で `AudioStreamPlayer.play("bgm")` を直接呼んでいたが、
/// Godot 準拠の Scene Node 化したことで:
///   - scene.json から stream / autoplay / loop / volume を宣言的に設定できる
///   - IDE Inspector で各プロパティを編集 → HotReload で preview に即反映できる
///   - IDE Inspector の Play / Stop ボタンで preview 再生を手動制御できる
///
/// ノード構造（トップレベル）:
///   BGM (AudioStreamPlayer, NodeTag.NoTag)
///
/// SceneLoader が attach 時に `applyAudioAttach` で volume / loop を OpenAL に反映し、
/// autoplay = true なら再生を開始する。autoplay は **runtime のみ** で反応し、
/// IDE preview では呼ばないため preview が勝手に鳴ることはない。
mod BgmScene {

    def name(): String = "BGM"
    pub def bgmPath(): NodePath = name() :: Nil

    /// scene.json への相対パス（cwd = プロジェクトルート想定）
    def scenePath(): String = AssetPath.resolve("src/scenes/BgmScene.scene.json")

    /// BGM ノードを scene tree に追加する。SceneLoader が AudioStreamPlayer ノードを
    /// パースし、`applyAudioAttach` を別途呼ぶことで autoplay = true の場合に再生開始する。
    /// `add` の呼出側で `SceneLoader.applyAudioAttach` を 1 度呼ぶ必要がある
    /// (シーン全体の AudioStreamPlayer を一括反映するため、ここでは呼ばない)
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(scenePath(),
                               SceneLoader.constTagParser(NodeTag.NoTag),
                               scene)

}
