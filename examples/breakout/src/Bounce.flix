// Bounce — Step が使う反射のルール（純関数）: パドルで受けた瞬間の「角度」と「速さ」を
// 決める古典式。本作の一番の見せ物。
//
// 角度: 中央に当たれば真上へ、端に寄るほど開いて鋭角に飛ぶ。当たった位置だけで決まる。
// 速さ: 受けるたびに少しずつ増し、端で受けるとさらに増す（上限つき）。どちらも純粋な
// 規則なので、プレイヤーは「端で当てれば横へ逃がせるが、速くなる」という駆け引きを
// 体で覚えられる。物理エンジン（Physics2D）が返す素の反射を、パドル接触のときだけ
// この 2 つの式で上書きする。
//
// 各規則は「パラメータを引数で受ける版（…At / …With）」が芯で、既定値の定数を埋めた短い名前が
// その別名。ゲームは parameters.json（F1 リロード）の値を芯へ渡し、テストとギャラリーは別名 =
// 既定値を使う。画面座標は y が下向きなので、「上へ返す」= y 成分は負。

mod Bounce {

    /// パドル中心からの最大反射角の既定値（真上=垂直からの傾き、ラジアン）。
    /// 60 度: 中央の真上から端の鋭角まで、開きが一目で分かる大きさに選んだ。
    pub def maxBounceAngle(): Float64 = 1.0471975511965976  // 60° = π/3

    /// パドル中心からの水平オフセットを [-1, 1] に正規化する。中心=0・左端=-1・右端=+1。
    /// 同じ型（Float64）が並ぶので名前で束ねる: ballX = ボール中心の x / paddleX = パドル中心の x /
    /// halfWidth = パドルの半幅（0 以下なら 0 を返して 0 除算を避ける）。
    pub def offsetFraction(spot: { ballX = Float64, paddleX = Float64, halfWidth = Float64 }): Float64 =
        if (spot#halfWidth <= 0.0) 0.0 else (spot#ballX - spot#paddleX) / spot#halfWidth

    /// 当たった位置に応じた反射角（垂直からの傾き）、最大角 maxAngle 指定版。
    /// offsetFrac は [-1, 1] にクランプされ、中央=0 で真上、端=±1 で ±maxAngle。
    pub def bounceAngleAt(maxAngle: Float64, offsetFrac: Float64): Float64 =
        Float64.max(-1.0, Float64.min(1.0, offsetFrac)) * maxAngle

    /// 既定の最大角での反射角。offsetFraction の結果をそのまま渡せる。
    pub def bounceAngle(offsetFrac: Float64): Float64 =
        bounceAngleAt(maxBounceAngle(), offsetFrac)

    /// パドルに当たったボールの新しい速度、パラメータ指定版。速さ speed は保つ。
    /// 中央は真上 (0, -speed)、端ほど横へ開く。返すのは常に上向き（y 成分が負）。
    /// 同じ型（Float64）が並ぶので名前で束ねる。
    pub def paddleReflectWith(spec: { maxAngle = Float64, offsetFrac = Float64, speed = Float64 }): Vec2.Vec2 =
        let angle = bounceAngleAt(spec#maxAngle, spec#offsetFrac);
        { x = spec#speed * RenderUtil.sinF(angle), y = -1.0 * spec#speed * RenderUtil.cosF(angle) }

    /// 既定の最大角での反射速度。
    pub def paddleReflect(offsetFrac: Float64, speed: Float64): Vec2.Vec2 =
        paddleReflectWith({ maxAngle = maxBounceAngle(), offsetFrac = offsetFrac, speed = speed })

    // ── 加速規則: ラリーが続くほど速く、端で受けるほどさらに速く ──
    // パドルヒットのたびに速さが少しずつ上がるので、同じ面でも終盤ほど張り詰める。
    // 端当ては角度が鋭くなるだけでなく追加の加速も付く —— 狙う価値と外す危険が釣り合う。
    // ミス（落下）後のサーブは基準の速さに戻る（リセットは Field.serveVelocity が担う）。

    /// パドルヒット 1 回ごとの倍率の既定値（+2.5%）。ラリーの基本の加速パラメータ。
    pub def speedGainPerHit(): Float64 = 1.025

    /// 端当ての追加加速の既定値。|offsetFraction| に比例し、端いっぱい（±1）でさらに +5%。
    pub def edgeSpeedBonus(): Float64 = 0.05

    /// 速さの上限の既定値、基準速度に対する倍率。どれだけ加速してもこの倍を超えない。
    pub def maxSpeedFactor(): Float64 = 1.6

    /// 加速規則のパラメータ一式（同じ型が並ぶので名前で束ねる）。
    pub type alias SpeedTuning = { gain = Float64, edgeBonus = Float64, maxFactor = Float64 }

    /// 既定値ぞろいの加速パラメータ。
    pub def defaultTuning(): SpeedTuning =
        { gain = speedGainPerHit(), edgeBonus = edgeSpeedBonus(), maxFactor = maxSpeedFactor() }

    /// speedAfterHit の引数一式。同じ型（Float64）が並ぶので名前で束ねる。
    /// current = 当たる直前の速さ / offsetFrac = 当たり位置（-1..1）/ base = 基準の速さ。
    pub type alias HitSpeed = { current = Float64, offsetFrac = Float64, base = Float64 }

    /// パドルヒット後の新しい速さ、パラメータ指定版。基準未満に落ちていれば基準まで戻してから、
    /// ヒット毎の倍率と端当てボーナスを掛け、上限（base × maxFactor）でクランプする。
    pub def speedAfterHitWith(tuning: SpeedTuning, spec: HitSpeed): Float64 =
        let edge = Float64.abs(Float64.max(-1.0, Float64.min(1.0, spec#offsetFrac)));
        let boosted = Float64.max(spec#base, spec#current)
            * tuning#gain * (1.0 + tuning#edgeBonus * edge);
        Float64.min(spec#base * tuning#maxFactor, boosted)

    /// 既定パラメータでのヒット後の速さ。
    pub def speedAfterHit(spec: HitSpeed): Float64 =
        speedAfterHitWith(defaultTuning(), spec)

    /// いまの速さが加速の道のりのどこか、パラメータ指定版: 基準 = 0、
    /// 上限（base × maxFactor）= 1 に正規化して [0, 1] にクランプする。
    /// 残像の色など「加速の見える化」の共通入力。同じ型（Float64）が並ぶので名前で束ねる。
    pub def speedRatioWith(spec: { maxFactor = Float64, speed = Float64, base = Float64 }): Float64 =
        let span = spec#base * (spec#maxFactor - 1.0);
        if (span <= 0.0) 0.0
        else Float64.max(0.0, Float64.min(1.0, (spec#speed - spec#base) / span))

    /// 既定の上限倍率での加速の道のり。
    pub def speedRatio(speed: Float64, base: Float64): Float64 =
        speedRatioWith({ maxFactor = maxSpeedFactor(), speed = speed, base = base })
}
