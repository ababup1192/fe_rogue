// UiMenu — World-entity UI のリスト選択メニュー共通純関数
//
// 縦並びの選択メニュー（GameOverMenu / ActionMenu など）が共有する「項目列の列挙」と
// 「選択ハイライト・disabled 淡色の text tint 適用」をまとめる。各メニュー UI モジュールは
// 自分のノード木を ui.json で宣言し、リスト所有ノード（menu）配下に **meta を持つ子** を
// 項目として並べる。ここはその共通規約（meta 持ちの子 = 項目列・order 順）を 1 か所に閉じる。
//
// 規約: リスト所有 entity（listPath）の直下の子のうち **metas を持つもの** を、order 昇順に
// 並べた列が「選択カーソルの項目列」。meta を持たない子（見出し・区切り等）は項目に数えない。
// 動的メニュー（ActionMenu）は空きスロットの meta を `UiStore.clearMeta` で外すことで、
// 項目数を可視項目に追随させる（display:none レイアウトと組で窓が縮む）。

mod UiMenu {

    /// listPath 配下の「meta を持つ子」を order 順に列挙する（選択カーソルの項目列）。
    /// listPath が未登録なら空。
    pub def itemIds(listPath: String, ui: UiStore.UiWorld): List[EntityId] =
        match UiStore.idOf(listPath, ui) {
            case None     => Nil
            case Some(id) =>
                UiHierarchy.childrenOf(id, ui#parents, ui#order)
                    |> List.filter(child -> not Option.isEmpty(Map.get(child, ui#metas)))
        }

    /// 項目列の meta 文字列を order 順に集める。
    pub def metas(listPath: String, ui: UiStore.UiWorld): List[String] =
        itemIds(listPath, ui) |> List.filterMap(id -> Map.get(id, ui#metas))

    /// 項目数（meta を持つ子の数）。
    pub def count(listPath: String, ui: UiStore.UiWorld): Int32 =
        List.length(itemIds(listPath, ui))

    /// 選択カーソル位置の meta を取り出す（範囲外は None）。
    pub def metaAtSelection(listPath: String, selection: Int32, ui: UiStore.UiWorld): Option[String] =
        List.nth(selection, metas(listPath, ui))

    /// 項目列の各 text tint を index → 色の関数で塗る（選択ハイライト・disabled 淡色などを
    /// 呼び側が `tintOf` に閉じる）。index は項目列（meta 持ち子）の 0 起点順序。
    /// 例: `idx -> if (idx == sel) accent else normal`（GameOver）。
    pub def applyItemTints(listPath: String, tintOf: Int32 -> Color, ui: UiStore.UiWorld): UiStore.UiWorld =
        itemIds(listPath, ui)
            |> List.zipWithIndex
            |> List.foldLeft((acc, pair) -> {
                let (idx, id) = pair;
                tintById(id, tintOf(idx), acc)
            }, ui)

    /// 項目 entity の text tint を差し替える。項目ノード自身が text を持つ形（項目=text ノード）と、
    /// 固定高の行コンテナ配下に `label` text を置く形（項目=box/none コンテナ）の両対応。
    /// どちらの setTextTint も対象に text が無ければ no-op なので、両パスへ流して存在する方だけ塗る。
    def tintById(id: EntityId, tint: Color, ui: UiStore.UiWorld): UiStore.UiWorld =
        match UiStore.pathOf(id, ui) {
            case None       => ui
            case Some(path) =>
                ui
                    |> UiStore.setTextTint(path, tint)
                    |> UiStore.setTextTint("${path}/label", tint)
        }

    // ========================================================================
    // 選択ハイライト箱（塗り箱）の位置合わせ
    // ========================================================================

    /// `applyHighlight` の引数束。
    /// `listPath`: 項目列を所有する entity の名前パス（`UiMenu.itemIds` の起点）。
    /// `highlightPath`: 塗り箱（abs 子）の名前パス。
    /// `sel`: 選択カーソルの index（項目列基準。範囲外は防御的にクランプする）。
    /// `rowPitch`: 行の固定ピッチ（px）。
    /// `inset`: 行セルの内側マージン（px。箱を行セルより少し小さくして隣行と接しないため）。
    pub type alias HighlightArgs = {
        listPath      = String,
        highlightPath = String,
        sel           = Int32,
        rowPitch      = Float64,
        inset         = Float64
    }

    /// 選択行の塗り箱を選択位置へ動かす。箱は listPath 直下に置いた abs 子（highlightPath）で、
    /// 塗り・枠・角丸・寸法は ui.json 側で固定宣言し、ここでは選択 index と行ピッチから
    /// フロー外オフセット（listPath コンテンツ原点基準）だけを決め打ちで再計算する。
    ///
    /// 行ピッチが固定（各行 = 固定高スロット・gap 0）なので、レイアウト結果を読み戻さずに
    /// `y = inset + sel × rowPitch` で決定論的に置ける。
    ///
    /// 項目が無いときは箱を隠す。sel は防御的に [0, count) へクランプする。
    pub def applyHighlight(args: HighlightArgs, ui: UiStore.UiWorld): UiStore.UiWorld =
        match highlightPlacement(count(args#listPath, ui), args#sel, args#rowPitch, args#inset) {
            case None      => UiStore.setVisible(args#highlightPath, false, ui)
            case Some(pos) =>
                ui
                    |> UiStore.setVisible(args#highlightPath, true)
                    |> UiStore.setAbs(args#highlightPath, pos)
        }

    /// 塗り箱のフロー外オフセットを決める純関数（UiWorld 非依存）。
    /// 項目 0 のときは None（箱を隠す）。それ以外は sel を [0, count) にクランプした行の
    /// abs オフセット `{x = inset, y = inset + row × rowPitch}` を返す。
    /// 行ピッチ固定を前提に、レイアウト結果を読み戻さず決定論的に位置を出す（テストはここを pin する）。
    pub def highlightPlacement(itemCount: Int32, sel: Int32, rowPitch: Float64, inset: Float64): Option[Vec2.Vec2] =
        if (itemCount <= 0) None
        else Some({x = inset, y = inset + Int32.toFloat64(clampIndex(itemCount, sel)) * rowPitch})

    /// 選択 index を [0, count) へ収める純関数。項目 0 のときは 0。
    pub def clampIndex(itemCount: Int32, sel: Int32): Int32 =
        if (itemCount <= 0) 0 else Int32.max(0, Int32.min(itemCount - 1, sel))

    /// 選択カーソルを項目数 [0, count) の範囲へ収める（防御クランプ）。項目 0 のときは 0。
    /// フェーズ遷移や項目数の変動でカーソルが範囲外に取り残されても、確定・ハイライトが破綻しない。
    pub def clampSelection(listPath: String, ui: UiStore.UiWorld): UiStore.UiWorld =
        let sel = UiStore.selectionOf(listPath, ui);
        let clamped = clampIndex(count(listPath, ui), sel);
        if (clamped == sel) ui else UiStore.putSelection(listPath, clamped, ui)
}
