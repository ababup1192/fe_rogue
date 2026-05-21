/// MoveRangeScene — プレイヤーの「今ターン移動可能なマス」を可視化する
///
/// FE 風のターン制移動を提供する。プレイヤーの現在位置から 4 方向 BFS で
/// `maxMoveTiles` ステップ以内の床セルを `Board.reachableCells` で求め、
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
        reachable = List[{x = Int32, y = Int32}]
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

    /// MapScene + PlayerScene が登録済みのシーンに MoveRange ノードと各セルの Sprite2D
    /// 子を追加する。**選択中プレイヤー** の位置を origin に `Board.reachableCells`
    /// で範囲を求める。未選択（PlayerCursor / EnemyTurn 等）なら何も描画しない。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None     => scene   // 未選択 → 表示なし
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case None    => scene   // 既に居ない（防御的）
                    case Some(_) => buildFor(id, scene)
                }
        }

    /// 指定 id を起点に MoveRange を組み立てる本体（既存ノードは事前に取り除いてから呼ぶ）。
    /// **通行不可**: 壁 / 敵駒。
    /// **味方駒は通過可能**（1 マスとしてカウント）。FE 流の「味方は素通り、ただし停止はできない」
    /// 表現。`Board.reachableForUnit` で到達範囲を出し、`stoppableForUnit` で味方マス
    /// （自分 + 他味方）を除いたものを青マスとして描画する。AutoMove も同じプリミティブで
    /// 動くため、ここで仕様が一致していれば自動で挙動が揃う。
    def buildFor(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let board  = BoardSnapshot.fromScene(scene);
        let origin = PlayerScene.getGridPos(id, scene);
        let steps  = PlayerScene.getMoveTiles(id, scene);
        let cells     = Board.reachableForUnit(board, origin, steps);
        let drawCells = Board.stoppableForUnit(board, origin, steps);
        scene
            |> addParent(cells)
            |> addTileChildren(drawCells)

    /// 既存の MoveRange ノードを丸ごと取り除いて `add` で組み直す。
    pub def refresh(scene: Scene[NodeTag]): Scene[NodeTag] \ SelectedPlayer.State =
        Scene.removeAt(moveRangePath(), scene) |> add

    /// 表示中の MoveRange ノードがあれば取り除く。なければ何もしない。
    /// PlayerAttack フェーズ移行時など、青マスを一時的に消したいときに使う
    /// （`EnemyRangeScene.clear` と対称）。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(moveRangePath(), scene)

    /// 親 Marker2D を origin (0,0) に追加する（位置はマップと同じワールド系）。
    def addParent(cells: List[{x = Int32, y = Int32}], scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addNode(name(),
            EngineNode.Marker2DWithState(parent, NodeTag.MoveRange({reachable = cells})),
            scene)

    /// `cells` を順に列挙して半透明 Sprite2D を `Tile_<idx>` として子追加する。
    /// `Vec2.one()` スケールで、テクスチャ自身を 16×16 として描く前提。
    def addTileChildren(cells: List[{x = Int32, y = Int32}], scene: Scene[NodeTag]): Scene[NodeTag] =
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

    /// グリッド座標 → セル中心ピクセル座標。MapScene の `mapToLocal` 慣習に揃える。
    def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// 指定セルが「現在のターンで踏める」範囲内にあるか。
    /// `MoveRange` ノードが未登録なら false を返す（ゲーム初期化前のフォールバック）。
    pub def isInRange(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#reachable)
            case _ => false
        }

    /// 現在範囲のセル一覧（テスト・デバッグ用）。未登録なら空リスト。
    pub def reachable(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) => data#reachable
            case _ => Nil
        }
}
