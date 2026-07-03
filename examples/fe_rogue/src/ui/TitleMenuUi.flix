// TitleMenuUi — 起動時のタイトル画面（GamePhase.Title・World-entity UI 版）。
//
// UI ツリーは TitleMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「見せる/隠す」「カーソルを動かす」「確定して
// 画面遷移を要求する」のゲーム側配線と、選択ハイライト・disabled 淡色の毎フレーム同期を持つ。
//
// 「はじめから」/「中断から再開」の 2 択。中断データ（SuspendSave）が無ければ「中断から再開」は
// 選べない（淡色で表示・カーソルが乗らない）。選択位置と再開可否は TitleMenuState resource が
// 権威で、入力は Game.onKeyPressed が GamePhase.Title のとき onKeyPressed へ委譲する。
//
// 確定:
//   - 「はじめから」   → GamePhase.CharacterSelect（出撃メンバー選択へ）
//   - 「中断から再開」 → CustomEffects.ResumeRequest.resume（resumable のときだけ。実 scene 構築は
//     Game.applyPhaseChange(Playing, from = Title) が担う）
//
// ノード構造（TitleMenu.ui.json / layer=6・独立画面）:
//   TitleMenu (none, 画面全体)
//     ├─ bg      (box, 画面全体を覆う背景)
//     ├─ titleRow(none, 中央寄せ) → title (text) タイトル文字
//     └─ menu    (none, 縦並び・gap 0・行ピッチ 16px 固定)
//           ├─ highlight (box) 選択行の塗り箱（abs 子・項目より背面 z・選択位置へ毎フレ移動）
//           ├─ item0 (newGame)  はじめから    ─┐ 各項目は固定高 16px の行で label を
//           └─ item1 (resume)   中断から再開  ─┘ 上下中央に置く。meta は行が持つ。

mod TitleMenuUi {

    // ========================================================================
    // spec 置き場 / 名前パス / 定数
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/TitleMenu.ui.json")

    /// root（可視トグルの対象）とリスト所有 entity（項目列の起点）の名前パス。
    pub def rootPath(): String = "TitleMenu"
    def menuPath(): String = "TitleMenu/menu"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各項目 height と一致させること。
    def rowPitch(): Float64 = 16.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること。
    def highlightInset(): Float64 = 0.5

    /// 項目の通常文字色（選択は塗り箱で示すので選択行も通常色のまま）。
    def normalColor(): Color = {r = 0.7f32, g = 0.7f32, b = 0.75f32}
    /// 「中断から再開」が選べないときの淡色。
    def disabledColor(): Color = {r = 0.35f32, g = 0.35f32, b = 0.4f32}

    // ========================================================================
    // 純粋: カーソル / 確定
    // ========================================================================

    /// 確定キー押下の結果。metadata でなく (cursor, resumable) から純粋に決める
    /// （項目が固定 2 択で disabled 分岐を持つため、GameOver の choiceOf より直接的）。
    pub enum Confirm with Eq, ToString {
        case StartNew   // はじめから → CharacterSelect
        case Resume     // 中断から再開 → ResumeRequest
        case Blocked    // 再開不可（中断データ無し / 使用済み）で確定できない
    }

    /// (カーソル, 再開可否) から確定先を 1 段で決める（旧 onKeyPressed の確定分岐と同一）。
    pub def confirmOutcome(cursor: Int32, resumable: Bool): Confirm =
        match (cursor, resumable) {
            case (0, _)    => Confirm.StartNew
            case (_, true) => Confirm.Resume
            case (_, _)    => Confirm.Blocked
        }

    /// 2 択（はじめから=0 / 中断から再開=1）のカーソルを反転する。
    pub def toggleCursor(data: TitleMenuState.Data): TitleMenuState.Data =
        {cursor = if (data#cursor == 0) 1 else 0 | data}

    // ========================================================================
    // 画面進入 / 退出（可視トグル + 再開可否の再判定）
    // ========================================================================

    /// タイトル画面へ入るたびに呼ぶ。中断データを 1 回読んで再開可否を確定し、カーソルを先頭へ
    /// 戻して root を可視化する。`SceneSetup.buildTitle` から呼ばれ、scene はパイプ素通し。
    pub def enter(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Fs.FileRead, TitleMenuState.State, UiWorldState.State} =
        let saved: Option[SuspendSave.Save] = SaveManager.read(SuspendSave.slot());
        TitleMenuState.State.put({cursor = 0, resumable = Option.nonEmpty(SuspendSave.resumable(saved))});
        UiWorldState.State.put(UiStore.setVisible(rootPath(), true, UiWorldState.State.get()));
        scene

    /// ダンジョン / 選択画面へ出るときにタイトルを隠す。scene はパイプ素通し。
    pub def leave(scene: Scene[NodeTag]): Scene[NodeTag] \ UiWorldState.State =
        UiWorldState.State.put(UiStore.setVisible(rootPath(), false, UiWorldState.State.get()));
        scene

    // ========================================================================
    // 毎フレーム同期（選択ハイライト + disabled 淡色）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。root が可視（タイトル画面中）のときだけ、選択行を
    /// 塗り箱ハイライトで示し、再開不可なら「中断から再開」を淡色にする。可視でなければ no-op。
    pub def frameStep(_dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {TitleMenuState.State, UiWorldState.State} =
        let ui0 = UiWorldState.State.get();
        if (not isActive(ui0)) scene
        else {
            let data = TitleMenuState.State.get();
            // 再開不可のときはカーソルが「中断から再開」に乗らないよう先頭へ寄せる。
            let sel = if (data#resumable) data#cursor else 0;
            // item0=はじめから は常に通常色、item1=中断から再開 は再開不可なら淡色。
            let tintOf = idx -> if (idx == 1 and not data#resumable) disabledColor() else normalColor();
            UiWorldState.State.put(ui0
                |> UiMenu.applyItemTints(menuPath(), tintOf)
                |> UiMenu.applyHighlight({listPath = menuPath(), highlightPath = highlightPath(),
                                          sel = sel, rowPitch = rowPitch(), inset = highlightInset()}));
            scene
        }

    /// root が可視（タイトル画面中）か。未 spawn / 不可視なら no-op ゲート。
    def isActive(ui: UiStore.UiWorld): Bool =
        UiStore.idOf(rootPath(), ui)
            |> Option.flatMap(id -> Map.get(id, ui#visible))
            |> Option.getWithDefault(false)

    // ========================================================================
    // 入力（1 押下ごと。Game.onKeyPressed が GamePhase.Title 中に委譲）
    // ========================================================================

    /// 1 押下ごとの操作。↑↓ でカーソル反転（再開可能なときだけ）、Z/Space/Enter で確定。
    pub def onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, CustomEffects.ResumeRequest,
                              TitleMenuState.State} =
        let data = TitleMenuState.State.get();
        if (isUp(key) or isDown(key)) {
            // 中断データが無い / 使用済みなら「はじめから」固定（カーソルを動かさない）。
            if (data#resumable) {
                AudioStreamPlayer.play("cursor");
                TitleMenuState.State.put(toggleCursor(data));
                scene
            } else scene
        } else if (isConfirm(key))
            match confirmOutcome(data#cursor, data#resumable) {
                case Confirm.StartNew =>
                    AudioStreamPlayer.play("confirm");
                    GamePhaseState.put(GamePhase.CharacterSelect);
                    scene
                case Confirm.Resume =>
                    AudioStreamPlayer.play("confirm");
                    CustomEffects.ResumeRequest.resume(scene)
                case Confirm.Blocked =>
                    // 中断データが無い / 使用済みなら再開できない（カーソル固定で通常来ない）。
                    AudioStreamPlayer.play("cancel");
                    scene
            }
        else scene

    def isUp(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Up or key == GameEngine.Key.W
    def isDown(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Down or key == GameEngine.Key.S
    def isConfirm(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Z or key == GameEngine.Key.Space or key == GameEngine.Key.Enter
}
