/// ChestScene — フロアに置かれる宝箱（ローグだけが開けられる）
///
/// 床アイテム(`ItemScene`)と同じく、World 配下の親 `Chests` に複数の Sprite2D を動的に並べる。
/// 床アイテムと違い「開ける」主体がクラス制限(ローグ)を持ち、中身は開けるまで見えない。
///
/// ノード構造（Cursor/Stairs と並列のトップレベル）:
///   World/Chests (Marker2D, 永続的な親)
///     ├─ Chest_0 (Sprite2D, NodeTag.Chest({gridPos, chestKey, content}))
///     └─ ...
///
/// 設計の要:
///   - **中身は配置時(`add`)に確定**して `Data#content` に格納する。`add` は `Math.Random` と
///     catalogs を持つのでここで `pickWeighted` + `ItemScene.lookupItem` を済ませる。これにより
///     開錠側(`ActionMenuScene.applyOpenChest`)は Math.Random も catalogs も要さず決定論的に振る舞える。
///   - 配置は駒(味方/敵)・床アイテム・階段・既配置の宝箱と重ならないセルにのみ行う。
///   - 開錠でノードごと削除する(`takeAt`)。開封済み状態は持たず、同セルを再度踏んでも宝箱は出ない。
mod ChestScene {

    use ItemData.GroundItemKind

    /// 宝箱 1 個ぶんの状態。
    /// `chestKey` は出典の宝箱種別 id（ログ/デバッグ用に保持）。
    /// `content` は開錠時に渡す中身。配置時に重み付き抽選で確定済み（開錠で再抽選はしない）。
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        chestKey = String,
        // 中身アイテムのカタログ id（配置時の抽選結果）。スナップショット保存で `content` を id 参照に
        // 落とすために保持する（`content` は resource を wrap していて id を持たないため）。
        contentId = String,
        content  = GroundItemKind
    }

    def parentName(): String = "Chests"
    pub def parentPath(): NodePath = MapScene.worldName() :: parentName() :: Nil

    /// `Chest_<n>` 形式のノード名
    def chestName(idx: Int32): String = "Chest_${idx}"

    /// 宝箱スプライトの zIndex（床より上、ユニット(=10)より下、床アイテム(=5)のすぐ上）。
    def chestZIndex(): Int32 = 6

    /// フロアごとに宝箱が出現する確率（宝箱は希少な報酬なので低め＝約 1/3 = 3 フロアに 1 回）。
    /// 出現が当たったフロアだけ `chestsPerFloor` の数を置く（外れたフロアは 0 個）。
    def chestSpawnChance(): Float64 = 0.33

    // ─── 構築 ─────────────────────────────────────────────────

    /// フロアに宝箱を配置する。配置数は `floor#chestsPerFloor` の min..max からランダム、
    /// 種別は `floor#chests` の重み付きプール、中身は各宝箱種別の `contents` プールから抽選する。
    /// 占有回避: 味方/敵/床アイテム/階段/既に置いた宝箱のセルを避ける。
    /// 階段配置(`StairsScene.placeRandom`)の後に呼ぶ前提（階段セルを `StairsScene.getPos` で読むため）。
    pub def add(chestCatalog: ChestCatalog.ChestCatalog,
                 catalog: UnitCatalog.UnitCatalog,
                 staffCatalog: Staff.StaffCatalog,
                 consumableCatalog: Consumable.ConsumableCatalog,
                 ringCatalog: Ring.RingCatalog,
                 floor: FloorCatalog.FloorResource,
                 scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        // 宝箱は希少: フロアごとに chestSpawnChance の確率でのみ出現させる
        // （外れたフロアは 0 個）。`and` の短絡で chests 空なら乱数は引かない。
        let willSpawn = not List.isEmpty(floor#chests)
                          and Math.Random.randomFloat64() < chestSpawnChance();
        let count = FloorCatalog.randomCountInRange(floor#chestsPerFloor);
        if (not willSpawn or count <= 0) scene
        else {
            let placements = MapScene.getPlacements(scene);
            let roomCount  = MapScene.getRoomCount(scene);
            let occupied   = occupiedCells(scene);
            // 第一候補は anchor(idx=0, 開始部屋)を除いた部屋の空き床セル。
            let nonAnchor = freeCellsIn(p -> p#idx >= 1 and p#idx < roomCount, placements, occupied);
            // 狭いフロアで非anchor部屋が埋まっていると候補が枯れて 1 個も置けないため、
            // その場合だけ開始部屋(idx=0)の空き床にフォールバックして「最低限は必ず出す」。
            let candidates =
                if (List.isEmpty(nonAnchor))
                    freeCellsIn(p -> p#idx == 0, placements, occupied)
                else nonAnchor;
            let withParent = ensureParent(scene);
            placeChests(count, 0, candidates,
                         chestCatalog, catalog, staffCatalog, consumableCatalog, ringCatalog, floor, withParent)
        }

    /// 述語 `roomPred` を満たす部屋の interiorCells のうち、占有されていない床セルを集める。
    def freeCellsIn(roomPred: DungeonComposer.ModulePlacement -> Bool,
                     placements: List[DungeonComposer.ModulePlacement],
                     occupied: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        placements
            |> List.filter(roomPred)
            |> List.flatMap(p -> p#interiorCells)
            |> List.filter(c -> not isOccupied(c, occupied))

    /// 駒(味方/敵) + 床アイテム + 階段 のセルを 1 本のリストに集める（配置時の回避集合）。
    def occupiedCells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        let units = List.append(
            PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
            EnemyScene.getAll(scene)  |> List.map(d -> d#gridPos));
        let items = ItemScene.getAllPositions(scene);
        let stairs = Option.toList(StairsScene.getPos(scene));
        List.append(units, List.append(items, stairs))

    def isOccupied(cell: {x = Int32, y = Int32},
                    occupied: List[{x = Int32, y = Int32}]): Bool =
        List.exists(o -> o#x == cell#x and o#y == cell#y, occupied)

    /// 候補セルから 1 つ選び、宝箱種別と中身を抽選して 1 個置く、を `remaining` 回くり返す。
    /// `forM` で「セル選択 → 種別抽選 → 中身抽選」を 1 本の Option 連鎖に畳み、どれかが無ければ
    /// その回で打ち切る（候補/プール枯渇時に安全に止まる）。
    def placeChests(remaining: Int32, idx: Int32,
                     candidates: List[{x = Int32, y = Int32}],
                     chestCatalog: ChestCatalog.ChestCatalog,
                     catalog: UnitCatalog.UnitCatalog,
                     staffCatalog: Staff.StaffCatalog,
                     consumableCatalog: Consumable.ConsumableCatalog,
                     ringCatalog: Ring.RingCatalog,
                     floor: FloorCatalog.FloorResource,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        if (remaining <= 0) scene
        else {
            let chosen = forM (
                cell      <- RandomUtil.pick(candidates);
                chestKey  <- FloorCatalog.pickWeighted(floor#chests);
                contentId <- FloorCatalog.pickWeighted(ChestCatalog.lookup(chestKey, chestCatalog)#contents)
            ) yield {
                let chest = ChestCatalog.lookup(chestKey, chestCatalog);
                let content = ItemScene.lookupItem(contentId, catalog, staffCatalog, consumableCatalog, ringCatalog);
                (cell, chestKey, contentId, chest#sprite, content)
            };
            match chosen {
                case None => scene
                case Some((cell, chestKey, contentId, sprite, content)) =>
                    let placed = addOneChest(idx, cell, chestKey, contentId, sprite, content, scene);
                    placeChests(remaining - 1, idx + 1, removeCell(cell, candidates),
                                 chestCatalog, catalog, staffCatalog, consumableCatalog, ringCatalog, floor, placed)
            }
        }

    def removeCell(cell: {x = Int32, y = Int32},
                    cells: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        List.filter(c -> not (c#x == cell#x and c#y == cell#y), cells)

    /// 宝箱 1 個ぶんの Sprite2D を World/Chests 配下に追加する。
    def addOneChest(idx: Int32, cell: {x = Int32, y = Int32},
                     chestKey: String, contentId: String, sprite: Sprite.SpriteResource,
                     content: GroundItemKind, scene: Scene[NodeTag]): Scene[NodeTag] =
        let center = MapSnapshot.cellCenter(cell);
        let pos: Vec2.Vec2 = {x = center#x + sprite#offset#x, y = center#y + sprite#offset#y};
        let node = Sprite2D.make(sprite#texture, pos, Vec2.one())
            |> Sprite2D.setHframes(sprite#hframes)
            |> Sprite2D.setVframes(sprite#vframes)
            |> Sprite2D.setFrame(sprite#frame)
            |> CanvasItem.setZIndex(chestZIndex());
        let data: Data = {gridPos = cell, chestKey = chestKey, contentId = contentId, content = content};
        Scene.addChildAt(parentPath(), chestName(idx),
            EngineNode.Sprite2DWithState(node, NodeTag.Chest(data)), scene)

    /// 親 Marker2D を Chests として World 配下に生やす（既にあれば何もしない）。
    def ensureParent(scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(parentPath(), scene) {
            case Some(_) => scene
            case None    =>
                let parent = Marker2D.make(Vec2.zero());
                Scene.addChildAt(MapScene.worldPath(), parentName(),
                    EngineNode.Marker2DWithState(parent, NodeTag.NoTag), scene)
        }

    // ─── クエリ / 取得 ─────────────────────────────────────────

    /// 指定セルの宝箱ノードのパスと Data を返す。`findAt` / `takeAt` の共通コア。
    def entryAt(coord: {x = Int32, y = Int32},
                 scene: Scene[NodeTag]): Option[(NodePath, Data)] =
        let childNames = Scene.getChildrenAt(parentPath(), scene);
        List.findMap(name -> {
            let path = List.append(parentPath(), name :: Nil);
            match Scene.getState(path, scene) {
                case Some(NodeTag.Chest(d)) =>
                    if (d#gridPos#x == coord#x and d#gridPos#y == coord#y) Some((path, d))
                    else None
                case _ => None
            }
        }, childNames)

    /// 指定セルに宝箱があれば Data を返す。ActionMenu が「あける」の出現条件・開錠処理で使う。
    pub def findAt(coord: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Option[Data] =
        entryAt(coord, scene) |> Option.map(pair -> { let (_, d) = pair; d })

    /// 指定セルの宝箱ノードを scene から取り除く（開錠後に呼ぶ）。無ければ何もしない。
    pub def takeAt(coord: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        entryAt(coord, scene)
            |> Option.map(pair -> { let (path, _) = pair; Scene.removeAt(path, scene) })
            |> Option.getWithDefault(scene)

    /// 配置済み全宝箱のグリッド座標（占有判定・ミニマップ表示など読み取り用途）。
    pub def getAllPositions(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        let childNames = Scene.getChildrenAt(parentPath(), scene);
        List.foldLeft((acc, name) -> {
            let path = List.append(parentPath(), name :: Nil);
            match Scene.getState(path, scene) {
                case Some(NodeTag.Chest(d)) => d#gridPos :: acc
                case _                       => acc
            }
        }, Nil, childNames)

    /// 配置済み全宝箱の Data を返す（スナップショット保存用）。
    pub def getAll(scene: Scene[NodeTag]): List[Data] =
        Scene.getChildrenAt(parentPath(), scene)
            |> List.filterMap(name ->
                match Scene.getState(List.append(parentPath(), name :: Nil), scene) {
                    case Some(NodeTag.Chest(d)) => Some(d)
                    case _                       => None
                })

    /// 現在の宝箱を `ChestSnap` 列（セル座標 ＋ 箱種別 id ＋ 中身 id）に射影する（スナップショット保存用）。
    /// `chestKey` / `contentId` は Data が保持するので逆引き不要。
    pub def captureSnaps(scene: Scene[NodeTag]): List[FloorSnapshot.ChestSnap] =
        getAll(scene) |> List.map(d ->
            ({gridPos = d#gridPos, chestKey = d#chestKey, contentId = d#contentId}: FloorSnapshot.ChestSnap))

    /// スナップショットの宝箱リストから決定論的に再配置する（乱数なし）。`chestKey` で sprite を、
    /// `contentId` で中身を catalog から引き直して `addOneChest` で置く。
    pub def addFromSnaps(snaps: List[FloorSnapshot.ChestSnap],
                          chestCatalog: ChestCatalog.ChestCatalog,
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        if (List.isEmpty(snaps)) scene
        else {
            let withParent = ensureParent(scene);
            let indexed = List.zip(List.range(0, List.length(snaps)), snaps);
            List.foldLeft((acc, pair) -> {
                let (idx, snap) = pair;
                let sprite  = ChestCatalog.lookup(snap#chestKey, chestCatalog)#sprite;
                let content = ItemScene.lookupItem(snap#contentId, catalog, staffCatalog, consumableCatalog, ringCatalog);
                addOneChest(idx, snap#gridPos, snap#chestKey, snap#contentId, sprite, content, acc)
            }, withParent, indexed)
        }

    /// フォグ適用: 各宝箱を「現在地が lit なら表示、さもなくば非表示」にする。
    /// `FogScene` から毎フレーム呼ばれる（床アイテム/階段と同じ visible トグル）。
    pub def applyFog(isLit: {x = Int32, y = Int32} -> Bool,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        let childNames = Scene.getChildrenAt(parentPath(), scene);
        List.foldLeft((acc, name) -> {
            let path = List.append(parentPath(), name :: Nil);
            match Scene.getState(path, acc) {
                case Some(NodeTag.Chest(d)) =>
                    Sprite2D.mapAt(path, CanvasItem.setVisible(isLit(d#gridPos)), acc)
                case _ => acc
            }
        }, scene, childNames)
}
