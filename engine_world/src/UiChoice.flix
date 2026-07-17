/// UiChoice — 左右キーで候補を 1 つずつ送る「サイクラー」行の純粋ヘルパ。
/// 候補の中身（文字列一覧など）はゲーム側が持ち、ここでは index の循環だけを扱う。
mod UiChoice {

    /// 選択位置と候補数。count <= 0 のときは常に index = 0 として扱う。
    pub type alias State = { index = Int32, count = Int32 }

    /// 次の候補へ（末尾の次は先頭へ回り込む）。
    pub def next(st: State): State =
        { index = UiMenu.moveCursor(1, st#count, st#index) | st }

    /// 前の候補へ（先頭の前は末尾へ回り込む）。
    pub def prev(st: State): State =
        { index = UiMenu.moveCursor(-1, st#count, st#index) | st }

    /// namePath 配下の `${namePath}/label` へ表示文言を書き込む。
    /// 文言そのもの（labelOf: index → 文字列）はゲーム側の候補一覧が決める。
    pub def apply(namePath: String, st: State, labelOf: Int32 -> String, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setText("${namePath}/label", labelOf(st#index), ui)
}
