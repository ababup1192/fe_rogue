// ZBand — 重なり順（zIndex）の「帯」の取り決めの正本。
// world の絵がどれだけ大きい z を使っても HUD より手前には出ない、を数で保証する。
// 利用例: composeScene が hud の z を HUD 帯へ持ち上げる / 描画部が帯ごとに並べ替える。
// 帯の地図（どの帯が何用か）は docs/z-bands.md にある。
mod ZBand {

    /// 帯 1 本の幅。帯の中で使える z は 0..innerMax（幅 - 1）まで。
    pub def bandWidth(): Int32 = 100_000_000

    /// 帯の中で使える z の上限。はみ出した z は clamp する（wrap しない —
    /// 折り返すと「大きい z ほど手前」の約束が帯の境目で裏返るため）。
    pub def innerMax(): Int32 = 99_999_999

    /// HUD 帯の底。withHudView の絵は composeScene がここへ持ち上げる。
    pub def hudBase(): Int32 = 1_000_000_000

    /// エンジンデバッグ帯の底（fps・矩形注釈・トースト・スクラブ表示）。
    /// HUD 帯よりさらに手前 — デバッグ中の表示はゲームのどの絵にも隠されない。
    /// Int32 の上限 2_147_483_647 に収まる（この帯の中は 0..10 しか使わない）。
    pub def debugBase(): Int32 = 2_000_000_000

    /// hud の z を HUD 帯へ持ち上げる（帯内は 0..innerMax に clamp）。
    pub def liftHud(z: Int32): Int32 =
        hudBase() + Int32.max(0, Int32.min(innerMax(), z))
}
