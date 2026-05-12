/// EnemyRangeScene — カーソルが敵に乗っているとき、その敵の移動範囲を赤色で可視化する
///
/// `MoveRangeScene` のミラー実装で、起点が「Player」ではなく「ホバー中の敵」になり、
/// 色が「青」ではなく「赤」になる。FE 風の「敵情報を見ながらターン計画を立てる」フローを
/// 提供するための情報表示専用シーン。
///
/// ノード構造（出ているとき）:
///   EnemyRange (Marker2D, NodeTag.EnemyRange({enemyId, reachable}))
///     ├─ Tile_0 (Sprite2D, alpha=1, modulate=red)
///     ├─ Tile_1 ...
///
/// **ライフサイクル**:
///   - Cursor がフレーム間で乗っている敵 id が変わったとき、`refreshFor(id, scene)` で
///     既存ノードを破棄して新規構築する
///   - Cursor が敵以外に移ったとき、`clear(scene)` でノードを丸ごと取り除く
///   - 敵ターン開始時 / フェーズ切替で見せたくない場面でも `clear` を呼んで消す
///
/// `MoveRangeScene` のような「常設」運用は取らず、必要なときだけ scene に存在するように
/// する（駒が増えたとき・敵が動いたときの再構築コストを cursor のホバー遷移時に閉じる）。
mod EnemyRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `enemyId` は今表示している対象敵。`reachable` は BFS で到達可能と判定された
    /// セル一覧（origin = 敵セルを含む）。
    pub type alias Data = {
        enemyId   = Int32,
        reachable = List[{x = Int32, y = Int32}]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "EnemyRange"
    pub def enemyRangePath(): NodePath = name() :: Nil

    /// `move_tile` テクスチャを赤く modulate して再利用する（専用テクスチャを足さない）
    def textureName(): String = "move_tile"

    /// LDTK 由来のタイルサイズ。MapScene と揃える。
    def tileSize(): Float64 = 16.0

    /// 不透明度。情報表示なので少し透かして駒や床を見やすくする
    def tileAlpha(): Float32 = 0.7f32

    /// 赤系 modulate。MoveRange の青 (0.3, 0.5, 1.0) と対比する
    def tileColor(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// MoveRange (= 1) と同じ階層。Player Sprite (= 10) より下に来る。
    /// MoveRange と重なるセルがあっても両方は同時に出ないので zIndex 衝突は問題にならない。
    def tileZIndex(): Int32 = 1

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 既存の EnemyRange ノードがあれば取り除き、`enemyId` の敵に対応する範囲で
    /// 構築し直す。敵が居なければ何もしない（`clear` 相当の保険）。
    pub def refreshFor(enemyId: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        match EnemyScene.get(enemyId, scene) {
            case None       => clear(scene)
            case Some(data) =>
                let cleared = clear(scene);
                let layer   = MapScene.getMapLayer(cleared);
                // FE 流: 壁のみ通れない。味方マスや他敵マスも「想定移動範囲」として
                // 表示する（プレイヤーは「もし誰も居なければここまで来られる」を読む）
                let cells = Board.reachableCells(
                    c -> TileMapLayer.isFloor(c, layer),
                    data#gridPos,
                    data#moveTiles);
                cleared
                    |> addParent(enemyId, cells)
                    |> addTileChildren(cells)
        }

    /// 表示中の EnemyRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(enemyRangePath(), scene)

    // ────────────────────────────────────────────────────────
    // 内部: ノード追加
    // ────────────────────────────────────────────────────────

    /// 親 Marker2D を origin (0,0) に追加する。MoveRangeScene と完全に同じ構造。
    def addParent(enemyId: Int32, cells: List[{x = Int32, y = Int32}],
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        let data: Data = { enemyId = enemyId, reachable = cells };
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.EnemyRange(data)),
            scene)

    /// `cells` を順に列挙して半透明 Sprite2D を `Tile_<idx>` として子追加する。
    def addTileChildren(cells: List[{x = Int32, y = Int32}],
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        let indexed = List.zipWithIndex(cells);
        List.foldLeft(acc -> entry -> {
            let (idx, cell) = entry;
            let pos: Vec2.Vec2 = cellCenter(cell);
            let sprite = Sprite2D.make(textureName(), pos, Vec2.one())
                            |> Sprite2D.setAlpha(tileAlpha())
                            |> CanvasItem.setModulate(tileColor())
                            |> CanvasItem.setZIndex(tileZIndex());
            Scene.addChild(name(),
                "Tile_${idx}",
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag),
                acc)
        }, scene, indexed)

    /// グリッド座標 → セル中心ピクセル座標。MoveRangeScene と揃える。
    def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// 現在表示している敵 id（出ていなければ None）
    pub def currentEnemyId(scene: Scene[NodeTag]): Option[Int32] =
        match Scene.getState(enemyRangePath(), scene) {
            case Some(NodeTag.EnemyRange(data)) => Some(data#enemyId)
            case _                              => None
        }

    /// 現在の reachable セル一覧（テスト・デバッグ用）。未登録なら空リスト。
    pub def reachable(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(enemyRangePath(), scene) {
            case Some(NodeTag.EnemyRange(data)) => data#reachable
            case _                              => Nil
        }
}
