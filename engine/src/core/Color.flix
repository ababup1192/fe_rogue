// Color — 3 チャンネル sRGB-linear カラー (alpha は別途持つ運用)
//
// Float32 ベース。GL の uniform に直接渡せるレンジ 0.0〜1.0。
// engine（契約層）の共有型なので、フロントのシーングラフとバックエンド（render_gl）が同じ色定義を見る。

pub type alias Color = {r = Float32, g = Float32, b = Float32}
