/// FlagScene — PlayerAutoMove の目印として立てる旗ノード
///
/// FE 風の「自動移動先マーカー」。空マスでカーソル決定すると `plant` で立ち、
/// 自動移動が終わると `clear` で消える。
///
/// ノード構造（Cursor と並列のトップレベル）:
///   Flag (Marker2D, NodeTag.Flag(Data))
///     └─ Sprite (Sprite2D, flag.png)
///
/// 設計:
///   - 親 Marker2D に位置と planted フラグを持たせる
///   - 立てていない間は親 Marker2D を invisible にする（add 直後・clear 後）
///   - planted = false の時は `getTargetPos` が None を返すので、AutoMove が
///     空回りせずフェーズを抜ける防御に使える
mod FlagScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// `gridPos`: 旗を立てたグリッド座標（planted = false のときは未使用）
    /// `planted`: 旗が立っているか。false の時は描画されず、`getTargetPos` も None を返す
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        planted = Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Flag"
    pub def flagPath(): NodePath = name() :: Nil

    /// scene.json への相対パス（cwd = プロジェクトルート想定）
    def scenePath(): String = "src/scenes/FlagScene.scene.json"

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene 登録済みの scene に旗ノードを追加する。
    /// レイアウト（Marker2D + 子 Sprite2D, テクスチャ, zIndex, 初期不可視）は
    /// `FlagScene.scene.json` に閉じ込めてあり、ロード後にゲーム状態 (`Data`) を
    /// `Scene.setState` で後付け注入する分業。
    /// 初期は planted = false（非表示）。`plant` を呼んで初めて表示される。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let initialData: Data = {gridPos = {x = 0, y = 0}, planted = false};
        SceneLoader.loadScene(scenePath(),
                               SceneLoader.constTagParser(NodeTag.NoTag),
                               scene)
            |> Scene.setState(flagPath(), NodeTag.Flag(initialData))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 空マスで Z 押下時の遷移: ログ + 旗を立てる + フェーズを `PlayerAutoMove` に進める。
    /// 周辺 overlay / cursor の整理は `PhaseTransitions.enterPlayerAutoMove` が担当する
    /// (この関数は旗の表示と log にだけ責任を持つ)。
    pub def plant(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State} =
        GameLogger.playerLog("旗を立てた");
        scene
            |> markAt(target)
            |> PhaseTransitions.enterPlayerAutoMove

    /// `target` セルに旗を立てる純粋なマーク操作 (位置更新 + 可視化)。
    /// フェーズ遷移は含めない。`plant` の内部実装として使う。
    def markAt(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        let world = MapScene.cellCenter(target);
        scene
            |> Scene.setGlobalPositionAt(flagPath(), world)
            |> mapFlag((m, _) ->
                (CanvasItem.setVisible(true, m),
                 ({gridPos = target, planted = true}: Data)))

    /// 旗を消す（不可視 + planted = false）。AutoMove 終了時に呼ぶ。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        mapFlag((m, d) ->
            (CanvasItem.setVisible(false, m),
             ({planted = false | d}: Data)),
            scene)

    /// 旗の現在のターゲット位置。立っていなければ None。
    pub def getTargetPos(scene: Scene[NodeTag]): Option[{x = Int32, y = Int32}] =
        match Scene.getState(flagPath(), scene) {
            case Some(NodeTag.Flag(d)) =>
                if (d#planted) Some(d#gridPos) else None
            case _ => None
        }

    /// 旗が立っているか。
    pub def isPlanted(scene: Scene[NodeTag]): Bool =
        match Scene.getState(flagPath(), scene) {
            case Some(NodeTag.Flag(d)) => d#planted
            case _ => false
        }

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート
    // ────────────────────────────────────────────────────────

    /// Flag の Marker2D + Data をまとめて変換する。
    def mapFlag(f: (Marker2D, Data) -> (Marker2D, Data),
                 scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(flagPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Flag(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Flag(newData))
            case other => other
        }, scene)

}
