/// MoveRangeScene — プレイヤーの「今ターン移動可能なマス」を可視化する
///
/// FE 風のターン制移動を提供する。プレイヤーの現在位置から 4 方向 BFS で
/// `maxMoveTiles` ステップ以内の床セルを `BoardLogic.reachableCells` で求め、
/// 各セルに半透明の `move_tile` Sprite2D を子として並べる。
///
/// ノード構造:
///   MoveRange (Marker2D, NodeTag.MoveRange({reachable}))
///     ├─ Tile_0 (Sprite2D, alpha=0.5)
///     ├─ Tile_1 (Sprite2D, alpha=0.5)
///     └─ ...
///
/// 親 Marker2D は world (0,0) に置く。MapScene の TileMapLayer も (0,0) なので、
/// 子 Sprite2D は `セル中心 = grid * tileSize + tileSize/2` を直接 position にすれば
/// マップと同じ座標系でぴったり重なる。
///
/// **ターン遷移**:
///   - `add` を初回・リロード時に 1 回呼んで現在位置から範囲を構築する。
///   - `Game.flix` の InputHandler が決定キー (Z / Space / Enter) のエッジを拾い、
///     `refresh` を呼ぶと 範囲を消して新しい原点で再構築する。
///   - 範囲は `MoveRangeScene.isInRange` 経由で `PlayerScene.physicsProcess` から
///     参照され、移動先の許可判定に使われる（範囲外のマスへは踏み込めない）。
mod MoveRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `reachable` は BFS で到達可能と判定されたセル一覧（origin を含む）。
    pub type alias Data = {
        reachable = List[Vec2.Vec2i]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "MoveRange"
    pub def moveRangePath(): NodePath = name() :: Nil

    /// `move_tile` 用テクスチャ名（Main.flix の textureManifest と整合）
    def textureName(): String = "move_tile"

    /// LDTK 由来のタイルサイズ（ピクセル）。MapScene と同じ 16px 正方形を前提。
    def tileSize(): Float64 = 16.0

    /// move_tile の不透明度。プレイヤーや床タイルが透けて見える程度の半透明。
    def tileAlpha(): Float32 = 1.0f32

    /// move_tile に乗せる青の modulate 色。Floor 装飾レイヤーの上で
    /// 移動可能マスとして識別しやすいように青寄りに着色する。
    def tileColor(): Color = {r = 0.3f32, g = 0.5f32, b = 1.0f32}

    /// move_tile スプライトの描画 zIndex。tilemap (= 0) より上、Player の Sprite (= 10)
    /// より下に来るように 1 を採用する。プレイヤーが常に最前面に立つ。
    def tileZIndex(): Int32 = 1

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene が登録済みのシーンに MoveRange ノードと
    /// 各セルの Sprite2D 子を追加する。プレイヤー現在位置を origin に
    /// `BoardLogic.reachableCells` で範囲を求める。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer  = MapScene.getMapLayer(scene);
        let origin = PlayerScene.getGridPos(scene);
        // 移動力はキャラごとに違う想定なので Player の Data から読む。
        // MoveRangeScene はマス数の出所を 1 か所（PlayerScene.Data#moveTiles）に集約する。
        let steps  = PlayerScene.getMoveTiles(scene);
        let cells  = BoardLogic.reachableCells(
            c -> TileMapLayer.isFloor(c, layer),
            origin,
            steps);
        // 描画は origin（プレイヤーが立っているマス）を除外する：自分自身のマスに
        // move_tile を敷くと視覚的に冗長で、プレイヤーの足元が必要以上に染まる。
        // ただし `reachable` 自体は origin を含めたまま保持しておく（isInRange の
        // 整合性 / 将来の用途に備える）。
        let drawCells = List.filter(c -> not (c#x == origin#x and c#y == origin#y), cells);
        scene
            |> addParent(cells)
            |> addTileChildren(drawCells)

    /// 既存の MoveRange ノードを丸ごと取り除いて `add` で組み直す。
    /// 「ターンエンド」相当の操作。プレイヤー位置が更新されている前提で呼ぶ。
    pub def refresh(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(moveRangePath(), scene) |> add

    /// 親 Marker2D を origin (0,0) に追加する（位置はマップと同じワールド系）。
    def addParent(cells: List[Vec2.Vec2i], scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.MoveRange({reachable = cells})),
            scene)

    /// `cells` を順に列挙して半透明 Sprite2D を `Tile_<idx>` として子追加する。
    /// `Vec2.one()` スケールで、テクスチャ自身を 16×16 として描く前提。
    def addTileChildren(cells: List[Vec2.Vec2i], scene: Scene[NodeTag]): Scene[NodeTag] =
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

    /// グリッド座標 → セル中心ピクセル座標。MapScene の `mapToLocal` 慣習に揃える。
    def cellCenter(cell: Vec2.Vec2i): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2.fromI(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// 指定セルが「現在のターンで踏める」範囲内にあるか。
    /// `MoveRange` ノードが未登録なら false を返す（ゲーム初期化前のフォールバック）。
    pub def isInRange(cell: Vec2.Vec2i, scene: Scene[NodeTag]): Bool =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#reachable)
            case _ => false
        }

    /// 現在範囲のセル一覧（テスト・デバッグ用）。未登録なら空リスト。
    pub def reachable(scene: Scene[NodeTag]): List[Vec2.Vec2i] =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) => data#reachable
            case _ => Nil
        }
}
