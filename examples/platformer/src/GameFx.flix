// GameFx — バーストの種から、粒の見た目を毎フレーム計算で導く（閉形式・状態を持たない）。
// World は (種, 発生位置, 方向, 勢い, 経過秒) だけを覚え、粒の実際の位置・大きさ・透明度は
// この elapsed から都度計算する。engine_world の Fx.deriveSeeded に乗せるだけの薄い層
// （モジュール名は engine_world の Fx と被らないよう GameFx にする）。
// power（0..1）は勢いの段階: 土埃は速いダッシュ・強い着地ほど粒が増えて大きくなる。

mod GameFx {

    /// 粒の寿命（秒）。Dust は短く散る、Jet はもう少し長く尾を引く。花火は大きく開いて消える。
    pub def lifeOf(kind: Field.FxKind): Float64 = match kind {
        case Field.FxKind.DustKind     => 0.3
        case Field.FxKind.JetKind      => 0.35
        case Field.FxKind.FireworkKind => 0.8
    }

    /// 1 バーストにつき出す粒の数。土埃は勢いで 4〜8 個に増える、ジェットは常に 12 個。
    def countOf(kind: Field.FxKind, power: Float64): Int32 = match kind {
        case Field.FxKind.DustKind     => 4 + RenderUtil.floatToInt32(Float64.floor(4.0 * power))
        case Field.FxKind.JetKind      => 12
        case Field.FxKind.FireworkKind => 24
    }

    /// 粒の飛ぶ速さ（px/秒）。
    def speedOf(kind: Field.FxKind): Float64 = match kind {
        case Field.FxKind.DustKind     => 30.0
        case Field.FxKind.JetKind      => 60.0
        case Field.FxKind.FireworkKind => 140.0
    }

    /// 粒の初期半径（px）。勢いで最大 1.8 倍まで育ち、寿命の経過とともに 0 へ縮む。
    def radiusOf(kind: Field.FxKind, power: Float64): Float64 =
        let base = match kind {
            case Field.FxKind.DustKind     => 2.0
            case Field.FxKind.JetKind      => 4.0
            case Field.FxKind.FireworkKind => 2.5
        };
        base * (1.0 + 0.8 * power)

    /// バースト 1 個から、粒 (位置, 半径, 透明度) の列を閉形式で導く。
    /// 粒ごとに dir を基準に、dir と直角な向きへ少しだけばらつかせて飛ばす（三角関数を使わず
    /// 直交ベクトルへの合成だけで散らす）。進んだ距離は速さ×elapsed。半径は寿命に向けて
    /// 線形に縮み、透明度も同様に落ちる。
    pub def particles(burst: Field.Burst): List[(Vec2.Vec2, Float64, Float32)] =
        let life = lifeOf(burst#kind);
        let count = countOf(burst#kind, burst#power);
        let speed = speedOf(burst#kind);
        let r0 = radiusOf(burst#kind, burst#power);
        Fx.deriveSeeded({ seed = burst#seed, count = count }, burst#elapsed,
            (i, rand, t) ->
                if (burst#kind == Field.FxKind.FireworkKind)
                    fireworkParticleAt(burst, life, speed, r0, count, i, rand, t)
                else particleAt(burst, life, speed, r0, i, rand, t))

    /// 花火の粒 1 個: 原点から放射状（count 等分の輪）へ飛び、重力の垂れ（40t² px）で
    /// 尾が下へしなる。速さは粒ごとに少し揺らして輪をほぐす。半径・透明度は寿命で減衰。
    def fireworkParticleAt(burst: Field.Burst, life: Float64, speed: Float64, r0: Float64,
                           count: Int32, i: Int32, rand: Int32 -> Float64, t: Float64):
                           (Vec2.Vec2, Float64, Float32) =
        let angle = Vec2.tau() * Int32.toFloat64(i) / Int32.toFloat64(count);
        let v = speed * (0.8 + 0.4 * rand(0));
        let pos = { x = burst#pos#x + Vec2.cos(angle) * v * t,
                    y = burst#pos#y + Vec2.sin(angle) * v * t + 40.0 * t * t };
        let progress = if (life <= 0.0) 1.0 else t / life;
        let radius = r0 * (1.0 - progress);
        let alpha = RenderUtil.f32(Float64.max(0.0, 1.0 - progress));
        (pos, radius, alpha)

    /// 粒 1 個の (位置, 半径, 透明度)。dir に直角なベクトルへ (rand(0)-0.5) 倍だけ寄せて
    /// 進行方向を散らし、速さも (rand(1)) で粒ごとに少し変える。
    def particleAt(burst: Field.Burst, life: Float64, speed: Float64, r0: Float64,
                   _i: Int32, rand: Int32 -> Float64, t: Float64): (Vec2.Vec2, Float64, Float32) =
        let perp = { x = -burst#dir#y, y = burst#dir#x };
        let wobble = (rand(0) - 0.5) * 1.2;
        let dirEffective = { x = burst#dir#x + perp#x * wobble, y = burst#dir#y + perp#y * wobble };
        let dist = speed * t * (0.6 + 0.4 * rand(1));
        let pos = { x = burst#pos#x + dirEffective#x * dist, y = burst#pos#y + dirEffective#y * dist };
        let progress = if (life <= 0.0) 1.0 else t / life;
        let radius = r0 * (1.0 - progress);
        let alpha = RenderUtil.f32(Float64.max(0.0, 1.0 - progress));
        (pos, radius, alpha)
}
