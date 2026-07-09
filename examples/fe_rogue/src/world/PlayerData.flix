/// PlayerData — 味方駒(Piece)のドメインデータ型。
///
/// 駒ドメインデータを scenes/ から切り離し、engine・game 双方が参照できる
/// 単一源泉とするために game/ に置く。
/// game/ 純ロジック(CounterAttackRules 等)はここに依存してよい。
/// game/ から scenes/ の型を参照することは禁じる（依存方向の不変条件）。
mod PlayerData {

    /// ItemMenu で選択中のアイテムの種別と inventory 内 index。
    /// 武器と杖は別リストに格納されているため、どちらに属するかを ADT で区別する。
    /// `Order` は複数選択のマーク集合（`Set[ItemKind]`）を作るために導出する。
    pub enum ItemKind with Eq, ToString, Order {
        case Weapon(Int32)     // weapons リスト上の index
        case Staff(Int32)      // staves リスト上の index
        case Consumable(Int32) // consumables リスト上の index
        case Ring(Int32)       // rings リスト上の index
    }

    // ────────────────────────────────────────────────────────
    // 複数選択（マーク）の純粋ヘルパー
    //   アイテムメニューの一括捨て・交換メニューの一括渡しが共用する。
    //   どれも副作用なしの値変換なので単体テストしやすい。
    // ────────────────────────────────────────────────────────

    /// マークを 1 つ切り替える。すでに印が付いていれば外し、無ければ付ける。
    pub def toggleMark(kind: ItemKind, marks: Set[ItemKind]): Set[ItemKind] =
        if (Set.memberOf(kind, marks)) Set.remove(kind, marks)
        else Set.insert(kind, marks)

    /// 並べ替え用のキー。「種別ごとのまとまり、その中は index の大きい順」になるよう
    /// (種別の順位, -index) を返す。昇順ソートすると武器→杖→消費の順、各まとまりは
    /// index の大きいものが先に来る。
    def markSortKey(kind: ItemKind): (Int32, Int32) = match kind {
        case ItemKind.Weapon(i)     => (0, 0 - i)
        case ItemKind.Staff(i)      => (1, 0 - i)
        case ItemKind.Consumable(i) => (2, 0 - i)
        case ItemKind.Ring(i)       => (3, 0 - i)
    }

    /// マーク集合を「各リスト内で index の大きい順」に並べた列にする。
    /// 武器・杖・消費アイテムは別々のリストなのでまとまり同士の順序は結果に影響しない。
    /// まとめて削除・転送するときは index の大きい方から処理すれば、まだ処理していない
    /// 小さい index がずれない（リストの前詰めで番号が繰り上がるのを避ける）。
    pub def marksDescendingPerList(marks: Set[ItemKind]): List[ItemKind] =
        Set.toList(marks) |> List.sortBy(markSortKey)

    /// マーク集合を「渡す分」と「手元に残す分」に分ける。最大 `freeSlots` 個までを
    /// index の大きい順に渡し、入りきらない残りを返す。相手が満杯のときの部分転送に使う。
    /// 戻り値は (渡す, 残す)。`freeSlots` が 0 以下なら全部残す。
    pub def planBulkTransfer(marks: Set[ItemKind], freeSlots: Int32):
            (List[ItemKind], List[ItemKind]) =
        let ordered = marksDescendingPerList(marks);
        let take = Int32.max(0, freeSlots);
        (List.take(take, ordered), List.drop(take, ordered))

    /// プレイヤー固有の状態。
    /// `id` は連番（Player_<id> ノード名と一致）。
    /// `gridPos` は盤面論理位置（`moveTo` で更新）。
    /// `moveTiles` は 1 ターン移動力。
    /// `hp` は残り体力（最小 0）。0 を検知した呼び手がゲームオーバー処理を行う責務を持つ。
    /// `waited` は行動済みフラグ（灰色表示・選択不可）。
    /// `attackTargetId` は体当たり攻撃中の被攻撃対象 id（Some の間はモーション実行中）。
    /// `resource` はユニット定義テンプレート（Spawn と同一参照を保持し、復元時に Spawn を再構築できる）。
    /// `weapons` は武器インベントリ（先頭が装備中）。
    /// `staves` は杖インベントリ（ItemMenu で使用）。
    /// `consumables` は消費アイテムインベントリ。
    /// `selectedItem` は ItemMenu で選択中の種別と index。
    /// `moveStepsTaken` は AutoMove 当ターンに進行済みマス数（範囲 0..moveTiles）。
    ///   ターン開始時に 0 にリセットされ、moveTiles に達した時点で移動完了とみなす。
    /// `facing` は向き（`walk_<dir>` アニメーション用）。
    /// `hidden` は集合・階段退場で盤面から除外されている状態。
    /// `usedStairs` は階段退場フラグ。
    /// `level` は現レベル（フロア跨ぎで継承）。
    /// `exp` は経験値（0..99）。
    /// `pendingLevelUp` は直近レベルアップ結果。LevelUpPanelUi が演出を終えた後に None へ戻す責務を持つ。
    /// ── Phase D field×source 分類（D1 design pin・2026-06-29・後段 slice を gate する先決成果物）─────
    /// **昇格基準**: (W)World-store 権威 = System が authoritative I/O に要る／既昇格と対称な sim turn-state／
    /// sim 解決を駆動する mutable state。(R)scene-backed 残置 = pure view/render/modal-trigger/UI-cursor/
    /// template で UI のみ消費・sim 非駆動（= hybrid-A 正規形・DoD#2 が許容＝「物理消去」でなく「分類された残置のみ」）。
    /// **PlayerData.Data 23 field**:
    ///   (W 済): id・gridPos・hp・waited・attackTargetId・hidden・level・exp・followUpUsed
    ///   (W 予定): weapons/staves/consumables/rings/ringEquipped(D3-4)・baseStats←resource 投影(D5)・moveTiles(D6.5)・statuses(D12)
    ///   (S→W micro-store D13a): moveStepsTaken・usedStairs（System 駆動 turn-state ゆえ enemy acted と同型に昇格）
    ///   (R 残置): classId(snapshot id)・resource(sprite/stat template・baseStats だけ store 投影)・
    ///             selectedItem(UI 選択)・facing(render 向き)・pendingLevelUp(LevelUpPanel modal trigger・sim 非駆動)
    /// **EnemyData.Data 17 field**: (W) id/gridPos/hp/alerted/isDying/attackTargetId/prevPos/followUpUsed/bottleUsed/
    ///   weapon/ring(単数射影)/baseStats/moveTiles/statuses(D12)・(S→W) acted(D13a)・(R) resource/resourceId/homeModuleIdx。
    /// 各 slice は **store dual-write → `[XXX DIFF]` 無音実証(実機 run) → reader-flip** の discipline。
    /// 詳細プラン = `~/.claude/plans/phase-d-implementation.md`（25 slice）。
    pub type alias Data = {
        id                 = Int32,
        // この味方を生成した UnitCatalog のクラス id（"lord" 等）。スナップショット保存で
        // resource を id 参照に落とすために記録する（PlayerResource は name を持たず逆引きできない
        // ため spawn 時に保持）。レベルアップで resource が書き換わっても `| d` 更新で温存される。
        classId            = String,
        gridPos            = {x = Int32, y = Int32},
        moveTiles          = Int32,
        hp                 = Int32,
        waited             = Bool,
        attackTargetId     = Option[Int32],
        resource           = UnitCatalog.UnitResource,
        weapons            = List[UnitCatalog.WeaponResource],
        staves             = List[Staff.StaffResource],
        consumables        = List[Consumable.ConsumableResource],
        // 指輪インベントリ。先頭(index 0)が装備候補で、`ringEquipped` が true のときだけ効果発動。
        // 1 ユニット 1 つだけ効果が出る。拾っただけでは装備されず、明示的に装備して初めて有効になる。
        rings              = List[Ring.RingResource],
        // 指輪を装備中かどうか。false なら先頭の指輪も効果を出さない（所持のみ）。
        ringEquipped       = Bool,
        selectedItem       = Option[ItemKind],
        moveStepsTaken     = Int32,
        facing             = Dir4.Dir4,
        hidden             = Bool,
        usedStairs         = Bool,
        level              = Int32,
        exp                = Int32,
        pendingLevelUp     = Option[LevelSystem.Result],
        // 付与中の時限ステータス効果（ちから薬/すばやさ薬の自己バフ、投擲デバフを被弾した場合等）。
        // 味方ターン開始 (`clearAllWaited`) で `StatusSystem.tick` され、効果は `combatView` に反映される。
        statuses           = List[StatusSystem.Status],
        // 追撃リングの 2 回攻撃を 1 度に制限するフラグ。ターン開始でリセット、追撃発火で true。
        followUpUsed       = Bool
    }

    /// スポーン時の中間表現（初期 spawn のスナップショット）。ゲームオーバー復元にも使う。
    /// hp・waited・exp 等の可変フィールドは含まず、resource から再構築できる最小情報のみを保持する設計。
    pub type alias Spawn = {
        id          = Int32,
        // 生成元 UnitCatalog のクラス id（resource の id 参照保存用、Data#classId と同じ値）。
        classId     = String,
        gridPos     = {x = Int32, y = Int32},
        resource    = UnitCatalog.UnitResource,
        weapons     = List[UnitCatalog.WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource],
        rings       = List[Ring.RingResource]
    }

    /// 装備中の武器 = `weapons` リストの先頭、という規約の単一の読み口。
    /// 装備モデルを変えるときはここだけ修正すればよい。
    pub def equippedWeapon(weapons: List[UnitCatalog.WeaponResource]):
            Option[UnitCatalog.WeaponResource] =
        List.head(weapons)

    /// 装備中の指輪 = `ringEquipped` が true のときだけ `rings` の先頭、という規約の単一の読み口。
    /// 武器と違い「所持しているが未装備」状態があるので、フラグで明示的に切り替える。
    pub def equippedRing(data: {rings = List[Ring.RingResource], ringEquipped = Bool | r}):
            Option[Ring.RingResource] =
        if (data#ringEquipped) List.head(data#rings) else None

    /// 味方パーティの現フレーム状態を副作用なく読み取る effect。
    /// 非 driver Scene (HUD/Camera/Menu/Overlay) はこの effect 経由で味方データを得ることで、
    /// PlayerDriver への直接型参照を持たずに済む（一方向依存の維持）。
    pub eff PartyQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
    }
}
