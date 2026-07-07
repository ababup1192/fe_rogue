// GameUi — 全ページ（Title / Hud / Dialog / Memo / Result / Ending）を ui.json から生成し、
// 毎フレーム World の判定結果を UiStore に刻み込む。見た目はすべて assets/*.ui.json にある。
mod GameUi {

    /// UI キャンバス、design px 単位。
    pub def designSize(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    def pagePaths(): List[String] =
        "assets/Title.ui.json" :: "assets/Hud.ui.json" :: "assets/Dialog.ui.json" ::
        "assets/Memo.ui.json" :: "assets/Result.ui.json" :: "assets/Ending.ui.json" :: Nil

    /// 全ページの Spec を 1 つの UiWorld へ生成する。壊れた・存在しないファイルは
    /// ページなしへ縮退する（ゲームはそれでも動く）。
    pub def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        pagePaths() |> List.foldLeft((ui, path) -> spawnPage(path, ui), UiStore.empty())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, spawned)) => spawned
            case Result.Err(_)           => ui
        }

    /// 会話窓の投影先（UiDialog に渡す名前パス束）。
    def dialogPaths(): UiDialog.Paths =
        { root = "Dialog", speaker = "Dialog/panel/speaker", body = "Dialog/panel/body" }

    /// メモのスロット規約（7 スロット固定・NPC 数ぶんだけ埋める）。
    def memoSlotSpec(): UiSlots.SlotSpec =
        { slotPath = i -> "Memo/panel/menu/slot${i}", maxSlots = 7 }

    def memoMenuPath(): String = "Memo/panel/menu"
    def confirmMenuPath(): String = "Dialog/confirm/menu"

    /// メモと確認メニューの行ピッチ（ui.json のスロット高と一致させる）。
    def memoRowPitch(): Float64 = 13.0
    def confirmRowPitch(): Float64 = 12.0

    // ── 毎フレームの投影 ──

    pub def projectUi(w: Room.World, ui0: UiStore.UiWorld): UiStore.UiWorld =
        let Room.World.World(s) = w;
        ui0
            |> UiStore.setVisible("Title", s#phase == Room.Phase.Title)
            |> applyHud(s)
            |> UiDialog.apply(dialogPaths(), s#dialog)
            |> applyConfirm(s)
            |> applyMemo(s)
            |> applyResult(s)
            |> UiStore.setVisible("Ending", s#phase == Room.Phase.Ending)

    /// HUD はゲーム中の全フェーズで出しっぱなし（タイトルとエンディングでは隠す）。
    def applyHud(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        let visible = s#phase != Room.Phase.Title and s#phase != Room.Phase.Ending;
        ui
            |> UiStore.setVisible("Hud", visible)
            |> UiStore.setText("Hud/bar/stage", "ステージ ${s#stage}／${Stage.stageCount()}")
            |> UiStore.setText("Hud/bar/liars", "うそつき ${s#liarCount}にん")

    /// 「この人を信じる？」は Confirming の間だけ出す（会話窓の上に重なる小パネル）。
    def applyConfirm(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        ui
            |> UiStore.setVisible("Dialog/confirm", s#phase == Room.Phase.Confirming)
            |> UiMenu.applyHighlight({
                listPath = confirmMenuPath(),
                highlightPath = "${confirmMenuPath()}/highlight",
                sel = s#confirmSel, rowPitch = confirmRowPitch(), inset = 0.5 })

    /// メモパネル: NPC 数ぶんのスロットに色見本・呼び名・マークを流し込む。
    def applyMemo(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        let entries = s#npcs |> List.map(npc ->
            ({ text = Palette.nameOf(npc#id), meta = Some(Int32.toString(npc#id)) }: UiSlots.Entry));
        ui
            |> UiStore.setVisible("Memo", s#memoOpen)
            |> UiSlots.fill(memoSlotSpec(), entries)
            |> UiMenu.applyItemLabels(memoMenuPath(), "mark", idx -> markText(markAt(idx, s)))
            |> applySwatchesAndTints(s)
            |> UiMenu.applyHighlight({
                listPath = memoMenuPath(),
                highlightPath = "${memoMenuPath()}/highlight",
                sel = s#memoSel, rowPitch = memoRowPitch(), inset = 0.5 })

    /// 各スロットの色見本を NPC の色に、マーク文字をマークの色に塗る。
    def applySwatchesAndTints(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        s#npcs |> List.foldLeft((acc, npc) -> {
            let slot = memoSlotSpec()#slotPath(npc#id);
            acc
                |> UiStore.setBoxColor("${slot}/swatch", Palette.npcBody(Palette.colorOf(npc#id)))
                |> UiStore.setTextTint("${slot}/mark", markTint(markAt(npc#id, s)))
        }, ui)

    def markAt(id: Int32, s: Room.State): Room.Mark =
        Map.get(id, s#memo) |> Option.getWithDefault(Room.Mark.Unknown)

    def markText(mark: Room.Mark): String = match mark {
        case Room.Mark.Unknown    => "？"
        case Room.Mark.LiarMark   => "うそ"
        case Room.Mark.HonestMark => "ほんと"
    }

    def markTint(mark: Room.Mark): Color = match mark {
        case Room.Mark.Unknown    => Palette.markUnknown()
        case Room.Mark.LiarMark   => Palette.markLiar()
        case Room.Mark.HonestMark => Palette.markHonest()
    }

    /// 正解・不正解のパネル。信じた相手の名前入りで結果を言い切る。
    def applyResult(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        let name = s#talkingTo |> Option.map(Palette.nameOf) |> Option.getWithDefault("？");
        match s#phase {
            case Room.Phase.Wrong =>
                ui
                    |> UiStore.setVisible("Result", true)
                    |> UiStore.setText("Result/panel/headline", "はずれ…")
                    |> UiStore.setTextTint("Result/panel/headline", Palette.markLiar())
                    |> UiStore.setText("Result/panel/detail", "${name}の人はうそつきだった…")
                    |> UiStore.setText("Result/panel/prompt", "Enter: もういちど")
            case Room.Phase.Cleared =>
                ui
                    |> UiStore.setVisible("Result", true)
                    |> UiStore.setText("Result/panel/headline", "せいかい！")
                    |> UiStore.setTextTint("Result/panel/headline", Palette.markHonest())
                    |> UiStore.setText("Result/panel/detail", "${name}の人は正直者だった！")
                    |> UiStore.setText("Result/panel/prompt",
                        if (s#stage < Stage.stageCount()) "Enter: つぎのへやへ" else "Enter: おしまいへ")
            case _ =>
                UiStore.setVisible("Result", false, ui)
        }
}
