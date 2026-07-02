/// PlayerScene — 複数プレイヤー（Marker2D + 子 Sprite2D）の集まり
///
/// FE 風 SRPG の「3 人パーティ」を表現する。EnemyScene と同じ流儀で、
/// 各プレイヤーをトップレベルの "Player_<id>" ノードとして並べて管理する。
///
/// ノード構造（プレイヤー 1 体あたり）:
///   Player_<id> (Marker2D, NodeTag.Player(Data))
///     └─ Sprite (Sprite2D, character_sheet)
///
/// Camera は CameraScene が独立した最上位ノードとして管理し、毎フレーム
/// 「選択中プレイヤー」の位置に追従させる（PlayerScene 自身は Camera を持たない）。
///
/// ターン進行:
///   - PlayerCursor で Z 押下 → カーソル位置の **アクティブな** プレイヤーを選択
///     （`SelectedPlayer.State.put(Some(id))` ＋ `PlayerMoving` へ遷移）
///   - PlayerMoving で WASD → 選択中プレイヤーが移動
///   - PlayerAttack で Z（敵に） / X（スキップ） → 選択中プレイヤーを `waited = true`
///   - 全員 waited なら敵ターン、まだ残っていれば PlayerCursor で次セレクトへ
///
/// `waited = true` のプレイヤーは:
///   - 灰色 modulate で表示される
///   - PlayerCursor で選択不可（Z で反応しない）
///
/// 移動は moveTo(id, target) で論理位置（gridPos）を即更新し、
/// 見た目は engine 層の `Tween` モジュールに委ねる。**壁・他駒の判定は
/// 呼び出し側（Board / MoveRangeScene）が moveTo を呼ぶ前に済ませている前提**。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    // Data / Spawn は PlayerData の型エイリアス。既存の呼び出し元は PlayerScene.Data / PlayerScene.Spawn
    // のまま参照できる（PlayerData.ItemKind は enum のため型エイリアスで再 export できない点に注意）。
    pub type alias Data = PlayerData.Data
    pub type alias Spawn = PlayerData.Spawn

    /// この味方の戦闘ビュー（faction 非依存）。装備武器は `weapons` の先頭。
    /// `Combat.estimate` / `Encounter` の join で使う（ダメージ式は `Combat` に集約）。
    pub def combatView(data: Data): Combat.CombatView =
        Combat.assembleView({
            base   = Combat.baseStatsFrom(data#resource),
            mods   = StatusSystem.combatMods(data#statuses),
            ring   = equippedRingBonus(data),
            hp     = data#hp,
            weapon = equippedWeaponView(data)})

    /// この味方の装備武器（先頭 = 装備中）の戦闘投影。`combatView` と World read-model 構築
    /// （`World.syncFromScene`）が共有し、proficiency 解決の二重実装を避ける。武器なしは None。
    pub def equippedWeaponView(data: Data): Option[Combat.WeaponView] =
        let equipped = PlayerData.equippedWeapon(data#weapons);
        Combat.weaponView(equipped, weaponProficient(data, equipped))

    /// この味方の装備指輪ボーナス。`combatView` と World read-model 構築が共有する。
    /// `ringEquipped` が false なら zeroBonuses（`PlayerData.equippedRing` が None を返す）。
    pub def equippedRingBonus(data: Data): Ring.Bonuses =
        Ring.bonuses(PlayerData.equippedRing(data))

    /// `combatView` の「装備武器を明示指定する」版。攻撃中に選択した武器（装備中=先頭とは
    /// 限らない）で戦闘予測を計算するため、`BattlePanelScene` から使う。
    pub def combatViewWith(data: Data, weapon: UnitCatalog.WeaponResource): Combat.CombatView =
        Combat.assembleView({
            base   = Combat.baseStatsFrom(data#resource),
            mods   = StatusSystem.combatMods(data#statuses),
            ring   = equippedRingBonus(data),
            hp     = data#hp,
            weapon = Combat.weaponView(Some(weapon),
                        UnitCatalog.proficientWith(data#resource, weapon#weaponType))})

    /// この味方が指定の装備武器（Option）を得意とするか。武器なしは true（estimate が None を扱う）。
    def weaponProficient(data: Data, weapon: Option[UnitCatalog.WeaponResource]): Bool =
        match weapon {
            case None    => true
            case Some(w) => UnitCatalog.proficientWith(data#resource, w#weaponType)
        }

    /// この味方の盤上ビュー（faction = Player）。`Encounter.fromScene` の join で使う。
    /// `weaponRange` は装備武器(先頭)の射程。味方に `isDying` は無いので常に false。
    pub def unitView(data: Data): UnitView =
        {id = data#id, faction = Faction.Player, pos = data#gridPos,
         hp = data#hp, moveTiles = effectiveMoveTilesOf(data),
         weaponRange = PlayerData.equippedWeapon(data#weapons) |> Option.map(w -> w#range),
         combat = combatView(data), isDying = false, hidden = data#hidden,
         // 味方は EnemyAI に渡らないので無害な固定値（型を埋めるためだけ）。
         aiType = EnemyAI.AiType.Aggressive}

    /// この味方の積載状態（重量制）。重量ゲージ UI・実効移動力・拾得判定が共用する単一の入口。
    /// 力は素の `resource#attack`（バフ・指輪を含まない物理特性）、体格は `resource#constitution`。
    pub def loadOf(data: Data): Encumbrance.Load =
        Encumbrance.loadOf(data#resource#constitution, data#resource#attack, data)

    /// 積載ペナルティ込みの実効移動力。素の `moveTiles` に積載率ペナルティ（80%/100%/110%）を掛けた値。
    /// getMoveTiles / unitView / PlayerMovementDriver / StairsExitDriver はすべてこの 1 関数を通すこと
    /// （範囲計算と歩数判定の不整合を防ぐため）。
    pub def effectiveMoveTilesOf(data: Data): Int32 =
        Encumbrance.effectiveMoveTiles(data#moveTiles, loadOf(data))

    /// 持ち物の指定スロット（`ItemKind`）にあるアイテム 1 個の重量。範囲外なら None。
    /// 交換のまとめ渡しが「この 1 個を渡すと受け手が重量過多になるか」を測るのに使う。
    pub def heldItemWeight(data: Data, kind: PlayerData.ItemKind): Option[Float64] = match kind {
        case PlayerData.ItemKind.Weapon(i)     =>
            List.nth(i, data#weapons)     |> Option.map(Encumbrance.weaponWeight)
        case PlayerData.ItemKind.Staff(i)      =>
            List.nth(i, data#staves)      |> Option.map(Encumbrance.staffWeight)
        case PlayerData.ItemKind.Consumable(i) =>
            List.nth(i, data#consumables) |> Option.map(Encumbrance.consumableWeight)
        case PlayerData.ItemKind.Ring(i)       =>
            List.nth(i, data#rings)       |> Option.map(Encumbrance.ringWeight)
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// ロード（主人公）として扱うパーティ id。集合での追従・カメラ追従の中心であり、
    /// このユニットが倒れると 1F からやり直し（ゲームオーバー扱い）になる。
    pub def lordId(): Int32 = 0

    /// この味方が床の宝箱を開けられるか。UnitResource の `canOpenChests`（ローグのみ true）を読む。
    /// 「駒の Data からクラス能力を引く」流儀。
    pub def canOpenChests(data: Data): Bool =
        data#resource#canOpenChests

    /// 味方 id の表示名（職業名 = `resource#description`）。ログ文言で使う。
    /// 見つからない場合は防御的に "味方" を返す（ログに id を出さない方針）。
    pub def displayName(id: Int32, scene: Scene[NodeTag]): String =
        get(id, scene) |> Option.map(d -> d#resource#description) |> Option.getWithDefault("味方")

    /// 持ち物が「もうこれ以上持てない」状態か（重量制）。個数上限は撤廃したので、
    /// 既に重量過多（積載 110%+ ＝ 移動不可）かどうかで判定する。
    /// 拾う対象が分かる場面では、より精密な `wouldOverloadByPicking` を使うこと。
    pub def isInventoryFull(data: Data): Bool =
        loadOf(data)#tier == Encumbrance.Tier.Immobile

    /// この床アイテムを拾うと重量過多（積載 110%+）になるか。なるなら拾わせない（詰み防止）。
    pub def wouldOverloadByPicking(data: Data, item: ItemData.GroundItemKind): Bool =
        Encumbrance.wouldExceedImmobile(loadOf(data), Encumbrance.groundItemWeight(item))

    /// プレイヤー Sprite の zIndex（Player は前面に立つ）。EnemyScene と同じ 10。
    pub def spriteZIndex(): Int32 = 10  // renderUnits が使うため pub

    /// 手動移動（PlayerMoving）・集合の主人公移動と味方追従（GatherMove）の 1 マス時間（≈ 0.167 秒）。
    /// 落ち着いて移動先を狙えるよう少しゆっくり（20 フレーム = 約 0.167 秒）にする。
    /// pub: 打ち手層（PlayerMovementDriver）が手動移動 / 追従 step で moveToById に渡す。
    pub def selectedSlideDuration(): Duration.Duration =
        Duration.frames(count = 20, fps = 120)

    /// `waited = true` 時の sprite modulate（薄い灰色）。
    /// CanvasItem.setModulate で sprite の RGB を乗算する。
    def waitedColor(): Color = UITheme.dimmed()

    /// `waited = false` 時の sprite modulate（白 = 元色）。
    def activeColor(): Color = UITheme.white()

    /// AnimatedSprite2D の「待機」アニメ名。spriteFrames には必ずこれが定義されている前提。
    def idleAnimName(): String = "idle"

    /// `walk_<direction>` アニメ名。spriteFrames に方向別 4 アニメを設定する前提。
    /// 未定義のアニメ名を渡すと AnimatedSprite2D は表示が止まる (anim 切り替え失敗) ので、
    /// 命名は spriteFrames 側 (units.json) と必ず揃える。
    def walkAnimName(dir: Staff.Direction): String = match dir {
        case Staff.Direction.Up    => "walk_up"
        case Staff.Direction.Down  => "walk_down"
        case Staff.Direction.Left  => "walk_left"
        case Staff.Direction.Right => "walk_right"
    }

    /// "Player_2" のようなノード名（World の直接の子）。
    pub def playerName(id: Int32): String = "Player_${id}"

    /// Player_<id> の NodePath。Y-sort root の World 配下にぶら下げるため
    /// "World/Player_<id>" の 2 段構造。Tween / GlobalPosition 等の API はこの helper
    /// 経由で呼ぶこと（直書きしない）
    pub def playerPath(id: Int32): NodePath =
        List.append(MapScene.worldPath(), playerName(id) :: Nil)

    /// Player_<id> の子 Sprite ノードへのパス。modulate 変更や将来の alpha tween に使う。
    pub def spritePath(id: Int32): NodePath =
        List.append(playerPath(id), "Sprite" :: Nil)

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene が登録済みの scene に出撃メンバーを追加する。
    /// 出撃メンバーは `PartySelection.State` に保持された選抜結果を使う。**未選抜のときだけ**
    /// `players` プールから「先頭（ロード）固定 + 残りからランダム 2 体」を抽選して保存し、
    /// 以降の build（フロア移動など）は同じメンバーを再利用する（＝シャッフルは開始時のみ）。
    /// `selectParty` 参照。フレッシュに組み直したい経路（ゲームオーバー / クリア周回）は
    /// 呼び出し側が `PartySelection.State.clear()` してから build する。
    /// 先頭は MapScene が記録した spawnGrid に、残りはその近傍の床セルに配置する。
    /// 各プレイヤーの `initialInventory` を kind 別に分割して `Data.weapons` / `Data.staves` に
    /// 詰め直す（weapons.head が装備中、staves は配列順で持ち物に積まれる）。未定義 id は
    /// 起動時 typo として即 panic する。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                  staffCatalog: Staff.StaffCatalog,
                  consumableCatalog: Consumable.ConsumableCatalog,
                  scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, PartySelection.State, World.Command} =
        let selected     = match PartySelection.State.get() {
            case Some(party) => party
            case None        =>
                let rolled = selectParty(UnitCatalog.pool("players", catalog));
                PartySelection.State.put(rolled);
                rolled
        };
        let n            = List.length(selected);
        let spawnGrid    = MapScene.getSpawnGrid(scene);
        let layer        = MapScene.getMapLayer(scene);
        let cells        = pickPlayerSpawns(spawnGrid, n, layer);
        // cells が n に満たない場合（極端に狭い anchor）は重複セルを許容して埋める
        let padded       = Board.padCells(cells, spawnGrid, n);
        let spawns: List[Spawn] = padded
            |> List.mapWithIndex(id -> c ->
                let (classId, res) = match List.nth(id, selected) {
                    case Some(pair) => pair
                    case None       => bug!("PlayerScene.add: party index ${id} out of range")
                };
                let split = splitInventory(res#initialInventory, catalog,
                                            staffCatalog, consumableCatalog);
                ({id = id, classId = classId, gridPos = c, resource = res,
                   weapons = split#weapons, staves = split#staves,
                   consumables = split#consumables, rings = Nil}: Spawn));
        List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), scene, spawns)

    /// 出撃メンバーを選抜する: **先頭（ロード）を固定**し、残りからランダムに 2 体選ぶ。
    /// プールが空なら空、ロードのみ（残り 0）ならロード 1 体、残りが 1 体ならロード + その 1 体。
    /// 並びは「ロードが先頭、続いて抽選された順」になる（先頭 = spawnGrid に配置されるため固定）。
    /// pub: 抽選プロパティ（ロード固定・件数・重複なし・部分集合）をテストから直接検証するため。
    pub def selectParty(party: List[a]): List[a] \ Math.Random =
        match party {
            case Nil          => Nil
            case lord :: rest => lord :: sampleN(2, rest)
        }

    /// `xs` から distinct な最大 k 件をランダムに取り出す（k >= 件数なら全件、順不同）。
    def sampleN(k: Int32, xs: List[a]): List[a] \ Math.Random =
        if (k <= 0 or List.isEmpty(xs))
            Nil
        else
            let i = randomIndex(List.length(xs));
            match List.nth(i, xs) {
                case None    => Nil  // 到達しない（i < length のため）
                case Some(x) => x :: sampleN(k - 1, removeNth(i, xs))
            }

    /// `[0, n)` の一様乱数インデックス（n > 0 前提）。
    def randomIndex(n: Int32): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * Int32.toFloat64(n)))

    /// `xs` から i 番目（0 始まり）の要素を取り除いたリストを返す。
    def removeNth(i: Int32, xs: List[a]): List[a] =
        match xs {
            case Nil    => Nil
            case h :: t => if (i == 0) t else h :: removeNth(i - 1, t)
        }

    /// `initialInventory` を kind 別に振り分けて weapons / staves リストに展開する。
    /// 各 kind の中での出現順を保つので、weapons.head が装備中の武器になる。
    /// 未定義 id は `lookupWeapon` / `Staff.lookup` で panic（起動時 typo の検知）。
    def splitInventory(inv: List[UnitBase.InventoryEntry],
                        catalog: UnitCatalog.UnitCatalog,
                        staffCatalog: Staff.StaffCatalog,
                        consumableCatalog: Consumable.ConsumableCatalog):
            {weapons     = List[UnitCatalog.WeaponResource],
              staves      = List[Staff.StaffResource],
              consumables = List[Consumable.ConsumableResource]} =
        let init: {weapons     = List[UnitCatalog.WeaponResource],
                    staves      = List[Staff.StaffResource],
                    consumables = List[Consumable.ConsumableResource]} =
            {weapons = Nil, staves = Nil, consumables = Nil};
        let acc = List.foldLeft((soFar, entry) -> {
            match entry#kind {
                case UnitBase.ItemKind.Weapon =>
                    let w = UnitCatalog.lookupWeapon(entry#id, catalog);
                    {weapons = List.append(soFar#weapons, w :: Nil),
                      staves  = soFar#staves, consumables = soFar#consumables}
                case UnitBase.ItemKind.Staff =>
                    let s = Staff.lookup(entry#id, staffCatalog);
                    {weapons = soFar#weapons,
                      staves  = List.append(soFar#staves, s :: Nil),
                      consumables = soFar#consumables}
                case UnitBase.ItemKind.Consumable =>
                    let c = Consumable.lookup(entry#id, consumableCatalog);
                    {weapons = soFar#weapons, staves = soFar#staves,
                      consumables = List.append(soFar#consumables, c :: Nil)}
            }
        }, init, inv);
        acc

    /// spawnGrid を中心に N 個の床セルを近い順で選ぶ。`isFloor` で篩い、
    /// 候補不足の場合は呼び出し側が `padCells` で埋める。
    def pickPlayerSpawns(origin: {x = Int32, y = Int32}, n: Int32,
                          layer: TileMapLayer): List[{x = Int32, y = Int32}] =
        let offsets =
                  ({x =  0, y =  0}: {x = Int32, y = Int32})
            ::    ({x =  1, y =  0}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  0}: {x = Int32, y = Int32})
            ::    ({x =  0, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  0, y = -1}: {x = Int32, y = Int32})
            ::    ({x =  1, y =  1}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  1, y = -1}: {x = Int32, y = Int32})
            ::    ({x = -1, y = -1}: {x = Int32, y = Int32})
            ::    Nil;
        offsets
            |> List.map(o -> ({x = origin#x + o#x, y = origin#y + o#y}: {x = Int32, y = Int32}))
            |> List.filter(c -> TileMapLayer.isFloor(c, layer))
            |> Board.dedupCells
            |> List.take(n)

    /// プレイヤー 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    /// ステータス・テクスチャ・フレームは `sp#resource`（UnitResource）から取る。
    /// pub: テストから catalog 経由の Spawn 構築 → 配置経路を直接検証するため公開する。
    pub def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // spawn/restore の funnel。新規ユニットの初期位置を World へ seed（Cmd.Move=位置 insert）。
        World.Command.emit(World.Cmd.Move(World.refOf(true, sp#id), sp#gridPos));
        // 初期 hp も World へ seed する。
        World.Command.emit(World.Cmd.SetHp(World.refOf(true, sp#id), sp#resource#hp));
        // 初期 followUpUsed=false も seed する。
        World.Command.emit(World.Cmd.SetFollowUpUsed(World.refOf(true, sp#id), false));
        // 初期 waited=false も seed する。
        World.Command.emit(World.Cmd.SetWaited(World.refOf(true, sp#id), false));
        // 初期 usedStairs=false も seed する（floor 遷移で scene reset しても World が
        // stale な true を保持しないように）。
        World.Command.emit(World.Cmd.SetUsedStairs(World.refOf(true, sp#id), false));
        // 初期 (level, exp=0) を seed する。
        World.Command.emit(World.Cmd.SetProgress(World.refOf(true, sp#id), sp#resource#level, 0));
        // 初期 weapons も World へ seed する。
        World.Command.emit(World.Cmd.SetWeapons(World.refOf(true, sp#id), sp#weapons));
        // 初期 baseStats も World へ seed する。
        World.Command.emit(World.Cmd.SetBaseStats(World.refOf(true, sp#id), Combat.baseStatsFrom(sp#resource)));
        // 初期 moveTiles も seed する（base＝resource 由来で以後不変）。
        World.Command.emit(World.Cmd.SetMoveTiles(World.refOf(true, sp#id), sp#resource#moveTiles));
        // 初期 staves/consumables/rings/ringEquipped も seed する。ringEquipped は spawn 時 false。
        World.Command.emit(World.Cmd.SetStaves(World.refOf(true, sp#id), sp#staves));
        World.Command.emit(World.Cmd.SetConsumables(World.refOf(true, sp#id), sp#consumables));
        World.Command.emit(World.Cmd.SetRings(World.refOf(true, sp#id), sp#rings));
        World.Command.emit(World.Cmd.SetRingEquipped(World.refOf(true, sp#id), false));
        let pos = MapSnapshot.cellCenter(sp#gridPos);
        let marker = Marker2D.make(pos);
        let res    = sp#resource;
        let data: Data = {
            id                = sp#id,
            classId           = sp#classId,
            gridPos           = sp#gridPos,
            moveTiles         = res#moveTiles,
            hp                = res#hp,
            waited            = false,
            attackTargetId    = None,
            resource          = res,
            weapons           = sp#weapons,
            staves            = sp#staves,
            consumables       = sp#consumables,
            selectedItem      = None,
            moveStepsTaken    = 0,
            facing            = Staff.Direction.Down,
            hidden            = false,
            usedStairs        = false,
            level             = res#level,
            exp               = 0,
            pendingLevelUp    = None,
            statuses          = Nil,
            rings             = sp#rings,
            ringEquipped      = false,
            followUpUsed      = false
        };
        // id 集合/team への登録（spawn funnel の一部）。
        World.Command.emit(World.Cmd.Spawn(World.EntityRef.Player(sp#id)));
        // 成長 read-model も spawn で seed する（resource 変化サイトは emitBaseStatsFromScene が束ねて emit）。
        World.Command.emit(World.Cmd.SetGrowth(sp#id,
            {base = LevelSystem.statsOf(res), rates = res#growthRates, name = res#description}));
        // 初期 weaponView/ringBonus も World へ seed する（weapons/rings と同源）。
        // data 構築後に emit（equippedWeaponView/equippedRingBonus は full Data を要する）。ringEquipped=false ゆえ ringBonus=zeroBonuses。
        World.Command.emit(World.Cmd.SetWeaponView(World.refOf(true, sp#id), equippedWeaponView(data)));
        World.Command.emit(World.Cmd.SetRingBonus(World.refOf(true, sp#id), equippedRingBonus(data)));
        // 子 Sprite ノードは廃止。AnimatedSprite2D 個体は初期アニメ（idle）を unitAnim store へ
        // seed し（コマ送りは stepWorld の elapsed 加算＋描画時の frame 導出）、静止 Sprite2D 個体は
        // resource の定数 frame を描画時に読むだけ＝store 不要。描画は RenderWorld.renderUnits が
        // resource + unitAnim/unitFlipH/unitModulate store から Sprite2D 値を直組みする。
        match res#spriteFrames {
            case Some(_) => World.Command.emit(World.Cmd.SetAnim(World.EntityRef.Player(sp#id), idleAnimName()))
            case None    => ()
        };
        scene
            |> Scene.addChildAt(MapScene.worldPath(), playerName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))

    // ────────────────────────────────────────────────────────
    // (D) ロジック — 移動
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（Board）が済ませている前提**。
    /// gridPos を即更新し、見た目は Tween に委ねる。`slide` は 1 マス分のスライド時間で、
    /// 呼び出し側がスピードを決める（手動移動・追従は少しゆっくり）。
    pub def moveTo(id: Int32, map: MapSnapshot, target: {x = Int32, y = Int32},
                    marker: Marker2D, data: Data, slide: Duration.Duration,
                    scene: Scene[NodeTag]): (Marker2D, Data)
                    \ {World.Command, World.WorldQuery} =
        let targetWorld = MapSnapshot.gridToWorld(target, map);
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        // 描画位置 tween は World（renderPos）権威＝engine `Tween.tweenPosition` は退役。
        // faction-blind な moveUnit に統一（敵も同じ口）。duration は秒（slide 同値）。
        World.moveUnit(World.EntityRef.Player(id), {start = startWorld, target = targetWorld}, Duration.toSeconds(slide));
        // 進行方向を facing に反映し、AnimatedSprite2D なら walk_<dir> 再生 (副作用)。
        // sprite ノード書き換えは moveToById 側でやる (moveTo は state を返すだけ)。
        // 移動前位置は World.posOf（Cmd.Move の emit **前**なので pre-move）。scene twin は退役。
        let pre = World.posOf(World.EntityRef.Player(id), World.WorldQuery.get())
                      |> Option.getWithDefault(data#gridPos);
        let nextFacing = directionOfStep(pre, target)
                            |> Option.getWithDefault(data#facing);
        World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target));
        (marker, {gridPos = target, facing = nextFacing | data})

    /// 指定 id のプレイヤーが現在移動（Position tween）中＝次の入力を受け付けない状態か。
    /// 移動中判定は World（renderPos tween）権威で、`World.isAnimating` が World の Position tween を見る。
    /// 1 フレーム 1 歩のリズムは維持する。
    pub def isMoving(id: Int32): Bool \ World.WorldQuery =
        World.isAnimating(World.EntityRef.Player(id), World.WorldQuery.get())

    /// 指定 id のプレイヤーを `target` グリッドへ Tween で移動させ、scene の Data も
    /// 同時に更新する。`moveTo` は (Marker2D, Data) を返す形だが、こちらは
    /// physicsProcess の外（AutoMove など）から id だけで呼べるように scene を直接編集する。
    /// `EnemyScene.moveTo` と同じインターフェース。**歩行可否は呼び出し側が確認済み前提**。
    pub def moveToById(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot, slide: Duration.Duration,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        // 1 歩移動を sim 書き込みと view 再生に分離する。
        // ── SYSTEM(sim): 位置の唯一権威。`Cmd.Move` が World に書く（gridPos は World 権威で
        //    scene へ直書きしない）。
        World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target));
        // ── VIEW(replay): Tween/facing/walk-anim はこの move から導出する純粋な見た目再生。
        //    `SimEvent.Moved` の消費側からも呼ぶ（イベント駆動の再生）。
        replayMoveView(id, target, map, slide, scene)

    /// `SimEvent.Moved` を view 再生する（イベント駆動の再生エントリ）。
    /// System が返した Moved を受けて Tween/facing/anim を再生する。位置の権威は World 側。
    /// 敵の move 再生は別途扱うため現状は no-op。
    pub def replayMovedEvent(event: World.SimEvent, map: MapSnapshot,
                              slide: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        match event {
            case World.SimEvent.Moved(World.EntityRef.Player(id), target) =>
                replayMoveView(id, target, map, slide, scene)
            case World.SimEvent.Moved(World.EntityRef.Enemy(_), _) => scene
            // simevent-algebra: 拡張された非 Moved variant は move seam に来ない（production emitter 無し）。
            // 黙って no-op せず、move seam 専用 invariant 違反として loud に落とす。
            case _ => bug!("PlayerScene.replayMovedEvent: non-Moved event on move seam")
        }

    /// `SimEvent.Moved` の着地マス。着地時の自動取得など view 側が座標を要する箇所で使う。
    /// move seam 専用＝Moved 以外は渡らない（非 Moved は到達不能ガード）。
    pub def movedTarget(event: World.SimEvent): {x = Int32, y = Int32} =
        match event {
            case World.SimEvent.Moved(_, target) => target
            // move-seam only invariant: 非 Moved は到達不能。原点 {0,0} を捏造すると
            // (0,0) で誤って自動取得が走るため、座標を作らず loud に落とす。
            case _                               => bug!("PlayerScene.movedTarget: non-Moved event on move seam")
        }

    /// 1 歩移動の **view 再生**（Tween 滑走 + facing + walk アニメ + 左右反転）。
    /// 位置の権威は World（`Cmd.Move`）にあり、ここは「move が起きた」結果から導く見た目だけを担う。
    /// sim 書き込みを含まない（`World.Command` を要求しない）＝イベント再生の純 view エントリ。
    pub def replayMoveView(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot, slide: Duration.Duration,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        let targetWorld = MapSnapshot.gridToWorld(target, map);
        // 描画位置 tween は World（renderPos）が唯一の権威＝engine `Tween.tweenPosition` は退役。
        // marker は `RenderWorld.syncMarkers` が renderPos に合わせる（敵 `replayEnemyMoveView` と対称）。
        World.moveUnit(World.EntityRef.Player(id), {start = startWorld, target = targetWorld}, Duration.toSeconds(slide));
        // 直前のグリッド座標から target への 1 マス差で方向を決める。
        // 0 ベクトル (= 同じセル) の場合は既存の facing を保つ。
        // 移動前位置は World.prevPosOf（applyCmd の Move が旧位置を自動記録）。
        // World 未登録（テスト/spawn 過渡）のみ scene fallback。
        let prev      = World.prevPosOf(World.EntityRef.Player(id), World.WorldQuery.get())
                            |> Option.getWithDefault(getGridPos(id, scene));
        let dirOpt    = directionOfStep(prev, target);
        // facing（向き＝視覚状態）だけここで更新する。
        let withState = mapPlayer(id, d -> {
            facing  = Option.getWithDefault(d#facing, dirOpt) | d
        }, scene);
        // AnimatedSprite2D を持つ unit なら walk_<dir> アニメに切り替える。
        // 方向が決まらなければ (= 同セル移動) 切り替えなし。
        let visuals = match dirOpt {
            case None    => withState
            case Some(d) => playAnim(id, walkAnimName(d), withState)
        };
        // flipForFacing 付き (= 左向き絵) の駒は左右移動で水平反転する。
        if (flipsForFacing(id, scene)) applyFacingFlip(id, dirOpt, visuals) else visuals

    /// 指定 id のプレイヤーを `target` グリッドに **瞬間移動** で戻す。
    /// 進行中の Tween があればキャンセルし、Marker2D の world 位置と Data#gridPos を
    /// 同時に target に揃える。PlayerMoving 中のキャンセルで「選択時の位置」に戻すのに使う。
    pub def snapTo(id: Int32, target: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let world = MapSnapshot.cellCenter(target);
        // SetRenderPos が進行中の World 描画 tween を破棄しつつ renderPos を
        // target にスナップする（`World.flix` handler で tweens から Position を remove）＝中断後に marker が滑り残らない。
        World.Command.emit(World.Cmd.SetRenderPos(World.EntityRef.Player(id), world));
        World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target));
        // gridPos は World 権威。ここは Tween 実体（描画位置）の
        // 即時スナップだけ行う（snapTo は瞬間移動ゆえ Marker2D の world 座標も即合わせる）。
        scene
            |> Scene.setGlobalPositionAt(playerPath(id), world)

    /// PlayerCursor + Z で味方マスを選択した瞬間の遷移: 選択中味方を SelectedPlayer に
    /// 記録し、PlayerMoving に進む。
    /// overlay (MoveRange / MoveAttackRange / EnemyRange) と Cursor の整理は
    /// `PhaseTransitions.enterPlayerMoving` が担当する (この関数は SelectedPlayer 更新だけ)。
    pub def beginSelection(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, World.WorldQuery} =
        SelectedPlayer.State.put({
            id     = Some(playerId),
            // 移動開始。元位置を巻き戻しドラフトの底に積む（前の移動の残骸は drafts ごと破棄）
            // 巻き戻し origin は World.posOf（scene gridPos twin は退役＝stale）。
            drafts = MoveDraft.DraftAction.MovedFrom(playerId,
                World.posOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
                    |> Option.getWithDefault(getGridPos(playerId, scene))) :: Nil,
            gatherActive = false
        });
        PhaseTransitions.enterPlayerMoving(scene)

    /// 「集合」確定で集合（行軍）モードに入る。主人公(id 0)を選択駒に固定し、
    /// 主人公＋生存味方全員の現在位置を巻き戻しドラフト(MovedFrom)に **1 回だけ** 積む。
    /// これにより GatherMove 中に主人公が動き味方が追従しても、X / メニューの「キャンセル」で
    /// `cancelSelection` を呼べば全員が集合開始位置へ戻る（既存の巻き戻し機構を流用）。
    /// 追従の各 1 歩は `moveToById` で動かすだけでドラフトは積まない
    /// （積むと巻き戻しが多重適用され開始位置に戻らなくなる）。
    /// overlay / cursor は `PhaseTransitions.enterGatherMove` が担当する。
    pub def beginGather(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, World.WorldQuery} =
        // 巻き戻し origin は World 位置（scene gridPos twin は退役＝stale）。
        let origins = getAllWithWorldPos(scene)
            |> List.filter(d -> d#hp > 0)
            |> List.map(d -> MoveDraft.DraftAction.MovedFrom(d#id, d#gridPos));
        SelectedPlayer.State.put({id = Some(lordId()), drafts = origins, gatherActive = true});
        // 追従の移動距離カウントを 0 から始める（味方は自分の moveTiles 歩まで追従して非アクティブ化）。
        resetAllMoveStepsTaken(scene)
            |> PhaseTransitions.enterGatherMove

    /// PlayerMoving + X: 選択駒を origin に瞬間移動で戻し、選択解除して PlayerCursor に戻す。
    /// 「キャンセル → 再選択の繰り返しで実質ターン制限なしの自由移動」を防ぐ。
    /// overlay / cursor の片付けは `PhaseTransitions.enterPlayerCursor` が担当。
    pub def cancelSelection(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery, World.Command} =
        // この移動で積んだ可逆ドラフトを新しい順に巻き戻す（拾得→元位置への復帰など）。
        // 「拾ってからキャンセルしたら拾っていないことにする」もこの一括巻き戻しで実現。
        let drafts   = SelectedPlayer.State.get()#drafts;
        let restored = List.foldLeft((acc, a) -> revertDraftAction(a, acc), scene, drafts);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        PhaseTransitions.enterPlayerCursor(restored)

    /// 集合（行軍）モードで「まだ誰も開始位置から動いていない」か。
    /// 集合直後（手動確定 / ターン継続での自動再突入）に C で個別行動モードへ戻せるかの判定。
    /// `gatherActive` でなければ false。`beginGather` が積んだ各 `MovedFrom` 起点と現在位置を
    /// 比べ、1 体でも origin から動いていれば false（移動を始めたら切替不可）。
    pub def gatherNotMovedYet(scene: Scene[NodeTag]): Bool \ {SelectedPlayer.State, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        if (not sel#gatherActive) false
        else {
            // 現在位置は World 上書き Data（origin との一致比較）。
            let living = getAllWithWorldPos(scene) |> List.filter(d -> d#hp > 0);
            not MoveDraft.anyMovedFromOrigin(living, sel#drafts)
        }

    /// 移動ドラフト 1 件を巻き戻す。巻き戻しの実体はここに集約する
    /// （新しい可逆操作を足すときはこの match に 1 分岐追加するだけ）。
    ///   - `MovedFrom`: origin に snapTo で戻し、walk 表示を idle に戻す
    ///     （移動中の walk_<dir> のままだと「キャンセル後に動いてないのに横向き」になる）
    ///   - `PickedUp` : 床へ戻し（`GroundItems.respawn`）+ 在庫末尾の仮取得分を取り消す
    def revertDraftAction(action: MoveDraft.DraftAction,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ World.Command =
        match action {
            case MoveDraft.DraftAction.MovedFrom(id, cell)              =>
                snapTo(id, cell, scene) |> playAnim(id, idleAnimName())
            case MoveDraft.DraftAction.PickedUp(pid, cell, itemKey, kind) =>
                scene
                    |> GroundItems.respawn(cell, itemKey, kind)
                    |> removeLastInventoryItem(pid, kind)
            case MoveDraft.DraftAction.Equipped(pid, idx)               =>
                // 装備 = moveToHead(idx) の逆。先頭を idx 位置へ戻す。
                // scene #weapons を巻き戻したら World にも SetWeapons を dual-write する。
                // これを欠くと mid-move equip(idx>0)+cancel で World が装備後の並びを保持し
                // scene が元並びへ戻って両者が食い違う（equipWeapon と対称）。
                let reverted = mapPlayer(pid, d -> {weapons = moveHeadTo(idx, d#weapons) | d}, scene);
                emitWeaponsFromScene(pid, reverted);
                reverted
            case MoveDraft.DraftAction.Dropped(pid, kind, item)        =>
                // 捨てる = removeAt(idx) の逆。元 idx に挿入し直す。
                insertInventoryItem(pid, kind, item, scene)
            case MoveDraft.DraftAction.Traded(t)                       =>
                // こうかん = swapItem の逆。相手末尾の付加分を除去 → 双方の元 idx へ戻す。
                // (逆順 revert なので付加分は各リストの末尾に在る前提が成立する)
                let s1 = removeLastInventoryItem(t#partnerId, t#selfItem, scene);
                let s2 = insertInventoryItem(t#selfId, t#selfKind, t#selfItem, s1);
                match (t#partnerKind, t#partnerItem) {
                    case (Some(pk), Some(pi)) =>
                        let s3 = removeLastInventoryItem(t#selfId, pi, s2);
                        insertInventoryItem(t#partnerId, pk, pi, s3)
                    case _                    => s2
                }
            case MoveDraft.DraftAction.GatherWaited(id)                =>
                // 集合中の移動距離切れで非アクティブ化した味方を再アクティブに戻す。
                setActive(id, scene)
        }

    /// インベントリの先頭から、距離 `distance` に射程が届く最初の武器の index を返す。
    /// 届く武器が無ければ None。攻撃中の武器選択・進入時装備で共用する純粋関数。
    pub def firstWeaponIdxReaching(data: Data, distance: Int32): Option[Int32] =
        data#weapons
            |> List.zipWithIndex
            |> List.findMap(p -> match p {
                case (i, w) => if (Weapon.inRange(distance, w#range)) Some(i) else None
            })

    /// scene 内に攻撃モーション中のプレイヤーが居れば true。
    /// EnemyTurnDriver の「敵の行動を進めて良いか」のガードに使う
    /// （味方の反撃モーション中はキューを進めない）。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    // ────────────────────────────────────────────────────────
    // (E) 状態クエリ・更新
    // ────────────────────────────────────────────────────────

    /// scene に登録されている全プレイヤーの Data を id 昇順で返す。
    pub def getAll(scene: Scene[NodeTag]): List[Data] =
        Scene.preorderPaths(scene)
            |> List.filterMap(path -> match Scene.getState(path, scene) {
                case Some(NodeTag.Player(d)) => Some(d)
                case _                       => None
            })
            |> List.sortBy(d -> d#id)

    /// id を持つプレイヤーの Data を取り出す。未登録なら None。
    pub def get(id: Int32, scene: Scene[NodeTag]): Option[Data] =
        match Scene.getState(playerPath(id), scene) {
            case Some(NodeTag.Player(d)) => Some(d)
            case _                       => None
        }

    /// id を持つプレイヤーの Data を `f` で更新する。Marker2D 位置は触らない。
    pub def mapPlayer(id: Int32, f: Data -> Data,
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(d)) =>
                EngineNode.Marker2DWithState(marker, NodeTag.Player(f(d)))
            case other => other
        }, scene)

    /// hp 書込 funnel。scene の hp を更新しつつ World にも `Cmd.SetHp` で dual-write する。
    /// 純 hp 書込（回復/吸血/効果回復など）の置換先。複合書込（hp＋他 field）は呼び出し側で単独 emit する。
    pub def setHp(id: Int32, newHp: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(id), newHp));
        mapPlayer(id, d -> {hp = newHp | d}, scene)

    /// weapons 書込 funnel。`scene`（mutation 適用後）から該当 player の weapons を読み戻して
    /// `Cmd.SetWeapons` を World へ dual-write する（`emitHpAt` と同じ「適用後 scene を読んで emit」流儀）。
    /// 装備並べ替え/捨てる/拾う/並び替え/こうかん など全 weapons mutation funnel の末尾で呼ぶ。
    pub def emitWeaponsFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(playerId), getWeapons(playerId, scene)));
        // weaponView は装備武器由来＝weapons funnel と 1:1 で SetWeaponView も co-emit（網羅を構造保証）。
        emitWeaponViewFromScene(playerId, scene)

    /// weaponView 書込 funnel（`emitBaseStatsFromScene` 同型）。mutation 適用後の `scene` から該当 player の
    /// 装備武器投影を読み戻して `Cmd.SetWeaponView` を World へ dual-write する。`emitWeaponsFromScene` が内部で呼ぶほか、
    /// emitWeaponsFromScene を経由しない weapons 書込サイト（carry/CombatDriver 耐久消費）からも直接呼ぶ。pub。
    pub def emitWeaponViewFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        match get(playerId, scene) {
            case Some(d) => World.Command.emit(World.Cmd.SetWeaponView(World.EntityRef.Player(playerId), equippedWeaponView(d)))
            case None    => ()
        }

    /// ringBonus 書込 funnel（`emitWeaponViewFromScene` 同型）。mutation 適用後の `scene` から該当 player の
    /// 装備指輪ボーナスを読み戻して `Cmd.SetRingBonus` を World へ dual-write する。rings/ringEquipped funnel が内部で呼ぶ。pub。
    pub def emitRingBonusFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        match get(playerId, scene) {
            case Some(d) => World.Command.emit(World.Cmd.SetRingBonus(World.EntityRef.Player(playerId), equippedRingBonus(d)))
            case None    => ()
        }

    /// baseStats 書込 funnel。`scene`（resource mutation 適用後）から該当 player の resource を読み戻して
    /// `Cmd.SetBaseStats` を World へ dual-write する（`emitWeaponsFromScene` と同じ read-after-mutate 流儀）。
    /// level-up（CombatDriver）/carry 復元/snapshot 復元/復活など resource を書き換えた直後に呼ぶ。pub（CombatDriver から）。
    pub def emitBaseStatsFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        match get(playerId, scene) {
            case Some(d) =>
                World.Command.emit(World.Cmd.SetBaseStats(World.EntityRef.Player(playerId), Combat.baseStatsFrom(d#resource)));
                // resource が変わる全サイトで growth read-model も束ねて更新する。
                World.Command.emit(World.Cmd.SetGrowth(playerId,
                    {base = LevelSystem.statsOf(d#resource), rates = d#resource#growthRates, name = d#resource#description}))
            case None    => ()
        }

    /// statusEffects 書込 funnel（`emitBaseStatsFromScene` 同型）。mutation（add/clearImmobilized/bind/tick）
    /// 適用後の `scene` から該当 player の `#statuses` を読み戻して `Cmd.Seed`（全置換 replace 意味論）で World へ
    /// dual-write する。各操作を個別 Cmd に写さず変更後の全リストを Seed で置換＝網羅が単純化し漏れにくい。
    /// statuses を書く全サイトの末尾で呼ぶ（特にターン開始 tick）。pub（StaffCast/CombatDriver/EnemyScene 起点から）。
    pub def emitStatusesFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        match get(playerId, scene) {
            case Some(d) => World.Command.emit(World.Cmd.Seed(World.EntityRef.Player(playerId), d#statuses))
            case None    => ()
        }

    /// staves/consumables/rings/ringEquipped 書込 funnel（`emitWeaponsFromScene` 同型）。
    /// mutation 適用後の `scene` から該当 player の各インベントリを読み戻して Cmd を World へ dual-write する。
    /// `pub`（StaffCast の杖/瓶消費からも呼ぶ）。
    pub def emitStavesFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetStaves(World.EntityRef.Player(playerId), getStaves(playerId, scene)))
    pub def emitConsumablesFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetConsumables(World.EntityRef.Player(playerId), getConsumables(playerId, scene)))
    pub def emitRingsFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetRings(World.EntityRef.Player(playerId), getRings(playerId, scene)));
        // ringBonus は装備指輪由来＝rings funnel と 1:1 で SetRingBonus も co-emit。
        emitRingBonusFromScene(playerId, scene)
    pub def emitRingEquippedFromScene(playerId: Int32, scene: Scene[NodeTag]): Unit \ World.Command =
        let eq = get(playerId, scene) |> Option.map(d -> d#ringEquipped) |> Option.getWithDefault(false);
        World.Command.emit(World.Cmd.SetRingEquipped(World.EntityRef.Player(playerId), eq));
        // ringBonus は ringEquipped 切替でも変わる＝ringEquipped funnel とも 1:1 で SetRingBonus を co-emit。
        emitRingBonusFromScene(playerId, scene)

    /// 指定プレイヤーの上下左右 1 マスに居る他味方を返す（自分は含まない）。
    /// 「こうかん」コマンドや将来の隣接判定 (例: 助太刀) の出現条件として使う。
    /// 斜め (例: (4,4) と (5,5)) は含まない。waited フィルタはここではせず、
    /// 全味方を対象にする (waited 駒との交換可否は呼び出し側で判定)。
    pub def adjacentAllies(player: Data): List[Data] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.getAll()
            |> List.filter(other ->
                other#id != player#id
                and Weapon.manhattan(player#gridPos, other#gridPos) == 1)

    /// `startId` を含む「隣接（マンハッタン 1）で連結した味方」の id 集合を id 昇順で返す。
    /// 直接隣接だけでなくチェーン（A-B-C で B が A 経由でつながる）も同じ塊として拾う連結成分。
    /// 集合(Gather)の交換で「リーダーに隣接していなくても仲間同士が隣接していれば 3 人で交換」を
    /// 成立させるために使う。純粋（テスト対象）。`startId` が `members` に居なければ空。
    pub def tradeComponent(startId: Int32,
                            members: List[{id = Int32, gridPos = {x = Int32, y = Int32} | r}]):
            List[Int32] =
        if (not List.exists(m -> m#id == startId, members)) Nil
        else expandComponent(startId :: Nil, Set#{startId}, members) |> Set.toList |> List.sort

    /// 連結成分の BFS: frontier の各 id の「隣接かつ未訪問」メンバーを visited に足しながら畳む。
    def expandComponent(frontier: List[Int32], visited: Set[Int32],
                         members: List[{id = Int32, gridPos = {x = Int32, y = Int32} | r}]):
            Set[Int32] =
        match frontier {
            case Nil        => visited
            case id :: rest =>
                let fresh    = adjacentUnvisited(id, visited, members);
                let visited2 = List.foldLeft((s, nid) -> Set.insert(nid, s), visited, fresh);
                expandComponent(List.append(rest, fresh), visited2, members)
        }

    /// `id` にマンハッタン 1 で隣接する、まだ visited に居ないメンバーの id。
    def adjacentUnvisited(id: Int32, visited: Set[Int32],
                          members: List[{id = Int32, gridPos = {x = Int32, y = Int32} | r}]):
            List[Int32] =
        match posOfMember(id, members) {
            case None      => Nil
            case Some(pos) =>
                members
                    |> List.filter(m -> not Set.memberOf(m#id, visited)
                                        and Weapon.manhattan(pos, m#gridPos) == 1)
                    |> List.map(m -> m#id)
        }

    /// メンバー id の gridPos を引く（居なければ None）。
    def posOfMember(id: Int32,
                    members: List[{id = Int32, gridPos = {x = Int32, y = Int32} | r}]):
            Option[{x = Int32, y = Int32}] =
        members |> List.findMap(m -> if (m#id == id) Some(m#gridPos) else None)

    /// アクティブ（waited でない）味方のうち、id 最小のものを返す。誰も居なければ None。
    /// `commitWaitedAndAdvance` の直後にカーソルを次に動ける駒へ飛ばす用途で使う。
    /// waited は **World 直読み**（read-after-write でフレーム中の SetWaited も即時見える。
    /// scene の d#waited twin は退役し stale）。
    pub def firstActive(scene: Scene[NodeTag]): Option[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        getAll(scene)
            |> List.filter(d -> not (World.waitedOf(World.EntityRef.Player(d#id), w)
                                        |> Option.getWithDefault(false)))
            |> List.sortBy(d -> d#id)
            |> List.head

    /// `firstActive` の「`excludeId` を行動済み扱いにする」変種。
    /// waited を World 直読みにしたため「たった今 waited 化した駒」も store で即時 true になり
    /// 除外は冗長になったが、防御的に維持（呼び出し側 API 据置・二重に安全）。
    pub def firstActiveExcluding(excludeId: Option[Int32], scene: Scene[NodeTag]):
            Option[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        getAll(scene)
            |> List.filter(d -> not (World.waitedOf(World.EntityRef.Player(d#id), w)
                                        |> Option.getWithDefault(false))
                                and Some(d#id) != excludeId)
            |> List.sortBy(d -> d#id)
            |> List.head

    /// 主人公(lordId=0)が集合（行軍）を率いられる状態か。集合は `beginGather` が主人公を
    /// 選択駒に固定するので、主人公が戦闘不能(hp<=0) / 階段退場(hidden) / かなしばり(immobilized)
    /// のいずれかなら率いられない。集合のターン跨ぎ自動継続の前提チェックに使う。
    pub def lordReadyToGather(scene: Scene[NodeTag]): Bool \ World.WorldQuery =
        // hp は World 直読み（ECS 戦闘は scene hp を書かず scene twin は stale）。
        // hidden/statuses は scene 権威のまま。
        let w = World.WorldQuery.get();
        match get(lordId(), scene) {
            case Some(d) =>
                let hp = World.hpOf(World.EntityRef.Player(lordId()), w) |> Option.getWithDefault(d#hp);
                hp > 0 and not d#hidden and not StatusSystem.isImmobilized(d#statuses)
            case None    => false
        }

    /// 敵攻撃で HP=0 になったプレイヤーを scene から取り除く。`killed` は
    /// `CombatDriver.applyEnemyAttackHit` が返した死亡 id のリスト (通常 1 要素)。
    /// 選択中プレイヤーが含まれていれば (反撃で死亡したケース) 選択も解除する。
    /// 次のいずれかでゲームオーバー (`CustomEffects.GameOverRequest.request`) を emit し、
    /// handler 側でマップ・配置を 1F からフルリビルドする:
    ///   - 味方が全員脱落した
    ///   - ロード（主人公 = `lordId()`）が倒れた（他の味方が残っていても 1F やり直し）
    pub def removeDeadAndCheckGameOver(killed: List[Int32],
                                         scene: Scene[NodeTag]):
            Scene[NodeTag] \ {CustomEffects.GameOverRequest, SelectedPlayer.State,
                               GameLogger.GameLogger, World.Command, World.WorldQuery} =
        if (List.isEmpty(killed)) scene
        else {
            // ノード除去の前に、現在いる全味方の位置を記録する（女神の加護の「その場復活」用）。
            // 死亡する駒もこの時点ではまだ scene 上におり、最後の位置が取れる。handler 側で蓄積する。
            // 位置は World 上書き Data（scene gridPos twin は退役）。
            CustomEffects.GameOverRequest.markDeaths(
                getAllWithWorldPos(scene) |> List.map(d -> (d#id, d#gridPos)) |> List.toMap);
            // 蘇生薬(AutoRevive)を所持している脱落者は、scene から取り除く前に全回復して復活させる。
            // この時点ではまだ味方ノードが生きている（removeAt 前）ので consumables/最大HP を読める。
            // 復活した分は killed から外れ、ロード戦死や全滅もそのぶん回避される。
            let units = killed |> List.filterMap(id ->
                get(id, scene) |> Option.map(d -> {id = id, consumables = d#consumables}));
            let revive = Consumable.tryReviveAll(units);
            let revivedScene = List.foldLeft(
                (sc, r) -> reviveOne(r#id, r#consumables, sc), scene, revive#revived);
            let stillDead = revive#stillDead;
            if (List.isEmpty(stillDead)) revivedScene
            else {
                // ノード除去と対で World の全 store からも除去する。
                List.forEach(id -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Player(id))), stillDead);
                let removed = List.foldLeft(
                    (sc, id) -> Scene.removeAt(playerPath(id), sc),
                    revivedScene, stillDead);
                let selectedKilled = match SelectedPlayer.State.get()#id {
                    case Some(id) => List.exists(k -> k == id, stillDead)
                    case None     => false
                };
                if (selectedKilled)
                    SelectedPlayer.State.put(SelectedPlayer.cleared())
                else ();
                let lordDead = List.exists(k -> k == lordId(), stillDead);
                if (List.isEmpty(getAll(removed)) or lordDead)
                    CustomEffects.GameOverRequest.request(removed)
                else removed
            }
        }

    /// 蘇生薬で復活する味方 1 体の Scene 反映: HP を最大まで戻し、蘇生薬消費後の
    /// インベントリへ差し替え、HPBar 更新、復活ログを出す。`removeDeadAndCheckGameOver` 専用。
    def reviveOne(id: Int32, newConsumables: List[Consumable.ConsumableResource],
                   scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                let maxHp = d#resource#hp;
                World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(id), maxHp));  // 復活 hp を World へ
                GameLogger.playerLog("${displayName(id, scene)}は 蘇生薬で復活した");
                let revived = scene
                    |> mapPlayer(id, dd -> {hp = maxHp, consumables = newConsumables | dd});
                // hp と consumables を束ねた書込（蘇生薬消費）。consumables も World へ dual-write。
                emitConsumablesFromScene(id, revived);
                revived
        }

    /// プレイヤーを「行動済み」にして sprite を灰色 modulate にする。
    /// AnimatedSprite2D 持ち unit はここで idle アニメに戻す (= 待機モーション表示)。
    /// PlayerAttack 確定 / スキップ時に呼ばれる。
    pub def setWaited(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // waited は World 権威（Cmd.SetWaited が唯一の source）。scene への直書きは撤去した。
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), true));
        scene
            |> setSpriteModulate(id, waitedColor())
            |> playAnim(id, idleAnimName())

    /// プレイヤー 1 体を「行動可能(アクティブ)」に戻す。`waited` を下ろし、sprite/HP ゲージを
    /// 通常色へ、idle アニメへ戻す（`setWaited` の逆）。集合キャンセルの巻き戻しで使う。
    pub def setActive(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // waited は World 権威。scene 直書きは撤去した。
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), false));
        scene
            |> setSpriteModulate(id, activeColor())
            |> playAnim(id, idleAnimName())

    /// 完全停止（かなしばり）を解除する。被攻撃 or 被投擲の瞬間に呼ぶ。
    /// 停止していなければ no-op（他の時限ステータスは残す）。
    pub def releaseBind(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // mutation 後に読んで Seed で全置換（read-after-mutate の正しい流儀）。
        let cleared = mapPlayer(id, d -> {statuses = StatusSystem.clearImmobilized(d#statuses) | d}, scene);
        emitStatusesFromScene(id, cleared);
        cleared

    /// 全プレイヤーの waited をクリアし、sprite を白に戻す。
    /// ターン開始時に呼ばれ、AnimatedSprite2D 持ち unit は idle アニメに戻す
    /// (= 新ターン開始時の待機モーション)。
    /// 敵ターン終了後に呼ぶ（次の味方ターン開始）。
    pub def clearAllWaited(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameLogger.GameLogger, World.Command, PlayerData.PartyQuery} =
        // 階段で退場した味方 (usedStairs) は「行動済み」を維持し、敵ターン後も再行動させない。
        let ids = getAll(scene) |> List.filter(d -> not d#usedStairs) |> List.map(d -> d#id);
        // dual-write: 味方ターン開始 tick を World へ発行する（scene の inline tick も維持）。
        World.Command.emit(World.Cmd.TickPlayers(ids));
        let reset = List.foldLeft((sc, id) -> {
            World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(id), false));  // reset を World へ
            World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), false));  // ターン開始で waited 解除
            let sc1 = sc
                // 味方ターン開始ごとに時限ステータス（自己バフ等）を 1 ターン分減算する。
                // 追撃リングの二重発動フラグ(followUpUsed)は World 権威＝上の Cmd emit のみ（scene 直書き撤去）。
                |> mapPlayer(id, d -> {waited = false, statuses = StatusSystem.tick(d#statuses) | d})
                |> setSpriteModulate(id, activeColor())
                |> playAnim(id, idleAnimName());
            // 味方ターン開始 tick 後の statuses を per-entity で World へ Seed（tick 網羅の核心）。
            emitStatusesFromScene(id, sc1);
            sc1 },
            scene, ids);
        // 味方ターン開始時に、いやしのリングを装備した味方の HP を回復する。
        applyRingRegen(reset)

    /// いやしのリングを装備した味方の HP を回復する（最大 HP でクランプ）。味方ターン開始で呼ぶ。
    /// 実際に回復した味方はログに出す。
    pub def applyRingRegen(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, World.Command, PlayerData.PartyQuery} =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) -> regenOnePlayer(id, sc), scene, ids)

    /// 1 味方ぶんの Mend 回復。Mend 以外 / 未装備なら no-op（match は入れ子にしない）。
    /// 判定読み（装備指輪/hp）は PartyQuery（World オーバーレイ）経由。
    def regenOnePlayer(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, World.Command, PlayerData.PartyQuery} =
        match PlayerData.PartyQuery.get(id) {
            case None    => scene
            case Some(d) => mendOnePlayer(id, d, scene)
        }

    /// 回復量を計算して適用するヘルパー（regenOnePlayer から呼ぶ）。
    /// 満タン等で実際に HP が増えないときはログも出さない。
    def mendOnePlayer(id: Int32, d: Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        let amt = Ring.mendAmount(PlayerData.equippedRing(d));
        let newHp = Combat.heal(d#hp, d#resource#hp, amt)#newHp;
        if (amt <= 0 or newHp <= d#hp) scene
        else {
            GameLogger.playerLog("${d#resource#description} は いやしのリングで HP+${newHp - d#hp}");
            scene
                |> setHp(id, newHp)
        }

    /// 全プレイヤーの sprite / HP ゲージを通常色(active)に戻す。`waited` フラグは変えない。
    /// 敵フェーズ中に「味方の行動済み灰色」を消してアクティブに見せるために使う
    /// （待機しているという扱い自体は残し、見た目だけ通常色に戻す。階段で退場済みの味方は対象外）。
    pub def showAllActive(scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let ids = getAll(scene) |> List.filter(d -> not d#usedStairs) |> List.map(d -> d#id);
        List.foldLeft((sc, id) ->
            sc
                |> setSpriteModulate(id, activeColor()),
            scene, ids)

    /// AutoMove で消費した移動歩数を記録するための setter。
    pub def setMoveStepsTaken(id: Int32, steps: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(id, d -> {moveStepsTaken = steps | d}, scene)

    /// 全プレイヤーの moveStepsTaken を 0 にリセットする。
    /// プレイヤーターン開始時 / AutoMove キャンセル時に呼ぶ。
    pub def resetAllMoveStepsTaken(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) -> mapPlayer(id, d -> {moveStepsTaken = 0 | d}, sc),
                       scene, ids)

    // ────────────────────────────────────────────────────────
    // (E') 盤面からの一時退場 — 階段退場(useStairs)の表示制御
    // ────────────────────────────────────────────────────────

    /// 味方 id の表示/退避を切り替える。`flag = true` で Marker2D ごと不可視にして
    /// hidden を立てる(階段で退場して消える)。`flag = false` で元に戻す。
    /// 親 Marker2D を不可視にすると子 Sprite / HPBar も連動して消える(Godot の
    /// 親子可視性 AND。CursorScene.setVisible と同手法)。
    pub def setHidden(id: Int32, flag: Bool, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        // playerHidden store へ dual-write する。
        World.Command.emit(World.Cmd.SetHidden(World.EntityRef.Player(id), flag));
        Scene.mapEngineNode(playerPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(d)) =>
                EngineNode.Marker2DWithState(CanvasItem.setVisible(not flag, marker),
                                              NodeTag.Player({hidden = flag | d}))
            case other => other
        }, scene)

    /// 暗転色を World store（unitModulate）へ emit（sprite ノード撤去に伴い Cmd 化。
    /// 本体描画/HP バー/武器アイコンが同じ store を読む）。scene はパイプ素通し。
    def setSpriteModulate(id: Int32, color: Color,
                           scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetModulate(World.EntityRef.Player(id), color));
        scene

    /// 再生アニメを World store（unitAnim）へ emit（play 意味論は applyCmd が再現）。
    /// spriteFrames を持たない unit でも emit 自体は無害（描画側が resource を見て無視）。
    def playAnim(id: Int32, animName: String, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetAnim(World.EntityRef.Player(id), animName));
        scene

    /// 左右反転を World store（unitFlipH）へ emit。
    def setSpriteFlipH(id: Int32, h: Bool, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetFlipH(World.EntityRef.Player(id), h));
        scene

    /// 進行方向に応じて「左向きの絵」を水平反転する。Right で flipH=true (右向き)、
    /// Left で flipH=false (左向き=素材そのまま)。Up/Down/None は現状維持。
    /// `sprite#flipForFacing` を持たない駒では呼び出し側 (`flipsForFacing`) が抑止する。
    def applyFacingFlip(id: Int32, dirOpt: Option[Staff.Direction],
                         scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match dirOpt {
            case Some(Staff.Direction.Right) => setSpriteFlipH(id, true, scene)
            case Some(Staff.Direction.Left)  => setSpriteFlipH(id, false, scene)
            case _                           => scene
        }

    /// 指定 id の味方が「左向き絵を右移動で反転」する駒か (resource の sprite フラグ)。
    def flipsForFacing(id: Int32, scene: Scene[NodeTag]): Bool =
        match Scene.getState(playerPath(id), scene) {
            case Some(NodeTag.Player(d)) => d#resource#sprite#flipForFacing
            case _                       => false
        }

    /// 1 マス分の差分 (prev → target) から進行方向を求める。
    /// 同セル / 0 ベクトルは None。斜めは便宜上 |x| >= |y| を横優先で扱う
    /// (FE では基本的に直交 1 マスのみ移動するので通常通らない)。
    def directionOfStep(prev: {x = Int32, y = Int32},
                         target: {x = Int32, y = Int32}): Option[Staff.Direction] =
        let dx = target#x - prev#x;
        let dy = target#y - prev#y;
        if (dx == 0 and dy == 0) None
        else if (Int32.abs(dx) >= Int32.abs(dy))
            if (dx > 0) Some(Staff.Direction.Right)
            else Some(Staff.Direction.Left)
        else
            if (dy > 0) Some(Staff.Direction.Down)
            else Some(Staff.Direction.Up)

    // ────────────────────────────────────────────────────────
    // (F) ゲームオーバー時のリセット
    // ────────────────────────────────────────────────────────

    /// 現在の全プレイヤーの spawn 情報（id / gridPos / resource / weapons / staves）を抽出する。
    /// `Game.start` で初回 build 直後に呼んで保存する。
    /// 攻撃前に取られる前提でインベントリは無破損の初期値。respawn ではこの値で復元される。
    /// 射影元 Data を `World.dataFromWorld` オーバーレイで World store 由来にする
    /// （captureSnaps と同型）。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        getAll(scene)
            |> List.map(d0 ->
                let d = World.dataFromWorld(d0#id, world, scene) |> Option.getWithDefault(d0);
                ({id = d#id, classId = d#classId, gridPos = d#gridPos, resource = d#resource,
                   weapons = d#weapons, staves = d#staves,
                   consumables = d#consumables, rings = d#rings}: Spawn))

    // ────────────────────────────────────────────────────────
    // (F') フロア進行 — 階段退場 / フロア持ち越し
    // ────────────────────────────────────────────────────────

    /// フロア間で引き継ぐ味方ステータス。HP / 武器 / 持ち物に加え、レベルアップで得た
    /// `level` / `exp` / 成長後ステータス (`stats`) を持つ。配置（gridPos）や waited は
    /// 次フロアで作り直すので含めない。
    pub type alias CarryData = {
        id          = Int32,
        hp          = Int32,
        weapons     = List[UnitCatalog.WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource],
        // 装備中の指輪。フロアを跨いでも装備が消えないよう引き継ぐ。
        rings       = List[Ring.RingResource],
        // 指輪を装備中かどうか。フロアを跨いでも装備状態を保つ。
        ringEquipped = Bool,
        level       = Int32,
        exp         = Int32,
        // 成長後の 9 ステータス（最大 HP 含む）。次フロアの新規 resource に上書きして引き継ぐ。
        stats   = LevelSystem.Stats
    }

    /// 味方 id を「階段で退場」させる。`usedStairs` を立て、`hidden` も同時に立てて
    /// Marker2D ごと不可視にする（= 盤面・敵範囲・占有・経路・カーソルから外れる）。
    /// `waited` も立てるので「行動済み」扱いになり、`firstActive` の対象から
    /// 外れて以後このフロアでは動けない。`clearAllWaited` は usedStairs を維持するため
    /// 敵ターンを跨いでも退場状態のままになる。次フロア構築 (addOnePlayer) で全て false に戻る。
    pub def useStairs(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), true));  // 階段退場で waited を World へ
        World.Command.emit(World.Cmd.SetUsedStairs(World.EntityRef.Player(id), true));  // usedStairs を World へ dual-write
        scene
            |> setHidden(id, true)
            // waited は World 権威（上の Cmd.SetWaited が source）。
            // usedStairs は store 化（additive・dual-write）。reader flip は後続ゆえ scene も維持。
            |> mapPlayer(id, d -> {usedStairs = true | d})

    /// 生存している味方が「全員」階段を使ったか（= このフロアの終了条件）。
    /// 生存者が 1 人も居ない場合は false（それは全滅 = ゲームオーバー側の扱い）。
    pub def allLivingUsedStairs(scene: Scene[NodeTag]): Bool =
        let living = getAll(scene) |> List.filter(d -> d#hp > 0);
        not List.isEmpty(living) and List.forAll(d -> d#usedStairs, living)

    /// 現在の生存味方の引き継ぎ用ステータス（HP / 武器 / 持ち物）を抽出する。
    /// 次フロアへ進む直前に呼び、構築後の `reconcileWithCarry` で復元する。
    /// 射影元 Data を `World.dataFromWorld` オーバーレイで World store 由来にする
    /// （captureSnaps と同型）。
    pub def snapshotCarry(scene: Scene[NodeTag]): List[CarryData] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        getAll(scene)
            |> List.map(d0 -> World.dataFromWorld(d0#id, world, scene) |> Option.getWithDefault(d0))
            |> List.filter(d -> d#hp > 0)
            |> List.map(d ->
                ({id = d#id, hp = d#hp, weapons = d#weapons, staves = d#staves,
                  consumables = d#consumables, rings = d#rings,
                  ringEquipped = d#ringEquipped,
                  level = d#level, exp = d#exp,
                  stats = LevelSystem.statsOf(d#resource)}: CarryData))

    /// 次フロアを通常 build した直後の scene に、前フロアの引き継ぎ値を反映する。
    ///   - carry に居ない id（前フロアで戦死）の味方ノードを除去する
    ///   - 生存 id は HP / 武器 / 持ち物 / レベル / EXP / 成長後ステータスを carry で上書きし、
    ///     HP バーも更新する
    /// `waited` / `usedStairs` / `hidden` / `moveStepsTaken` は addOnePlayer が false / 0 で
    /// 作り直しているのでリセット不要（= フロア開始時に全員再行動可・たいきリセット）。
    pub def reconcileWithCarry(carry: List[CarryData], scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let carryIds = carry |> List.map(c -> c#id);
        let deadIds = getAll(scene)
            |> List.filter(d -> not List.exists(id -> id == d#id, carryIds))
            |> List.map(d -> d#id);
        // ノード除去と対で World からも除去（前フロア戦死者の store 掃除）。
        List.forEach(id -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Player(id))), deadIds);
        let pruned = List.foldLeft((sc, id) -> Scene.removeAt(playerPath(id), sc), scene, deadIds);
        List.foldLeft((sc, c) -> {
            World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(c#id), c#hp));  // carry hp を World へ
            World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(c#id), c#level, c#exp));  // carry 進行度
            World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(c#id), c#weapons));  // carry weapons を World へ
            World.Command.emit(World.Cmd.SetStaves(World.EntityRef.Player(c#id), c#staves));  // carry inventory を World へ
            World.Command.emit(World.Cmd.SetConsumables(World.EntityRef.Player(c#id), c#consumables));
            World.Command.emit(World.Cmd.SetRings(World.EntityRef.Player(c#id), c#rings));
            World.Command.emit(World.Cmd.SetRingEquipped(World.EntityRef.Player(c#id), c#ringEquipped));
            let next = sc
                |> mapPlayer(c#id, d ->
                    {hp = c#hp, weapons = c#weapons, staves = c#staves,
                     consumables = c#consumables, rings = c#rings,
                     ringEquipped = c#ringEquipped,
                     level = c#level, exp = c#exp,
                     resource = LevelSystem.withStats(c#stats, d#resource) | d});
            // carry の成長後 stats を resource へ書いた＝baseStats の source が変わったので World へ dual-write。
            emitBaseStatsFromScene(c#id, next);
            // carry の weapons/rings/ringEquipped 復元に 1:1 で weaponView/ringBonus も World へ dual-write。
            emitWeaponViewFromScene(c#id, next);
            emitRingBonusFromScene(c#id, next);
            next },
            pruned, carry)

    /// スナップショットの味方リストから決定論的に再配置する（乱数なし）。
    /// base resource を `classId` で引き、`addOnePlayer` で土台を置いてから snap の動的値
    /// （HP / 装備 / 持ち物 / レベル / EXP / 成長後ステータス / 向き / 時限ステータス）を上書きする。
    /// 進入時スナップショット（フロア最初から）では向き＝既定・statuses 空なので overlay しても不変、
    /// 中断セーブからの再開では中断時点の現在値がそのまま復元される（snapshot が単一の真実源）。
    pub def addFromSnaps(snaps: List[FloorSnapshot.PlayerSnap],
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        List.foldLeft((acc, snap) ->
            placeOneFromSnap(snap, catalog, staffCatalog, consumableCatalog, ringCatalog, acc),
            scene, snaps)

    /// 味方 1 体を snap から配置する。base resource を classId で引いて `addOnePlayer` で土台を置き、
    /// snap の動的値（HP / レベル / EXP / 成長後ステータス / 装備中フラグ / 向き / 時限ステータス）を
    /// 上書きする（`reconcileWithCarry` の 1 体版 ＋ 中断再開用の向き・statuses 復元）。
    /// 進入時スナップショットでは向き＝既定・statuses 空なので overlay しても不変。
    def placeOneFromSnap(snap: FloorSnapshot.PlayerSnap,
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let sp = snapToPlayerSpawn(snap, catalog, staffCatalog, consumableCatalog, ringCatalog);
        let placed = addOnePlayer(sp, scene)
            |> mapPlayer(snap#id, d -> {hp = snap#hp, level = snap#level, exp = snap#exp,
                                         ringEquipped = snap#ringEquipped,
                                         facing = snap#facing, statuses = snap#statuses,
                                         resource = LevelSystem.withStats(snap#stats, d#resource) | d});
        // 🐛fix: 復元 hp/progress の World dual-write は **addOnePlayer の後**に emit する。
        // addOnePlayer が spawn 値(SetHp(maxHp)/SetProgress(level,0)) を emit するので、先に出すと
        // worldRef で spawn 値に上書きされてしまう（scene は mapPlayer 上書きで snap 値・World だけ spawn で食い違う）。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(snap#id), snap#hp));
        World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(snap#id), snap#level, snap#exp));
        // mapPlayer が resource=withStats(snap#stats,..) で成長後 stats に上書き（addOnePlayer は base resource を seed）。
        // hp/progress 同様 addOnePlayer の後に emit する（spawn 値上書き回避）。
        emitBaseStatsFromScene(snap#id, placed);
        // mapPlayer が ringEquipped=snap#ringEquipped で上書き（addOnePlayer は false を seed）＝束ね書込の片割れ。
        emitRingEquippedFromScene(snap#id, placed);
        // mapPlayer が statuses=snap#statuses で上書き（addOnePlayer は Nil を seed）。ここで Seed しないと
        // scene の復元 statuses（非空のとき）が World へ届かず combatViewOf が buff/debuff を落とす。
        emitStatusesFromScene(snap#id, placed);
        placed

    /// `PlayerSnap` を配置用 `Spawn`（base resource ＋ 解決済み持ち物）に変換する。
    /// `placeOneFromSnap`（フロア最初から）と `reviveOneFromSnap`（女神の加護）が共有する。
    def snapToPlayerSpawn(snap: FloorSnapshot.PlayerSnap,
                           catalog: UnitCatalog.UnitCatalog,
                           staffCatalog: Staff.StaffCatalog,
                           consumableCatalog: Consumable.ConsumableCatalog,
                           ringCatalog: Ring.RingCatalog): Spawn =
        {id = snap#id, classId = snap#classId, gridPos = snap#gridPos,
         resource = UnitCatalog.lookupUnit(snap#classId, catalog),
         weapons = resolveWeapons(snap#weapons, catalog),
         staves = resolveStaves(snap#staves, staffCatalog),
         consumables = resolveConsumables(snap#consumables, consumableCatalog),
         rings = resolveRings(snap#rings, ringCatalog)}

    /// snap の武器 id ＋ 耐久を `WeaponResource` のリストに解決する。
    def resolveWeapons(refs: List[{id = String, durability = Int32}],
                        catalog: UnitCatalog.UnitCatalog): List[UnitCatalog.WeaponResource] =
        List.map(ref -> {durability = ref#durability | UnitCatalog.lookupWeapon(ref#id, catalog)}, refs)

    /// snap の杖 id ＋ 耐久を `StaffResource` のリストに解決する。
    def resolveStaves(refs: List[{id = String, durability = Int32}],
                       staffCatalog: Staff.StaffCatalog): List[Staff.StaffResource] =
        List.map(ref -> {durability = ref#durability | Staff.lookup(ref#id, staffCatalog)}, refs)

    /// snap の消費 id ＋ 耐久を `ConsumableResource` のリストに解決する。
    def resolveConsumables(refs: List[{id = String, durability = Int32}],
                            consumableCatalog: Consumable.ConsumableCatalog): List[Consumable.ConsumableResource] =
        List.map(ref -> {durability = ref#durability | Consumable.lookup(ref#id, consumableCatalog)}, refs)

    /// snap の指輪 id を `RingResource` のリストに解決する。
    def resolveRings(ids: List[String], ringCatalog: Ring.RingCatalog): List[Ring.RingResource] =
        List.map(id -> Ring.lookup(id, ringCatalog), ids)

    /// 女神の加護: 既存の味方を全て取り除き、スナップショットの全メンバーを **リーダー(`lordId`)の
    /// 周り** に再配置して全快復活させる（無敵は付与しない）。リーダーを `leaderPos`（倒れたその場）に置き、
    /// 残りはそこから最も近い空き床セルへ順に詰める。敵は呼び出し側で一掃済み前提なので、壁と味方同士の
    /// 重なりだけを避ければよい。マップ・アイテムは現在 scene のまま。
    pub def reviveAroundLeader(snaps: List[FloorSnapshot.PlayerSnap],
                                catalog: UnitCatalog.UnitCatalog,
                                staffCatalog: Staff.StaffCatalog,
                                consumableCatalog: Consumable.ConsumableCatalog,
                                ringCatalog: Ring.RingCatalog,
                                leaderPos: {x = Int32, y = Int32},
                                scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let cleared = List.foldLeft((sc, d) -> Scene.removeAt(playerPath(d#id), sc), scene, getAll(scene));
        let layer = MapScene.getMapLayer(cleared);
        // リーダーを先頭にして、近い順に空きセルを割り当てる（先頭がちょうど leaderPos に乗る）。
        let ordered = leaderFirst(snaps);
        let result = List.foldLeft((acc, snap) -> {
            let (sc, taken) = acc;
            let cell = nearestFreeCell(leaderPos, layer, taken);
            (reviveOneAt(snap, cell, catalog, staffCatalog, consumableCatalog, ringCatalog, sc),
             cell :: taken)
        }, (cleared, (Nil: List[{x = Int32, y = Int32}])), ordered);
        fst(result)

    /// `lordId` の味方を先頭に並べ替える（残りは元の順を保つ）。
    def leaderFirst(snaps: List[FloorSnapshot.PlayerSnap]): List[FloorSnapshot.PlayerSnap] =
        let (lead, rest) = List.partition(s -> s#id == lordId(), snaps);
        List.append(lead, rest)

    /// `origin` に最も近い空き床セルを返す。床（`isFloor`）かつ `taken`（既配置の味方）でないセルを
    /// `origin` 周辺の箱から集め、`origin` からのマンハッタン距離が小さい順に選ぶ。候補ゼロなら `origin`。
    def nearestFreeCell(origin: {x = Int32, y = Int32}, layer: TileMapLayer,
                         taken: List[{x = Int32, y = Int32}]): {x = Int32, y = Int32} =
        let r = 12;
        let candidates = List.range(origin#x - r, origin#x + r + 1)
            |> List.flatMap(x -> List.range(origin#y - r, origin#y + r + 1)
                |> List.map(y -> ({x = x, y = y}: {x = Int32, y = Int32})));
        let free = candidates
            |> List.filter(c -> TileMapLayer.isFloor(c, layer) and not sameCellExists(c, taken))
            |> List.sortBy(c -> Int32.abs(origin#x - c#x) + Int32.abs(origin#y - c#y));
        match List.head(free) {
            case Some(c) => c
            case None    => origin
        }

    /// `c` と同じ座標がリストに含まれるか。
    def sameCellExists(c: {x = Int32, y = Int32}, cells: List[{x = Int32, y = Int32}]): Bool =
        List.exists(x -> x#x == c#x and x#y == c#y, cells)

    /// 味方 1 体を `cell` に全快復活させる（無敵なし）。装備 / レベル / 成長後ステータスは進入時編成。
    def reviveOneAt(snap: FloorSnapshot.PlayerSnap, cell: {x = Int32, y = Int32},
                     catalog: UnitCatalog.UnitCatalog,
                     staffCatalog: Staff.StaffCatalog,
                     consumableCatalog: Consumable.ConsumableCatalog,
                     ringCatalog: Ring.RingCatalog,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let sp = {gridPos = cell | snapToPlayerSpawn(snap, catalog, staffCatalog, consumableCatalog, ringCatalog)};
        let placed = addOnePlayer(sp, scene)
            |> mapPlayer(snap#id, d -> {hp = snap#stats#hp, level = snap#level, exp = snap#exp,
                                         ringEquipped = snap#ringEquipped,
                                         resource = LevelSystem.withStats(snap#stats, d#resource) | d});
        // 🐛fix: 復元 hp/progress の World emit は addOnePlayer の後（spawn 値上書き回避・placeOneFromSnap と同じ）。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(snap#id), snap#stats#hp));
        World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(snap#id), snap#level, snap#exp));
        // mapPlayer が resource=withStats(snap#stats,..) で成長後 stats に上書き＝baseStats source 変化（placeOneFromSnap と同型）。
        emitBaseStatsFromScene(snap#id, placed);
        // mapPlayer が ringEquipped=snap#ringEquipped で上書き（addOnePlayer は false を seed）＝束ね書込の片割れ。
        emitRingEquippedFromScene(snap#id, placed);
        placed

    /// 現在の全味方を `PlayerSnap` 列に射影する（スナップショット保存用）。持ち物 resource は
    /// 各 catalog の `idOf`（name 逆引き）で id 化し、耐久など動的値を併せて保持する。
    /// 射影元 Data を `World.dataFromWorld` オーバーレイで
    /// World store（hp/在庫/level/exp/statuses/pos 等）由来にする（core store 欠けは scene fallback）。
    /// セーブ**形式**は不変。
    pub def captureSnaps(scene: Scene[NodeTag],
                          weaponCatalog: WeaponCatalog.WeaponCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog): List[FloorSnapshot.PlayerSnap] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        getAll(scene) |> List.map(d0 ->
            let d = World.dataFromWorld(d0#id, world, scene) |> Option.getWithDefault(d0);
            ({id = d#id, classId = d#classId, gridPos = d#gridPos, hp = d#hp,
               level = d#level, exp = d#exp, stats = LevelSystem.statsOf(d#resource),
               facing = d#facing, statuses = d#statuses,
               weapons = captureWeaponRefs(d#weapons, weaponCatalog),
               staves = captureStaffRefs(d#staves, staffCatalog),
               consumables = captureConsumableRefs(d#consumables, consumableCatalog),
               rings = List.map(r -> CatalogId.requireId("ring", r#name, Ring.idOf(r, ringCatalog)), d#rings),
               ringEquipped = d#ringEquipped}: FloorSnapshot.PlayerSnap))

    /// 武器リストを `{id, durability}` 列に射影する（id は name 逆引き、失敗時は即 panic）。
    def captureWeaponRefs(weapons: List[UnitCatalog.WeaponResource],
                           weaponCatalog: WeaponCatalog.WeaponCatalog): List[{id = String, durability = Int32}] =
        List.map(w -> {id = CatalogId.requireId("weapon", w#name, WeaponCatalog.idOf(w, weaponCatalog)),
                       durability = w#durability}, weapons)

    /// 杖リストを `{id, durability}` 列に射影する。
    def captureStaffRefs(staves: List[Staff.StaffResource],
                          staffCatalog: Staff.StaffCatalog): List[{id = String, durability = Int32}] =
        List.map(s -> {id = CatalogId.requireId("staff", s#name, Staff.idOf(s, staffCatalog)),
                       durability = s#durability}, staves)

    /// 消費アイテムリストを `{id, durability}` 列に射影する。
    def captureConsumableRefs(consumables: List[Consumable.ConsumableResource],
                               consumableCatalog: Consumable.ConsumableCatalog): List[{id = String, durability = Int32}] =
        List.map(c -> {id = CatalogId.requireId("consumable", c#name, Consumable.idOf(c, consumableCatalog)),
                       durability = c#durability}, consumables)

    // ────────────────────────────────────────────────────────
    // (G) 個別 getter（呼び出し側の便宜）
    // ────────────────────────────────────────────────────────

    /// 指定 id のプレイヤーの現在グリッド座標を返す。未登録なら panic。
    /// scene Data の gridPos だけ World.posOf で上書きして返す（他 field は scene 権威のまま）。
    /// gridPos twin 退役後の「現在位置つき Data」取得口。World 未登録（テスト/spawn 過渡）は scene 値。
    pub def getWithWorldPos(id: Int32, scene: Scene[NodeTag]): Option[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        get(id, scene) |> Option.map(d ->
            {gridPos = World.posOf(World.EntityRef.Player(id), w) |> Option.getWithDefault(d#gridPos) | d})

    /// `getWithWorldPos` の全員版。
    pub def getAllWithWorldPos(scene: Scene[NodeTag]): List[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        getAll(scene) |> List.map(d ->
            {gridPos = World.posOf(World.EntityRef.Player(d#id), w) |> Option.getWithDefault(d#gridPos) | d})

    pub def getGridPos(id: Int32, scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        // scene twin 読み（World 未登録のテスト/spawn 過渡と replayMoveView fallback 用に残置）。
        // live の現在位置は World.posOf / PartyQuery を使うこと。
        match get(id, scene) {
            case Some(d) => d#gridPos
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの移動力（マス数）を返す。未登録なら panic。
    /// 積載ペナルティ込みの実効値を返す（MoveRangeScene の青マスもこの値で縮む）。
    pub def getMoveTiles(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => effectiveMoveTilesOf(d)
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの現在 HP を返す。未登録なら panic。
    pub def getHp(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => d#hp
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの武器インベントリを返す。武器が 1 つも無ければ Nil。
    pub def getWeapons(id: Int32, scene: Scene[NodeTag]): List[UnitCatalog.WeaponResource] =
        match get(id, scene) {
            case Some(d) => d#weapons
            case None    => Nil
        }

    /// 指定 id のプレイヤーの杖インベントリを返す（無ければ空）。
    pub def getStaves(id: Int32, scene: Scene[NodeTag]): List[Staff.StaffResource] =
        match get(id, scene) {
            case Some(d) => d#staves
            case None    => Nil
        }

    /// 指定 id のプレイヤーの消費アイテムインベントリを返す（無ければ空）。
    pub def getConsumables(id: Int32, scene: Scene[NodeTag]):
            List[Consumable.ConsumableResource] =
        match get(id, scene) {
            case Some(d) => d#consumables
            case None    => Nil
        }

    /// ItemMenu で選ばれたアイテム（武器 or 杖）の種別と index を Data#selectedItem にセットする。
    /// `ItemActionSelect` フェーズに進むときに ItemMenuScene から呼ばれる。
    pub def setSelectedItem(playerId: Int32, item: PlayerData.ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = Some(item) | d}, scene)

    /// 選択中アイテムをクリアする（サブメニュー確定後の後始末）。
    pub def clearSelectedItem(playerId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = None | d}, scene)

    /// 指定 idx の武器を装備（= weapons リストの先頭に移動）。
    /// 既に先頭なら何もしない。範囲外なら no-op。
    /// 「こうげき」は常に `weapons.head` を使うため、これで装備切り替えが反映される。
    /// 武器切り替えの単一 commit 点なので、ここで左上の武器系統アイコンも貼り直す
    /// （WeaponSelect / ItemMenu / BattlePanel いずれの経路でも追従する）。
    pub def equipWeapon(playerId: Int32, idx: Int32,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let moved = mapPlayer(playerId, d -> {weapons = moveToHead(idx, d#weapons) | d}, scene);
        emitWeaponsFromScene(playerId, moved);  // 装備並べ替え後の weapons を World へ
        // 武器アイコンは renderGlyphs/renderPlates が World.weaponView から毎フレーム直描き＝貼り直し不要。
        moved

    /// 指定 idx の武器をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropWeapon(playerId: Int32, idx: Int32,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let dropped = mapPlayer(playerId, d -> {weapons = removeAt(idx, d#weapons) | d}, scene);
        emitWeaponsFromScene(playerId, dropped);  // 捨てた後の weapons を World へ
        dropped

    /// 指定 idx の杖をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropStaff(playerId: Int32, idx: Int32,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let dropped = mapPlayer(playerId, d -> {staves = removeAt(idx, d#staves) | d}, scene);
        emitStavesFromScene(playerId, dropped);  // 捨てた後の staves を World へ
        dropped

    /// 指定 idx の消費アイテムをインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropConsumable(playerId: Int32, idx: Int32,
                             scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let dropped = mapPlayer(playerId, d -> {consumables = removeAt(idx, d#consumables) | d}, scene);
        emitConsumablesFromScene(playerId, dropped);  // 捨てた後の consumables を World へ
        dropped

    /// 2 プレイヤー間でインベントリのアイテム 1 個ずつを交換する純粋関数。
    ///   - 双方が実体アイテム持ちなら相互スワップ（ともに元の場所から消え、相手の末尾に追加）
    ///   - 相手が `None` (= 空スロット) のときは一方向 transfer
    ///     (自分のアイテムが消えて相手の対応リスト末尾に積まれる)
    /// 種別 (武器/杖) は元のままなので、武器 ↔ 杖の交換も自動的に両者の対応リストへ振り分けられる。
    /// `selfKind` が範囲外 / `selfId` が存在しない場合は防御的に no-op。
    /// 「こうかん」確定 (Phase 4) で TradeMenuScene から呼ばれる。
    ///
    /// 引数 (record-style):
    ///   - `selfId`      : 必ず実体アイテムを渡す側のプレイヤー id
    ///   - `selfKind`    : self 側で渡すアイテム種別 (Weapon idx / Staff idx)
    ///   - `partnerId`   : もう一方のプレイヤー id
    ///   - `partnerKind` : Some なら双方向 swap、None なら self 側からの片方向 transfer
    pub def swapItem(args: {selfId = Int32, selfKind = PlayerData.ItemKind,
                              partnerId = Int32,
                              partnerKind = Option[PlayerData.ItemKind]},
                      scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let selfId      = args#selfId;
        let selfKind    = args#selfKind;
        let partnerId   = args#partnerId;
        let partnerKind = args#partnerKind;
        // 1. 両者のアイテム実体を「現在の scene」から抜き出す (まだ削除はしない)
        let selfItemOpt = getInventoryItem(selfId, selfKind, scene);
        let partnerItemOpt = partnerKind
            |> Option.flatMap(pk -> getInventoryItem(partnerId, pk, scene));
        // 2. self 側に実体が無ければ no-op (selfKind = 空スロットは仕様外)
        selfItemOpt
            |> Option.map(selfItem -> scene
                |> removeInventoryItem(selfId, selfKind)
                |> removeOptInventoryItem(partnerId, partnerKind)
                |> addOptInventoryItem(selfId, partnerItemOpt)
                |> addInventoryItem(partnerId, selfItem))
            |> Option.getWithDefault(scene)

    /// 同じ player のインベントリ内で 2 アイテムの並び順を入れ替える（並び替え）。
    /// 表示順 (weapons ++ staves ++ consumables) を 1 列とみなして kindA / kindB の位置を
    /// 入れ替え、種別ごとのリストに振り直す。同じ種類同士なら純粋な位置入替、種別を跨ぐ
    /// ときは各リスト内での相対順だけが変わる。weapons[0] が装備なので武器の並び替えは
    /// 装備変更も兼ねる。
    pub def reorderItem(playerId: Int32, kindA: PlayerData.ItemKind, kindB: PlayerData.ItemKind,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let weapons     = getWeapons(playerId, scene);
        let staves      = getStaves(playerId, scene);
        let consumables = getConsumables(playerId, scene);
        let rings       = getRings(playerId, scene);
        let nw = List.length(weapons);
        let ns = List.length(staves);
        let nc = List.length(consumables);
        let seq = List.append(
            List.map(w -> ItemData.GroundItemKind.WeaponItem(w), weapons),
            List.append(
                List.map(s -> ItemData.GroundItemKind.StaffItem(s), staves),
                List.append(
                    List.map(c -> ItemData.GroundItemKind.ConsumableItem(c), consumables),
                    List.map(r -> ItemData.GroundItemKind.RingItem(r), rings))));
        let swapped = swapListAt(displaySeqIndex(kindA, nw, ns, nc),
                                  displaySeqIndex(kindB, nw, ns, nc), seq);
        let newWeapons = List.filterMap(item -> match item {
            case ItemData.GroundItemKind.WeaponItem(w) => Some(w)
            case _                                      => None
        }, swapped);
        let newStaves = List.filterMap(item -> match item {
            case ItemData.GroundItemKind.StaffItem(s) => Some(s)
            case _                                     => None
        }, swapped);
        let newConsumables = List.filterMap(item -> match item {
            case ItemData.GroundItemKind.ConsumableItem(c) => Some(c)
            case _                                          => None
        }, swapped);
        let newRings = List.filterMap(item -> match item {
            case ItemData.GroundItemKind.RingItem(r) => Some(r)
            case _                                    => None
        }, swapped);
        let reordered = mapPlayer(playerId, d ->
            {weapons = newWeapons, staves = newStaves, consumables = newConsumables,
             rings = newRings | d}, scene);
        emitWeaponsFromScene(playerId, reordered);  // 並び替え後の weapons を World へ
        // 並び替えは staves/consumables/rings も書き換える束ね書込＝3 つとも World へ dual-write。
        emitStavesFromScene(playerId, reordered);
        emitConsumablesFromScene(playerId, reordered);
        emitRingsFromScene(playerId, reordered);
        reordered

    /// PlayerData.ItemKind を、表示順 (weapons ++ staves ++ consumables ++ rings) 上の通し index に変換する。
    def displaySeqIndex(kind: PlayerData.ItemKind, nw: Int32, ns: Int32, nc: Int32): Int32 =
        match kind {
            case PlayerData.ItemKind.Weapon(i)     => i
            case PlayerData.ItemKind.Staff(i)      => nw + i
            case PlayerData.ItemKind.Consumable(i) => nw + ns + i
            case PlayerData.ItemKind.Ring(i)       => nw + ns + nc + i
        }

    /// list の index a と b の要素を入れ替える。範囲外 / a==b なら元の list。
    def swapListAt(a: Int32, b: Int32, list: List[t]): List[t] =
        if (a == b) list
        else match (List.nth(a, list), List.nth(b, list)) {
            case (Some(x), Some(y)) =>
                List.mapWithIndex(i -> v -> if (i == a) y else if (i == b) x else v, list)
            case _ => list
        }

    /// 指定 player の (kind = Weapon(idx) | Staff(idx)) のアイテム実体を返す。
    /// player が居ない / index が範囲外なら None
    /// (getWeapons / getStaves が居ない player に対し Nil を返すので、その経由で None)。
    /// 戻り値は `ItemData.GroundItemKind` を流用 (= 「インベントリ可能なアイテム値」)。
    pub def getInventoryItem(playerId: Int32, kind: PlayerData.ItemKind, scene: Scene[NodeTag]):
            Option[ItemData.GroundItemKind] =
        match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                List.nth(idx, getWeapons(playerId, scene))
                    |> Option.map(w -> ItemData.GroundItemKind.WeaponItem(w))
            case PlayerData.ItemKind.Staff(idx) =>
                List.nth(idx, getStaves(playerId, scene))
                    |> Option.map(s -> ItemData.GroundItemKind.StaffItem(s))
            case PlayerData.ItemKind.Consumable(idx) =>
                List.nth(idx, getConsumables(playerId, scene))
                    |> Option.map(c -> ItemData.GroundItemKind.ConsumableItem(c))
            case PlayerData.ItemKind.Ring(idx) =>
                List.nth(idx, getRings(playerId, scene))
                    |> Option.map(r -> ItemData.GroundItemKind.RingItem(r))
        }

    /// 指定 player の `kind` のアイテムをインベントリから取り除く。
    /// `dropWeapon` / `dropStaff` のディスパッチ統合版。
    def removeInventoryItem(playerId: Int32, kind: PlayerData.ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match kind {
            case PlayerData.ItemKind.Weapon(idx)     => dropWeapon(playerId, idx, scene)
            case PlayerData.ItemKind.Staff(idx)      => dropStaff(playerId, idx, scene)
            case PlayerData.ItemKind.Consumable(idx) => dropConsumable(playerId, idx, scene)
            case PlayerData.ItemKind.Ring(idx)       => dropRing(playerId, idx, scene)
        }

    /// `partnerKind = None` (= 空スロット相手) の場合は no-op、Some なら removeInventoryItem。
    def removeOptInventoryItem(playerId: Int32, kindOpt: Option[PlayerData.ItemKind],
                                 scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        kindOpt
            |> Option.map(k -> removeInventoryItem(playerId, k, scene))
            |> Option.getWithDefault(scene)

    /// 武器インベントリの末尾に 1 個追加する。末尾追加により weapons[0] が常に装備中を保つ。
    /// 「ひろう」「こうかん」「キャンセル undo」など複数の追加経路がここに集約されるため、
    /// 追加ルール（末尾 = 装備中の後ろ）の変更は 1 箇所で完結する。
    pub def addWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let added = mapPlayer(playerId,
            d -> {weapons = List.append(d#weapons, weapon :: Nil) | d}, scene);
        emitWeaponsFromScene(playerId, added);  // 拾う/こうかん/undo の追加後 weapons を World へ
        added

    /// 杖インベントリの末尾に 1 個追加する。追加ルールは `addWeapon` と同じ（末尾追加）。
    pub def addStaff(playerId: Int32, staff: Staff.StaffResource,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let added = mapPlayer(playerId,
            d -> {staves = List.append(d#staves, staff :: Nil) | d}, scene);
        emitStavesFromScene(playerId, added);  // 追加後の staves を World へ
        added

    /// 消費アイテムインベントリの末尾に 1 個追加する。追加ルールは `addWeapon` と同じ（末尾追加）。
    pub def addConsumable(playerId: Int32, item: Consumable.ConsumableResource,
                            scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let added = mapPlayer(playerId,
            d -> {consumables = List.append(d#consumables, item :: Nil) | d}, scene);
        emitConsumablesFromScene(playerId, added);  // 追加後の consumables を World へ
        added

    /// 指輪インベントリ（先頭が装備中）。居ない player は Nil。
    pub def getRings(id: Int32, scene: Scene[NodeTag]): List[Ring.RingResource] =
        match get(id, scene) {
            case Some(d) => d#rings
            case None    => Nil
        }

    /// 指輪インベントリの末尾に 1 個追加する（末尾追加 = 装備中の後ろ）。
    pub def addRing(playerId: Int32, ring: Ring.RingResource,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let added = mapPlayer(playerId,
            d -> {rings = List.append(d#rings, ring :: Nil) | d}, scene);
        emitRingsFromScene(playerId, added);  // 追加後の rings を World へ
        added

    /// 指定 idx の指輪を先頭へ移動し、装備状態にする（`ringEquipped = true`）。範囲外なら no-op。
    /// 拾っただけでは装備されないので、ここを通って初めて効果が出る。
    pub def equipRing(playerId: Int32, idx: Int32,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let equipped = mapPlayer(playerId,
            d -> {rings = moveToHead(idx, d#rings), ringEquipped = true | d}, scene);
        // rings と ringEquipped 両方の束ね書込（装備）＝両方 emit する。
        emitRingsFromScene(playerId, equipped);
        emitRingEquippedFromScene(playerId, equipped);
        equipped

    /// 装備中の指輪を外す（所持は維持し、効果だけ止める）。並びは変えない。
    pub def unequipRing(playerId: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let unequipped = mapPlayer(playerId, d -> {ringEquipped = false | d}, scene);
        emitRingEquippedFromScene(playerId, unequipped);  // 解除後の ringEquipped を World へ
        unequipped

    /// 指定 idx の指輪をインベントリから削除（捨てる）。範囲外なら no-op。
    /// 装備中の指輪（先頭）を捨てたら装備状態も解除する（残った先頭が勝手に装備されないように）。
    pub def dropRing(playerId: Int32, idx: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let dropped = mapPlayer(playerId,
            d -> {rings = removeAt(idx, d#rings),
                  ringEquipped = if (idx == 0) false else d#ringEquipped | d}, scene);
        // rings と ringEquipped 両方の束ね書込（捨てる・先頭なら解除）＝両方 emit する。
        emitRingsFromScene(playerId, dropped);
        emitRingEquippedFromScene(playerId, dropped);
        dropped

    /// ringman の特殊行動で「指輪に変えられる」持ち物 = 装備外のアイテムを (種別 index, 表示名) で列挙する。
    /// 装備中の武器（weapons 先頭）と装備中の指輪（ringEquipped のときの rings 先頭）は守り、
    /// それ以外の武器・杖・薬・指輪を対象にする。居ない player は Nil。
    /// 在庫読みは PartyQuery（World.dataFromWorld オーバーレイ）経由。
    pub def transformableItems(playerId: Int32):
            List[(PlayerData.ItemKind, String)] \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(playerId) {
            case None    => Nil
            case Some(d) => transformableOf(d)
        }

    /// `transformableItems` の本体（Data から純粋に列挙）。装備中の武器先頭・装備中の指輪先頭を除く。
    pub def transformableOf(d: Data): List[(PlayerData.ItemKind, String)] =
        let weaponItems = d#weapons
            |> List.mapWithIndex(idx -> w -> (idx, w#name))
            |> List.filterMap(t -> let (idx, name) = t;
                if (idx >= 1) Some((PlayerData.ItemKind.Weapon(idx), name)) else None);
        let staffItems = d#staves
            |> List.mapWithIndex(idx -> s -> (PlayerData.ItemKind.Staff(idx), s#name));
        let consumableItems = d#consumables
            |> List.mapWithIndex(idx -> c -> (PlayerData.ItemKind.Consumable(idx), c#name));
        let ringItems = d#rings
            |> List.mapWithIndex(idx -> r -> (idx, r#name))
            |> List.filterMap(t -> let (idx, name) = t;
                if (d#ringEquipped and idx == 0) None
                else Some((PlayerData.ItemKind.Ring(idx), name)));
        List.append(weaponItems,
            List.append(staffItems, List.append(consumableItems, ringItems)))

    /// 指定 player の `kind` の持ち物を 1 つ取り除き、代わりに `ring` を持ち物末尾に加える。
    /// ringman の特殊行動の scene 変換部（どの指輪にするかの抽選は catalog を持つ呼び出し側）。
    pub def replaceItemWithRing(playerId: Int32, kind: PlayerData.ItemKind,
                                 ring: Ring.RingResource, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        addRing(playerId, ring, removeInventoryItem(playerId, kind, scene))

    /// 指定 player のインベントリに `item` を追加（種別ごとに上記 writer へ委譲）。
    /// `addPickedItem`（ログ付き版）と同じ追加ルールの、ログを出さない版。
    def addInventoryItem(playerId: Int32, item: ItemData.GroundItemKind,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match item {
            case ItemData.GroundItemKind.WeaponItem(weapon)        =>
                addWeapon(playerId, weapon, scene)
            case ItemData.GroundItemKind.StaffItem(staff)          =>
                addStaff(playerId, staff, scene)
            case ItemData.GroundItemKind.ConsumableItem(consumable) =>
                addConsumable(playerId, consumable, scene)
            case ItemData.GroundItemKind.RingItem(ring)            =>
                addRing(playerId, ring, scene)
        }

    /// 床アイテム（`gridPos`）を playerId の在庫へ取得する共通処理。重量ゲートは呼び出し側が
    /// 行う前提（手動「ひろう」も、移動着地の自動取得も、拾えると判断してからここを呼ぶ）。
    /// 取得は `cancelSelection` で巻き戻せるよう `PickedUp` ドラフトに積んでから、
    /// 床撤去 → 在庫末尾へ追加 → ログ、の順で行う。床にアイテムが無ければ素通し（防御的）。
    pub def pickupFloorItem(playerId: Int32, gridPos: {x = Int32, y = Int32},
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, GameLogger.GameLogger, World.Command,
                              World.WorldQuery} =
        // 床アイテムは World store から読む（scene ノード撤去済み・read-after-write で fresh）。
        match World.groundItemAtOf(gridPos, World.WorldQuery.get()) {
            case None    => scene
            case Some(d) =>
                SelectedPlayer.pushDraft(
                    MoveDraft.DraftAction.PickedUp(playerId, d#gridPos, d#itemKey, d#item));
                let (afterTake, taken) = GroundItems.takeAt(d#gridPos, scene);
                taken
                    |> Option.map(kind -> addPickedItem(playerId, kind, afterTake))
                    |> Option.getWithDefault(afterTake)
        }

    /// 拾ったアイテムを在庫末尾に追加し「拾った」ログを出す（ログを出さない
    /// `addInventoryItem` のログ付き版）。手動「ひろう」/ 移動着地の自動取得 / 宝箱開錠の
    /// 取得経路が共有する。武器は weapons 末尾、杖は staves 末尾に積む。
    pub def addPickedItem(playerId: Int32, kind: ItemData.GroundItemKind,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, World.Command} =
        match kind {
            case ItemData.GroundItemKind.WeaponItem(weapon) =>
                GameLogger.playerLog("${displayName(playerId, scene)} が${weapon#name} を拾った");
                addWeapon(playerId, weapon, scene)
            case ItemData.GroundItemKind.StaffItem(staff) =>
                GameLogger.playerLog("${displayName(playerId, scene)} が${staff#name} を拾った");
                addStaff(playerId, staff, scene)
            case ItemData.GroundItemKind.ConsumableItem(item) =>
                GameLogger.playerLog("${displayName(playerId, scene)} が${item#name} を拾った");
                addConsumable(playerId, item, scene)
            case ItemData.GroundItemKind.RingItem(ring) =>
                GameLogger.playerLog("${displayName(playerId, scene)} が${ring#name} を拾った");
                addRing(playerId, ring, scene)
        }

    /// `optItem = None` のときは no-op、Some なら addInventoryItem。
    def addOptInventoryItem(playerId: Int32, optItem: Option[ItemData.GroundItemKind],
                              scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        optItem
            |> Option.map(item -> addInventoryItem(playerId, item, scene))
            |> Option.getWithDefault(scene)

    /// `kind` 種別の在庫リスト末尾の 1 個を取り除く（`addInventoryItem` の逆操作）。
    /// 「ひろう」をキャンセルしたときに、末尾追加した仮取得アイテムを取り消すのに使う。
    /// 該当リストが空なら no-op。
    def removeLastInventoryItem(playerId: Int32, kind: ItemData.GroundItemKind,
                                  scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match kind {
            case ItemData.GroundItemKind.WeaponItem(_)     =>
                let n = List.length(getWeapons(playerId, scene));
                if (n > 0) dropWeapon(playerId, n - 1, scene) else scene
            case ItemData.GroundItemKind.StaffItem(_)      =>
                let n = List.length(getStaves(playerId, scene));
                if (n > 0) dropStaff(playerId, n - 1, scene) else scene
            case ItemData.GroundItemKind.ConsumableItem(_) =>
                let n = List.length(getConsumables(playerId, scene));
                if (n > 0) dropConsumable(playerId, n - 1, scene) else scene
            case ItemData.GroundItemKind.RingItem(_)       =>
                let n = List.length(getRings(playerId, scene));
                if (n > 0) dropRing(playerId, n - 1, scene) else scene
        }

    /// List の `idx` 番目の要素を先頭に移動する。範囲外なら元のリストをそのまま返す。
    /// `[a, b, c, d]` の idx=2 を頭に → `[c, a, b, d]`。
    def moveToHead(idx: Int32, list: List[a]): List[a] =
        match List.nth(idx, list) {
            case None    => list
            case Some(x) => x :: removeAt(idx, list)
        }

    /// List から `idx` 番目の要素を取り除く。範囲外なら元のリストをそのまま返す。
    def removeAt(idx: Int32, list: List[a]): List[a] =
        List.zipWithIndex(list)
            |> List.filter(pair -> let (i, _) = pair; i != idx)
            |> List.map(pair -> let (_, x) = pair; x)

    /// `moveToHead` の逆操作: 先頭要素を `idx` 位置へ戻す。
    /// `[c, a, b, d]` の idx=2 → `[a, b, c, d]`（c を index 2 に挿入し直す）。
    /// 空リストはそのまま。
    def moveHeadTo(idx: Int32, list: List[a]): List[a] =
        match list {
            case Nil    => Nil
            case h :: t => insertAt(idx, h, t)
        }

    /// `removeAt` の逆操作: `x` を `idx` 位置に挿入する。
    /// idx <= 0 は先頭、idx >= 長さ は末尾に clamp。
    def insertAt(idx: Int32, x: a, list: List[a]): List[a] =
        if (idx <= 0) x :: list
        else match list {
            case Nil    => x :: Nil
            case h :: t => h :: insertAt(idx - 1, x, t)
        }

    /// `removeInventoryItem` の対: `kind`(Weapon/Staff/Consumable idx) の示す位置に
    /// `item` を挿入し直す（捨てる・交換のキャンセル巻き戻しで元の並びを復元する）。
    /// kind と item の種別が食い違う場合は防御的に no-op。
    def insertInventoryItem(playerId: Int32, kind: PlayerData.ItemKind,
                              item: ItemData.GroundItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match (kind, item) {
            case (PlayerData.ItemKind.Weapon(idx), ItemData.GroundItemKind.WeaponItem(w))         =>
                let inserted = mapPlayer(playerId, d -> {weapons = insertAt(idx, w, d#weapons) | d}, scene);
                emitWeaponsFromScene(playerId, inserted);  // 挿入巻き戻し後の weapons を World へ
                inserted
            case (PlayerData.ItemKind.Staff(idx), ItemData.GroundItemKind.StaffItem(s))           =>
                let inserted = mapPlayer(playerId, d -> {staves = insertAt(idx, s, d#staves) | d}, scene);
                emitStavesFromScene(playerId, inserted);  // 挿入巻き戻し後の staves を World へ
                inserted
            case (PlayerData.ItemKind.Consumable(idx), ItemData.GroundItemKind.ConsumableItem(c)) =>
                let inserted = mapPlayer(playerId, d -> {consumables = insertAt(idx, c, d#consumables) | d}, scene);
                emitConsumablesFromScene(playerId, inserted);  // 挿入巻き戻し後の consumables を World へ
                inserted
            case (PlayerData.ItemKind.Ring(idx), ItemData.GroundItemKind.RingItem(r)) =>
                let inserted = mapPlayer(playerId, d -> {rings = insertAt(idx, r, d#rings) | d}, scene);
                emitRingsFromScene(playerId, inserted);  // 挿入巻き戻し後の rings を World へ
                inserted
            case _ => scene
        }


    /// レベルアップ表示待ち (pendingLevelUp = Some) の味方が 1 人でも居るか。
    /// 自分の攻撃（TurnFlow.commitWaitedAndAdvance）でも敵ターンの反撃（endTurn）でも、
    /// この判定でステータス変化パネルへ割り込む。
    pub def anyPendingLevelUp(scene: Scene[NodeTag]): Bool =
        getAll(scene) |> List.exists(d -> Option.nonEmpty(d#pendingLevelUp))

    /// World 直下の `Player_<id>` 形式の NodePath から id を取り出す。
    /// それ以外なら None。AnimationPlayer の event 振り分けに使う
    pub def idFromPath(path: NodePath): Option[Int32] =
        match path {
            case world :: name :: Nil if world == MapScene.worldName() =>
                if (String.startsWith({prefix = "Player_"}, name))
                    String.dropLeft(7, name) |> Int32.fromString
                else None
            case _ => None
        }

}
