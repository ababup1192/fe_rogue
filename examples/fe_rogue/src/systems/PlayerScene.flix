/// PlayerScene — 味方パーティ（3 人）の spawn・移動・在庫・ターン状態の操作の集まり
///
/// FE 風 SRPG の「3 人パーティ」を表現する。駒の状態は World の各 store が唯一の権威で、
/// 読みは `World.dataFromWorld`（store 群からの `Data` 再構築）、書きは `World.Cmd` の emit に統一する。
/// 見た目（本体 sprite / HP バー / 武器アイコン）は World store から直描きし、
/// 描画位置も World（renderPos / lunge）から導出する。
///
/// Camera の状態は World の cameraSmoothPos が視点の権威で、`CameraScene.step` が
/// フェーズ別の追従先（選択中プレイヤー等の World 座標）を毎フレーム選ぶ（PlayerScene 自身は Camera を持たない）。
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
/// 移動は moveToById(id, target) で論理位置（World の pos）を即更新し、
/// 見た目は World の renderPos tween に委ねる。**壁・他駒の判定は
/// 呼び出し側（Board / MoveRangeScene）が moveToById を呼ぶ前に済ませている前提**。
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

    /// この味方の装備武器（先頭 = 装備中）の戦闘投影。`combatView` と World read-model 構築が共有し、
    /// proficiency 解決の二重実装を避ける。武器なしは None。
    pub def equippedWeaponView(data: Data): Option[Combat.WeaponView] =
        weaponViewOfParts(data#resource, data#weapons)

    /// `equippedWeaponView` の部品版（resource＋weapons から直接組む）。
    /// World 在庫からの weaponView co-emit（emitWeaponViewFromWorld）が full Data なしで使う。
    pub def weaponViewOfParts(res: UnitCatalog.UnitResource,
                               weapons: List[UnitCatalog.WeaponResource]): Option[Combat.WeaponView] =
        let equipped = PlayerData.equippedWeapon(weapons);
        let proficient = match equipped {
            case None    => true
            case Some(w) => UnitCatalog.proficientWith(res, w#weaponType)
        };
        Combat.weaponView(equipped, proficient)

    /// この味方の装備指輪ボーナス。`combatView` と World read-model 構築が共有する。
    /// `ringEquipped` が false なら zeroBonuses（`PlayerData.equippedRing` が None を返す）。
    pub def equippedRingBonus(data: Data): Ring.Bonuses =
        Ring.bonuses(PlayerData.equippedRing(data))

    /// `combatView` の「装備武器を明示指定する」版。攻撃中に選択した武器（装備中=先頭とは
    /// 限らない）で戦闘予測を計算するため、`BattlePanelUi` から使う。
    pub def combatViewWith(data: Data, weapon: UnitCatalog.WeaponResource): Combat.CombatView =
        Combat.assembleView({
            base   = Combat.baseStatsFrom(data#resource),
            mods   = StatusSystem.combatMods(data#statuses),
            ring   = equippedRingBonus(data),
            hp     = data#hp,
            weapon = Combat.weaponView(Some(weapon),
                        UnitCatalog.proficientWith(data#resource, weapon#weaponType))})

    /// この味方の盤上ビュー（faction = Player）。`Encounter` の join で使う。
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
    pub def displayName(id: Int32): String \ World.WorldQuery =
        get(id) |> Option.map(d -> d#resource#description) |> Option.getWithDefault("味方")

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
    /// unitModulate store 経由で sprite の RGB を乗算する。
    def waitedColor(): Color = UITheme.dimmed()

    /// `waited = false` 時の sprite modulate（白 = 元色）。
    def activeColor(): Color = UITheme.white()

    /// AnimatedSprite2D 相当の「待機」アニメ名。spriteFrames には必ずこれが定義されている前提。
    def idleAnimName(): String = "idle"

    /// `walk_<direction>` アニメ名。spriteFrames に方向別 4 アニメを設定する前提。
    /// 未定義のアニメ名を渡すと表示が止まる (anim 切り替え失敗) ので、
    /// 命名は spriteFrames 側 (units.json) と必ず揃える。
    def walkAnimName(dir: Dir4.Dir4): String = match dir {
        case Dir4.Up    => "walk_up"
        case Dir4.Down  => "walk_down"
        case Dir4.Left  => "walk_left"
        case Dir4.Right => "walk_right"
    }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// マップ（World の terrain / spawnGrid）が seed 済みの World に出撃メンバーを追加する。
    /// 出撃メンバーは `PartySelection.State` に保持された選抜結果を使う。**未選抜のときだけ**
    /// `players` プールから「先頭（ロード）固定 + 残りからランダム 2 体」を抽選して保存し、
    /// 以降の build（フロア移動など）は同じメンバーを再利用する（＝シャッフルは開始時のみ）。
    /// `selectParty` 参照。フレッシュに組み直したい経路（ゲームオーバー / クリア周回）は
    /// 呼び出し側が `PartySelection.State.clear()` してから build する。
    /// 先頭は World の spawnGrid に、残りはその近傍の床セルに配置する。
    /// 各プレイヤーの `initialInventory` を kind 別に分割して `Data.weapons` / `Data.staves` に
    /// 詰め直す（weapons.head が装備中、staves は配列順で持ち物に積まれる）。未定義 id は
    /// 起動時 typo として即 panic する。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                  staffCatalog: Staff.StaffCatalog,
                  consumableCatalog: Consumable.ConsumableCatalog):
            Unit \ {Math.Random, PartySelection.State, World.Command, World.WorldQuery} =
        let selected     = match PartySelection.State.get() {
            case Some(party) => party
            case None        =>
                let rolled = selectParty(UnitCatalog.pool("players", catalog));
                PartySelection.State.put(rolled);
                rolled
        };
        let n            = List.length(selected);
        let world0       = World.WorldQuery.get();
        let spawnGrid    = World.spawnGridOf(world0);
        let terrain      = World.terrainOrBug(world0);
        let cells        = pickPlayerSpawns(spawnGrid, n, terrain);
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
        List.forEach(sp -> addOnePlayer(sp), spawns)

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
                          terrain: MapSnapshot): List[{x = Int32, y = Int32}] =
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
            |> List.filter(c -> MapSnapshot.isFloor(c, terrain))
            |> Board.dedupCells
            |> List.take(n)

    /// プレイヤー 1 体ぶんの World store 群を seed する（spawn/restore の funnel）。
    /// ステータス・テクスチャは `sp#resource`（UnitResource）から取る。
    /// pub: テストから catalog 経由の Spawn 構築 → 配置経路を直接検証するため公開する。
    pub def addOnePlayer(sp: Spawn): Unit \ World.Command =
        // 新規ユニットの初期位置を World へ seed（Cmd.Move=位置 insert）。
        World.Command.emit(World.Cmd.Move(World.refOf(true, sp#id), sp#gridPos));
        // 初期 hp も World へ seed する。
        World.Command.emit(World.Cmd.SetHp(World.refOf(true, sp#id), sp#resource#hp));
        // 初期 followUpUsed=false も seed する。
        World.Command.emit(World.Cmd.SetFollowUpUsed(World.refOf(true, sp#id), false));
        // 初期 waited=false も seed する。
        World.Command.emit(World.Cmd.SetWaited(World.refOf(true, sp#id), false));
        // 初期 usedStairs=false も seed する（floor 遷移しても World が stale な true を保持しないように）。
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
        // テンプレート（classId/resource）と向き/歩数も seed する（dataFromWorld の gate 対象）。
        World.Command.emit(World.Cmd.SetClassId(sp#id, sp#classId));
        World.Command.emit(World.Cmd.SetPlayerResource(sp#id, sp#resource));
        World.Command.emit(World.Cmd.SetFacing(sp#id, Dir4.Down));
        World.Command.emit(World.Cmd.SetMoveSteps(sp#id, 0));
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
            facing            = Dir4.Down,
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
        // 成長 read-model も spawn で seed する（resource 変化サイトは emitBaseStatsFromWorld が束ねて emit）。
        World.Command.emit(World.Cmd.SetGrowth(sp#id,
            {base = LevelSystem.statsOf(res), rates = res#growthRates, name = res#description}));
        // 初期 weaponView/ringBonus も World へ seed する（weapons/rings と同源）。
        // data 構築後に emit（equippedWeaponView/equippedRingBonus は full Data を要する）。ringEquipped=false ゆえ ringBonus=zeroBonuses。
        World.Command.emit(World.Cmd.SetWeaponView(World.refOf(true, sp#id), equippedWeaponView(data)));
        World.Command.emit(World.Cmd.SetRingBonus(World.refOf(true, sp#id), equippedRingBonus(data)));
        // AnimatedSprite2D 相当の個体は初期アニメ（idle）を unitAnim store へ
        // seed し（コマ送りは stepWorld の elapsed 加算＋描画時の frame 導出）、静止画の個体は
        // resource の定数 frame を描画時に読むだけ＝store 不要。描画は RenderWorld.renderUnits が
        // resource + unitAnim/unitFlipH/unitModulate store から描画値を直組みする。
        match res#spriteFrames {
            case Some(_) => World.Command.emit(World.Cmd.SetAnim(World.EntityRef.Player(sp#id), idleAnimName()))
            case None    => ()
        }

    // ────────────────────────────────────────────────────────
    // (D) ロジック — 移動
    // ────────────────────────────────────────────────────────

    /// 指定 id のプレイヤーが現在移動（Position tween）中＝次の入力を受け付けない状態か。
    /// 移動中判定は World（renderPos tween）権威で、`World.isAnimating` が World の Position tween を見る。
    /// 1 フレーム 1 歩のリズムは維持する。
    pub def isMoving(id: Int32): Bool \ World.WorldQuery =
        World.isAnimating(World.EntityRef.Player(id), World.WorldQuery.get())

    /// 指定 id のプレイヤーを `target` グリッドへ移動させる。
    /// `EnemyScene.moveTo` と同じインターフェース。**歩行可否は呼び出し側が確認済み前提**。
    pub def moveToById(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot, slide: Duration.Duration):
            Unit \ {World.Command, World.WorldQuery} =
        // 1 歩移動を sim 書き込みと view 再生に分離する。
        // ── SYSTEM(sim): 位置の唯一権威。`Cmd.Move` が World に書く。
        World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target));
        // ── VIEW(replay): Tween/facing/walk-anim はこの move から導出する純粋な見た目再生。
        //    `SimEvent.Moved` の消費側からも呼ぶ（イベント駆動の再生）。
        replayMoveView(id, target, map, slide)

    /// `SimEvent.Moved` を view 再生する（イベント駆動の再生エントリ）。
    /// System が返した Moved を受けて Tween/facing/anim を再生する。位置の権威は World 側。
    /// 敵の move 再生は別途扱うため現状は no-op。
    pub def replayMovedEvent(event: World.SimEvent, map: MapSnapshot,
                              slide: Duration.Duration): Unit \ {World.Command, World.WorldQuery} =
        match event {
            case World.SimEvent.Moved(World.EntityRef.Player(id), target) =>
                replayMoveView(id, target, map, slide)
            case World.SimEvent.Moved(World.EntityRef.Enemy(_), _) => ()
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
    pub def replayMoveView(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot, slide: Duration.Duration):
            Unit \ {World.Command, World.WorldQuery} =
        // 始点は World の描画位置（tween 中=renderPos）。renderPos 未 seed（一度も滑走していない駒）は
        // 現在セル中心へフォールバック（＝spawn 時の初期描画位置と同値）。
        let w0 = World.WorldQuery.get();
        let startWorld  = World.renderPosOf(World.EntityRef.Player(id), w0)
            |> Option.getWithDefault(MapSnapshot.cellCenter(getGridPos(id)));
        let targetWorld = MapSnapshot.gridToWorld(target, map);
        // 描画位置 tween は World（renderPos）が唯一の権威（読者は `World.visualPosOf` で導出。
        // 敵 `replayEnemyMoveView` と対称）。
        World.moveUnit(World.EntityRef.Player(id), {start = startWorld, target = targetWorld}, Duration.toSeconds(slide));
        // 直前のグリッド座標から target への 1 マス差で方向を決める。
        // 0 ベクトル (= 同じセル) の場合は既存の facing を保つ。
        // 移動前位置は World.prevPosOf（applyCmd の Move が旧位置を自動記録）。
        let prev      = World.prevPosOf(World.EntityRef.Player(id), World.WorldQuery.get())
                            |> Option.getWithDefault(getGridPos(id));
        let dirOpt    = directionOfStep(prev, target);
        // facing は World 権威（Cmd.SetFacing が唯一の writer）。
        // 方向が決まらない (= 同セル移動) ときは現状維持＝emit しない。
        match dirOpt {
            case Some(dir) => World.Command.emit(World.Cmd.SetFacing(id, dir))
            case None      => ()
        };
        // AnimatedSprite2D 相当の unit なら walk_<dir> アニメに切り替える。
        // 方向が決まらなければ (= 同セル移動) 切り替えなし。
        match dirOpt {
            case None    => ()
            case Some(d) => playAnim(id, walkAnimName(d))
        };
        // flipForFacing 付き (= 左向き絵) の駒は左右移動で水平反転する。
        if (flipsForFacing(id)) applyFacingFlip(id, dirOpt) else ()

    /// 指定 id のプレイヤーを `target` グリッドに **瞬間移動** で戻す。
    /// 進行中の Tween があればキャンセルし、描画位置（renderPos）と論理位置（pos）を
    /// 同時に target に揃える。PlayerMoving 中のキャンセルで「選択時の位置」に戻すのに使う。
    pub def snapTo(id: Int32, target: {x = Int32, y = Int32}): Unit \ World.Command =
        let world = MapSnapshot.cellCenter(target);
        // SetRenderPos が進行中の World 描画 tween を破棄しつつ renderPos を
        // target にスナップする（`World.flix` handler で tweens から Position を remove）＝中断後に滑り残らない。
        World.Command.emit(World.Cmd.SetRenderPos(World.EntityRef.Player(id), world));
        World.Command.emit(World.Cmd.Move(World.EntityRef.Player(id), target))

    /// PlayerCursor + Z で味方マスを選択した瞬間の遷移: 選択中味方を SelectedPlayer に
    /// 記録し、PlayerMoving に進む。
    /// overlay (MoveRange / MoveAttackRange / EnemyRange) と Cursor の整理は
    /// `PhaseTransitions.enterPlayerMoving` が担当する (この関数は SelectedPlayer 更新だけ)。
    pub def beginSelection(playerId: Int32):
            Unit \ {TurnPhase.State, SelectedPlayer.State, World.WorldQuery,
                    RangeOverlayState.State, CursorState.State} =
        SelectedPlayer.State.put({
            id     = Some(playerId),
            // 移動開始。元位置を巻き戻しドラフトの底に積む（前の移動の残骸は drafts ごと破棄）
            // 巻き戻し origin は World.posOf（位置は World 権威）。
            drafts = MoveDraft.DraftAction.MovedFrom(playerId,
                World.posOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
                    |> Option.getWithDefault({x = 0, y = 0})) :: Nil,
            gatherActive = false
        });
        PhaseTransitions.enterPlayerMoving()

    /// 「集合」確定で集合（行軍）モードに入る。主人公(id 0)を選択駒に固定し、
    /// 主人公＋生存味方全員の現在位置を巻き戻しドラフト(MovedFrom)に **1 回だけ** 積む。
    /// これにより GatherMove 中に主人公が動き味方が追従しても、X / メニューの「キャンセル」で
    /// `cancelSelection` を呼べば全員が集合開始位置へ戻る（既存の巻き戻し機構を流用）。
    /// 追従の各 1 歩は `moveToById` で動かすだけでドラフトは積まない
    /// （積むと巻き戻しが多重適用され開始位置に戻らなくなる）。
    /// overlay / cursor は `PhaseTransitions.enterGatherMove` が担当する。
    pub def beginGather():
            Unit \ {TurnPhase.State, SelectedPlayer.State, World.WorldQuery, World.Command,
                    RangeOverlayState.State, CursorState.State} =
        // 巻き戻し origin は World 位置（位置は World 権威）。
        let origins = getAll()
            |> List.filter(d -> d#hp > 0)
            |> List.map(d -> MoveDraft.DraftAction.MovedFrom(d#id, d#gridPos));
        SelectedPlayer.State.put({id = Some(lordId()), drafts = origins, gatherActive = true});
        // 追従の移動距離カウントを 0 から始める（味方は自分の moveTiles 歩まで追従して非アクティブ化）。
        resetAllMoveStepsTaken();
        PhaseTransitions.enterGatherMove()

    /// PlayerMoving + X: 選択駒を origin に瞬間移動で戻し、選択解除して PlayerCursor に戻す。
    /// 「キャンセル → 再選択の繰り返しで実質ターン制限なしの自由移動」を防ぐ。
    /// overlay / cursor の片付けは `PhaseTransitions.enterPlayerCursor` が担当。
    pub def cancelSelection():
            Unit \ {TurnPhase.State, SelectedPlayer.State, CursorState.State,
                    PlayerData.PartyQuery, World.Command, World.WorldQuery, RangeOverlayState.State} =
        // この移動で積んだ可逆ドラフトを新しい順に巻き戻す（拾得→元位置への復帰など）。
        // 「拾ってからキャンセルしたら拾っていないことにする」もこの一括巻き戻しで実現。
        let drafts   = SelectedPlayer.State.get()#drafts;
        List.forEach(a -> revertDraftAction(a), drafts);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        PhaseTransitions.enterPlayerCursor()

    /// 集合（行軍）モードで「まだ誰も開始位置から動いていない」か。
    /// 集合直後（手動確定 / ターン継続での自動再突入）に C で個別行動モードへ戻せるかの判定。
    /// `gatherActive` でなければ false。`beginGather` が積んだ各 `MovedFrom` 起点と現在位置を
    /// 比べ、1 体でも origin から動いていれば false（移動を始めたら切替不可）。
    pub def gatherNotMovedYet(): Bool \ {SelectedPlayer.State, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        if (not sel#gatherActive) false
        else {
            // 現在位置は World 由来 Data（origin との一致比較）。
            let living = getAll() |> List.filter(d -> d#hp > 0);
            not MoveDraft.anyMovedFromOrigin(living, sel#drafts)
        }

    /// 移動ドラフト 1 件を巻き戻す。巻き戻しの実体はここに集約する
    /// （新しい可逆操作を足すときはこの match に 1 分岐追加するだけ）。
    ///   - `MovedFrom`: origin に snapTo で戻し、walk 表示を idle に戻す
    ///     （移動中の walk_<dir> のままだと「キャンセル後に動いてないのに横向き」になる）
    ///   - `PickedUp` : 床へ戻し（`GroundItems.respawn`）+ 在庫末尾の仮取得分を取り消す
    def revertDraftAction(action: MoveDraft.DraftAction):
            Unit \ {World.Command, World.WorldQuery} =
        match action {
            case MoveDraft.DraftAction.MovedFrom(id, cell)              =>
                snapTo(id, cell);
                playAnim(id, idleAnimName())
            case MoveDraft.DraftAction.PickedUp(pid, cell, itemKey, kind) =>
                GroundItems.respawn(cell, itemKey, kind);
                removeLastInventoryItem(pid, kind)
            case MoveDraft.DraftAction.Equipped(pid, idx)               =>
                // 装備 = moveToHead(idx) の逆。World の先頭を idx 位置へ戻す（equipWeapon と対称）。
                putWeapons(pid, moveHeadTo(idx, weaponsW(pid)))
            case MoveDraft.DraftAction.Dropped(pid, kind, item)        =>
                // 捨てる = removeAt(idx) の逆。元 idx に挿入し直す。
                insertInventoryItem(pid, kind, item)
            case MoveDraft.DraftAction.Traded(t)                       =>
                // こうかん = swapItem の逆。相手末尾の付加分を除去 → 双方の元 idx へ戻す。
                // (逆順 revert なので付加分は各リストの末尾に在る前提が成立する)
                removeLastInventoryItem(t#partnerId, t#selfItem);
                insertInventoryItem(t#selfId, t#selfKind, t#selfItem);
                match (t#partnerKind, t#partnerItem) {
                    case (Some(pk), Some(pi)) =>
                        removeLastInventoryItem(t#selfId, pi);
                        insertInventoryItem(t#partnerId, pk, pi)
                    case _                    => ()
                }
            case MoveDraft.DraftAction.GatherWaited(id)                =>
                // 集合中の移動距離切れで非アクティブ化した味方を再アクティブに戻す。
                setActive(id)
        }

    /// インベントリの先頭から、距離 `distance` に射程が届く最初の武器の index を返す。
    /// 届く武器が無ければ None。攻撃中の武器選択・進入時装備で共用する純粋関数。
    pub def firstWeaponIdxReaching(data: Data, distance: Int32): Option[Int32] =
        data#weapons
            |> List.zipWithIndex
            |> List.findMap(p -> match p {
                case (i, w) => if (Weapon.inRange(distance, w#range)) Some(i) else None
            })

    /// 攻撃モーション中のプレイヤーが居れば true。
    /// EnemyTurnDriver の「敵の行動を進めて良いか」のガードに使う
    /// （味方の反撃モーション中はキューを進めない）。
    pub def anyAttacking(): Bool \ World.WorldQuery =
        World.anyPlayerAttacking(World.WorldQuery.get())

    // ────────────────────────────────────────────────────────
    // (E) 状態クエリ・更新
    // ────────────────────────────────────────────────────────

    /// 在籍している全プレイヤーの Data を id 昇順で返す（World store 群から再構築）。
    pub def getAll(): List[Data] \ World.WorldQuery =
        let world = World.WorldQuery.get();
        World.playerIdsOf(world) |> List.filterMap(id -> World.dataFromWorld(id, world))

    /// id を持つプレイヤーの Data を取り出す。未登録なら None。
    pub def get(id: Int32): Option[Data] \ World.WorldQuery =
        World.dataFromWorld(id, World.WorldQuery.get())

    /// hp 書込 funnel。純 hp 書込（回復/吸血/効果回復など）の置換先。
    /// 複合書込（hp＋他 field）は呼び出し側で単独 emit する。
    pub def setHp(id: Int32, newHp: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(id), newHp))

    // ────────────────────────────────────────────────────────
    // 在庫・statuses の write funnel（World 単独権威）
    //   各 writer は「World の現在値を読む → 純粋変換 → Cmd で書く」。Cmd は worldRef へ即時適用
    //   される（read-after-write）ため、同フレーム内の連鎖書込も正しく合成される。
    // ────────────────────────────────────────────────────────

    /// World の武器在庫（未登録は Nil）。writer の read-modify-write 用。
    pub def weaponsW(id: Int32): List[UnitCatalog.WeaponResource] \ World.WorldQuery =
        World.weaponsOf(World.EntityRef.Player(id), World.WorldQuery.get()) |> Option.getWithDefault(Nil)

    /// World の杖在庫（未登録は Nil）。
    pub def stavesW(id: Int32): List[Staff.StaffResource] \ World.WorldQuery =
        World.stavesOf(World.EntityRef.Player(id), World.WorldQuery.get()) |> Option.getWithDefault(Nil)

    /// World の消費アイテム在庫（未登録は Nil）。
    pub def consumablesW(id: Int32): List[Consumable.ConsumableResource] \ World.WorldQuery =
        World.consumablesOf(World.EntityRef.Player(id), World.WorldQuery.get()) |> Option.getWithDefault(Nil)

    /// World の指輪在庫（未登録は Nil）。
    pub def ringsW(id: Int32): List[Ring.RingResource] \ World.WorldQuery =
        World.ringsOf(World.EntityRef.Player(id), World.WorldQuery.get()) |> Option.getWithDefault(Nil)

    /// World の指輪装備フラグ（未登録は false）。
    pub def ringEquippedW(id: Int32): Bool \ World.WorldQuery =
        World.ringEquippedOf(World.EntityRef.Player(id), World.WorldQuery.get()) |> Option.getWithDefault(false)

    /// weapons を World へ書き、装備武器投影（weaponView）も 1:1 で co-emit する（網羅を構造保証）。
    pub def putWeapons(playerId: Int32, ws: List[UnitCatalog.WeaponResource]): Unit \ {World.Command, World.WorldQuery} =
        World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(playerId), ws));
        emitWeaponViewFromWorld(playerId)

    /// 装備武器投影を World の現在値（resource テンプレ＋weapons）から導いて `Cmd.SetWeaponView` を emit する。
    /// weapons 書込サイト（putWeapons/carry/CombatDriver 耐久消費）と 1:1 で呼ぶ。
    pub def emitWeaponViewFromWorld(playerId: Int32): Unit \ {World.Command, World.WorldQuery} =
        match World.playerResourceOf(World.EntityRef.Player(playerId), World.WorldQuery.get()) {
            case Some(res) =>
                World.Command.emit(World.Cmd.SetWeaponView(World.EntityRef.Player(playerId),
                    weaponViewOfParts(res, weaponsW(playerId))))
            case None      => ()
        }

    /// 装備指輪ボーナスを World の現在値（rings＋ringEquipped）から導いて `Cmd.SetRingBonus` を emit する。
    /// rings/ringEquipped 書込サイトと 1:1 で呼ぶ。
    pub def emitRingBonusFromWorld(playerId: Int32): Unit \ {World.Command, World.WorldQuery} =
        World.Command.emit(World.Cmd.SetRingBonus(World.EntityRef.Player(playerId),
            Ring.bonuses(PlayerData.equippedRing(
                {rings = ringsW(playerId), ringEquipped = ringEquippedW(playerId)}))))

    /// staves / consumables / rings / ringEquipped の write funnel（putWeapons 同型）。
    pub def putStaves(playerId: Int32, xs: List[Staff.StaffResource]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetStaves(World.EntityRef.Player(playerId), xs))
    pub def putConsumables(playerId: Int32, xs: List[Consumable.ConsumableResource]): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetConsumables(World.EntityRef.Player(playerId), xs))
    pub def putRings(playerId: Int32, xs: List[Ring.RingResource]): Unit \ {World.Command, World.WorldQuery} =
        World.Command.emit(World.Cmd.SetRings(World.EntityRef.Player(playerId), xs));
        // ringBonus は装備指輪由来＝rings funnel と 1:1 で SetRingBonus も co-emit。
        emitRingBonusFromWorld(playerId)
    pub def putRingEquipped(playerId: Int32, b: Bool): Unit \ {World.Command, World.WorldQuery} =
        World.Command.emit(World.Cmd.SetRingEquipped(World.EntityRef.Player(playerId), b));
        // ringBonus は ringEquipped 切替でも変わる＝ringEquipped funnel とも 1:1 で SetRingBonus を co-emit。
        emitRingBonusFromWorld(playerId)

    /// baseStats 書込 funnel。World の現在 resource（mutation 適用後）を読み戻して
    /// `Cmd.SetBaseStats` を emit する（read-after-mutate 流儀）。
    /// level-up（CombatDriver）/carry 復元/snapshot 復元/復活など resource を書き換えた直後に呼ぶ。pub（CombatDriver から）。
    pub def emitBaseStatsFromWorld(playerId: Int32): Unit \ {World.Command, World.WorldQuery} =
        match World.playerResourceOf(World.EntityRef.Player(playerId), World.WorldQuery.get()) {
            case Some(res) =>
                World.Command.emit(World.Cmd.SetBaseStats(World.EntityRef.Player(playerId), Combat.baseStatsFrom(res)));
                // resource が変わる全サイトで growth read-model も束ねて更新する。
                World.Command.emit(World.Cmd.SetGrowth(playerId,
                    {base = LevelSystem.statsOf(res), rates = res#growthRates, name = res#description}))
            case None    => ()
        }

    /// statusEffects 書込 funnel。World の現在 statuses に純粋変換 `f` を適用し、`Cmd.Seed`
    /// （全置換 replace 意味論）で書く。各操作を個別 Cmd に写さず変更後の全リストで置換＝網羅が単純化し漏れにくい。
    /// statuses を書く全サイト（add/clearImmobilized/bind）が使う。pub（StaffCast/CombatDriver 起点から）。
    pub def updateStatuses(playerId: Int32,
                            f: StatusSystem.StatusEffects -> StatusSystem.StatusEffects):
            Unit \ {World.Command, World.WorldQuery} =
        let ref = World.EntityRef.Player(playerId);
        let cur = World.statusEffectsOf(ref, World.WorldQuery.get());
        World.Command.emit(World.Cmd.Seed(ref, f(cur)))

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
    /// waited は World 直読み（read-after-write でフレーム中の SetWaited も即時見える）。
    pub def firstActive(): Option[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        getAll()
            |> List.filter(d -> not (World.waitedOf(World.EntityRef.Player(d#id), w)
                                        |> Option.getWithDefault(false)))
            |> List.sortBy(d -> d#id)
            |> List.head

    /// `firstActive` の「`excludeId` を行動済み扱いにする」変種。
    /// waited を World 直読みにしたため「たった今 waited 化した駒」も store で即時 true になり
    /// 除外は冗長になったが、防御的に維持（呼び出し側 API 据置・二重に安全）。
    pub def firstActiveExcluding(excludeId: Option[Int32]):
            Option[Data] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        getAll()
            |> List.filter(d -> not (World.waitedOf(World.EntityRef.Player(d#id), w)
                                        |> Option.getWithDefault(false))
                                and Some(d#id) != excludeId)
            |> List.sortBy(d -> d#id)
            |> List.head

    /// 主人公(lordId=0)が集合（行軍）を率いられる状態か。集合は `beginGather` が主人公を
    /// 選択駒に固定するので、主人公が戦闘不能(hp<=0) / 階段退場(hidden) / かなしばり(immobilized)
    /// のいずれかなら率いられない。集合のターン跨ぎ自動継続の前提チェックに使う。
    pub def lordReadyToGather(): Bool \ World.WorldQuery =
        let w = World.WorldQuery.get();
        match get(lordId()) {
            case Some(d) =>
                d#hp > 0 and not d#hidden
                    and not StatusSystem.isImmobilized(World.statusEffectsOf(World.EntityRef.Player(lordId()), w))
            case None    => false
        }

    /// 敵攻撃で HP=0 になったプレイヤーを盤面から取り除く。`killed` は
    /// `CombatDriver.applyEnemyAttackHit` が返した死亡 id のリスト (通常 1 要素)。
    /// 選択中プレイヤーが含まれていれば (反撃で死亡したケース) 選択も解除する。
    /// 次のいずれかでゲームオーバー (`CustomEffects.GameOverRequest.request`) を emit し、
    /// handler 側でマップ・配置を 1F からフルリビルドする:
    ///   - 味方が全員脱落した
    ///   - ロード（主人公 = `lordId()`）が倒れた（他の味方が残っていても 1F やり直し）
    pub def removeDeadAndCheckGameOver(killed: List[Int32]):
            Unit \ {CustomEffects.GameOverRequest, SelectedPlayer.State,
                    GameLogger.GameLogger, World.Command, World.WorldQuery} =
        if (List.isEmpty(killed)) ()
        else {
            // 除去の前に、現在いる全味方の位置を記録する（女神の加護の「その場復活」用）。
            // 死亡する駒もこの時点ではまだ在籍しており、最後の位置が取れる。handler 側で蓄積する。
            CustomEffects.GameOverRequest.markDeaths(
                getAll() |> List.map(d -> (d#id, d#gridPos)) |> List.toMap);
            // 蘇生薬(AutoRevive)を所持している脱落者は、取り除く前に全回復して復活させる。
            // 復活した分は killed から外れ、ロード戦死や全滅もそのぶん回避される。
            // 蘇生薬の所持判定は World 在庫。
            let units = killed |> List.filterMap(id ->
                get(id) |> Option.map(d -> {id = id, consumables = consumablesW(d#id)}));
            let revive = Consumable.tryReviveAll(units);
            List.forEach(r -> reviveOne(r#id, r#consumables), revive#revived);
            let stillDead = revive#stillDead;
            if (List.isEmpty(stillDead)) ()
            else {
                // World の全 store から除去する。
                List.forEach(id -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Player(id))), stillDead);
                let selectedKilled = match SelectedPlayer.State.get()#id {
                    case Some(id) => List.exists(k -> k == id, stillDead)
                    case None     => false
                };
                if (selectedKilled)
                    SelectedPlayer.State.put(SelectedPlayer.cleared())
                else ();
                let lordDead = List.exists(k -> k == lordId(), stillDead);
                if (List.isEmpty(getAll()) or lordDead)
                    CustomEffects.GameOverRequest.request()
                else ()
            }
        }

    /// 蘇生薬で復活する味方 1 体の反映: HP を最大まで戻し、蘇生薬消費後の
    /// インベントリへ差し替え、復活ログを出す。`removeDeadAndCheckGameOver` 専用。
    def reviveOne(id: Int32, newConsumables: List[Consumable.ConsumableResource]):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match get(id) {
            case None    => ()
            case Some(d) =>
                let maxHp = d#resource#hp;
                World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(id), maxHp));  // 復活 hp を World へ
                GameLogger.playerLog("${displayName(id)}は 蘇生薬で復活した");
                // 蘇生薬消費後の在庫は World 権威。
                putConsumables(id, newConsumables)
        }

    /// プレイヤーを「行動済み」にして sprite を灰色 modulate にする。
    /// AnimatedSprite2D 相当の unit はここで idle アニメに戻す (= 待機モーション表示)。
    /// PlayerAttack 確定 / スキップ時に呼ばれる。
    pub def setWaited(id: Int32): Unit \ World.Command =
        // waited は World 権威（Cmd.SetWaited が唯一の source）。
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), true));
        setSpriteModulate(id, waitedColor());
        playAnim(id, idleAnimName())

    /// プレイヤー 1 体を「行動可能(アクティブ)」に戻す。`waited` を下ろし、sprite/HP ゲージを
    /// 通常色へ、idle アニメへ戻す（`setWaited` の逆）。集合キャンセルの巻き戻しで使う。
    pub def setActive(id: Int32): Unit \ World.Command =
        // waited は World 権威。
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), false));
        setSpriteModulate(id, activeColor());
        playAnim(id, idleAnimName())

    /// 完全停止（かなしばり）を解除する。被攻撃 or 被投擲の瞬間に呼ぶ。
    /// 停止していなければ no-op（他の時限ステータスは残す）。
    pub def releaseBind(id: Int32): Unit \ {World.Command, World.WorldQuery} =
        // statuses は World 権威＝現在値に clearImmobilized を適用して Seed（全置換）で書く。
        updateStatuses(id, StatusSystem.clearImmobilized)

    /// 全プレイヤーの waited をクリアし、sprite を白に戻す。
    /// ターン開始時に呼ばれ、AnimatedSprite2D 相当の unit は idle アニメに戻す
    /// (= 新ターン開始時の待機モーション)。
    /// 敵ターン終了後に呼ぶ（次の味方ターン開始）。
    pub def clearAllWaited(): Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        // 階段で退場した味方 (usedStairs) は「行動済み」を維持し、敵ターン後も再行動させない。
        // usedStairs は World 権威で読む。
        let w0 = World.WorldQuery.get();
        let ids = getAll()
            |> List.filter(d -> not (World.usedStairsOf(World.EntityRef.Player(d#id), w0)
                                        |> Option.getWithDefault(false)))
            |> List.map(d -> d#id);
        // 味方ターン開始 tick を World へ発行する（statuses のターン開始減算）。
        World.Command.emit(World.Cmd.TickPlayers(ids));
        List.forEach(id -> {
            World.Command.emit(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(id), false));  // reset を World へ
            World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), false));  // ターン開始で waited 解除
            setSpriteModulate(id, activeColor());
            playAnim(id, idleAnimName())
        }, ids);
        // 味方ターン開始時に、いやしのリングを装備した味方の HP を回復する。
        applyRingRegen()

    /// いやしのリングを装備した味方の HP を回復する（最大 HP でクランプ）。味方ターン開始で呼ぶ。
    /// 実際に回復した味方はログに出す。
    pub def applyRingRegen():
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        let ids = getAll() |> List.map(d -> d#id);
        List.forEach(id -> regenOnePlayer(id), ids)

    /// 1 味方ぶんの Mend 回復。Mend 以外 / 未装備なら no-op（match は入れ子にしない）。
    /// 判定読み（装備指輪/hp）は PartyQuery（World 由来）経由。
    def regenOnePlayer(id: Int32):
            Unit \ {GameLogger.GameLogger, World.Command, PlayerData.PartyQuery} =
        match PlayerData.PartyQuery.get(id) {
            case None    => ()
            case Some(d) => mendOnePlayer(id, d)
        }

    /// 回復量を計算して適用するヘルパー（regenOnePlayer から呼ぶ）。
    /// 満タン等で実際に HP が増えないときはログも出さない。
    def mendOnePlayer(id: Int32, d: Data):
            Unit \ {GameLogger.GameLogger, World.Command} =
        let amt = Ring.mendAmount(PlayerData.equippedRing(d));
        let newHp = Combat.heal(d#hp, d#resource#hp, amt)#newHp;
        if (amt <= 0 or newHp <= d#hp) ()
        else {
            GameLogger.playerLog("${d#resource#description} は いやしのリングで HP+${newHp - d#hp}");
            setHp(id, newHp)
        }

    /// 全プレイヤーの sprite / HP ゲージを通常色(active)に戻す。`waited` フラグは変えない。
    /// 敵フェーズ中に「味方の行動済み灰色」を消してアクティブに見せるために使う
    /// （待機しているという扱い自体は残し、見た目だけ通常色に戻す。階段で退場済みの味方は対象外）。
    pub def showAllActive(): Unit \ {World.Command, World.WorldQuery} =
        // usedStairs は World 権威で読む。
        let w = World.WorldQuery.get();
        let ids = getAll()
            |> List.filter(d -> not (World.usedStairsOf(World.EntityRef.Player(d#id), w)
                                        |> Option.getWithDefault(false)))
            |> List.map(d -> d#id);
        List.forEach(id -> setSpriteModulate(id, activeColor()), ids)

    /// AutoMove で消費した移動歩数を記録するための setter（World 権威・SetMoveSteps が唯一の writer）。
    pub def setMoveStepsTaken(id: Int32, steps: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetMoveSteps(id, steps))

    /// 全プレイヤーの moveStepsTaken を 0 にリセットする。
    /// プレイヤーターン開始時 / AutoMove キャンセル時に呼ぶ。
    pub def resetAllMoveStepsTaken(): Unit \ {World.Command, World.WorldQuery} =
        let ids = getAll() |> List.map(d -> d#id);
        List.forEach(id -> World.Command.emit(World.Cmd.SetMoveSteps(id, 0)), ids)

    // ────────────────────────────────────────────────────────
    // (E') 盤面からの一時退場 — 階段退場(useStairs)の表示制御
    // ────────────────────────────────────────────────────────

    /// 味方 id の表示/退避を切り替える。`flag = true` で hidden を立てる(階段で退場して消える)。
    /// `flag = false` で元に戻す。描画側（本体 sprite / HPBar / 武器アイコン）は
    /// hidden（playerHidden store）を可視ゲートに読む。
    pub def setHidden(id: Int32, flag: Bool): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetHidden(World.EntityRef.Player(id), flag))

    /// 暗転色を World store（unitModulate）へ emit する
    /// （本体描画/HP バー/武器アイコンが同じ store を読む）。
    def setSpriteModulate(id: Int32, color: Color): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetModulate(World.EntityRef.Player(id), color))

    /// 再生アニメを World store（unitAnim）へ emit（play 意味論は applyCmd が再現）。
    /// spriteFrames を持たない unit でも emit 自体は無害（描画側が resource を見て無視）。
    def playAnim(id: Int32, animName: String): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetAnim(World.EntityRef.Player(id), animName))

    /// 左右反転を World store（unitFlipH）へ emit。
    def setSpriteFlipH(id: Int32, h: Bool): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetFlipH(World.EntityRef.Player(id), h))

    /// 進行方向に応じて「左向きの絵」を水平反転する。Right で flipH=true (右向き)、
    /// Left で flipH=false (左向き=素材そのまま)。Up/Down/None は現状維持。
    /// `sprite#flipForFacing` を持たない駒では呼び出し側 (`flipsForFacing`) が抑止する。
    def applyFacingFlip(id: Int32, dirOpt: Option[Dir4.Dir4]): Unit \ World.Command =
        match dirOpt {
            case Some(Dir4.Right) => setSpriteFlipH(id, true)
            case Some(Dir4.Left)  => setSpriteFlipH(id, false)
            case _                           => ()
        }

    /// 指定 id の味方が「左向き絵を右移動で反転」する駒か (resource の sprite フラグ)。
    def flipsForFacing(id: Int32): Bool \ World.WorldQuery =
        World.playerResourceOf(World.EntityRef.Player(id), World.WorldQuery.get())
            |> Option.map(res -> res#sprite#flipForFacing)
            |> Option.getWithDefault(false)

    /// 1 マス分の差分 (prev → target) から進行方向を求める。
    /// 同セル / 0 ベクトルは None。斜めは便宜上 |x| >= |y| を横優先で扱う
    /// (FE では基本的に直交 1 マスのみ移動するので通常通らない)。
    def directionOfStep(prev: {x = Int32, y = Int32},
                         target: {x = Int32, y = Int32}): Option[Dir4.Dir4] =
        let dx = target#x - prev#x;
        let dy = target#y - prev#y;
        if (dx == 0 and dy == 0) None
        else if (Int32.abs(dx) >= Int32.abs(dy))
            if (dx > 0) Some(Dir4.Right)
            else Some(Dir4.Left)
        else
            if (dy > 0) Some(Dir4.Down)
            else Some(Dir4.Up)

    // ────────────────────────────────────────────────────────
    // (F) ゲームオーバー時のリセット
    // ────────────────────────────────────────────────────────

    /// 現在の全プレイヤーの spawn 情報（id / gridPos / resource / weapons / staves）を抽出する。
    /// `Game.start` で初回 build 直後に呼んで保存する。
    /// 攻撃前に取られる前提でインベントリは無破損の初期値。respawn ではこの値で復元される。
    pub def snapshotSpawns(): List[Spawn] \ World.WorldQuery =
        getAll()
            |> List.map(d ->
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
    /// 描画・盤面・敵範囲・占有・経路・カーソルから外す。
    /// `waited` も立てるので「行動済み」扱いになり、`firstActive` の対象から
    /// 外れて以後このフロアでは動けない。`clearAllWaited` は usedStairs を維持するため
    /// 敵ターンを跨いでも退場状態のままになる。次フロア構築 (addOnePlayer) で全て false に戻る。
    pub def useStairs(id: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetWaited(World.EntityRef.Player(id), true));  // 階段退場で waited を World へ
        // waited / usedStairs はともに World 権威（Cmd が唯一の source）。
        World.Command.emit(World.Cmd.SetUsedStairs(World.EntityRef.Player(id), true));
        setHidden(id, true)

    /// 生存している味方が「全員」階段を使ったか（= このフロアの終了条件）。
    /// 生存者が 1 人も居ない場合は false（それは全滅 = ゲームオーバー側の扱い）。
    /// hp / usedStairs は World 権威。
    pub def allLivingUsedStairs(): Bool \ World.WorldQuery =
        let w = World.WorldQuery.get();
        let living = getAll() |> List.filter(d -> d#hp > 0);
        not List.isEmpty(living) and List.forAll(d ->
            World.usedStairsOf(World.EntityRef.Player(d#id), w) |> Option.getWithDefault(false), living)

    /// 現在の生存味方の引き継ぎ用ステータス（HP / 武器 / 持ち物）を抽出する。
    /// 次フロアへ進む直前に呼び、構築後の `reconcileWithCarry` で復元する。
    pub def snapshotCarry(): List[CarryData] \ World.WorldQuery =
        getAll()
            |> List.filter(d -> d#hp > 0)
            |> List.map(d ->
                ({id = d#id, hp = d#hp, weapons = d#weapons, staves = d#staves,
                  consumables = d#consumables, rings = d#rings,
                  ringEquipped = d#ringEquipped,
                  level = d#level, exp = d#exp,
                  stats = LevelSystem.statsOf(d#resource)}: CarryData))

    /// 次フロアを通常 build した直後の World に、前フロアの引き継ぎ値を反映する。
    ///   - carry に居ない id（前フロアで戦死）の味方を除去する
    ///   - 生存 id は HP / 武器 / 持ち物 / レベル / EXP / 成長後ステータスを carry で上書きする
    /// `waited` / `usedStairs` / `hidden` / `moveStepsTaken` は addOnePlayer が false / 0 で
    /// 作り直しているのでリセット不要（= フロア開始時に全員再行動可・たいきリセット）。
    pub def reconcileWithCarry(carry: List[CarryData]): Unit \ {World.Command, World.WorldQuery} =
        let carryIds = carry |> List.map(c -> c#id);
        let deadIds = getAll()
            |> List.filter(d -> not List.exists(id -> id == d#id, carryIds))
            |> List.map(d -> d#id);
        // 前フロア戦死者の store 掃除。
        List.forEach(id -> World.Command.emit(World.Cmd.Despawn(World.EntityRef.Player(id))), deadIds);
        List.forEach(c -> {
            World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(c#id), c#hp));  // carry hp を World へ
            World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(c#id), c#level, c#exp));  // carry 進行度
            World.Command.emit(World.Cmd.SetWeapons(World.EntityRef.Player(c#id), c#weapons));  // carry weapons を World へ
            World.Command.emit(World.Cmd.SetStaves(World.EntityRef.Player(c#id), c#staves));  // carry inventory を World へ
            World.Command.emit(World.Cmd.SetConsumables(World.EntityRef.Player(c#id), c#consumables));
            World.Command.emit(World.Cmd.SetRings(World.EntityRef.Player(c#id), c#rings));
            World.Command.emit(World.Cmd.SetRingEquipped(World.EntityRef.Player(c#id), c#ringEquipped));
            // carry の成長後 stats を resource テンプレへ反映する（addOnePlayer は base resource を seed 済み）。
            match World.playerResourceOf(World.EntityRef.Player(c#id), World.WorldQuery.get()) {
                case Some(res) => World.Command.emit(World.Cmd.SetPlayerResource(c#id, LevelSystem.withStats(c#stats, res)))
                case None      => ()
            };
            // resource が変わった＝baseStats の source が変わったので read-after-mutate で emit。
            emitBaseStatsFromWorld(c#id);
            // carry の weapons/rings/ringEquipped 復元に 1:1 で weaponView/ringBonus も更新する。
            emitWeaponViewFromWorld(c#id);
            emitRingBonusFromWorld(c#id)
        }, carry)

    /// スナップショットの味方リストから決定論的に再配置する（乱数なし）。
    /// base resource を `classId` で引き、`addOnePlayer` で土台を置いてから snap の動的値
    /// （HP / 装備 / 持ち物 / レベル / EXP / 成長後ステータス / 向き / 時限ステータス）を上書きする。
    /// 進入時スナップショット（フロア最初から）では向き＝既定・statuses 空なので overlay しても不変、
    /// 中断セーブからの再開では中断時点の現在値がそのまま復元される（snapshot が単一の真実源）。
    pub def addFromSnaps(snaps: List[FloorSnapshot.PlayerSnap],
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog): Unit \ {World.Command, World.WorldQuery} =
        List.forEach(snap ->
            placeOneFromSnap(snap, catalog, staffCatalog, consumableCatalog, ringCatalog),
            snaps)

    /// 味方 1 体を snap から配置する。base resource を classId で引いて `addOnePlayer` で土台を置き、
    /// snap の動的値（HP / レベル / EXP / 成長後ステータス / 装備中フラグ / 向き / 時限ステータス）を
    /// 上書きする（`reconcileWithCarry` の 1 体版 ＋ 中断再開用の向き・statuses 復元）。
    /// 進入時スナップショットでは向き＝既定・statuses 空なので overlay しても不変。
    def placeOneFromSnap(snap: FloorSnapshot.PlayerSnap,
                          catalog: UnitCatalog.UnitCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog): Unit \ {World.Command, World.WorldQuery} =
        let sp = snapToPlayerSpawn(snap, catalog, staffCatalog, consumableCatalog, ringCatalog);
        addOnePlayer(sp);
        // 復元値の World write は **addOnePlayer の後**に emit する。
        // addOnePlayer が spawn 値(SetHp(maxHp)/SetProgress(level,0)/SetFacing(Down)/SetPlayerResource(base)) を
        // emit するので、先に出すと worldRef で spawn 値に上書きされてしまう。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(snap#id), snap#hp));
        World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(snap#id), snap#level, snap#exp));
        // 復元 facing / 復元 statuses は World 権威。
        World.Command.emit(World.Cmd.SetFacing(snap#id, snap#facing));
        World.Command.emit(World.Cmd.Seed(World.EntityRef.Player(snap#id), snap#statuses));
        // 成長後 stats の resource を World テンプレへ反映する。
        World.Command.emit(World.Cmd.SetPlayerResource(snap#id, LevelSystem.withStats(snap#stats, sp#resource)));
        // resource が成長後 stats に変わった＝baseStats source 変化。hp/progress 同様
        // addOnePlayer の後に emit する（spawn 値上書き回避）。
        emitBaseStatsFromWorld(snap#id);
        // 復元 ringEquipped は World 権威（addOnePlayer は false を seed → snap 値で上書き）。
        putRingEquipped(snap#id, snap#ringEquipped)

    /// `PlayerSnap` を配置用 `Spawn`（base resource ＋ 解決済み持ち物）に変換する。
    /// `placeOneFromSnap`（フロア最初から）と `reviveOneAt`（女神の加護）が共有する。
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

    /// 女神の加護: スナップショットの全メンバーを **リーダー(`lordId`)の周り** に再配置して
    /// 全快復活させる（無敵は付与しない）。リーダーを `leaderPos`（倒れたその場）に置き、
    /// 残りはそこから最も近い空き床セルへ順に詰める。敵は呼び出し側で一掃済み前提なので、壁と味方同士の
    /// 重なりだけを避ければよい。マップ・アイテムは現在の World のまま
    /// （各 store は addOnePlayer の再 seed で全上書きされる）。
    pub def reviveAroundLeader(snaps: List[FloorSnapshot.PlayerSnap],
                                catalog: UnitCatalog.UnitCatalog,
                                staffCatalog: Staff.StaffCatalog,
                                consumableCatalog: Consumable.ConsumableCatalog,
                                ringCatalog: Ring.RingCatalog,
                                leaderPos: {x = Int32, y = Int32}): Unit \ {World.Command, World.WorldQuery} =
        let terrain = World.terrainOrBug(World.WorldQuery.get());
        // リーダーを先頭にして、近い順に空きセルを割り当てる（先頭がちょうど leaderPos に乗る）。
        let ordered = leaderFirst(snaps);
        let _ = List.foldLeft((taken, snap) -> {
            let cell = nearestFreeCell(leaderPos, terrain, taken);
            reviveOneAt(snap, cell, catalog, staffCatalog, consumableCatalog, ringCatalog);
            cell :: taken
        }, (Nil: List[{x = Int32, y = Int32}]), ordered);
        ()

    /// `lordId` の味方を先頭に並べ替える（残りは元の順を保つ）。
    def leaderFirst(snaps: List[FloorSnapshot.PlayerSnap]): List[FloorSnapshot.PlayerSnap] =
        let (lead, rest) = List.partition(s -> s#id == lordId(), snaps);
        List.append(lead, rest)

    /// `origin` に最も近い空き床セルを返す。床（`isFloor`）かつ `taken`（既配置の味方）でないセルを
    /// `origin` 周辺の箱から集め、`origin` からのマンハッタン距離が小さい順に選ぶ。候補ゼロなら `origin`。
    def nearestFreeCell(origin: {x = Int32, y = Int32}, terrain: MapSnapshot,
                         taken: List[{x = Int32, y = Int32}]): {x = Int32, y = Int32} =
        let r = 12;
        let candidates = List.range(origin#x - r, origin#x + r + 1)
            |> List.flatMap(x -> List.range(origin#y - r, origin#y + r + 1)
                |> List.map(y -> ({x = x, y = y}: {x = Int32, y = Int32})));
        let free = candidates
            |> List.filter(c -> MapSnapshot.isFloor(c, terrain) and not sameCellExists(c, taken))
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
                     ringCatalog: Ring.RingCatalog): Unit \ {World.Command, World.WorldQuery} =
        let sp = {gridPos = cell | snapToPlayerSpawn(snap, catalog, staffCatalog, consumableCatalog, ringCatalog)};
        addOnePlayer(sp);
        // 復元 hp/progress の World emit は addOnePlayer の後（spawn 値上書き回避・placeOneFromSnap と同じ）。
        World.Command.emit(World.Cmd.SetHp(World.EntityRef.Player(snap#id), snap#stats#hp));
        World.Command.emit(World.Cmd.SetProgress(World.EntityRef.Player(snap#id), snap#level, snap#exp));
        // 成長後 stats の resource を World テンプレへ反映する（placeOneFromSnap と同型）。
        World.Command.emit(World.Cmd.SetPlayerResource(snap#id, LevelSystem.withStats(snap#stats, sp#resource)));
        // resource が成長後 stats に変わった＝baseStats source 変化（placeOneFromSnap と同型）。
        emitBaseStatsFromWorld(snap#id);
        // 復元 ringEquipped は World 権威（placeOneFromSnap と同型）。
        putRingEquipped(snap#id, snap#ringEquipped)

    /// 現在の全味方を `PlayerSnap` 列に射影する（スナップショット保存用）。持ち物 resource は
    /// 各 catalog の `idOf`（name 逆引き）で id 化し、耐久など動的値を併せて保持する。
    /// セーブ**形式**は不変。
    pub def captureSnaps(weaponCatalog: WeaponCatalog.WeaponCatalog,
                          staffCatalog: Staff.StaffCatalog,
                          consumableCatalog: Consumable.ConsumableCatalog,
                          ringCatalog: Ring.RingCatalog): List[FloorSnapshot.PlayerSnap] \ World.WorldQuery =
        getAll() |> List.map(d ->
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

    pub def getGridPos(id: Int32): {x = Int32, y = Int32} \ World.WorldQuery =
        match World.posOf(World.EntityRef.Player(id), World.WorldQuery.get()) {
            case Some(p) => p
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの移動力（マス数）を返す。未登録なら panic。
    /// 積載ペナルティ込みの実効値を返す（MoveRangeScene の青マスもこの値で縮む）。
    pub def getMoveTiles(id: Int32): Int32 \ World.WorldQuery =
        match (get(id) |> Option.map(effectiveMoveTilesOf)) {
            case Some(n) => n
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの現在 HP を返す。未登録なら panic。
    pub def getHp(id: Int32): Int32 \ World.WorldQuery =
        match get(id) {
            case Some(d) => d#hp
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    /// 指定 id のプレイヤーの武器インベントリを返す。武器が 1 つも無ければ Nil。
    pub def getWeapons(id: Int32): List[UnitCatalog.WeaponResource] \ World.WorldQuery =
        weaponsW(id)

    /// 指定 id のプレイヤーの杖インベントリを返す（無ければ空）。
    pub def getStaves(id: Int32): List[Staff.StaffResource] \ World.WorldQuery =
        stavesW(id)

    /// 指定 id のプレイヤーの消費アイテムインベントリを返す（無ければ空）。
    pub def getConsumables(id: Int32): List[Consumable.ConsumableResource] \ World.WorldQuery =
        consumablesW(id)

    /// ItemMenu で選ばれたアイテム（武器 or 杖）の種別と index をセットする
    /// （World 権威・SetSelectedItem が唯一の writer）。`ItemActionSelect` フェーズに進むときに ItemMenuUi から呼ばれる。
    pub def setSelectedItem(playerId: Int32, item: PlayerData.ItemKind): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetSelectedItem(playerId, Some(item)))

    /// 選択中アイテムをクリアする（サブメニュー確定後の後始末）。
    pub def clearSelectedItem(playerId: Int32): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetSelectedItem(playerId, None))

    /// 指定 idx の武器を装備（= weapons リストの先頭に移動）。
    /// 既に先頭なら何もしない。範囲外なら no-op。
    /// 「こうげき」は常に `weapons.head` を使うため、これで装備切り替えが反映される。
    pub def equipWeapon(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        // 在庫は World 権威＝現在値を読んで並べ替えを Cmd で書く。
        // 武器アイコンは renderGlyphs/renderPlates が World.weaponView から毎フレーム直描き＝貼り直し不要。
        putWeapons(playerId, moveToHead(idx, weaponsW(playerId)))

    /// 指定 idx の武器をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropWeapon(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        putWeapons(playerId, removeAt(idx, weaponsW(playerId)))

    /// 指定 idx の杖をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropStaff(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        putStaves(playerId, removeAt(idx, stavesW(playerId)))

    /// 指定 idx の消費アイテムをインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropConsumable(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        putConsumables(playerId, removeAt(idx, consumablesW(playerId)))

    /// 2 プレイヤー間でインベントリのアイテム 1 個ずつを交換する。
    ///   - 双方が実体アイテム持ちなら相互スワップ（ともに元の場所から消え、相手の末尾に追加）
    ///   - 相手が `None` (= 空スロット) のときは一方向 transfer
    ///     (自分のアイテムが消えて相手の対応リスト末尾に積まれる)
    /// 種別 (武器/杖) は元のままなので、武器 ↔ 杖の交換も自動的に両者の対応リストへ振り分けられる。
    /// `selfKind` が範囲外 / `selfId` が存在しない場合は防御的に no-op。
    /// 「こうかん」確定 (Phase 4) で TradeMenuUi から呼ばれる。
    ///
    /// 引数 (record-style):
    ///   - `selfId`      : 必ず実体アイテムを渡す側のプレイヤー id
    ///   - `selfKind`    : self 側で渡すアイテム種別 (Weapon idx / Staff idx)
    ///   - `partnerId`   : もう一方のプレイヤー id
    ///   - `partnerKind` : Some なら双方向 swap、None なら self 側からの片方向 transfer
    pub def swapItem(args: {selfId = Int32, selfKind = PlayerData.ItemKind,
                              partnerId = Int32,
                              partnerKind = Option[PlayerData.ItemKind]}):
            Unit \ {World.Command, World.WorldQuery} =
        let selfId      = args#selfId;
        let selfKind    = args#selfKind;
        let partnerId   = args#partnerId;
        let partnerKind = args#partnerKind;
        // 1. 両者のアイテム実体を「現在の World」から抜き出す (まだ削除はしない)
        let selfItemOpt = getInventoryItem(selfId, selfKind);
        let partnerItemOpt = partnerKind
            |> Option.flatMap(pk -> getInventoryItem(partnerId, pk));
        // 2. self 側に実体が無ければ no-op (selfKind = 空スロットは仕様外)
        match selfItemOpt {
            case None           => ()
            case Some(selfItem) =>
                removeInventoryItem(selfId, selfKind);
                removeOptInventoryItem(partnerId, partnerKind);
                addOptInventoryItem(selfId, partnerItemOpt);
                addInventoryItem(partnerId, selfItem)
        }

    /// 同じ player のインベントリ内で 2 アイテムの並び順を入れ替える（並び替え）。
    /// 表示順 (weapons ++ staves ++ consumables) を 1 列とみなして kindA / kindB の位置を
    /// 入れ替え、種別ごとのリストに振り直す。同じ種類同士なら純粋な位置入替、種別を跨ぐ
    /// ときは各リスト内での相対順だけが変わる。weapons[0] が装備なので武器の並び替えは
    /// 装備変更も兼ねる。
    pub def reorderItem(playerId: Int32, kindA: PlayerData.ItemKind, kindB: PlayerData.ItemKind):
            Unit \ {World.Command, World.WorldQuery} =
        // 先に World から在庫 4 リストを一括で読み、以降は値だけで並べ替える（読みの陳腐化を防ぐ）。
        let weapons     = weaponsW(playerId);
        let staves      = stavesW(playerId);
        let consumables = consumablesW(playerId);
        let rings       = ringsW(playerId);
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
        // 並び替えは在庫 4 リストの束ね書込＝4 つとも World へ書く。
        putWeapons(playerId, newWeapons);
        putStaves(playerId, newStaves);
        putConsumables(playerId, newConsumables);
        putRings(playerId, newRings)

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
    pub def getInventoryItem(playerId: Int32, kind: PlayerData.ItemKind):
            Option[ItemData.GroundItemKind] \ World.WorldQuery =
        match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                List.nth(idx, getWeapons(playerId))
                    |> Option.map(w -> ItemData.GroundItemKind.WeaponItem(w))
            case PlayerData.ItemKind.Staff(idx) =>
                List.nth(idx, getStaves(playerId))
                    |> Option.map(s -> ItemData.GroundItemKind.StaffItem(s))
            case PlayerData.ItemKind.Consumable(idx) =>
                List.nth(idx, getConsumables(playerId))
                    |> Option.map(c -> ItemData.GroundItemKind.ConsumableItem(c))
            case PlayerData.ItemKind.Ring(idx) =>
                List.nth(idx, getRings(playerId))
                    |> Option.map(r -> ItemData.GroundItemKind.RingItem(r))
        }

    /// 指定 player の `kind` のアイテムをインベントリから取り除く。
    /// `dropWeapon` / `dropStaff` のディスパッチ統合版。
    def removeInventoryItem(playerId: Int32, kind: PlayerData.ItemKind):
            Unit \ {World.Command, World.WorldQuery} =
        match kind {
            case PlayerData.ItemKind.Weapon(idx)     => dropWeapon(playerId, idx)
            case PlayerData.ItemKind.Staff(idx)      => dropStaff(playerId, idx)
            case PlayerData.ItemKind.Consumable(idx) => dropConsumable(playerId, idx)
            case PlayerData.ItemKind.Ring(idx)       => dropRing(playerId, idx)
        }

    /// `partnerKind = None` (= 空スロット相手) の場合は no-op、Some なら removeInventoryItem。
    def removeOptInventoryItem(playerId: Int32, kindOpt: Option[PlayerData.ItemKind]):
            Unit \ {World.Command, World.WorldQuery} =
        match kindOpt {
            case Some(k) => removeInventoryItem(playerId, k)
            case None    => ()
        }

    /// 武器インベントリの末尾に 1 個追加する。末尾追加により weapons[0] が常に装備中を保つ。
    /// 「ひろう」「こうかん」「キャンセル undo」など複数の追加経路がここに集約されるため、
    /// 追加ルール（末尾 = 装備中の後ろ）の変更は 1 箇所で完結する。
    pub def addWeapon(playerId: Int32, weapon: UnitCatalog.WeaponResource): Unit \ {World.Command, World.WorldQuery} =
        putWeapons(playerId, List.append(weaponsW(playerId), weapon :: Nil))

    /// 杖インベントリの末尾に 1 個追加する。追加ルールは `addWeapon` と同じ（末尾追加）。
    pub def addStaff(playerId: Int32, staff: Staff.StaffResource): Unit \ {World.Command, World.WorldQuery} =
        putStaves(playerId, List.append(stavesW(playerId), staff :: Nil))

    /// 消費アイテムインベントリの末尾に 1 個追加する。追加ルールは `addWeapon` と同じ（末尾追加）。
    pub def addConsumable(playerId: Int32, item: Consumable.ConsumableResource): Unit \ {World.Command, World.WorldQuery} =
        putConsumables(playerId, List.append(consumablesW(playerId), item :: Nil))

    /// 指輪インベントリ（先頭が装備中）。居ない player は Nil。
    pub def getRings(id: Int32): List[Ring.RingResource] \ World.WorldQuery =
        ringsW(id)

    /// 指輪インベントリの末尾に 1 個追加する（末尾追加 = 装備中の後ろ）。
    pub def addRing(playerId: Int32, ring: Ring.RingResource): Unit \ {World.Command, World.WorldQuery} =
        putRings(playerId, List.append(ringsW(playerId), ring :: Nil))

    /// 指定 idx の指輪を先頭へ移動し、装備状態にする（`ringEquipped = true`）。範囲外なら no-op。
    /// 拾っただけでは装備されないので、ここを通って初めて効果が出る。
    pub def equipRing(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        // rings と ringEquipped 両方の束ね書込（装備）＝両方 World へ書く。
        putRings(playerId, moveToHead(idx, ringsW(playerId)));
        putRingEquipped(playerId, true)

    /// 装備中の指輪を外す（所持は維持し、効果だけ止める）。並びは変えない。
    pub def unequipRing(playerId: Int32): Unit \ {World.Command, World.WorldQuery} =
        putRingEquipped(playerId, false)

    /// 指定 idx の指輪をインベントリから削除（捨てる）。範囲外なら no-op。
    /// 装備中の指輪（先頭）を捨てたら装備状態も解除する（残った先頭が勝手に装備されないように）。
    pub def dropRing(playerId: Int32, idx: Int32): Unit \ {World.Command, World.WorldQuery} =
        // rings と ringEquipped 両方の束ね書込（捨てる・先頭なら解除）＝両方 World へ書く。
        putRings(playerId, removeAt(idx, ringsW(playerId)));
        putRingEquipped(playerId, if (idx == 0) false else ringEquippedW(playerId))

    /// ringman の特殊行動で「指輪に変えられる」持ち物 = 装備外のアイテムを (種別 index, 表示名) で列挙する。
    /// 装備中の武器（weapons 先頭）と装備中の指輪（ringEquipped のときの rings 先頭）は守り、
    /// それ以外の武器・杖・薬・指輪を対象にする。居ない player は Nil。
    /// 在庫読みは PartyQuery（World 由来）経由。
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
    /// ringman の特殊行動の状態変換部（どの指輪にするかの抽選は catalog を持つ呼び出し側）。
    pub def replaceItemWithRing(playerId: Int32, kind: PlayerData.ItemKind,
                                 ring: Ring.RingResource): Unit \ {World.Command, World.WorldQuery} =
        removeInventoryItem(playerId, kind);
        addRing(playerId, ring)

    /// 指定 player のインベントリに `item` を追加（種別ごとに上記 writer へ委譲）。
    /// `addPickedItem`（ログ付き版）と同じ追加ルールの、ログを出さない版。
    def addInventoryItem(playerId: Int32, item: ItemData.GroundItemKind):
            Unit \ {World.Command, World.WorldQuery} =
        match item {
            case ItemData.GroundItemKind.WeaponItem(weapon)        =>
                addWeapon(playerId, weapon)
            case ItemData.GroundItemKind.StaffItem(staff)          =>
                addStaff(playerId, staff)
            case ItemData.GroundItemKind.ConsumableItem(consumable) =>
                addConsumable(playerId, consumable)
            case ItemData.GroundItemKind.RingItem(ring)            =>
                addRing(playerId, ring)
        }

    /// 床アイテム（`gridPos`）を playerId の在庫へ取得する共通処理。重量ゲートは呼び出し側が
    /// 行う前提（手動「ひろう」も、移動着地の自動取得も、拾えると判断してからここを呼ぶ）。
    /// 取得は `cancelSelection` で巻き戻せるよう `PickedUp` ドラフトに積んでから、
    /// 床撤去 → 在庫末尾へ追加 → ログ、の順で行う。床にアイテムが無ければ素通し（防御的）。
    pub def pickupFloorItem(playerId: Int32, gridPos: {x = Int32, y = Int32}):
            Unit \ {SelectedPlayer.State, GameLogger.GameLogger, World.Command,
                    World.WorldQuery} =
        // 床アイテムは World store から読む（read-after-write で fresh）。
        match World.groundItemAtOf(gridPos, World.WorldQuery.get()) {
            case None    => ()
            case Some(d) =>
                SelectedPlayer.pushDraft(
                    MoveDraft.DraftAction.PickedUp(playerId, d#gridPos, d#itemKey, d#item));
                match GroundItems.takeAt(d#gridPos) {
                    case Some(kind) => addPickedItem(playerId, kind)
                    case None       => ()
                }
        }

    /// 拾ったアイテムを在庫末尾に追加し「拾った」ログを出す（ログを出さない
    /// `addInventoryItem` のログ付き版）。手動「ひろう」/ 移動着地の自動取得 / 宝箱開錠の
    /// 取得経路が共有する。武器は weapons 末尾、杖は staves 末尾に積む。
    pub def addPickedItem(playerId: Int32, kind: ItemData.GroundItemKind):
            Unit \ {GameLogger.GameLogger, World.Command, World.WorldQuery} =
        match kind {
            case ItemData.GroundItemKind.WeaponItem(weapon) =>
                GameLogger.playerLog("${displayName(playerId)} が${weapon#name} を拾った");
                addWeapon(playerId, weapon)
            case ItemData.GroundItemKind.StaffItem(staff) =>
                GameLogger.playerLog("${displayName(playerId)} が${staff#name} を拾った");
                addStaff(playerId, staff)
            case ItemData.GroundItemKind.ConsumableItem(item) =>
                GameLogger.playerLog("${displayName(playerId)} が${item#name} を拾った");
                addConsumable(playerId, item)
            case ItemData.GroundItemKind.RingItem(ring) =>
                GameLogger.playerLog("${displayName(playerId)} が${ring#name} を拾った");
                addRing(playerId, ring)
        }

    /// `optItem = None` のときは no-op、Some なら addInventoryItem。
    def addOptInventoryItem(playerId: Int32, optItem: Option[ItemData.GroundItemKind]):
            Unit \ {World.Command, World.WorldQuery} =
        match optItem {
            case Some(item) => addInventoryItem(playerId, item)
            case None       => ()
        }

    /// `kind` 種別の在庫リスト末尾の 1 個を取り除く（`addInventoryItem` の逆操作）。
    /// 「ひろう」をキャンセルしたときに、末尾追加した仮取得アイテムを取り消すのに使う。
    /// 該当リストが空なら no-op。
    def removeLastInventoryItem(playerId: Int32, kind: ItemData.GroundItemKind):
            Unit \ {World.Command, World.WorldQuery} =
        match kind {
            case ItemData.GroundItemKind.WeaponItem(_)     =>
                let n = List.length(getWeapons(playerId));
                if (n > 0) dropWeapon(playerId, n - 1) else ()
            case ItemData.GroundItemKind.StaffItem(_)      =>
                let n = List.length(getStaves(playerId));
                if (n > 0) dropStaff(playerId, n - 1) else ()
            case ItemData.GroundItemKind.ConsumableItem(_) =>
                let n = List.length(getConsumables(playerId));
                if (n > 0) dropConsumable(playerId, n - 1) else ()
            case ItemData.GroundItemKind.RingItem(_)       =>
                let n = List.length(getRings(playerId));
                if (n > 0) dropRing(playerId, n - 1) else ()
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
                              item: ItemData.GroundItemKind):
            Unit \ {World.Command, World.WorldQuery} =
        match (kind, item) {
            case (PlayerData.ItemKind.Weapon(idx), ItemData.GroundItemKind.WeaponItem(w))         =>
                putWeapons(playerId, insertAt(idx, w, weaponsW(playerId)))
            case (PlayerData.ItemKind.Staff(idx), ItemData.GroundItemKind.StaffItem(st))          =>
                putStaves(playerId, insertAt(idx, st, stavesW(playerId)))
            case (PlayerData.ItemKind.Consumable(idx), ItemData.GroundItemKind.ConsumableItem(c)) =>
                putConsumables(playerId, insertAt(idx, c, consumablesW(playerId)))
            case (PlayerData.ItemKind.Ring(idx), ItemData.GroundItemKind.RingItem(r)) =>
                putRings(playerId, insertAt(idx, r, ringsW(playerId)))
            case _ => ()
        }


    /// レベルアップ表示待ち (pendingLevelUp = Some) の味方が 1 人でも居るか。
    /// 自分の攻撃（TurnFlow.commitWaitedAndAdvance）でも敵ターンの反撃（endTurn）でも、
    /// この判定でステータス変化パネルへ割り込む。pendingLevelUp は World 権威。
    pub def anyPendingLevelUp(): Bool \ World.WorldQuery =
        World.anyPendingLevelUp(World.WorldQuery.get())

}
