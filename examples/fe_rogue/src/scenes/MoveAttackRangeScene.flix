/// MoveAttackRangeScene — 「移動先のいずれかから攻撃が届くセル」を赤マスで可視化する
///
/// 目的: 移動先を決める前に「ここに動けばあそこの敵を攻撃できる」「ここに動くと
/// この敵の射程に入る」が一目で分かるようにする。Fire Emblem 風の脅威範囲表示。
///
/// 描画ルール:
///   - 表示中: `PlayerMoving` / `ActionSelect` フェーズ
///   - セル集合 = ⋃ {reachable のセル c から武器射程 (`min..max` マンハッタン) で
///                 届くセル} − reachable 自身
///     (= 「移動マスとは別のところ」だけ赤で出す。重なるなら青を優先)
///   - 武器なし / 射程ゼロなら何も描かない
///   - 地形フィルタはかけない (壁・床問わず射程を一貫表示)
///
/// ノード構造:
///   MoveAttackRange (Marker2D, NodeTag.MoveAttackRange({cells}))
///     ├─ Tile_0 (Sprite2D, alpha=0.5, modulate=red)
///     ├─ Tile_1 ...
///
/// **ライフサイクル**:
///   - `MoveRangeScene.refresh` の直後に `MoveAttackRangeScene.refresh` を呼ぶ
///     (reachable に依存するので、青マスを組み立てた後でないとデータが取れない)
///   - `MoveRangeScene.clear` の直後に `MoveAttackRangeScene.clear` を呼ぶ
mod MoveAttackRangeScene {

    /// 親 Marker2D に紐づくデータ。reachable と重複しない「赤マスだけ」のセル一覧。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    def name(): String = "MoveAttackRange"
    pub def rangePath(): NodePath = name() :: Nil

    def textureName(): String = "move_tile"
    def tileSize(): Float64 = 16.0

    /// PlayerAttackRangeScene と同じ赤系 modulate。
    /// alpha は青マス (0.5–1.0) より少し透けさせて区別する。
    def tileAlpha(): Float32 = 0.5f32
    def tileColor(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// MoveRange (青) と同じ z (= 1)。重ならない set 設計なので前後関係は実害なし。
    def tileZIndex(): Int32 = 1

    /// 既存ノードを取り除いて再構築する。`MoveRangeScene` の青マスが既に build 済みの
    /// 前提で、その reachable を読み取って差集合を作る。
    pub def refresh(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        let cleared = clear(scene);
        match SelectedPlayer.State.get()#id {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.get(id, cleared) {
                    case None         => cleared
                    case Some(player) =>
                        match List.head(player#weapons) {
                            case None    => cleared     // 武器なし
                            case Some(w) =>
                                let reachable = MoveRangeScene.reachable(cleared);
                                let cells = computeThreatCells(reachable, w#range);
                                if (List.isEmpty(cells)) cleared
                                else
                                    cleared
                                        |> addParent(cells)
                                        |> addTileChildren(cells)
                        }
                }
        }

    /// 表示中の MoveAttackRange ノードがあれば取り除く。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(rangePath(), scene)

    /// `reachable` の各セルから武器射程 (`min..max` マンハッタン) で届くセル集合を作り、
    /// reachable 自身は除外して返す。同一セルは 1 つにまとめる。
    pub def computeThreatCells(reachable: List[{x = Int32, y = Int32}],
                                range: UnitCatalog.WeaponRange):
                               List[{x = Int32, y = Int32}] =
        let lo = Int32.max(1, range#min);
        let hi = range#max;
        if (hi < lo or List.isEmpty(reachable)) Nil
        else
            let offsets = manhattanOffsets(lo, hi);
            let raw = List.flatMap(c ->
                List.map(o ->
                    ({x = c#x + o#x, y = c#y + o#y}: {x = Int32, y = Int32}),
                    offsets),
                reachable);
            // reachable 自身を除外しつつ、最初に出現したものだけ残す (順序保持の dedup)
            let init: {seen = List[{x = Int32, y = Int32}], out = List[{x = Int32, y = Int32}]} =
                {seen = reachable, out = Nil};
            let folded = List.foldLeft(acc -> cell -> {
                if (List.exists(s -> s#x == cell#x and s#y == cell#y, acc#seen)) acc
                else {seen = cell :: acc#seen, out = cell :: acc#out}
            }, init, raw);
            List.reverse(folded#out)

    /// `lo..hi` のマンハッタン距離内にあるオフセット (dx, dy) を全列挙する。
    def manhattanOffsets(lo: Int32, hi: Int32): List[{x = Int32, y = Int32}] =
        let coords = List.range(-hi, hi + 1);
        List.flatMap(dx ->
            List.foldRight(dy -> acc -> {
                let d = Int32.abs(dx) + Int32.abs(dy);
                if (d >= lo and d <= hi)
                    ({x = dx, y = dy}: {x = Int32, y = Int32}) :: acc
                else acc
            }, Nil, coords),
            coords)

    /// 親 Marker2D を origin (0, 0) に追加する (マップと同じワールド系)。
    def addParent(cells: List[{x = Int32, y = Int32}],
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        let data: Data = {cells = cells};
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.MoveAttackRange(data)),
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

    /// テスト・デバッグ用: 現在の脅威セル一覧。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.MoveAttackRange(data)) => data#cells
            case _ => Nil
        }
}
