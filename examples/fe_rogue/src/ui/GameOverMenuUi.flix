// GameOverMenuUi — 全滅時のモーダル選択ウィンドウ（World-entity UI 版）。
//
// UI ツリーは GameOverMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「見せる / 選択を動かす / 確定して復帰種別を emit」
// のゲーム側配線と、可視・選択ハイライトの毎フレーム同期だけを持つ。
//
// ノード構造（GameOverMenu.ui.json）:
//   GameOverMenu (none, 画面全体)
//     └─ panel (box, 中央モーダル・パネル地)
//           └─ menu (none, 選択肢を縦並び・gap 0・行ピッチ 8px 固定)
//                 ├─ highlight (box) 選択行の塗り箱（abs 子・項目より背面 z・選択位置へ毎フレ移動）
//                 ├─ item0 (goddess)  女神の加護（その場復活）  ─┐ 各項目は固定高 8px の行で
//                 ├─ item1 (floor)    フロアの最初から          ├ label を上下中央に置く。
//                 └─ item2 (beginning) 最初から                 ─┘ meta は行が持つ（項目列の識別）。

mod GameOverMenuUi {

    /// 確定した選択肢の識別。metadata 文字列から解決し、対応する復帰 op を emit する。
    pub enum Choice with Eq, ToString {
        case ReviveInPlace
        case RestartFloor
        case RestartBeginning
    }

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/GameOverMenu.ui.json")

    /// root（可視トグルの対象）とリスト所有 entity（選択カーソルのキー）の名前パス。
    pub def rootPath(): String = "GameOverMenu"
    def menuPath(): String = "GameOverMenu/panel/menu"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各項目 height と一致させること。
    def rowPitch(): Float64 = 8.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること。
    def highlightInset(): Float64 = 0.5

    /// 項目の文字色（通常色）。選択は塗り箱ハイライトで示すため選択行も通常色のまま。
    def normalColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    // ========================================================================
    // 純粋: 選択 → 復帰種別
    // ========================================================================

    /// metadata 文字列を Choice へ。未知値は None。
    pub def choiceOf(meta: String): Option[Choice] =
        if (meta == "goddess") Some(Choice.ReviveInPlace)
        else if (meta == "floor") Some(Choice.RestartFloor)
        else if (meta == "beginning") Some(Choice.RestartBeginning)
        else None

    // ========================================================================
    // 表示 / 選択 / 確定
    // ========================================================================

    /// 全滅を受けて盤面をフリーズし、モーダルを表示する。
    ///   - 敵ターンキューを空にして以後の敵 step を止める
    ///   - フェーズを GameOver にして全 driver / 入力ルーティングを no-op 化
    ///   - 進行中アニメ（攻撃 lunge / 死亡演出）を一括キャンセル
    ///   - root を可視化・menu にフォーカス・選択カーソルを先頭へ
    pub def show(): Unit \ {EnemyTurn.Queue, TurnPhase.State, AnimationPlayer.Scheduler, UiWorldState.State} =
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.GameOver);
        AnimationPlayer.Scheduler.cancelAll();
        let ui = UiWorldState.State.get();
        UiWorldState.State.put(ui
            |> UiStore.setVisible(rootPath(), true)
            |> UiStore.focusOn(menuPath())
            |> UiStore.putSelection(menuPath(), 0))

    /// 選択カーソルを delta（±1）動かす（端で回り込む）。
    pub def moveSelection(delta: Int32): Unit \ UiWorldState.State =
        let ui = UiWorldState.State.get();
        let count = UiMenu.count(menuPath(), ui);
        let next = UiWidget.selectionMove(count, delta, UiStore.selectionOf(menuPath(), ui));
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui))

    /// 現在カーソル位置の選択肢を確定し、対応する復帰 op を emit する。
    /// metadata が未解決なら何もしない。
    pub def confirmSelection(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.GameOverRequest, GameEngine.Audio, UiWorldState.State} =
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        match UiMenu.metaAtSelection(menuPath(), sel, ui) |> Option.flatMap(choiceOf) {
            case None         => scene
            case Some(choice) =>
                AudioStreamPlayer.play("confirm");
                emitChoice(choice, scene)
        }

    /// Choice を対応する GameOverRequest op へ振り分けて emit する。
    def emitChoice(choice: Choice, scene: Scene[NodeTag]): Scene[NodeTag] \ CustomEffects.GameOverRequest =
        match choice {
            case Choice.ReviveInPlace    => CustomEffects.GameOverRequest.reviveInPlace(scene)
            case Choice.RestartFloor     => CustomEffects.GameOverRequest.restartFloor(scene)
            case Choice.RestartBeginning => CustomEffects.GameOverRequest.restartBeginning(scene)
        }

    // ========================================================================
    // 毎フレーム同期（可視 + 選択ハイライト）
    // ========================================================================

    /// phase==GameOver の間だけ root を可視化し、選択行を塗り箱ハイライトで示す。
    /// gameLoop のパイプ段として 1 回呼ばれる（refreshItems の per-node dispatch を置換）。
    pub def frameStep(_dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {UiWorldState.State, World.PhaseQuery} =
        let visible = World.PhaseQuery.phase() == SimPhase.GameOver;
        // カーソルを [0, count) へ防御クランプしてから、その位置へ塗り箱を置く。
        let ui = UiMenu.clampSelection(menuPath(), UiWorldState.State.get());
        let sel = UiStore.selectionOf(menuPath(), ui);
        // 全項目を通常色に塗る（選択は塗り箱で示すので文字色は変えない）。
        let tintOf = _idx -> normalColor();
        UiWorldState.State.put(ui
            |> UiStore.setVisible(rootPath(), visible)
            |> UiMenu.applyItemTints(menuPath(), tintOf)
            |> UiMenu.applyHighlight(menuPath(), highlightPath(), sel, rowPitch(), highlightInset()));
        scene
}
