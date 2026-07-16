// Hits — hitbox.json の置き場所・キー名の対応表・半径の引き方。判定の幾何と JSON の読みは
// エンジンの Hit / HitDoc が持ち、このゲーム固有の名前だけをここに集める。
// 対象は照会型の当たり（敵との接触・踏み）だけ。地形は Physics2D の領分なので宣言しない。

mod Hits {
    use Hit.HitShape

    /// hitbox.json の置き場所。
    pub def path(): String = "assets/hitbox.json"

    /// 自機のキー名。
    pub def playerKey(): String = "player"

    /// 敵のキー名（全種共通の 1 つの円）。
    pub def enemyKey(): String = "enemy"

    /// hitbox.json に必ず居てほしいキー（自機・敵）。
    pub def requiredKeys(): List[String] =
        playerKey() :: enemyKey() :: Nil

    /// 起動時ロード: 読めない・必須キーの欠けは起動を止めて知らせる。
    pub def load(): HitDoc.Sheet \ Fs.FileRead =
        HitDoc.loadOrBug(path(), requiredKeys())

    /// F1 リロード: 読めて欠けが無いときだけ差し替える（壊れていれば今の sheet を守る）。
    pub def reloaded(current: HitDoc.Sheet): HitDoc.Sheet \ Fs.FileRead =
        HitDoc.reloaded(requiredKeys(), HitDoc.load(path()), current)

    /// hitbox.json と同じ値のコード内 sheet。テストとギャラリーはファイルに依らずこちらを使う。
    /// 実行は Main が JSON を読む — ずれは pin テスト（TestHits）が見つける。
    pub def defaults(): HitDoc.Sheet =
        Map#{
            playerKey() => HitShape.CircleH({ dx = 0.0, dy = 0.0, r = Field.playerRadius() }) :: Nil,
            enemyKey()  => HitShape.CircleH({ dx = 0.0, dy = 0.0, r = Field.enemyRadius() }) :: Nil
        }

    /// 敵の判定半径（宣言 sheet から）。踏みの「頭より上か」のしきい値が使う。
    pub def enemyHitRadius(hits: HitDoc.Sheet): Float64 =
        match headShape(enemyKey(), hits) {
            case HitShape.CircleH(c) => c#r
            case HitShape.BoxH(_)    => bug!("hitbox: hit 'enemy' must be a circle")
        }

    /// key の先頭の形。空は「当たらないゲーム」を黙って作るので止める（起動時の load が普段は防ぐ）。
    def headShape(key: String, hits: HitDoc.Sheet): HitShape =
        match HitDoc.shapesOf(key, hits) {
            case shape :: _ => shape
            case Nil        => bug!("hitbox: hit '${key}' has no shape")
        }
}
