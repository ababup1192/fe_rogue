// SuspendConfirmUi — 中断確認のモーダルウィンドウ（World-entity UI 版）。
//
// UI ツリーは SuspendConfirm.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「文脈に依存しない固定 2 択（はい/いいえ）の
// 可視・選択ハイライトを毎フレーム同期する / 確定・キャンセルのゲームロジックを適用する」の
// ゲーム側配線を持つ。
//
// 空マスメニューの「中断」確定で `show` が呼ばれ、`TurnPhase.Phase.SuspendConfirm` に入って
// 画面中央に「本当に中断しますか？ / はい / いいえ」を出す。↑↓ で選択、Z/Enter で確定、X でキャンセル。
//   - はい  → `CustomEffects.SuspendRequest.save`（保存成功でタイトルへ。失敗時は PlayerCursor に留まる）
//   - いいえ → `PlayerCursor` に戻る（中断をやめる）
//
// ノード構造（SuspendConfirm.ui.json / layer=3）:
//   SuspendConfirm (none, 画面固定 HUD)
//     └─ panel (box, モーダル地)
//           ├─ title (text) 「本当に中断しますか？」
//           └─ menu (none, 縦並び・gap 0・行ピッチ 8px 固定)
//                 ├─ highlight (box) 選択行の塗り箱（abs 子・項目より背面 z・選択位置へ毎フレ移動）
//                 ├─ item0 (固定高 8px の行 / label=はい / meta=yes)
//                 └─ item1 (固定高 8px の行 / label=いいえ / meta=no)

mod SuspendConfirmUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/SuspendConfirm.ui.json")

    /// root（可視トグルの対象）とリスト所有 entity（選択カーソルのキー）の名前パス。
    pub def rootPath(): String = "SuspendConfirm"
    def menuPath(): String = "SuspendConfirm/panel/menu"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各項目 height と一致させること。
    def rowPitch(): Float64 = 8.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること。
    def highlightInset(): Float64 = 0.5

    // ── 文字色（通常色。ActionMenu と同じ配色）。選択は塗り箱ハイライトで示す ──
    def normalColor(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}

    /// `onConfirmed` で分岐する選択肢の識別子（ui.json の meta と一致させること）。
    /// "yes" 以外（"no" を含む）は cancel() 扱いにする。
    def yesMeta(): String = "yes"

    // ========================================================================
    // 毎フレーム同期（可視 + 選択ハイライト）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。
    /// SuspendConfirm フェーズの間だけ root を可視化し、選択行を塗り箱ハイライトで示す。
    /// 非表示中はカーソルを先頭へ戻す（誤確定防止。次に開いたとき常に「はい」から始まる）。
    pub def frameStep(_dt: Duration.Duration): Unit
            \ {TurnPhase.State, UiWorldState.State} =
        let visible = TurnPhase.State.get() == TurnPhase.Phase.SuspendConfirm;
        let ui = UiWorldState.State.get();
        if (not visible) {
            UiWorldState.State.put(ui
                |> UiStore.setVisible(rootPath(), false)
                |> UiStore.putSelection(menuPath(), 0))
        } else {
            // カーソルを [0, count) へ防御クランプしてから、塗り箱をその位置へ置く。
            let clamped = UiMenu.clampSelection(menuPath(), ui);
            let sel = UiStore.selectionOf(menuPath(), clamped);
            // 全項目を通常色に塗る（選択は塗り箱で示すので文字色は変えない）。
            let tintOf = _idx -> normalColor();
            UiWorldState.State.put(clamped
                |> UiStore.setVisible(rootPath(), true)
                |> UiMenu.applyItemTints(menuPath(), tintOf)
                |> UiMenu.applyHighlight({listPath = menuPath(), highlightPath = highlightPath(),
                                          sel = sel, rowPitch = rowPitch(), inset = highlightInset()}))
        }

    // ========================================================================
    // 表示 / 選択 / 確定 / キャンセル
    // ========================================================================

    /// 「中断」確定を受けて確認ダイアログを表示する。`SuspendConfirm` フェーズに入るだけで、
    /// 可視化・選択カーソルの初期化は次フレームの `frameStep` が担う（ActionMenuUi.openMenu と同じ設計）。
    pub def show(): Unit \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.SuspendConfirm)

    /// 選択カーソルを delta（±1）動かす（端で回り込む。disabled 項目は無いのでスキップ判定は不要）。
    pub def moveSelection(delta: Int32): Unit \ UiWorldState.State =
        let ui = UiWorldState.State.get();
        let count = UiMenu.count(menuPath(), ui);
        let next = UiWidget.selectionMove(count, delta, UiStore.selectionOf(menuPath(), ui));
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui))

    /// Z/Enter 確定。はい → 中断保存要求、いいえ → キャンセル（PlayerCursor へ）。
    pub def confirmCurrentSelection(): Unit
            \ {CustomEffects.SuspendRequest, GameEngine.Audio, TurnPhase.State, UiWorldState.State} =
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        match UiMenu.metaAtSelection(menuPath(), sel, ui) {
            case None    => ()
            case Some(m) => onConfirmed(m)
        }

    def onConfirmed(meta: String): Unit
            \ {CustomEffects.SuspendRequest, GameEngine.Audio, TurnPhase.State} =
        if (meta == yesMeta()) {
            AudioStreamPlayer.play("confirm");
            // 保存失敗時に確認画面へ留まらないよう先に PlayerCursor へ戻す。
            // 成功時は handler が GamePhase を Title にして画面ごと作り直すので無害。
            TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
            CustomEffects.SuspendRequest.save()
        } else {
            // cancel() が "cancel" 音と PlayerCursor 復帰を担う。
            cancel()
        }

    /// 中断をやめて味方ターンのカーソルへ戻る（X / いいえ）。次フレームの frameStep が非表示にする。
    pub def cancel(): Unit \ {GameEngine.Audio, TurnPhase.State} =
        AudioStreamPlayer.play("cancel");
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor)
}
