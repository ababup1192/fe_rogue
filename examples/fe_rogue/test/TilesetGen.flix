// TilesetGen — 手続きタイルセット生成器 v1（純粋・決定論）。
//
// tileset_dungeon_green.png と同一レイアウト（26px セル × 12 列 × 9 行）のテーマ別アトラスを
// 「役割テンプレ × 材質生成器 × テーマ（材質割当 + パレット + 風化）」の直交分解で 1 ピクセルずつ
// 導出する。原本の各セルの役割（壁天端・壁面・床・水）を保ち、座標互換を守る。
//
// 設計:
//   - 役割（Role）は「どの辺が露出し、どこに縁が来るか」の幾何。cellRole が (col,row) → Role。
//     原本で塗り面積が薄いセル（蜘蛛の巣 / 骨 / 扉 / 柵 など装飾）は None ＝ 透明のまま残す
//     （マップから参照されない＝ゲーム非依存。装飾のテーマ変換は v2 送り）。
//   - 材質生成器は「名前つきノブ」を持つ純関数: brick（course/brickW/mortar/jitter）・
//     flagstone（大判目地）・sand（風化粒）・water（ripple/縁光）。ゆらぎは hash01（セル座標 seed・決定論）。
//   - テーマ = パレット + 風化（CrackGlow=火の粉のひび / Moss=苔 / Crumble=崩れ）+ 水の別材質（溶岩など）。
//
// 出力ピクセルは packed ARGB Int32（上位バイト alpha、0 ＝ 透明）。焼き出しは TilesetGallery（@Test/IO）。
mod TilesetGen {

    // ── アトラス寸法（原本と同一・厳守）──
    pub def cell(): Int32 = 26
    pub def cols(): Int32 = 12
    pub def rows(): Int32 = 9
    pub def atlasW(): Int32 = cell() * cols()   // 312
    pub def atlasH(): Int32 = cell() * rows()   // 234

    // ════════════════════════════════════════════════════════
    // パレット・ノブ・テーマ
    // ════════════════════════════════════════════════════════

    /// 5 段の明度ランプ + アクセント。各色は 0xRRGGBB（DB32 由来）。
    pub type alias Pal = {
        shadow = Int32, dark = Int32, mid = Int32, light = Int32, hi = Int32, accent = Int32
    }

    /// 風化オーバーレイの種別（テーマの表情）。
    pub enum Weather { case CrackGlow, case Moss, case Crumble }

    /// 床材質の種別。
    pub enum FloorKind { case Flagstone, case Sand }

    /// brick（壁）材質のノブ。course=段高 / brickW=レンガ幅 / mortar=目地幅 / jitter=個体明度ゆらぎ。
    pub type alias WallKnobs = {
        pal = Pal, course = Int32, brickW = Int32, mortar = Int32, jitter = Float64, weather = Weather
    }

    /// 床材質のノブ。kind=材質 / cellSize=目地間隔 / jitter=ゆらぎ。
    pub type alias FloorKnobs = { pal = Pal, kind = FloorKind, cellSize = Int32, jitter = Float64 }

    /// 水材質のノブ。ripple=うねりの強さ / glow>0 ＝ 溶岩（縁光をアクセントで灯す）/ framePal=石枠。
    pub type alias WaterKnobs = { pal = Pal, framePal = Pal, ripple = Float64, glow = Float64 }

    /// テーマ = 材質割当（壁 / 床 / 水）の束。パレットと風化ノブがテーマの個性。
    pub type alias Theme = { name = String, wall = WallKnobs, floor = FloorKnobs, water = WaterKnobs }

    // ── テーマ: 炎（黒い玄武岩 + 溶岩 + 火の粉のひび）──
    pub def fire(): Theme = {
        name = "fire",
        wall = { pal = { shadow = 0x0c0a0e, dark = 0x1b181f, mid = 0x2c2733, light = 0x413b49,
                         hi = 0x585262, accent = 0xe0621c },
                 course = 7, brickW = 13, mortar = 2, jitter = 0.5, weather = Weather.CrackGlow },
        floor = { pal = { shadow = 0x140f10, dark = 0x241a19, mid = 0x352625, light = 0x483433,
                          hi = 0x5c4442, accent = 0xff7b28 },
                  kind = FloorKind.Flagstone, cellSize = 13, jitter = 0.4 },
        water = { pal = { shadow = 0x2a1206, dark = 0x5e2408, mid = 0xb0400d, light = 0xff7b1e,
                          hi = 0xffd23b, accent = 0xffe98a },
                  framePal = { shadow = 0x0c0a0e, dark = 0x1b181f, mid = 0x2c2733, light = 0x413b49,
                               hi = 0x585262, accent = 0xe0621c },
                  ripple = 0.7, glow = 1.0 }
    }

    // ── テーマ: 森（苔むした石 + 澄んだ水 + 蔓）──
    pub def forest(): Theme = {
        name = "forest",
        wall = { pal = { shadow = 0x1a221c, dark = 0x2a352c, mid = 0x3a4a3c, light = 0x51654f,
                         hi = 0x6d8369, accent = 0x4f8a2c },
                 course = 7, brickW = 13, mortar = 2, jitter = 0.45, weather = Weather.Moss },
        floor = { pal = { shadow = 0x1c261f, dark = 0x2c3a2e, mid = 0x3c4d3d, light = 0x51664f,
                          hi = 0x66805f, accent = 0x5a9a34 },
                  kind = FloorKind.Flagstone, cellSize = 13, jitter = 0.4 },
        water = { pal = { shadow = 0x123038, dark = 0x1c4a54, mid = 0x2f7c88, light = 0x63b6c6,
                          hi = 0xc6ecf1, accent = 0xe8ffff },
                  framePal = { shadow = 0x1a221c, dark = 0x2a352c, mid = 0x3a4a3c, light = 0x51654f,
                               hi = 0x6d8369, accent = 0x4f8a2c },
                  ripple = 0.55, glow = 0.0 }
    }

    // ── テーマ: 古代遺跡（砂岩 + 崩れ + 砂だまり）──
    pub def ruins(): Theme = {
        name = "ruins",
        wall = { pal = { shadow = 0x453520, dark = 0x67512f, mid = 0x896f46, light = 0xa88a58,
                         hi = 0xc9ad78, accent = 0x5f4a2a },
                 course = 8, brickW = 13, mortar = 3, jitter = 0.5, weather = Weather.Crumble },
        floor = { pal = { shadow = 0x6b5636, dark = 0x8a7046, mid = 0xa88a5a, light = 0xc4a670,
                          hi = 0xdcc48c, accent = 0x9a7d4c },
                  kind = FloorKind.Sand, cellSize = 13, jitter = 0.35 },
        water = { pal = { shadow = 0x2c3a30, dark = 0x3e5344, mid = 0x5a7a5f, light = 0x86a884,
                          hi = 0xc0d6b6, accent = 0xdce8c8 },
                  framePal = { shadow = 0x453520, dark = 0x67512f, mid = 0x896f46, light = 0xa88a58,
                               hi = 0xc9ad78, accent = 0x5f4a2a },
                  ripple = 0.3, glow = 0.0 }
    }

    /// 全テーマ（ギャラリー / 報告で反復する）。
    pub def themes(): List[Theme] = fire() :: forest() :: ruins() :: Nil

    // ════════════════════════════════════════════════════════
    // 役割（Role）と原本レイアウトの台帳
    // ════════════════════════════════════════════════════════

    /// セルの役割。Water は露出辺（top,bottom,left,right）＝ 石枠の掛かる側を持つ。
    pub enum Role { case WallTop, case WallFace, case Floor, case Water(Bool, Bool, Bool, Bool) }

    /// 原本で「塗り面積が厚い（cov≥85%）構造セル」の集合。原本 PNG の 26px 格子を実測した台帳。
    /// ここに無いセル（装飾・疎なセル）は透明のまま。
    def solid(col: Int32, row: Int32): Bool =
        if (row >= 0 and row <= 3) col >= 0 and col <= 11        // 壁天端 + 壁面（全列）
        else if (row == 4)         col >= 0 and col <= 6          // 壁面（右側は装飾で薄い）
        else if (row == 5)         col >= 0 and col <= 11         // 床帯
        else if (row == 6)         col >= 0 and col <= 11         // 水プール上端 + 床
        else if (row == 7)         (col >= 0 and col <= 2) or (col >= 9 and col <= 11)  // プール中 + 横水盤
        else if (row == 8)         col >= 0 and col <= 2          // 水プール下端
        else false

    /// (col,row) → Role。solid でなければ None（透明）。
    /// 領域規則: row0=壁天端 / row1-4=壁面 / row5=床 / row6 左3列=水上端・他=床 /
    /// row7 左3列=水プール中・右3列=横水盤 / row8 左3列=水プール下端。
    pub def cellRole(col: Int32, row: Int32): Option[Role] =
        if (not solid(col, row)) None
        else if (row == 0) Some(Role.WallTop)
        else if (row >= 1 and row <= 4) Some(Role.WallFace)
        else if (row == 5) Some(Role.Floor)
        else if (row == 6)
            if (col <= 2) Some(poolCell(col, row)) else Some(Role.Floor)
        else if (row == 7)
            if (col <= 2) Some(poolCell(col, row)) else Some(troughCell(col))
        else if (row == 8) Some(poolCell(col, row))
        else None

    /// 3×3 水プール（rows6-8 × cols0-2）内セルの露出辺。外周に石枠が掛かる。
    def poolCell(col: Int32, row: Int32): Role =
        Role.Water(row == 6, row == 8, col == 0, col == 2)

    /// 横長水盤（row7 × cols9-11）。上下は常に枠、左右は端のみ。
    def troughCell(col: Int32): Role =
        Role.Water(true, true, col == 9, col == 11)

    // ════════════════════════════════════════════════════════
    // 決定論ノイズ（hash01）と色ユーティリティ
    // ════════════════════════════════════════════════════════

    /// 3 入力の整数ハッシュ（Int32 乗算は JVM と同じくラップする）。
    def hashI(a: Int32, b: Int32, s: Int32): Int32 =
        let h1 = (a * 374761393) + (b * 668265263) + (s * 1013904223);
        let h2 = h1 * (h1 + 30011);
        h2 * (h2 + 19937)

    /// hash01: 決定論の [0,1) 疑似乱数。セル座標や brick 番号を seed にする。
    /// Int32.modulo は正の除数で常に非負を返すので符号補正は不要。
    pub def hash01(a: Int32, b: Int32, s: Int32): Float64 =
        Int32.toFloat64(Int32.modulo(hashI(a, b, s), 100003)) / 100003.0

    /// 0xRRGGBB → (r,g,b)。
    def rgbOf(hex: Int32): (Int32, Int32, Int32) =
        (Int32.modulo(hex / 65536, 256), Int32.modulo(hex / 256, 256), Int32.modulo(hex, 256))

    /// 2 色を t で線形補間。
    def lerpHex(c1: Int32, c2: Int32, t: Float64): (Int32, Int32, Int32) =
        let (r1, g1, b1) = rgbOf(c1);
        let (r2, g2, b2) = rgbOf(c2);
        let l = (a, b) -> a + ri((Int32.toFloat64(b) - Int32.toFloat64(a)) * clamp01(t));
        (l(r1, r2), l(g1, g2), l(b1, b2))

    /// (r,g,b) の明度を係数 f で調整（1.0 = 変化なし）。
    def shade(c: (Int32, Int32, Int32), f: Float64): (Int32, Int32, Int32) =
        let (r, g, b) = c;
        (clampB(ri(Int32.toFloat64(r) * f)), clampB(ri(Int32.toFloat64(g) * f)), clampB(ri(Int32.toFloat64(b) * f)))

    /// alpha と (r,g,b) を packed ARGB Int32 へ（乗算はラップし setRGB 用の符号付き int になる）。
    pub def packArgb(a: Int32, c: (Int32, Int32, Int32)): Int32 =
        let (r, g, b) = c;
        (a * 16777216) + (r * 65536) + (g * 256) + b

    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))
    def clampB(v: Int32): Int32 = Int32.max(0, Int32.min(255, v))
    def ri(x: Float64): Int32 = Float64.tryToInt32(x + 0.5) |> Option.getWithDefault(0)
    def frac(x: Float64): Float64 = x - Float64.floor(x)
    /// 三角波（0..1..0）。うねり・縞に使う。
    def tri(x: Float64): Float64 = Float64.abs(frac(x * 0.5) * 2.0 - 1.0)

    // ════════════════════════════════════════════════════════
    // ピクセル導出（役割 → 材質生成器）
    // ════════════════════════════════════════════════════════

    /// (col,row,lx,ly) の出力 ARGB。透明は 0。lx,ly はセル内ローカル px（0..25）。
    pub def pixelArgb(theme: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32): Int32 =
        match cellRole(col, row) {
            case None       => 0
            case Some(role) =>
                let gx = col * cell() + lx;
                let gy = row * cell() + ly;
                match role {
                    case Role.WallTop           => packArgb(255, wallTopPx(theme#wall, gx, gy, ly))
                    case Role.WallFace          => packArgb(255, brickPx(theme#wall, gx, gy))
                    case Role.Floor             => packArgb(255, floorPx(theme#floor, gx, gy))
                    case Role.Water(t, b, l, r) => waterPx(theme#water, gx, gy, lx, ly, t, b, l, r)
                }
        }

    // ── 材質生成器: brick（壁面）──
    // 段（course）ごとに半レンガずらし、目地（mortar）を影色で刻む。レンガ毎に hash01 で明度ゆらぎ、
    // 上端をベベルで明るく・下端を影に。weather がテーマの表情（ひび光 / 苔 / 崩れ）を足す。
    def brickPx(k: WallKnobs, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let course = k#course;
        let brickRow = gy / course;
        let yInRow = Int32.modulo(gy, course);
        let offset = Int32.modulo(brickRow, 2) * (k#brickW / 2);
        let bx = gx + offset;
        let brickCol = bx / k#brickW;
        let xInBrick = Int32.modulo(bx, k#brickW);
        let onMortar = xInBrick < k#mortar or yInRow < k#mortar;
        if (onMortar)
            mortarColor(k, brickCol, brickRow, gx, gy)
        else {
            // レンガ本体: 個体明度ゆらぎ + 縦ベベル（上明・下暗）。
            let j = hash01(brickCol, brickRow, 7);
            let base = lerpHex(k#pal#dark, k#pal#light, 0.35 + j * k#jitter);
            let bevel =
                if (yInRow <= k#mortar + 1) 1.22
                else if (yInRow >= course - 2) 0.78
                else 1.0;
            let speck = 1.0 + (hash01(gx, gy, 13) - 0.5) * 0.12;
            weatherBody(k, brickCol, brickRow, gx, gy, shade(base, bevel * speck))
        }

    /// 目地色。CrackGlow テーマは一部の目地を火の粉色に灯す。
    def mortarColor(k: WallKnobs, bcol: Int32, brow: Int32, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        match k#weather {
            case Weather.CrackGlow =>
                let g = hash01(bcol, brow, 29);
                if (g > 0.72) lerpHex(k#pal#accent, k#pal#hi, hash01(gx, gy, 31) * 0.5)
                else rgbOf(k#pal#shadow)
            case _ => rgbOf(k#pal#shadow)
        }

    /// レンガ本体への風化オーバーレイ。
    def weatherBody(k: WallKnobs, _bcol: Int32, brow: Int32, gx: Int32, gy: Int32,
                    c: (Int32, Int32, Int32)): (Int32, Int32, Int32) =
        match k#weather {
            case Weather.Moss =>
                // 下段ほど苔が乗る（重力方向）。斑に accent 緑を混ぜる。
                let m = hash01(gx / 2, gy / 2, 41);
                let bias = 0.35 + Int32.toFloat64(Int32.modulo(brow, 4)) * 0.12;
                if (m < bias * 0.5) lerpHex(packOf(c), k#pal#accent, 0.35 + m)
                else c
            case Weather.Crumble =>
                // 砂岩の欠け: 斑に影を落として風化を出す。
                let m = hash01(gx, gy, 43);
                if (m > 0.86) shade(c, 0.7) else c
            case Weather.CrackGlow =>
                // 玄武岩の残り火: ごく稀に本体へ暗い赤熱点。
                let m = hash01(gx, gy, 47);
                if (m > 0.95) lerpHex(packOf(c), k#pal#accent, 0.3) else c
        }

    /// (r,g,b) を 0xRRGGBB へ戻す（lerpHex の第 1 引数に本体色を渡すため）。
    def packOf(c: (Int32, Int32, Int32)): Int32 =
        let (r, g, b) = c;
        (r * 65536) + (g * 256) + b

    // ── 役割: 壁天端（壁面 + 上端に丸石のレール）──
    def wallTopPx(k: WallKnobs, gx: Int32, gy: Int32, ly: Int32): (Int32, Int32, Int32) =
        let capH = 8;
        if (ly >= capH)
            brickPx(k, gx, gy)
        else {
            // 上端レール: 幅 brickW 単位の丸石。中央を明るく・縁を影に（丸みの陰影）。
            let sx = Int32.modulo(gx, k#brickW);
            let t = Int32.toFloat64(sx) / Int32.toFloat64(k#brickW);   // 0..1 石の横位置
            let round = 1.0 - Float64.abs(t - 0.5) * 1.4;              // 中央 1.0 → 縁 負
            let topFade = Int32.toFloat64(ly) / Int32.toFloat64(capH);  // 上ほど明るい天面
            let j = hash01(gx / k#brickW, 0, 53);
            let baseCol = lerpHex(k#pal#mid, k#pal#hi, 0.4 + j * 0.3);
            if (round < 0.0 or ly >= capH - 1)
                rgbOf(k#pal#shadow)                                     // 石の間の溝・下端の影
            else
                shade(baseCol, 0.7 + round * 0.4 + (1.0 - topFade) * 0.2)
        }

    // ── 材質生成器: 床（Flagstone 大判目地 / Sand 風化粒）──
    def floorPx(k: FloorKnobs, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        match k#kind {
            case FloorKind.Flagstone =>
                let cs = k#cellSize;
                let cx = gx / cs;
                let cy = gy / cs;
                let onSeam = Int32.modulo(gx, cs) == 0 or Int32.modulo(gy, cs) == 0;
                if (onSeam) rgbOf(k#pal#shadow)
                else {
                    let j = hash01(cx, cy, 61);
                    let speck = 1.0 + (hash01(gx, gy, 67) - 0.5) * 0.14;
                    shade(lerpHex(k#pal#dark, k#pal#light, 0.3 + j * k#jitter), speck)
                }
            case FloorKind.Sand =>
                // なめらかな砂 + 風化粒 + 緩い砂だまりの筋。
                let dune = tri((Int32.toFloat64(gx) + Int32.toFloat64(gy) * 0.3) / 9.0) * 0.25;
                let grain = (hash01(gx, gy, 71) - 0.5) * 0.18;
                shade(lerpHex(k#pal#dark, k#pal#hi, 0.45 + dune + grain), 1.0)
        }

    // ── 材質生成器: 水（ripple 縞 + 上縁ハイライト / glow>0 で溶岩）+ 石枠 ──
    def waterPx(k: WaterKnobs, gx: Int32, gy: Int32, lx: Int32, ly: Int32,
                top: Bool, bot: Bool, left: Bool, right: Bool): Int32 =
        let frameW = 4;
        let c = cell();
        let onFrame =
            (top and ly < frameW) or (bot and ly >= c - frameW)
                or (left and lx < frameW) or (right and lx >= c - frameW);
        if (onFrame)
            packArgb(255, framePx(k#framePal, gx, gy, lx, ly, top, bot, left, right, frameW))
        else if (k#glow > 0.0)
            packArgb(255, lavaPx(k, gx, gy))
        else
            packArgb(255, liquidPx(k, gx, gy, ly, top, frameW))

    /// 澄んだ水: 横方向の ripple 縞と、上縁近くの白いハイライト帯。
    def liquidPx(k: WaterKnobs, gx: Int32, gy: Int32, ly: Int32, top: Bool, frameW: Int32): (Int32, Int32, Int32) =
        let streak = tri((Int32.toFloat64(gx) * 0.7 + Int32.toFloat64(gy) * 2.3
                          + hash01(0, gy, 83) * 6.0) / 7.0);
        let base = lerpHex(k#pal#dark, k#pal#light, 0.3 + streak * k#ripple);
        // 上縁のすぐ内側に明るい水縁。
        let nearTop = top and ly >= frameW and ly < frameW + 3;
        if (nearTop) lerpHex(packOf(base), k#pal#hi, 0.6)
        else if (hash01(gx, gy, 89) > 0.965) rgbOf(k#pal#hi)   // まばらなきらめき
        else base

    /// 溶岩: 暗い外殻に、hash で走る明るい割れ目（accent の縁光）。
    def lavaPx(k: WaterKnobs, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let crust = lerpHex(k#pal#shadow, k#pal#dark, hash01(gx / 3, gy / 3, 97));
        let vein = tri((Int32.toFloat64(gx) + hash01(0, gy / 2, 101) * 12.0) / 6.0);
        if (vein > 0.82)
            lerpHex(k#pal#light, k#pal#hi, hash01(gx, gy, 103))
        else if (vein > 0.7)
            rgbOf(k#pal#mid)
        else crust

    /// 石枠: 外周に丸石の縁石。角は影を強め、内側に一段暗いリップ。
    def framePx(pal: Pal, gx: Int32, gy: Int32, lx: Int32, ly: Int32,
                top: Bool, bot: Bool, left: Bool, right: Bool, frameW: Int32): (Int32, Int32, Int32) =
        let c = cell();
        // 内リップ（水に接する 1px）を影に。
        let innerLip =
            (top and ly == frameW - 1) or (bot and ly == c - frameW)
                or (left and lx == frameW - 1) or (right and lx == c - frameW);
        if (innerLip) rgbOf(pal#shadow)
        else {
            let j = hash01(gx / 5, gy / 5, 109);
            let speck = 1.0 + (hash01(gx, gy, 113) - 0.5) * 0.15;
            shade(lerpHex(pal#dark, pal#hi, 0.35 + j * 0.4), speck)
        }
}
