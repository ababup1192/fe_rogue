// SnapshotHarness — スナップショット用の effect handler 束。
//
// 目的: 手組み UiStore ではなく **本物のゲームコード（各 Ui の frameStep / applyFrame）** に
// フィクスチャデータを流して UI を組ませる。`run(config, thunk)` は各 Ui.frameStep が要求する
// read 系 effect（フェーズ / 選択駒 / カーソル / 在庫 Query / World / メニューセッション状態）を
// 1 呼び出しで供給し、`thunk`（＝ frameStep 呼び出し）を回す。
//
// handler の素材は `TestUnitFixtures` の既存 mock を再利用する（テスト側と共通化）:
//   noop Tween / Anim, 固定フェーズ, PartyQuery / RosterQuery（World 由来の Data 一覧）,
//   WorldQuery / PhaseQuery。
// SelectedPlayer（gatherActive 対応）/ ItemMenuState / TradeMenuState は config 値を返す小 handler を
// ここで巻く。GameEngine.Game と UiWorldState.State は呼び出し側（SnapshotSupport.withMockGame /
// UiWorldState.withState）が供給し、`run` は `ef` で透過させる。
mod SnapshotHarness {

    /// frameStep を回すためのフィクスチャデータ束。1 レコードで名前渡しする。
    ///   phase / simPhase : TurnPhase / World いずれの読みにも応える確定フェーズ。
    ///   selectedId       : 選択中の味方 id（空マス / ゲームオーバー経路は None）。
    ///   gatherActive     : 集合（行軍）中か（ActionMenu の隣接メニュー分岐）。
    ///   cursor           : カーソルのグリッド座標（武器 / カード対象の解決に使う）。
    ///   world            : 味方 / 敵 / 盤面 / 配置物を seed 済みの World
    ///                      （PartyQuery / RosterQuery / WorldQuery すべての供給源）。
    ///   itemCategory     : ItemMenu の現在カテゴリ（0=武器 1=消費 2=杖 3=指輪）。
    ///   itemMarks        : ItemMenu の複数選択マーク集合。
    ///   trade            : 交換セッション状態（members / focus / pick / marks）。
    pub type alias Config = {
        phase        = TurnPhase.Phase,
        simPhase     = SimPhase,
        selectedId   = Option[Int32],
        gatherActive = Bool,
        cursor       = {x = Int32, y = Int32},
        world        = World,
        itemCategory = Int32,
        itemMarks    = Set[PlayerData.ItemKind],
        trade        = TradeMenuUi.PanelData
    }

    /// 既定 Config。`world` だけ与えれば「PlayerCursor・未選択・原点カーソル・武器カテゴリ・空交換」で
    /// 始まる。各フィクスチャは必要なフィールドだけ `| base` で上書きする。
    pub def config(world: World): Config = {
        phase        = TurnPhase.Phase.PlayerCursor,
        simPhase     = SimPhase.PlayerTurn,
        selectedId   = None,
        gatherActive = false,
        cursor       = {x = 0, y = 0},
        world        = world,
        itemCategory = 0,
        itemMarks    = Set#{},
        trade        = TradeMenuUi.defaultPanelData()
    }

    /// `run` が供給する read 系 effect の束。frameStep が要求する順に内側から巻く。
    /// GameEngine.Game / UiWorldState.State は外側（withMockGame / UiWorldState.withState）から
    /// `ef` で透過。SelectedPlayer / ItemMenuState / TradeMenuState は config 値を返す固定 handler。
    /// PartyQuery / RosterQuery は config の World から再構築した Data 一覧
    /// （TestUnitFixtures.worldPlayers / worldEnemies）を返す。
    pub def withMocks(cfg: Config, thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State - SelectedPlayer.State - CursorState.State
                    - PlayerData.PartyQuery - EnemyData.RosterQuery
                    - World.WorldQuery - World.PhaseQuery
                    - ItemMenuState.State - TradeMenuState.State) =
        TestUnitFixtures.withNoopTween(() ->
        TestUnitFixtures.withNoopAnim(() ->
        TestUnitFixtures.withFixedPhase(cfg#phase, () ->
        withSelection(cfg, () ->
        TestUnitFixtures.withCursorAt(cfg#cursor, () ->
        TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(cfg#world), () ->
        TestUnitFixtures.withMockRosterQuery(TestUnitFixtures.worldEnemies(cfg#world), () ->
        TestUnitFixtures.withWorldQuery(cfg#world, () ->
        TestUnitFixtures.withWorldPhase(cfg#simPhase, () ->
        withItemMenu(cfg, () ->
        withTrade(cfg, thunk)))))))))))

    /// SelectedPlayer.State を config の `selectedId` / `gatherActive` で固定する（put は捨てる）。
    /// `withSelectedPlayer` は gatherActive=false 固定なので、集合メニューも扱えるようここで巻く。
    def withSelection(cfg: Config, thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k({id = cfg#selectedId, drafts = Nil, gatherActive = cfg#gatherActive})
            def put(_, k) = k()
        }

    /// ItemMenuState.State を config の `itemCategory` / `itemMarks` で固定する（put は捨てる）。
    def withItemMenu(cfg: Config, thunk: Unit -> a \ ef): a \ (ef - ItemMenuState.State) =
        run { thunk() } with handler ItemMenuState.State {
            def get(k)    = k({category = cfg#itemCategory, marks = cfg#itemMarks})
            def put(_, k) = k()
        }

    /// TradeMenuState.State を config の `trade` で固定する（put は捨てる）。
    def withTrade(cfg: Config, thunk: Unit -> a \ ef): a \ (ef - TradeMenuState.State) =
        run { thunk() } with handler TradeMenuState.State {
            def get(k)    = k(cfg#trade)
            def put(_, k) = k()
        }

    // ════════════════════════════════════════════════════════
    // full モード（確定でフェーズが変わる多段階遷移を撮るための可変ハーネス）
    // ════════════════════════════════════════════════════════
    //
    // `withMocks` は phase / 選択状態を **固定値** で返すため、確定（Z）でフェーズが変わる遷移
    // （コマンド→アイテムメニュー開）を撮れない。`withFullMocks` は各状態を **可変 Ref** で持ち、
    // 確定のゲームロジック（`enterItemSelect` / `enterWeaponSelect` 等）を **本物のまま実行** する。
    // 書かれた phase が同スコープ内の次の frameStep の可視判定に効く（実機と同じ因果）。
    //
    // `withMocks` との差:
    //   - TurnPhase.State は初期値 `cfg#phase` の可変 Ref（確定で書いた phase が持続）。
    //   - SelectedPlayer は Ref-backed（drafts / gatherActive を持ち越す）。
    //   - 確定経路が要求する障害 effect を全供給:
    //       no-op    : GameLogger / Audio / FloorAdvanceRequest / GatherResume
    //       Ref-back : EnemyTurn.Queue / ArrowCursorState / ItemPickupPopupState / ItemMenuState / TradeMenuState
    //       World    : World.Command はローカル World Ref へ畳み、World.WorldQuery が同 Ref を読む
    //                  （read-after-write。確定経路の pickup/stairs 系 Cmd も内容に矛盾なく反映される。
    //                   ItemMenu/Weapon の可視・内容は PartyQuery＝開始時 World の Data 一覧（静的）なので
    //                   World 書込に非依存）。
    //       Board    : fixture World の駒列（worldPlayers / worldEnemies）と 13×13 地形から
    //                  `BoardSnapshot.fromParts` で組む。
    // GameEngine.Game / UiWorldState.State は呼び出し側（withMockGame / UiWorldState.withState）が
    // 供給し、ここは `ef` で透過させる（`withMocks` と同じ）。
    //
    // 使い方: `execute` 全体を 1 回だけこの handler で包む（applyKey/tick を個別に包まない）。
    // これで phase など可変状態が 1 スコープを貫通して持続する。
    // region は内部で開いて閉じる（可変状態は thunk 実行中だけ生存すれば足り、`withCancelTransitionMocks`
    // と同じく rc を引数に取らない＝Region[r] を sub-combinator 経由で使う際の擬似 unused 警告も避ける）。
    pub def withFullMocks(cfg: Config, thunk: Unit -> a \ ef):
            a \ (ef - GameLogger.GameLogger
                    - EnemyTurn.Queue - TurnPhase.State - SelectedPlayer.State - CursorState.State
                    - ArrowCursorState.State - GatherResume.State - PlayerData.PartyQuery
                    - EnemyData.RosterQuery - CustomEffects.FloorAdvanceRequest - GameEngine.Audio
                    - World.Command - World.WorldQuery - BoardQuery - ItemPickupPopupState.State
                    - ItemMenuState.State - TradeMenuState.State - RangeOverlayState.State
                    - StairsExitDriver.State) =
        let initialSel: SelectedPlayer.Selection =
            {id = cfg#selectedId, drafts = Nil, gatherActive = cfg#gatherActive};
        let board = BoardSnapshot.fromParts(TestWorldFixtures.floorSnapshot({w = 13, h = 13}),
            TestUnitFixtures.worldPlayers(cfg#world), TestUnitFixtures.worldEnemies(cfg#world));
        region rc {
        TestUnitFixtures.withRangeOverlay(rc, () ->
        TestUnitFixtures.withNoopTween(() ->
        TestUnitFixtures.withNoopAnim(() ->
        TestUnitFixtures.withMockGameLogger(() ->
        TestUnitFixtures.withMockAudio(() ->
        TestUnitFixtures.withNoopFloorAdvance(() ->
        TestUnitFixtures.withMockGatherResume(() ->
        TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(cfg#world), () ->
        TestUnitFixtures.withMockRosterQuery(TestUnitFixtures.worldEnemies(cfg#world), () ->
        TestUnitFixtures.withMockBoard(board, () ->
        TestUnitFixtures.withCursorAt(cfg#cursor, () ->
        TestUnitFixtures.withTradeMenu(rc, () ->
        TestUnitFixtures.withSelectionRef(rc, initialSel, () ->
        EnemyTurn.withQueue(rc, () ->
        StairsExitDriver.withState(rc, () ->
        ArrowCursorState.withState(rc, () ->
        ItemPickupPopupState.withState(rc, () ->
        ItemMenuState.withState(rc, () ->
        withPhaseState(rc, cfg#phase, () ->
        withLocalWorld(rc, cfg#world, thunk))))))))))))))))))))
        }

    /// TurnPhase.State を初期値 `initial` の可変 Ref で供給する（`put` が持続 = 確定でフェーズが変わる）。
    /// engine の `TurnPhase.withState` は初期値 PlayerCursor 固定なので、fixture の開始フェーズを
    /// 渡せるこちらを使う（dual-write は不要 = World.PhaseQuery は full ハーネスの consumer に無い）。
    def withPhaseState(rc: Region[r], initial: TurnPhase.Phase, thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State) + r =
        let phaseRef: Ref[TurnPhase.Phase, r] = Ref.fresh(rc, initial);
        run { thunk() } with handler TurnPhase.State {
            def get(k)         = k(Ref.get(phaseRef))
            def put(target, k) = { Ref.put(target, phaseRef); k() }
        }

    /// World.Command をローカル World Ref へ畳み、World.WorldQuery が同 Ref を読む（read-after-write）。
    /// `withWorldCommand`（TestUnitFixtures）と同型だが、seed を fixture World で渡せる版。
    def withLocalWorld(rc: Region[r], seed: World, thunk: Unit -> a \ ef):
            a \ ((ef - World.Command) - World.WorldQuery) + r =
        let wref: Ref[World, r] = Ref.fresh(rc, seed);
        run { thunk() }
            with handler World.WorldQuery {
                def get(k) = k(Ref.get(wref))
            }
            with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
            }
}
