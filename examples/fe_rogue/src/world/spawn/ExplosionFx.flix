/// ExplosionFx — 一発再生の爆発エフェクト（火炎瓶 / 爆発瓶 / 魔法攻撃の着弾）
///
/// `DamagePopupFx` と同じ「emit で World の store に 1 件積み、tick で寿命を減らして
/// 期限切れを drop する」流儀（`Cmd.SpawnExplosionFx` で spawn・`stepWorld` が tick）。
/// `explosion` テクスチャ（assets/effect/explosion.png）の **1 行目** を寿命にわたって
/// frame 0 → frameCount-1 まで送ることでコマ送りアニメする。
///
/// scene ノードは持たない。寿命・位置・scale すべて World の `explosionFx` store が持ち、
/// 描画は `RenderWorld.renderExplosions` が Sprite 値を組んで直描きする（コマ送りは経過比率から導出）。
mod ExplosionFx {

    /// explosion.png は 896x576。64px グリッドで 14 列 x 9 行。**1 行目（frame 0..13）が爆発**。
    /// renderExplosions が使うため pub。
    pub def texture(): String = "explosion"
    pub def hframes(): Int32 = 14
    pub def vframes(): Int32 = 9
    /// 1 行目で使うコマ数（14 列ぶん）。
    pub def frameCount(): Int32 = 14
    /// 1 マス 16px に対して少し大きめ（迫力重視）に見せる拡大率（火炎瓶 / 魔法攻撃の着弾）。
    def scaleFactor(): Float64 = 0.4
    /// 爆発瓶用の大きい拡大率。3×3 の影響範囲を覆うサイズ感。
    def bigScaleFactor(): Float64 = 0.95
    /// 1 回の爆発の寿命（出現 → 消滅）。
    def lifetime(): Duration.Duration = Duration.millis(500)
    /// ダメージポップアップ(100)より少し奥。ユニットよりは前面。renderExplosions 用に pub。
    pub def zIndex(): Int32 = 90

    /// 指定セル中心に通常サイズの爆発を 1 つ発生させる。
    pub def emitAtCell(cell: {x = Int32, y = Int32}): Unit \ World.Command =
        emit(MapSnapshot.cellCenter(cell), scaleFactor())

    /// 指定セル中心に大きい爆発を 1 つ発生させる（爆発瓶用。3×3 範囲を覆う見た目）。
    pub def emitBigAtCell(cell: {x = Int32, y = Int32}): Unit \ World.Command =
        emit(MapSnapshot.cellCenter(cell), bigScaleFactor())

    /// 指定ワールド座標に `scale` 倍の爆発を 1 つ発生させる。
    /// `Cmd.SpawnExplosionFx` の emit のみ（ノード無し）。
    pub def emit(worldPos: Vec2.Vec2, scale: Float64): Unit \ World.Command =
        World.Command.emit(World.Cmd.SpawnExplosionFx(
            {total = Duration.toSeconds(lifetime()), pos = worldPos, scale = scale}))
}
