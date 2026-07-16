// GameUi — 全ページ（Title / Hud / Dialog / Memo / Result / Ending）を ui.json から生成し、
// 毎フレーム World の判定結果を UiStore に刻み込む。見た目はすべて assets/*.ui.json にある。
mod GameUi {

    /// UI キャンバス、design px 単位。
    pub def designSize(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    def pagePaths(): List[String] =
        "assets/Title.ui.json" :: "assets/Hud.ui.json" :: "assets/Dialog.ui.json" ::
        "assets/Memo.ui.json" :: "assets/Result.ui.json" :: "assets/Ending.ui.json" :: Nil

    /// 全ページの Spec を 1 つの UiWorld へ生成する。壊れた・存在しないファイルは
    /// そのページを抜いたまま進む（ゲームはそれでも動く）。
    pub def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        pagePaths() |> List.foldLeft((ui, path) -> spawnPage(path, ui), UiStore.empty())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, spawned)) => spawned
            case Result.Err(_)           => ui
        }

    /// 会話窓の投影先（UiDialog に渡す名前パス束）。本文はスパン描画なので View 側が持つ。
    def dialogPaths(): UiDialog.Paths =
        { root = "Dialog", speaker = "Dialog/panel/speaker" }

    /// メモのスロット規約（7 スロット固定・NPC 数ぶんだけ埋める）。
    def memoSlotSpec(): UiSlots.SlotSpec =
        { slotPath = i -> "Memo/panel/menu/slot${i}", maxSlots = 7 }

    def memoMenuPath(): String = "Memo/panel/menu"

    /// メモの行ピッチ（ui.json のスロット高と一致させる）。
    def memoRowPitch(): Float64 = 13.0

    // ── 毎フレームの投影 ──

    pub def projectUi(w: Room.World, ui0: UiStore.UiWorld): UiStore.UiWorld =
        let Room.World.World(s) = w;
        ui0
            |> UiStore.setVisible("Title", s#phase == Room.Phase.Title)
            |> applyHud(s)
            |> UiDialog.apply(dialogPaths(), s#dialog)
            |> applySpeakerTint(s)
            |> applyMemo(s)
            |> applyResult(s)
            |> UiStore.setVisible("Ending", s#phase == Room.Phase.Ending)
            |> UiBinding.apply(key -> bindText(key, s))

    /// bind key → いまの表示文字列。ui.json 側の "bind" 宣言と対になる表。
    /// speakerName と slot 系の bind はここに載せない — 実行時は UiDialog / UiSlots / UiMenu が
    /// 流し込む欄で、bind 宣言はエディタのプレビュー用（None なら今の文字のまま）。
    def bindText(key: String, s: Room.State): Option[String] = match key {
        case "stageLabel"     => Some("ステージ ${s#stage}／${Stage.stageCount()}")
        case "liarsLabel"     => Some("うそつき ${s#liarCount}にん")
        case "submitLabel"    => Some(if (Room.memoComplete(s)) "Enter:こたえあわせ！" else "ぜんいんぶん埋めよう")
        case "resultHeadline" => resultText(s) |> Option.map(t -> t#headline)
        case "resultDetail"   => resultText(s) |> Option.map(t -> t#detail)
        case "resultPrompt"   => resultText(s) |> Option.map(t -> t#prompt)
        case _                => None
    }

    /// 正解・不正解パネルの文言。パネルが出ていないフェーズは None（隠れている欄は触らない）。
    def resultText(s: Room.State): Option[{headline = String, detail = String, prompt = String}] =
        match s#phase {
            case Room.Phase.Wrong   =>
                Some({ headline = "はずれ…", detail = "メモのどこかがちがう…", prompt = "Enter: もういちど" })
            case Room.Phase.Cleared =>
                Some({ headline = "せいかい！", detail = "ぜんいんの正体を見やぶった！",
                       prompt = if (s#stage < Stage.stageCount()) "Enter: つぎのへやへ" else "Enter: おしまいへ" })
            case _                  => None
        }

    /// HUD はゲーム中の全フェーズで出しっぱなし（タイトルとエンディングでは隠す）。
    def applyHud(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setVisible("Hud", s#phase != Room.Phase.Title and s#phase != Room.Phase.Ending, ui)

    /// 話者名を相手の色で塗る（本文の色付き名前と同じ約束）。
    def applySpeakerTint(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        match s#talkingTo {
            case None     => ui
            case Some(id) =>
                UiStore.setTextTint("Dialog/panel/speaker", Palette.npcText(Palette.colorOf(id)), ui)
        }

    /// メモパネル: NPC 数ぶんのスロットに色見本・呼び名・マークを流し込む。
    /// 全員ぶん埋まったら提出行が「こたえあわせ」に点灯する（メモ = 回答用紙）。
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
            |> applySubmitRow(s)

    /// 提出行の色: 全員ぶん埋まったら点灯、まだなら灰色（文言は bind submitLabel が入れる）。
    def applySubmitRow(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setTextTint("Memo/panel/submit",
            if (Room.memoComplete(s)) Palette.talkIndicator() else Palette.markUnknown(), ui)

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

    /// 正解・不正解のパネルの可視と見出し色（文言は bind の resultText が入れる）。
    /// 不正解ではどこが違うかは言わない（メモを見直させる）。
    def applyResult(s: Room.State, ui: UiStore.UiWorld): UiStore.UiWorld =
        match s#phase {
            case Room.Phase.Wrong =>
                ui
                    |> UiStore.setVisible("Result", true)
                    |> UiStore.setTextTint("Result/panel/headline", Palette.markLiar())
            case Room.Phase.Cleared =>
                ui
                    |> UiStore.setVisible("Result", true)
                    |> UiStore.setTextTint("Result/panel/headline", Palette.markHonest())
            case _ =>
                UiStore.setVisible("Result", false, ui)
        }
}
