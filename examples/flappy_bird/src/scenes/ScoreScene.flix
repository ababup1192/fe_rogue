// ScoreScene — HUD レイヤーとスコア/ベストスコアラベルの構築・更新
//
// CanvasLayer (layer=1) の子として Label2D を配置し、
// カメラに影響されないスクリーン固定のスコア表示を行う。
// スコア値は Label2D の NodeTag.ScoreLabel(Score) に保持する。
// ベストスコアは NodeTag.BestScoreLabel(BestScore) に保持する（非表示）。
//
//   CanvasLayerWithState(hud, NoTag)
//     ├── Label2DWithState(score_label, ScoreLabel(0))
//     └── Label2DWithState(best_score_label, BestScoreLabel(0))  // 非表示

mod ScoreScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// HUD レイヤーのノード名
    def hudLayerName(): String = "hud"

    /// スコアラベルのノード名
    def scoreLabelName(): String = "score_label"

    /// ベストスコアラベルのノード名
    def bestScoreLabelName(): String = "best_score_label"

    /// スコアラベルのノードパス
    pub def scoreLabelPath(): NodePath = hudLayerName() :: scoreLabelName() :: Nil

    /// ベストスコアラベルのノードパス
    pub def bestScoreLabelPath(): NodePath = hudLayerName() :: bestScoreLabelName() :: Nil

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// HUD シーン定義 JSON のパス
    def sceneJsonPath(): String = "src/scenes/ScoreScene.scene.json"

    /// HUD レイヤーとスコア/ベストスコアラベルをシーンに追加する。
    /// 構造は ScoreScene.scene.json から読み込み、ScoreLabel/BestScoreLabel タグと
    /// ベストスコアの初期表示値は読み込み後に setState/setText で適用する
    pub def addHud(fontAtlas: FontAtlas, bestScore: BestScore,
                   scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, scene)
            |> Scene.setState(scoreLabelPath(), NodeTag.ScoreLabel(0))
            |> Scene.setState(bestScoreLabelPath(), NodeTag.BestScoreLabel(bestScore))
            |> Scene.mapEngineNode(bestScoreLabelPath(),
                EngineNode.mapLabel2D(Label2D.setText("${bestScore}")))

    // ========================================================================
    // 取得
    // ========================================================================

    /// Scene から現在のスコアを取り出す
    pub def getScore(scene: Scene[NodeTag]): Score =
        match Scene.getState(scoreLabelPath(), scene) {
            case Some(NodeTag.ScoreLabel(score)) => score
            case _ => bug!("score_label not found")
        }

    /// Scene からベストスコアを取り出す
    pub def getBestScore(scene: Scene[NodeTag]): BestScore =
        match Scene.getState(bestScoreLabelPath(), scene) {
            case Some(NodeTag.BestScoreLabel(bestScore)) => bestScore
            case _ => bug!("best_score_label not found")
        }

    // ========================================================================
    // 更新
    // ========================================================================

    /// スコアを指定値に更新する（NodeTag とラベルテキストの両方）
    pub def setScore(score: Score, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.setState(scoreLabelPath(), NodeTag.ScoreLabel(score))
            |> Scene.mapEngineNode(scoreLabelPath(),
                EngineNode.mapLabel2D(l -> Label2D.setText("${score}", l)))

    /// ベストスコアを更新する（ラベルは非表示なのでテキストは更新しない）
    pub def setBestScore(bestScore: BestScore, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.setState(bestScoreLabelPath(), NodeTag.BestScoreLabel(bestScore), scene)

    /// 現在のスコアを関数 f で変換する
    pub def mapScore(f: Score -> Score, scene: Scene[NodeTag]): Scene[NodeTag] =
        setScore(f(getScore(scene)), scene)

    /// 現在のベストスコアを関数 f で変換する
    pub def mapBestScore(f: BestScore -> BestScore, scene: Scene[NodeTag]): Scene[NodeTag] =
        setBestScore(f(getBestScore(scene)), scene)

    /// スコアを 1 加算し、ラベルテキストも同時に更新する
    pub def incrementScore(scene: Scene[NodeTag]): Scene[NodeTag] =
        mapScore(s -> s + 1, scene)

    // ========================================================================
    // 応答処理
    // ========================================================================

    /// HUD のスコアラベルを非表示にする（Menu / GameOver 遷移時に使用）
    pub def hideScoreLabel(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(scoreLabelPath(),
            EngineNode.mapLabel2D(CanvasItem.hide), scene)

    /// 現在のスコアでベストスコアを更新する（max を取って setBestScore）
    pub def finalizeScore(scene: Scene[NodeTag]): Scene[NodeTag] =
        let score = getScore(scene);
        mapBestScore(b -> Int32.max(score, b), scene)

    /// 鳥がコインを通過したときの処理
    /// スコアを +1 し、効果音を鳴らし、コインの NodeTag を NoTag に変更して再採点を防止する
    pub def onBirdPassedCoin(coinPath: {coinPath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        GameEngine.Audio.playAudio("sfx_point");
        scene
            |> incrementScore
            |> Scene.setState(coinPath#coinPath, NodeTag.NoTag)
}
