/// ItemScene — ダンジョン床に落ちている拾える武器（ground item）
///
/// `buildPlayingScene` の流れで `add` を呼ぶと、各部屋の床セルからランダムに `dropsPerRoom`
/// 個まで選んで、`weapons` カタログからランダム抽選した武器をそのセルに落とす。
/// プレイヤーが同じセルに乗ったあと ActionMenu で「ひろう」を選ぶと
/// `pickupAt` で取り出してインベントリに加える。
///
/// ノード構造:
///   World/Items (Marker2D, 永続的な親)
///     ├─ Item_0 (Sprite2D, NodeTag.GroundItem({gridPos, weaponKey, weapon}))
///     ├─ Item_1 (...)
///     └─ ...
///
/// 設計メモ:
///   - 1 セルに 1 アイテムまで（同セル重複は事前フィルタで弾く）
///   - 敵/味方のスポーンセルは避ける
///   - アイテムノードを Sprite2D で表示。武器の `sprite` を使う
mod ItemScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ─── 状態 ─────────────────────────────────────────────────

    /// 個別 ground item に紐づくデータ。
    /// `weaponKey` はカタログ id で再ロード時にも復元できる。
    /// `weapon` は WeaponResource 実体（拾う時にプレイヤーに渡す用）。
    pub type alias Data = {
        gridPos   = {x = Int32, y = Int32},
        weaponKey = String,
        weapon    = UnitCatalog.WeaponResource
    }

    // ─── 定数 ─────────────────────────────────────────────────

    def parentName(): String = "Items"
    pub def parentPath(): NodePath = MapScene.worldName() :: parentName() :: Nil

    /// `Item_<n>` 形式のノード名
    def itemName(idx: Int32): String = "Item_${idx}"

    /// 1 タイル幅（PlayerScene 等と共通）
    def tileSize(): Float64 = 16.0

    /// Sprite の zIndex（床より上、Sprite (=10) より下に置く）
    def spriteZIndex(): Int32 = 5

    /// 1 部屋あたり最大何個落とすか
    def dropsPerRoom(): Int32 = 1

    // ─── 構築 ─────────────────────────────────────────────────

    /// 部屋の床セルにランダムで武器を配置する。
    /// player / enemy が居るセルは避ける。
    pub def add(catalog: UnitCatalog.UnitCatalog, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Math.Random =
        let weaponsMap = UnitCatalog.weaponsOf(catalog);
        let weaponEntries = Map.toList(weaponsMap);  // List[(String, WeaponResource)]
        if (List.isEmpty(weaponEntries)) scene
        else {
            let layer       = MapScene.getMapLayer(scene);
            let placements  = MapScene.getPlacements(scene);
            let roomCount   = MapScene.getRoomCount(scene);
            // 既存のユニットセルを taken に入れて避ける
            let occupied =
                List.append(
                    PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
                    EnemyScene.getAll(scene) |> List.map(d -> d#gridPos));
            // anchor (idx=0) を除いた部屋だけを対象にする
            let rooms = List.filter(p ->
                p#idx >= 1 and p#idx < roomCount, placements);
            // (nextId, takenCells, dropList) を畳み込み
            let initial: (Int32, List[{x = Int32, y = Int32}],
                           List[(Int32, {x = Int32, y = Int32}, String, UnitCatalog.WeaponResource)]) =
                (0, occupied, Nil);
            let (_, _, accDrops) = List.foldLeft(state -> p ->
                dropsInRoom(layer, p, dropsPerRoom(), weaponEntries, state),
                initial, rooms);
            let drops = List.reverse(accDrops);
            // 親 Marker2D + 各 Item Sprite2D を追加
            let withParent = ensureParent(scene);
            List.foldLeft((acc, drop) -> {
                let (id, cell, key, weapon) = drop;
                addOneItem(id, cell, key, weapon, acc)
            }, withParent, drops)
        }

    /// 親 Marker2D を Items として World 配下に生やす（既にあれば何もしない）。
    def ensureParent(scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(parentPath(), scene) {
            case Some(_) => scene
            case None    =>
                let parent = Marker2D.make(Vec2.zero());
                Scene.addChildAt(MapScene.worldPath(), parentName(),
                    EngineNode.Marker2DWithState(parent, NodeTag.NoTag), scene)
        }

    /// アイテム 1 個ぶんの Sprite2D を World/Items 配下に追加する。
    def addOneItem(idx: Int32, cell: {x = Int32, y = Int32},
                    weaponKey: String, weapon: UnitCatalog.WeaponResource,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        // セル中心 + sprite#offset で sheet padding を補正した位置に置く
        let pos: Vec2.Vec2 = {
            x = Int32.toFloat64(cell#x) * s + s / 2.0 + weapon#sprite#offset#x,
            y = Int32.toFloat64(cell#y) * s + s / 2.0 + weapon#sprite#offset#y
        };
        let sprite = Sprite2D.make(weapon#sprite#texture, pos, Vec2.one())
            |> Sprite2D.setHframes(weapon#sprite#hframes)
            |> Sprite2D.setVframes(weapon#sprite#vframes)
            |> Sprite2D.setFrame(weapon#sprite#frame)
            |> CanvasItem.setZIndex(spriteZIndex());
        let data: Data = {gridPos = cell, weaponKey = weaponKey, weapon = weapon};
        Scene.addChildAt(parentPath(), itemName(idx),
            EngineNode.Sprite2DWithState(sprite, NodeTag.GroundItem(data)), scene)

    /// 部屋 1 つから count 個のドロップセルを選び state に積む。
    def dropsInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     weaponEntries: List[(String, UnitCatalog.WeaponResource)],
                     state: (Int32, List[{x = Int32, y = Int32}],
                              List[(Int32, {x = Int32, y = Int32}, String, UnitCatalog.WeaponResource)])):
                    (Int32, List[{x = Int32, y = Int32}],
                     List[(Int32, {x = Int32, y = Int32}, String, UnitCatalog.WeaponResource)])
                    \ Math.Random =
        if (count <= 0) state
        else {
            let (nextId, taken, list) = state;
            let candidates = floorCellsInRoom(layer, p)
                              |> List.filter(c -> not isTaken(c, taken));
            match RandomUtil.pick(candidates) {
                case None       => state
                case Some(cell) =>
                    match RandomUtil.pick(weaponEntries) {
                        case None              => state
                        case Some((key, weapon)) =>
                            let entry = (nextId, cell, key, weapon);
                            dropsInRoom(layer, p, count - 1, weaponEntries,
                                         (nextId + 1, cell :: taken, entry :: list))
                    }
            }
        }

    /// 部屋の bbox に含まれる床セルを列挙する（EnemyScene と同じロジック）
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        let minX = p#offset#x;
        let minY = p#offset#y;
        let maxX = p#offset#x + p#gridSize#x;
        let maxY = p#offset#y + p#gridSize#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> TileMapLayer.isFloor(c, layer),
                List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32}), xs)),
            ys)

    def isTaken(c: {x = Int32, y = Int32}, taken: List[{x = Int32, y = Int32}]): Bool =
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    // ─── クエリ ───────────────────────────────────────────────

    /// 指定セルに落ちているアイテムの (path, weapon) を返す。無ければ None。
    pub def findAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]): Option[(NodePath, UnitCatalog.WeaponResource)] =
        let childNames = Scene.getChildrenAt(parentPath(), scene);
        List.findMap(name -> {
            let path = List.append(parentPath(), name :: Nil);
            match Scene.getState(path, scene) {
                case Some(NodeTag.GroundItem(d)) =>
                    if (d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                        Some((path, d#weapon))
                    else None
                case _ => None
            }
        }, childNames)

    /// 指定セルのアイテムを scene から取り除いて武器を返す。
    /// 拾う操作の本体。
    pub def takeAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]):
            (Scene[NodeTag], Option[UnitCatalog.WeaponResource]) =
        match findAt(coord, scene) {
            case None              => (scene, None)
            case Some((path, w))   => (Scene.removeAt(path, scene), Some(w))
        }
}
