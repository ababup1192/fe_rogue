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

    /// ItemMenu で選択中のアイテムの種別と inventory 内 index。
    /// 武器と杖は別リストに格納されているため、どちらに属するかを ADT で区別する。
    pub enum ItemKind with Eq, ToString {
        case Weapon(Int32)     // weapons リスト上の index
        case Staff(Int32)      // staves リスト上の index
        case Consumable(Int32) // consumables リスト上の index
    }


    /// プレイヤー固有の状態。
    /// id: 0..N-1 の連番（N は `pools.party` の長さ）。"Player_<id>" ノード名と一致する。
    /// gridPos: 盤面上の駒の論理位置。moveTo で即座に更新される。
    /// moveTiles: 1 ターンに移動できるマス数（FE の「移動力」相当）。`resource` から初期値を継承。
    /// hp: 残り体力。0 になるとゲームオーバー。`resource#hp` が初期値。
    /// waited: 行動済みフラグ。true なら灰色表示・選択不可。
    /// attackTargetId: 体当たり攻撃モーション中なら Some(被攻撃者 id)。
    ///   `attack_lunge` アニメーションの method 発火 / finished 時に GameManager が
    ///   この値を読んでダメージ適用 / commit を行う。アニメ完了で None に戻す。
    /// resource: スポーン時のユニット定義テンプレート（UnitResource）。
    ///   ゲームオーバー時の復元（`respawnFromInitial`）で同じユニット種別で再生するために保持。
    /// weapons: 装備中の武器インベントリ。先頭が「装備中」武器で、攻撃時に自動使用される。
    ///   `equipWeapon` で他の武器を先頭に持ってくると装備が切り替わる。
    ///   攻撃で耐久度が 1 減り、0 になったら weapons から取り除かれる（武器が壊れた）。
    /// staves: 杖のインベントリ。攻撃には使わず、ItemMenu の「使う」で発動する。
    ///   発動で耐久度が 1 減り、0 になったら staves から取り除かれる。
    /// consumables: 消費アイテム（きずぐすり等）のインベントリ。ItemMenu の「使う」で
    ///   使用者自身に効果が出る。使用で耐久度（使用回数）が 1 減り、0 で取り除かれる。
    /// selectedItem: ItemMenu で選択中のアイテム（武器 / 杖 / 消費アイテム）。
    ///   一覧画面で選んだ瞬間にセット、サブメニュー（使う/装備/捨てる）で確定後にクリアされる。
    pub type alias Data = {
        id                 = Int32,
        gridPos            = {x = Int32, y = Int32},
        moveTiles          = Int32,
        hp                 = Int32,
        waited             = Bool,
        attackTargetId     = Option[Int32],
        resource           = UnitCatalog.UnitResource,
        weapons            = List[UnitCatalog.WeaponResource],
        staves             = List[Staff.StaffResource],
        consumables        = List[Consumable.ConsumableResource],
        selectedItem       = Option[ItemKind],
        // AutoMove 中にこの味方が当ターン何マス進んだか。
        // moveTiles に達したら `waited = true` にして次の味方に交代する。
        // プレイヤーターン開始時に 0 リセット。
        moveStepsTaken     = Int32,
        // 今向いている方向 (= 直近に動いた方向、初期値 Down)。
        // 子 Sprite が AnimatedSprite2D の場合、移動時に `walk_<dir>` アニメを再生する
        // ためにここから方向を読む。子が Sprite2D の場合は表示には影響しないが、
        // 戦闘・スキル系で利用しやすいよう値は保持する。
        facing             = Staff.Direction,
        // ローグ移動モードで「しゅうごう」してロードに合流し、退避中なら true。
        // hidden の味方は Marker2D ごと不可視 + `BoardSnapshot.fromScene` で盤面から除外され、
        // 敵範囲判定・占有・経路探索・カーソルの対象から外れる。「かいさん」で false に戻り
        // ロード周囲へ再出現する。持ち物・HP は hidden の間も Data に保持される。
        hidden             = Bool,
        // 階段を使ってこのフロアから退場したら true。`hidden` も同時に立てて盤面・敵範囲・
        // カーソルから外す。ローグの「しゅうごう」(hidden のみ) と区別するためのフラグで、
        // 「かいさん」での再出現対象から除外し、フロア終了判定 (全員退場) にも使う。
        // 次フロア開始時は false にリセットされる。
        usedStairs         = Bool,
        // 現在レベル（初期 1）。フロアを跨いで引き継ぐ。
        level              = Int32,
        // 現在 EXP（0..99）。敵に与ダメ・撃破で増え、100 到達でレベルアップして余剰を繰り越す。
        exp                = Int32,
        // 直近のレベルアップ結果。Some の間はステータス変化パネルを表示し、
        // commitWaitedAndAdvance がターンを進めずに LevelUpView へ割り込む。パネルを閉じると None。
        pendingLevelUp     = Option[LevelSystem.Result]
    }

    /// この味方の戦闘ビュー（faction 非依存）。装備武器は `weapons` の先頭。
    /// `Combat.estimate` / `Encounter` の join で使う（ダメージ式は `Combat` に集約）。
    pub def combatView(data: Data): Combat.CombatView =
        let equipped = List.head(data#weapons);
        {attack = data#resource#attack, magicAttack = data#resource#magicAttack,
         defense = data#resource#defense, magicDefense = data#resource#magicDefense,
         skill = data#resource#skill, speed = data#resource#speed, luck = data#resource#luck,
         hp = data#hp, weapon = Combat.weaponView(equipped, weaponProficient(data, equipped))}

    /// `combatView` の「装備武器を明示指定する」版。攻撃中に選択した武器（装備中=先頭とは
    /// 限らない）で戦闘予測を計算するため、`BattlePanelScene` から使う。
    pub def combatViewWith(data: Data, weapon: UnitCatalog.WeaponResource): Combat.CombatView =
        {attack = data#resource#attack, magicAttack = data#resource#magicAttack,
         defense = data#resource#defense, magicDefense = data#resource#magicDefense,
         skill = data#resource#skill, speed = data#resource#speed, luck = data#resource#luck,
         hp = data#hp,
         weapon = Combat.weaponView(Some(weapon),
                     UnitCatalog.proficientWith(data#resource, weapon#weaponType))}

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
         hp = data#hp, moveTiles = data#moveTiles,
         weaponRange = List.head(data#weapons) |> Option.map(w -> w#range),
         combat = combatView(data), isDying = false, hidden = data#hidden}

    /// 味方パーティの「現フレーム状態」を Scene を介さずに読み取る effect。
    ///
    /// 非 driver / 非 data Scene (HUD / Camera / Menu / Overlay) は `PlayerScene` モジュールを
    /// 直接タイプせず、この effect 経由で味方データを得る。これにより一方向の依存グラフを
    /// 保ち、テストで handler を差し替えてスタブできる。
    ///
    /// 設計は `BoardQuery` (Board.flix:34) と同じ:
    ///   - 読み取り専用、Ref を持たない
    ///   - handler は Game.start で `Ref.get(sceneRef)` から最新 scene を読んで `PlayerScene.*`
    ///     をそのまま呼び返す inline handler
    ///   - 毎フレーム gameLoop が sceneRef を更新するため、各 op は最新値を返す
    ///
    /// driver Scene (AutoMoveScene / EnemyTurnDriverScene) と data Scene 同士の相互参照は
    /// orchestrator として現状の直接呼び出しを許容する (本 effect は経由しない)。
    pub eff PartyQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
        def getGridPos(id: Int32): {x = Int32, y = Int32}
        def getMoveTiles(id: Int32): Int32
    }

    /// スポーン時の中間表現。`add` で配置するセルの id/gridPos に加え、
    /// どのユニット定義（UnitResource）でセットアップするかも持つ。
    /// 初期 spawn のスナップショット（ゲームオーバー時の復元用）にも使う。
    /// `weapons` / `staves` は初期インベントリ（壊れる前の固定リスト）で、
    /// respawn 時にこの値で復元する。
    pub type alias Spawn = {
        id          = Int32,
        gridPos     = {x = Int32, y = Int32},
        resource    = UnitCatalog.UnitResource,
        weapons     = List[UnitCatalog.WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// ロード（主人公）として扱うパーティ id。合流・カメラ追従の中心であり、
    /// このユニットが倒れると 1F からやり直し（ゲームオーバー扱い）になる。
    pub def lordId(): Int32 = 0

    /// 持ち物（武器 + 杖 + 消費アイテム）を判定する職種名。`units.json` の "description" と一致させる。
    /// この職種だけ持ち物上限が広い（2 ページぶん持てる）。
    def lordClass(): String = "ロード"

    /// ロード職以外の持ち物上限（合計個数）。
    def normalItemCapacity(): Int32 = 8

    /// ロード職の持ち物上限（合計個数）。8 個 × 2 ページぶん。
    def lordItemCapacity(): Int32 = 16

    /// この味方が持てる持ち物の合計上限。職種が「ロード」なら 16、それ以外は 8。
    pub def itemCapacity(data: Data): Int32 =
        if (data#resource#description == lordClass()) lordItemCapacity()
        else normalItemCapacity()

    /// いま持っている持ち物の合計個数（武器 + 杖 + 消費アイテムを合算する）。
    pub def itemCount(data: Data): Int32 =
        List.length(data#weapons)
            + List.length(data#staves)
            + List.length(data#consumables)

    /// 持ち物が上限に達しているか（これ以上拾えないか）。
    pub def isInventoryFull(data: Data): Bool =
        itemCount(data) >= itemCapacity(data)

    /// プレイヤー Sprite の zIndex（Player は前面に立つ）。EnemyScene と同じ 10。
    def spriteZIndex(): Int32 = 10

    /// 1 マス分のスライド時間（≈ 0.133 秒）。ローグ自由移動・自動移動で使う通常スピード。
    def slideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 120)

    /// キャラ選択後の手動移動（PlayerMoving）の 1 マス時間（≈ 0.167 秒）。
    /// 通常の約 80% スピード（時間 1.25 倍 = 16→20 フレーム）にして、落ち着いて移動先を
    /// 狙えるよう少しゆっくりにする。自動移動やローグ自由移動には影響させない。
    def selectedSlideDuration(): Duration.Duration =
        Duration.frames(count = 20, fps = 120)

    /// `waited = true` 時の sprite modulate（薄い灰色）。
    /// CanvasItem.setModulate で sprite の RGB を乗算する。
    def waitedColor(): Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32}

    /// `waited = false` 時の sprite modulate（白 = 元色）。
    def activeColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

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
                  scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, PartySelection.State} =
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
        let padded       = padCells(cells, spawnGrid, n);
        let spawns: List[Spawn] = padded
            |> List.mapWithIndex(id -> c ->
                let res = match List.nth(id, selected) {
                    case Some(r) => r
                    case None    => bug!("PlayerScene.add: party index ${id} out of range")
                };
                let split = splitInventory(res#initialInventory, catalog,
                                            staffCatalog, consumableCatalog);
                ({id = id, gridPos = c, resource = res,
                   weapons = split#weapons, staves = split#staves,
                   consumables = split#consumables}: Spawn));
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
            |> dedupCells
            |> List.take(n)

    /// `cells` が n 個に満たない場合、不足分を spawnGrid で埋める。
    /// 配置不能なほど狭い部屋への保険（実運用では candidate がほぼ充足する想定）。
    def padCells(cells: List[{x = Int32, y = Int32}], fallback: {x = Int32, y = Int32},
                  n: Int32): List[{x = Int32, y = Int32}] =
        let len = List.length(cells);
        if (len >= n) List.take(n, cells)
        else
            let padding = List.repeat(n - len, fallback);
            List.append(cells, padding)

    /// セル一覧から重複を取り除く（順序保持・先勝ち）
    def dedupCells(cells: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        List.foldLeft((acc, c) ->
            if (List.exists(p -> p#x == c#x and p#y == c#y, acc)) acc
            else List.append(acc, c :: Nil),
            (Nil: List[{x = Int32, y = Int32}]), cells)

    /// プレイヤー 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    /// ステータス・テクスチャ・フレームは `sp#resource`（UnitResource）から取る。
    /// pub: `PlayerScene.add` の party 追加ループから呼ばれる本体内部ロジック。
    /// テストでも catalog からの Spawn 構築 → addOnePlayer の本体経路を流用する。
    pub def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pos = MapScene.cellCenter(sp#gridPos);
        let marker = Marker2D.make(pos);
        let res    = sp#resource;
        let data: Data = {
            id                = sp#id,
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
            pendingLevelUp    = None
        };
        // unit に spriteFrames があれば AnimatedSprite2D で配置、無ければ Sprite2D
        // (静止単一フレーム) で配置する。AnimatedSprite2D は engine の per-node
        // process が advanceFrame を毎フレーム呼ぶので、こちらでチクチク回す必要は無い。
        let spriteNode = match res#spriteFrames {
            case Some(sf) =>
                let anim = AnimatedSprite2D.make(sf,
                    {animation = idleAnimName()}, Vec2.zero(), res#sprite#scale)
                    |> AnimatedSprite2D.setOffset(res#sprite#offset)
                    |> AnimatedSprite2D.setAutoplay(idleAnimName())
                    |> CanvasItem.setZIndex(spriteZIndex());
                EngineNode.AnimSprite2DWithState(anim, NodeTag.NoTag)
            case None =>
                let sprite = Sprite2D.make(res#sprite#texture, res#sprite#offset,
                                            res#sprite#scale)
                                |> Sprite2D.setHframes(res#sprite#hframes)
                                |> Sprite2D.setVframes(res#sprite#vframes)
                                |> Sprite2D.setFrame(res#sprite#frame)
                                |> CanvasItem.setZIndex(spriteZIndex());
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag)
        };
        scene
            |> Scene.addChildAt(MapScene.worldPath(), playerName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))
            |> Scene.addChildAt(playerPath(sp#id), "Sprite", spriteNode)
            |> UnitHPBarScene.attach(playerPath(sp#id), res#hp, UnitHPBarScene.Team.Player)

    // ────────────────────────────────────────────────────────
    // (D) ロジック — 移動
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（Board）が済ませている前提**。
    /// gridPos を即更新し、見た目は Tween に委ねる。`slide` は 1 マス分のスライド時間で、
    /// 呼び出し側がスピードを決める（手動移動は少しゆっくり、ローグ自由移動は通常）。
    pub def moveTo(id: Int32, map: MapSnapshot, target: {x = Int32, y = Int32},
                    marker: Marker2D, data: Data, slide: Duration.Duration,
                    scene: Scene[NodeTag]): (Marker2D, Data)
                    \ Tween.Scheduler =
        let targetWorld = map#gridToWorld(target);
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        Tween.tweenPosition(playerPath(id), startWorld, targetWorld, slide);
        // 進行方向を facing に反映し、AnimatedSprite2D なら walk_<dir> 再生 (副作用)。
        // sprite ノード書き換えは moveToById 側でやる (moveTo は state を返すだけ)。
        let nextFacing = directionOfStep(data#gridPos, target)
                            |> Option.getWithDefault(data#facing);
        (marker, {gridPos = target, facing = nextFacing | data})

    /// 指定 id のプレイヤーが現在 tween 中（次の入力を受け付けない状態）か。
    pub def isMoving(id: Int32): Bool \ Tween.Scheduler =
        Tween.Scheduler.isActive(playerPath(id))

    /// 指定 id のプレイヤーを `target` グリッドへ Tween で移動させ、scene の Data も
    /// 同時に更新する。`moveTo` は (Marker2D, Data) を返す形だが、こちらは
    /// physicsProcess の外（AutoMove など）から id だけで呼べるように scene を直接編集する。
    /// `EnemyScene.moveTo` と同じインターフェース。**歩行可否は呼び出し側が確認済み前提**。
    pub def moveToById(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        let targetWorld = map#gridToWorld(target);
        Tween.tweenPosition(playerPath(id), startWorld, targetWorld, slideDuration());
        // 直前のグリッド座標から target への 1 マス差で方向を決める。
        // 0 ベクトル (= 同じセル) の場合は既存の facing を保つ。
        let prev      = getGridPos(id, scene);
        let dirOpt    = directionOfStep(prev, target);
        let withState = mapPlayer(id, d -> {
            gridPos = target,
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
                    scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let world = MapScene.cellCenter(target);
        Tween.Scheduler.cancel(playerPath(id));
        scene
            |> Scene.setGlobalPositionAt(playerPath(id), world)
            |> mapPlayer(id, d -> {gridPos = target | d})

    /// PlayerCursor + Z で味方マスを選択した瞬間の遷移: 選択中味方を SelectedPlayer に
    /// 記録し、PlayerMoving に進む。
    /// overlay (MoveRange / MoveAttackRange / EnemyRange) と Cursor の整理は
    /// `PhaseTransitions.enterPlayerMoving` が担当する (この関数は SelectedPlayer 更新だけ)。
    pub def beginSelection(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        SelectedPlayer.State.put({
            id     = Some(playerId),
            // 移動開始。元位置を巻き戻しドラフトの底に積む（前の移動の残骸は drafts ごと破棄）
            drafts = MoveDraft.DraftAction.MovedFrom(playerId, getGridPos(playerId, scene)) :: Nil
        });
        PhaseTransitions.enterPlayerMoving(scene)

    /// PlayerMoving + X: 選択駒を origin に瞬間移動で戻し、選択解除して PlayerCursor に戻す。
    /// 「キャンセル → 再選択の繰り返しで実質ターン制限なしの自由移動」を防ぐ FE 流。
    /// overlay / cursor の片付けは `PhaseTransitions.enterPlayerCursor` が担当。
    pub def cancelSelection(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PartyQuery} =
        // この移動で積んだ可逆ドラフトを新しい順に巻き戻す（拾得→元位置への復帰など）。
        // 「拾ってからキャンセルしたら拾っていないことにする」もこの一括巻き戻しで実現。
        let drafts   = SelectedPlayer.State.get()#drafts;
        let restored = List.foldLeft((acc, a) -> revertDraftAction(a, acc), scene, drafts);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        PhaseTransitions.enterPlayerCursor(restored)

    /// 移動ドラフト 1 件を巻き戻す。巻き戻しの実体はここに集約する
    /// （新しい可逆操作を足すときはこの match に 1 分岐追加するだけ）。
    ///   - `MovedFrom`: origin に snapTo で戻し、walk 表示を idle に戻す
    ///     （移動中の walk_<dir> のままだと「キャンセル後に動いてないのに横向き」になる）
    ///   - `PickedUp` : 床へ戻し（`ItemScene.respawn`）+ 在庫末尾の仮取得分を取り消す
    def revertDraftAction(action: MoveDraft.DraftAction,
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        match action {
            case MoveDraft.DraftAction.MovedFrom(id, cell)              =>
                snapTo(id, cell, scene) |> playAnim(id, idleAnimName())
            case MoveDraft.DraftAction.PickedUp(pid, cell, itemKey, kind) =>
                scene
                    |> ItemScene.respawn(cell, itemKey, kind)
                    |> removeLastInventoryItem(pid, kind)
            case MoveDraft.DraftAction.Equipped(pid, idx)               =>
                // 装備 = moveToHead(idx) の逆。先頭を idx 位置へ戻す。
                mapPlayer(pid, d -> {weapons = moveHeadTo(idx, d#weapons) | d}, scene)
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
        }

    /// ActionMenu「こうげき」確定で呼ばれる: 攻撃ターゲット選択フェーズへ。
    /// overlay / cursor 整理は `PhaseTransitions.enterPlayerAttack` が担当
    /// (全武器の射程の和集合で赤マスを敷き、最初のターゲットへカーソルをスナップ)。
    /// その後、カーソルが乗った敵に届く先頭の武器を装備(先頭へ移動)しておく。これにより
    /// 装備中(先頭)武器が届かない敵でも、届く武器を「装備した扱い」で攻撃ウィンドウを開ける。
    pub def enterAttackPhase(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PartyQuery, EnemyScene.RosterQuery} =
        let withPhase = PhaseTransitions.enterPlayerAttack(scene);
        equipReachingWeaponForCursor(withPhase)

    /// カーソルが乗っている敵に届く先頭の武器を装備する (届く武器が無ければ no-op)。
    /// 進入直後の「装備した扱い」初期化用。`enterAttackPhase` からのみ呼ぶ。
    def equipReachingWeaponForCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None     => scene
            case Some(id) =>
                let equipped = forM (
                    player <- get(id, scene);
                    eid    <- EnemyScene.findIdAt(CursorScene.getGridPos(scene), scene);
                    enemy  <- EnemyScene.get(eid, scene);
                    idx    <- firstWeaponIdxReaching(player,
                                  Weapon.manhattan(player#gridPos, enemy#gridPos))
                ) yield equipWeapon(id, idx, scene);
                Option.getWithDefault(scene, equipped)
        }

    /// インベントリの先頭から、距離 `distance` に射程が届く最初の武器の index を返す。
    /// 届く武器が無ければ None。攻撃中の武器選択・進入時装備で共用する純粋関数。
    pub def firstWeaponIdxReaching(data: Data, distance: Int32): Option[Int32] =
        data#weapons
            |> List.zipWithIndex
            |> List.findMap(p -> match p {
                case (i, w) => if (Weapon.inRange(distance, w#range)) Some(i) else None
            })

    /// 各 Player ノードの毎フレーム process。AnimationPlayer から自分宛 (`playerPath(id)`)
    /// の signal だけ pull し、attack:hit (中点) / attack_lunge (完了) に反応する。
    /// Game.flix の `Node[NodeTag] instance` の process redef から全 Player に dispatch
    /// される (per-node)。owner 完全一致なので他 Player の signal は取りこぼさない。
    /// 「Sceneのライフサイクルで処理が完結」する Godot 流の per-node signal モデル。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameEngine.Audio, GameEngine.Game,
                        GameLogger.GameLogger,
                        EnemyTurn.Queue, TurnPhase.State,
                        SelectedPlayer.State, Pacing.State, Math.Random} =
        match idFromPath(path) {
            case None           => (node, scene)
            case Some(playerId) =>
                let bundle = AnimationPlayer.Scheduler.drainSignals(playerPath(playerId));
                let afterMethods = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.AttackHit) => onAttackHit(playerId, sc)
                        case _                              => sc
                    },
                    scene, bundle#methods);
                let afterFinished = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.AttackLunge) => onAttackLungeDone(playerId, sc)
                        case _                                => sc
                    },
                    afterMethods, bundle#finished);
                // 待機モーションへの復帰は Tween 完了をトリガーにせず、
                // setWaited / clearAllWaited (= 待機確定 / 次ターン開始) に集約している。
                // 移動 Tween 完了後は最後に向いた walk_<dir> アニメをそのまま維持する。
                // signal handler が scene 経由で self (Player ノード) を更新する可能性が
                // あるため、最新ノードを取り直して返す (古い node で打ち消されないように)
                match Scene.getEngineNode(path, afterFinished) {
                    case Some(latest) => (latest, afterFinished)
                    case None         => (node, afterFinished)
                }
        }

    /// 毎フレーム engine から呼ばれる。**選択中プレイヤーのみ** 動かす。
    /// Game.flix の Node[NodeTag] redef からは PlayerMoving フェーズで
    /// 「id == SelectedPlayer.State.get()」のノードに対してだけ dispatch される。
    pub def physicsProcess(_delta: Duration.Duration,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                if (isMoving(data#id)) (node, scene)
                else
                    let board = BoardQuery.board();
                    let allowed = c -> MoveRangeScene.isInRange(c, scene);
                    // 方向キー押下で 1 セルだけ進む。味方セルへ進入可能 (重なる)、
                    // ただし重なっている間は Z で行動決定できない (`Board.isOverlappingAlly`
                    // で `TurnRules` がブロック)。「味方を超えて自動スライド」する旧
                    // `stepThroughAllies` 挙動は廃止。
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- Board.tryMoveWithRange(board, data#gridPos, dir, allowed)
                    ) yield {
                        let (newMarker, newData) =
                            moveTo(data#id, board#map, target, marker, data,
                                   selectedSlideDuration(), scene);
                        // 子 Sprite が AnimatedSprite2D なら、進行方向の walk_<dir> アニメに
                        // 切り替える (Sprite2D の unit は playAnim が no-op)。
                        // direction が決まらない (= 同セル移動) ケースは scene 据え置き。
                        let dirOpt = directionOfStep(data#gridPos, target);
                        let animScene = match dirOpt {
                            case Some(d) => playAnim(data#id, walkAnimName(d), scene)
                            case None    => scene
                        };
                        let nextScene = if (data#resource#sprite#flipForFacing)
                                            applyFacingFlip(data#id, dirOpt, animScene)
                                        else animScene;
                        (EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                         nextScene)
                    };
                    Option.getWithDefault((node, scene), movement)
            case _ => (node, scene)
        }

    /// ローグ移動モード(RogueMove)中のロード(id 0)の自由歩行。`physicsProcess` と違い
    /// **移動力(MoveRange)の制限がなく**、床であれば何マスでも歩ける。他味方は合流して
    /// hidden = 盤面から除外されているので、実質「地形 + 敵」だけが移動の障害になる。
    /// 敵範囲入りの判定と自動解散は driver(`AutoMoveScene.roamJudge`)側が行う。
    pub def lordRoamProcess(_delta: Duration.Duration,
                             node: EngineNode[NodeTag],
                             _path: NodePath,
                             scene: Scene[NodeTag]):
                            (EngineNode[NodeTag], Scene[NodeTag])
                            \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                if (isMoving(data#id)) (node, scene)
                else
                    let board = BoardQuery.board();
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- Board.tryMove(board, data#gridPos, dir)
                    ) yield {
                        let (newMarker, newData) =
                            moveTo(data#id, board#map, target, marker, data,
                                   slideDuration(), scene);
                        let dirOpt = directionOfStep(data#gridPos, target);
                        let animScene = match dirOpt {
                            case Some(d) => playAnim(data#id, walkAnimName(d), scene)
                            case None    => scene
                        };
                        let nextScene = if (data#resource#sprite#flipForFacing)
                                            applyFacingFlip(data#id, dirOpt, animScene)
                                        else animScene;
                        (EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                         nextScene)
                    };
                    Option.getWithDefault((node, scene), movement)
            case _ => (node, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右）
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None

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

    /// 指定プレイヤーの上下左右 1 マスに居る他味方を返す（自分は含まない）。
    /// 「こうかん」コマンドや将来の隣接判定 (例: 助太刀) の出現条件として使う。
    /// 斜め (例: (4,4) と (5,5)) は含まない。waited フィルタはここではせず、
    /// 全味方を対象にする (waited 駒との交換可否は呼び出し側で判定)。
    pub def adjacentAllies(player: Data): List[Data] \ PartyQuery =
        PartyQuery.getAll()
            |> List.filter(other ->
                other#id != player#id
                and Weapon.manhattan(player#gridPos, other#gridPos) == 1)

    /// 指定セル上の全プレイヤー（waited 含む）の id を返す。
    /// 敵が攻撃する隣接プレイヤーの判定など、waited 含めて見たいときに使う。
    pub def findIdAt(coord: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Option[Int32] =
        getAll(scene)
            |> List.findMap(d ->
                if (d#gridPos#x == coord#x and d#gridPos#y == coord#y) Some(d#id)
                else None)

    /// アクティブなプレイヤーが 1 人でも残っていれば true。
    /// 「全員行動済みなら敵ターンへ」の判定に使う。
    pub def anyActive(scene: Scene[NodeTag]): Bool =
        List.exists(d -> not d#waited, getAll(scene))

    /// アクティブ（waited でない）味方のうち、id 最小のものを返す。誰も居なければ None。
    /// `commitWaitedAndAdvance` の直後にカーソルを次に動ける駒へ飛ばす用途で使う
    /// (`PartyQuery` 経由だとフレーム冒頭 snapshot を読むため stale)。
    pub def firstActive(scene: Scene[NodeTag]): Option[Data] =
        getAll(scene)
            |> List.filter(d -> not d#waited)
            |> List.sortBy(d -> d#id)
            |> List.head

    /// 敵攻撃で HP=0 になったプレイヤーを scene から取り除く。`killed` は
    /// `EnemyScene.applyAttackHit` が返した死亡 id のリスト (通常 1 要素)。
    /// 選択中プレイヤーが含まれていれば (反撃で死亡したケース) 選択も解除する。
    /// 次のいずれかでゲームオーバー (`CustomEffects.GameOverRequest.request`) を emit し、
    /// handler 側でマップ・配置を 1F からフルリビルドする:
    ///   - 味方が全員脱落した
    ///   - ロード（主人公 = `lordId()`）が倒れた（他の味方が残っていても 1F やり直し）
    pub def removeDeadAndCheckGameOver(killed: List[Int32],
                                         scene: Scene[NodeTag]):
            Scene[NodeTag] \ {CustomEffects.GameOverRequest, SelectedPlayer.State} =
        if (List.isEmpty(killed)) scene
        else {
            let removed = List.foldLeft(
                (sc, id) -> Scene.removeAt(playerPath(id), sc),
                scene, killed);
            let selectedKilled = match SelectedPlayer.State.get()#id {
                case Some(id) => List.exists(k -> k == id, killed)
                case None     => false
            };
            if (selectedKilled)
                SelectedPlayer.State.put(SelectedPlayer.cleared())
            else ();
            let lordDead = List.exists(k -> k == lordId(), killed);
            if (List.isEmpty(getAll(removed)) or lordDead)
                CustomEffects.GameOverRequest.request(removed)
            else removed
        }

    /// プレイヤーを「行動済み」にして sprite を灰色 modulate にする。
    /// AnimatedSprite2D 持ち unit はここで idle アニメに戻す (= 待機モーション表示)。
    /// PlayerAttack 確定 / スキップ時に呼ばれる。
    pub def setWaited(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> mapPlayer(id, d -> {waited = true | d})
            |> setSpriteModulate(id, waitedColor())
            |> UnitHPBarScene.setModulate(playerPath(id), waitedColor())
            |> playAnim(id, idleAnimName())

    /// 全プレイヤーを「行動済み(非アクティブ)」にする。各 id に `setWaited` を適用し、
    /// waited を立てて灰色 modulate + idle アニメへ揃える。
    /// 「集合 → 解散」でパーティ全員のターンを一括消費するときに使う
    /// (この後 active な味方が居なくなるので呼び出し側は敵ターンへ進める)。
    pub def setAllWaited(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) -> setWaited(id, sc), scene, ids)

    /// 全プレイヤーの waited をクリアし、sprite を白に戻す。
    /// ターン開始時に呼ばれ、AnimatedSprite2D 持ち unit は idle アニメに戻す
    /// (= 新ターン開始時の待機モーション)。
    /// 敵ターン終了後に呼ぶ（次の味方ターン開始）。
    pub def clearAllWaited(scene: Scene[NodeTag]): Scene[NodeTag] =
        // 階段で退場した味方 (usedStairs) は「行動済み」を維持し、敵ターン後も再行動させない。
        let ids = getAll(scene) |> List.filter(d -> not d#usedStairs) |> List.map(d -> d#id);
        List.foldLeft((sc, id) ->
            sc
                |> mapPlayer(id, d -> {waited = false | d})
                |> setSpriteModulate(id, activeColor())
                |> UnitHPBarScene.setModulate(playerPath(id), activeColor())
                |> playAnim(id, idleAnimName()),
            scene, ids)

    /// 全プレイヤーの sprite / HP ゲージを通常色(active)に戻す。`waited` フラグは変えない。
    /// 敵フェーズ中に「味方の行動済み灰色」を消してアクティブに見せるために使う
    /// （待機しているという扱い自体は残し、見た目だけ通常色に戻す。階段で退場済みの味方は対象外）。
    pub def showAllActive(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.filter(d -> not d#usedStairs) |> List.map(d -> d#id);
        List.foldLeft((sc, id) ->
            sc
                |> setSpriteModulate(id, activeColor())
                |> UnitHPBarScene.setModulate(playerPath(id), activeColor()),
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
    // (E') ローグ移動モード — 合流退避 / 再出現 / 候補選び
    // ────────────────────────────────────────────────────────

    /// 味方 id の表示/退避を切り替える。`flag = true` で Marker2D ごと不可視にして
    /// hidden を立てる(合流して消える)。`flag = false` で元に戻す(かいさんで再出現)。
    /// 親 Marker2D を不可視にすると子 Sprite / HPBar も連動して消える(Godot の
    /// 親子可視性 AND。CursorScene.setVisible と同手法)。
    pub def setHidden(id: Int32, flag: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(d)) =>
                EngineNode.Marker2DWithState(CanvasItem.setVisible(not flag, marker),
                                              NodeTag.Player({hidden = flag | d}))
            case other => other
        }, scene)

    /// 味方 id を「正面待機」に戻す。`facing` を Down にし、AnimatedSprite2D 持ち unit は
    /// idle アニメ(= 正面フレーム)へ切り替える。Sprite2D 静止 unit は playAnim が no-op。
    /// 移動 Tween 完了を idle 復帰のトリガーにしない設計のため(`process` 参照)、
    /// 「かいさん」など歩いて再出現した直後の settle 地点で明示的に呼ぶ。
    /// これが無いと walk_<dir> のまま固まり、再出現した archer が横/後ろを向いたままになる。
    pub def faceFrontIdle(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> mapPlayer(id, d -> {facing = Staff.Direction.Down | d})
            |> playAnim(id, idleAnimName())

    /// 合流して退避中(hidden)の味方一覧。「かいさん」での再出現対象。
    /// このリストが空でない = いまローグ移動モード中、の手掛かりとしても使う。
    /// 階段で退場した味方 (usedStairs) は hidden だが再出現対象ではないので除外する。
    pub def hiddenAllies(scene: Scene[NodeTag]): List[Data] =
        getAll(scene) |> List.filter(d -> d#hidden and not d#usedStairs)

    /// 合流させられる味方一覧(= ロード(id 0)以外で、まだ表示中の味方)。
    /// 「しゅうごう」を出す条件 / 合流で歩かせる対象として使う。
    pub def mergeableAllies(scene: Scene[NodeTag]): List[Data] =
        getAll(scene) |> List.filter(d -> d#id != 0 and not d#hidden)

    /// すべての座標が `center` の周囲 `range` マス以内（チェビシェフ距離 = max(|dx|,|dy|)）に
    /// あるか。空リストは true。位置だけのピュア判定（テストしやすいよう座標で受け取る）。
    pub def allWithinRange(range: Int32, center: {x = Int32, y = Int32},
                            positions: List[{x = Int32, y = Int32}]): Bool =
        List.forAll(pos ->
            Int32.max(Int32.abs(pos#x - center#x), Int32.abs(pos#y - center#y)) <= range,
            positions)

    /// 合流対象の味方（mergeableAllies）が全員、ロード(id 0)の周囲 `range` マス以内に居るか。
    /// 「しゅうごう」をその場でできる（全員が近くに固まっている）かの判定に使う。
    pub def allMergeableWithin(range: Int32, scene: Scene[NodeTag]): Bool =
        allWithinRange(range, getGridPos(0, scene),
                       mergeableAllies(scene) |> List.map(d -> d#gridPos))

    /// 合流で次に動かす 1 体を選ぶ純粋関数(= ロードに最も近い味方)。居なければ None。
    pub def nearestMover(lordPos: {x = Int32, y = Int32},
                          movers: List[Data]): Option[Data] =
        movers
            |> List.sortBy(d -> Weapon.manhattan(d#gridPos, lordPos))
            |> List.head

    /// 「かいさん」でロード周囲に味方を再配置するためのセルを `n` 個選ぶ純粋関数。
    /// `origin`(ロード位置)の 8 近傍から「床 かつ 駒に占有されていない かつ origin 以外」を
    /// 近い順に拾い、不足分は origin で埋めて長さ `n` を保つ(狭所での保険。重なっても
    /// 次の移動で解ける)。`spawn` 配置(`pickPlayerSpawns`)と同じ近傍・dedup 規則。
    pub def pickRespawnCells(origin: {x = Int32, y = Int32}, n: Int32,
                              board: Board): List[{x = Int32, y = Int32}] =
        let offsets =
                  ({x =  1, y =  0}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  0}: {x = Int32, y = Int32})
            ::    ({x =  0, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  0, y = -1}: {x = Int32, y = Int32})
            ::    ({x =  1, y =  1}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  1, y = -1}: {x = Int32, y = Int32})
            ::    ({x = -1, y = -1}: {x = Int32, y = Int32})
            ::    Nil;
        let cands = offsets
            |> List.map(o -> ({x = origin#x + o#x, y = origin#y + o#y}: {x = Int32, y = Int32}))
            |> List.filter(c -> Board.isWalkable(board, c) and not Board.isOccupied(c, board))
            |> dedupCells;
        padCells(cands, origin, n)

    /// 指定 id の子 Sprite の modulate を変える内部ヘルパー。
    /// Sprite2D / AnimatedSprite2D どちらの実装でも動くように両方の inner mapper を試す。
    def setSpriteModulate(id: Int32, color: Color,
                           scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id),
            n -> n
                |> EngineNode.mapSprite2D(s -> CanvasItem.setModulate(color, s))
                |> EngineNode.mapAnimSprite2D(s -> CanvasItem.setModulate(color, s)),
            scene)

    /// 子 Sprite が AnimatedSprite2D なら `play(animName)` を適用する内部ヘルパー。
    /// Sprite2D だった場合 (= spriteFrames を持たない unit) は no-op。
    /// unknown id や Sprite ノードが無いケースも no-op で安全。
    def playAnim(id: Int32, animName: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id), node -> match node {
            case EngineNode.AnimSprite2DWithState(sp, tag) =>
                EngineNode.AnimSprite2DWithState(AnimatedSprite2D.play(animName, sp), tag)
            case other => other
        }, scene)

    /// 子 Sprite (Sprite2D / AnimatedSprite2D いずれの実装でも) に flipH を設定する。
    def setSpriteFlipH(id: Int32, h: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id),
            n -> n
                |> EngineNode.mapSprite2D(s -> Sprite2D.setFlipH(h, s))
                |> EngineNode.mapAnimSprite2D(s -> AnimatedSprite2D.setFlipH(h, s)),
            scene)

    /// 進行方向に応じて「左向きの絵」を水平反転する。Right で flipH=true (右向き)、
    /// Left で flipH=false (左向き=素材そのまま)。Up/Down/None は現状維持。
    /// `sprite#flipForFacing` を持たない駒では呼び出し側 (`flipsForFacing`) が抑止する。
    def applyFacingFlip(id: Int32, dirOpt: Option[Staff.Direction],
                         scene: Scene[NodeTag]): Scene[NodeTag] =
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
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                ({id = d#id, gridPos = d#gridPos, resource = d#resource,
                   weapons = d#weapons, staves = d#staves,
                   consumables = d#consumables}: Spawn))

    /// 既存のプレイヤーを全て scene から取り除き、`spawns` から再構築する。
    /// HP / waited / gridPos を初期値で生成する。
    pub def respawnFromInitial(spawns: List[Spawn],
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        let cleared = List.foldLeft((sc, d) ->
            Scene.removeAt(playerPath(d#id), sc), scene, getAll(scene));
        List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), cleared, spawns)

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
        level       = Int32,
        exp         = Int32,
        // 成長後の 6 ステータス（最大 HP 含む）。次フロアの新規 resource に上書きして引き継ぐ。
        stats   = LevelSystem.Stats
    }

    /// 味方 id を「階段で退場」させる。`usedStairs` を立て、`hidden` も同時に立てて
    /// Marker2D ごと不可視にする（= 盤面・敵範囲・占有・経路・カーソルから外れる）。
    /// `waited` も立てるので「行動済み」扱いになり、`firstActive` / `anyActive` の対象から
    /// 外れて以後このフロアでは動けない。`clearAllWaited` は usedStairs を維持するため
    /// 敵ターンを跨いでも退場状態のままになる。次フロア構築 (addOnePlayer) で全て false に戻る。
    pub def useStairs(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> setHidden(id, true)
            |> mapPlayer(id, d -> {usedStairs = true, waited = true | d})

    /// 生存している味方が「全員」階段を使ったか（= このフロアの終了条件）。
    /// 生存者が 1 人も居ない場合は false（それは全滅 = ゲームオーバー側の扱い）。
    pub def allLivingUsedStairs(scene: Scene[NodeTag]): Bool =
        let living = getAll(scene) |> List.filter(d -> d#hp > 0);
        not List.isEmpty(living) and List.forAll(d -> d#usedStairs, living)

    /// 現在の生存味方の引き継ぎ用ステータス（HP / 武器 / 持ち物）を抽出する。
    /// 次フロアへ進む直前に呼び、構築後の `reconcileWithCarry` で復元する。
    pub def snapshotCarry(scene: Scene[NodeTag]): List[CarryData] =
        getAll(scene)
            |> List.filter(d -> d#hp > 0)
            |> List.map(d ->
                ({id = d#id, hp = d#hp, weapons = d#weapons, staves = d#staves,
                  consumables = d#consumables,
                  level = d#level, exp = d#exp,
                  stats = LevelSystem.statsOf(d#resource)}: CarryData))

    /// 次フロアを通常 build した直後の scene に、前フロアの引き継ぎ値を反映する。
    ///   - carry に居ない id（前フロアで戦死）の味方ノードを除去する
    ///   - 生存 id は HP / 武器 / 持ち物 / レベル / EXP / 成長後ステータスを carry で上書きし、
    ///     HP バーも更新する
    /// `waited` / `usedStairs` / `hidden` / `moveStepsTaken` は addOnePlayer が false / 0 で
    /// 作り直しているのでリセット不要（= フロア開始時に全員再行動可・たいきリセット）。
    pub def reconcileWithCarry(carry: List[CarryData], scene: Scene[NodeTag]): Scene[NodeTag] =
        let carryIds = carry |> List.map(c -> c#id);
        let pruned = getAll(scene)
            |> List.filter(d -> not List.exists(id -> id == d#id, carryIds))
            |> List.foldLeft((sc, d) -> Scene.removeAt(playerPath(d#id), sc), scene);
        List.foldLeft((sc, c) ->
            sc
                |> mapPlayer(c#id, d ->
                    {hp = c#hp, weapons = c#weapons, staves = c#staves,
                     consumables = c#consumables,
                     level = c#level, exp = c#exp,
                     resource = LevelSystem.withStats(c#stats, d#resource) | d})
                |> UnitHPBarScene.update(playerPath(c#id), c#hp),
            pruned, carry)

    // ────────────────────────────────────────────────────────
    // (G) 個別 getter（呼び出し側の便宜）
    // ────────────────────────────────────────────────────────

    pub def getGridPos(id: Int32, scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        match get(id, scene) {
            case Some(d) => d#gridPos
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def getMoveTiles(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => d#moveTiles
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def getHp(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => d#hp
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def isWaited(id: Int32, scene: Scene[NodeTag]): Bool =
        match get(id, scene) {
            case Some(d) => d#waited
            case None    => false
        }

    /// 指定 id のプレイヤーの武器インベントリを返す。武器が 1 つも無ければ Nil。
    pub def getWeapons(id: Int32, scene: Scene[NodeTag]): List[UnitCatalog.WeaponResource] =
        match get(id, scene) {
            case Some(d) => d#weapons
            case None    => Nil
        }

    /// 指定 id のプレイヤーが攻撃可能か（武器を 1 本以上持っているか）。
    pub def canAttack(id: Int32, scene: Scene[NodeTag]): Bool =
        not List.isEmpty(getWeapons(id, scene))

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
    pub def setSelectedItem(playerId: Int32, item: ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = Some(item) | d}, scene)

    /// 選択中アイテムをクリアする（サブメニュー確定後の後始末）。
    pub def clearSelectedItem(playerId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = None | d}, scene)

    /// 指定 idx の武器を装備（= weapons リストの先頭に移動）。
    /// 既に先頭なら何もしない。範囲外なら no-op。
    /// 「こうげき」は常に `weapons.head` を使うため、これで装備切り替えが反映される。
    pub def equipWeapon(playerId: Int32, idx: Int32,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {weapons = moveToHead(idx, d#weapons) | d}, scene)

    /// 指定 idx の武器をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropWeapon(playerId: Int32, idx: Int32,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {weapons = removeAt(idx, d#weapons) | d}, scene)

    /// 指定 idx の杖をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropStaff(playerId: Int32, idx: Int32,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {staves = removeAt(idx, d#staves) | d}, scene)

    /// 指定 idx の消費アイテムをインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropConsumable(playerId: Int32, idx: Int32,
                             scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {consumables = removeAt(idx, d#consumables) | d}, scene)

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
    pub def swapItem(args: {selfId = Int32, selfKind = ItemKind,
                              partnerId = Int32,
                              partnerKind = Option[ItemKind]},
                      scene: Scene[NodeTag]): Scene[NodeTag] =
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

    /// 指定 player の (kind = Weapon(idx) | Staff(idx)) のアイテム実体を返す。
    /// player が居ない / index が範囲外なら None
    /// (getWeapons / getStaves が居ない player に対し Nil を返すので、その経由で None)。
    /// 戻り値は `ItemScene.GroundItemKind` を流用 (= 「インベントリ可能なアイテム値」)。
    pub def getInventoryItem(playerId: Int32, kind: ItemKind, scene: Scene[NodeTag]):
            Option[ItemScene.GroundItemKind] =
        match kind {
            case ItemKind.Weapon(idx) =>
                List.nth(idx, getWeapons(playerId, scene))
                    |> Option.map(w -> ItemScene.GroundItemKind.WeaponItem(w))
            case ItemKind.Staff(idx) =>
                List.nth(idx, getStaves(playerId, scene))
                    |> Option.map(s -> ItemScene.GroundItemKind.StaffItem(s))
            case ItemKind.Consumable(idx) =>
                List.nth(idx, getConsumables(playerId, scene))
                    |> Option.map(c -> ItemScene.GroundItemKind.ConsumableItem(c))
        }

    /// 指定 player の `kind` のアイテムをインベントリから取り除く。
    /// `dropWeapon` / `dropStaff` のディスパッチ統合版。
    def removeInventoryItem(playerId: Int32, kind: ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        match kind {
            case ItemKind.Weapon(idx)     => dropWeapon(playerId, idx, scene)
            case ItemKind.Staff(idx)      => dropStaff(playerId, idx, scene)
            case ItemKind.Consumable(idx) => dropConsumable(playerId, idx, scene)
        }

    /// `partnerKind = None` (= 空スロット相手) の場合は no-op、Some なら removeInventoryItem。
    def removeOptInventoryItem(playerId: Int32, kindOpt: Option[ItemKind],
                                 scene: Scene[NodeTag]): Scene[NodeTag] =
        kindOpt
            |> Option.map(k -> removeInventoryItem(playerId, k, scene))
            |> Option.getWithDefault(scene)

    /// 指定 player のインベントリに `item` を追加
    /// (武器なら weapons 末尾、杖なら staves 末尾、消費アイテムなら consumables 末尾)。
    /// `ActionMenuScene.addPickedItem` と同じ追加ルール (ログを出さない版)。
    def addInventoryItem(playerId: Int32, item: ItemScene.GroundItemKind,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        match item {
            case ItemScene.GroundItemKind.WeaponItem(weapon)   =>
                mapPlayer(playerId,
                    d -> {weapons = List.append(d#weapons, weapon :: Nil) | d}, scene)
            case ItemScene.GroundItemKind.StaffItem(staff)     =>
                mapPlayer(playerId,
                    d -> {staves = List.append(d#staves, staff :: Nil) | d}, scene)
            case ItemScene.GroundItemKind.ConsumableItem(consumable) =>
                mapPlayer(playerId,
                    d -> {consumables = List.append(d#consumables, consumable :: Nil) | d}, scene)
        }

    /// `optItem = None` のときは no-op、Some なら addInventoryItem。
    def addOptInventoryItem(playerId: Int32, optItem: Option[ItemScene.GroundItemKind],
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        optItem
            |> Option.map(item -> addInventoryItem(playerId, item, scene))
            |> Option.getWithDefault(scene)

    /// `kind` 種別の在庫リスト末尾の 1 個を取り除く（`addInventoryItem` の逆操作）。
    /// 「ひろう」をキャンセルしたときに、末尾追加した仮取得アイテムを取り消すのに使う。
    /// 該当リストが空なら no-op。
    def removeLastInventoryItem(playerId: Int32, kind: ItemScene.GroundItemKind,
                                  scene: Scene[NodeTag]): Scene[NodeTag] =
        match kind {
            case ItemScene.GroundItemKind.WeaponItem(_)     =>
                let n = List.length(getWeapons(playerId, scene));
                if (n > 0) dropWeapon(playerId, n - 1, scene) else scene
            case ItemScene.GroundItemKind.StaffItem(_)      =>
                let n = List.length(getStaves(playerId, scene));
                if (n > 0) dropStaff(playerId, n - 1, scene) else scene
            case ItemScene.GroundItemKind.ConsumableItem(_) =>
                let n = List.length(getConsumables(playerId, scene));
                if (n > 0) dropConsumable(playerId, n - 1, scene) else scene
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
    def insertInventoryItem(playerId: Int32, kind: ItemKind,
                              item: ItemScene.GroundItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        match (kind, item) {
            case (ItemKind.Weapon(idx), ItemScene.GroundItemKind.WeaponItem(w))         =>
                mapPlayer(playerId, d -> {weapons = insertAt(idx, w, d#weapons) | d}, scene)
            case (ItemKind.Staff(idx), ItemScene.GroundItemKind.StaffItem(s))           =>
                mapPlayer(playerId, d -> {staves = insertAt(idx, s, d#staves) | d}, scene)
            case (ItemKind.Consumable(idx), ItemScene.GroundItemKind.ConsumableItem(c)) =>
                mapPlayer(playerId, d -> {consumables = insertAt(idx, c, d#consumables) | d}, scene)
            case _ => scene
        }

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// `WeaponMenuScene.onWeaponConfirmed` 経由でフェーズが AttackForecast に進み、
    /// `BattlePanelScene.confirm` がこの値を読んで実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択をキャンセルしたとき等）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    // ────────────────────────────────────────────────────────
    // (H) 体当たり攻撃モーション — AnimationPlayer ベース
    // ────────────────────────────────────────────────────────

    /// 体当たりの片道（origin → target）所要時間。Forward + Returning の合計が
    /// アニメ全長になる。視認性を保つため移動 (16/120) より速めに設定する。
    def attackPhaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒 / 片道

    /// `attack_lunge` アニメーション。
    /// - position track: origin → target → origin の 3 keyframe
    /// - method "attack:hit": 中点（target に重なる瞬間）で発火 → ダメージ適用 + SE 再生
    /// - finished: 攻撃モーション終了 → GameManager が waited 確定 / 次状態へ
    ///
    /// `targetPath` は攻撃側マーカー（PlayerScene なら `playerPath(id)`）。
    /// アニメ全長は 2 phase 分で、method "attack:hit" は phase 1 つぶん経過した時点
    /// （正規化 t = 0.5）で発火する。
    pub def attackLungeAnimation(targetPath: NodePath,
                                  originGrid: {x = Int32, y = Int32},
                                  targetGrid: {x = Int32, y = Int32}):
                                 AnimationPlayer.Animation =
        let phase    = attackPhaseDuration();
        let total    = Duration.add(phase, phase);
        let originW  = MapScene.cellCenter(originGrid);
        let targetW  = MapScene.cellCenter(targetGrid);
        let posKeys: List[AnimationPlayer.PosKey] =
            ({time = 0.0, pos = originW}: AnimationPlayer.PosKey) ::
            ({time = 0.5, pos = targetW}: AnimationPlayer.PosKey) ::
            ({time = 1.0, pos = originW}: AnimationPlayer.PosKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetPath,
            prop   = AnimationPlayer.Property.Position(posKeys)
        };
        let methodHit: AnimationPlayer.MethodKey = {
            time = phase,
            name = AnimEvent.tagToString(AnimEvent.Tag.AttackHit)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.AttackLunge),
            length  = total,
            tracks  = track :: Nil,
            methods = methodHit :: Nil
        }

    /// プレイヤー id の体当たり攻撃モーションを開始する。
    /// AnimationPlayer に `attack_lunge` を登録し、`attackTargetId = Some(targetEnemyId)` を
    /// 立てるだけ。中点で `attack:hit` メソッド、終端で finished が GameManager に届き、
    /// それぞれダメージ適用と waited 確定が行われる。
    /// インベントリが空（`weapons = Nil`）のプレイヤーは攻撃に到達してはいけない設計で、
    /// 防御的に no-op する（呼び出し側 = PlayerAttackRangeScene/TurnRules で禁止される）。
    pub def startAttack(id: Int32, targetEnemyId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                if (List.isEmpty(d#weapons)) scene
                else {
                    AnimationPlayer.play(playerPath(id),
                        attackLungeAnimation(playerPath(id), d#gridPos, targetGrid));
                    mapPlayer(id, dd -> {attackTargetId = Some(targetEnemyId) | dd}, scene)
                }
        }


    /// scene 内に攻撃モーション中のプレイヤーが居れば true。
    /// stepEnemyTurn 等の「敵の行動を進めて良いか」のガードに使う将来用の保険。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    /// `attack:hit` メソッド発火時に GameManager から呼ばれるダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵への攻撃を解決する。
    /// 命中ロールは `applyDamageToEnemy` 側で行い、命中なら SE + ダメージ + ログ、
    /// 回避なら SE を鳴らさず "miss" 表示のみ。HP <= 0 なら death_blink を開始する。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
                              GameLogger.GameLogger, Math.Random} =
        match get(playerId, scene) {
            case None    => scene
            case Some(d) =>
                match d#attackTargetId {
                    case None         => scene
                    case Some(enemyId) =>
                        applyDamageToEnemy(playerId, d, enemyId, scene)
                }
        }

    /// `attack_lunge` finished 時に GameManager から呼ばれる。
    /// `attackTargetId` をクリアする。waited 確定 / 次フェーズへの遷移は GameManager の
    /// `commitWaitedAndAdvance` が担当する。
    pub def clearAttackTarget(playerId: Int32,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// PlayerAttack / WeaponSelect / ActionMenu「たいき」を抜けるときの共通処理:
    ///   1) 選択中駒を waited に (灰色 modulate)
    ///   2) 選択クリア
    ///   3) 残ったアクティブが居れば PlayerCursor に戻り、次セレクト準備
    ///      居なければ `EnemyTurnDriverScene.beginTurn` で敵ターン開始
    /// 複数 Scene 跨ぎなので「次フェーズ判定」をまとめてここに置く。
    /// ActionMenu / EnemyScene / BattlePanel / EnemyTurnDriverScene / TurnInputBridge から
    /// 呼ばれる。
    /// レベルアップ表示待ち (pendingLevelUp = Some) の味方が 1 人でも居るか。
    /// 自分の攻撃（commitWaitedAndAdvance）でも敵ターンの反撃（endTurn）でも、この判定で
    /// ステータス変化パネルへ割り込む。
    pub def anyPendingLevelUp(scene: Scene[NodeTag]): Bool =
        getAll(scene) |> List.exists(d -> Option.nonEmpty(d#pendingLevelUp))

    pub def commitWaitedAndAdvance(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        // レベルアップ表示待ちの味方が居れば、ターンを進めずステータス変化パネル (LevelUpView) へ割り込む。
        // パネルを閉じると LevelUpPanelScene.confirm が pendingLevelUp を消して再度ここを呼ぶので、
        // そのとき保留が無くなって通常の確定・前進に進む。Kill / Counter / Commit の 3 経路すべてが
        // 最後にここを通るため、自分の攻撃で得たレベルアップ表示の割り込みは 1 箇所で足りる。
        if (anyPendingLevelUp(scene))
            PhaseTransitions.enterLevelUpView(scene)
        else
        let withWaited = match SelectedPlayer.State.get()#id {
            case Some(id) => setWaited(id, scene)
            case None     => scene   // 防御的 (選択なしで Attack に入ることは想定外)
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        // 次の active 味方の gridPos をローカル `withWaited` から直接拾って渡す。
        // `enterPlayerCursor` 側の PartyQuery フォールバックは sceneRef (frame 冒頭の snapshot)
        // を読むので、たった今 setWaited した駒をまだ active として返してしまう。
        match firstActive(withWaited) {
            case Some(next) =>
                PhaseTransitions.enterPlayerCursorAt(next#gridPos, withWaited)
            case None       =>
                EnemyTurnDriverScene.beginTurn(withWaited)
        }

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理 (味方側)。
    /// 攻撃ダメージ適用本体は既存 `applyAttackHit` を呼ぶ。
    /// 名前は「event 受信」の semantics を明示するための薄ラッパ。
    pub def onAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        applyAttackHit(playerId, scene)

    /// AnimationPlayer の `attack_lunge` finished イベント受信時の処理 (味方側)。
    /// 2 通りある:
    ///   - `PlayerAttackHold` (= 味方主攻撃の完了) → CounterAttackRules.decide で分岐:
    ///       Kill (敵瀕死) / Counter (敵反撃) / Commit (waited 確定)。
    ///   - `EnemyTurn` (= 敵攻撃に対する味方反撃の完了) → 単純に attackTargetId クリア。
    ///       次フレーム以降で EnemyTurnDriver が PlayerScene.anyAttacking が false に
    ///       なったのを見て次の step に進む。FE 風で「反撃の反撃」は実装しない。
    pub def onAttackLungeDone(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        if (TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn) {
            // 敵ターン中の味方反撃が完了した。反撃でレベルアップしていれば、その場で
            // （反撃ごとに）ステータス変化パネルへ割り込む。閉じると敵ターンに戻って続行する。
            let cleared = clearAttackTarget(playerId, scene);
            if (anyPendingLevelUp(cleared))
                PhaseTransitions.enterLevelUpView(cleared)
            else
                cleared
        } else match get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                let target = player#attackTargetId
                    |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
                match CounterAttackRules.decide(player, target) {
                    case CounterAttackRules.Outcome.Kill =>
                        let cleared = clearAttackTarget(playerId, scene);
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        Pacing.State.hold(700 |> Duration.millis);
                        cleared
                    case CounterAttackRules.Outcome.Counter(enemyId) =>
                        let cleared = clearAttackTarget(playerId, scene);
                        match get(playerId, cleared) {
                            case None    => commitWaitedAndAdvance(cleared)
                            case Some(p) =>
                                GameLogger.enemyLog("敵${enemyId} の反撃");
                                EnemyScene.startAttack(enemyId, playerId, p#gridPos, cleared)
                        }
                    case CounterAttackRules.Outcome.Commit =>
                        let cleared = clearAttackTarget(playerId, scene);
                        commitWaitedAndAdvance(cleared)
                }
        }

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

    /// 敵 id にダメージを与える。攻撃力は `力(unit#attack) + 装備中武器の攻撃力` で、
    /// `Combat.attackDamage(総合攻撃力, 防御者#defense)` から素ダメージを得て
    /// `Combat.damage` で HP 減算 + 死亡判定。HP <= 0 で死亡演出を開始する。
    /// 装備中武器は `weapons.head`（= リストの先頭）。「装備」操作で先頭を入れ替えると
    /// 攻撃に使われる武器が切り替わる。攻撃成立後に耐久度を 1 減らし、0 になったら
    /// インベントリから取り除き「P{N} の {武器名} がこわれた」ログを出す。
    /// ログはスペック準拠で「P{N} → 敵{M} に Xダメージ」 / 撃破時「P{N} → 敵{M} を撃破」。
    /// 命中ロール用の 0..99 の一様乱数。`Combat.isHit(hitRate, roll)` に渡す。
    def rollPercent(): Int32 \ Math.Random =
        Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64() * 100.0))

    /// 命中ロール: 攻撃側の技・幸運・武器命中と防御側の速さ・幸運から `Combat.hitRate`
    /// を求め、0..99 の乱数と比較する（`Combat.isHit`）。命中なら SE("damage") を鳴らし
    /// ダメージ + 数値ポップアップ、回避なら SE を鳴らさず "miss" 表示のみで HP は変えない。
    /// 命中/回避どちらでも攻撃したので武器の耐久度は 1 減る。
    /// インベントリ空 / 敵不在ならば防御的に no-op。
    def applyDamageToEnemy(playerId: Int32, player: Data, enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                               GameEngine.Game, GameLogger.GameLogger, Math.Random} =
        // 常に先頭武器（= 装備中）を使う。空なら no-op。
        let idx = 0;
        match (List.nth(idx, player#weapons), EnemyScene.get(enemyId, scene)) {
            case (None, _)        => scene
            case (_, None)        => scene
            case (Some(weapon), Some(enemy)) =>
                let phys = UnitCatalog.isPhysical(weapon#weaponType);
                // 苦手武器なら威力・命中を 80% に。武器タイプ習熟（得意=100%）を 1 か所で解決し、
                // 命中判定とダメージ計算の両方に同じ補正を効かせる（予報 estimate と一致させる）。
                let proficient  = UnitCatalog.proficientWith(player#resource, weapon#weaponType);
                let totalAttack = Combat.attackStatFor(player#resource#attack,
                                                       player#resource#magicAttack,
                                                       weapon#attack, phys);
                let (adjAttack, adjHit) = Combat.proficiencyAdjust(totalAttack, weapon#hit, proficient);
                // 武器相性: 攻撃側（味方）の武器 vs 敵の装備武器。敵が未装備なら中立。
                let rel = WeaponTriangle.relationOpt(weapon#weaponType,
                                                     enemy#weapon |> Option.map(w -> w#weaponType));
                let hitChance = Combat.hitRate(player#resource#skill, player#resource#luck,
                                               adjHit,
                                               enemy#resource#speed, enemy#resource#luck, rel);
                let roll = rollPercent();
                let popupPos = MapScene.cellCenter(enemy#gridPos);
                let popupColor = DamagePopupScene.damageToEnemyColor();
                // 命中なら EXP を得る（回避時は 0）。獲得量はレベル差から Combat.battleExp が算出する。
                let (afterDamage, expGain) =
                    if (not Combat.isHit(hitChance, roll)) {
                        // 回避: miss SE を鳴らして "miss" を浮かす。HP も死亡演出も無し。
                        GameLogger.playerLog("P${playerId} → 敵${enemyId} ミス");
                        AudioStreamPlayer.play("miss");
                        (DamagePopupScene.emitText(popupPos, "miss", popupColor, scene), 0)
                    } else {
                        // 命中: SE を鳴らしダメージ適用 + 数値ポップアップ。
                        AudioStreamPlayer.play("damage");
                        let targetDef   = Combat.defenseStatFor(enemy#resource#defense,
                                                                enemy#resource#magicDefense,
                                                                phys);
                        // 威力は習熟補正済み（adjAttack）。苦手なら 80%。
                        let dmg    = Combat.attackDamage(adjAttack, targetDef, rel);
                        let result = Combat.damage(hp = enemy#hp, amount = dmg);
                        let withPopup = DamagePopupScene.emit(popupPos, dmg, popupColor, scene);
                        let sceneAfter =
                            if (result#isDead) {
                                GameLogger.playerLog("P${playerId} → 敵${enemyId} を撃破");
                                withPopup
                                    |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
                                    |> EnemyScene.startDeathAnimation(enemyId)
                            } else {
                                GameLogger.playerLog("P${playerId} → 敵${enemyId} に ${dmg}ダメージ");
                                withPopup
                                    |> EnemyScene.mapEnemy(enemyId,
                                        enemyData -> {hp = result#newHp | enemyData})
                                    |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
                            };
                        (sceneAfter, Combat.battleExp(enemy#resource#level, player#level, result#isDead))
                    };
                let consumed = Weapon.consume(weapon);
                let newWeapons = match consumed {
                    case Some(updated) =>
                        // 同じ index の要素だけ更新後の値に差し替える
                        List.mapWithIndex(i -> w -> if (i == idx) updated else w, player#weapons)
                    case None =>
                        // 壊れた → index 位置の要素を取り除く
                        List.mapWithIndex(i -> w -> (i, w), player#weapons)
                            |> List.filter(pair -> let (i, _) = pair; i != idx)
                            |> List.map(pair -> let (_, w) = pair; w)
                };
                if (Option.isEmpty(consumed))
                    GameLogger.playerLog("P${playerId} の ${weapon#name} がこわれた")
                else ();
                let withWeapons = mapPlayer(playerId,
                    d -> {weapons = newWeapons | d}, afterDamage);
                // 命中していれば EXP を加算する。自分の攻撃でも敵ターンの反撃でも同様（FE 流）。
                // 反撃で得たレベルアップは敵ターン終了後にまとめて表示する
                // （pendingLevelUp を立て、EnemyTurnDriverScene.endTurn が LevelUpView へ流す）。
                if (expGain <= 0)
                    withWeapons
                else
                    applyExpGain(playerId, expGain, withWeapons)
        }

    /// 6 ステータスぶんの成長判定用乱数 (各 0..99) をまとめて振る。
    /// 値の意味づけ・成長判定は LevelSystem 側のピュア関数が行う。
    def rollGrowth(): LevelSystem.Rolls \ Math.Random =
        {hp           = rollPercent(),
         attack       = rollPercent(),
         defense      = rollPercent(),
         magicAttack  = rollPercent(),
         magicDefense = rollPercent(),
         speed        = rollPercent(),
         skill        = rollPercent(),
         luck         = rollPercent()}

    /// 味方 id に EXP を加算し、100 到達ならレベルアップを解決する。
    ///   - レベルアップしない → `exp` だけ更新。
    ///   - レベルアップする   → 成長ロールを振って各ステータスを成長させ、最大 HP が
    ///     増えた分だけ現在 HP も増やし、`pendingLevelUp` に結果を積む（パネル表示の合図）。
    /// `pendingLevelUp` が立つと commitWaitedAndAdvance がターンを進めずパネルへ割り込む。
    def applyExpGain(playerId: Int32, expGain: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, GameLogger.GameLogger} =
        match get(playerId, scene) {
            case None    => scene
            case Some(d) =>
                let outcome = LevelSystem.gainExp(d#exp, expGain);
                if (not outcome#levelUp)
                    mapPlayer(playerId, dd -> {exp = outcome#exp | dd}, scene)
                else {
                    let rolls  = rollGrowth();
                    let before = LevelSystem.statsOf(d#resource);
                    let after  = LevelSystem.applyGrowth(before, d#resource#growthRates, rolls);
                    let hpGain = after#hp - before#hp;
                    let result = LevelSystem.buildResult(d#resource#description, d#level,
                                                         before, after);
                    let newHp  = d#hp + hpGain;
                    GameLogger.playerLog("P${playerId} Lv${d#level} → Lv${d#level + 1}");
                    mapPlayer(playerId, dd ->
                        {exp            = outcome#exp,
                         level          = dd#level + 1,
                         resource       = LevelSystem.withStats(after, dd#resource),
                         hp             = newHp,
                         pendingLevelUp = Some(result) | dd}, scene)
                        |> UnitHPBarScene.update(playerPath(playerId), newHp)
                }
        }

    // ────────────────────────────────────────────────────────
    // (I) 杖の発動 — direction → 直線レイキャスト → 効果適用 → ターン進行
    // ────────────────────────────────────────────────────────

    /// 杖を発動する。`StaffAim` フェーズで方向キーが押された瞬間に呼ばれる。
    ///   1. プレイヤーの `staves[staffIdx]` と `gridPos` / `magicAttack` を取り出す
    ///   2. `Board.rayCast` で射線上の最初の当たり対象を `RayHit` で得る
    ///   3. `staff#effect × hit` で効果を分岐適用（Heal / Blowback / Swap）
    ///   4. `Staff.consume` で耐久 -1、0 なら staves から除去 + 破損ログ
    ///   5. 選択中アイテムをクリア → `commitWaitedAndAdvance` で waited 確定し次ターンへ
    ///
    /// 杖は CounterAttackRules を経由しない（反撃なし）。
    /// 該当プレイヤー / 杖が見つからない場合は防御的に no-op。
    pub def applyStaffCast(playerId: Int32, staffIdx: Int32,
                             direction: Staff.Direction,
                             scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        match get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                match List.nth(staffIdx, player#staves) {
                    case None        => scene
                    case Some(staff) =>
                        let board = BoardQuery.board();
                        let dir   = Staff.toVec2i(direction);
                        // 杖は射程を持たない: 盤面外は壁扱いなので、十分大きい上限を渡せば
                        // 必ず壁または駒で止まる（無限射程と等価）。
                        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
                        // 回復の杖が味方/敵に当たった瞬間に回復音を鳴らす（空振りは鳴らさない）
                        match (staff#effect, hit) {
                            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(_, _)) =>
                                AudioStreamPlayer.play("cure")
                            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(_, _)) =>
                                AudioStreamPlayer.play("cure")
                            case _ => ()
                        };
                        let afterEffect = applyStaffEffect(playerId, player, staff,
                                                            dir, hit, scene);
                        let afterConsume = consumeStaff(playerId, staffIdx, staff, afterEffect);
                        let cleared = clearSelectedItem(playerId, afterConsume);
                        commitWaitedAndAdvance(cleared)
                }
        }

    /// 杖の射程上限。盤面の最大寸法より大きければ実質「無限」として機能する。
    def staffMaxRange(): Int32 = 1000

    /// 杖を構えるときの初期照準方向。選択中アイテムが回復の杖で、HP が減っている味方が
    /// 居れば、一番ふさわしい味方の方向(4方位)を返す。同じ行/列に並ぶ(=射線が届く)味方を
    /// 優先し、無ければ最も近い負傷味方の主軸方向を返す。
    /// 回復杖でない / 負傷味方が居ないなら None（呼び出し側はデフォルト Up のまま）。
    /// ネストした match を避けるため Option の forM で短絡的に畳む。
    pub def staffAimInitialDirection(playerId: Int32, scene: Scene[NodeTag]):
            Option[Staff.Direction] =
        forM (
            player <- get(playerId, scene);
            idx    <- selectedStaffIndex(player);
            staff  <- List.nth(idx, player#staves);
            dir    <- healDirectionFor(player, playerId, staff, scene)
        ) yield dir

    /// 選択中アイテムが杖ならその staves index、それ以外は None。
    def selectedStaffIndex(player: Data): Option[Int32] =
        match player#selectedItem {
            case Some(ItemKind.Staff(idx)) => Some(idx)
            case _                          => None
        }

    /// 回復杖なら負傷味方への方向、それ以外（攻撃杖等）は None。
    def healDirectionFor(player: Data, playerId: Int32, staff: Staff.StaffResource,
                          scene: Scene[NodeTag]): Option[Staff.Direction] =
        if (staff#effect == Staff.StaffEffect.Heal)
            pickHealDirection(player#gridPos, injuredAlliesExcept(playerId, scene))
        else None

    /// 自分以外で HP が最大未満（負傷している）の味方一覧。
    def injuredAlliesExcept(playerId: Int32, scene: Scene[NodeTag]): List[Data] =
        getAll(scene) |> List.filter(a -> a#id != playerId and a#hp < a#resource#hp)

    /// 負傷味方リストから構える 4 方位を選ぶ。同じ行/列に整列している味方を優先し、
    /// 次にマンハッタン距離が近い味方を選ぶ。空なら None。
    def pickHealDirection(origin: {x = Int32, y = Int32}, allies: List[Data]):
            Option[Staff.Direction] =
        let scored = allies |> List.map(a -> {
            let dx = a#gridPos#x - origin#x;
            let dy = a#gridPos#y - origin#y;
            (dx == 0 or dy == 0, Int32.abs(dx) + Int32.abs(dy), deltaToDirection(dx, dy))
        });
        let best = List.foldLeft((acc, cur) -> match acc {
            case None    => Some(cur)
            case Some(b) =>
                let (ba, bd, _) = b;
                let (ca, cd, _) = cur;
                if ((ca and not ba) or (ca == ba and cd < bd)) Some(cur) else acc
        }, None, scored);
        Option.map(t -> { let (_ali, _dist, d) = t; d }, best)

    /// グリッドの差分ベクトルを 4 方位に丸める。主軸(絶対値が大きい方)を採用し、
    /// 整列している(片軸が 0)場合はその軸方向になる。
    def deltaToDirection(dx: Int32, dy: Int32): Staff.Direction =
        if (Int32.abs(dx) >= Int32.abs(dy))
            (if (dx < 0) Staff.Direction.Left else Staff.Direction.Right)
        else
            (if (dy < 0) Staff.Direction.Up else Staff.Direction.Down)

    /// `staff#effect × hit` の組み合わせで効果を適用する。
    /// 9 通り（うち実意味のあるのは 6 通り）の分岐は table comment を参照。
    def applyStaffEffect(playerId: Int32, player: Data,
                          staff: Staff.StaffResource,
                          dir: {x = Int32, y = Int32},
                          hit: RayHit,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger} =
        match (staff#effect, hit) {
            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(targetId, _)) =>
                applyHealToPlayer(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(targetId, _)) =>
                applyHealToEnemy(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitPlayer(targetId, hitCell)) =>
                applyBlowbackToPlayer(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitEnemy(targetId, hitCell)) =>
                applyBlowbackToEnemy(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitPlayer(otherId, otherCell)) =>
                applySwapWithPlayer(playerId, player#gridPos, otherId, otherCell, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitEnemy(enemyId, enemyCell)) =>
                applySwapWithEnemy(playerId, player#gridPos, enemyId, enemyCell, scene)
            // 空振り系: 効果なし、ログだけ（実際の杖名を表示する）
            case (Staff.StaffEffect.Heal, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Blowback, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Swap, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は消えた");
                scene
        }

    /// ライブ × 味方: 対象味方の HP を「魔力 + 10」回復、HPBar 更新、ログ。
    def applyHealToPlayer(srcId: Int32, player: Data, targetId: Int32,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack + 10;
        match get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let result = Combat.heal(target#hp, target#resource#hp, amount);
                let healed = result#newHp - target#hp;
                GameLogger.playerLog("P${srcId} → P${targetId} を ${healed}回復");
                scene
                    |> mapPlayer(targetId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(playerPath(targetId), result#newHp)
        }

    /// ライブ × 敵: 敵の HP を「魔力 + 10」回復（敵にも効く仕様）。
    def applyHealToEnemy(srcId: Int32, player: Data, enemyId: Int32,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack + 10;
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let result = Combat.heal(enemy#hp, enemy#resource#hp, amount);
                let healed = result#newHp - enemy#hp;
                GameLogger.playerLog("P${srcId} → 敵${enemyId} を ${healed}回復");
                scene
                    |> EnemyScene.mapEnemy(enemyId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
        }

    /// ふきとばし × 味方: 1 ダメ → 死亡なら止まる、生存なら最終位置までスナップで移動。
    /// 仕様確認: MVP では「最終位置に瞬間移動 + ダメージ popup」で済ませる
    /// （1 マスずつ tween は engine の sequence 機能が要るため、後続タスクで強化）。
    def applyBlowbackToPlayer(srcId: Int32, targetId: Int32,
                                hitCell: {x = Int32, y = Int32},
                                dir: {x = Int32, y = Int32},
                                scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        match get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let dmgResult = Combat.damage(hp = target#hp, amount = 1);
                let withDamage = scene
                    |> mapPlayer(targetId, d -> {hp = dmgResult#newHp | d})
                    |> UnitHPBarScene.update(playerPath(targetId), dmgResult#newHp);
                GameLogger.playerLog(
                    "P${srcId} → P${targetId} を ふきとばし (1ダメージ)");
                if (dmgResult#isDead) withDamage
                else applyBlowbackMove(targetId, hitCell, dir, withDamage,
                                        cell -> snapTo(targetId, cell, withDamage))
        }

    /// ふきとばし × 敵: 1 ダメ → 死亡なら startDeathAnimation、生存なら最終位置に snapTo。
    def applyBlowbackToEnemy(srcId: Int32, enemyId: Int32,
                               hitCell: {x = Int32, y = Int32},
                               dir: {x = Int32, y = Int32},
                               scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                GameLogger.GameLogger} =
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let dmgResult = Combat.damage(hp = enemy#hp, amount = 1);
                if (dmgResult#isDead) {
                    GameLogger.playerLog("P${srcId} → 敵${enemyId} を ふきとばし撃破");
                    scene
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), 0)
                        |> EnemyScene.startDeathAnimation(enemyId)
                } else {
                    let withDamage = scene
                        |> EnemyScene.mapEnemy(enemyId, d -> {hp = dmgResult#newHp | d})
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), dmgResult#newHp);
                    GameLogger.playerLog(
                        "P${srcId} → 敵${enemyId} を ふきとばし (1ダメージ)");
                    applyBlowbackMove(enemyId, hitCell, dir, withDamage,
                                       cell -> EnemyScene.snapTo(enemyId, cell, withDamage))
                }
        }

    /// 押される対象の最終位置を `Board.knockbackPath` で計算し、`moveFn` で動かす。
    /// 経路が空（押される先がない）なら何もしない。
    def applyBlowbackMove(_targetId: Int32,
                           hitCell: {x = Int32, y = Int32},
                           dir: {x = Int32, y = Int32},
                           scene: Scene[NodeTag],
                           moveFn: {x = Int32, y = Int32} -> Scene[NodeTag] \ Tween.Scheduler):
            Scene[NodeTag] \ Tween.Scheduler =
        let board: Board = BoardSnapshot.fromScene(scene);
        let path = Board.knockbackPath(hitCell, dir, board);
        match List.last(path) {
            case None       => scene
            case Some(last) => moveFn(last)
        }

    /// いれかえ × 味方: 自分と相手の gridPos を瞬間 swap する。
    def applySwapWithPlayer(srcId: Int32, srcCell: {x = Int32, y = Int32},
                              otherId: Int32, otherCell: {x = Int32, y = Int32},
                              scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と P${otherId} がいれかわった");
        scene
            |> snapTo(srcId, otherCell)
            |> snapTo(otherId, srcCell)

    /// いれかえ × 敵: 自分（Player）と敵を交換する。
    def applySwapWithEnemy(srcId: Int32, srcCell: {x = Int32, y = Int32},
                             enemyId: Int32, enemyCell: {x = Int32, y = Int32},
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と 敵${enemyId} がいれかわった");
        scene
            |> snapTo(srcId, enemyCell)
            |> EnemyScene.snapTo(enemyId, srcCell)

    /// 杖の耐久を 1 減らし、0 なら staves から除去 + 破損ログ。
    def consumeStaff(playerId: Int32, staffIdx: Int32, staff: Staff.StaffResource,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Staff.consume(staff);
        let newStaves = replaceOrDropAt(staffIdx, consumed, getStaves(playerId, scene));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${staff#name} がこわれた")
        else ();
        mapPlayer(playerId, d -> {staves = newStaves | d}, scene)

    /// 消費アイテム（きずぐすり等）を「つかう」: 使用者自身を回復し、耐久を 1 減らして
    /// 0 なら一覧から除去、選択クリア → ターン消費して次へ進む。杖と違い方向・対象選択は無いので
    /// `StaffAim` のような中間フェーズは経由せず、メニュー確定経路でそのまま完結する。
    /// BoardQuery / GameEngine.Game は不要（`commitWaitedAndAdvance` の effect 集合で足りる）。
    /// 該当プレイヤー / アイテムが見つからない場合は防御的に no-op。
    pub def applyConsumableUse(playerId: Int32, idx: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, GameEngine.Audio} =
        match get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                match List.nth(idx, player#consumables) {
                    case None       => scene
                    case Some(item) =>
                        // きずぐすり等の消費アイテムは使用＝回復成立なので回復音を鳴らす
                        AudioStreamPlayer.play("cure");
                        let afterHeal    = applyConsumableHeal(playerId, player, item, scene);
                        let afterConsume = consumeConsumable(playerId, idx, item, afterHeal);
                        let cleared      = clearSelectedItem(playerId, afterConsume);
                        commitWaitedAndAdvance(cleared)
                }
        }

    /// 消費アイテムで使用者自身の HP を `healAmount` 回復、HPBar 更新、ログ。
    def applyConsumableHeal(playerId: Int32, player: Data,
                             item: Consumable.ConsumableResource,
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let result = Combat.heal(player#hp, player#resource#hp, item#healAmount);
        let healed = result#newHp - player#hp;
        GameLogger.playerLog("P${playerId} は ${item#name} で ${healed}回復");
        scene
            |> mapPlayer(playerId, d -> {hp = result#newHp | d})
            |> UnitHPBarScene.update(playerPath(playerId), result#newHp)

    /// 消費アイテムの耐久（使用回数）を 1 減らし、0 なら consumables から除去 + 使い切りログ。
    /// `consumeStaff` と同形。
    def consumeConsumable(playerId: Int32, idx: Int32,
                           item: Consumable.ConsumableResource,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Consumable.consume(item);
        let newConsumables = replaceOrDropAt(idx, consumed, getConsumables(playerId, scene));
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${item#name} を使い切った")
        else ();
        mapPlayer(playerId, d -> {consumables = newConsumables | d}, scene)

    /// idx 番目を `updatedOpt` の中身で差し替えたリストを返す。`None`（耐久 0 で消滅）なら
    /// その要素を除去する。`consumeStaff` / `consumeConsumable` で共有する
    /// 「耐久を減らした結果の差し替え or 除去」処理。
    def replaceOrDropAt(idx: Int32, updatedOpt: Option[a], list: List[a]): List[a] =
        match updatedOpt {
            case Some(updated) =>
                List.mapWithIndex(i -> x -> if (i == idx) updated else x, list)
            case None =>
                dropAt(idx, list)
        }

    /// List から `idx` 番目を取り除く（範囲外なら元のリスト）。
    def dropAt(idx: Int32, list: List[a]): List[a] =
        List.zipWithIndex(list)
            |> List.filter(pair -> let (i, _) = pair; i != idx)
            |> List.map(pair -> let (_, x) = pair; x)
}
