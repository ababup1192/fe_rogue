/// EnemyScene — 敵キャラクターの spawn・移動・死亡演出・ターン状態の操作の集まり
///
/// FE 風のターン制で味方を追跡してくる敵駒を表現する。敵の状態は World の各 store が唯一の
/// 権威で、読みは `World.dataFromWorldEnemy`（store 群からの `Data` 再構築）、書きは
/// `World.Cmd` の emit に統一する。見た目（本体 sprite / HP バー / 武器アイコン）は World store
/// から直描きし、描画位置・フォグ可視も World（renderPos / posOf×明るい穴）から導出する。
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
    pub def spriteZIndex(): Int32 = 10  // renderUnits が使うため pub

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

    /// 死亡点滅の alpha を経過秒から導出する純関数（山 1.0 → 谷 0.3 を 3 サイクル）。
    /// `World.dyingElapsedOf` を入力に renderUnits が呼ぶ。全長 total を 3 等分した三角波は
    /// engine_world の `Curve.tri`（0→1→0）を山 f・谷 d に写して評価する。全長超過は f で
    /// 平ら（完了フレーム〜除去までの端数。tri は先へ進むと再び谷へ落ちるため明示的に止める）。
    pub def deathBlinkAlpha(elapsed: Float64): Float32 =
        let total = Duration.toSeconds(deathBlinkLength());
        let f = Float32.toFloat64(fullAlpha());
        let d = Float32.toFloat64(dimAlpha());
        let alpha =
            if (elapsed >= total) f
            else f - (f - d) * Curve.tri(total / 3.0, elapsed);
        alpha |> Float64.truncateToFloat32

    /// 死亡点滅の全長（秒）。`World.stepAnimClocks` が dyingElapsed との比較に使い、
    /// 到達フレームで DeathBlinkDone signal（→ `onDeathBlinkDone` = down_enemy + Despawn）を発火する。
    pub def deathBlinkTotalSeconds(): Float64 =
        Duration.toSeconds(deathBlinkLength())

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// マップ（World の terrain / placements）が seed 済みで PlayerScene 登録済みの World に敵を追加する。
    /// 各部屋について 0..`floor#monstersPerRoom` 体のスポーン位置を決め、
    /// それぞれに `floor#monsters` から percent 重みでランダム抽選した unit id を引いて
    /// UnitResource を割り当て、`initialInventory` の先頭武器を装備させる
    /// （敵は杖を使わない前提で、weapon kind の最初のエントリだけを採用）。
    /// `Math.Random` を使うのでこの effect が必要。
    pub def add(enemies: EnemyCatalog.EnemyCatalog,
                 weapons: WeaponCatalog.WeaponCatalog,
                 ringCatalog: Ring.RingCatalog,
                 floor: FloorCatalog.FloorResource): Unit \ {Math.Random, World.Command, World.WorldQuery} =
        let world0      = World.WorldQuery.get();
        let terrain     = World.terrainOrBug(world0);
        let placements  = World.placementsOf(world0);
        let roomCount   = World.roomCountOf(world0);
        // パーティ全員のセルを taken に入れて避ける（敵が味方の上にスポーンしないように）。
        let playerCells = PlayerScene.getAll() |> List.map(d -> d#gridPos);
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
            spawnInRoom(terrain, p, FloorCatalog.randomCountInRange(range),
                         monsters, enemies, weapons, state),
            initial, rooms);
        // accSpawns は逆順（cons で積んだ）なので reverse して id 昇順に揃える
        let spawns = List.reverse(accSpawns);
        List.forEach(sp -> addOneEnemy(sp, ringCatalog), spawns)

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
    def spawnInRoom(terrain: MapSnapshot,
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
            let candidates = floorCellsInRoom(terrain, p)
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
                            spawnInRoom(terrain, p, count - 1, monsters, enemies, weapons,
                                         (nextId + 1, cell :: taken, entry :: list))
                    }
            }

    /// 部屋の bbox（offset + floorBounds）に含まれる床セルを列挙する。
    /// n-format では gridSize が床範囲より広いため、floorBounds で絞らないと
    /// 隣接する通路の床まで候補に入って通路に敵がスポーンしてしまう。
    def floorCellsInRoom(terrain: MapSnapshot,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        let minX = p#offset#x + p#floorBoundsMin#x;
        let minY = p#offset#y + p#floorBoundsMin#y;
        let maxX = p#offset#x + p#floorBoundsMaxEx#x;
        let maxY = p#offset#y + p#floorBoundsMaxEx#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> MapSnapshot.isFloor(c, terrain),
                List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32}), xs)),
            ys)

    def isTaken(c: {x = Int32, y = Int32}, taken: List[{x = Int32, y = Int32}]): Bool =
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    /// 敵 1 体ぶんの World store 群を seed する（spawn/restore の funnel）。
    /// ステータス・テクスチャは `sp#resource` から取る。
    def addOneEnemy(sp: Spawn, ringCatalog: Ring.RingCatalog): Unit \ World.Command =
        // 新規敵の初期位置を World へ seed（Cmd.Move=位置 insert）。
        World.Command.emit(World.Cmd.Move(World.refOf(false, sp#id), sp#gridPos));
        // 初期 hp も World へ seed する。
        World.Command.emit(World.Cmd.SetHp(World.refOf(false, sp#id), sp#resource#hp));
        // 初期 alerted=false も seed する。
        World.Command.emit(World.Cmd.SetAlerted(World.refOf(false, sp#id), false));
        // 初期 acted=false も seed する。
        World.Command.emit(World.Cmd.SetActed(World.refOf(false, sp#id), false));
        // 初期 bottleUsed=false も seed する。
        World.Command.emit(World.Cmd.SetBottleUsed(World.refOf(false, sp#id), false));
        // 初期 followUpUsed=false も seed する。
        World.Command.emit(World.Cmd.SetFollowUpUsed(World.refOf(false, sp#id), false));
        // 初期 weapon も World へ seed（単数→0/1 List 射影）。
        World.Command.emit(World.Cmd.SetWeapons(World.refOf(false, sp#id), sp#weapon :: Nil));
        // 初期 baseStats も World へ seed（敵 resource は spawn で確定し以後不変）。
        World.Command.emit(World.Cmd.SetBaseStats(World.refOf(false, sp#id), Combat.baseStatsFrom(sp#resource)));
        // 初期 moveTiles も seed（resource 由来で以後不変）。
        World.Command.emit(World.Cmd.SetMoveTiles(World.refOf(false, sp#id), sp#resource#moveTiles));
        // テンプレート（catalog id / 出身部屋 / resource 本体）も seed する（dataFromWorldEnemy の gate 対象）。
        World.Command.emit(World.Cmd.SetEnemyProfile(sp#id, {resourceId = sp#resourceId, homeModuleIdx = sp#moduleIdx}));
        World.Command.emit(World.Cmd.SetEnemyResource(sp#id, sp#resource));
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
        // id 集合/team・effectRule・装備指輪も spawn で seed する。
        World.Command.emit(World.Cmd.Spawn(World.EntityRef.Enemy(sp#id)));
        World.Command.emit(World.Cmd.SetEffectRule(sp#id, res#effectRule));
        World.Command.emit(World.Cmd.SetEnemyRing(sp#id, ring));
        // 初期 weaponView/ringBonus も World へ seed（weapons/ring と 1:1・敵は spawn 後不変）。
        // data 構築後に emit（equippedWeaponView/equippedRingBonus は full Data を要する）。
        World.Command.emit(World.Cmd.SetWeaponView(World.refOf(false, sp#id), equippedWeaponView(data)));
        World.Command.emit(World.Cmd.SetRingBonus(World.refOf(false, sp#id), equippedRingBonus(data)))

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
                                      tick: Int32): Unit \ {Math.Random, World.Command, World.WorldQuery} =
        let current = getAll();
        let wandererCount =
            current |> List.count(d -> d#resource#aiType == EnemyAI.AiType.Wanderer);
        if (Int32.remainder(tick, spawnIntervalTicks()) != 0) ()
        else if (wandererCount >= maxWanderersOnFloor()) ()
        else spawnOneWandererInRoom(enemies, weapons, ringCatalog, floor, current)

    /// 部屋の空き・視界外セルを 1 つ選び、フロアの Wanderer タイプ敵を重み抽選して 1 体追加する。
    def spawnOneWandererInRoom(enemies: EnemyCatalog.EnemyCatalog,
                                weapons: WeaponCatalog.WeaponCatalog,
                                ringCatalog: Ring.RingCatalog,
                                floor: FloorCatalog.FloorResource,
                                current: List[Data]): Unit \ {Math.Random, World.Command, World.WorldQuery} =
        let world0     = World.WorldQuery.get();
        let terrain    = World.terrainOrBug(world0);
        let placements = World.placementsOf(world0);
        let roomCount  = World.roomCountOf(world0);
        // 空きセル・可視判定は World 位置。
        let holes      = FogScene.holesFor(PlayerScene.getAll(), placements, roomCount, false);
        let playerCells = PlayerScene.getAll() |> List.map(d -> d#gridPos);
        let enemyCells  = current |> List.map(d -> d#gridPos);
        // アンカー除外の部屋 (idx in [1, roomCount)) の床セルを (idx, cell) 付きで集め、
        // 空き + 視界外（プレイヤーが居ない部屋）のみ残す。初期配置と同じ部屋集合。
        let candidates = placements
            |> List.filter(p -> p#idx >= 1 and p#idx < roomCount)
            |> List.flatMap(p -> floorCellsInRoom(terrain, p) |> List.map(c -> (p#idx, c)))
            |> List.filter(pair -> {
                let (_, c) = pair;
                not isTaken(c, playerCells)
                    and not isTaken(c, enemyCells)
                    and not FogScene.insideAny(c, holes)
            });
        // 「湧ける部屋セル」「Wanderer タイプの抽選」「敵リソース解決」の 3 つの Option を
        // forM で畳む（ネスト match を回避）。どれかが None なら湧かさない。
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
            addOneEnemy(entry, ringCatalog)
        };
        Option.getWithDefault((), spawned)

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

    /// 在籍する全ての敵の Data を id 昇順で返す（World store 群から再構築）。
    pub def getAll(): List[Data] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        World.enemyIdsOf(world) |> List.filterMap(id -> World.dataFromWorldEnemy(id, world))

    /// id を持つ敵の Data を取り出す。未登録なら None。
    pub def get(id: Int32): Option[Data] \ World.WorldQuery =
        World.dataFromWorldEnemy(id, World.WorldQuery.get())

    /// statusEffects 書込 funnel（`PlayerScene.updateStatuses` の Enemy 版）。World の現在 statuses に
    /// 純粋変換 `f` を適用し、`Cmd.Seed`（全置換 replace 意味論）で書く。
    /// statuses を書く全サイト（add/clearImmobilized/bind）が使う。pub（StaffCast/CombatDriver 起点から）。
    pub def updateStatuses(id: Int32,
                            f: StatusSystem.StatusEffects -> StatusSystem.StatusEffects):
            Unit \ {World.Command, World.WorldQuery} =
        let ref = World.EntityRef.Enemy(id);
        let cur = World.statusEffectsOf(ref, World.WorldQuery.get());
        World.Command.emit(World.Cmd.Seed(ref, f(cur)))

    /// 敵 id の表示名（敵種名 = `resource#description`）。ログ文言で使う。
    /// 見つからない場合は防御的に "敵" を返す（ログに id を出さない方針）。
    pub def displayName(id: Int32): String \ World.WorldQuery =
        get(id) |> Option.map(d -> d#resource#description) |> Option.getWithDefault("敵")

    /// hp 書込 funnel。純 hp 書込（回復/吸血など）の置換先。
    /// 複合書込（hp＋他 field）は呼び出し側で単独 emit する。
    pub def setHp(id: Int32, newHp: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(id), newHp))

    // 行動済み時に sprite / HP ゲージを暗転し、プレイヤーの waitedColor と外観を揃えるグループ。

    /// 行動済みの sprite / HP ゲージ color（薄い灰色）。プレイヤーの waitedColor と揃える。
    def actedColor(): Color = UITheme.dimmed()
    /// 通常時の color（白 = 元色）。
    def activeColor(): Color = UITheme.white()

    /// 暗転色を World store（unitModulate）へ emit する
    /// （本体描画/HP バー/武器アイコンが同じ store を読む）。
    def setSpriteModulate(id: Int32, color: Color): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetModulate(World.EntityRef.Enemy(id), color))

    /// 敵 id を「行動済み」にして本体スプライトと HP ゲージを暗転する。
    /// 敵ターン中、その敵の行動が終わった時点で呼ぶ。
    pub def setActed(id: Int32): Unit \ World.Command =
        // acted は World 権威（Cmd.SetActed が唯一の source）。
        World.Command.emit(World.Cmd.SetActed(World.EntityRef.Enemy(id), true));
        setSpriteModulate(id, actedColor())

    /// 完全停止（かなしばり）を解除する。被攻撃 or 被投擲の瞬間に呼ぶ。
    /// 停止していなければ no-op（他の時限ステータスは残す）。
    pub def releaseBind(id: Int32): Unit \ {World.Command, World.WorldQuery} =
        // statuses は World 権威＝現在値に clearImmobilized を適用して Seed（全置換）で書く。
        updateStatuses(id, StatusSystem.clearImmobilized)

    /// 全敵の「行動済み」を解除し、本体スプライトと HP ゲージを通常の明るさへ戻す。
    /// 敵ターン開始時に呼ぶ（プレイヤーの clearAllWaited と対称）。
    pub def clearActedAll(): Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let ids = getAll() |> List.map(d -> d#id);
        // 敵ターン開始 tick を World へ発行（statuses のターン開始減算）。
        World.Command.emit(World.Cmd.TickEnemies);
        List.forEach(id -> {
            World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(id), false));  // reset を World へ
            World.Command.emit(World.Cmd.SetActed(World.EntityRef.Enemy(id), false));  // acted reset を World へ
            setSpriteModulate(id, activeColor())
        }, ids);
        // 敵ターン開始時に、いやしのリングを装備した敵の HP を回復する。
        applyRingRegen()

    /// いやしのリングを装備した敵の HP を回復する（最大 HP でクランプ）。敵ターン開始で呼ぶ。
    /// 実際に回復した敵はログに出す。
    pub def applyRingRegen(): Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        let ids = getAll() |> List.map(d -> d#id);
        List.forEach(id -> regenOneEnemy(id), ids)

    /// 1 敵ぶんの Mend 回復。Mend 以外 / 未装備なら no-op（match は入れ子にしない）。
    def regenOneEnemy(id: Int32): Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        // 判定読み（装備指輪/hp）は World 由来 Data（dataFromWorldEnemy）で行う。
        match World.dataFromWorldEnemy(id, World.WorldQuery.get()) {
            case None    => ()
            case Some(d) => mendOneEnemy(id, d)
        }

    /// 回復量を計算して適用するヘルパー（regenOneEnemy から呼ぶ）。
    /// 満タン等で実際に HP が増えないときはログも出さない。
    def mendOneEnemy(id: Int32, d: Data):
            Unit \ {GameLogger.GameLogger, World.Command} =
        let amt = Ring.mendAmount(d#ring);
        let newHp = Combat.heal(d#hp, d#resource#hp, amt)#newHp;
        if (amt <= 0 or newHp <= d#hp) ()
        else {
            GameLogger.enemyLog("${d#resource#description} は いやしのリングで HP+${newHp - d#hp}");
            setHp(id, newHp)
        }

    /// 全敵の sprite / HP ゲージを通常色(active)に戻す。`acted` フラグは変えない。
    /// 味方フェーズ中に「敵の行動済み灰色」を消してアクティブに見せるために使う
    /// （行動済みという扱い自体は残し、見た目だけ通常色に戻す）。
    pub def showAllActive(): Unit \ {World.Command, World.WorldQuery} =
        let ids = getAll() |> List.map(d -> d#id);
        List.forEach(id -> setSpriteModulate(id, activeColor()), ids)

    /// 敵 id が指定の「明るい穴」で照らされているか（World 位置×穴の純関数）。
    /// フレーム 1 回計算した穴（`FogScene.holesNow` / render の共有 holesOpt）を渡して使う。
    /// 未 spawn（pos 不在）は false（居ない＝見えない扱い）。
    /// 隠れていても AI は継続するため、フォグで隠れた敵も行動する点に注意。
    pub def isLitIn(id: Int32, holes: List[GridRect], world: World): Bool =
        World.posOf(World.EntityRef.Enemy(id), world)
            |> Option.map(p -> FogScene.insideAny(p, holes))
            |> Option.getWithDefault(false)

    /// 敵 id がいまフォグで隠れず見えているか（現在の明るい穴からの導出）。
    /// CursorScene のホバー情報抑制・UnitCard の表示対象判定などの単発読みに使う。
    /// 盤面レス（穴 None）は false。
    pub def isVisible(id: Int32): Bool \ {SelectedPlayer.State, World.WorldQuery} =
        match FogScene.holesNow() {
            case None        => false
            case Some(holes) => isLitIn(id, holes, World.WorldQuery.get())
        }

    /// 敵 id を `target` に移動させる。論理位置（World の pos）は即時更新し、
    /// 見た目の補間は renderPos tween に委ねる（PlayerScene.moveToById と同じ機構）。
    /// 呼び出しごとに 1 マス分（隣接セル）の Tween を登録する前提。複数マス分の
    /// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ呼ぶことで実現する。
    /// **歩行可否（壁・他駒）の判定は呼び出し側（EnemyAI）が済ませている前提**で、
    /// EnemyScene 自身は衝突判定を持たない。
    pub def moveTo(id: Int32, target: {x = Int32, y = Int32},
                    map: MapSnapshot): Unit \ {World.Command, World.WorldQuery} =
        // プレイヤー移動（PlayerScene）と同じ `SimEvent.Moved` seam に統一。
        //   moveTo = SYSTEM(stepEnemyMove: Cmd.Move emit + Moved 返却) → VIEW(replayMovedEvent 再生)。
        //   歩行可否は呼び出し側（EnemyAI.decideAction）が済ませている前提＝System は判定せず書くだけ。
        // INVARIANT: replayMovedEvent は move-seam 専用＝Moved 以外は bug! で落ちる（no-op ではない）。
        // ここは stepEnemyMove が常に Moved を返すので安全。Moved 以外の event を渡す場合は
        // 必ず Moved に pre-filter すること。
        replayMovedEvent(stepEnemyMove(id, target), map)

    /// SYSTEM(sim): 敵 1 体を target へ動かす位置 write。`Cmd.Move` を emit し `Moved` を返す。
    /// 合法性は EnemyAI が決定済み（プレイヤーの `stepPlayerMove` と違い board 再判定はしない）。
    pub def stepEnemyMove(id: Int32, target: {x = Int32, y = Int32}):
            World.SimEvent \ World.Command =
        World.Command.emit(World.Cmd.Move(World.EntityRef.Enemy(id), target));
        World.SimEvent.Moved(World.EntityRef.Enemy(id), target)

    /// VIEW(replay): `SimEvent.Moved` の敵分を再生する。プレイヤー分は対象外
    /// （`PlayerScene.replayMovedEvent` が担当）＝faction ごとに自分の event を再生。
    /// faction 分岐は 1 段の match に留め、敵の見た目再生は `replayEnemyMoveView` に委譲（ネスト回避）。
    pub def replayMovedEvent(event: World.SimEvent, map: MapSnapshot):
            Unit \ {World.Command, World.WorldQuery} =
        match event {
            case World.SimEvent.Moved(World.EntityRef.Enemy(id), target)  => replayEnemyMoveView(id, target, map)
            case World.SimEvent.Moved(World.EntityRef.Player(_), _)        => ()
            // simevent-algebra: 拡張された非 Moved variant は move seam に来ない（production emitter 無し）。
            // 黙って no-op せず、move seam 専用 invariant 違反として loud に落とす。
            case _ => bug!("EnemyScene.replayMovedEvent: non-Moved event on move seam")
        }

    /// 敵 1 体の move 見た目再生（Tween 滑走 + 左右反転 + prevPos 記録）。
    def replayEnemyMoveView(id: Int32, target: {x = Int32, y = Int32},
                             map: MapSnapshot): Unit \ {World.Command, World.WorldQuery} =
        // 始点は World の描画位置。`Cmd.Move` は emit 済み（posOf=target）なので、renderPos 未 seed
        // （一度も滑走していない敵）は prevPos（Move が自動記録した直前セル）のセル中心、それも無ければ
        // target のセル中心へフォールバック。
        let w0 = World.WorldQuery.get();
        let startWorld  = match (World.renderPosOf(World.EntityRef.Enemy(id), w0),
                                 World.prevPosOf(World.EntityRef.Enemy(id), w0)) {
            case (Some(p), _)    => p
            case (None, Some(c)) => MapSnapshot.cellCenter(c)
            case (None, None)    => MapSnapshot.cellCenter(target)
        };
        let targetWorld = MapSnapshot.gridToWorld(target, map);
        // 描画位置 tween は World（renderPos）が唯一の権威（読者は `World.visualPosOf` で導出）。
        World.moveUnit(World.EntityRef.Enemy(id), {start = startWorld, target = targetWorld}, Duration.toSeconds(slideDuration()));
        // 移動前位置は World.prevPosOf（applyCmd の Move が直前位置を自動記録）から読む。
        let prevX = World.prevPosOf(World.EntityRef.Enemy(id), World.WorldQuery.get())
            |> Option.map(p -> p#x);
        // flipForFacing 付き (= 左向き絵) の敵だけ左右反転する。match でなく Option パイプで畳む。
        get(id)
            |> Option.filter(d -> d#resource#sprite#flipForFacing)
            |> Option.flatMap(_ -> prevX)
            |> Option.map(px -> applyFacingFlip(id, px, target#x))
            |> Option.getWithDefault(())

    /// 左右反転を World store（unitFlipH）へ emit する。
    def setSpriteFlipH(id: Int32, h: Bool): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetFlipH(World.EntityRef.Enemy(id), h))

    /// 横移動の符号で「左向き絵」を反転する。右移動 (dx>0) で flipH=true (右向き)、
    /// 左移動で flipH=false。縦移動 (dx==0) は現状維持。
    def applyFacingFlip(id: Int32, prevX: Int32, targetX: Int32): Unit \ World.Command =
        let dx = targetX - prevX;
        if (dx > 0) setSpriteFlipH(id, true)
        else if (dx < 0) setSpriteFlipH(id, false)
        else ()

    /// 敵 id を `target` に **瞬間移動** で戻す（杖の「いれかえ」用）。
    /// 進行中の Tween があればキャンセルし、描画位置（renderPos）と論理位置（pos）を
    /// 同時に target に揃える。`PlayerScene.snapTo` と同じ流儀。
    pub def snapTo(id: Int32, target: {x = Int32, y = Int32}): Unit \ World.Command =
        let world = MapSnapshot.cellCenter(target);
        // SetRenderPos が進行中の World 描画 tween を破棄しつつ renderPos を
        // target にスナップ（tweens から Position を remove）＝いれかえ後に滑り残らない。
        World.Command.emit(World.Cmd.SetRenderPos(World.EntityRef.Enemy(id), world));
        World.Command.emit(World.Cmd.Move(World.EntityRef.Enemy(id), target))

    /// 指定セルに居る（生きている）敵の id を返す。死亡演出中の敵は対象外。
    /// PlayerAttack フェーズで「カーソルが赤マス上の敵に乗っているか」の判定に使う。
    pub def findIdAt(coord: {x = Int32, y = Int32}): Option[Int32] \ World.WorldQuery =
        getAll()
            |> List.findMap(d ->
                if (not d#isDying
                    and d#gridPos#x == coord#x
                    and d#gridPos#y == coord#y) Some(d#id)
                else None)

    // ────────────────────────────────────────────────────────
    // (E) 死亡演出 — dyingElapsed の点滅導出 → DeathBlinkDone で Despawn
    // ────────────────────────────────────────────────────────

    /// 敵 id の HP を 0 にして死亡演出を開始する。
    /// `isDying = true` を立て、`SetDying` で dyingElapsed=0 を seed する（点滅 alpha は
    /// renderUnits が dyingElapsed から導出。全長到達で DeathBlinkDone signal →
    /// `completeDeath` が Despawn と down_enemy 再生を行う）。
    pub def startDeathAnimation(id: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(id), 0));  // 死亡で hp=0 を World へ
        World.Command.emit(World.Cmd.SetDying(World.EntityRef.Enemy(id)))   // isDying を World へ

    /// 死亡点滅の完了（DeathBlinkDone）で呼ぶ後始末。
    /// 敵撃破 SE (down_enemy) を再生し、World の全 store から除去する
    /// （damage の後に down_enemy が鳴る順序保証）。
    pub def completeDeath(id: Int32): Unit \ {GameEngine.Audio, World.Command} =
        AudioStreamPlayer.play("down_enemy");
        World.Command.emit(World.Cmd.Despawn(World.EntityRef.Enemy(id)))

    // ────────────────────────────────────────────────────────
    // (F) 初期 spawn のスナップショットと再配置（ゲームオーバー時のリセット）
    // ────────────────────────────────────────────────────────

    /// 在籍する全敵の `Spawn` 情報（id / gridPos / homeModuleIdx / resource / weapon）を
    /// 抽出する。`Game.start` で初回 buildPlayingScene 直後に呼んで保存し、ゲームオーバー時に
    /// `respawnFromInitial` で同じ位置・同じ敵種別・同じ武器で再配置する。
    /// スナップショットは攻撃前に取られる前提で `weapon` は常に Some。
    pub def snapshotSpawns(): List[Spawn] \ World.WorldQuery =
        getAll()
            |> List.map(d ->
                let weapon = match d#weapon {
                    case Some(w) => w
                    case None    => bug!("EnemyScene.snapshotSpawns: weapon is None for 敵${d#id} (snapshot taken after weapon broke?)")
                };
                ({id = d#id, resourceId = d#resourceId, gridPos = d#gridPos, moduleIdx = d#homeModuleIdx, resource = d#resource, weapon = weapon}: Spawn))

    /// 既存の敵を全て取り除き、`spawns` から再構築する。
    /// 各敵は `addOneEnemy` を使って HP・alerted・dying を初期値で生成する。
    pub def respawnFromInitial(spawns: List[Spawn], ringCatalog: Ring.RingCatalog):
            Unit \ {World.Command, World.WorldQuery} =
        // 既存敵を World の全 store から除去する（build choke 外から呼ばれても store が腐らない）。
        List.forEach(d -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Enemy(d#id))), getAll());
        List.forEach(sp -> addOneEnemy(sp, ringCatalog), spawns)

    /// 現在の全敵を取り除く（女神の加護でフロアの敵を一掃する）。
    /// World から Despawn するので描画（本体 sprite / HP バー / 武器アイコン）も消える。
    pub def removeAll(): Unit \ {World.Command, World.WorldQuery} =
        List.forEach(d -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Enemy(d#id))), getAll())

    /// スナップショットの敵リストから決定論的に再配置する（乱数なし）。
    /// `resourceId` で EnemyResource を、`weapon` の id で武器を catalog から引き直して `Spawn` を作り、
    /// `respawnFromInitial` で full HP・既定状態に配置したあと、snap の動的値
    /// （HP / 時限ステータス / 検知フラグ / 指輪）を overlay で上書きする。
    /// 進入時スナップショット（フロア最初から）では full HP・既定状態なので overlay しても不変、
    /// 中断セーブからの再開では中断時点の現在値がそのまま復元される（snapshot が単一の真実源）。
    pub def addFromSnaps(snaps: List[FloorSnapshot.EnemySnap],
                          enemyCatalog: EnemyCatalog.EnemyCatalog,
                          weaponCatalog: WeaponCatalog.WeaponCatalog,
                          ringCatalog: Ring.RingCatalog): Unit \ {World.Command, World.WorldQuery} =
        let spawns = snaps |> List.map(snap -> snapToSpawn(snap, enemyCatalog, weaponCatalog));
        respawnFromInitial(spawns, ringCatalog);
        List.forEach(snap -> restoreEnemyState(snap, ringCatalog), snaps)

    /// 敵 1 体の現在状態（HP / 時限ステータス / 検知フラグ / 指輪）を snap から上書きする。
    /// HP バーは World.hp から直描き＝ここでの押し込み更新は不要。
    def restoreEnemyState(snap: FloorSnapshot.EnemySnap, ringCatalog: Ring.RingCatalog):
            Unit \ World.Command =
        let ring = snap#ring |> Option.map(id -> Ring.lookup(id, ringCatalog));
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Enemy(snap#id), snap#hp));  // 復元 hp を World へ
        World.Command.emit(World.Cmd.SetAlerted(World.EntityRef.Enemy(snap#id), snap#alerted));  // 復元 alerted を World へ
        World.Command.emit(World.Cmd.SetEnemyRing(snap#id, ring));  // 復元 ring を World へ
        // 復元 statuses / ring は World 権威。中断再開は in-loop phase change のため
        // Seed で明示復元する（refreshMirror は preserve）。
        World.Command.emit(World.Cmd.Seed(World.EntityRef.Enemy(snap#id), snap#statuses))

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
    pub def captureSnaps(weaponCatalog: WeaponCatalog.WeaponCatalog,
                          ringCatalog: Ring.RingCatalog): List[FloorSnapshot.EnemySnap] \ World.WorldQuery =
        getAll() |> List.map(d ->
            ({id = d#id, resourceId = d#resourceId, gridPos = d#gridPos, hp = d#hp,
               moduleIdx = d#homeModuleIdx,
               weapon = d#weapon |> Option.map(w ->
                   {id = CatalogId.requireId("weapon", w#name, WeaponCatalog.idOf(w, weaponCatalog)),
                    durability = w#durability}),
               ring = d#ring |> Option.map(r -> CatalogId.requireId("ring", r#name, Ring.idOf(r, ringCatalog))),
               statuses = d#statuses, alerted = d#alerted}: FloorSnapshot.EnemySnap))

    // ────────────────────────────────────────────────────────
    // (G) 攻撃モーション関連のクエリとシグナル受信
    //     攻撃の解決本体（startAttack / 命中適用 / 反撃判定）は CombatDriver に集約。
    // ────────────────────────────────────────────────────────

    /// 攻撃モーション中の敵が 1 体以上いれば true。
    /// モーション中はキューを進めてはならないため、呼び出し元は必ずこれで待機する。
    pub def anyAttacking(): Bool \ World.WorldQuery =
        World.anyEnemyAttacking(World.WorldQuery.get())

    /// フォグで見えている生存敵が 1 体以上いれば true（死亡演出中 `isDying` は除外）。
    /// 在籍・可視とも World＋現在の明るい穴からの導出（集合自動継続の「画面内に敵がいるか」判定に使う）。
    pub def anyVisible(): Bool \ {SelectedPlayer.State, World.WorldQuery} =
        match FogScene.holesNow() {
            case None        => false
            case Some(holes) =>
                let world = World.WorldQuery.get();
                World.enemyIdsOf(world)
                    |> List.exists(id -> not World.isDyingOf(World.EntityRef.Enemy(id), world)
                                             and isLitIn(id, holes, world))
        }

    /// DeathBlinkDone signal のエントリポイント。
    /// SE 再生と Despawn を completeDeath に委譲する。
    pub def onDeathBlinkDone(enemyId: Int32): Unit \ {GameEngine.Audio, World.Command} =
        completeDeath(enemyId)

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

    /// この敵の装備武器の戦闘投影。`combatView` と World read-model 構築が共有する。
    /// 敵は得意/苦手の概念がないので proficient は常に true。武器なしは None。
    pub def equippedWeaponView(data: Data): Option[Combat.WeaponView] =
        Combat.weaponView(data#weapon, true)

    /// この敵の装備指輪ボーナス。`combatView` と World read-model 構築が共有する。
    pub def equippedRingBonus(data: Data): Ring.Bonuses =
        Ring.bonuses(data#ring)

    /// この敵の盤上ビュー（faction = Enemy）。`Encounter` の join で使う。
    /// `weaponRange` は装備武器の射程。敵に `hidden` は無いので常に false。
    pub def unitView(data: Data): UnitView =
        {id = data#id, faction = Faction.Enemy, pos = data#gridPos,
         hp = data#hp, moveTiles = data#moveTiles,
         weaponRange = data#weapon |> Option.map(w -> w#range),
         combat = combatView(data), isDying = data#isDying, hidden = false,
         aiType = data#resource#aiType}

}
