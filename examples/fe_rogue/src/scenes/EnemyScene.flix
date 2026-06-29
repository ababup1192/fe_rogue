/// EnemyScene — 敵キャラクター（Marker2D + 子 Sprite2D）の集まり
///
/// FE 風のターン制で味方を追跡してくる敵駒を表現する。プレイヤーと違って
/// 1 シーンに複数体が同時に存在するため、各敵をトップレベルの "Enemy_<id>"
/// ノードとして並べて管理する（PlayerScene が単一 Marker2D なのに対して、
/// EnemyScene は同じノード型を id 別に量産するイメージ）。
///
/// ノード構造（敵 1 体あたり）:
///   Enemy_<id> (Marker2D, NodeTag.Enemy(Data))
///     └─ Sprite (Sprite2D, frame=4 の `character_sheet` 上段一番右)
///
/// スポーン規則（anchor 除外）:
///   - 部屋（idx in [1, roomCount)）ごとに `Random` で 0..maxPerRoom 体スポーン。
///   - anchor 部屋（idx 0、プレイヤー初期位置）は除外。起動直後に敵に隣接しないよう保証する。
///   - 通路（idx >= roomCount）は対象外。プレイヤーが通り抜けるだけの空間にする。
///   - 各敵は部屋の床セルから 1 つを選ぶ（プレイヤー位置・既存敵セルを避ける）。
mod EnemyScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 敵駒状態の再 export。フィールドの詳細は `EnemyData.Data` の doc 参照。
    pub type alias Data = EnemyData.Data
    pub type alias Spawn = EnemyData.Spawn

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// プレイヤーと同じ高さで前面に立つ。MoveRange (1) より上。
    def spriteZIndex(): Int32 = 10

    // per-room cap は引数の floor#monstersPerRoom で制御される（resource 駆動）。

    /// 1 マス分のスライド時間。Player と同じ感覚で見えるよう揃える。
    def slideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 120)

    /// 死亡点滅アニメーションの全長。3 サイクル（半透明 → 不透明）× 2 フェーズ × 150ms。
    def deathBlinkLength(): Duration.Duration = 900 |> Duration.millis

    /// 死亡演出時の半透明 alpha 値（点滅の谷）。
    def dimAlpha(): Float32 = 0.3f32

    /// 通常時 / 点滅の山の alpha 値。
    def fullAlpha(): Float32 = 1.0f32

    /// `death_blink` アニメーション。1 → 0.3 → 1 → 0.3 → 1 → 0.3 → 1 を均等な 6 区間で
    /// 並べて 3 サイクルの点滅を表現する。target は子 Sprite ノードの alpha。
    /// アニメ完了時の `finished` イベント (owner=enemyPath, name="death_blink") を
    /// GameManager がディスパッチして down_enemy + Scene.removeAt を実行する。
    def deathBlinkAnimation(targetSprite: NodePath): AnimationPlayer.Animation =
        let alphaKeys: List[AnimationPlayer.AlphaKey] =
            ({time = 0.0,        alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 1.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 2.0 / 6.0,  alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 3.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 4.0 / 6.0,  alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 5.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 1.0,        alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetSprite,
            prop   = AnimationPlayer.Property.Alpha(alphaKeys)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.DeathBlink),
            length  = deathBlinkLength(),
            tracks  = track :: Nil,
            methods = Nil
        }

    /// "Enemy_3" のようなノード名（World の直接の子）。
    pub def enemyName(id: Int32): String = "Enemy_${id}"

    /// 敵 id の NodePath。Y-sort root の World 配下にぶら下げるため
    /// "World/Enemy_<id>" の 2 段構造
    pub def enemyPath(id: Int32): NodePath =
        List.append(MapScene.worldPath(), enemyName(id) :: Nil)

    /// 敵 id の子 Sprite ノードへのパス。alpha 補間 (Tween.tweenAlpha) のターゲットに使う。
    pub def spritePath(id: Int32): NodePath =
        List.append(enemyPath(id), "Sprite" :: Nil)

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene が登録済みの scene に敵を追加する。
    /// 各部屋について 0..`floor#monstersPerRoom` 体のスポーン位置を決め、
    /// それぞれに `floor#monsters` から percent 重みでランダム抽選した unit id を引いて
    /// UnitResource を割り当て、`initialInventory` の先頭武器を装備させる
    /// （敵は杖を使わない前提で、weapon kind の最初のエントリだけを採用）。
    /// `Math.Random` を使うのでこの effect が必要。
    pub def add(enemies: EnemyCatalog.EnemyCatalog,
                 weapons: WeaponCatalog.WeaponCatalog,
                 ringCatalog: Ring.RingCatalog,
                 floor: FloorCatalog.FloorResource,
                 scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, World.Command} =
        let layer       = MapScene.getMapLayer(scene);
        let placements  = MapScene.getPlacements(scene);
        let roomCount   = MapScene.getRoomCount(scene);
        // パーティ全員のセルを taken に入れて避ける（敵が味方の上にスポーンしないように）。
        // 意図的な PlayerScene 直接 read: build 中の scene は PartyQuery handler の
        // sceneRef にまだ反映されていないため、effect 経由では構築中の味方が見えない。
        let playerCells = PlayerScene.getAll(scene) |> List.map(d -> d#gridPos);
        // anchor (idx = 0) を除いた部屋だけを対象にする
        let rooms = List.filter(p ->
            p#idx >= 1 and p#idx < roomCount, placements);
        // 部屋を順に走査し、(nextId, takenCells, spawns) を畳み込む。
        // pickCellsInRoom と weighted 抽選が `Math.Random` を持つので畳み込み全体も `Math.Random`。
        let initial: (Int32, List[{x = Int32, y = Int32}], List[Spawn]) =
            (0, playerCells, Nil);
        let monsters = floor#monsters;
        let range = floor#monstersPerRoom;
        let (_, _, accSpawns) = List.foldLeft(state -> p ->
            spawnInRoom(layer, p, FloorCatalog.randomCountInRange(range),
                         monsters, enemies, weapons, state),
            initial, rooms);
        // accSpawns は逆順（cons で積んだ）なので reverse して id 昇順に揃える
        let spawns = List.reverse(accSpawns);
        List.foldLeft(acc -> sp -> addOneEnemy(sp, ringCatalog, acc), scene, spawns)

    /// `initialInventory` の中で最初の `weapon` kind の id を `lookupWeapon` で解決する。
    /// 敵は杖を持たない前提なので weapon kind だけを採用する。weapon が一つも無いユニットは
    /// 起動時 typo / schema 不整合として `bug!` で落とす（パーティ運用には不可避）。
    def lookupFirstWeapon(res: EnemyCatalog.EnemyResource,
                            weapons: WeaponCatalog.WeaponCatalog): UnitCatalog.WeaponResource =
        match List.find(e -> e#kind == UnitBase.ItemKind.Weapon, res#initialInventory) {
            case Some(e) => WeaponCatalog.lookup(e#id, weapons)
            case None    =>
                bug!("EnemyScene.lookupFirstWeapon: unit has no weapon in initialInventory")
        }

    /// 一部の敵職はスポーン時に一定確率（`specialWeaponChance`）で専用武器に持ち替える。
    ///   - バーバリアン_T3 → あくまの斧（demon_axe）
    ///   - パラディン_T2   → 如意棒（nyoibo）
    /// それ以外 / 抽選外なら `base`（通常の initialInventory 武器）のまま。
    def maybeSwapSpecialWeapon(res: EnemyCatalog.EnemyResource,
                                base: UnitCatalog.WeaponResource,
                                weapons: WeaponCatalog.WeaponCatalog):
            UnitCatalog.WeaponResource \ Math.Random =
        let roll = Float64.truncateToInt32(Math.Random.randomFloat64() * 100.0);
        if (res#description == "バーバリアン_T3" and roll < specialWeaponChance())
            WeaponCatalog.lookup("demon_axe", weapons)
        else if (res#description == "パラディン_T2" and roll < specialWeaponChance())
            WeaponCatalog.lookup("nyoibo", weapons)
        else base

    /// 専用武器に持ち替える確率（%）。「たまに装備」の体感に合わせた約 35%。
    def specialWeaponChance(): Int32 = 35

    /// 部屋 1 つから `count` 個のスポーンセルを選んで state に積む。
    /// state = (次に振る id, スポーン済みセル累積, spawn list 累積)。
    /// 候補不足のときは取れる分だけ積んで打ち切る。
    /// 各セルにつき floor の `monsters` (percent 配列) から重み付き抽選した unit id を
    /// `catalog#units` で UnitResource に解決し、`initialInventory` の先頭武器を装備させる。
    def spawnInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     monsters: List[FloorCatalog.SpawnEntry],
                     enemies: EnemyCatalog.EnemyCatalog,
                     weapons: WeaponCatalog.WeaponCatalog,
                     state: (Int32, List[{x = Int32, y = Int32}], List[Spawn])):
                    (Int32, List[{x = Int32, y = Int32}], List[Spawn]) \ Math.Random =
        if (count <= 0) state
        else
            let (nextId, taken, list) = state;
            let candidates = floorCellsInRoom(layer, p)
                              |> List.filter(c -> not isTaken(c, taken));
            match RandomUtil.pick(candidates) {
                case None       => state   // 候補ゼロで打ち切り
                case Some(cell) =>
                    match FloorCatalog.pickWeighted(monsters) {
                        case None => state  // weight 配列が空 / 合計 0 → スキップ
                        case Some(id) =>
                            let res = match EnemyCatalog.get(id, enemies) {
                                case Some(u) => u
                                case None    =>
                                    bug!("EnemyScene.spawnInRoom: enemy id '${id}' not in catalog")
                            };
                            let weapon = maybeSwapSpecialWeapon(res, lookupFirstWeapon(res, weapons), weapons);
                            let entry: Spawn = {
                                id = nextId, resourceId = id, gridPos = cell, moduleIdx = p#idx,
                                resource = res, weapon = weapon
                            };
                            spawnInRoom(layer, p, count - 1, monsters, enemies, weapons,
                                         (nextId + 1, cell :: taken, entry :: list))
                    }
            }

    /// 部屋の bbox（offset + floorBounds）に含まれる床セルを列挙する。
    /// n-format では gridSize が床範囲より広いため、floorBounds で絞らないと
    /// 隣接する通路の床まで候補に入って通路に敵がスポーンしてしまう。
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        let minX = p#offset#x + p#floorBoundsMin#x;
        let minY = p#offset#y + p#floorBoundsMin#y;
        let maxX = p#offset#x + p#floorBoundsMaxEx#x;
        let maxY = p#offset#y + p#floorBoundsMaxEx#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> TileMapLayer.isFloor(c, layer),
                List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32}), xs)),
            ys)

    def isTaken(c: {x = Int32, y = Int32}, taken: List[{x = Int32, y = Int32}]): Bool =
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    /// 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    /// ステータス・テクスチャ・フレームは `sp#resource`（UnitResource）から取る。
    def addOneEnemy(sp: Spawn, ringCatalog: Ring.RingCatalog, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // P0b: spawn/restore の funnel。新規敵の初期位置を World へ seed（Cmd.Move=位置 insert）。
        // dual-write 維持＝挙動不変（mirror が P2 まで生きる）。
        World.Command.emit(World.Cmd.Move(World.refOf(false, sp#id), sp#gridPos));
        // F6a: 初期 hp も World へ seed（spawn フレームの [F6 HP DIFF] を塞ぐ＝F6b preserve の前提）。
        World.Command.emit(World.Cmd.SetHp(World.refOf(false, sp#id), sp#resource#hp));
        // F7-spike: 初期 alerted=false も seed（spawn の [ALERTED DIFF] transient を塞ぐ）。
        World.Command.emit(World.Cmd.SetAlerted(World.refOf(false, sp#id), false));
        // F7-slice2: 初期 bottleUsed=false も seed。
        World.Command.emit(World.Cmd.SetBottleUsed(World.refOf(false, sp#id), false));
        // F7-slice4: 初期 followUpUsed=false も seed。
        World.Command.emit(World.Cmd.SetFollowUpUsed(World.refOf(false, sp#id), false));
        // D3: 初期 weapon も World へ seed（単数→0/1 List 射影・[WEAPONS DIFF] を塞ぐ）。
        World.Command.emit(World.Cmd.SetWeapons(World.refOf(false, sp#id), sp#weapon :: Nil));
        // S2.3: 初期 baseStats も World へ seed（敵 resource は spawn で確定し以後不変＝[BASESTATS DIFF] を塞ぐ・preserve の前提）。
        World.Command.emit(World.Cmd.SetBaseStats(World.refOf(false, sp#id), Combat.baseStatsFrom(sp#resource)));
        // S2.5: 初期 moveTiles も seed（resource 由来で以後不変＝[MOVETILES DIFF] を塞ぐ＝preserve の前提）。
        World.Command.emit(World.Cmd.SetMoveTiles(World.refOf(false, sp#id), sp#resource#moveTiles));
        let pos = MapSnapshot.cellCenter(sp#gridPos);
        let marker = Marker2D.make(pos);
        let res    = sp#resource;
        // enemies.json の指輪 id を実体に解決する（未指定なら None）。
        let ring   = res#ring |> Option.map(id -> Ring.lookup(id, ringCatalog));
        let data: Data = {
            id             = sp#id,
            resourceId     = sp#resourceId,
            gridPos        = sp#gridPos,
            alerted        = false,
            homeModuleIdx  = sp#moduleIdx,
            moveTiles      = res#moveTiles,
            hp             = res#hp,
            isDying        = false,
            attackTargetId = None,
            resource       = res,
            weapon         = Some(sp#weapon),
            acted          = false,
            prevPos        = None,
            statuses       = Nil,
            ring           = ring,
            followUpUsed   = false,
            bottleUsed     = false
        };
        // S2.4: 初期 weaponView/ringBonus も World へ seed（weapons/ring と 1:1・敵は spawn 後不変＝各 DIFF を塞ぐ・preserve の前提）。
        // data 構築後に emit（equippedWeaponView/equippedRingBonus は full Data を要する）。
        World.Command.emit(World.Cmd.SetWeaponView(World.refOf(false, sp#id), equippedWeaponView(data)));
        World.Command.emit(World.Cmd.SetRingBonus(World.refOf(false, sp#id), equippedRingBonus(data)));
        let sprite = Sprite2D.make(res#sprite#texture, res#sprite#offset,
                                    res#sprite#scale)
                        |> Sprite2D.setHframes(res#sprite#hframes)
                        |> Sprite2D.setVframes(res#sprite#vframes)
                        |> Sprite2D.setFrame(res#sprite#frame)
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addChildAt(MapScene.worldPath(), enemyName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Enemy(data)))
            |> Scene.addChildAt(enemyPath(sp#id), "Sprite",
                                 EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> UnitHPBarScene.attach(enemyPath(sp#id), res#hp, UnitHPBarScene.Team.Enemy)
            |> WeaponIconScene.attach(enemyPath(sp#id), Some(sp#weapon))

    // ────────────────────────────────────────────────────────
    // (C2) 試練(シレン)型・部屋湧き（Wanderer タイプの敵をフロア進行中にじわっとスポーン）
    // ────────────────────────────────────────────────────────

    /// 湧き周期。N ティック（= 敵ターン終端ごとの合算カウント）ごとに 1 体湧く。
    /// 確率式のムラを避け、試練のように「長居でじわ増え」る安定したペースにする（tunable）。
    def spawnIntervalTicks(): Int32 = 10
    /// フロア上限。盤上の Wanderer がこの数に達したら湧かせない
    /// （無限湧き防止 + 敵ターン冗長化防止）。倒せば再び湧ける。
    def maxWanderersOnFloor(): Int32 = 6

    /// 試練式の部屋湧き。`tick` が周期に達した節目で、盤上 Wanderer 数が上限未満なら
    /// 「プレイヤー視界外の部屋」へ Wanderer タイプの敵を 1 体湧かせる。
    /// 発生条件（どれか欠けたら何もしない）: `tick mod 周期 == 0` / 上限未満 /
    /// 湧ける部屋セル（空き + 視界外）がある / フロアの `monsters` に Wanderer タイプが居る。
    /// 視界外（フォグ内）に湧かせるので出現の瞬間はプレイヤーから見えない（シレン準拠の不意打ち）。
    pub def maybeSpawnWandererInRoom(enemies: EnemyCatalog.EnemyCatalog,
                                      weapons: WeaponCatalog.WeaponCatalog,
                                      ringCatalog: Ring.RingCatalog,
                                      floor: FloorCatalog.FloorResource,
                                      tick: Int32,
                                      scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, World.Command} =
        let current = getAll(scene);
        let wandererCount =
            current |> List.count(d -> d#resource#aiType == EnemyAI.AiType.Wanderer);
        if (Int32.remainder(tick, spawnIntervalTicks()) != 0) scene
        else if (wandererCount >= maxWanderersOnFloor()) scene
        else spawnOneWandererInRoom(enemies, weapons, ringCatalog, floor, current, scene)

    /// 部屋の空き・視界外セルを 1 つ選び、フロアの Wanderer タイプ敵を重み抽選して 1 体追加する。
    def spawnOneWandererInRoom(enemies: EnemyCatalog.EnemyCatalog,
                                weapons: WeaponCatalog.WeaponCatalog,
                                ringCatalog: Ring.RingCatalog,
                                floor: FloorCatalog.FloorResource,
                                current: List[Data],
                                scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, World.Command} =
        let layer      = MapScene.getMapLayer(scene);
        let placements = MapScene.getPlacements(scene);
        let roomCount  = MapScene.getRoomCount(scene);
        let holes      = FogScene.holesFor(PlayerScene.getAll(scene), placements, roomCount, false);
        let playerCells = PlayerScene.getAll(scene) |> List.map(d -> d#gridPos);
        let enemyCells  = current |> List.map(d -> d#gridPos);
        // アンカー除外の部屋 (idx in [1, roomCount)) の床セルを (idx, cell) 付きで集め、
        // 空き + 視界外（プレイヤーが居ない部屋）のみ残す。初期配置と同じ部屋集合。
        let candidates = placements
            |> List.filter(p -> p#idx >= 1 and p#idx < roomCount)
            |> List.flatMap(p -> floorCellsInRoom(layer, p) |> List.map(c -> (p#idx, c)))
            |> List.filter(pair -> {
                let (_, c) = pair;
                not isTaken(c, playerCells)
                    and not isTaken(c, enemyCells)
                    and not FogScene.insideAny(c, holes)
            });
        // 「湧ける部屋セル」「Wanderer タイプの抽選」「敵リソース解決」の 3 つの Option を
        // forM で畳む（ネスト match を回避）。どれかが None なら湧かさず scene を返す。
        // res は wandererMonstersOf が `EnemyCatalog.get` が Some の id だけに絞っているため実質必ず取れる。
        let spawned = forM (
            cellPick <- RandomUtil.pick(candidates);
            id       <- FloorCatalog.pickWeighted(wandererMonstersOf(floor, enemies));
            res      <- EnemyCatalog.get(id, enemies)
        ) yield {
            let (idx, cell) = cellPick;
            let entry: Spawn = {
                id = nextEnemyId(current), resourceId = id, gridPos = cell, moduleIdx = idx,
                resource = res, weapon = maybeSwapSpecialWeapon(res, lookupFirstWeapon(res, weapons), weapons)
            };
            addOneEnemy(entry, ringCatalog, scene)
        };
        Option.getWithDefault(scene, spawned)

    /// フロアの monsters 出現テーブルのうち、catalog 上 `aiType = Wanderer` の敵だけに絞る。
    def wandererMonstersOf(floor: FloorCatalog.FloorResource,
                            enemies: EnemyCatalog.EnemyCatalog): List[FloorCatalog.SpawnEntry] =
        floor#monsters
            |> List.filter(m -> EnemyCatalog.get(m#id, enemies)
                                    |> Option.map(r -> r#aiType == EnemyAI.AiType.Wanderer)
                                    |> Option.getWithDefault(false))

    /// 既存敵 id の最大 + 1（湧き個体に未使用 id を振る）。敵ゼロなら 0。
    def nextEnemyId(current: List[Data]): Int32 =
        1 + (current |> List.map(d -> d#id) |> List.maximum |> Option.getWithDefault(-1))

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// scene 上に登録された全ての敵の Data を返す（preorder 走査順）。
    pub def getAll(scene: Scene[NodeTag]): List[Data] =
        Scene.preorderPaths(scene)
            |> List.filterMap(path -> match Scene.getState(path, scene) {
                case Some(NodeTag.Enemy(data)) => Some(data)
                case _                          => None
            })

    /// id を持つ敵の Data を取り出す。未登録なら None。
    pub def get(id: Int32, scene: Scene[NodeTag]): Option[Data] =
        match Scene.getState(enemyPath(id), scene) {
            case Some(NodeTag.Enemy(data)) => Some(data)
            case _                          => None
        }

    /// 敵 id の表示名（敵種名 = `resource#description`）。ログ文言で使う。
    /// 見つからない場合は防御的に "敵" を返す（ログに id を出さない方針）。
    pub def displayName(id: Int32, scene: Scene[NodeTag]): String =
        get(id, scene) |> Option.map(d -> d#resource#description) |> Option.getWithDefault("敵")

    /// 敵 id の Data を `f` で更新する。Marker2D 自体には触れない。
    pub def mapEnemy(id: Int32, f: Data -> Data,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(enemyPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Enemy(data)) =>
                EngineNode.Marker2DWithState(marker, NodeTag.Enemy(f(data)))
            case other => other
        }, scene)

    /// F6a: hp 書込 funnel。scene の hp を更新しつつ World にも `Cmd.SetHp` で dual-write する。
    /// 純 hp 書込（回復/吸血など）の置換先。複合書込（hp＋他 field）は呼び出し側で単独 emit する。
    pub def setHp(id: Int32, newHp: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(id), newHp));
        mapEnemy(id, d -> {hp = newHp | d}, scene)

    // 行動済み時に sprite / HP ゲージを暗転し、プレイヤーの waitedColor と外観を揃えるグループ。

    /// 行動済みの sprite / HP ゲージ modulate（薄い灰色）。プレイヤーの waitedColor と揃える。
    def actedColor(): Color = UITheme.dimmed()
    /// 通常時の modulate（白 = 元色）。
    def activeColor(): Color = UITheme.white()

    /// 敵 id の子 Sprite に modulate を設定する（Sprite2D / AnimatedSprite2D 両対応）。
    def setSpriteModulate(id: Int32, color: Color, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id),
            n -> n
                |> EngineNode.mapSprite2D(s -> CanvasItem.setModulate(color, s))
                |> EngineNode.mapAnimSprite2D(s -> CanvasItem.setModulate(color, s)),
            scene)

    /// 敵 id を「行動済み」にして本体スプライトと HP ゲージを暗転する。
    /// 敵ターン中、その敵の行動が終わった時点で呼ぶ。
    pub def setActed(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> mapEnemy(id, d -> {acted = true | d})
            |> setSpriteModulate(id, actedColor())
            |> UnitHPBarScene.setModulate(enemyPath(id), actedColor())
            |> WeaponIconScene.setModulate(enemyPath(id), actedColor())

    /// 完全停止（かなしばり）を解除する。被攻撃 or 被投擲の瞬間に呼ぶ。
    /// 停止していなければ no-op（他の時限ステータスは残す）。
    pub def releaseBind(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // emit-flip(E3, dual-write): かなしばり解除を World へ発行（scene の inline clear も当面維持）。
        World.Command.emit(World.Cmd.ClearImmobilized(World.EntityRef.Enemy(id)));
        mapEnemy(id, d -> {statuses = StatusSystem.clearImmobilized(d#statuses) | d}, scene)

    /// 全敵の「行動済み」を解除し、本体スプライトと HP ゲージを通常の明るさへ戻す。
    /// 敵ターン開始時に呼ぶ（プレイヤーの clearAllWaited と対称）。
    pub def clearActedAll(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let ids = getAll(scene) |> List.map(d -> d#id);
        // emit-flip(E1, dual-write): 敵ターン開始 tick を World へ発行（scene の inline tick も当面維持）。
        World.Command.emit(World.Cmd.TickEnemies);
        let reset = List.foldLeft((sc, id) -> {
            World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(id), false));  // F7-slice4: reset を World へ
            sc
                // 敵ターン開始ごとに時限デバフ（目潰し/鈍足）を 1 ターン分減算し、
                // 追撃リングの二重発動フラグを戻す。
                |> mapEnemy(id, d -> {acted = false, statuses = StatusSystem.tick(d#statuses),
                                      followUpUsed = false | d})
                |> setSpriteModulate(id, activeColor())
                |> UnitHPBarScene.setModulate(enemyPath(id), activeColor())
                |> WeaponIconScene.setModulate(enemyPath(id), activeColor()) },
            scene, ids);
        // 敵ターン開始時に、いやしのリングを装備した敵の HP を回復する。
        applyRingRegen(reset)

    /// いやしのリングを装備した敵の HP を回復する（最大 HP でクランプ）。敵ターン開始で呼ぶ。
    /// 実際に回復した敵はログに出す。
    pub def applyRingRegen(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) -> regenOneEnemy(id, sc), scene, ids)

    /// 1 敵ぶんの Mend 回復。Mend 以外 / 未装備なら no-op（match は入れ子にしない）。
    def regenOneEnemy(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        match get(id, scene) {
            case None    => scene
            case Some(d) => mendOneEnemy(id, d, scene)
        }

    /// 回復量を計算して適用するヘルパー（regenOneEnemy から呼ぶ）。
    /// 満タン等で実際に HP が増えないときはログも出さない。
    def mendOneEnemy(id: Int32, d: Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let amt = Ring.mendAmount(d#ring);
        let newHp = Combat.heal(d#hp, d#resource#hp, amt)#newHp;
        if (amt <= 0 or newHp <= d#hp) scene
        else {
            GameLogger.enemyLog("${d#resource#description} は いやしのリングで HP+${newHp - d#hp}");
            scene
                |> setHp(id, newHp)
                |> UnitHPBarScene.update(enemyPath(id), newHp)
        }

    /// 全敵の sprite / HP ゲージを通常色(active)に戻す。`acted` フラグは変えない。
    /// 味方フェーズ中に「敵の行動済み灰色」を消してアクティブに見せるために使う
    /// （行動済みという扱い自体は残し、見た目だけ通常色に戻す）。
    pub def showAllActive(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) ->
            sc
                |> setSpriteModulate(id, activeColor())
                |> UnitHPBarScene.setModulate(enemyPath(id), activeColor())
                |> WeaponIconScene.setModulate(enemyPath(id), activeColor()),
            scene, ids)

    /// フォグ適用: 各敵を「現在地が lit(=isLit) なら表示、さもなくば非表示」にする。
    /// 親 Marker2D の visible を切り替えるので子 Sprite / HPBar も連動する。
    /// visible を落としても AI は継続するため、フォグで隠れた敵も行動する点に注意。
    pub def applyFog(isLit: {x = Int32, y = Int32} -> Bool,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, d) -> setEnemyVisible(d#id, isLit(d#gridPos), acc),
                      scene, getAll(scene))

    /// 敵 id の親 Marker2D の visible を設定する（Data は素通し）。
    def setEnemyVisible(id: Int32, vis: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Marker2D.mapAt(enemyPath(id), CanvasItem.setVisible(vis), scene)

    /// 敵 id の親 Marker2D が現在 visible か（フォグで隠れていないか）を返す。
    /// フォグは `applyFog` で毎フレーム visible を設定するため、これが「いま見えているか」の
    /// 真実源になる。プレイヤーターン中は敵が動かないので前フレームの値で判定して問題ない。
    /// 未登録なら false（居ない＝見えない扱い）。CursorScene のホバー情報抑制に使う。
    pub def isVisible(id: Int32, scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(enemyPath(id), scene) {
            case Some(EngineNode.Marker2DWithState(marker, _)) => CanvasItem.isVisible(marker)
            case _                                              => false
        }

    /// 敵 id を `target` に移動させる。論理位置（gridPos）は即時更新し、
    /// 見た目の補間は Tween に委ねる（PlayerScene.moveTo と同じ機構）。
    /// 呼び出しごとに 1 マス分（隣接セル）の Tween を登録する前提。複数マス分の
    /// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ呼ぶことで実現する。
    /// **歩行可否（壁・他駒）の判定は呼び出し側（EnemyAI）が済ませている前提**で、
    /// EnemyScene 自身は衝突判定を持たない。
    pub def moveTo(id: Int32, target: {x = Int32, y = Int32},
                    map: MapSnapshot,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ {Tween.Scheduler, World.Command} =
        // F4a: プレイヤー移動（PlayerScene）と同じ `SimEvent.Moved` seam に統一。
        //   moveTo = SYSTEM(stepEnemyMove: Cmd.Move emit + Moved 返却) → VIEW(replayMovedEvent 再生)。
        //   歩行可否は呼び出し側（EnemyAI.decideAction）が済ませている前提＝System は判定せず書くだけ。
        // INVARIANT: replayMovedEvent は move-seam 専用＝Moved 以外は bug! で落ちる（no-op ではない）。
        // ここは stepEnemyMove が常に Moved を返すので安全。Phase C で combat SimEvent を配線したら
        // この seam に渡す event は必ず Moved に pre-filter すること。
        replayMovedEvent(stepEnemyMove(id, target), map, scene)

    /// SYSTEM(sim): 敵 1 体を target へ動かす位置 write。`Cmd.Move` を emit し `Moved` を返す。
    /// 合法性は EnemyAI が決定済み（プレイヤーの `stepPlayerMove` と違い board 再判定はしない）。
    /// gridPos は frame-end の `syncTreeFromWorld` で World 由来に derive＝ここでは scene を触らない。
    pub def stepEnemyMove(id: Int32, target: {x = Int32, y = Int32}):
            World.SimEvent \ World.Command =
        World.Command.emit(World.Cmd.Move(World.EntityRef.Enemy(id), target));
        World.SimEvent.Moved(World.EntityRef.Enemy(id), target)

    /// VIEW(replay): `SimEvent.Moved` の敵分を再生する。プレイヤー分は対象外
    /// （`PlayerScene.replayMovedEvent` が担当）＝faction ごとに自分の event を再生。
    /// faction 分岐は 1 段の match に留め、敵の見た目再生は `replayEnemyMoveView` に委譲（ネスト回避）。
    pub def replayMovedEvent(event: World.SimEvent, map: MapSnapshot,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ {Tween.Scheduler, World.Command} =
        match event {
            case World.SimEvent.Moved(World.EntityRef.Enemy(id), target)  => replayEnemyMoveView(id, target, map, scene)
            case World.SimEvent.Moved(World.EntityRef.Player(_), _)        => scene
            // simevent-algebra: 拡張された非 Moved variant は move seam に来ない（production emitter 無し）。
            // 黙って no-op せず、move seam 専用 invariant 違反として loud に落とす。
            case _ => bug!("EnemyScene.replayMovedEvent: non-Moved event on move seam")
        }

    /// 敵 1 体の move 見た目再生（Tween 滑走 + 左右反転 + prevPos 記録）。
    def replayEnemyMoveView(id: Int32, target: {x = Int32, y = Int32},
                             map: MapSnapshot, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, World.Command} =
        let startWorld  = Scene.globalPositionAt(enemyPath(id), scene);
        let targetWorld = MapSnapshot.gridToWorld(target, map);
        Tween.tweenPosition(enemyPath(id), startWorld, targetWorld, slideDuration());
        // flipForFacing 付き (= 左向き絵) の敵だけ左右反転する。match でなく Option パイプで畳む。
        let flipped = get(id, scene)
            |> Option.filter(d -> d#resource#sprite#flipForFacing)
            |> Option.map(d -> applyFacingFlip(id, d#gridPos#x, target#x, scene))
            |> Option.getWithDefault(scene);
        // 直前位置を記録（徘徊の「来た道へ戻らない」判定に使う）。`d#gridPos` は frame-head の
        // 移動前位置なので正しい（gridPos 自体は frame-end の syncTreeFromWorld で World 由来に derive）。
        // F7-slice3: prevPos も World へ dual-write（移動前 gridPos）。
        match get(id, scene) |> Option.map(d -> d#gridPos) {
            case Some(p) => World.Command.emit(World.Cmd.SetPrevPos(World.EntityRef.Enemy(id), p))
            case None    => ()
        };
        mapEnemy(id, d -> {prevPos = Some(d#gridPos) | d}, flipped)

    /// 子 Sprite2D に flipH を設定する内部ヘルパー (敵スプライトは常に Sprite2D)。
    def setSpriteFlipH(id: Int32, h: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id),
            n -> EngineNode.mapSprite2D(s -> Sprite2D.setFlipH(h, s), n), scene)

    /// 横移動の符号で「左向き絵」を反転する。右移動 (dx>0) で flipH=true (右向き)、
    /// 左移動で flipH=false。縦移動 (dx==0) は現状維持。
    def applyFacingFlip(id: Int32, prevX: Int32, targetX: Int32,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        let dx = targetX - prevX;
        if (dx > 0) setSpriteFlipH(id, true, scene)
        else if (dx < 0) setSpriteFlipH(id, false, scene)
        else scene

    /// 敵 id を `target` に **瞬間移動** で戻す（杖の「いれかえ」用）。
    /// 進行中の Tween があればキャンセルし、ノードの world 位置と Data#gridPos を
    /// 同時に target に揃える。`PlayerScene.snapTo` と同じ流儀。
    pub def snapTo(id: Int32, target: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]): Scene[NodeTag] \ {Tween.Scheduler, World.Command} =
        let world = MapSnapshot.cellCenter(target);
        Tween.Scheduler.cancel(enemyPath(id));
        World.Command.emit(World.Cmd.Move(World.EntityRef.Enemy(id), target));
        // S5b: gridPos は frame-end の syncTreeFromWorld で derive。瞬間移動の Marker2D world 座標だけ即合わせる。
        scene
            |> Scene.setGlobalPositionAt(enemyPath(id), world)

    /// 指定セルに居る（生きている）敵の id を返す。死亡演出中の敵は対象外。
    /// PlayerAttack フェーズで「カーソルが赤マス上の敵に乗っているか」の判定に使う。
    pub def findIdAt(coord: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Option[Int32] =
        getAll(scene)
            |> List.findMap(d ->
                if (not d#isDying
                    and d#gridPos#x == coord#x
                    and d#gridPos#y == coord#y) Some(d#id)
                else None)

    // ────────────────────────────────────────────────────────
    // (E) 死亡演出 — death_blink アニメ → finished で Scene 削除
    // ────────────────────────────────────────────────────────

    /// 敵 id の HP を 0 にして死亡演出を開始する。
    /// `isDying = true` を立てて `death_blink` アニメーションを再生する。
    /// アニメ完了で GameManager が `completeDeath` を呼んでノード削除と bonus 再生を行う。
    pub def startDeathAnimation(id: Int32,
                                 scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, World.Command} =
        AnimationPlayer.play(enemyPath(id), deathBlinkAnimation(spritePath(id)));
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(id), 0));  // F6a: 死亡で hp=0 を World へ
        World.Command.emit(World.Cmd.SetDying(World.EntityRef.Enemy(id)));  // 軸1 仕上げ: isDying を World へ
        mapEnemy(id, d -> {hp = 0, isDying = true | d}, scene)

    /// `death_blink` 完了時に GameManager が呼ぶ後始末。
    /// 敵撃破 SE (down_enemy) を再生し、ノードを scene から削除する
    /// （damage の後に down_enemy が鳴る順序保証）。
    pub def completeDeath(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Audio =
        AudioStreamPlayer.play("down_enemy");
        Scene.removeAt(enemyPath(id), scene)

    /// World 直下の `Enemy_<id>` 形式の NodePath から id を取り出す。
    /// それ以外なら None。AnimationPlayer の finished イベント振り分けに使う。
    pub def idFromPath(path: NodePath): Option[Int32] =
        match path {
            case world :: name :: Nil if world == MapScene.worldName() =>
                if (String.startsWith({prefix = "Enemy_"}, name))
                    String.dropLeft(6, name) |> Int32.fromString
                else None
            case _ => None
        }

    // ────────────────────────────────────────────────────────
    // (F) 初期 spawn のスナップショットと再配置（ゲームオーバー時のリセット）
    // ────────────────────────────────────────────────────────

    /// 現在 scene に居る全敵の `Spawn` 情報（id / gridPos / homeModuleIdx / resource / weapon）を
    /// 抽出する。`Game.start` で初回 buildPlayingScene 直後に呼んで保存し、ゲームオーバー時に
    /// `respawnFromInitial` で同じ位置・同じ敵種別・同じ武器で再配置する。
    /// スナップショットは攻撃前に取られる前提で `weapon` は常に Some。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                let weapon = match d#weapon {
                    case Some(w) => w
                    case None    => bug!("EnemyScene.snapshotSpawns: weapon is None for 敵${d#id} (snapshot taken after weapon broke?)")
                };
                ({id = d#id, resourceId = d#resourceId, gridPos = d#gridPos, moduleIdx = d#homeModuleIdx, resource = d#resource, weapon = weapon}: Spawn))

    /// 既存の敵を全て scene から取り除き、`spawns` から再構築する。
    /// 各敵は `addOneEnemy` を使って HP・alerted・dying を初期値で生成する。
    pub def respawnFromInitial(spawns: List[Spawn], ringCatalog: Ring.RingCatalog,
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let cleared = List.foldLeft((sc, d) -> Scene.removeAt(enemyPath(d#id), sc),
                                     scene, getAll(scene));
        List.foldLeft((sc, sp) -> addOneEnemy(sp, ringCatalog, sc), cleared, spawns)

    /// 現在の全敵を scene から取り除く（女神の加護でフロアの敵を一掃する）。子スプライト / HP バーも
    /// マーカー subtree ごと消える。
    pub def removeAll(scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((sc, d) -> Scene.removeAt(enemyPath(d#id), sc), scene, getAll(scene))

    /// スナップショットの敵リストから決定論的に再配置する（乱数なし）。
    /// `resourceId` で EnemyResource を、`weapon` の id で武器を catalog から引き直して `Spawn` を作り、
    /// `respawnFromInitial` で full HP・既定状態に配置したあと、snap の動的値
    /// （HP / 時限ステータス / 検知フラグ / 指輪）を overlay で上書きする。
    /// 進入時スナップショット（フロア最初から）では full HP・既定状態なので overlay しても不変、
    /// 中断セーブからの再開では中断時点の現在値がそのまま復元される（snapshot が単一の真実源）。
    pub def addFromSnaps(snaps: List[FloorSnapshot.EnemySnap],
                          enemyCatalog: EnemyCatalog.EnemyCatalog,
                          weaponCatalog: WeaponCatalog.WeaponCatalog,
                          ringCatalog: Ring.RingCatalog,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let spawns = snaps |> List.map(snap -> snapToSpawn(snap, enemyCatalog, weaponCatalog));
        let placed = respawnFromInitial(spawns, ringCatalog, scene);
        List.foldLeft((acc, snap) -> restoreEnemyState(snap, ringCatalog, acc), placed, snaps)

    /// 敵 1 体の現在状態（HP / 時限ステータス / 検知フラグ / 指輪）を snap から上書きする。
    /// HP バーの見た目も `UnitHPBarScene.update` で現在値に合わせる（最大 HP は spawn 時の resource#hp 据え置き）。
    def restoreEnemyState(snap: FloorSnapshot.EnemySnap, ringCatalog: Ring.RingCatalog,
                           scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let ring = snap#ring |> Option.map(id -> Ring.lookup(id, ringCatalog));
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(snap#id), snap#hp));  // F6a: 復元 hp を World へ
        World.Command.emit(World.Cmd.SetAlerted(World.EntityRef.Enemy(snap#id), snap#alerted));  // F7-spike: 復元 alerted を World へ
        mapEnemy(snap#id, d -> {hp = snap#hp, statuses = snap#statuses,
                                 alerted = snap#alerted, ring = ring | d}, scene)
            |> UnitHPBarScene.update(enemyPath(snap#id), snap#hp)

    /// `EnemySnap` を配置用 `Spawn` に解決する。武器は保存済み id ＋ 耐久で復元し、
    /// 武器 id が無い（壊れていた）場合は resource の初期武器にフォールバックする。
    def snapToSpawn(snap: FloorSnapshot.EnemySnap,
                     enemyCatalog: EnemyCatalog.EnemyCatalog,
                     weaponCatalog: WeaponCatalog.WeaponCatalog): Spawn =
        let resource = match EnemyCatalog.get(snap#resourceId, enemyCatalog) {
            case Some(r) => r
            case None    => bug!("EnemyScene.addFromSnaps: enemy '${snap#resourceId}' not in catalog")
        };
        let weapon = match snap#weapon {
            case Some(ref) => {durability = ref#durability | WeaponCatalog.lookup(ref#id, weaponCatalog)}
            case None      => lookupFirstWeapon(resource, weaponCatalog)
        };
        ({id = snap#id, resourceId = snap#resourceId, gridPos = snap#gridPos,
           moduleIdx = snap#moduleIdx, resource = resource, weapon = weapon}: Spawn)

    /// 現在の全敵を `EnemySnap` 列に射影する（スナップショット保存用）。`resourceId` は Data が保持。
    /// 武器は name 逆引きで id 化し耐久を併せて保持。指輪は id 化（多くは None）。
    pub def captureSnaps(scene: Scene[NodeTag],
                          weaponCatalog: WeaponCatalog.WeaponCatalog,
                          ringCatalog: Ring.RingCatalog): List[FloorSnapshot.EnemySnap] =
        getAll(scene) |> List.map(d ->
            ({id = d#id, resourceId = d#resourceId, gridPos = d#gridPos, hp = d#hp,
               moduleIdx = d#homeModuleIdx,
               weapon = d#weapon |> Option.map(w ->
                   {id = CatalogId.requireId("weapon", w#name, WeaponCatalog.idOf(w, weaponCatalog)),
                    durability = w#durability}),
               ring = d#ring |> Option.map(r -> CatalogId.requireId("ring", r#name, Ring.idOf(r, ringCatalog))),
               statuses = d#statuses, alerted = d#alerted}: FloorSnapshot.EnemySnap))

    // ────────────────────────────────────────────────────────
    // (G) 攻撃モーション関連のクエリとシグナル受信
    //     攻撃の解決本体（startAttack / 命中適用 / 反撃判定）は CombatScene に集約。
    // ────────────────────────────────────────────────────────

    /// 攻撃モーション中の敵が 1 体以上いれば true。
    /// モーション中はキューを進めてはならないため、呼び出し元は必ずこれで待機する。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    /// フォグで見えている生存敵が 1 体以上いれば true（死亡演出中 `isDying` は除外）。
    /// `isVisible` は applyFog が毎フレーム設定する marker 可視を読むので、呼び出し前に
    /// フォグが当該フレームで適用済みであることを前提とする（集合自動継続の「画面内に敵がいるか」判定に使う）。
    pub def anyVisible(scene: Scene[NodeTag]): Bool =
        List.exists(d -> not d#isDying and isVisible(d#id, scene), getAll(scene))

    /// `death_blink` finished イベントのエントリポイント。
    /// SE 再生とノード削除を completeDeath に委譲する。
    pub def onDeathBlinkDone(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Audio =
        completeDeath(enemyId, scene)

    /// この敵の戦闘ビュー（faction 非依存）。`Combat.estimate` / `Encounter` の join で使う。
    /// 敵には得意/苦手の概念が無いので、持っている武器は常に得意（proficient = true、100%）。
    pub def combatView(data: Data): Combat.CombatView =
        // 投擲デバフ（目潰し=命中ダウン / 鈍足=速さダウン）を被弾していれば戦闘ビューに反映する。
        Combat.assembleView({
            base   = Combat.baseStatsFrom(data#resource),
            mods   = StatusSystem.combatMods(data#statuses),
            ring   = equippedRingBonus(data),
            hp     = data#hp,
            weapon = equippedWeaponView(data)})

    /// S-A0: この敵の装備武器の戦闘投影。`combatView` と World read-model 構築が共有する。
    /// 敵は得意/苦手の概念がないので proficient は常に true。武器なしは None。
    pub def equippedWeaponView(data: Data): Option[Combat.WeaponView] =
        Combat.weaponView(data#weapon, true)

    /// S-A0c: この敵の装備指輪ボーナス。`combatView` と World read-model 構築が共有する。
    pub def equippedRingBonus(data: Data): Ring.Bonuses =
        Ring.bonuses(data#ring)

    /// この敵の盤上ビュー（faction = Enemy）。`Encounter.fromScene` の join で使う。
    /// `weaponRange` は装備武器の射程。敵に `hidden` は無いので常に false。
    pub def unitView(data: Data): UnitView =
        {id = data#id, faction = Faction.Enemy, pos = data#gridPos,
         hp = data#hp, moveTiles = data#moveTiles,
         weaponRange = data#weapon |> Option.map(w -> w#range),
         combat = combatView(data), isDying = data#isDying, hidden = false,
         aiType = data#resource#aiType}

    /// 指定 id の敵が現在装備している武器を返す。未装備（壊れた後）なら None。
    /// EnemyAI 等が「攻撃できるか」を判定するために使う。
    pub def getWeapon(id: Int32, scene: Scene[NodeTag]): Option[UnitCatalog.WeaponResource] =
        match get(id, scene) {
            case Some(d) => d#weapon
            case None    => None
        }
}
