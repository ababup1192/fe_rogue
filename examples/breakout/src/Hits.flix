// Hits — hitbox.json の置き場所・キー名の対応表・寸法の引き方。判定の幾何と JSON の読みは
// エンジンの Hit / HitDoc が持ち、このゲーム固有の名前だけをここに集める。

mod Hits {
    use Hit.HitShape

    /// hitbox.json の置き場所。
    pub def path(): String = "assets/hitbox.json"

    /// ボールのキー名。
    pub def ballKey(): String = "ball"

    /// パドルのキー名。
    pub def paddleKey(): String = "paddle"

    /// hitbox.json に必ず居てほしいキー（ボール・パドル）。ブロックの寸法は格子から
    /// 導出される値なので JSON には置かず、World の式が持つ。
    pub def requiredKeys(): List[String] =
        ballKey() :: paddleKey() :: Nil

    /// 起動時ロード: 読めない・必須キーの欠けは起動を止めて知らせる。
    pub def load(): HitDoc.Sheet \ Fs.FileRead =
        HitDoc.loadOrBug(path(), requiredKeys())

    /// F1 リロード: 読めて欠けが無いときだけ差し替える（壊れていれば今の sheet を守る）。
    pub def reloaded(current: HitDoc.Sheet): HitDoc.Sheet \ Fs.FileRead =
        HitDoc.reloaded(requiredKeys(), HitDoc.load(path()), current)

    /// hitbox.json と同じ値のコード内 sheet。テストとギャラリーはファイルに依らずこちらを使う。
    /// 実行は Main が JSON を読む — 値を変えるときは両方を揃える（ずれは pin テストが見つける）。
    pub def defaults(): HitDoc.Sheet =
        Map#{
            ballKey()   => HitShape.CircleH({ dx = 0.0, dy = 0.0, r = 3.0 }) :: Nil,
            paddleKey() => HitShape.BoxH({ dx = 0.0, dy = 0.0, w = 44.0, h = 6.0 }) :: Nil
        }

    // ── 寸法の読み出し（宣言はどれも形 1 個なので先頭を見る）──

    /// ボールの半径。
    pub def ballRadius(hits: HitDoc.Sheet): Float64 = circleR(ballKey(), hits)

    /// パドルの幅と高さ。
    pub def paddleSize(hits: HitDoc.Sheet): Vec2.Vec2 = boxSize(paddleKey(), hits)

    /// key の宣言を物理の Store 用に変換する（中心からのずれ, CollisionShape2D）。
    /// ずれは呼び側が位置に足す（Hit.toCollisionShape の取り決め）。
    pub def collisionOf(key: String, hits: HitDoc.Sheet): (Vec2.Vec2, CollisionShape2D) =
        Hit.toCollisionShape(headShape(key, hits))

    /// key の先頭の形。空は「当たらないゲーム」を黙って作るので止める（起動時の load が普段は防ぐ）。
    def headShape(key: String, hits: HitDoc.Sheet): HitShape =
        match HitDoc.shapesOf(key, hits) {
            case shape :: _ => shape
            case Nil        => bug!("hitbox: hit '${key}' has no shape")
        }

    /// key の円の半径。円でなければ止める（黙って別の寸法を使わない）。
    def circleR(key: String, hits: HitDoc.Sheet): Float64 =
        match headShape(key, hits) {
            case HitShape.CircleH(c) => c#r
            case HitShape.BoxH(_)    => bug!("hitbox: hit '${key}' must be a circle")
        }

    /// key の箱の幅と高さ。箱でなければ止める。
    def boxSize(key: String, hits: HitDoc.Sheet): Vec2.Vec2 =
        match headShape(key, hits) {
            case HitShape.BoxH(b)    => { x = b#w, y = b#h }
            case HitShape.CircleH(_) => bug!("hitbox: hit '${key}' must be a box")
        }
}
