/// PlayerAttackRangeScene — 攻撃フェーズ中に味方の射程を赤色で可視化する
///
/// `EnemyRangeScene` のミラー実装で、起点が「ホバー中の敵」ではなく「味方」になる。
/// 射程は装備中武器の `WeaponResource#range` から取る。range = 1 なら隣接 4 マス、
/// range = 2 なら十字に 2 マスずつ伸びる（くんれんゆみ等の間接攻撃）。
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
        cells = List[{x = Int32, y = Int32}]
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

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 既存の PlayerAttackRange ノードがあれば取り除き、**選択中プレイヤー** の現在位置
    /// origin に対して装備中武器の `range` で赤マスを敷き直す。
    /// 未選択時は cleared を返す（赤マス表示なし）。
    /// 選択中プレイヤーの武器が壊れている（`weapons = Nil`）場合は cells を空にして
    /// 親ノードだけ追加する。これにより PlayerAttack フェーズに入ってもカーソルが
    /// 敵に乗らず、Z 押下で AttackHit が発火しない（X でスキップして抜ける）。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        let cleared = clear(scene);
        match SelectedPlayer.State.get()#id {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.get(id, cleared) {
                    case None    => cleared
                    case Some(d) =>
                        let cells = match List.head(d#weapons) {
                            case None    => Nil  // 武器なし → 射程ゼロ
                            case Some(w) =>
                                let origin = d#gridPos;
                                let layer  = MapScene.getMapLayer(cleared);
                                computeAttackCells(origin, w#range, layer)
                        };
                        cleared
                            |> addParent(cells)
                            |> addTileChildren(cells)
                }
        }

    /// 表示中の PlayerAttackRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(attackRangePath(), scene)

    /// 範囲計算の純粋関数。
    /// origin から **マンハッタン距離** `range#min..range#max` (inclusive) にある全セルを
    /// 列挙する (= 菱形パターン)。斜め (1,1) もマンハッタン距離 2 として含まれる。
    /// 例:
    ///   `{min=1, max=1}` → 隣接 4 セル (剣・槍)
    ///   `{min=2, max=2}` → 距離 2 の 8 セル (弓: 上下左右 2 マス先 + 斜め 1 マス)
    ///   `{min=1, max=2}` → 距離 1〜2 の 12 セル (手槍・手斧)
    /// 地形フィルタはかけない: 壁・味方・床いずれの上にも赤マスを描いて「武器の届く範囲」
    /// を一貫表示する (実際に攻撃できるのは敵セルだけで、その判定は TurnRules 側)。
    /// `layer` 引数は将来の terrain-aware フィルタ用に残してある (現状 unused)。
    pub def computeAttackCells(origin: {x = Int32, y = Int32},
                                range: UnitCatalog.WeaponRange,
                                _layer: TileMapLayer): List[{x = Int32, y = Int32}] =
        let lo = Int32.max(1, range#min);
        let hi = range#max;
        if (hi < lo) Nil
        else
            let coords = List.range(-hi, hi + 1);
            List.flatMap(dx ->
                List.foldRight(dy -> acc -> {
                    let d = Int32.abs(dx) + Int32.abs(dy);
                    if (d >= lo and d <= hi) {
                        let cell: {x = Int32, y = Int32} =
                            {x = origin#x + dx, y = origin#y + dy};
                        cell :: acc
                    } else acc
                }, Nil, coords),
                coords)

    // ────────────────────────────────────────────────────────
    // 内部: ノード追加
    // ────────────────────────────────────────────────────────

    /// 親 Marker2D を origin (0, 0) に追加する（MapScene と同じワールド系で重ねる）。
    def addParent(cells: List[{x = Int32, y = Int32}],
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        let data: Data = { cells = cells };
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.PlayerAttackRange(data)),
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

    /// グリッド座標 → セル中心ピクセル座標。EnemyRangeScene / MoveRangeScene と揃える。
    def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// 指定セルが現在の射程内（赤マス上）にあるか。
    /// 範囲が表示されていない（= フェーズが PlayerAttack ではない）場合は false。
    pub def isInRange(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#cells)
            case _ => false
        }

    /// 現在の射程内セル一覧（テスト・デバッグ用）。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) => data#cells
            case _ => Nil
        }

    /// 赤マス内に居る「生きている敵」の Data リストを reading order (y 昇順 → x 昇順)
    /// で返す。`PlayerAttack` フェーズでカーソルを敵間でサイクルさせる用。
    /// 死亡演出中 (`isDying`) と HP 0 以下の敵は除外する。
    pub def targetsInRange(scene: Scene[NodeTag]): List[EnemyScene.Data] =
        let inRangeCells = cells(scene);
        EnemyScene.getAll(scene)
            |> List.filter(d ->
                not d#isDying
                and d#hp > 0
                and List.exists(c ->
                    c#x == d#gridPos#x and c#y == d#gridPos#y,
                    inRangeCells))
            |> List.sortBy(d -> (d#gridPos#y, d#gridPos#x))
}
