// ShaderEval — Spec 木を CPU（Float64）で評価する検証用の純関数。描画経路ではない。
// テスト（代表点 (u,v,t) の値を釘打ち）と、将来のプレビューのために使う。
// GPU と byte 一致させる義務はない（Hash は近似で可）が、式の構造は ShaderGen と同じにして
// 「数式の正気」を確かめる（網目が目地で立つ・スクロールで動く・パレットが回る、など）。

mod ShaderEval {

    /// 代表点 uv（0..1 目安）と時刻 t の最終色（Color = 0..1 の Float32 rgb）。
    pub def evalPixel(spec: ShaderDoc.Spec, uv: Vec2.Vec2, t: Float64): Color =
        match spec#out {
            case ShaderDoc.Out.Fill(f) => evalShade(spec#cycleRate, f#shade, uv, t, envOf(spec#bindings))
        }

    /// 代表点のアルファ（Fill#alpha の場を評価）。
    pub def evalAlpha(spec: ShaderDoc.Spec, uv: Vec2.Vec2, t: Float64): Float64 =
        match spec#out {
            case ShaderDoc.Out.Fill(f) => evalFieldEnv(f#alpha, uv, t, envOf(spec#bindings))
        }

    /// bindings（前から順）を名前→場の env に畳む。前の binding だけが後の binding から Ref できる。
    def envOf(bindings: List[(String, ShaderDoc.Field)]): Map[String, ShaderDoc.Field] =
        List.foldLeft((env, nf) -> {
            let (name, field) = nf;
            Map.insert(name, field, env)
        }, Map.empty(), bindings)

    def evalShade(cycleRate: Float64, shade: ShaderDoc.Shade, uv: Vec2.Vec2, t: Float64,
                  env: Map[String, ShaderDoc.Field]): Color =
        match shade {
            case ShaderDoc.Shade.Solid(c) => c
            case ShaderDoc.Shade.Ramp(r)  =>
                // cycleRate = 0 は素直な補間。cycleRate>0 だけ三角波で往復（パレット循環）。
                let field = evalFieldEnv(r#field, uv, t, env);
                let phase = if (cycleRate == 0.0) clamp01(field)
                            else clamp01(triWave(field + cycleRate * t));
                mixColor(r#lo, r#hi, phase)
            case ShaderDoc.Shade.Gradient(g) =>
                // GLSL と同じ数式でなぞる: 係数 f を Ramp と同じ規約で作り、
                // 先頭色から隣の区切りごとに smoothstep 重みで次の色へ寄せる。
                let field = evalFieldEnv(g#field, uv, t, env);
                let f = if (cycleRate == 0.0) clamp01(field)
                        else clamp01(triWave(field + cycleRate * t));
                gradientColor(f, g#stops)
            case ShaderDoc.Shade.Cosine(cs) =>
                let field = evalFieldEnv(cs#field, uv, t, env);
                let tt = if (cycleRate == 0.0) field else field + cycleRate * t;
                cosColor(cs#a, cs#b, cs#c, cs#d, tt)
        }

    /// コサインパレット col = a + b·cos(2π(c·t + d)) を各チャンネルで（ShaderGen の sg_cospal と同じ数式）。
    def cosColor(pa: Color, pb: Color, pc: Color, pd: Color, t: Float64): Color =
        let ch = (av, bv, cv, dv) ->
            colorF32(av + bv * Vec2.cos(6.2831853 * (cv * t + dv)));
        { r = ch(colorF64(pa#r), colorF64(pb#r), colorF64(pc#r), colorF64(pd#r)),
          g = ch(colorF64(pa#g), colorF64(pb#g), colorF64(pc#g), colorF64(pd#g)),
          b = ch(colorF64(pa#b), colorF64(pb#b), colorF64(pc#b), colorF64(pd#b)) }

    def colorF64(x: Float32): Float64 = Float32.toFloat64(x)
    def colorF32(x: Float64): Float32 = Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)

    /// 係数 f（0..1）で stops を混ぜた色。ShaderGen の gradientExpr と同じ入れ子 mix を辿る。
    def gradientColor(f: Float64, stops: List[(Float64, Color)]): Color =
        match stops {
            case Nil => { r = 0.0f32, g = 0.0f32, b = 0.0f32 }
            case (_, c0) :: rest =>
                let (col, _) = List.foldLeft((acc, sc) -> {
                    let (curCol, prevPos) = acc;
                    let (pos, col) = sc;
                    let w = smoothstep(prevPos, pos, f);
                    (mixColor(curCol, col, w), pos)
                }, (c0, gradientFirstPos(stops)), rest);
                col
        }

    def gradientFirstPos(stops: List[(Float64, Color)]): Float64 =
        match stops {
            case (p, _) :: _ => p
            case Nil         => 0.0
        }

    /// 場を Float64 へ。uv は「今読むべき座標」（Scaled/Warp が差し替える）。
    /// public はシグネチャ不変（呼び元を割らない）で、内部の env 版に空 env で委譲する。
    pub def evalField(field: ShaderDoc.Field, uv: Vec2.Vec2, t: Float64): Float64 =
        evalFieldEnv(field, uv, t, Map.empty())

    /// env 付きの場評価。Ref だけが env を読み、他 case は受けて再帰へ渡すだけ。
    def evalFieldEnv(field: ShaderDoc.Field, uv: Vec2.Vec2, t: Float64,
                     env: Map[String, ShaderDoc.Field]): Float64 =
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
            case ShaderDoc.Field.FbmTile(b) =>
                fbmTile(Vec2.mul(uv, b#scale), b#period, b#octaves, Int32.toFloat64(b#seed))
            case ShaderDoc.Field.Smoothstep(s) =>
                smoothstep(s#lo, s#hi, evalFieldEnv(s#of, uv, t, env))
            case ShaderDoc.Field.Scaled(s) =>
                let uv2 = Vec2.add(Vec2.mul(uv, s#factor), Vec2.mul(s#scroll, t));
                evalFieldEnv(s#of, uv2, t, env)
            case ShaderDoc.Field.Warp(wp) =>
                let ox = fbm(Vec2.mul(uv, wp#scale), 3, Int32.toFloat64(wp#seed)) - 0.5;
                let oy = fbm(Vec2.mul(uv, wp#scale), 3, Int32.toFloat64(wp#seed) + 91.0) - 0.5;
                let uv2 = Vec2.add(uv, Vec2.mul({ x = ox, y = oy }, wp#amount));
                evalFieldEnv(wp#of, uv2, t, env)
            case ShaderDoc.Field.Swirl(sw) =>
                let c = { x = sw#cx, y = sw#cy };
                let p = Vec2.sub(uv, c);
                let r = Vec2.length(p);
                let a = sw#strength / (r + 0.08) + sw#rate * t;
                let co = Vec2.cos(a);
                let s = Vec2.sin(a);
                let uv2 = { x = c#x + p#x * co - p#y * s, y = c#y + p#x * s + p#y * co };
                evalFieldEnv(sw#of, uv2, t, env)
            case ShaderDoc.Field.Angle(an) =>
                Vec2.atan2(uv#y - an#cy, uv#x - an#cx) * 0.15915494 + 0.5
            case ShaderDoc.Field.Rotate(rt) =>
                let c = { x = rt#cx, y = rt#cy };
                let p = Vec2.sub(uv, c);
                let a = 6.2831853 * (rt#turns + rt#rate * t);
                let co = Vec2.cos(a);
                let s = Vec2.sin(a);
                let uv2 = { x = c#x + p#x * co - p#y * s, y = c#y + p#x * s + p#y * co };
                evalFieldEnv(rt#of, uv2, t, env)
            case ShaderDoc.Field.Mix(m) =>
                lerp(evalFieldEnv(m#a, uv, t, env), evalFieldEnv(m#b, uv, t, env), m#t)
            case ShaderDoc.Field.Blend(bl) =>
                lerp(evalFieldEnv(bl#a, uv, t, env), evalFieldEnv(bl#b, uv, t, env),
                     clamp01(evalFieldEnv(bl#by, uv, t, env)))
            case ShaderDoc.Field.Disk(d) =>
                let dist = Vec2.length(Vec2.sub(uv, { x = d#cx, y = d#cy }));
                1.0 - smoothstep(d#radius, d#radius + d#feather, dist)
            case ShaderDoc.Field.Radial(rd) =>
                Vec2.length(Vec2.sub(uv, { x = rd#cx, y = rd#cy }))
            case ShaderDoc.Field.RadialAspect(ra) =>
                Vec2.length({ x = (uv#x - ra#cx) * ra#aspect, y = uv#y - ra#cy })
            case ShaderDoc.Field.Quantize(q) =>
                let n = Int32.toFloat64(Int32.max(1, q#steps));
                Float64.floor(evalFieldEnv(q#of, uv, t, env) * n) / n
            case ShaderDoc.Field.Scales(sc) =>
                let p = Vec2.mul(uv, sc#scale);
                let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
                let best = List.foldLeft((acc, cell) -> {
                    let (i, j) = cell;
                    let cy = ip#y + Int32.toFloat64(j);
                    let stag = (cy - Float64.floor(cy / 2.0) * 2.0) * sc#stagger;
                    let center = { x = ip#x + Int32.toFloat64(i) + 0.5 + stag, y = cy + 0.5 };
                    Float64.min(acc, Vec2.length(Vec2.sub(p, center)))
                }, 8.0, neighborCells());
                clamp01(best)
            case ShaderDoc.Field.Glints(g) =>
                let p = Vec2.mul(uv, g#scale);
                let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
                let fpx = fract(p#x);
                let fpy = fract(p#y);
                let sd = Int32.toFloat64(g#seed);
                let on = if (hash1(ip, sd) >= 1.0 - g#density) 1.0 else 0.0;
                let phase = hash1(ip, sd + 7.0) * 6.2831853;
                let tw = Float64.max(0.0, Vec2.sin(t * g#rate + phase));
                let dash = (1.0 - smoothstep(0.04, 0.10, Float64.abs(fpy - 0.5))) *
                           (1.0 - smoothstep(0.28, 0.46, Float64.abs(fpx - 0.5)));
                on * tw * dash
            case ShaderDoc.Field.Ripples(rp) =>
                let sd = Int32.toFloat64(rp#seed);
                let wob = Vec2.sin(uv#x * 6.2831853 * rp#freq * 0.5 + sd) * rp#amp
                        + Vec2.sin(uv#x * 6.2831853 * rp#freq * 1.3 + sd * 2.7) * rp#amp * 0.4;
                let band = uv#y * rp#freq + wob + t * rp#speed;
                0.5 + 0.5 * Vec2.sin(band * 6.2831853)
            case ShaderDoc.Field.Sparkle(sp) =>
                let p = Vec2.mul(uv, sp#scale);
                let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
                let fp = { x = fract(p#x), y = fract(p#y) };
                let sd = Int32.toFloat64(sp#seed);
                let tt = t * sp#rate + hash1(ip, sd + 3.0) * 6.2831853;
                let cyc = Float64.floor(tt / 6.2831853);
                let ipc = Vec2.add(ip, { x = cyc, y = cyc });
                let on = if (hash1(ipc, sd) >= 1.0 - sp#density) 1.0 else 0.0;
                let s = Float64.max(0.0, Vec2.sin(tt));
                let s4 = (s * s) * (s * s);
                let tw = (s4 * s4) * s4;
                let h = hash2(ipc, sd + 11.0);
                let pos = { x = 0.15 + 0.7 * h#x, y = 0.15 + 0.7 * h#y };
                let d = Float64.abs(fp#x - pos#x) + Float64.abs(fp#y - pos#y);
                let point = 1.0 - smoothstep(0.04, 0.26, d);
                on * tw * point
            case ShaderDoc.Field.Bin(bn) =>
                let a = evalFieldEnv(bn#a, uv, t, env);
                let b = evalFieldEnv(bn#b, uv, t, env);
                match bn#op {
                    case ShaderDoc.BinOp.Add  => a + b
                    case ShaderDoc.BinOp.Sub  => a - b
                    case ShaderDoc.BinOp.Mul  => a * b
                    case ShaderDoc.BinOp.Min  => Float64.min(a, b)
                    case ShaderDoc.BinOp.Max  => Float64.max(a, b)
                    case ShaderDoc.BinOp.Step => if (b >= a) 1.0 else 0.0
                }
            case ShaderDoc.Field.Hash1(h) =>
                hash1(hashCoord(h#scale, h#bucket, uv, t, env), Int32.toFloat64(h#seed))
            case ShaderDoc.Field.Hash2(h) =>
                let v = hash2(hashCoord(h#scale, h#bucket, uv, t, env), Int32.toFloat64(h#seed));
                match h#comp {
                    case ShaderDoc.Axis.U => v#x
                    case ShaderDoc.Axis.V => v#y
                }
            case ShaderDoc.Field.Un(un) =>
                let x = evalFieldEnv(un#of, uv, t, env);
                match un#op {
                    case ShaderDoc.UnOp.Neg      => -x
                    case ShaderDoc.UnOp.Abs      => Float64.abs(x)
                    case ShaderDoc.UnOp.Fract    => fract(x)
                    case ShaderDoc.UnOp.Floor    => Float64.floor(x)
                    case ShaderDoc.UnOp.Sin      => Vec2.sin(x)
                    case ShaderDoc.UnOp.Cos      => Vec2.cos(x)
                    case ShaderDoc.UnOp.Sat      => clamp01(x)
                    case ShaderDoc.UnOp.OneMinus => 1.0 - x
                }
            case ShaderDoc.Field.Pow(pw) =>
                powf(evalFieldEnv(pw#of, uv, t, env), pw#p)
            case ShaderDoc.Field.Time(tm) =>
                t * tm#scale + evalFieldEnv(tm#offset, uv, t, env)
            case ShaderDoc.Field.Tiling(tl) =>
                // 各マス内は fract(uv*tiles)。of をこの座標で読む（GLSL の差し替えと同じ形）。
                let uv2 = { x = fract(uv#x * tl#tiles#x), y = fract(uv#y * tl#tiles#y) };
                evalFieldEnv(tl#of, uv2, t, env)
            case ShaderDoc.Field.Snap(sn) =>
                // GLSL の (floor(uv*cells)+0.5)/cells と同じ形（bake と実機で塊の位置を割らない）。
                let cx = snapCells(sn#cells#x);
                let cy = snapCells(sn#cells#y);
                let uv2 = { x = (Float64.floor(uv#x * cx) + 0.5) / cx,
                            y = (Float64.floor(uv#y * cy) + 0.5) / cy };
                evalFieldEnv(sn#of, uv2, t, env)
            case ShaderDoc.Field.Ref(name) =>
                // parse が定義済みを保証する。未定義は 0.0（保険）。
                match Map.get(name, env) {
                    case Some(f) => evalFieldEnv(f, uv, t, env)
                    case None    => 0.0
                }
        }

    // Pow の CPU 評価。整数指数は反復積（GLSL の powProduct と同じ左結合の並び）で、
    // 非整数のみ Float64.pow を呼ぶ（第 1 引数はレコード）。負の底は 0 で下切り。
    def powf(x: Float64, p: Float64): Float64 =
        let base = Float64.max(0.0, x);
        if (Float64.floor(p) == p)
            powProduct(base, Float64.floor(p))
        else
            Float64.pow({ base = base }, p)

    // Snap の分割数（ShaderGen.snapCells と同じ下切り）。
    def snapCells(c: Float64): Float64 = Float64.max(1.0, c)

    // base を n 回掛ける（n=0 は 1.0）。ShaderGen.powProduct と同じ左からの掛け順。
    def powProduct(base: Float64, n: Float64): Float64 =
        let k = Int32.max(0, Float64.tryToInt32(n) |> Option.getWithDefault(0));
        if (k == 0) 1.0
        else List.foldLeft((acc, _) -> acc * base, base, List.range(1, k))

    // ── ノイズの CPU 版（GLSL prelude と同じ構造・byte 一致は狙わない）──

    // hash に渡すセル座標。floor(uv*scale) に、bucket が有ればその値を両成分へ足す（GLSL の
    // vec2+float 自動配りと同じ）。GLSL の hashCoord と同じ形。
    def hashCoord(scale: Float64, bucket: Option[ShaderDoc.Field], uv: Vec2.Vec2, t: Float64,
                  env: Map[String, ShaderDoc.Field]): Vec2.Vec2 =
        let ip = { x = Float64.floor(uv#x * scale), y = Float64.floor(uv#y * scale) };
        match bucket {
            case None    => ip
            case Some(b) => let bv = evalFieldEnv(b, uv, t, env); Vec2.add(ip, { x = bv, y = bv })
        }

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

    // GLSL の mod と同じ折り返し（結果の符号は m 側・fract と違い任意周期）。
    def gmod(x: Float64, m: Float64): Float64 = x - m * Float64.floor(x / m)

    // 格子点を period で折り返す value noise（GLSL prelude の sg_valueNoiseTile と同じ構造）。
    def valueNoiseTile(p: Vec2.Vec2, period: Vec2.Vec2, seed: Float64): Float64 =
        let ip = { x = Float64.floor(p#x), y = Float64.floor(p#y) };
        let fx = fract(p#x);
        let fy = fract(p#y);
        let wx = fx * fx * (3.0 - 2.0 * fx);
        let wy = fy * fy * (3.0 - 2.0 * fy);
        let wrap = (dx, dy) ->
            ({ x = gmod(ip#x + dx, period#x), y = gmod(ip#y + dy, period#y) }: Vec2.Vec2);
        let a = hash1(wrap(0.0, 0.0), seed);
        let b = hash1(wrap(1.0, 0.0), seed);
        let c = hash1(wrap(0.0, 1.0), seed);
        let d = hash1(wrap(1.0, 1.0), seed);
        lerp(lerp(a, b, wx), lerp(c, d, wx), wy)

    // 周期つき fbm。オクターブごとに period も freq 倍する（sg_fbmTile と同じ構造）。
    def fbmTile(p: Vec2.Vec2, period: Vec2.Vec2, octaves: Int32, seed: Float64): Float64 =
        List.foldLeft((acc, i) -> {
            let (sum, amp, freq) = acc;
            let s = sum + amp * valueNoiseTile(Vec2.mul(p, freq), Vec2.mul(period, freq),
                                               seed + Int32.toFloat64(i) * 13.0);
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
