// B0a ゲート spike — ActionMenu を render-from-World で描く試験実装（engine 改修なし・text/solidBox のみ）。
// 目的: scene.json(宣言ノード木) + ItemList ウィジェット が提供していた描画/レイアウトを
//       「手書き Flix layout」へ置換するコストを実測する。throwaway。
//
// 現 ActionMenu の scene.json が宣言していたもの（99行・GUI 編集可）:
//   Panel(bg/border) → headerBg/headerBgFill(Panel) → header(Label2D) → menu(ItemList: cursor/focus/disabled/auto-size 内蔵)
// ↓ render-from-World では全部このコードに：
mod BGateActionMenuRender {
    use Render.RenderItem
    use Vec2.Vec2

    /// World 由来のメニュー状態（scene Data でなく純データ）。
    /// 本来は World component（menuEntity の MenuComp）から引く想定。
    pub type alias MenuState = {
        pos       = Vec2,              // パネル左上
        header    = String,
        items     = List[(String, Bool)],  // (ラベル, enabled)
        selected  = Int32,
        focused   = Bool
    }

    // ── 色（scene.json の background/border を手書きで再現）──
    // ⚠ engine gap: Render.text に色引数が無いため header/item/disabled/cursor の *文字色* は再現不可。
    //   box 系の色だけ指定できる（下記）。文字着色は本体 B で Render.text(tint) 追加が前提。
    def panelBg(): Color    = {r = 0.12f32, g = 0.15f32, b = 0.22f32}
    def headerBg(): Color   = {r = 0.067f32, g = 0.094f32, b = 0.165f32}
    def highlightBg(): Color = {r = 0.22f32, g = 0.18f32, b = 0.12f32}

    // ── レイアウト定数（scene.json の pos/size/fontSize を手書き定数化）──
    def panelW(): Float64 = 40.0
    def headerH(): Float64 = 7.0
    def itemH(): Float64 = 5.0
    def fontSize(): Float64 = 2.56
    def headerFontSize(): Float64 = 2.4
    def padX(): Float64 = 4.0
    def cursorOffsetX(): Float64 = 3.0
    def cursorGlyph(): String = "▶"  // ▶

    // zIndex 帯
    def zPanel(): Int32     = 0
    def zHighlight(): Int32 = 1
    def zText(): Int32      = 2

    /// エントリ: MenuState → draw list（dodge RenderWorld と同型の extract）。
    pub def drawActionMenu(st: MenuState, atlas: FontAtlas): List[(Vec2, RenderItem)] =
        if (List.isEmpty(st#items)) Nil
        else {
            let n = List.length(st#items);
            let panelH = headerH() + itemH() * Int32.toFloat64(n) + 2.0;
            // パネル背景
            let panel = (st#pos, Render.solidBox({x = panelW(), y = panelH}, panelBg(), zPanel()));
            // ヘッダ背景 + ヘッダ文字
            let hbg = ({x = st#pos#x + 1.0, y = st#pos#y + 1.0},
                       Render.solidBox({x = panelW() - 2.0, y = headerH() - 1.0}, headerBg(), zPanel()));
            let htext = ({x = st#pos#x + padX(), y = st#pos#y + 2.0},
                         Render.text(st#header, atlas, headerFontSize(), zText()));
            // 各項目（cursor/highlight/disabled 色を手書き）
            let itemsY0 = st#pos#y + headerH();
            // ⚠ engine gap: Render.text(content, atlas, fontSize, zIndex) に色引数が無い＝disabled グレー /
            //   cursor 色が出せない（ItemList は per-item 色を持っていた）。本体 B では Render.text に tint 追加要。
            let itemDraws = List.flatten(List.mapWithIndex(i -> entry -> {
                let (label, _enabled) = entry;
                let y = itemsY0 + itemH() * Int32.toFloat64(i);
                let isSel = i == st#selected;
                let row = ({x = st#pos#x + padX(), y = y}, Render.text(label, atlas, fontSize(), zText()));
                // 選択行のハイライト枠（focus 時のみ・色分けは box で代替＝text 着色不可の回避）
                let hi = if (isSel and st#focused)
                             ({x = st#pos#x + 1.0, y = y - 0.5}, Render.solidBox({x = panelW() - 2.0, y = itemH()}, highlightBg(), zHighlight())) :: Nil
                         else Nil;
                let cur = if (isSel and st#focused)
                              ({x = st#pos#x + cursorOffsetX() - 1.0, y = y}, Render.text(cursorGlyph(), atlas, fontSize(), zText())) :: Nil
                          else Nil;
                List.append(hi, row :: cur)
            }, st#items));
            panel :: hbg :: htext :: itemDraws
        }
}
