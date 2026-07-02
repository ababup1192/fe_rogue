/// GroundItems — ダンジョン床に落ちている拾える武器（ground item）
///
/// `buildPlayingScene` の流れで `add` を呼ぶと、各部屋の床セルからランダムに `dropsPerRoom`
/// 個まで選んで、`weapons` カタログからランダム抽選した武器をそのセルに落とす。
/// プレイヤーが同じセルに乗ると（重量が許せば自動で）、または ActionMenu で「ひろう」を選ぶと
/// `PlayerScene.pickupFloorItem` で取り出してインベントリに加える。
///
/// scene ノードは撤去済み。存在/中身/点滅位相の権威は World.groundItems
/// （`Cmd.SpawnItem/RemoveItem/ClearItems`・elapsed は stepWorld が tick）、描画は
/// `RenderWorld.renderItems` が spriteOf(kind) から本体＋縁取り 4 枚を直描きする。
///
/// 設計メモ:
///   - 1 セルに 1 アイテムまで（同セル重複は事前フィルタで弾く）
///   - 敵/味方のスポーンセルは避ける
///   - アイテムノードを Sprite2D で表示。武器の `sprite` を使う
mod GroundItems {

    use JsonCompat.PathTag.Root

    // ─── 状態 ─────────────────────────────────────────────────

    /// 個別 ground item に紐づくデータ。
    /// `itemKey` はカタログ id (weapons / staves のどちらかに登録された id)。
    /// `item` は実体（拾う時にプレイヤーに渡す用）。
    /// `elapsed` は点滅サイクル内の経過時間（`tickAll` で進める）。
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        itemKey = String,
        item    = ItemData.GroundItemKind,
        elapsed = Duration.Duration
    }

    /// アイテム種別から sprite を取り出すヘルパー（表示・縁取り構築で共通利用）。
    pub def spriteOf(kind: ItemData.GroundItemKind): Sprite.SpriteResource = match kind {
        case ItemData.GroundItemKind.WeaponItem(weapon)   => weapon#sprite
        case ItemData.GroundItemKind.StaffItem(staff)     => staff#sprite
        case ItemData.GroundItemKind.ConsumableItem(item) => item#sprite
        case ItemData.GroundItemKind.RingItem(ring)       => ring#sprite
    }

    /// アイテム種別から表示名を取り出すヘルパー（`spriteOf` と対称）。
    /// 「○○の上に乗った」ログなど、種別を問わず名前だけ欲しい場面で使う。
    pub def kindDisplayName(kind: ItemData.GroundItemKind): String = match kind {
        case ItemData.GroundItemKind.WeaponItem(weapon)   => weapon#name
        case ItemData.GroundItemKind.StaffItem(staff)     => staff#name
        case ItemData.GroundItemKind.ConsumableItem(item) => item#name
        case ItemData.GroundItemKind.RingItem(ring)       => ring#name
    }

    // ─── 定数 ─────────────────────────────────────────────────

    /// Sprite の zIndex（床より上、Sprite (=10) より下に置く）。renderItems が使うため pub。
    pub def spriteZIndex(): Int32 = 5

    /// 縁取り Sprite の zIndex（アイテム本体のすぐ下）。
    pub def outlineZIndex(): Int32 = 4

    /// 縁取りの色。マルチプライで暗い武器ピクセルが黒に潰れるのを補うため、
    /// b は 1.0 超に振って GPU クランプで明るい青を引き出す
    pub def outlineColor(): Color = {r = 0.3f32, g = 0.7f32, b = 4.0f32}

    /// 通常時のアウトライン不透明度（薄っすら）
    def baseAlpha(): Float32 = 0.35f32

    /// 「光った」瞬間のアウトライン不透明度
    def peakAlpha(): Float32 = 1.0f32

    /// 1 サイクル（次の点滅までの間隔）
    def cycleDuration(): Duration.Duration = Duration.seconds(2.0)

    /// サイクル先頭で「光っている」時間。この間に三角波で base→peak→base と変化する
    def pulseDuration(): Duration.Duration = Duration.seconds(0.3)

    /// 4 方向 (suffix, 描画オフセット) ペア。renderItems が使うため pub。
    pub def outlineDeltas(): List[(String, Vec2.Vec2)] =
        ("n", ({x =  0.0, y = -1.0}: Vec2.Vec2)) ::
        ("s", ({x =  0.0, y =  1.0}: Vec2.Vec2)) ::
        ("e", ({x =  1.0, y =  0.0}: Vec2.Vec2)) ::
        ("w", ({x = -1.0, y =  0.0}: Vec2.Vec2)) :: Nil

    // per-room cap は引数で受け取る floor の `itemsPerRoom` を使う (resource 駆動)。

    // ─── 構築 ─────────────────────────────────────────────────

    /// 部屋の床セルに floor の `items` (percent 配列) から重み付き抽選したアイテムを配置する。
    /// `items` の id は **weapons catalog → staves catalog → consumables catalog の順** で解決される。
    /// player / enemy が居るセルは避ける。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                 staffCatalog: Staff.StaffCatalog,
                 consumableCatalog: Consumable.ConsumableCatalog,
                 ringCatalog: Ring.RingCatalog,
                 floor: FloorCatalog.FloorResource,
                 scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Math.Random, World.Command} =
        let items = floor#items;
        if (List.isEmpty(items)) scene
        else {
            let layer       = MapScene.getMapLayer(scene);
            let placements  = MapScene.getPlacements(scene);
            let roomCount   = MapScene.getRoomCount(scene);
            // 既存のユニットセルを taken に入れて避ける。
            // 構築時 (buildPlayingScene) は sceneRef が更新前なので PartyQuery/RosterQuery では
            // なく scene 引数を直接読む。
            let occupied =
                List.append(
                    PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
                    EnemyScene.getAll(scene) |> List.map(d -> d#gridPos));
            // anchor (idx=0) を除いた部屋だけを対象にする
            let rooms = List.filter(p ->
                p#idx >= 1 and p#idx < roomCount, placements);
            // (nextId, takenCells, dropList) を畳み込み
            let initial: (Int32, List[{x = Int32, y = Int32}],
                           List[(Int32, {x = Int32, y = Int32}, String, ItemData.GroundItemKind)]) =
                (0, occupied, Nil);
            let range = floor#itemsPerRoom;
            let (_, _, accDrops) = List.foldLeft(state -> p ->
                dropsInRoom(layer, p, FloorCatalog.randomCountInRange(range),
                             items, catalog, staffCatalog, consumableCatalog, ringCatalog, state),
                initial, rooms);
            let drops = List.reverse(accDrops);
            // ノードは積まない＝Cmd spawn のみ（点滅の初期位相 stagger は id で付与）。
            List.foldLeft((acc, drop) -> {
                let (id, cell, key, kind) = drop;
                addOneItem(id, cell, key, kind, acc)
            }, scene, drops)
        }

    /// id を weapons catalog → staves catalog → consumables catalog の順で引いて、
    /// 見つかった方を ADT で返す。どれにも無ければ起動時 typo として panic。
    /// 宝箱の中身解決(`Chests.add`)でも同じ id→GroundItemKind 規則を共有するため pub。
    pub def lookupItem(id: String,
                    catalog: UnitCatalog.UnitCatalog,
                    staffCatalog: Staff.StaffCatalog,
                    consumableCatalog: Consumable.ConsumableCatalog,
                    ringCatalog: Ring.RingCatalog): ItemData.GroundItemKind =
        // weapons → staves → consumables → rings の順に引いて最初に当たった種別を採用する。
        // 各カタログ引きを Option で並べ、先頭の Some を取る形にする（match ネストにしない）。
        let candidates =
            (Map.get(id, UnitCatalog.weaponsOf(catalog))             |> Option.map(w -> ItemData.GroundItemKind.WeaponItem(w))) ::
            (Map.get(id, Staff.stavesOf(staffCatalog))               |> Option.map(s -> ItemData.GroundItemKind.StaffItem(s))) ::
            (Map.get(id, Consumable.consumablesOf(consumableCatalog)) |> Option.map(c -> ItemData.GroundItemKind.ConsumableItem(c))) ::
            (Map.get(id, Ring.ringsOf(ringCatalog))                  |> Option.map(r -> ItemData.GroundItemKind.RingItem(r))) :: Nil;
        match List.filterMap(o -> o, candidates) {
            case kind :: _ => kind
            case Nil       =>
                bug!("GroundItems.lookupItem: id '${id}' not in weapons / staves / consumables / rings catalog")
        }

    /// アイテム 1 個ぶんを配置する＝`Cmd.SpawnItem` を emit して World store を更新する。
    /// 描画は `RenderWorld.renderItems` が World から直描きするため scene ノードは積まない。
    /// `idx` は点滅の初期位相 stagger（同時点滅回避）にだけ使う。
    def addOneItem(idx: Int32, cell: {x = Int32, y = Int32},
                    itemKey: String, item: ItemData.GroundItemKind,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let initElapsed = Duration.seconds(0.4 * Int32.toFloat64(idx));
        let data: Data = {
            gridPos = cell, itemKey = itemKey, item = item,
            elapsed = initElapsed
        };
        World.Command.emit(World.Cmd.SpawnItem(data));
        scene

    /// 部屋 1 つから count 個のドロップセルを選び state に積む。
    /// 各セルにつき floor の `items` (percent 配列) から重み付き抽選した id を
    /// weapons → staves → consumables の順で解決して配置する。
    def dropsInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     items: List[FloorCatalog.SpawnEntry],
                     catalog: UnitCatalog.UnitCatalog,
                     staffCatalog: Staff.StaffCatalog,
                     consumableCatalog: Consumable.ConsumableCatalog,
                     ringCatalog: Ring.RingCatalog,
                     state: (Int32, List[{x = Int32, y = Int32}],
                              List[(Int32, {x = Int32, y = Int32}, String, ItemData.GroundItemKind)])):
                    (Int32, List[{x = Int32, y = Int32}],
                     List[(Int32, {x = Int32, y = Int32}, String, ItemData.GroundItemKind)])
                    \ Math.Random =
        if (count <= 0) state
        else {
            let (nextId, taken, list) = state;
            let candidates = floorCellsInRoom(layer, p)
                              |> List.filter(c -> not isTaken(c, taken));
            match RandomUtil.pick(candidates) {
                case None       => state
                case Some(cell) =>
                    match FloorCatalog.pickWeighted(items) {
                        case None     => state
                        case Some(id) =>
                            let kind = lookupItem(id, catalog, staffCatalog, consumableCatalog, ringCatalog);
                            let entry = (nextId, cell, id, kind);
                            dropsInRoom(layer, p, count - 1, items, catalog,
                                         staffCatalog, consumableCatalog, ringCatalog,
                                         (nextId + 1, cell :: taken, entry :: list))
                    }
            }
        }

    /// 「offset + 半開 bbox(boundsMin..boundsMaxEx)」内で床述語 `isFloorAt` を満たすセルを列挙する
    /// 純粋関数。床判定の供給元（`TileMapLayer` 等）に依存しないので単体テストできる。
    /// `floorCellsInRoom` の純粋コア（engine 非依存）。
    pub def floorCellsInBounds(isFloorAt: {x = Int32, y = Int32} -> Bool,
                                offset: {x = Int32, y = Int32},
                                boundsMin: {x = Int32, y = Int32},
                                boundsMaxEx: {x = Int32, y = Int32}): List[{x = Int32, y = Int32}] =
        let minX = offset#x + boundsMin#x;
        let minY = offset#y + boundsMin#y;
        let maxX = offset#x + boundsMaxEx#x;
        let maxY = offset#y + boundsMaxEx#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> isFloorAt(c),
                List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32}), xs)),
            ys)

    /// 部屋の bbox（offset + floorBounds）に含まれる床セルを列挙する（EnemyScene と同じロジック）。
    /// n-format で通路の床がアイテム候補に混ざらないよう floorBounds で絞る。
    /// 純粋コア `floorCellsInBounds` に床述語（TileMapLayer 床判定）を注入する薄いシェル。
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        floorCellsInBounds(c -> TileMapLayer.isFloor(c, layer),
                            p#offset, p#floorBoundsMin, p#floorBoundsMaxEx)

    /// セル `c` が既取得リスト `taken` に含まれるか（同セル二重ドロップ防止）。
    pub def isTaken(c: {x = Int32, y = Int32}, taken: List[{x = Int32, y = Int32}]): Bool = // pub: 単体テスト用に公開
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    // ─── クエリ ───────────────────────────────────────────────
    // 読みは World.groundItemAtOf / groundItemsOf が唯一の経路。

    /// 指定セルのアイテムを除去してアイテム実体を返す＝`Cmd.RemoveItem` を emit。
    /// World store に居るときだけ emit。scene は素通し。
    pub def takeAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]):
            (Scene[NodeTag], Option[ItemData.GroundItemKind]) \ {World.Command, World.WorldQuery} =
        match World.groundItemAtOf(coord, World.WorldQuery.get()) {
            case None    => (scene, None)
            case Some(d) =>
                World.Command.emit(World.Cmd.RemoveItem(coord));
                (scene, Some(d#item))
        }

    /// 現在の床アイテムを `ItemSnap` 列（セル座標 ＋ 種別 id）に射影する（スナップショット保存用）。
    /// 床アイテムは `itemKey`（id）を持つので逆引き不要。
    /// 射影元は World の groundItems store。並び順は cellKey 昇順で、決定論・セーブ形式とも不変
    /// （復元は位置キーで意味論同一）。
    pub def captureSnaps(_scene: Scene[NodeTag]): List[FloorSnapshot.ItemSnap] \ World.WorldQuery =
        World.groundItemsOf(World.WorldQuery.get())
            |> Map.valuesOf
            |> List.map(d -> ({gridPos = d#gridPos, itemKey = d#itemKey}: FloorSnapshot.ItemSnap))

    /// スナップショットの床アイテムリストから決定論的に再配置する（乱数なし）。
    /// `itemKey` で種別を catalog から引き直し `respawn` で置く。
    pub def addFromSnaps(snaps: List[FloorSnapshot.ItemSnap],
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        List.foldLeft((acc, snap) -> {
            let kind = lookupItem(snap#itemKey, catalog, staffCatalog, consumableCatalog, ringCatalog);
            respawn(snap#gridPos, snap#itemKey, kind, acc)
        }, scene, snaps)

    /// `takeAt` の逆操作として、アイテムを `cell` に再配置する＝`Cmd.SpawnItem` を emit。
    /// P6-1e: 点滅位相は 0 から（旧 idx 由来 stagger は spawn 経路のみ）。
    pub def respawn(cell: {x = Int32, y = Int32}, itemKey: String,
                     kind: ItemData.GroundItemKind, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        addOneItem(0, cell, itemKey, kind, scene)

    // P6-1e: 旧 applyFog（可視トグル）と step（点滅 tick）は撤去。lit ゲートと縁取り alpha は
    // `RenderWorld.renderItems` が描画時に判定し、elapsed は `World.stepWorld` が tick する。

    /// `elapsed` をサイクル長で巻き戻す。`Duration` に mod 演算がなく float 誤差も避けたいため、
    /// dt が cycle 未満であることを前提に 1 回の減算で対応する。P6-1e: stepWorld から呼ぶため pub。
    pub def advance(e: Duration.Duration): Duration.Duration =
        if (Duration.toSeconds(e) >= Duration.toSeconds(cycleDuration()))
            Duration.sub(e, cycleDuration())
        else e

    /// サイクル先頭 `pulseDuration` の間は base→peak→base の三角波、それ以外は base 固定。
    /// P6-1e: renderItems が縁取り alpha に使うため pub。
    pub def pulseAlpha(elapsed: Duration.Duration): Float32 =
        let e = Duration.toSeconds(elapsed);
        let p = Duration.toSeconds(pulseDuration());
        if (e < p) {
            let t = e / p;                              // 0..1
            let tri = 1.0 - Float64.abs(2.0 * t - 1.0); // 0..1..0
            let b = Float32.toFloat64(baseAlpha());
            let pk = Float32.toFloat64(peakAlpha());
            Float64.truncateToFloat32(b + (pk - b) * tri)
        } else baseAlpha()

}
