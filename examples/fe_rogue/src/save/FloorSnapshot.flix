/// FloorSnapshot — フロアの状態を「カタログ id ＋ 動的値」だけで表す純粋データ。
///
/// 全滅時の「そのフロアの最初から」復元と、将来の中断機能（JSON セーブ）が共有する土台。
/// resource 実体・GPU ハンドル・関数を一切含まないため、そのまま JSON 化（`Saveable`）でき、
/// 空の World から決定論的に再構築できる（マップは `DungeonGenerator.Plan` を
/// `composeFromSideConnections` に渡して乱数なしで再現）。
///
/// 進入時スナップショット（リスタート用）では動的値は「進入時の値」（敵=full hp・default、
/// 味方=carry 反映後の HP/durability）。型は現在状態も表現できるので、中断保存では現在値を入れる。
mod FloorSnapshot {

    // 武器 / 杖 / 消費の持ち物は `{id = String, durability = Int32}`（id はカタログ id、durability は
    // 実行時の残り耐久）で表す。型エイリアスにすると別モジュールの推論で構造型と unify しない癖が出るため
    // 各所でインラインに展開して書く。

    /// 味方 1 体のスナップショット。`classId` は UnitCatalog のクラス id（resource は復元時に lookup）。
    /// 注: `facing` / `statuses` は**現在状態（中断保存）用に保持**するフィールドで、リスタート復元
    /// （進入時 = facing 既定 / statuses 空）では消費しない。中断ロード実装時に復元側で読む想定。
    pub type alias PlayerSnap = {
        id           = Int32,
        classId      = String,
        gridPos      = {x = Int32, y = Int32},
        hp           = Int32,
        level        = Int32,
        exp          = Int32,
        // 成長後の 9 ステータス（最大 HP 含む）。レベルアップは成長率乱数なので level から再計算できず、
        // 値を保存する（`PlayerDriver.CarryData#stats` と同じ役割）。復元時 base resource に上書きする。
        stats        = LevelSystem.Stats,
        facing       = Dir4.Dir4,
        statuses     = List[StatusSystem.Status],
        weapons      = List[{id = String, durability = Int32}],
        staves       = List[{id = String, durability = Int32}],
        consumables  = List[{id = String, durability = Int32}],
        rings        = List[String],   // 指輪 id のリスト（先頭が装備候補）
        ringEquipped = Bool
    }

    /// 敵 1 体のスナップショット。`resourceId` は EnemyCatalog の id（resource は復元時に lookup）。
    /// `weapon` は装備中武器（id ＋ 残り耐久、壊れて無ければ None）。`ring` は装備指輪 id（多くは None）。
    /// 注: `hp` / `statuses` / `alerted` は**現在状態（中断保存）用**。リスタート復元は full HP・既定状態で
    /// 再配置するため消費しない（中断ロード実装時に復元側で読む想定）。
    pub type alias EnemySnap = {
        id         = Int32,
        resourceId = String,
        gridPos    = {x = Int32, y = Int32},
        hp         = Int32,
        moduleIdx  = Int32,
        weapon     = Option[{id = String, durability = Int32}],
        ring       = Option[String],
        statuses   = List[StatusSystem.Status],
        alerted    = Bool
    }

    /// 床に落ちているアイテム 1 個（種別 id ＋ セル座標）。
    pub type alias ItemSnap = { gridPos = {x = Int32, y = Int32}, itemKey = String }

    /// 宝箱 1 個（箱種別 id ＋ 中身アイテム id ＋ セル座標）。
    pub type alias ChestSnap = {
        gridPos   = {x = Int32, y = Int32},
        chestKey  = String,
        contentId = String
    }

    /// フロア全体のスナップショット。
    pub type alias T = {
        floorId  = String,
        mapPlan  = DungeonGenerator.Plan,
        players  = List[PlayerSnap],
        enemies  = List[EnemySnap],
        items    = List[ItemSnap],
        chests   = List[ChestSnap],
        stairs   = Option[{x = Int32, y = Int32}]
    }

    /// 進入時スナップショットの保持 effect（`InitialSpawns` と同じ handler 注入パターン）。
    /// 全滅時の「そのフロアの最初から」で読み出す。初期値 `None`（フロア進入で `put` される）。
    pub eff State {
        /// 保存済みスナップショットを返す（未保存なら `None`）。
        def get(): Option[T]
        /// 進入時スナップショットを上書き保存する。
        def put(snapshot: T): Unit
    }

    /// World の `floorSnapshot` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として
    /// 受け取り、get/put とも World 経由で読み書きする（初期値 `None` は `World.empty` が持つ）。
    pub def withState(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k)           = k(World.floorSnapshotOf(Ref.get(worldRef)))
                def put(snapshot, k) = { Ref.put(World.applyCmd(World.Cmd.SetFloorSnapshot(Some(snapshot)), Ref.get(worldRef)), worldRef); k() }
            }
        }
}

// ════════════════════════════════════════════════════════════════════════
// FloorSnapshotCodec — 中断セーブの JSON round-trip（本体）
// ════════════════════════════════════════════════════════════════════════
//
// `FloorSnapshot.T` は type alias（構造的レコード型）なので **`Saveable` instance は付けられない**
// （instance は nominal 型のみ）。ここでは encode/decode を plain 関数で提供し、ディスク I/O 用の
// `Saveable` は nominal にラップした `SuspendSave.Save` 側で定義してこの codec へ委譲する。
// テストは decode 結果を比較可能スカラーのタプルに射影して検証する（`TestFloorSnapshotCodec`）。

/// `FloorSnapshot.T` 1 件分の encode / decode。ネスト型（Plan / Stats / Status / Dir4 /
/// {id,durability} / {x,y}）を個別ヘルパーに分け、各 decode は **明示型注釈付き record リテラル**
/// で構造型を固定する（type alias の構造型 unify 癖を避ける）。`Option` フィールド（敵の weapon/ring・
/// stairs）は **キー欠落 = None** で表す（forM の束縛にせず yield 内で `Map.get |> flatMap` で読む）。
mod FloorSnapshotCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JBool}
    use JsonCodec.{expectObject, expectString, expectInt, expectBool, intToBd,
                    encodeList, decodeList}
    use FloorSnapshot.{T, PlayerSnap, EnemySnap, ItemSnap, ChestSnap}
    use DungeonGenerator.Plan
    use DungeonComposer.{SideConnection, SideRef}
    use LevelSystem.Stats
    use StatusSystem.Status

    // ── {x, y} セル ──
    def encodeCell(cell: {x = Int32, y = Int32}): Json =
        JObject(Map#{"x" => JNumber(intToBd(cell#x)), "y" => JNumber(intToBd(cell#y))})

    def decodeCell(element: Json): Option[{x = Int32, y = Int32}] =
        forM (
            obj <- expectObject(element);
            xJ  <- Map.get("x", obj);
            yJ  <- Map.get("y", obj);
            x   <- expectInt(xJ);
            y   <- expectInt(yJ)
        ) yield ({x = x, y = y}: {x = Int32, y = Int32})

    // ── LevelSystem.Stats（数値 8 フィールド直書き）──
    def encodeStats(s: Stats): Json =
        JObject(Map#{
            "hp"           => JNumber(intToBd(s#hp)),
            "attack"       => JNumber(intToBd(s#attack)),
            "defense"      => JNumber(intToBd(s#defense)),
            "magicAttack"  => JNumber(intToBd(s#magicAttack)),
            "magicDefense" => JNumber(intToBd(s#magicDefense)),
            "speed"        => JNumber(intToBd(s#speed)),
            "skill"        => JNumber(intToBd(s#skill)),
            "luck"         => JNumber(intToBd(s#luck)),
            "constitution" => JNumber(intToBd(s#constitution))
        })

    def decodeStats(element: Json): Option[Stats] =
        forM (
            obj  <- expectObject(element);
            hpJ  <- Map.get("hp", obj);
            atJ  <- Map.get("attack", obj);
            dfJ  <- Map.get("defense", obj);
            maJ  <- Map.get("magicAttack", obj);
            mdJ  <- Map.get("magicDefense", obj);
            spJ  <- Map.get("speed", obj);
            skJ  <- Map.get("skill", obj);
            lkJ  <- Map.get("luck", obj);
            hp   <- expectInt(hpJ);
            at   <- expectInt(atJ);
            df   <- expectInt(dfJ);
            ma   <- expectInt(maJ);
            md   <- expectInt(mdJ);
            sp   <- expectInt(spJ);
            sk   <- expectInt(skJ);
            lk   <- expectInt(lkJ)
        ) yield {
            // constitution は旧セーブ後方互換のため省略可（欠落時は 0）。
            let con = Map.get("constitution", obj) |> Option.flatMap(expectInt)
                            |> Option.getWithDefault(0);
            ({hp = hp, attack = at, defense = df, magicAttack = ma,
              magicDefense = md, speed = sp, skill = sk, luck = lk,
              constitution = con}: Stats)
        }

    // ── StatusSystem.Status ──
    def encodeStatus(s: Status): Json =
        JObject(Map#{
            "effect"    => JString(StatusSystem.effectToString(s#effect)),
            "magnitude" => JNumber(intToBd(s#magnitude)),
            "remaining" => JNumber(intToBd(s#remaining))
        })

    def decodeStatus(element: Json): Option[Status] =
        forM (
            obj    <- expectObject(element);
            effJ   <- Map.get("effect", obj);
            magJ   <- Map.get("magnitude", obj);
            remJ   <- Map.get("remaining", obj);
            effStr <- expectString(effJ);
            effVal <- Result.toOption(StatusSystem.parseEffect(effStr));
            mag    <- expectInt(magJ);
            rem    <- expectInt(remJ)
        ) yield ({effect = effVal, magnitude = mag, remaining = rem}: Status)

    // ── {id, durability}（武器 / 杖 / 消費の持ち物 1 件）──
    def encodeIdDur(w: {id = String, durability = Int32}): Json =
        JObject(Map#{"id" => JString(w#id), "durability" => JNumber(intToBd(w#durability))})

    def decodeIdDur(element: Json): Option[{id = String, durability = Int32}] =
        forM (
            obj   <- expectObject(element);
            idJ   <- Map.get("id", obj);
            durJ  <- Map.get("durability", obj);
            id    <- expectString(idJ);
            dur   <- expectInt(durJ)
        ) yield ({id = id, durability = dur}: {id = String, durability = Int32})

    // ── DungeonGenerator.Plan（SideRef / SideConnection 経由）──
    def encodeSideRef(r: SideRef): Json =
        JObject(Map#{
            "moduleIndex" => JNumber(intToBd(r#moduleIndex)),
            "side"        => JString(DungeonComposer.doorSideToString(r#side))
        })

    def decodeSideRef(element: Json): Option[SideRef] =
        forM (
            obj     <- expectObject(element);
            miJ     <- Map.get("moduleIndex", obj);
            sideJ   <- Map.get("side", obj);
            mi      <- expectInt(miJ);
            sideStr <- expectString(sideJ);
            side    <- Result.toOption(DungeonComposer.parseDoorSide(sideStr))
        ) yield ({moduleIndex = mi, side = side}: SideRef)

    def encodeSideConnection(c: SideConnection): Json =
        JObject(Map#{"a" => encodeSideRef(c#a), "b" => encodeSideRef(c#b)})

    def decodeSideConnection(element: Json): Option[SideConnection] =
        forM (
            obj <- expectObject(element);
            aJ  <- Map.get("a", obj);
            bJ  <- Map.get("b", obj);
            a   <- decodeSideRef(aJ);
            b   <- decodeSideRef(bJ)
        ) yield ({a = a, b = b}: SideConnection)

    def encodePlan(p: Plan): Json =
        JObject(Map#{
            "modulePaths"     => encodeList(s -> JString(s), p#modulePaths),
            "sideConnections" => encodeList(encodeSideConnection, p#sideConnections),
            "roomCount"       => JNumber(intToBd(p#roomCount))
        })

    def decodePlan(element: Json): Option[Plan] =
        forM (
            obj  <- expectObject(element);
            mpJ  <- Map.get("modulePaths", obj);
            scJ  <- Map.get("sideConnections", obj);
            rcJ  <- Map.get("roomCount", obj);
            mp   <- decodeList(expectString, mpJ);
            sc   <- decodeList(decodeSideConnection, scJ);
            rc   <- expectInt(rcJ)
        ) yield ({modulePaths = mp, sideConnections = sc, roomCount = rc}: Plan)

    // ── PlayerSnap ──
    def encodePlayer(p: PlayerSnap): Json =
        JObject(Map#{
            "id"           => JNumber(intToBd(p#id)),
            "classId"      => JString(p#classId),
            "gridPos"      => encodeCell(p#gridPos),
            "hp"           => JNumber(intToBd(p#hp)),
            "level"        => JNumber(intToBd(p#level)),
            "exp"          => JNumber(intToBd(p#exp)),
            "stats"        => encodeStats(p#stats),
            "facing"       => JString(Staff.directionToString(p#facing)),
            "statuses"     => encodeList(encodeStatus, p#statuses),
            "weapons"      => encodeList(encodeIdDur, p#weapons),
            "staves"       => encodeList(encodeIdDur, p#staves),
            "consumables"  => encodeList(encodeIdDur, p#consumables),
            "rings"        => encodeList(s -> JString(s), p#rings),
            "ringEquipped" => JBool(p#ringEquipped)
        })

    def decodePlayer(element: Json): Option[PlayerSnap] =
        forM (
            obj      <- expectObject(element);
            idJ      <- Map.get("id", obj);
            classJ   <- Map.get("classId", obj);
            posJ     <- Map.get("gridPos", obj);
            hpJ      <- Map.get("hp", obj);
            lvJ      <- Map.get("level", obj);
            expJ     <- Map.get("exp", obj);
            statsJ   <- Map.get("stats", obj);
            faceJ    <- Map.get("facing", obj);
            statusJ  <- Map.get("statuses", obj);
            weaponsJ <- Map.get("weapons", obj);
            stavesJ  <- Map.get("staves", obj);
            consJ    <- Map.get("consumables", obj);
            ringsJ   <- Map.get("rings", obj);
            reJ      <- Map.get("ringEquipped", obj);
            id       <- expectInt(idJ);
            classId  <- expectString(classJ);
            pos      <- decodeCell(posJ);
            hp       <- expectInt(hpJ);
            level    <- expectInt(lvJ);
            exp      <- expectInt(expJ);
            stats    <- decodeStats(statsJ);
            faceStr  <- expectString(faceJ);
            facing   <- Result.toOption(Staff.parseDirection(faceStr));
            statuses <- decodeList(decodeStatus, statusJ);
            weapons  <- decodeList(decodeIdDur, weaponsJ);
            staves   <- decodeList(decodeIdDur, stavesJ);
            cons     <- decodeList(decodeIdDur, consJ);
            rings    <- decodeList(expectString, ringsJ);
            re       <- expectBool(reJ)
        ) yield ({id = id, classId = classId, gridPos = pos, hp = hp, level = level,
                   exp = exp, stats = stats, facing = facing, statuses = statuses,
                   weapons = weapons, staves = staves, consumables = cons,
                   rings = rings, ringEquipped = re}: PlayerSnap)

    // ── EnemySnap（weapon / ring は Option = キー欠落で None）──
    def encodeEnemy(e: EnemySnap): Json =
        let base = Map#{
            "id"         => JNumber(intToBd(e#id)),
            "resourceId" => JString(e#resourceId),
            "gridPos"    => encodeCell(e#gridPos),
            "hp"         => JNumber(intToBd(e#hp)),
            "moduleIdx"  => JNumber(intToBd(e#moduleIdx)),
            "statuses"   => encodeList(encodeStatus, e#statuses),
            "alerted"    => JBool(e#alerted)
        };
        let withWeapon = match e#weapon {
            case Some(w) => Map.insert("weapon", encodeIdDur(w), base)
            case None    => base
        };
        let withRing = match e#ring {
            case Some(r) => Map.insert("ring", JString(r), withWeapon)
            case None    => withWeapon
        };
        JObject(withRing)

    def decodeEnemy(element: Json): Option[EnemySnap] =
        forM (
            obj      <- expectObject(element);
            idJ      <- Map.get("id", obj);
            resJ     <- Map.get("resourceId", obj);
            posJ     <- Map.get("gridPos", obj);
            hpJ      <- Map.get("hp", obj);
            modJ     <- Map.get("moduleIdx", obj);
            statusJ  <- Map.get("statuses", obj);
            alertJ   <- Map.get("alerted", obj);
            id       <- expectInt(idJ);
            resId    <- expectString(resJ);
            pos      <- decodeCell(posJ);
            hp       <- expectInt(hpJ);
            moduleIdx <- expectInt(modJ);
            statuses <- decodeList(decodeStatus, statusJ);
            alerted  <- expectBool(alertJ)
        ) yield {
            let weapon = Map.get("weapon", obj) |> Option.flatMap(decodeIdDur);
            let ring   = Map.get("ring", obj) |> Option.flatMap(expectString);
            ({id = id, resourceId = resId, gridPos = pos, hp = hp, moduleIdx = moduleIdx,
               weapon = weapon, ring = ring, statuses = statuses, alerted = alerted}: EnemySnap)
        }

    // ── ItemSnap / ChestSnap ──
    def encodeItem(i: ItemSnap): Json =
        JObject(Map#{"gridPos" => encodeCell(i#gridPos), "itemKey" => JString(i#itemKey)})

    def decodeItem(element: Json): Option[ItemSnap] =
        forM (
            obj  <- expectObject(element);
            posJ <- Map.get("gridPos", obj);
            keyJ <- Map.get("itemKey", obj);
            pos  <- decodeCell(posJ);
            key  <- expectString(keyJ)
        ) yield ({gridPos = pos, itemKey = key}: ItemSnap)

    def encodeChest(c: ChestSnap): Json =
        JObject(Map#{
            "gridPos"   => encodeCell(c#gridPos),
            "chestKey"  => JString(c#chestKey),
            "contentId" => JString(c#contentId)
        })

    def decodeChest(element: Json): Option[ChestSnap] =
        forM (
            obj    <- expectObject(element);
            posJ   <- Map.get("gridPos", obj);
            keyJ   <- Map.get("chestKey", obj);
            contJ  <- Map.get("contentId", obj);
            pos    <- decodeCell(posJ);
            key    <- expectString(keyJ);
            cont   <- expectString(contJ)
        ) yield ({gridPos = pos, chestKey = key, contentId = cont}: ChestSnap)

    // ── FloorSnapshot.T（stairs は Option = キー欠落で None）──
    pub def encode(t: T): Json =
        let base = Map#{
            "floorId" => JString(t#floorId),
            "mapPlan" => encodePlan(t#mapPlan),
            "players" => encodeList(encodePlayer, t#players),
            "enemies" => encodeList(encodeEnemy, t#enemies),
            "items"   => encodeList(encodeItem, t#items),
            "chests"  => encodeList(encodeChest, t#chests)
        };
        let withStairs = match t#stairs {
            case Some(cell) => Map.insert("stairs", encodeCell(cell), base)
            case None       => base
        };
        JObject(withStairs)

    pub def decode(element: Json): Option[T] =
        forM (
            obj      <- expectObject(element);
            floorJ   <- Map.get("floorId", obj);
            planJ    <- Map.get("mapPlan", obj);
            playersJ <- Map.get("players", obj);
            enemiesJ <- Map.get("enemies", obj);
            itemsJ   <- Map.get("items", obj);
            chestsJ  <- Map.get("chests", obj);
            floorId  <- expectString(floorJ);
            plan     <- decodePlan(planJ);
            players  <- decodeList(decodePlayer, playersJ);
            enemies  <- decodeList(decodeEnemy, enemiesJ);
            items    <- decodeList(decodeItem, itemsJ);
            chests   <- decodeList(decodeChest, chestsJ)
        ) yield {
            let stairs = Map.get("stairs", obj) |> Option.flatMap(decodeCell);
            ({floorId = floorId, mapPlan = plan, players = players, enemies = enemies,
               items = items, chests = chests, stairs = stairs}: T)
        }
}
