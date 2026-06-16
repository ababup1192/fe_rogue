/// 中断セーブ codec（`Saveable[FloorSnapshot.T]` / `SuspendSave.T`）の round-trip テスト。
///
/// `FloorSnapshot.T` 系は type alias（Eq derive 不可）なので、decode 結果を
/// **比較可能スカラーのタプルに射影**して `assertEq` で検証する（プロジェクト慣習）。
/// 壊れた JSON が `None` になること（= 安全に「中断データ無し」へ倒れる）も回帰防止する。
mod TestFloorSnapshotCodec {

    use FloorSnapshot.{T, PlayerSnap, EnemySnap, ItemSnap, ChestSnap}
    use Staff.Direction
    use StatusSystem.{Status, StatusEffect}
    use LevelSystem.Stats
    use DungeonComposer.{SideConnection, SideRef, DoorSide}

    /// 検証用の小さなフロアスナップショット（区切りの良い数値で組む）。
    def sample(): T =
        let stats = ({hp = 24, attack = 12, defense = 9, magicAttack = 4,
                      magicDefense = 5, speed = 14, skill = 10, luck = 8}: Stats);
        let pStatuses = ({effect = StatusEffect.SpdDown, magnitude = 3, remaining = 2}: Status) :: Nil;
        let player = ({id = 0, classId = "lord", gridPos = {x = 10, y = 15},
                       hp = 22, level = 3, exp = 45, stats = stats,
                       facing = Direction.Down, statuses = pStatuses,
                       weapons = ({id = "iron_sword", durability = 45}: {id = String, durability = Int32}) :: Nil,
                       staves = (Nil: List[{id = String, durability = Int32}]),
                       consumables = ({id = "vulnerary", durability = 3}: {id = String, durability = Int32}) :: Nil,
                       rings = "plain_ring" :: Nil, ringEquipped = true}: PlayerSnap);
        let eStatuses = ({effect = StatusEffect.Immobilized, magnitude = 0, remaining = 4}: Status) :: Nil;
        let enemy = ({id = 1, resourceId = "goblin", gridPos = {x = 8, y = 12},
                      hp = 8, moduleIdx = 2,
                      weapon = Some(({id = "iron_axe", durability = 30}: {id = String, durability = Int32})),
                      ring = (None: Option[String]), statuses = eStatuses, alerted = true}: EnemySnap);
        let conn = ({a = ({moduleIndex = 0, side = DoorSide.Right}: SideRef),
                     b = ({moduleIndex = 1, side = DoorSide.Left}: SideRef)}: SideConnection);
        let plan = ({modulePaths = "a.json" :: "b.json" :: Nil,
                     sideConnections = conn :: Nil, roomCount = 3}: DungeonGenerator.Plan);
        ({floorId = "f01", mapPlan = plan, players = player :: Nil, enemies = enemy :: Nil,
          items = ({gridPos = {x = 3, y = 4}, itemKey = "longsword"}: ItemSnap) :: Nil,
          chests = ({gridPos = {x = 20, y = 20}, chestKey = "wood", contentId = "elixir"}: ChestSnap) :: Nil,
          stairs = Some(({x = 5, y = 6}: {x = Int32, y = Int32}))}: T)

    /// トップレベル（floorId / 各リスト件数 / Plan / stairs）が round-trip で保たれる。
    @Test
    def testRoundTripTopLevel(): Unit \ Assert =
        let decoded = FloorSnapshotCodec.decode(FloorSnapshotCodec.encode(sample()));
        Assert.assertEq(
            expected = Some(("f01", 1, 1, 1, 1, 3, 2, Some((5, 6)))),
            decoded |> Option.map(t ->
                (t#floorId, List.length(t#players), List.length(t#enemies),
                 List.length(t#items), List.length(t#chests),
                 t#mapPlan#roomCount, List.length(t#mapPlan#modulePaths),
                 t#stairs |> Option.map(c -> (c#x, c#y)))))

    /// 味方の動的値（HP/level/exp/facing/stats/装備/指輪）が round-trip で保たれる。
    @Test
    def testRoundTripPlayer(): Unit \ Assert =
        let decoded = FloorSnapshotCodec.decode(FloorSnapshotCodec.encode(sample()));
        Assert.assertEq(
            expected = Some((22, 3, 45, "Down", 24, 14, true, Some(("iron_sword", 45)))),
            decoded
                |> Option.flatMap(t -> List.head(t#players))
                |> Option.map(p ->
                    (p#hp, p#level, p#exp, Staff.directionToString(p#facing),
                     p#stats#hp, p#stats#speed, p#ringEquipped,
                     List.head(p#weapons) |> Option.map(w -> (w#id, w#durability)))))

    /// 味方の statuses（種別・magnitude・remaining）が round-trip で保たれる。
    @Test
    def testRoundTripPlayerStatus(): Unit \ Assert =
        let decoded = FloorSnapshotCodec.decode(FloorSnapshotCodec.encode(sample()));
        Assert.assertEq(
            expected = Some(("SpdDown", 3, 2)),
            decoded
                |> Option.flatMap(t -> List.head(t#players))
                |> Option.flatMap(p -> List.head(p#statuses))
                |> Option.map(s -> (StatusSystem.effectToString(s#effect), s#magnitude, s#remaining)))

    /// 敵の動的値（HP/moduleIdx/alerted/weapon(Some)/ring(None)/status）が round-trip で保たれる。
    @Test
    def testRoundTripEnemy(): Unit \ Assert =
        let decoded = FloorSnapshotCodec.decode(FloorSnapshotCodec.encode(sample()));
        Assert.assertEq(
            expected = Some((8, 2, true, Some(("iron_axe", 30)), (None: Option[String]), "Immobilized")),
            decoded
                |> Option.flatMap(t -> List.head(t#enemies))
                |> Option.map(e ->
                    (e#hp, e#moduleIdx, e#alerted,
                     e#weapon |> Option.map(w -> (w#id, w#durability)),
                     e#ring,
                     List.head(e#statuses) |> Option.map(s -> StatusSystem.effectToString(s#effect))
                        |> Option.getWithDefault("?"))))

    /// Plan の sideConnections（SideRef の moduleIndex / DoorSide）が round-trip で保たれる。
    @Test
    def testRoundTripPlanSideConnection(): Unit \ Assert =
        let decoded = FloorSnapshotCodec.decode(FloorSnapshotCodec.encode(sample()));
        Assert.assertEq(
            expected = Some((0, "Right", 1, "Left")),
            decoded
                |> Option.flatMap(t -> List.head(t#mapPlan#sideConnections))
                |> Option.map(c ->
                    (c#a#moduleIndex, DungeonComposer.doorSideToString(c#a#side),
                     c#b#moduleIndex, DungeonComposer.doorSideToString(c#b#side))))

    /// 空 object（必須キー欠落）は `None`（壊れた save が安全に「中断データ無し」へ倒れる）。
    /// `T` は構造的レコード型で ToString/Eq を持たないため Bool（isEmpty）に射影して検証する。
    @Test
    def testDecodeMissingKeysIsNone(): Unit \ Assert =
        Assert.assertEq(
            expected = true,
            Option.isEmpty(FloorSnapshotCodec.decode(Util.Json.Json.JObject(Map.empty()))))

    /// object でない JSON（型不一致）も `None`。
    @Test
    def testDecodeNonObjectIsNone(): Unit \ Assert =
        Assert.assertEq(
            expected = true,
            Option.isEmpty(FloorSnapshotCodec.decode(Util.Json.Json.JString("nope"))))

    /// `Staff.Direction` の文字列 round-trip（全 4 方位）。
    @Test
    def testDirectionRoundTrip(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true),
            (Staff.parseDirection(Staff.directionToString(Direction.Up))    == Ok(Direction.Up),
             Staff.parseDirection(Staff.directionToString(Direction.Down))  == Ok(Direction.Down),
             Staff.parseDirection(Staff.directionToString(Direction.Left))  == Ok(Direction.Left),
             Staff.parseDirection(Staff.directionToString(Direction.Right)) == Ok(Direction.Right)))

    /// `StatusSystem.StatusEffect` の文字列 round-trip（全 6 種別）。
    @Test
    def testStatusEffectRoundTrip(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true, true, true),
            (StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.HitDown))     == Ok(StatusEffect.HitDown),
             StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.SpdDown))     == Ok(StatusEffect.SpdDown),
             StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.AtkUp))       == Ok(StatusEffect.AtkUp),
             StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.SpdUp))       == Ok(StatusEffect.SpdUp),
             StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.DefDown))     == Ok(StatusEffect.DefDown),
             StatusSystem.parseEffect(StatusSystem.effectToString(StatusEffect.Immobilized)) == Ok(StatusEffect.Immobilized)))

    /// `SuspendSave` の round-trip（consumed フラグ + snapshot を Saveable instance 経由で）。
    @Test
    def testSuspendSaveRoundTrip(): Unit \ Assert =
        let save = SuspendSave.make(false, sample());
        let decoded: Option[SuspendSave.Save] = Saveable.fromJson(Saveable.toJson(save));
        Assert.assertEq(
            expected = Some((false, "f01")),
            decoded |> Option.map(s -> (SuspendSave.consumedOf(s), SuspendSave.snapshotOf(s)#floorId)))

    /// `SuspendSave` の consumed=true も round-trip で保たれる（使用済みフラグがディスク往復で
    /// 落ちて再び再開可能（save-scum）にならないことの回帰防止）。
    @Test
    def testSuspendSaveConsumedRoundTrip(): Unit \ Assert =
        let save = SuspendSave.make(true, sample());
        let decoded: Option[SuspendSave.Save] = Saveable.fromJson(Saveable.toJson(save));
        Assert.assertEq(
            expected = Some(true),
            decoded |> Option.map(s -> SuspendSave.consumedOf(s)))

    /// `resumable`: 未使用なら Some(snapshot)、使用済み / 不在なら None。
    @Test
    def testResumableConsumedRules(): Unit \ Assert =
        let fresh    = Some(SuspendSave.make(false, sample()));
        let consumed = Some(SuspendSave.make(true,  sample()));
        // 未使用のみ Some（= 再開可）。使用済み / 不在は None（= 再開不可）。
        Assert.assertEq(
            expected = (false, true, true),
            (Option.isEmpty(SuspendSave.resumable(fresh)),
             Option.isEmpty(SuspendSave.resumable(consumed)),
             Option.isEmpty(SuspendSave.resumable(None))))
}
