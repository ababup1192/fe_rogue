/// UITheme — fe_rogue の UI 共通色パレット（Scene ではない共有定数モジュール）
///
/// 複数の Scene で同値だった色（特に白 (1,1,1) が 17 箇所、駒の dim グレー (0.5) が 2 箇所）を
/// 1 箇所に集約する。各 Scene のセマンティックな関数（textColor / borderColor / activeColor /
/// damageToEnemyColor 等）は **名前を残したまま** 本モジュールへ委譲し、「何の色か」という宣言的
/// intent を保ちつつ、色値の真理点だけを一本化する（白を一括で変えたいとき 1 箇所で済む）。
///
/// 画面固有の意味を持つ色（playerColor / enemyColor / itemColor / fogColor / stairsColor /
/// selectedColor / hpBarFillColor / windowBgColor 等）は各 Scene にローカルのまま残す（過剰集約を避ける）。
mod UITheme {

    /// 標準の白。UI テキスト・枠・フォーカス枠・アクティブ駒 modulate・ダメージ数字・
    /// 危険域タイルなど、多数の Scene が共通で使う基本色。
    pub def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 行動済み（待機 / acted）の駒を薄く見せる modulate 用グレー。
    /// アクティブ駒は `white()`、行動済みは `dimmed()` という対のセマンティクスで使う。
    pub def dimmed(): Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32}

    // ── コマンドウィンドウ配色（HTML プロトタイプ「遺宝探索記 UI」と同値）──

    /// ウィンドウ地色。panel #1f2638（near-black から一段明るく。アイコンは別途明るい敷物で見せる）。
    /// scene.json の panel `background`（ActionMenu / WeaponSelect / UnitCard）と同期（test で pin）。
    pub def panel(): Color = {r = 0.12f32, g = 0.15f32, b = 0.22f32}

    /// ウィンドウ枠の暗いスレート。panelBorder #2a3445。
    /// scene.json の panel `border` と同期（test で pin）。
    pub def panelBorder(): Color = {r = 0.165f32, g = 0.204f32, b = 0.271f32}

    /// 見出し（● コマンド）の淡い青。headerText #9cc0ff。
    /// scene.json の header `modulate` と同期（test で pin）。
    pub def headerText(): Color = {r = 0.612f32, g = 0.753f32, b = 1.0f32}

    /// 項目本文の白に近いオフホワイト。labelText #eef1f7。menu `textColor` の真理点。
    /// NOTE: ItemList に textColor getter が無いため test pin は未（値は scene.json に再掲）。
    pub def labelText(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}

    /// 味方の青（選択枠）。allyBlue #2f6df0。
    /// scene.json の selectedHighlight `borderColor` と同期（test で pin）。
    pub def allyBlue(): Color = {r = 0.184f32, g = 0.427f32, b = 0.941f32}

    /// 選択行の塗り（暗い藍）。selectBg #16314f。
    /// scene.json の selectedHighlight `fillColor` と同期（test で pin）。
    pub def selectBg(): Color = {r = 0.086f32, g = 0.192f32, b = 0.310f32}

    /// 全行チップの塗り（地よりわずかに明るい紺）。rowBg #0e1626。
    /// scene.json の rowHighlight `fillColor` と同期（test で pin）。
    pub def rowBg(): Color = {r = 0.055f32, g = 0.086f32, b = 0.149f32}

    /// 全行チップの枠（控えめなスレート）。rowBorder #1c2533。
    /// scene.json の rowHighlight `borderColor` と同期（test で pin）。
    pub def rowBorder(): Color = {r = 0.110f32, g = 0.145f32, b = 0.200f32}

    /// サブラベルの淡色（くすんだ青灰）。faint #7d8aa3。menu `subtextColor` の真理点。
    /// NOTE: ItemList に subtextColor getter が無いため test pin は未（値は scene.json に再掲）。
    pub def faint(): Color = {r = 0.490f32, g = 0.541f32, b = 0.639f32}

    // ── 重量（積載段階）の警告色 ──────────────────────────────────────
    // 重くなるほど黄→橙→赤で警告する。アイテム窓の重量ゲージと交換窓のヘッダで共用する。

    /// 軽量超過（積載 80%+）の黄。
    pub def encumbranceHeavy(): Color = {r = 1.0f32, g = 0.85f32, b = 0.3f32}

    /// 重量オーバー（積載 100%+）の橙。
    pub def encumbranceOverloaded(): Color = {r = 1.0f32, g = 0.6f32, b = 0.2f32}

    /// 重量過多（積載 110%+・移動不可）の赤。
    pub def encumbranceImmobile(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// 積載段階 → ゲージ色。通常はヘッダ色、超過するほど黄→橙→赤。
    /// 重量ゲージ（ItemMenu）と交換ヘッダ（Trade）が同じ配色を共有する単一の真理点。
    pub def encumbranceTierColor(tier: Encumbrance.Tier): Color = match tier {
        case Encumbrance.Tier.Normal     => headerText()
        case Encumbrance.Tier.Heavy      => encumbranceHeavy()
        case Encumbrance.Tier.Overloaded => encumbranceOverloaded()
        case Encumbrance.Tier.Immobile   => encumbranceImmobile()
    }
}
