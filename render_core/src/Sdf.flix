// RenderSdf — 角丸矩形の符号付き距離関数 (SDF)
//
// StyledRect 描画のフラグメントシェーダ (GLSL) と同じ式の Flix 実装。
// GPU 上では直接テストできないため、ここに純関数として切り出して境界値を
// ユニットテストし、シェーダ側はこの式を GLSL に転記する (両者が一致する前提)。
//
// 参考: Inigo Quilez "distance functions" の sdRoundBox。

mod RenderSdf {

    /// 角丸矩形の符号付き距離。
    ///   p  = 矩形中心からのオフセット (px)
    ///   half = 矩形の半サイズ (px)
    ///   r  = 角半径 (px、0 で通常の矩形)
    /// 戻り値: 負=内側 / 0=境界 / 正=外側。
    /// GLSL 転記元:
    ///   vec2 q = abs(p) - half + r;
    ///   return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    pub def roundedBox(px: Float64, py: Float64,
                        halfX: Float64, halfY: Float64, r: Float64): Float64 =
        let qx = Float64.abs(px) - halfX + r;
        let qy = Float64.abs(py) - halfY + r;
        let inner = Float64.min(Float64.max(qx, qy), 0.0);
        let ox = Float64.max(qx, 0.0);
        let oy = Float64.max(qy, 0.0);
        inner + RenderUtil.sqrtF(ox * ox + oy * oy) - r

}
