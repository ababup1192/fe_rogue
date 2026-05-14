// RenderUtil — 数値変換ヘルパー (GL uniform / shader 用)
//
// LwjglLayer.flix の f32 / floatToInt32 / sinF / cosF を移植。

mod RenderUtil {
    import java.lang.Math

    /// Float64 → Float32 (GL uniform 用)
    pub def f32(v: Float64): Float32 =
        Float64.truncateToFloat32(v)

    /// Float64 → Int32 (四捨五入)
    pub def floatToInt32(v: Float64): Int32 =
        Int64.truncateToInt32(unchecked_cast(Math.round(v) as _ \ {}))

    pub def sinF(x: Float64): Float64 =
        unchecked_cast(Math.sin(x) as _ \ {})

    pub def cosF(x: Float64): Float64 =
        unchecked_cast(Math.cos(x) as _ \ {})

}
