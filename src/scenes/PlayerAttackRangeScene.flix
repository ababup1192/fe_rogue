/// PlayerAttackRangeScene — 攻撃フェーズ中に味方の射程を赤色で可視化する
///
/// `EnemyRangeScene` のミラー実装で、起点が「ホバー中の敵」ではなく「味方」になる。
/// 直接攻撃 (range = 1) では味方の上下左右 4 マスを赤く表示する。
/// `computeAttackCells` を差し替えれば間接攻撃（range > 1 の十字）にも拡張できる。
///
/// ノード構造（出ているとき）:
///   PlayerAttackRange (Marker2D, NodeTag.PlayerAttackRange({cells}))
///     ├─ Tile_0 (Sprite2D, alpha=0.7, modulate=red)
///     ├─ Tile_1 ...
///
/// **ライフサイクル**:
///   - `PlayerMoving + Z` で `PlayerAttack` フェーズに入るとき `show(scene)` を呼んで
///     味方の現在位置を origin に赤マスを描く
///   - `PlayerAttack` を抜ける（敵ターンへ移行）ときは `clear(scene)` で取り除く
///
/// 既存 `EnemyRangeScene` と色・alpha・zIndex は揃える（同じ「赤マス」の意味）。
mod PlayerAttackRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `cells` は赤く描画されている射程内セル一覧（origin = 味方セルは含まない）。
    /// `isInRange` の判定に使う（カーソル clamp の述語）。
    pub type alias Data = {
        cells = List[Vec2.Vec2i]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "PlayerAttackRange"
    pub def attackRangePath(): NodePath = name() :: Nil

    /// `move_tile` テクスチャを赤く modulate して再利用する（EnemyRangeScene と同じ素材）
    def textureName(): String = "move_tile"

    /// LDTK 由来のタイルサイズ。MapScene と揃える。
    def tileSize(): Float64 = 16.0

    /// 不透明度。EnemyRangeScene と同じく少し透かして駒や床を見やすくする。
    def tileAlpha(): Float32 = 0.7f32

    /// 赤系 modulate。EnemyRangeScene と同色。
    def tileColor(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// MoveRange / EnemyRange と同じ階層。Player Sprite (= 10) より下。
    def tileZIndex(): Int32 = 1

    /// 直接攻撃の射程（マス）。FE 流の隣接 1 マス。
    /// 武器ごとに射程を変えたくなったら `show` 引数化するか、ここを read する側を増やす。
    pub def directRange(): Int32 = 1

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 既存の PlayerAttackRange ノードがあれば取り除き、**選択中プレイヤー** の現在位置
    /// origin に対して射程 = `directRange()` で赤マスを敷き直す。
    /// 未選択時は cleared を返す（赤マス表示なし）。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        let cleared = clear(scene);
        match SelectedPlayer.State.get() {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.get(id, cleared) {
                    case None    => cleared
                    case Some(d) =>
                        let origin = d#gridPos;
                        let layer  = MapScene.getMapLayer(cleared);
                        let cells  = computeAttackCells(origin, directRange(), layer);
                        cleared
                            |> addParent(cells)
                            |> addTileChildren(cells)
                }
        }

    /// 表示中の PlayerAttackRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(attackRangePath(), scene)

    /// 範囲計算の純粋関数。**間接攻撃に拡張するときはここを差し替える**。
    /// 現状は origin から上下左右 4 方向に距離 1..range（inclusive）の十字パターンを出す。
    /// floor タイル以外（壁・voids）は除外して見た目を整える。
    pub def computeAttackCells(origin: Vec2.Vec2i, range: Int32,
                                layer: TileMapLayer): List[Vec2.Vec2i] =
        if (range <= 0) Nil
        else
            let dists = List.range(1, range + 1);
            let candidates = List.flatMap(n ->
                ({x = origin#x,     y = origin#y - n}: Vec2.Vec2i)
                    :: ({x = origin#x,     y = origin#y + n}: Vec2.Vec2i)
                    :: ({x = origin#x - n, y = origin#y}: Vec2.Vec2i)
                    :: ({x = origin#x + n, y = origin#y}: Vec2.Vec2i)
                    :: Nil,
                dists);
            List.filter(c -> TileMapLayer.isFloor(c, layer), candidates)

    // ────────────────────────────────────────────────────────
    // 内部: ノード追加
    // ────────────────────────────────────────────────────────

    /// 親 Marker2D を origin (0, 0) に追加する（MapScene と同じワールド系で重ねる）。
    def addParent(cells: List[Vec2.Vec2i],
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        let data: Data = { cells = cells };
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.PlayerAttackRange(data)),
            scene)

    /// `cells` を順に列挙して半透明 Sprite2D を `Tile_<idx>` として子追加する。
    def addTileChildren(cells: List[Vec2.Vec2i],
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        let indexed = List.zip(List.range(0, List.length(cells)), cells);
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

    /// グリッド座標 → セル中心ピクセル座標。EnemyRangeScene / MoveRangeScene と揃える。
    def cellCenter(cell: Vec2.Vec2i): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2.fromI(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// 指定セルが現在の射程内（赤マス上）にあるか。
    /// 範囲が表示されていない（= フェーズが PlayerAttack ではない）場合は false。
    pub def isInRange(cell: Vec2.Vec2i, scene: Scene[NodeTag]): Bool =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#cells)
            case _ => false
        }

    /// 現在の射程内セル一覧（テスト・デバッグ用）。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[Vec2.Vec2i] =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) => data#cells
            case _ => Nil
        }
}
