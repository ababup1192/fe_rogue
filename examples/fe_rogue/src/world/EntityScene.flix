/// EntityScene — faction-blind な accessor 層（`EntityRef` → PlayerScene/EnemyScene dispatch の集約点）
///
/// World 側の `toUid`/`teamOf`（store を faction-blind に触る seam）に対応する **駒操作版**。
/// 「`match ref { Player => PlayerScene.x ; Enemy => EnemyScene.x }`」という Player/Enemy 分岐を
/// **この 1 モジュールだけ**に閉じ込め、combat 等の本体を faction-blind にする。
///
/// 狙い: faction 分岐を各モジュールに散らさない。faction の表現（split→unified 等）が変わっても、
/// 直す箇所はこのモジュール（と World の `toUid`/`refOfSide`）だけで済む。
mod EntityScene {

    /// EntityRef の UnitView（faction 非依存ビュー）。
    /// 在庫/statuses 込みの盤上ビューは World 単独再構築（unitViewFromWorld）が権威。
    pub def unitView(ref: World.EntityRef): Option[UnitView] \ World.WorldQuery =
        World.unitViewFromWorld(ref, World.WorldQuery.get())
}
