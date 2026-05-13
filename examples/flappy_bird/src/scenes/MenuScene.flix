// MenuScene — メニュー画面の構築
//
// CanvasLayer (layer=2) の子としてタイトルロゴ・操作説明画像・Play ボタンを配置する。
// Play ボタン押下時の遷移は Game の ButtonHandler が GamePhaseState.put(GamePhase.Playing) することで処理する。
// メニュー → プレイ画面への切替は Scene 全体を作り直す方式のため、ここに削除処理は持たない。
//
// シーン構造の宣言は src/scenes/MenuScene.scene.json に外出ししてある。
// 構造を編集したいときは JSON を直接書き換える（ホットリロード基盤の Phase 1）。
//
//   CanvasLayerWithState(menu, NoTag)  [layer=2]
//     ├── Sprite2DWithState(title_logo, NoTag)                  // label_flappy_bird (y=140)
//     ├── Sprite2DWithState(instructions_img, NoTag)            // instructions (y=340)
//     └── TextureButtonWithState(play_button, NoTag)            // button_play_normal (y=440)

mod MenuScene {

    // ========================================================================
    // 定数 — ノード名
    // ========================================================================

    /// メニューレイヤーのノード名
    def layerName(): String = "menu"

    /// タイトルロゴのノード名
    def titleLogoName(): String = "title_logo"

    /// 操作説明画像のノード名
    def instructionsName(): String = "instructions_img"

    /// Play ボタンのノード名
    def playButtonName(): String = "play_button"

    // ========================================================================
    // 定数 — パス
    // ========================================================================

    pub def titleLogoPath(): NodePath = layerName() :: titleLogoName() :: Nil
    pub def instructionsPath(): NodePath = layerName() :: instructionsName() :: Nil
    pub def playButtonPath(): NodePath = layerName() :: playButtonName() :: Nil

    // ========================================================================
    // シーン定義 JSON のパス
    // ========================================================================

    /// メニュー UI のシーン定義 JSON ファイルのパス
    def sceneJsonPath(): String = "src/scenes/MenuScene.scene.json"

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// メニュー UI をシーンに追加する。構造は MenuScene.scene.json から読み込む
    pub def addMenuUI(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        SceneLoader.loadScene(sceneJsonPath(), scene)
}
