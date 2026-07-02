/// Stairs — フロアの「次の階へ降りる階段」マーカー
///
/// 各フロアに 1 つだけ、床のランダムなセルに配置される。味方がそのセルに乗ると
/// 行動メニューに「かいだん」が出て、選ぶとその味方はマップから退場し次フロアへ進む。
///
/// P6-1c: scene ノードは撤去済み。位置の権威は World.stairsPos（`Cmd.SetStairs`）、描画は
/// `RenderWorld.renderStairs` が見た目定数（texture/scale/zIndex＝旧 scene.json 値）から直描きする。
/// `Data`/`getPos` は StaffCast の warp（杖）と golden fixture が手組みノードで使うテスト seam。
mod Stairs {

    /// `gridPos`: 階段を置いたグリッド座標（placed = false のときは未使用）
    /// `placed`: 階段が配置済みか。false の間は描画されず、`getPos` は None を返す
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        placed  = Bool
    }

    def name(): String = "Stairs"
    pub def stairsPath(): NodePath = name() :: Nil

    // ── P6-1c: 見た目定数（旧 `Stairs.scene.json` の Sprite2D 宣言から移設） ──
    /// project.json の "textures" に登録された階段テクスチャ名。
    pub def texture(): String = "stairs"
    /// タイル 16px に合わせた表示スケール。
    pub def spriteScale(): Vec2.Vec2 = {x = 0.65, y = 0.52}
    /// Floor(-1)/Walls(0) の上・Item(4,5)/Unit(10) の下。
    pub def spriteZIndex(): Int32 = 1

    /// 床セルからランダムに 1 つ選んで階段を配置する。
    /// 候補は「部屋の内部床セル かつ 駒（味方・敵）に占有されていない かつ 床アイテムが無い」セル。
    /// 部屋は anchor（プレイヤー初期配置, idx=0）を除いた idx 1..roomCount を対象にする
    /// （= 階段はスタート部屋以外に出す）。各部屋の `interiorCells`（decorTiles の world 座標）を
    /// そのまま使うので、door セル（通路の出入口）や通路の床は最初から候補に入らず、
    /// 階段が「通路にある」状態にならない。
    /// 候補が 1 つも無い極端なマップでは何もしない（階段は非表示のまま）。
    /// プレイヤー・敵・アイテム配置が済んだ後（= buildPlayingScene の末尾）に呼ぶ。
    pub def placeRandom(scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, World.Command, World.WorldQuery} =
        let placements = MapScene.getPlacements(scene);
        let roomCount  = MapScene.getRoomCount(scene);
        let occupied   = List.append(
            PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
            EnemyScene.getAll(scene)  |> List.map(d -> d#gridPos));
        // anchor (idx=0) を除いた部屋だけを候補に（idx >= 1 かつ idx < roomCount = 部屋）
        let rooms = List.filter(p -> p#idx >= 1 and p#idx < roomCount, placements);
        let candidates = rooms
            |> List.flatMap(p -> p#interiorCells)
            |> List.filter(cell ->
                not isOccupied(cell, occupied)
                and Option.isEmpty(World.groundItemAtOf(cell, World.WorldQuery.get())));
        match RandomUtil.pick(candidates) {
            case Some(cell) => placeAt(cell, scene)
            case None       => scene
        }

    def isOccupied(cell: {x = Int32, y = Int32},
                    occupied: List[{x = Int32, y = Int32}]): Bool =
        List.exists(o -> o#x == cell#x and o#y == cell#y, occupied)

    /// `target` セルに階段を配置する＝`Cmd.SetStairs(Some(cell))` を emit して World を更新する。
    /// P6-1c: scene ノード書きは撤去（描画は `RenderWorld.renderStairs` が World から直描き）。
    /// scene はパイプ互換のためそのまま返す。
    pub def placeAt(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetStairs(Some(target)));
        scene

    /// placed = false（未配置）のときは座標として意味のある値を持たないため None を返す。
    pub def getPos(scene: Scene[NodeTag]): Option[{x = Int32, y = Int32}] =
        match Scene.getState(stairsPath(), scene) {
            case Some(NodeTag.Stairs(data)) =>
                if (data#placed) Some(data#gridPos) else None
            case _ => None
        }

    // P6-1c: 旧 `mapStairs`/`applyFog`（scene ノードの可視制御）は撤去。fog の lit ゲートは
    // `RenderWorld.renderStairs` が直描き時に判定する。
}
