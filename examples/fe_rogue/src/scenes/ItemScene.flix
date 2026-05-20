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
    /// `elapsed` は点滅サイクル内の経過時間（`tickAll` で進める）。
    pub type alias Data = {
        gridPos   = {x = Int32, y = Int32},
        weaponKey = String,
        weapon    = UnitCatalog.WeaponResource,
        elapsed   = Duration.Duration
    }

    // ─── 定数 ─────────────────────────────────────────────────

    def parentName(): String = "Items"
    pub def parentPath(): NodePath = MapScene.worldName() :: parentName() :: Nil

    /// `Item_<n>` 形式のノード名
    def itemName(idx: Int32): String = "Item_${idx}"

    /// `Item_<n>_outline_<dir>` 形式の縁取り兄弟ノード名
    def outlineName(idx: Int32, suffix: String): String = "Item_${idx}_outline_${suffix}"

    /// 1 タイル幅（PlayerScene 等と共通）
    def tileSize(): Float64 = 16.0

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
    /// 視認性のため 4 方向 1px シフトの縁取り Sprite を先に重ね、本体を上に置く。
    def addOneItem(idx: Int32, cell: {x = Int32, y = Int32},
                    weaponKey: String, weapon: UnitCatalog.WeaponResource,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        // セル中心 + sprite#offset で sheet padding を補正した位置に置く
        let pos: Vec2.Vec2 = {
            x = Int32.toFloat64(cell#x) * s + s / 2.0 + weapon#sprite#offset#x,
            y = Int32.toFloat64(cell#y) * s + s / 2.0 + weapon#sprite#offset#y
        };
        // フレーム指定済みのスプライト構築ヘルパ。エンジンは Sprite2D#offset を描画時に無視するため、
        // 縁取りのずらしは position 自体に乗せる（Node2D の position フィールドが globalPos に伝播する）。
        let makeFramed = (p: Vec2.Vec2) ->
            Sprite2D.make(weapon#sprite#texture, p, Vec2.one())
                |> Sprite2D.setHframes(weapon#sprite#hframes)
                |> Sprite2D.setVframes(weapon#sprite#vframes)
                |> Sprite2D.setFrame(weapon#sprite#frame);
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
            gridPos = cell, weaponKey = weaponKey, weapon = weapon,
            elapsed = initElapsed
        };
        Scene.addChildAt(parentPath(), itemName(idx),
            EngineNode.Sprite2DWithState(sprite, NodeTag.GroundItem(data)), withOutlines)

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
    /// 本体ノードと一緒に 4 つの縁取り兄弟ノードも消す。
    pub def takeAt(coord: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]):
            (Scene[NodeTag], Option[UnitCatalog.WeaponResource]) =
        match findAt(coord, scene) {
            case None              => (scene, None)
            case Some((path, w))   =>
                let cleaned = scene
                    |> removeOutlinesFor(path)
                    |> Scene.removeAt(path);
                (cleaned, Some(w))
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

    /// 全 GroundItem の `elapsed` を進めて、4 兄弟の縁取り Sprite のアルファを更新する。
    /// `GameManager.commonEpilogue` から毎フレーム呼ばれる。
    pub def tickAll(dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag] =
        let paths = Scene.findPaths(tag -> match tag {
            case NodeTag.GroundItem(_) => true
            case _                     => false
        }, scene);
        List.foldLeft(acc -> path -> tickOne(dt, path, acc), scene, paths)

    /// 1 つの GroundItem について、elapsed を進めてから縁取りに alpha を反映する。
    def tickOne(dt: Duration.Duration, itemPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(itemPath, scene) {
            case Some(NodeTag.GroundItem(d)) =>
                let newElapsed = advance(Duration.add(d#elapsed, dt));
                let alpha = pulseAlpha(newElapsed);
                scene
                    |> writeElapsed(itemPath, newElapsed)
                    |> applyAlphaToOutlines(itemPath, alpha)
            case _ => scene
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
            Scene.mapEngineNode(path, n -> match n {
                case EngineNode.Sprite2DWithState(sp, tag) =>
                    EngineNode.Sprite2DWithState(Sprite2D.setAlpha(alpha, sp), tag)
                case other => other
            }, acc)
        }, scene, outlineSuffixes())
}
