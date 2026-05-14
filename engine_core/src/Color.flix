// Color — 3 チャンネル sRGB-linear カラー (alpha は別途持つ運用)
//
// Float32 ベース。GL の uniform に直接渡せるレンジ 0.0〜1.0。
// engine_core に置くことで render_core と engine が共有する。
//
// 元の定義は engine/src/scene/CanvasItem.flix の line 1 にあったが、
// render_core からも参照する必要があるため engine_core に移動した。

pub type alias Color = {r = Float32, g = Float32, b = Float32}
