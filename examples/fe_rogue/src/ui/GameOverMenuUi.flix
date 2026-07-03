// GameOverMenuUi — 全滅時のモーダル選択ウィンドウ（World-entity UI 版）。
//
// UI ツリーは GameOverMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「見せる / 選択を動かす / 確定して復帰種別を emit」
// のゲーム側配線と、可視・選択ハイライトの毎フレーム同期だけを持つ。
//
// ノード構造（GameOverMenu.ui.json）:
//   GameOverMenu (none, 画面全体)
//     └─ panel (box, 中央モーダル・パネル地)
//           └─ menu (none, 選択肢を縦並び)
//                 ├─ item0 (goddess)  女神の加護（その場復活）
//                 ├─ item1 (floor)    フロアの最初から
//                 └─ item2 (beginning) 最初から

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

    /// 選択項目のハイライト色（accent）と通常色。
    def accentColor(): Color = {r = 1.0f32, g = 0.87f32, b = 0.4f32}
    def normalColor(): Color = {r = 0.91f32, g = 0.91f32, b = 0.91f32}

    // ========================================================================
    // 純粋: 選択 → 復帰種別
    // ========================================================================

    /// metadata 文字列を Choice へ。未知値は None。
    pub def choiceOf(meta: String): Option[Choice] =
        if (meta == "goddess") Some(Choice.ReviveInPlace)
        else if (meta == "floor") Some(Choice.RestartFloor)
        else if (meta == "beginning") Some(Choice.RestartBeginning)
        else None

    /// 選択カーソル位置の metadata を取り出す（範囲外は None）。
    pub def metaAtSelection(selection: Int32, metas: List[String]): Option[String] =
        List.nth(selection, metas)

    /// menu の子項目を order 順に辿り、宣言された metadata を集める。
    def orderedMetas(ui: UiStore.UiWorld): List[String] =
        match UiStore.idOf(menuPath(), ui) {
            case None         => Nil
            case Some(menuId) =>
                UiHierarchy.childrenOf(menuId, ui#parents, ui#order)
                    |> List.filterMap(id -> Map.get(id, ui#metas))
        }

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
        let count = List.length(orderedMetas(ui));
        let next = UiWidget.selectionMove(count, delta, UiStore.selectionOf(menuPath(), ui));
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui))

    /// 現在カーソル位置の選択肢を確定し、対応する復帰 op を emit する。
    /// metadata が未解決なら何もしない。
    pub def confirmSelection(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.GameOverRequest, GameEngine.Audio, UiWorldState.State} =
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        match metaAtSelection(sel, orderedMetas(ui)) |> Option.flatMap(choiceOf) {
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

    /// phase==GameOver の間だけ root を可視化し、選択項目の tint を accent 色へ寄せる。
    /// gameLoop のパイプ段として 1 回呼ばれる（refreshItems の per-node dispatch を置換）。
    pub def frameStep(_dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {UiWorldState.State, World.PhaseQuery} =
        let visible = World.PhaseQuery.phase() == SimPhase.GameOver;
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        UiWorldState.State.put(ui |> UiStore.setVisible(rootPath(), visible) |> applyTints(sel));
        scene

    /// menu の meta 持ち子項目に選択ハイライトを適用する（選択位置=accent、他=normal）。
    /// index は meta を持つ子だけで振る（orderedMetas と同一基準）。meta を持たない
    /// text 子（将来の hint 等）は選択対象でないので tint を触らない。
    def applyTints(sel: Int32, ui: UiStore.UiWorld): UiStore.UiWorld =
        match UiStore.idOf(menuPath(), ui) {
            case None         => ui
            case Some(menuId) =>
                UiHierarchy.childrenOf(menuId, ui#parents, ui#order)
                    |> List.filter(id -> not Option.isEmpty(Map.get(id, ui#metas)))
                    |> List.zipWithIndex
                    |> List.foldLeft((acc, pair) -> {
                        let (idx, id) = pair;
                        let tint = if (idx == sel) accentColor() else normalColor();
                        tintById(id, tint, acc)
                    }, ui)
        }

    /// entity の名前パスを引いて text tint を差し替える（path 経由の setter を再利用）。
    def tintById(id: EntityId, tint: Color, ui: UiStore.UiWorld): UiStore.UiWorld =
        match UiStore.pathOf(id, ui) {
            case None       => ui
            case Some(path) => UiStore.setTextTint(path, tint, ui)
        }
}
