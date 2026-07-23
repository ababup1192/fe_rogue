// NovelKit — 会話窓と選択肢の「キット」。見た目は assets/ui/*.ui.json が持ち、
// ここは状態（いま何を話していて、何を選ばせているか）とその進め方だけを持つ（純粋）。
// 中身はエンジンの UiDialog（開閉と行送り）+ UiTypewriter（文字送り）+ UiSlots（選択肢の
// 流し込み）の組み合わせで、クリックの意味は meta 文字列（novel/choice/N）で伝える。
mod NovelKit {

    /// キットの状態。choices が Some のときは「文字送りが終わったら選択肢を出す」。
    pub type alias Kit = {
        dialog = UiDialog.Dialog,
        choices = Option[List[UiSlots.Entry]]
    }

    pub def closed(): Kit =
        { dialog = UiDialog.closed(), choices = None }

    /// 1 拍しゃべる（speaker が空文字なら地の文）。
    pub def say(speaker: String, text: String): Kit =
        { dialog = UiDialog.openWith({ speaker = speaker, body = RichText.plain(text) :: Nil } :: Nil),
          choices = None }

    /// 1 拍しゃべって、読み終えたら選択肢を出す。スロットは 6 枠なので、
    /// あふれた分は黙って切り捨てる（台本は Doc なので落とさない = fail-open）。
    pub def ask(speaker: String, text: String, entries: List[UiSlots.Entry]): Kit =
        { dialog = UiDialog.openWith({ speaker = speaker, body = RichText.plain(text) :: Nil } :: Nil),
          choices = Some(List.take(maxChoices(), entries)) }

    /// 選択肢スロットの数（assets/ui/choices.ui.json の slot0..slot5 と対）。
    pub def maxChoices(): Int32 = 6

    /// 毎フレームの文字送り。速さ（cps）は novel.kind.json から来る。
    pub def step(cps: {cps = Float64}, dt: Float64, kit: Kit): Kit =
        { dialog = UiDialog.step(cps = cps#cps, dt, kit#dialog) | kit }

    /// 決定 1 回分。選択肢待ちでは窓を閉じない（文字送りの飛ばしだけ効く）。
    pub def advance(kit: Kit): Kit =
        if (isAsking(kit)) kit
        else { dialog = UiDialog.advance(kit#dialog) | kit }

    /// 選択肢を出して入力を待っている状態か（本文を読み終えてから出す）。
    /// 空の選択肢は「待ち」にしない — advance も選択もできない詰みを作らないため。
    pub def isAsking(kit: Kit): Bool =
        match kit#choices {
            case Some(entries) =>
                not List.isEmpty(entries) and UiDialog.lineDone(kit#dialog) and UiDialog.isOpen(kit#dialog)
            case None => false
        }

    pub def isOpen(kit: Kit): Bool =
        UiDialog.isOpen(kit#dialog)

    // ── UiStore への投影（名前パスは assets/ui/*.ui.json の宣言と対） ──

    def dialogPaths(): UiDialog.Paths =
        { root = "novel_dialog", speaker = "novel_dialog/panel/speaker" }

    /// 選択肢の項目列を持つパネルの名前パス。UiMenu の listPath に渡す。
    pub def choicesPath(): String = "novel_choices/panel"

    /// 選択肢 meta の接頭辞。後ろに番号を足して novel/choice/N になる。
    pub def choicePrefix(): String = "novel/choice/"

    def choiceSlots(): UiSlots.SlotSpec =
        { slotPath = i -> "${choicesPath()}/slot${i}", maxSlots = maxChoices() }

    /// 毎フレーム、キットの状態を UI へ刻む。本文（スパン）は body が別に描く。
    pub def apply(kit: Kit, ui: UiStore.UiWorld): UiStore.UiWorld =
        let ui1 = UiDialog.apply(dialogPaths(), kit#dialog, ui);
        match (if (isAsking(kit)) kit#choices else None) {
            case Some(entries) =>
                ui1 |> UiStore.setVisible("novel_choices", true)
                    |> UiSlots.fill(choiceSlots(), entries)
            case None => UiStore.setVisible("novel_choices", false, ui1)
        }

    /// 本文（文字送りの途中まで）。会話窓パネルの内側に折り返して描く。
    /// 置き場所と幅は dialog.ui.json のパネル（abs [12, 226]・幅 456・pad 10/5）から導いた値。
    /// 文字色（ink）は色票（novel.theme.json）から来る。
    pub def body(atlas: FontAtlas, ink: Color, kit: Kit): List[Render.PlacedItem] =
        RichText.place(
            { atlas = atlas, size = 10.0, baseTint = ink,
              z = 103, pos = { x = 22.0, y = 244.0 }, maxWidth = 436.0, lineGap = 3.0 },
            UiDialog.visibleBody(kit#dialog))

    /// キットが使う ui.json の一覧（spawn と「表示中」の名乗りが同じ台帳を見る）。
    pub def uiPaths(): List[String] =
        "assets/ui/dialog.ui.json" :: "assets/ui/choices.ui.json" :: Nil

    /// キットの ui.json 一式を 1 つの UiStore へ spawn する（起動と bake が同じ台帳を見る）。
    pub def spawnAssets(): UiStore.UiWorld \ Fs.FileRead =
        List.foldLeft((ui, path) -> spawnOne(path, ui), UiStore.empty(), uiPaths())

    def spawnOne(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Ok((_, ui1)) => ui1
            case Err(e)       => bug!("${path}: ${JsonCompat.describe(e)}")
        }
}
