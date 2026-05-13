// GameOverScene — ゲームオーバー画面の構築・アニメーション・ボタン判定
//
// CanvasLayer (layer=2) の子として各 UI 要素を配置する。
// HUD (layer=1) の上に描画される。
// 子ノードは初期非表示で追加され、GameOverAnim state の経過時間に応じて段階的に表示される。
//
//   CanvasLayerWithState(gameover, GameOverAnim({elapsed = 0.0}))
//     ├── Sprite2DWithState(gameover_label, NoTag)              // "GAME OVER" ラベル
//     ├── Sprite2DWithState(score_panel, NoTag)                 // スコアパネル背景
//     ├── Sprite2DWithState(medal, NoTag)                       // メダル（score>=10 のみ）
//     ├── Label2DWithState(final_score, NoTag)                  // パネル上のスコア数値
//     ├── Label2DWithState(best_score, NoTag)                   // パネル上のベストスコア数値
//     └── TextureButtonWithState(play_button, NoTag)            // Play ボタン

mod GameOverScene {

    // ========================================================================
    // 定数 — ノード名
    // ========================================================================

    /// ゲームオーバーレイヤーのノード名
    def layerName(): String = "gameover"

    /// GAME OVER ラベルのノード名
    def labelName(): String = "gameover_label"

    /// スコアパネルのノード名
    def panelName(): String = "score_panel"

    /// メダルのノード名
    def medalName(): String = "medal"

    /// 最終スコアラベルのノード名
    def finalScoreName(): String = "final_score"

    /// ベストスコアラベルのノード名
    def bestScoreName(): String = "best_score"

    /// Play ボタンのノード名
    def playButtonName(): String = "play_button"

    // ========================================================================
    // 定数 — パス
    // ========================================================================

    /// ゲームオーバーレイヤーのパス
    def layerPath(): NodePath = layerName() :: Nil

    /// Play ボタンのパス
    pub def playButtonPath(): NodePath = layerName() :: playButtonName() :: Nil

    /// メダルのパス
    def medalPath(): NodePath = layerName() :: medalName() :: Nil

    /// 最終スコアラベルのパス
    def finalScorePath(): NodePath = layerName() :: finalScoreName() :: Nil

    /// ベストスコアラベルのパス
    def bestScorePath(): NodePath = layerName() :: bestScoreName() :: Nil

    // ========================================================================
    // シーン定義 JSON のパス
    // ========================================================================

    /// ゲームオーバー UI のシーン定義 JSON ファイルのパス
    def sceneJsonPath(): String = "src/scenes/GameOverScene.scene.json"

    // ========================================================================
    // アニメーション定数
    // ========================================================================

    /// GAME OVER ラベルの表示タイミング（即座）
    def labelShowTime(): Float64 = 0.0

    /// スコアパネル + スコア数値の表示タイミング
    def panelShowTime(): Float64 = 0.3

    /// メダルの表示タイミング
    def medalShowTime(): Float64 = 0.5

    /// Play ボタンの表示タイミング
    def buttonShowTime(): Float64 = 0.7

    /// アニメーション全体の長さ
    def animDuration(): Float64 = 0.8

    // ========================================================================
    // メダル判定
    // ========================================================================

    /// スコアに応じたメダルテクスチャ名を返す
    /// score >= 50: platinum, >= 30: gold, >= 20: silver, >= 10: bronze
    pub def getMedalTexture(score: Int32): Option[String] =
        if (score >= 50) Some("medal_platinum")
        else if (score >= 30) Some("medal_gold")
        else if (score >= 20) Some("medal_silver")
        else if (score >= 10) Some("medal_bronze")
        else None

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// ゲームオーバー画面への遷移処理
    /// 効果音再生 → スコア確定 → UI 追加をまとめる
    pub def enterGameOver(fontAtlas: FontAtlas,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, Fs.FileRead} =
        GameEngine.Audio.playAudio("sfx_swooshing");
        scene
            |> ScoreScene.finalizeScore
            |> addGameOverUI(fontAtlas)

    /// ゲームオーバー UI をシーンに追加する。
    /// 構造は GameOverScene.scene.json から読み込み（全 6 子ノードは初期非表示）、
    /// 読み込み後に GameOverAnim タグ・スコアテキスト・メダル差し替えを適用する。
    /// メダルはベストスコア < 10 のときに削除する（メダルなし表示）。
    /// HUD のスコアラベルも非表示にする
    pub def addGameOverUI(fontAtlas: FontAtlas,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        let score = ScoreScene.getScore(scene);
        let bestScore = ScoreScene.getBestScore(scene);
        scene
            |> ScoreScene.hideScoreLabel
            |> SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas)
            // GameOverAnim 状態をルートレイヤーにセット
            |> Scene.setState(layerPath(), NodeTag.GameOverAnim({elapsed = 0.0}))
            // 最終スコア・ベストスコアのテキストを実際の値に差し替え
            |> Scene.mapEngineNode(finalScorePath(),
                EngineNode.mapLabel2D(Label2D.setText("${score}")))
            |> Scene.mapEngineNode(bestScorePath(),
                EngineNode.mapLabel2D(Label2D.setText("${bestScore}")))
            // メダルテクスチャを bestScore に応じて差し替え（< 10 のときは削除）
            |> applyMedal(bestScore)

    /// bestScore に応じてメダルテクスチャを差し替える、
    /// あるいは bestScore < 10 のときはメダルノードを削除する
    def applyMedal(bestScore: BestScore, scene: Scene[NodeTag]): Scene[NodeTag] =
        match getMedalTexture(bestScore) {
            case Some(medalTex) =>
                Scene.mapEngineNode(medalPath(),
                    EngineNode.mapSprite2D(Sprite2D.setTexture(medalTex)), scene)
            case None =>
                Scene.removeAt(medalPath(), scene)
        }

    // ========================================================================
    // アニメーション
    // ========================================================================

    /// アニメーションが完了したか判定する
    pub def isAnimationFinished(scene: Scene[NodeTag]): Bool =
        match Scene.getState(layerPath(), scene) {
            case Some(NodeTag.GameOverAnim(animData)) =>
                animData#elapsed >= animDuration()
            case _ => true
        }

    /// CanvasLayer の毎フレーム更新（GameOverAnim 状態を進めて再ラップする）
    /// 該当しないノードはそのまま返す
    pub def process(delta: Float64, node: EngineNode[NodeTag],
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.GameOverAnim(_)) =>
                let newScene = updateAnimation(delta, scene);
                let newState = match Scene.getState(layerPath(), newScene) {
                    case Some(tag) => tag
                    case _         => NodeTag.GameOverAnim({elapsed = 0.0})
                };
                (EngineNode.CanvasLayerWithState(layer, newState), newScene)
            case _ => (node, scene)
        }

    /// アニメーションの経過時間を進め、閾値超過時にノードを表示する
    pub def updateAnimation(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(layerPath(), scene) {
            case Some(NodeTag.GameOverAnim(animData)) =>
                let prevElapsed = animData#elapsed;
                let newElapsed = prevElapsed + dt;
                let updatedScene = Scene.setState(layerPath(),
                    NodeTag.GameOverAnim({elapsed = newElapsed}), scene);
                // 閾値を超えた瞬間にノードを show する
                updatedScene
                    |> showChildIfCrossed(labelName(), labelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(panelName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(finalScoreName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(bestScoreName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(medalName(), medalShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(playButtonName(), buttonShowTime(), prevElapsed, newElapsed)
            case _ => scene
        }

    /// 閾値を超えた瞬間に子ノードを表示する
    def showChildIfCrossed(childName: String, threshold: Float64,
                            prevElapsed: Float64, newElapsed: Float64,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        if (prevElapsed < threshold and newElapsed >= threshold)
            showChild(childName, scene)
        else
            scene

    /// 子ノードを表示する（存在しない場合は何もしない）
    def showChild(childName: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let path = layerName() :: childName :: Nil;
        match Scene.getEngineNode(path, scene) {
            case Some(_) =>
                Scene.mapEngineNode(path, CanvasItem.show, scene)
            case None => scene
        }

}
