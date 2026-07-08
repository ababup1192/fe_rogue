// ActionMenuUi — 行動選択ウィンドウ（World-entity UI 版）。
//
// UI ツリーは ActionMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「文脈から項目列を組む / 可視・選択・disabled 淡色を
// 毎フレーム同期する / 確定・キャンセルのゲームロジックを適用する」のゲーム側配線を持つ。
//
// PlayerMoving / PlayerCursor / GatherMove で Z を押した瞬間に ActionSelect フェーズへ入り、
// 画面に出る。文脈で項目が切り替わる:
//   - PlayerMoving 由来（SelectedPlayer あり） → こうげき / アイテム / ひろう / たいき ほか
//   - PlayerCursor 由来・空マス（SelectedPlayer なし） → 集合 / ターンエンド / 中断
//   - GatherMove 由来（gatherActive=true・主人公選択中） → 交換 / 全員待機 ほか
// ↑↓ で選択（disabled はスキップ）、Enter/Z で確定、X/Escape で元のフェーズへ戻る。
// 入力は現在の phase（ActionSelect と随伴フェーズ）で振り分ける。GameOverMenu のような
// UI focus scope（モーダル占有）は張らず、可視・選択・確定はすべて phase から決まる。
//
// ノード構造（ActionMenu.ui.json / layer=7）:
//   ActionMenu (none, 画面固定 HUD)
//     └─ panel (box, コマンドウィンドウ地・幅は内容にフィット)
//           ├─ header (box) タイトル帯 + title「コマンド」
//           └─ menu (none, 縦並び・gap 0・行ピッチ 8px 固定)
//                 ├─ highlight (box) 選択行の塗り箱（abs 子・項目より背面 z・選択位置へ毎フレ移動）
//                 └─ slot0..slot6 (none, 固定高 8px の行) 文脈項目のスロット
//                       └─ label (text) 項目テキスト（meta はスロットが持つ＝項目列の識別）
//
// 各スロットは固定高 8px の行コンテナ（label を上下中央に置く）。選択は塗り箱ハイライトで示し、
// 行ピッチが固定なので `UiMenu.applyHighlight` が箱の y を決定論的に置ける（旧 ItemList の
// itemHeight=8 / selectedHighlight の再現）。meta を持つスロットだけが選択カーソルの項目列。
//
// スロットは最大 7 個（味方メニューの拾う/あける/階段/攻撃/アイテム/交換/待機が最大数）。
// 各フレーム、成立した項目を先頭スロットから順に流し込み、余ったスロットは visible=false で
// レイアウトから外す（display:none で窓が縮む）＋ meta を消して選択カーソルの対象から外す。

mod ActionMenuUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/ActionMenu.ui.json")

    /// root（可視トグルの対象）とリスト所有 entity（選択カーソルのキー）の名前パス。
    pub def rootPath(): String = "ActionMenu"
    def menuPath(): String = "ActionMenu/panel/menu"

    /// スロットの最大数（ui.json の slot0..slot6 と一致させること）。
    /// pub: 実 asset の slot 宣言数と一致することをテストが pin するため。
    pub def maxSlots(): Int32 = 7
    /// i 番スロット（固定高の行コンテナ・meta を持つ）の名前パス。
    def slotPath(i: Int32): String = "${menuPath()}/slot${i}"
    /// i 番スロット内の項目テキスト（label）の名前パス。text と tint はここへ流す。
    def labelPath(i: Int32): String = "${slotPath(i)}/label"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各スロット height と一致させること（旧 ItemList itemHeight=8）。
    def rowPitch(): Float64 = 8.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること
    /// （旧 selectedHighlight inset=0.5。箱を行セルより 0.5px 内側に置き、隣行と接しないようにする）。
    def highlightInset(): Float64 = 0.5

    /// パネル（コマンドウィンドウ地）の名前パス。内容フィットで幅を毎フレーム設定する対象。
    def panelPath(): String = "ActionMenu/panel"
    /// パネルの design 空間での左端 x（ui.json の panel abs x と一致）。
    def panelAbsX(): Float64 = 2.0
    /// パネル幅の初期値／フォールバック（ui.json の panel width と一致）。実幅は frameStep が
    /// 内容フィットで毎フレーム UiWorldState へ設定し、panelDesignRight がそれを読み戻す。
    def panelWidth(): Float64 = 40.0

    /// パネル右端の design x。武器選択 / アイテム窓が右隣に重ねて出るときの追従基準。
    /// パネル幅は内容（最長項目・見出し）に合わせて毎フレーム変わるので、現在のパネル幅を
    /// UiWorldState から読み戻して右端を出す。
    pub def panelDesignRight(): Float64 \ UiWorldState.State =
        panelAbsX() + currentPanelWidth()

    /// 現在のパネル幅（内容フィットで設定された固定 px）。まだ設定されていなければ初期値。
    def currentPanelWidth(): Float64 \ UiWorldState.State =
        UiStore.widthPxOf(panelPath(), UiWorldState.State.get())
            |> Option.getWithDefault(panelWidth())

    // ── 文字色（通常 / disabled=淡色。旧 scene.json の textColor / disabledColor 由来）──
    // 選択は塗り箱ハイライトで示すため選択行も通常色のまま（旧 ItemList は白文字 + 選択塗り箱で、
    // 文字色は選択非選択で変えない。塗り箱 + 色替えの二重強調を避ける）。
    def normalColor(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}
    def disabledColor(): Color = {r = 0.36f32, g = 0.40f32, b = 0.47f32}

    // ========================================================================
    // metadata の値（onActionConfirmed で再現するためのアクション識別子）
    // ========================================================================

    def attackMeta(): String    = "attack"
    def exchangeMeta(): String  = "exchange"
    def itemMeta(): String      = "item"
    def waitMeta(): String      = "wait"
    def pickupMeta(): String    = "pickup"
    def openMeta(): String      = "open"
    def gatherMeta(): String    = "gather"
    def turnEndMeta(): String   = "turnEnd"
    /// 中断セーブ（ターンエンドの直下に置く。現フロアを保存してタイトルへ戻る）。
    def suspendMeta(): String   = "suspend"
    def stairsMeta(): String    = "stairs"
    /// 集合（行軍）の隣接メニューの「交換」（主人公＋隣接味方の N 人持ち物交換）。
    def gatherTradeMeta(): String = "gatherTrade"
    /// 集合（行軍）の隣接メニューの「階段で離脱」。
    def gatherStairsMeta(): String = "gatherStairs"
    /// 集合（行軍）隣接メニューの「全員待機」。挙動は turnEnd と同一だが識別子を分ける。
    def waitAllMeta(): String = "waitAll"

    // ========================================================================
    // 幅フィット（内容に合わせてパネル幅を詰める・旧 fitMenuToItems の内容フィット式）
    // ========================================================================

    /// ラベルの font（ui.json の label template と一致）。実測に使う。
    def labelFont(): String = "ui"
    /// ラベルの fontSize（ui.json の label template と一致）。実測に使う。
    def labelFontSize(): Float64 = 2.56
    /// 見出しテキスト（ui.json の title と一致）。実測に使う。
    def headerText(): String = "コマンド"
    /// 見出しの fontSize（ui.json の title と一致）。実測に使う。
    def headerFontSize(): Float64 = 2.4
    /// 最長ラベルの左右に空ける余白（片側 px）。中央に無駄な余白を出さないよう詰める。
    def menuLabelSidePad(): Float64 = 4.0
    /// 見出し帯（menu より x=+2 に置く）を賄うため header 実測幅に足す補正（px）。
    def headerExtraPad(): Float64 = 2.0
    /// パネル内側マージン（片側 px・ui.json の panel pad 左右と一致）。innerW↔panelW 換算に使う。
    def menuSideMargin(): Float64 = 2.0

    /// 幅フィットの純粋コア。ラベル実測幅リストと見出しテキスト実測幅から、パネル幅 panelW と
    /// 内側幅 innerW（＝メニュー内容幅・ハイライト基準）を決める:
    ///   contentW = 最長ラベル幅 + 2×menuLabelSidePad、headerW = 見出し幅 + headerExtraPad、
    ///   innerW = max(contentW, headerW)、panelW = innerW + 2×menuSideMargin。
    /// pub: 具体値をテストが pin するため（実測は effect なので幅リストを引数に取る純関数にする）。
    pub def fitWidths(labelWidths: List[Float64], headerTextWidth: Float64):
                      {innerW = Float64, panelW = Float64} =
        let maxLabelW = List.foldLeft(Float64.max, 0.0, labelWidths);
        let contentW  = maxLabelW + 2.0 * menuLabelSidePad();
        let headerW   = headerTextWidth + headerExtraPad();
        let innerW    = Float64.max(contentW, headerW);
        {innerW = innerW, panelW = innerW + 2.0 * menuSideMargin()}

    /// テキスト 1 本の実測幅（design px）。ui.json の label template と同じ font で測る。
    /// 幅測りは engine_world の TextDraw.width（唯一の入口）へ委譲する。
    def measureUiText(text: String, fontSize: Float64): Float64 \ GameEngine.Game =
        TextDraw.width(text, GameEngine.Game.getFontAtlas(labelFont()), fontSize)

    // ========================================================================
    // 毎フレーム同期（可視 + スロット流し込み + 幅フィット + 選択 / disabled tint）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System（旧 refreshItems + applyVisibility の置換）。
    /// メニューフェーズの間だけ root を可視化し、文脈項目をスロットへ流し込む。
    /// ActionSelect ではカーソルが disabled 項目に乗っていたら選択可能項目へ寄せる（WeaponSelect
    /// 等の随伴フェーズではカーソルを固定して「攻撃」行のハイライトを保つ）。
    pub def frameStep(_dt: Duration.Duration):
            Unit
            \ {TurnPhase.State, SelectedPlayer.State,
               PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery, UiWorldState.State,
               GameEngine.Game} =
        let phase = TurnPhase.State.get();
        if (not isMenuPhase(phase)) {
            // 非表示中はカーソルを先頭に戻し、全スロットを隠して meta も消す。
            let ui = UiWorldState.State.get();
            UiWorldState.State.put(ui
                |> UiStore.setVisible(rootPath(), false)
                |> fillSlots(Nil)
                |> UiStore.putSelection(menuPath(), 0))
        } else {
            let items = buildItems();
            let ui0 = UiWorldState.State.get();
            let sel0 = UiStore.selectionOf(menuPath(), ui0);
            let itemCount = List.length(items);
            // ActionSelect のときだけ disabled 項目上のカーソルを選択可能項目へ寄せる。
            let selResolved = if (phase == TurnPhase.Phase.ActionSelect and selectedIsDisabledAt(sel0, items))
                                  firstEnabledIndex(items)
                              else sel0;
            // 防御クランプ: 項目数が減った直後などにカーソルが範囲外に残っても [0, count) へ収める。
            let sel = if (itemCount <= 0) 0 else Int32.max(0, Int32.min(itemCount - 1, selResolved));
            // 内容（最長ラベル / 見出し）に合わせてパネル幅とハイライト幅を詰める（中央の無駄余白を出さない）。
            // ハイライトは abs 子で crossAlign stretch に乗らないため、内側幅から inset ぶん引いて明示設定する。
            let fit = fitWidths(
                List.map(entry -> measureUiText(entry#text, labelFontSize()), items),
                measureUiText(headerText(), headerFontSize()));
            UiWorldState.State.put(ui0
                |> UiStore.setVisible(rootPath(), true)
                |> fillSlots(items)
                |> UiStore.setWidthPx(panelPath(), fit#panelW)
                |> UiStore.setWidthPx(highlightPath(), fit#innerW - 2.0 * highlightInset())
                |> UiStore.putSelection(menuPath(), sel)
                |> applyTints(items, sel)
                |> UiMenu.applyHighlight({listPath = menuPath(), highlightPath = highlightPath(),
                                          sel = sel, rowPitch = rowPitch(), inset = highlightInset()}))
        }

    /// メニューウィンドウを表示するフェーズか（旧 applyVisibility の visible 集合と一致）。
    /// WeaponSelect / ItemSelect / ItemActionSelect / TradeTargetSelect / TradeInventory でも
    /// コマンドメニューを表示し続け、随伴ウィンドウの文脈（攻撃 / アイテム / 交換行）を見せる。
    def isMenuPhase(phase: TurnPhase.Phase): Bool =
        phase == TurnPhase.Phase.ActionSelect
            or phase == TurnPhase.Phase.WeaponSelect
            or phase == TurnPhase.Phase.ItemSelect
            or phase == TurnPhase.Phase.ItemActionSelect
            or phase == TurnPhase.Phase.TradeTargetSelect
            or phase == TurnPhase.Phase.TradeInventory

    /// items をスロット 0..N へ流し込む。項目のあるスロットは label text/meta を設定して可視化、
    /// 余ったスロットは meta を消して不可視にする（display:none で窓が縮む＋選択対象から外れる）。
    /// 項目数がスロット数を超えたら（ui.json の slot 宣言不足）flow が破綻するので bug! で検知する。
    def fillSlots(items: List[ItemEntry], ui: UiStore.UiWorld): UiStore.UiWorld =
        if (List.length(items) > maxSlots())
            bug!("ActionMenu items (${List.length(items)}) exceed slots (${maxSlots()})")
        else
        List.range(0, maxSlots()) |> List.foldLeft((acc, i) ->
            match List.nth(i, items) {
                case Some(entry) =>
                    acc
                        |> UiStore.setText(labelPath(i), entry#text)
                        |> UiStore.setMeta(slotPath(i), Option.getWithDefault("", entry#metadata))
                        |> UiStore.setVisible(slotPath(i), true)
                case None =>
                    acc
                        |> UiStore.clearMeta(slotPath(i))
                        |> UiStore.setVisible(slotPath(i), false)
            }, ui)

    /// 項目列の text tint を塗る。disabled=淡色、それ以外（選択含む）=通常色。
    /// 選択は塗り箱ハイライトで示すため、文字色は選択非選択で変えない（二重強調を避ける）。
    /// index は項目列（meta 持ちスロット）の 0 起点で、fillSlots が並べた items と同順。
    def applyTints(items: List[ItemEntry], _sel: Int32, ui: UiStore.UiWorld): UiStore.UiWorld =
        let tintOf = idx -> match List.nth(idx, items) {
            case Some(entry) => if (entry#disabled) disabledColor() else normalColor()
            case None        => normalColor()
        };
        UiMenu.applyItemTints(menuPath(), tintOf, ui)

    /// items の最初の「選択可能（not disabled）」項目の index。全部 disabled なら 0。
    def firstEnabledIndex(items: List[ItemEntry]): Int32 =
        items
            |> List.zipWithIndex
            |> List.findLeft(pair -> {let (_i, entry) = pair; not entry#disabled})
            |> Option.map(pair -> {let (i, _entry) = pair; i})
            |> Option.getWithDefault(0)

    /// 選択 index が disabled 項目を指しているか（範囲外は false）。
    def selectedIsDisabledAt(sel: Int32, items: List[ItemEntry]): Bool =
        List.nth(sel, items)
            |> Option.map(e -> e#disabled)
            |> Option.getWithDefault(false)

    // ========================================================================
    // 表示 / 選択 / 確定 / キャンセル
    // ========================================================================

    /// 選択カーソルを delta（±1）動かす（disabled をスキップ・端で回り込む）。
    /// 移動可能な項目が無ければ据え置く。移動音は onKeyPressed の isMenuCursorMove が鳴らす。
    pub def moveSelection(delta: Int32):
            Unit
            \ {UiWorldState.State, SelectedPlayer.State,
               PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        let items = buildItems();
        let ui = UiWorldState.State.get();
        let count = List.length(items);
        let disabledAt = i -> List.nth(i, items) |> Option.map(e -> e#disabled) |> Option.getWithDefault(true);
        let next = UiWidget.selectionMoveSkipping(count, delta, UiStore.selectionOf(menuPath(), ui), disabledAt);
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui))

    /// Z 押下から呼ばれる。現在カーソルがある項目を確定する（disabled は no-op）。
    /// 選択位置の項目はその場で buildItems を再現して index で引く（同一フレームなので一致）。
    pub def confirmCurrentSelection():
                                    Unit
            \ {RangeOverlayState.State,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                CursorState.State, GatherResume.State, PlayerData.PartyQuery,
                EnemyData.RosterQuery,
                CustomEffects.FloorAdvanceRequest,
                GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery,
                ItemPickupPopupState.State, ItemMenuState.State, TradeMenuState.State, UiWorldState.State,
                StairsExitDriver.State} =
        let sel = UiStore.selectionOf(menuPath(), UiWorldState.State.get());
        match List.nth(sel, buildItems()) {
            // disabled 項目（例: 敵が射程外の「攻撃」）は確定しても何もしない。
            case Some(entry) => if (entry#disabled) () else onActionConfirmed(entry)
            case None        => ()
        }

    /// メニューを閉じて元のフェーズに戻る（X / Escape）。戻り先の overlay / cursor 状態は
    /// `PhaseTransitions.enter*` に委譲して確立する（bare put 禁止・旧 ActionMenuScene と同じ不変条件）。
    ///   - gatherActive          → enterGatherMove   （集合・行軍へ。移動やり直し）
    ///   - SelectedPlayer = Some → enterPlayerMoving （駒操作中。カーソルは設計上非表示）
    ///   - SelectedPlayer = None → enterPlayerCursor （空マス由来。カーソル再表示＋snap）
    pub def onActionCancelled():
                              Unit \ {RangeOverlayState.State,
                                                TurnPhase.State, SelectedPlayer.State, CursorState.State,
                                                PlayerData.PartyQuery, World.Command, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        if (sel#gatherActive)
            PhaseTransitions.enterGatherMove()
        else match sel#id {
            case Some(_) => PhaseTransitions.enterPlayerMoving()
            case None    => PhaseTransitions.enterPlayerCursor()
        }

    // ========================================================================
    // 開くフェーズ遷移（旧 ActionMenuScene.openFrom* と同一）
    // ========================================================================

    /// PlayerMoving + Z: 行動選択ウィンドウを開く（フェーズ = ActionSelect）。項目は frameStep が
    /// 毎フレーム再構築する。選択カーソルは非表示中に frameStep が先頭(0)へ戻してある。
    pub def openFromMoving(): Unit \ TurnPhase.State =
        openMenu()

    /// PlayerCursor + Z（空マス）: 集合メニューを開く。SelectedPlayer は None のまま。
    pub def openFromCursor(): Unit \ TurnPhase.State =
        openMenu()

    /// GatherMove + Z: 隣接メニュー（交換 / 全員待機）を開く。gatherActive は true のまま。
    pub def openFromGather(): Unit \ TurnPhase.State =
        openMenu()

    /// ActionSelect フェーズへ入る（共通実装）。3 経路は呼び出し元フェーズをコールサイトで
    /// 明示するために分けている（挙動同一）。選択カーソルは非表示中に frameStep が 0 に戻すので、
    /// 開いた最初のフレームは先頭（disabled なら firstEnabled）に乗る。
    def openMenu(): Unit \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect)

    // ========================================================================
    // 項目の構築（旧 ActionMenuScene.buildItems・文脈依存）
    // ========================================================================

    /// 選択中プレイヤーの状況から成立する項目だけ返す。
    /// gatherActive=true のときは集合（行軍）の隣接メニュー、SelectedPlayer が None のときは
    /// 空マスメニュー、Some のときはその味方の行動メニュー。
    /// pub: 文脈分岐（項目の text/disabled/meta）をテストが直接 pin するため。
    pub def buildItems(): List[ItemEntry]
            \ {SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        match (sel#gatherActive, sel#id) {
            case (true, _)         => gatherAdjacentMenuItems()
            case (false, None)     => gatherMenuItems()
            case (false, Some(id)) =>
                PlayerData.PartyQuery.get(id)
                    |> Option.map(player -> selectedPlayerMenuItems(player))
                    |> Option.getWithDefault(Nil)
        }

    /// 移動を終えた味方の行動メニュー項目。成立するものだけ固定順
    /// 「ひろう → あける → 階段 → こうげき → アイテム → こうかん → たいき」で返す。
    /// かなしばり中は「待機」だけ出してターンを閉じられるようにする。
    def selectedPlayerMenuItems(player: PlayerScene.Data): List[ItemEntry]
            \ {PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        if (StatusSystem.isImmobilized(player#statuses)) boundMenuItems()
        else {
            let attackItem =
                ({text = "攻撃", disabled = not canAttackFrom(player),
                  metadata = Some(attackMeta())}: ItemEntry) :: Nil;
            let exchangeItem =
                ({text = "交換", disabled = List.isEmpty(PlayerScene.adjacentAllies(player)),
                  metadata = Some(exchangeMeta())}: ItemEntry) :: Nil;
            let itemItem =
                if (not (List.isEmpty(player#weapons) and List.isEmpty(player#staves)))
                    ({text = "アイテム", disabled = false, metadata = Some(itemMeta())}: ItemEntry) :: Nil
                else Nil;
            let pickupItem =
                if (Option.nonEmpty(World.groundItemAtOf(player#gridPos, World.WorldQuery.get())))
                    ({text = "拾う", disabled = false, metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                else Nil;
            let stairsItem =
                if (World.stairsPosOf(World.WorldQuery.get())
                        |> Option.exists(c -> c#x == player#gridPos#x and c#y == player#gridPos#y))
                    ({text = "階段", disabled = false, metadata = Some(stairsMeta())}: ItemEntry) :: Nil
                else Nil;
            let openItem =
                if (Option.nonEmpty(World.chestAtOf(player#gridPos, World.WorldQuery.get())))
                    ({text = "あける", disabled = false, metadata = Some(openMeta())}: ItemEntry) :: Nil
                else Nil;
            let waitItem =
                if (canWaitOn(player))
                    ({text = "待機", disabled = false, metadata = Some(waitMeta())}: ItemEntry) :: Nil
                else Nil;
            List.flatten(pickupItem :: openItem :: stairsItem :: attackItem ::
                           itemItem :: exchangeItem :: waitItem :: Nil)
        }

    /// かなしばり中のメニュー: 行動不能なので「待機」だけ出す（ターンを閉じるため）。
    def boundMenuItems(): List[ItemEntry] =
        ({text = "待機", disabled = false, metadata = Some(waitMeta())}: ItemEntry) :: Nil

    /// 集合（行軍）の交換に参加するメンバーの player id（主人公を含む連結した生存味方の塊）。
    def gatherTradeMembers(): List[Int32] \ PlayerData.PartyQuery =
        let living = PlayerData.PartyQuery.getAll() |> List.filter(d -> d#hp > 0);
        PlayerScene.tradeComponent(PlayerScene.lordId(), living)

    /// 集合（行軍）の隣接メニュー項目。固定順「拾う → 階段 → 交換 → 全員待機」で成立分だけ返す
    /// （全員待機は常に表示）。判定はすべて主人公（リーダー id=0）基準。
    def gatherAdjacentMenuItems(): List[ItemEntry] \ {PlayerData.PartyQuery, World.WorldQuery} =
        let lordItems = match PlayerData.PartyQuery.get(PlayerScene.lordId()) {
            case None       => Nil
            case Some(lord) =>
                let adj = PlayerScene.adjacentAllies(lord) |> List.filter(d -> d#hp > 0);
                let pickup =
                    if (Option.nonEmpty(World.groundItemAtOf(lord#gridPos, World.WorldQuery.get())))
                        ({text = "拾う", disabled = false,
                          metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                    else Nil;
                let stairsExit =
                    if (World.stairsPosOf(World.WorldQuery.get())
                            |> Option.exists(c -> c#x == lord#gridPos#x and c#y == lord#gridPos#y))
                        ({text = "階段", disabled = false,
                          metadata = Some(gatherStairsMeta())}: ItemEntry) :: Nil
                    else Nil;
                let trade =
                    if (not List.isEmpty(adj))
                        ({text = "交換", disabled = false,
                          metadata = Some(gatherTradeMeta())}: ItemEntry) :: Nil
                    else Nil;
                List.flatten(pickup :: stairsExit :: trade :: Nil)
        };
        let waitAll =
            ({text = "全員待機", disabled = false,
              metadata = Some(waitAllMeta())}: ItemEntry) :: Nil;
        List.flatten(lordItems :: waitAll :: Nil)

    /// 「集合」が選べる状況か（主人公以外に生存味方が居る）。
    pub def gatherAvailable(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.getAll()
            |> List.exists(d -> d#id != PlayerScene.lordId() and d#hp > 0)

    /// 主人公（リーダー）が行動済み(waited)か。
    def lordWaited(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(PlayerScene.lordId())
            |> Option.map(d -> d#waited)
            |> Option.getWithDefault(false)

    /// 「集合（行軍）」を開始できるか。生存味方が他に居て、主人公が未行動で、かつフォグで
    /// 見えている敵が 1 体もいないとき。空マスメニューの「集合」disabled 判定と C キー可否で共有。
    pub def gatherEnabled(): Bool \ {PlayerData.PartyQuery, SelectedPlayer.State, World.WorldQuery} =
        gatherAvailable() and not lordWaited() and not EnemyScene.anyVisible()

    /// 通常の空マスメニュー項目。「集合」（開始不可時は disabled）と「ターンエンド」「中断」。
    def gatherMenuItems(): List[ItemEntry] \ {PlayerData.PartyQuery, SelectedPlayer.State, World.WorldQuery} =
        let gather =
            ({text = "集合", disabled = not gatherEnabled(),
              metadata = Some(gatherMeta())}: ItemEntry) :: Nil;
        let turnEnd =
            ({text = "ターンエンド", disabled = false,
              metadata = Some(turnEndMeta())}: ItemEntry) :: Nil;
        let suspend =
            ({text = "中断", disabled = false,
              metadata = Some(suspendMeta())}: ItemEntry) :: Nil;
        List.flatten(gather :: turnEnd :: suspend :: Nil)

    /// C キー / ゲームパッド Y のショートカット: メニューを開かず「集合」を直接確定する。
    pub def gatherShortcut():
            Unit \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery, World.Command,
                              RangeOverlayState.State, CursorState.State} =
        applyGather()

    /// Shift 長押しゲージ満了時のショートカット: メニューを開かず「全員待機」と同じ。
    pub def turnEndShortcut():
            Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                              World.Command, World.WorldQuery, RangeOverlayState.State} =
        applyTurnEnd()

    /// インベントリのいずれかの武器の射程内に生きている敵が居るか。
    def canAttackFrom(player: PlayerScene.Data): Bool \ EnemyData.RosterQuery =
        let enemies = EnemyData.RosterQuery.getAll();
        List.exists(w -> weaponReachesAnyEnemy(player#gridPos, w, enemies), player#weapons)

    /// 指定位置から `weapon` の射程内に生きている敵（hp > 0 かつ not isDying）が居るか。
    def weaponReachesAnyEnemy(pos: {x = Int32, y = Int32},
                               weapon: UnitCatalog.WeaponResource,
                               enemies: List[EnemyScene.Data]): Bool =
        List.exists(e -> {
            let ev = EnemyScene.unitView(e);
            ev#hp > 0 and not ev#isDying
                and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
        }, enemies)

    /// 自分の現在セルに「自分以外の味方」が居なければたいき可。
    def canWaitOn(player: PlayerScene.Data): Bool \ PlayerData.PartyQuery =
        not List.exists(d ->
            d#id != player#id
            and d#gridPos#x == player#gridPos#x
            and d#gridPos#y == player#gridPos#y,
            PlayerData.PartyQuery.getAll())

    // ========================================================================
    // 確定アクションの適用（旧 ActionMenuScene のゲームロジックを移植・挙動不変）
    // ========================================================================

    /// メニュー確定アクションを「決定(data)」と「適用(effect)」に分離する seam。現状 "wait" のみ intent 化。
    pub enum ActionIntent {
        case Wait
    }

    /// 決定: metadata から `ActionIntent` を引く純関数（副作用なし）。
    def actionIntentOf(metadata: String): Option[ActionIntent] =
        if (metadata == waitMeta()) Some(ActionIntent.Wait) else None

    /// 適用: `ActionIntent` を World へ適用する単一 dispatcher。
    def applyActionIntent(intent: ActionIntent):
            Unit
            \ {RangeOverlayState.State, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
               World.Command, World.WorldQuery} =
        match intent {
            case ActionIntent.Wait => TurnFlow.commitWaitedAndAdvance()
        }

    /// 確定された項目の metadata を分岐して、それぞれの帰結を適用する。
    /// pub: confirm 経路のゲームロジック（wait/pickup/gather/turnEnd 等）をテストが pin するため。
    pub def onActionConfirmed(entry: ItemEntry):
                              Unit
            \ {RangeOverlayState.State,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                CursorState.State, GatherResume.State, PlayerData.PartyQuery,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery,
                ItemPickupPopupState.State, ItemMenuState.State, TradeMenuState.State,
                StairsExitDriver.State} =
        match entry#metadata {
            case None    => ()
            case Some(m) =>
                match actionIntentOf(m) {
                    case Some(intent) => applyActionIntent(intent)
                    case None         =>
                if (m == attackMeta())        enterWeaponSelect()
                else if (m == exchangeMeta()) PhaseTransitions.enterTradeTargetSelect()
                else if (m == itemMeta())     openItemMenu()
                else if (m == pickupMeta())   applyPickup()
                else if (m == openMeta())     applyOpenChest()
                else if (m == gatherMeta())   applyGather()
                else if (m == turnEndMeta())  applyTurnEnd()
                else if (m == waitAllMeta())  applyTurnEnd()
                else if (m == suspendMeta())  SuspendConfirmUi.show()
                else if (m == stairsMeta())   applyStairs()
                else if (m == gatherTradeMeta()) openGatherTrade()
                else if (m == gatherStairsMeta()) StairsExitDriver.begin()
                else                          ()
                }
        }

    /// 「かいだん」確定。選択中の味方を階段で退場させる。
    def applyStairs():
            Unit
            \ {RangeOverlayState.State,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        AudioStreamPlayer.play("change_floor");
        GameLogger.playerLog("階段を降りた");
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                PlayerScene.useStairs(id);
                if (PlayerScene.allLivingUsedStairs())
                    CustomEffects.FloorAdvanceRequest.advance()
                else
                    TurnFlow.commitWaitedAndAdvance()
            case None =>
                CustomEffects.FloorAdvanceRequest.advance()
        }

    /// 「アイテム」確定で ItemMenuUi を開く。
    def openItemMenu():
            Unit \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery, RangeOverlayState.State, CursorState.State} =
        match SelectedPlayer.State.get()#id {
            case None           => ()
            case Some(playerId) => ItemMenuUi.openFor(playerId)
        }

    /// 「交換」確定（集合の隣接メニュー）: 主人公＋隣接味方の N 人持ち物交換画面を開く。
    def openGatherTrade():
            Unit \ {TurnPhase.State, PlayerData.PartyQuery, TradeMenuState.State, CursorState.State} =
        PhaseTransitions.enterGatherTrade(gatherTradeMembers())

    /// 「集合」確定: 集合（行軍）モードを開始する（GatherMove フェーズへ）。
    def applyGather():
            Unit \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery, World.Command,
                              RangeOverlayState.State, CursorState.State} =
        if (leaderWaited())
            GameLogger.playerLog("リーダーは既に行動済みです。")
        else {
            GameLogger.playerLog("集合");
            PlayerScene.beginGather()
        }

    /// 主人公(リーダー)が既に行動済み(waited)か。集合確定のガードに使う。
    def leaderWaited(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(PlayerScene.lordId())
            |> Option.map(d -> d#waited)
            |> Option.getWithDefault(false)

    /// 「ターンエンド」／集合の「全員待機」確定。`TurnFlow.commitAllWaitedAndAdvance` に委譲する。
    def applyTurnEnd():
            Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                              World.Command, World.WorldQuery, RangeOverlayState.State} =
        TurnFlow.commitAllWaitedAndAdvance(true)

    /// 「ひろう」確定の本体。床アイテムを取得してインベントリに加える（ターン消費しない）。
    def applyPickup():
            Unit \ {GameLogger.GameLogger,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.Command, World.WorldQuery,
                              ItemPickupPopupState.State} =
        match pickupTarget() {
            case None       => ()
            case Some(info) =>
                if (wouldPickupOverload(info))
                    ItemPickupPopupUi.showFull()
                else {
                    PlayerScene.pickupFloorItem(info#playerId, info#gridPos);
                    ItemPickupPopupUi.reserveGetItemSound()
                }
        }

    /// 拾う主体が足元の床アイテムを拾うと重量過多になるか。
    def wouldPickupOverload(info: {playerId = Int32, gridPos = {x = Int32, y = Int32}}):
                             Bool \ {PlayerData.PartyQuery, World.WorldQuery} =
        match (PlayerData.PartyQuery.get(info#playerId),
               World.groundItemAtOf(info#gridPos, World.WorldQuery.get())) {
            case (Some(player), Some(floor)) =>
                PlayerScene.wouldOverloadByPicking(player, floor#item)
            case _ => false
        }

    /// 「あける」確定。宝箱に乗った駒で開錠を試みる。
    def applyOpenChest():
            Unit \ {GameLogger.GameLogger,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.Command, World.WorldQuery,
                              ItemPickupPopupState.State} =
        match openTarget() {
            case None                      => ()
            case Some((info, player, chest)) =>
                if (not PlayerScene.canOpenChests(player))
                    ItemPickupPopupUi.showMessage("開けることができない")
                else if (PlayerScene.wouldOverloadByPicking(player, chest#content))
                    ItemPickupPopupUi.showFull()
                else {
                    PlayerScene.addPickedItem(info#playerId, chest#content);
                    Chests.takeAt(info#gridPos);
                    ItemPickupPopupUi.reserveGetItemSound()
                }
        }

    /// 開錠対象を 1 本の Option 連鎖で解決する。
    def openTarget():
            Option[({playerId = Int32, gridPos = {x = Int32, y = Int32}},
                    PlayerScene.Data, Chests.Data)]
            \ {SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery} =
        forM (
            info   <- pickupTarget();
            player <- PlayerData.PartyQuery.get(info#playerId);
            chest  <- World.chestAtOf(info#gridPos, World.WorldQuery.get())
        ) yield (info, player, chest)

    /// 拾う主体(playerId)と拾う位置(gridPos)を決める。
    def pickupTarget():
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        selectedPlayerInfo()

    /// 選択中の味方の id と現在位置をまとめて返す。
    def selectedPlayerInfo():
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield {playerId = playerId, gridPos = player#gridPos}

    /// 「こうげき」確定時の遷移: 武器選択ウィンドウ (WeaponSelect) を開く。
    def enterWeaponSelect(): Unit \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.WeaponSelect)
}
