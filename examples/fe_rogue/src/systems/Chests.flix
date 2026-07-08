/// Chests — フロアに置かれる宝箱（ローグだけが開けられる）
///
/// scene ノードは持たない。存在/中身の権威は World.chests（`Cmd.SpawnChest/RemoveChest/
/// ClearChests`）、描画は `RenderWorld.renderChests` が chestKey→ChestCatalog の sprite から直描きする。
///
/// 設計の要:
///   - **中身は配置時(`add`)に確定**して `Data#content` に格納する。`add` は `Math.Random` と
///     catalogs を持つのでここで `pickWeighted` + `GroundItems.lookupItem` を済ませる。これにより
///     開錠側(`ActionMenuScene.applyOpenChest`)は Math.Random も catalogs も要さず決定論的に振る舞える。
///   - 配置は駒(味方/敵)・床アイテム・階段・既配置の宝箱と重ならないセルにのみ行う。
///   - 開錠で World から削除する(`takeAt`)。開封済み状態は持たず、同セルを再度踏んでも宝箱は出ない。
mod Chests {

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

    /// 宝箱スプライトの zIndex（床より上、ユニット(=10)より下、床アイテム(=5)のすぐ上）。
    /// `RenderWorld.renderChests` が直描き時に使うため pub。
    pub def chestZIndex(): Int32 = 6

    /// フロアごとに宝箱が出現する確率（宝箱は希少な報酬なので低め＝約 1/3 = 3 フロアに 1 回）。
    /// 出現が当たったフロアだけ `chestsPerFloor` の数を置く（外れたフロアは 0 個）。
    def chestSpawnChance(): Float64 = 0.33

    // ─── 構築 ─────────────────────────────────────────────────

    /// フロアに宝箱を配置する。配置数は `floor#chestsPerFloor` の min..max からランダム、
    /// 種別は `floor#chests` の重み付きプール、中身は各宝箱種別の `contents` プールから抽選する。
    /// 占有回避: 味方/敵/床アイテム/階段/既に置いた宝箱のセルを避ける。
    /// 階段配置(`Stairs.placeRandom`)の後に呼ぶ前提（階段セルを `World.stairsPosOf` で読むため）。
    pub def add(chestCatalog: ChestCatalog.ChestCatalog,
                 catalog: UnitCatalog.UnitCatalog,
                 staffCatalog: Staff.StaffCatalog,
                 consumableCatalog: Consumable.ConsumableCatalog,
                 ringCatalog: Ring.RingCatalog,
                 floor: FloorCatalog.FloorResource): Unit \ {Math.Random, World.Command, World.WorldQuery} =
        // 宝箱は希少: フロアごとに chestSpawnChance の確率でのみ出現させる
        // （外れたフロアは 0 個）。`and` の短絡で chests 空なら乱数は引かない。
        let willSpawn = not List.isEmpty(floor#chests)
                          and Math.Random.randomFloat64() < chestSpawnChance();
        let count = FloorCatalog.randomCountInRange(floor#chestsPerFloor);
        if (not willSpawn or count <= 0) ()
        else {
            let world0     = World.WorldQuery.get();
            let placements = World.placementsOf(world0);
            let roomCount  = World.roomCountOf(world0);
            let occupied   = occupiedCells();
            // 第一候補は anchor(idx=0, 開始部屋)を除いた部屋の空き床セル。
            let nonAnchor = freeCellsIn(p -> p#idx >= 1 and p#idx < roomCount, placements, occupied);
            // 狭いフロアで非anchor部屋が埋まっていると候補が枯れて 1 個も置けないため、
            // その場合だけ開始部屋(idx=0)の空き床にフォールバックして「最低限は必ず出す」。
            let candidates =
                if (List.isEmpty(nonAnchor))
                    freeCellsIn(p -> p#idx == 0, placements, occupied)
                else nonAnchor;
            placeChests(count, candidates,
                         chestCatalog, catalog, staffCatalog, consumableCatalog, ringCatalog, floor)
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
    /// 階段位置は World.stairsPos から読む（build 中の placeRandom→SetStairs emit は
    /// read-after-write で見える）。
    def occupiedCells(): List[{x = Int32, y = Int32}] \ World.WorldQuery =
        let units = List.append(
            PlayerScene.getAll() |> List.map(d -> d#gridPos),
            EnemyScene.getAll()  |> List.map(d -> d#gridPos));
        let items = World.groundItemsOf(World.WorldQuery.get()) |> Map.valuesOf |> List.map(d -> d#gridPos);
        let stairs = Option.toList(World.stairsPosOf(World.WorldQuery.get()));
        List.append(units, List.append(items, stairs))

    def isOccupied(cell: {x = Int32, y = Int32},
                    occupied: List[{x = Int32, y = Int32}]): Bool =
        List.exists(o -> o#x == cell#x and o#y == cell#y, occupied)

    /// 候補セルから 1 つ選び、宝箱種別と中身を抽選して 1 個置く、を `remaining` 回くり返す。
    /// `forM` で「セル選択 → 種別抽選 → 中身抽選」を 1 本の Option 連鎖に畳み、どれかが無ければ
    /// その回で打ち切る（候補/プール枯渇時に安全に止まる）。
    def placeChests(remaining: Int32,
                     candidates: List[{x = Int32, y = Int32}],
                     chestCatalog: ChestCatalog.ChestCatalog,
                     catalog: UnitCatalog.UnitCatalog,
                     staffCatalog: Staff.StaffCatalog,
                     consumableCatalog: Consumable.ConsumableCatalog,
                     ringCatalog: Ring.RingCatalog,
                     floor: FloorCatalog.FloorResource): Unit \ {Math.Random, World.Command} =
        if (remaining <= 0) ()
        else {
            let chosen = forM (
                cell      <- RandomUtil.pick(candidates);
                chestKey  <- FloorCatalog.pickWeighted(floor#chests);
                contentId <- FloorCatalog.pickWeighted(ChestCatalog.lookup(chestKey, chestCatalog)#contents)
            ) yield {
                let content = GroundItems.lookupItem(contentId, catalog, staffCatalog, consumableCatalog, ringCatalog);
                (cell, chestKey, contentId, content)
            };
            match chosen {
                case None => ()
                case Some((cell, chestKey, contentId, content)) =>
                    addOneChest(cell, chestKey, contentId, content);
                    placeChests(remaining - 1, removeCell(cell, candidates),
                                 chestCatalog, catalog, staffCatalog, consumableCatalog, ringCatalog, floor)
            }
        }

    def removeCell(cell: {x = Int32, y = Int32},
                    cells: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        List.filter(c -> not (c#x == cell#x and c#y == cell#y), cells)

    /// 宝箱 1 個ぶんを配置する＝`Cmd.SpawnChest` を emit して World store を更新する。
    /// scene ノードは書かない（描画は `RenderWorld.renderChests` が World から直描き）。
    def addOneChest(cell: {x = Int32, y = Int32},
                     chestKey: String, contentId: String,
                     content: GroundItemKind): Unit \ World.Command =
        let data: Data = {gridPos = cell, chestKey = chestKey, contentId = contentId, content = content};
        World.Command.emit(World.Cmd.SpawnChest(data))

    /// 指定セルの宝箱を除去する＝`Cmd.RemoveChest` を emit（開錠後に呼ぶ）。
    /// World store に居るときだけ emit。
    pub def takeAt(coord: {x = Int32, y = Int32}): Unit \ {World.Command, World.WorldQuery} =
        match World.chestAtOf(coord, World.WorldQuery.get()) {
            case Some(_) => World.Command.emit(World.Cmd.RemoveChest(coord))
            case None    => ()
        }

    /// 現在の宝箱を `ChestSnap` 列（セル座標 ＋ 箱種別 id ＋ 中身 id）に射影する（スナップショット保存用）。
    /// `chestKey` / `contentId` は Data が保持するので逆引き不要。
    /// 射影元は **World の chests store**（存在の権威）。並び順は cellKey 昇順（GroundItems と同じ注記）。
    pub def captureSnaps(): List[FloorSnapshot.ChestSnap] \ World.WorldQuery =
        World.chestsOf(World.WorldQuery.get())
            |> Map.valuesOf
            |> List.map(d ->
            ({gridPos = d#gridPos, chestKey = d#chestKey, contentId = d#contentId}: FloorSnapshot.ChestSnap))

    /// スナップショットの宝箱リストから決定論的に再配置する（乱数なし）。
    /// `contentId` で中身を catalog から引き直して `addOneChest`（Cmd emit）で置く。
    pub def addFromSnaps(snaps: List[FloorSnapshot.ChestSnap],
                          _chestCatalog: ChestCatalog.ChestCatalog,
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog): Unit \ World.Command =
        List.forEach(snap -> {
            let content = GroundItems.lookupItem(snap#contentId, catalog, staffCatalog, consumableCatalog, ringCatalog);
            addOneChest(snap#gridPos, snap#chestKey, snap#contentId, content)
        }, snaps)

    // fog の lit ゲートは `RenderWorld.renderChests` が直描き時に判定する。
}
