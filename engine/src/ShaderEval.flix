// ShaderEval — Spec 木を CPU（Float64）で評価する検証用の純関数。描画経路ではない。
// テスト（代表点 (u,v,t) の値を釘打ち）と、将来のプレビューのために使う。
// GPU と byte 一致させる義務はない（Hash は近似で可）が、式の構造は ShaderGen と同じにして
// 「数式の正気」を確かめる（網目が目地で立つ・スクロールで動く・パレットが回る、など）。

mod ShaderEval {

    /// 代表点 uv（0..1 目安）と時刻 t の最終色（Color = 0..1 の Float32 rgb）。
    pub def evalPixel(spec: ShaderDoc.Spec, uv: Vec2.Vec2, t: Float64): Color =
        match spec#out {
            case ShaderDoc.Out.Fill(f) => evalShade(spec#cycleRate, f#shade, uv, t)
        }

    /// 代表点のアルファ（Fill#alpha の場を評価）。
    pub def evalAlpha(spec: ShaderDoc.Spec, uv: Vec2.Vec2, t: Float64): Float64 =
        match spec#out {
            case ShaderDoc.Out.Fill(f) => evalField(f#alpha, uv, t)
        }

    def evalShade(cycleRate: Float64, shade: ShaderDoc.Shade, uv: Vec2.Vec2, t: Float64): Color =
        match shade {
            case ShaderDoc.Shade.Solid(c) => c
            case ShaderDoc.Shade.Ramp(r)  =>
                let phase = clamp01(triWave(evalField(r#field, uv, t) + cycleRate * t));
                mixColor(r#lo, r#hi, phase)
        }

    /// 場を Float64 へ。uv は「今読むべき座標」（Scaled/Warp が差し替える）。
    pub def evalField(field: ShaderDoc.Field, uv: Vec2.Vec2, t: Float64): Float64 =
        match field {
            case ShaderDoc.Field.Const(v) => v
            case ShaderDoc.Field.Uv(u)    =>
                match u#axis {
                    case ShaderDoc.Axis.U => uv#x
                    case ShaderDoc.Axis.V => uv#y
                }
            case ShaderDoc.Field.Worley(w) =>
                let (f1, f2) = worleyF1F2(Vec2.mul(uv, w#scale), Int32.toFloat64(w#seed));
                match w#out {
                    case ShaderDoc.WorleyOut.F1    => f1
                    case ShaderDoc.WorleyOut.F2    => f2
                    case ShaderDoc.WorleyOut.F2mF1 => f2 - f1
                }
            case ShaderDoc.Field.Fbm(b) =>
                fbm(Vec2.mul(uv, b#scale), b#octaves, Int32.toFloat64(b#seed))
            case ShaderDoc.Field.Smoothstep(s) =>
                smoothstep(s#lo, s#hi, evalField(s#of, uv, t))
            case ShaderDoc.Field.Scaled(s) =>
                let uv2 = Vec2.add(Vec2.mul(uv, s#factor), Vec2.mul(s#scroll, t));
                evalField(s#of, uv2, t)
            case ShaderDoc.Field.Warp(wp) =>
                let ox = fbm(Vec2.mul(uv, wp#scale), 3, Int32.toFloat64(wp#seed)) - 0.5;
                let oy = fbm(Vec2.mul(uv, wp#scale), 3, Int32.toFloat64(wp#seed) + 91.0) - 0.5;
                let uv2 = Vec2.add(uv, Vec2.mul({ x = ox, y = oy }, wp#amount));
                evalField(wp#of, uv2, t)
            case ShaderDoc.Field.Mix(m) =>
                lerp(evalField(m#a, uv, t), evalField(m#b, uv, t), m#t)
            case ShaderDoc.Field.Blend(bl) =>
                lerp(evalField(bl#a, uv, t), evalField(bl#b, uv, t),
                     clamp01(evalField(bl#by, uv, t)))
            case ShaderDoc.Field.Disk(d) =>
                let dist = Vec2.length(Vec2.sub(uv, { x = d#cx, y = d#cy }));
                1.0 - smoothstep(d#radius, d#radius + d#feather, dist)
        }

    // ── ノイズの CPU 版（GLSL prelude と同じ構造・byte 一致は狙わない）──

    def hash1(p: Vec2.Vec2, seed: Float64): Float64 =
        fract(Vec2.sin(p#x * 127.1 + p#y * 311.7 + seed * 0.017) * 43758.5453123)

    def hash2(p: Vec2.Vec2, seed: Float64): Vec2.Vec2 =
        { x = hash1(p, seed), y = hash1(Vec2.add(p, { x = 19.19, y = 7.31 }), seed) }

    def worleyF1F2(p: Vec2.Vec2, seed: Float64): (Float64, Float64) =
        let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
        let fp = { x = fract(p#x), y = fract(p#y) };
        // 近傍 3x3 セルを走査して最近 F1・次近 F2 を求める。
        List.foldLeft((acc, cell) -> {
            let (f1, f2) = acc;
            let (i, j) = cell;
            let g = { x = Int32.toFloat64(i), y = Int32.toFloat64(j) };
            let o = hash2(Vec2.add(ip, g), seed);
            let r = Vec2.sub(Vec2.add(g, o), fp);
            let d = Vec2.length(r);
            if (d < f1) (d, f1)
            else if (d < f2) (f1, d)
            else (f1, f2)
        }, (8.0, 8.0), neighborCells())

    def neighborCells(): List[(Int32, Int32)] =
        (-1, -1) :: (0, -1) :: (1, -1) ::
        (-1,  0) :: (0,  0) :: (1,  0) ::
        (-1,  1) :: (0,  1) :: (1,  1) :: Nil

    def valueNoise(p: Vec2.Vec2, seed: Float64): Float64 =
        let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
        let fx = fract(p#x);
        let fy = fract(p#y);
        let wx = fx * fx * (3.0 - 2.0 * fx);
        let wy = fy * fy * (3.0 - 2.0 * fy);
        let a = hash1(ip, seed);
        let b = hash1(Vec2.add(ip, { x = 1.0, y = 0.0 }), seed);
        let c = hash1(Vec2.add(ip, { x = 0.0, y = 1.0 }), seed);
        let d = hash1(Vec2.add(ip, { x = 1.0, y = 1.0 }), seed);
        lerp(lerp(a, b, wx), lerp(c, d, wx), wy)

    def fbm(p: Vec2.Vec2, octaves: Int32, seed: Float64): Float64 =
        List.foldLeft((acc, i) -> {
            let (sum, amp, freq) = acc;
            let s = sum + amp * valueNoise(Vec2.mul(p, freq), seed + Int32.toFloat64(i) * 13.0);
            (s, amp * 0.5, freq * 2.0)
        }, (0.0, 0.5, 1.0), List.range(0, Int32.max(0, octaves))) |> fst3

    // ── 小道具 ──

    def fst3(t: (Float64, Float64, Float64)): Float64 = let (a, _, _) = t; a

    def fract(x: Float64): Float64 = x - Float64.floor(x)

    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))

    def lerp(a: Float64, b: Float64, t: Float64): Float64 = a + (b - a) * t

    /// 0..1 を三角波（0→1→0）に折り返す（GLSL の abs(fract(x)*2-1) と同じ）。
    def triWave(x: Float64): Float64 = Float64.abs(fract(x) * 2.0 - 1.0)

    def smoothstep(lo: Float64, hi: Float64, x: Float64): Float64 =
        if (hi - lo == 0.0) (if (x < lo) 0.0 else 1.0)
        else {
            let tt = clamp01((x - lo) / (hi - lo));
            tt * tt * (3.0 - 2.0 * tt)
        }

    def mixColor(a: Color, b: Color, t: Float64): Color =
        let tf = Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, t);
        { r = a#r + (b#r - a#r) * tf,
          g = a#g + (b#g - a#g) * tf,
          b = a#b + (b#b - a#b) * tf }
}
