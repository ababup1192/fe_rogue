/// ItemScene — ダンジョン床に落ちている拾える武器（ground item）
///
/// `buildPlayingScene` の流れで `add` を呼ぶと、各部屋の床セルからランダムに `dropsPerRoom`
/// 個まで選んで、`weapons` カタログからランダム抽選した武器をそのセルに落とす。
/// プレイヤーが同じセルに乗ったあと ActionMenu で「ひろう」を選ぶと
/// `pickupAt` で取り出してインベントリに加える。
///
/// ノード構造:
///   World/Items (Marker2D, 永続的な親)
///     ├─ Item_0 (Sprite2D, NodeTag.GroundItem({gridPos, itemKey, item}))
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

    /// ground item の中身。武器 (`WeaponItem`) と杖 (`StaffItem`) を区別する ADT。
    /// 拾うとプレイヤーの weapons / staves リストに追加される。
    pub enum GroundItemKind {
        case WeaponItem(UnitCatalog.WeaponResource)
        case StaffItem(Staff.StaffResource)
    }

    /// 個別 ground item に紐づくデータ。
    /// `itemKey` はカタログ id (weapons / staves のどちらかに登録された id)。
    /// `item` は実体（拾う時にプレイヤーに渡す用）。
    /// `elapsed` は点滅サイクル内の経過時間（`tickAll` で進める）。
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        itemKey = String,
        item    = GroundItemKind,
        elapsed = Duration.Duration
    }

    /// アイテム種別から sprite を取り出すヘルパー（表示・縁取り構築で共通利用）。
    pub def spriteOf(kind: GroundItemKind): UnitCatalog.SpriteResource = match kind {
        case GroundItemKind.WeaponItem(weapon) => weapon#sprite
        case GroundItemKind.StaffItem(staff)   => staff#sprite
    }

    // ─── 定数 ─────────────────────────────────────────────────

    def parentName(): String = "Items"
    pub def parentPath(): NodePath = MapScene.worldName() :: parentName() :: Nil

    /// `Item_<n>` 形式のノード名
    def itemName(idx: Int32): String = "Item_${idx}"

    /// `Item_<n>_outline_<dir>` 形式の縁取り兄弟ノード名
    def outlineName(idx: Int32, suffix: String): String = "Item_${idx}_outline_${suffix}"

    /// Sprite の zIndex（床より上、Sprite (=10) より下に置く）
    def spriteZIndex(): Int32 = 5

    /// 縁取り Sprite の zIndex（アイテム本体のすぐ下）
    def outlineZIndex(): Int32 = 4

    /// 縁取りの色。マルチプライで暗い武器ピクセルが黒に潰れるのを補うため、
    /// b は 1.0 超に振って GPU クランプで明るい青を引き出す
    def outlineColor(): Color = {r = 0.3f32, g = 0.7f32, b = 4.0f32}

    /// 通常時のアウトライン不透明度（薄っすら）
    def baseAlpha(): Float32 = 0.35f32

    /// 「光った」瞬間のアウトライン不透明度
    def peakAlpha(): Float32 = 1.0f32

    /// 1 サイクル（次の点滅までの間隔）
    def cycleDuration(): Duration.Duration = Duration.seconds(2.0)

    /// サイクル先頭で「光っている」時間。この間に三角波で base→peak→base と変化する
    def pulseDuration(): Duration.Duration = Duration.seconds(0.3)

    /// 4 方向 (suffix, 描画オフセット) ペア
    def outlineDeltas(): List[(String, Vec2.Vec2)] =
        ("n", ({x =  0.0, y = -1.0}: Vec2.Vec2)) ::
        ("s", ({x =  0.0, y =  1.0}: Vec2.Vec2)) ::
        ("e", ({x =  1.0, y =  0.0}: Vec2.Vec2)) ::
        ("w", ({x = -1.0, y =  0.0}: Vec2.Vec2)) :: Nil

    def outlineSuffixes(): List[String] = "n" :: "s" :: "e" :: "w" :: Nil

    // per-room cap は引数で受け取る floor の `itemsPerRoom` を使う (resource 駆動)。
    // 旧 `dropsPerRoom()` 定数は floor 駆動化で廃止

    // ─── 構築 ─────────────────────────────────────────────────

    /// 部屋の床セルに floor の `items` (percent 配列) から重み付き抽選したアイテムを配置する。
    /// `items` の id は **weapons catalog → staves catalog の順** で解決される。
    /// player / enemy が居るセルは避ける。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                 staffCatalog: Staff.StaffCatalog,
                 floor: FloorCatalog.FloorResource,
                 scene: Scene[NodeTag]):
            Scene[NodeTag] \ Math.Random =
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
                           List[(Int32, {x = Int32, y = Int32}, String, GroundItemKind)]) =
                (0, occupied, Nil);
            let range = floor#itemsPerRoom;
            let (_, _, accDrops) = List.foldLeft(state -> p ->
                dropsInRoom(layer, p, FloorCatalog.randomCountInRange(range),
                             items, catalog, staffCatalog, state),
                initial, rooms);
            let drops = List.reverse(accDrops);
            // 親 Marker2D + 各 Item Sprite2D を追加
            let withParent = ensureParent(scene);
            List.foldLeft((acc, drop) -> {
                let (id, cell, key, kind) = drop;
                addOneItem(id, cell, key, kind, acc)
            }, withParent, drops)
        }

    /// id を weapons catalog → staves catalog の順で引いて、見つかった方を ADT で返す。
    /// どちらにも無ければ起動時 typo として panic。
    def lookupItem(id: String,
                    catalog: UnitCatalog.UnitCatalog,
                    staffCatalog: Staff.StaffCatalog): GroundItemKind =
        match Map.get(id, UnitCatalog.weaponsOf(catalog)) {
            case Some(weapon) => GroundItemKind.WeaponItem(weapon)
            case None         =>
                match Map.get(id, Staff.stavesOf(staffCatalog)) {
                    case Some(staff) => GroundItemKind.StaffItem(staff)
                    case None        =>
                        bug!("ItemScene.lookupItem: id '${id}' not in weapons / staves catalog")
                }
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
    /// 視認性のため 4 方向 1px シフトの縁取り Sprite を先に重ね、本体を上に置く。
    def addOneItem(idx: Int32, cell: {x = Int32, y = Int32},
                    itemKey: String, item: GroundItemKind,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let sprite0 = spriteOf(item);
        // セル中心 + sprite#offset で sheet padding を補正した位置に置く
        let center = MapScene.cellCenter(cell);
        let pos: Vec2.Vec2 = {
            x = center#x + sprite0#offset#x,
            y = center#y + sprite0#offset#y
        };
        // フレーム指定済みのスプライト構築ヘルパ。エンジンは Sprite2D#offset を描画時に無視するため、
        // 縁取りのずらしは position 自体に乗せる（Node2D の position フィールドが globalPos に伝播する）。
        let makeFramed = (p: Vec2.Vec2) ->
            Sprite2D.make(sprite0#texture, p, Vec2.one())
                |> Sprite2D.setHframes(sprite0#hframes)
                |> Sprite2D.setVframes(sprite0#vframes)
                |> Sprite2D.setFrame(sprite0#frame);
        // 4 方向の縁取りを先に追加（NodeTag.NoTag、本体より低い zIndex、薄い青）
        let withOutlines = List.foldLeft((acc, entry) -> {
            let (suffix, delta) = entry;
            let outlinePos: Vec2.Vec2 = {x = pos#x + delta#x, y = pos#y + delta#y};
            let outline = makeFramed(outlinePos)
                |> Sprite2D.setAlpha(baseAlpha())
                |> CanvasItem.setModulate(outlineColor())
                |> CanvasItem.setZIndex(outlineZIndex());
            Scene.addChildAt(parentPath(), outlineName(idx, suffix),
                EngineNode.Sprite2DWithState(outline, NodeTag.NoTag), acc)
        }, scene, outlineDeltas());
        let sprite = makeFramed(pos) |> CanvasItem.setZIndex(spriteZIndex());
        // idx でスタガーして同時点滅を避ける
        let initElapsed = Duration.seconds(0.4 * Int32.toFloat64(idx));
        let data: Data = {
            gridPos = cell, itemKey = itemKey, item = item,
            elapsed = initElapsed
        };
        Scene.addChildAt(parentPath(), itemName(idx),
            EngineNode.Sprite2DWithState(sprite, NodeTag.GroundItem(data)), withOutlines)

    /// 部屋 1 つから count 個のドロップセルを選び state に積む。
    /// 各セルにつき floor の `items` (percent 配列) から重み付き抽選した id を
    /// weapons → staves の順で解決して配置する。
    def dropsInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     items: List[FloorCatalog.SpawnEntry],
                     catalog: UnitCatalog.UnitCatalog,
                     staffCatalog: Staff.StaffCatalog,
                     state: (Int32, List[{x = Int32, y = Int32}],
                              List[(Int32, {x = Int32, y = Int32}, String, GroundItemKind)])):
                    (Int32, List[{x = Int32, y = Int32}],
                     List[(Int32, {x = Int32, y = Int32}, String, GroundItemKind)])
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
                            let kind = lookupItem(id, catalog, staffCatalog);
                            let entry = (nextId, cell, id, kind);
                            dropsInRoom(layer, p, count - 1, items, catalog,
                                         staffCatalog,
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

    /// 指定セルに落ちているアイテムの (path, item) を返す。無ければ None。
    pub def findAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]): Option[(NodePath, GroundItemKind)] =
        let childNames = Scene.getChildrenAt(parentPath(), scene);
        List.findMap(name -> {
            let path = List.append(parentPath(), name :: Nil);
            match Scene.getState(path, scene) {
                case Some(NodeTag.GroundItem(d)) =>
                    if (d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                        Some((path, d#item))
                    else None
                case _ => None
            }
        }, childNames)

    /// 指定セルのアイテムを scene から取り除いてアイテム実体を返す。
    /// 本体ノードと一緒に 4 つの縁取り兄弟ノードも消す。
    pub def takeAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]):
            (Scene[NodeTag], Option[GroundItemKind]) =
        match findAt(coord, scene) {
            case None              => (scene, None)
            case Some((path, kind)) =>
                let cleaned = scene
                    |> removeOutlinesFor(path)
                    |> Scene.removeAt(path);
                (cleaned, Some(kind))
        }

    /// `Item_<n>` のパスから 4 つの兄弟 `Item_<n>_outline_<dir>` を削除する。
    def removeOutlinesFor(itemPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, suffix) ->
            Scene.removeAt(outlinePathOf(itemPath, suffix), acc),
            scene, outlineSuffixes())

    /// `World/Items/Item_<n>` のパス → `World/Items/Item_<n>_outline_<suffix>` のパス
    def outlinePathOf(itemPath: NodePath, suffix: String): NodePath =
        match List.reverse(itemPath) {
            case Nil          => itemPath
            case last :: rest => List.reverse(("${last}_outline_${suffix}") :: rest)
        }

    // ─── tick（点滅アニメーション） ───────────────────────────

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から、各 GroundItem に
    /// 対して per-node dispatch される。`elapsed` を進めて 4 兄弟の縁取り Sprite に alpha
    /// (`pulseAlpha`) を反映する。
    /// `writeElapsed` は self を更新し `applyAlphaToOutlines` は子ノードを更新するため
    /// scene 経由で両方処理してから、scene から self の最新ノードを取り直して返す。
    pub def process(dt: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) =
        let next = match Scene.getState(path, scene) {
            case Some(NodeTag.GroundItem(d)) =>
                let newElapsed = advance(Duration.add(d#elapsed, dt));
                let alpha = pulseAlpha(newElapsed);
                scene
                    |> writeElapsed(path, newElapsed)
                    |> applyAlphaToOutlines(path, alpha)
            case _ => scene
        };
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// `elapsed` をサイクル長で巻き戻す（mod の代わり）。dt が cycle 未満であることを前提に 1 回引き算するだけ。
    def advance(e: Duration.Duration): Duration.Duration =
        if (Duration.toSeconds(e) >= Duration.toSeconds(cycleDuration()))
            Duration.sub(e, cycleDuration())
        else e

    /// サイクル先頭 `pulseDuration` の間は base→peak→base の三角波、それ以外は base 固定。
    def pulseAlpha(elapsed: Duration.Duration): Float32 =
        let e = Duration.toSeconds(elapsed);
        let p = Duration.toSeconds(pulseDuration());
        if (e < p) {
            let t = e / p;                              // 0..1
            let tri = 1.0 - Float64.abs(2.0 * t - 1.0); // 0..1..0
            let b = Float32.toFloat64(baseAlpha());
            let pk = Float32.toFloat64(peakAlpha());
            Float64.truncateToFloat32(b + (pk - b) * tri)
        } else baseAlpha()

    /// アイテム本体ノードの `elapsed` のみ更新する（縁取りには触らない）。
    def writeElapsed(itemPath: NodePath, newElapsed: Duration.Duration,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(itemPath, n -> match n {
            case EngineNode.Sprite2DWithState(sp, NodeTag.GroundItem(d)) =>
                EngineNode.Sprite2DWithState(sp, NodeTag.GroundItem({elapsed = newElapsed | d}))
            case other => other
        }, scene)

    /// 4 つの縁取り Sprite2D に同じ alpha を書き込む。
    def applyAlphaToOutlines(itemPath: NodePath, alpha: Float32,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, suffix) -> {
            let path = outlinePathOf(itemPath, suffix);
            Sprite2D.mapAt(path, Sprite2D.setAlpha(alpha), acc)
        }, scene, outlineSuffixes())
}
