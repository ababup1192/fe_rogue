/// EntityScene — faction-blind な scene accessor 層（`EntityRef` → PlayerScene/EnemyScene dispatch の集約点）
///
/// World 側の `toUid`/`teamOf`（store を faction-blind に触る seam）に対応する **scene 版**。
/// 「`match ref { Player => PlayerScene.x ; Enemy => EnemyScene.x }`」という Player/Enemy 分岐を
/// **この 1 モジュールだけ**に閉じ込め、combat 等の本体を faction-blind にする。
///
/// 狙い: faction 分岐を各 scene に散らさない。faction の表現（split→unified 等）が変わっても、
/// 直す箇所はこのモジュール（と World の `toUid`/`refOfSide`）だけで済む。
mod EntityScene {

    /// EntityRef → scene ノードパス（playerPath / enemyPath）。
    pub def path(ref: World.EntityRef): NodePath = match ref {
        case World.EntityRef.Player(id) => PlayerScene.playerPath(id)
        case World.EntityRef.Enemy(id)  => EnemyScene.enemyPath(id)
    }

    /// EntityRef の UnitView（faction 非依存ビュー）。
    /// P6-2b fix: pos は **World.posOf で上書き**する（scene Data の gridPos twin は退役＝凍結値。
    /// これを attack lunge の origin に使うとマーカーが古いセルへ飛び・戻るバグになる）。
    pub def unitView(ref: World.EntityRef, scene: Scene[NodeTag]): Option[UnitView] \ World.WorldQuery =
        let w = World.WorldQuery.get();
        let base = match ref {
            case World.EntityRef.Player(id) => PlayerScene.get(id, scene) |> Option.map(PlayerScene.unitView)
            case World.EntityRef.Enemy(id)  => EnemyScene.get(id, scene) |> Option.map(EnemyScene.unitView)
        };
        base |> Option.map(uv -> {pos = World.posOf(ref, w) |> Option.getWithDefault(uv#pos) | uv})

    /// EntityRef の scene `attackTargetId` を書く（faction-blind）。
    pub def setAttackTargetId(ref: World.EntityRef, target: Int32, scene: Scene[NodeTag]): Scene[NodeTag] = match ref {
        case World.EntityRef.Player(id) => PlayerScene.mapPlayer(id, dd -> {attackTargetId = Some(target) | dd}, scene)
        case World.EntityRef.Enemy(id)  => EnemyScene.mapEnemy(id, dd -> {attackTargetId = Some(target) | dd}, scene)
    }
}
