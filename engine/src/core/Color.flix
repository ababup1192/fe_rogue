// Color — 3 チャンネル sRGB-linear カラー (alpha は別途持つ運用)
//
// Float32 ベース。GL の uniform に直接渡せるレンジ 0.0〜1.0。
// engine（契約層）の共有型なので、フロントのシーングラフとバックエンド（render_gl）が同じ色定義を見る。

pub type alias Color = {r = Float32, g = Float32, b = Float32}

mod Color {

    /// 色を白へamountだけ寄せる。通常は0から1を渡し、範囲外は補正しない。
    /// 既存ゲームと同じ色を保つため、amountをFloat32へ変えてから各チャンネルを補間する。
    pub def lighten(color: Color, amount: Float64): Color =
        let value = Float64.truncateToFloat32(amount);
        { r = color#r + (1.0f32 - color#r) * value,
          g = color#g + (1.0f32 - color#g) * value,
          b = color#b + (1.0f32 - color#b) * value }

    /// 色を黒へamountだけ寄せる。通常は0から1を渡し、範囲外は補正しない。
    /// 丸め順を保つため、Float64で残す割合を求めてからFloat32へ変える。
    pub def darken(color: Color, amount: Float64): Color =
        let remaining = Float64.truncateToFloat32(1.0 - amount);
        { r = color#r * remaining,
          g = color#g * remaining,
          b = color#b * remaining }

    /// 暖色（黄寄り）へ amount だけ寄せる。lighten と対で使う。
    /// 明暗だけで塗ると面が塊に見えるので、光の当たる側は暖色・影の側は寒色へずらす。
    /// 離れて見ると 2 色が混ざり、実際に使った色数より多くの階調があるように見える。
    pub def warm(color: Color, amount: Float64): Color =
        let t = Float64.truncateToFloat32(amount);
        { r = pin01(color#r + t * 0.30f32),
          g = pin01(color#g + t * 0.18f32),
          b = pin01(color#b - t * 0.14f32) }

    /// 寒色（青寄り）へ amount だけ寄せる（warm の対）。影の側に使う。
    pub def cool(color: Color, amount: Float64): Color =
        let t = Float64.truncateToFloat32(amount);
        { r = pin01(color#r - t * 0.18f32),
          g = pin01(color#g - t * 0.06f32),
          b = pin01(color#b + t * 0.16f32) }

    def pin01(v: Float32): Float32 = Float32.max(0.0f32, Float32.min(1.0f32, v))

    /// 目に映る明るさ（0〜1）。3 チャンネルの平均で採らないのは、人の目が緑にいちばん
    /// 敏感だから — 平均だと同じ数字の赤と緑が違う明るさに見える。緑だけ倍に数える。
    /// 「明るいところだけ / 暗いところだけを拾う」判断に使う（映り込み・しきい処理）。
    pub def brightness(color: Color): Float64 =
        (Float32.toFloat64(color#r) + Float32.toFloat64(color#g) * 2.0
            + Float32.toFloat64(color#b)) / 4.0

    /// HSV から色を作る。h は色相（1 周 = 1.0・0 = 赤・範囲外は折り返し）、s は鮮やかさ、
    /// v は明るさ（どちらも 0〜1）。「値に沿って色相を流す」（虹のグラデーション・
    /// 残量ゲージの緑→赤）が 1 行で導ける。
    /// 同型の Float64 が並ぶので、取り違え防止にレコードで名前渡しする。
    pub def hsv(spec: {h = Float64, s = Float64, v = Float64}): Color =
        let h6 = (spec#h - Float64.floor(spec#h)) * 6.0;
        let f = h6 - Float64.floor(h6);
        let p = spec#v * (1.0 - spec#s);
        let q = spec#v * (1.0 - spec#s * f);
        let u = spec#v * (1.0 - spec#s * (1.0 - f));
        let (r, g, b) =
            if (h6 < 1.0) (spec#v, u, p)
            else if (h6 < 2.0) (q, spec#v, p)
            else if (h6 < 3.0) (p, spec#v, u)
            else if (h6 < 4.0) (p, q, spec#v)
            else if (h6 < 5.0) (u, p, spec#v)
            else (spec#v, p, q);
        { r = clamp01(r), g = clamp01(g), b = clamp01(b) }

    /// GL に渡せる 0〜1 の Float32 へ収める。
    def clamp01(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)
}
