/// エリア重なり検出と AreaHandler 発火（Godot Area2D シグナル準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_area2d.html#signals
///
/// 使い方:
///   1. ノード型に AreaHandler[s] を実装し onAreaEntered / onAreaExited を定義
///   2. Scene.processAll の後で handleOverlaps を呼び出す
///      （ゲームループでは GameEngine.handleCollisions が代行）

/// 有向オーバーラップペア (selfPath, otherPath) の集合。
/// 前フレームの重なり状態を保持し、離脱イベントの検出に使う。
pub type alias OverlapPairSet = Set[(NodePath, NodePath)]

/// エリア間の接触情報
pub type alias AreaContact = {
    path = NodePath,
    position = Vec2.Vec2
}

/// 検出された重なり 1 件分。
/// selfPath 側の onAreaEntered が発火される。
pub type alias AreaOverlap = {
    selfPath = NodePath,
    selfPos = Vec2.Vec2,
    other = AreaContact
}

pub mod AreaEvent {

    // ========================================================================
    // 衝突応答トレイト（ノード主導のエリアイベント処理）
    // ========================================================================

    /// 衝突応答トレイト（OnAreaEvent エフェクトの代替、ノード主導）
    ///
    /// 外部ハンドラではなく、ノード型自身が衝突応答ロジックを持つ。
    /// ゲーム固有の状態 s を受け取り、エンジンノードへのアクセスが必要な場合は
    /// Scene.getEngineNode / Scene.mapEngineNode を使う。
    ///
    /// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
    /// 例: 効果音を鳴らす場合は `type Aef = { GameEngine.Audio }`、
    ///      純粋な場合は `type Aef = {}` とする。
    pub trait AreaHandler[s] {

        /// 衝突応答で発生するエフェクト
        type Aef: Eff

        /// 自分のエリアに他ノードが侵入したとき呼ばれる。
        /// Scene を書き換えて返す。
        ///
        /// selfPath: 自分のパス
        /// selfState: 自分のゲーム状態
        /// otherPath: 相手のパス
        /// otherState: 相手のゲーム状態
        /// scene: 現在のシーン
        pub def onAreaEntered(
            selfPath: NodePath,
            selfState: s,
            otherPath: NodePath,
            otherState: s,
            scene: Scene[s]
        ): Scene[s] \ AreaHandler.Aef[s]

        /// 自分のエリアから他ノードが離脱したとき呼ばれる。
        /// デフォルトでは何もしない。
        pub def onAreaExited(
            _selfPath: NodePath,
            _selfState: s,
            _otherPath: NodePath,
            _otherState: s,
            scene: Scene[s]
        ): Scene[s] \ AreaHandler.Aef[s] = checked_ecast(scene)
    }

    // ========================================================================
    // 重なり検出（純粋関数 — EngineNode の CollisionObject2D を直接使用）
    // ========================================================================

    /// Scene 内の全 CollisionObject2D ペアの重なりを検出する。
    /// monitoring / monitorable フラグを考慮し、有効なペアのみ返す。
    pub def detectOverlaps(scene: Scene[s]): List[AreaOverlap] =
        let paths = Scene.preorderPaths(scene);
        let areas = List.filterMap(path ->
            Scene.getEngineNode(path, scene) |> Option.flatMap(engineNode ->
                CollisionObject2D.getCollisionShape(engineNode) |> Option.map(shape ->
                    (path, Scene.globalPositionAt(path, scene), shape,
                     CollisionObject2D.isMonitoring(engineNode),
                     CollisionObject2D.isMonitorable(engineNode))
                )
            ), paths);
        collectPairs(areas)

    /// 内部ヘルパー: 全ペアを総当たりで比較し、重なりイベントを収集する。
    def collectPairs(areas: List[(NodePath, Vec2.Vec2, CollisionShape2D, Bool, Bool)]): List[AreaOverlap] =
        match areas {
            case Nil => Nil
            case (pathA, posA, shapeA, monitoringA, monitorableA) :: tail =>
                let pairsFromA = List.flatMap(entry ->
                    let (pathB, posB, shapeB, monitoringB, monitorableB) = entry;
                    if (CollisionShape2D.checkOverlap(posA, shapeA, posB, shapeB))
                        let forward: List[AreaOverlap] =
                            if (monitoringA and monitorableB)
                                {selfPath = pathA, selfPos = posA,
                                 other = {path = pathB, position = posB}} :: Nil
                            else Nil;
                        let reverse: List[AreaOverlap] =
                            if (monitoringB and monitorableA)
                                {selfPath = pathB, selfPos = posB,
                                 other = {path = pathA, position = posA}} :: Nil
                            else Nil;
                        List.append(forward, reverse)
                    else Nil
                , tail);
                List.append(pairsFromA, collectPairs(tail))
        }

    // ========================================================================
    // AreaHandler 統合（ノード主導の衝突応答）
    // ========================================================================

    /// AreaOverlap リストから有向ペアセットに変換する
    pub def toOverlapPairSet(overlaps: List[AreaOverlap]): OverlapPairSet =
        List.foldLeft((acc, ov) ->
            Set.insert((ov#selfPath, ov#other#path), acc),
            Set.empty(),
            overlaps)

    /// processAll 済みの Scene に対してエリアイベントを検出・ハンドリングする。
    /// AreaHandler.onAreaEntered / onAreaExited をディスパッチし、
    /// prevOverlaps を更新して返す。
    pub def handleOverlaps(scene: Scene[s]): Scene[s] \ AreaHandler.Aef[s] with AreaHandler[s] =
        let prevOverlaps = Scene.getPrevOverlaps(scene);
        let overlaps = detectOverlaps(scene);
        let currentPairs = toOverlapPairSet(overlaps);
        // 現在重なっているペアに onAreaEntered を発火
        let sceneAfterEnter = List.foldLeft((sc, ov) ->
            match (Scene.getState(ov#selfPath, sc), Scene.getState(ov#other#path, sc)) {
                case (Some(selfState), Some(otherState)) =>
                    AreaHandler.onAreaEntered(ov#selfPath, selfState, ov#other#path, otherState, sc)
                case _ => sc
            },
            scene,
            overlaps);
        // 前フレームにあって今フレームにないペアに onAreaExited を発火
        let exitedPairs = Set.difference(prevOverlaps, currentPairs);
        let sceneAfterExit = Set.foldLeft((sc, pair) ->
            let (selfPath, otherPath) = pair;
            match (Scene.getState(selfPath, sc), Scene.getState(otherPath, sc)) {
                case (Some(selfState), Some(otherState)) =>
                    AreaHandler.onAreaExited(selfPath, selfState, otherPath, otherState, sc)
                case _ => sc
            },
            sceneAfterEnter,
            exitedPairs);
        Scene.setPrevOverlaps(currentPairs, sceneAfterExit)
}
