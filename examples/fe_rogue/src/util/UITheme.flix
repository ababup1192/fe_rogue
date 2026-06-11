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
}
