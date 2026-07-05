// TilesetGreen — 手続きタイルセット生成器 v6（純粋・決定論・全108セル・固定ランプ量子化・テーマ差替）。
//
// v5 で確立した最低保証（全 108 セルを原本実測の材質辞書でトレースし、シルエット/材質の二重 XOR を
// ワーストセルで assert）の上に、v6 は「パキッと感」とテーマ展開を載せる:
//
//   1. 固定ランプ量子化: 原本はアトラス全体で実測 31 色しかないドット絵。手続き陰影が連続階調の
//      中間色を量産すると少色数規律が崩れて淡くぼやける。よって各材質の出力は 3〜5 段の固定ランプ
//      （目地/最暗 → 影 → 地 → 光 → 最明）に量子化し、連続値（ハッシュ・ドーム）は段の選択にだけ使う。
//      目地・輪郭はランプ最暗段で締める。緑テーマのランプは原本の実測色そのもの。
//   2. テーマ差替（Theme レコード）: 材質領域マップ（形）はテーマ共通、材質ランプだけ差し替える。
//      green=原本実測 / fire=黒玄武岩+溶岩 / forest=苔石+青水 / ruins=砂岩+濁り水。
//      「石で囲われた水」の役割分離により、枠=石系ランプ・中身=液体系ランプが独立に切り替わる。
//
//   形と材質 = tracedMask: (col,row) -> 26×26 材質チャー（原本を材質辞書で分類した実測データ）
//   材質辞書  = classify(argb): 実測 31 色を 虚空/石/水/木/金属/骨/植物 に分類する閾値関数。
//               水際の淡緑（泡）は teal 寄り実測により水へ（蔓の真緑 b-r≤9 とは b-r で分離）。
//
// 出力は packed ARGB Int32。虚空はテーマの虚空色で塗る（透明ではない）。
mod TilesetGreen {

    // ── アトラス寸法（原本と同一・厳守）──
    pub def cell(): Int32 = 26
    pub def cols(): Int32 = 12
    pub def rows(): Int32 = 9
    pub def atlasW(): Int32 = cell() * cols()   // 312
    pub def atlasH(): Int32 = cell() * rows()   // 234

    // ════════════════════════════════════════════════════════
    // テーマ（材質ランプの束。形=材質領域マップはテーマ共通）
    // ════════════════════════════════════════════════════════
    /// 各ランプは暗→明の固定段。stone/water は 5 段（0=目地/最暗 .. 4=最明/泡）、
    /// wood/metal/plant は 3 段、bone/web は 4 段。ember は石目地の発光色（0=なし・fire 用）。
    pub type alias Theme = {
        name  = String,
        stone = List[Int32],
        water = List[Int32],
        wood  = List[Int32],
        metal = List[Int32],
        bone  = List[Int32],
        plant = List[Int32],
        web   = List[Int32],
        ember = Int32,
        voidC = Int32
    }

    /// green = 原本 tileset_dungeon_green.png の実測 31 色から組んだランプ（再現の基準テーマ）。
    pub def themeGreen(): Theme = {
        name  = "green",
        stone = 0x2d2f37 :: 0x373e3f :: 0x424949 :: 0x475752 :: 0x5a6763 :: Nil,
        water = 0x293e3f :: 0x2b4644 :: 0x3d6056 :: 0x486f62 :: 0x62967e :: Nil,
        wood  = 0x472a22 :: 0x5a392c :: 0x6f4a37 :: Nil,
        metal = 0x2c2934 :: 0x302d37 :: 0x3a3642 :: Nil,
        bone  = 0x423f3d :: 0x5e5956 :: 0x746f6c :: 0x8b8582 :: Nil,
        plant = 0x18381d :: 0x28562e :: 0x3c7638 :: Nil,
        web   = 0x3d6056 :: 0x486f62 :: 0x62967e :: 0x95c5a3 :: Nil,
        ember = 0,
        voidC = 0x19201a
    }

    /// fire = 黒玄武岩+溶岩。石目地はまばらに橙の発光（ember・控えめ）。木は焦げ・植物は燃え殻。
    pub def themeFire(): Theme = {
        name  = "fire",
        stone = 0x18141a :: 0x241e26 :: 0x302832 :: 0x3c323e :: 0x4c404e :: Nil,
        water = 0x461208 :: 0x82240a :: 0xc85a14 :: 0xf09628 :: 0xffd660 :: Nil,
        wood  = 0x1e1816 :: 0x302622 :: 0x42342e :: Nil,
        metal = 0x2c2934 :: 0x302d37 :: 0x3a3642 :: Nil,
        bone  = 0x423f3d :: 0x5e5956 :: 0x746f6c :: 0x8b8582 :: Nil,
        plant = 0x3a241a :: 0x60341c :: 0x965020 :: Nil,
        web   = 0x463e42 :: 0x5a5054 :: 0x72666a :: 0x8c7e82 :: Nil,
        ember = 0xc85a14,
        voidC = 0x1a100e
    }

    /// forest = 苔石+澄んだ青水+濃い緑の植物。
    pub def themeForest(): Theme = {
        name  = "forest",
        stone = 0x222c20 :: 0x2e3c2a :: 0x3a4c34 :: 0x485e3e :: 0x5a744c :: Nil,
        water = 0x182c54 :: 0x203e74 :: 0x3860a0 :: 0x5c8ac8 :: 0xa0c8eb :: Nil,
        wood  = 0x422c1a :: 0x5e4024 :: 0x7a5832 :: Nil,
        metal = 0x2c2934 :: 0x302d37 :: 0x3a3642 :: Nil,
        bone  = 0x423f3d :: 0x5e5956 :: 0x746f6c :: 0x8b8582 :: Nil,
        plant = 0x0e2c12 :: 0x16461a :: 0x246828 :: Nil,
        web   = 0x3d6056 :: 0x486f62 :: 0x62967e :: 0x95c5a3 :: Nil,
        ember = 0,
        voidC = 0x121810
    }

    /// ruins = 砂岩+濁った緑水+枯れ蔓。金属は錆・木は乾いた灰茶。
    pub def themeRuins(): Theme = {
        name  = "ruins",
        stone = 0x383022 :: 0x4c422e :: 0x62563c :: 0x76684a :: 0x8c7c5a :: Nil,
        water = 0x2c3620 :: 0x384628 :: 0x4a5c32 :: 0x5e743e :: 0x788c50 :: Nil,
        wood  = 0x3a3026 :: 0x4e4234 :: 0x625442 :: Nil,
        metal = 0x3c2a1e :: 0x503826 :: 0x684a30 :: Nil,
        bone  = 0x423f3d :: 0x5e5956 :: 0x746f6c :: 0x8b8582 :: Nil,
        plant = 0x423a1e :: 0x5c5028 :: 0x746634 :: Nil,
        web   = 0x645c48 :: 0x7c725a :: 0x948a6e :: 0xb0a484 :: Nil,
        ember = 0,
        voidC = 0x181610
    }

    // ════════════════════════════════════════════════════════
    // 決定論ノイズ・色ユーティリティ
    // ════════════════════════════════════════════════════════
    def hashI(a: Int32, b: Int32, s: Int32): Int32 =
        let h1 = (a * 374761393) + (b * 668265263) + (s * 1013904223);
        let h2 = h1 * (h1 + 30011);
        h2 * (h2 + 19937)

    pub def hash01(a: Int32, b: Int32, s: Int32): Float64 =
        Int32.toFloat64(Int32.modulo(hashI(a, b, s), 100003)) / 100003.0

    def rgbOf(hex: Int32): (Int32, Int32, Int32) =
        (Int32.modulo(hex / 65536, 256), Int32.modulo(hex / 256, 256), Int32.modulo(hex, 256))

    pub def packArgb(a: Int32, c: (Int32, Int32, Int32)): Int32 =
        let (r, g, b) = c;
        (a * 16777216) + (r * 65536) + (g * 256) + b

    def ri(x: Float64): Int32 = Float64.tryToInt32(x + 0.5) |> Option.getWithDefault(0)
    def frac(x: Float64): Float64 = x - Float64.floor(x)
    def tri(x: Float64): Float64 = Float64.abs(frac(x * 0.5) * 2.0 - 1.0)

    /// ランプの i 段目の色（クランプ付き）。量子化の唯一の出口 — 中間色を作らない。
    def rampAt(ramp: List[Int32], i: Int32): (Int32, Int32, Int32) =
        let n = List.length(ramp);
        let j = Int32.max(0, Int32.min(n - 1, i));
        rgbOf(List.nth(j, ramp) |> Option.getWithDefault(0))

    /// 連続値 j∈[0,1) を n 段のインデックスへ量子化。
    def qIdx(j: Float64, n: Int32): Int32 =
        Int32.min(n - 1, Float64.tryToInt32(Float64.floor(j * Int32.toFloat64(n))) |> Option.getWithDefault(0))

    // ════════════════════════════════════════════════════════
    // 材質辞書（実測パレット由来の分類・v5/v6 の第一級要素）
    // ════════════════════════════════════════════════════════
    /// 材質の 7 分類。テーマ差替・材質 XOR 計測の単位。
    pub enum Material {
        case Void
        case Stone
        case Water
        case Wood
        case Metal
        case Bone
        case Plant
    }

    /// ARGB 1 画素 → 材質。原本の実測 31 色を分類して作った閾値規則（材質辞書）。
    /// 原本の任意色にも再現の手続き色にも同じ規則で効く。green テーマの全ランプ色はこの規則で
    /// 意図した材質に分類される（材質 XOR=0 の根拠）。
    ///   虚空 = alpha=0 または 最暗・低彩度 / 木 = 暖色(r-b≥16) /
    ///   植物 = 真緑(g-b≥14 かつ g-r≥20 かつ b-r≤9・蔓) /
    ///   水 = teal(b-r≥18 かつ g-r≥12) または淡泡(g-r≥35 かつ b-r≥10) /
    ///   金属 = 青紫(b-g≥6 かつ g≤r・中明度) / 骨 = 暖色淡灰(b≤r・明るい) / それ以外 = 石。
    pub def classify(argb: Int32): Material =
        // ARGB は alpha=255 で最上位ビットが立ち Int32 が負になる。符号付き除算では成分が壊れるため
        // 下位 24bit を先にマスク（非負に）してから R/G/B を取り出す。alpha=0 判定は上位バイトの検査。
        let alphaZero = Int32.bitwiseAnd(argb, -16777216) == 0;   // 0xFF000000
        let rgb = Int32.bitwiseAnd(argb, 16777215);               // 0x00FFFFFF
        let r = rgb / 65536;
        let g = Int32.bitwiseAnd(rgb / 256, 255);
        let b = Int32.bitwiseAnd(rgb, 255);
        let lum = (r * 30 + g * 59 + b * 11) / 100;
        if (alphaZero) Material.Void
        else if (lum < 40 and (g - r) < 16 and (b - r) < 16) Material.Void
        else if (r - b >= 16) Material.Wood
        else if (g - b >= 14 and g - r >= 20 and b - r <= 9) Material.Plant
        else if ((b - r >= 18 and g - r >= 12) or (g - r >= 35 and b - r >= 10)) Material.Water
        else if (b - g >= 6 and g <= r and lum >= 40 and lum <= 72) Material.Metal
        else if (b - r <= 2 and lum >= 54) Material.Bone
        else Material.Stone

    /// 材質の意味名（レポート・凡例）。
    pub def materialName(m: Material): String = match m {
        case Material.Void  => "void"
        case Material.Stone => "stone"
        case Material.Water => "water"
        case Material.Wood  => "wood"
        case Material.Metal => "metal"
        case Material.Bone  => "bone"
        case Material.Plant => "plant"
    }

    /// 材質チャー → 材質。tracedMask のチャーと classify の値を一致させる橋。
    pub def charMaterial(ch: Char): Material = match ch {
        case 's' => Material.Stone
        case 'w' => Material.Water
        case 'k' => Material.Wood
        case 'm' => Material.Metal
        case 'b' => Material.Bone
        case 'p' => Material.Plant
        case _   => Material.Void
    }

    /// 材質分類の代表色（材質 diff の可視化に使う塗り分け色）。
    pub def materialSwatch(m: Material): (Int32, Int32, Int32) = match m {
        case Material.Void  => (24, 28, 26)
        case Material.Stone => (110, 118, 118)
        case Material.Water => (70, 150, 200)
        case Material.Wood  => (150, 96, 54)
        case Material.Metal => (150, 120, 210)
        case Material.Bone  => (216, 210, 180)
        case Material.Plant => (90, 190, 96)
    }

    // ════════════════════════════════════════════════════════
    // 形と材質: tracedMask（全 108 セル・原本を材質辞書で分類した実測データ）
    // ════════════════════════════════════════════════════════
    // 各文字列は 1 行 26 文字。'#'=虚空 's'=石 'w'=水 'k'=木 'm'=金属 'b'=骨 'p'=植物。
    // 原本が全面虚空のセル（c6/r1・c10/r8・c11/r8）だけ None（全面虚空で塗る）。
    // 形（シルエット）も材質もこの一枚のデータで決まる。多セル建築（中央アーチ門 c3-6/r4 等）は
    // 原本の連続画像から切り出しているため、隣接セルのマスクが自然に整合する。
    pub def tracedMask(col: Int32, row: Int32): Option[List[String]] =
        match (col, row) {
            case (0, 0) => Some(
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssss##ssssssssss###ssss" ::
                "#ssssss###ssssssssss###sss" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss###########sssssss" ::
                "#ssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########ssssssss" ::
                "#sssssss###########sssssss" ::
                "#sssssss##########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "sssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss###########ssssssss" ::
                "sssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########sssssss#" ::
                Nil)
            case (1, 0) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "#ssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "##sssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (2, 0) => Some(
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssss###ssssssss##ssssss#" ::
                "#ssss#####ssssss###sssssss" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "sssssss###########sssssss#" ::
                "sssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########sssssss" ::
                "sssssss###########sssssss#" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "##sssss###########sssssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############sssssss" ::
                Nil)
            case (3, 0) => Some(
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssss###sssssssssss##sss" ::
                "#ssssss##sssssssssss####ss" ::
                "#ssssss##################s" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (4, 0) => Some(
                "sssssss#sssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssss###ssssssss##ssssss#" ::
                "ssss####ssssssss###sssssss" ::
                "ss#################ssssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                Nil)
            case (5, 0) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "####################sssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                Nil)
            case (6, 0) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (7, 0) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "##sssss###################" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                Nil)
            case (8, 0) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "#ssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "####################sssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                Nil)
            case (9, 0) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "#ssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "##sssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (10, 0) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "#ssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "##sssss###################" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                Nil)
            case (11, 0) => Some(
                "#ssssssssssssssssssssssss#" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "#ssssss##ssssssss##ssssss#" ::
                "#ssssss##sssssss###sssssss" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "ssssssss##########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssssss" ::
                "#sssssss##########sssssss#" ::
                "#sssssss##########sssssss#" ::
                "#sssssss###########ssssss#" ::
                "sssssss###########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssssss" ::
                Nil)
            case (0, 1) => Some(
                "#sssssss###########sssssss" ::
                "#sssssss###########sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "#ssssss############ssssss#" ::
                "#ssssss#############sssss#" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss#ssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssssssssssssssssss#ssss" ::
                "#ssssss#ssssssssssssssssss" ::
                "#ssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (1, 1) => Some(
                "sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (2, 1) => Some(
                "sssssss############ssssss#" ::
                "ssssssss##########sssssss#" ::
                "sssssss###########sssssss#" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "##ssss#############ssssss#" ::
                "##################sssssss#" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssss#ssssssssss#ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "sssssss#sssssssssssssssss#" ::
                "sssssss#sssssssss##ssssss#" ::
                "#ss########sss######sss###" ::
                Nil)
            case (3, 1) => Some(
                "#sssssss##################" ::
                "#sssssss##################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss#ssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssssssssssssssssss#ssss" ::
                "#ssssss#ssssssssssssssssss" ::
                "#ssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (4, 1) => Some(
                "###################ssssss#" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################sssssss#" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssss#ssssssssss#ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "sssssss#sssssssssssssssss#" ::
                "sssssss#sssssssss##ssssss#" ::
                "#ss########sss######sss###" ::
                Nil)
            case (5, 1) => Some(
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################sssssss#" ::
                "##################ssssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                Nil)
            case (7, 1) => Some(
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (8, 1) => Some(
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (9, 1) => Some(
                "sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (10, 1) => Some(
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "##ssss####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (11, 1) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "ssssssss##########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssssss" ::
                "#sssssss##########sssssss#" ::
                "#sssssss##########sssssss#" ::
                "#sssssss###########ssssss#" ::
                "sssssss###########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssssss" ::
                Nil)
            case (0, 2) => Some(
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "ssssssss###########sssssss" ::
                "#ssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########ssssssss" ::
                "#sssssss###########sssssss" ::
                "#sssssss##########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "sssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss###########ssssssss" ::
                "sssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########sssssss#" ::
                Nil)
            case (1, 2) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "##sssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (2, 2) => Some(
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################sssssss#" ::
                "##################ssssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "sssssss###########sssssss#" ::
                "sssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########sssssss" ::
                "sssssss###########sssssss#" ::
                "ssssssss##########sssssss#" ::
                "ssssssss###########ssssss#" ::
                "#ssssss###########sssssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############sssssss" ::
                Nil)
            case (3, 2) => Some(
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "##ssss####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "####################sssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                Nil)
            case (4, 2) => Some(
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "##sssss###################" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                Nil)
            case (5, 2) => Some(
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (6, 2) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "#ssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (7, 2) => Some(
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "##ssss####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (8, 2) => Some(
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssss###sssssssssss##sss" ::
                "#ssssss##sssssssssss####ss" ::
                "sssssss##################s" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#ssssss###################" ::
                "#ssssss#ssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssss#sssssssssssss#ssss" ::
                "#ssssssssssssssssssss#ssss" ::
                "#ssssss#ssssssssssssssssss" ::
                "#ssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (9, 2) => Some(
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss###ssssssssss###ssss" ::
                "sssss#####ssssssssss###sss" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssss##ssss" ::
                "#ss########sss#########ss#" ::
                Nil)
            case (10, 2) => Some(
                "sssssss#sssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssss###ssssssss##ssssss#" ::
                "ssss####ssssssss##sssssss#" ::
                "ss################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssss#ssssssssss#ssssss#" ::
                "sssssss#ssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "sssssss#sssssssssssssssss#" ::
                "sssssss#sssssssss##ssssss#" ::
                "#ss########sss######sss###" ::
                Nil)
            case (11, 2) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss##########sssssss#" ::
                "#sssssss##########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "#ssssss#ssssssssss#ssssss#" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#sssssssssssssssss#sssssss" ::
                "#ssssss#sssssssssssssssss#" ::
                "#ssssss#sssssssss##ssssss#" ::
                "#ss########sss######sss###" ::
                Nil)
            case (0, 3) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss#############sssss#" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "ssssssss###########sssssss" ::
                "#ssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########ssssssss" ::
                "#sssssss###########sssssss" ::
                "#sssssss##########ssssssss" ::
                "#sssssss##########ssssssss" ::
                "sssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss###########ssssssss" ::
                "sssssss############sssssss" ::
                "#ssssss###########ssssssss" ::
                "#ssssss###########sssssss#" ::
                Nil)
            case (1, 3) => Some(
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########sssssss" ::
                "sssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "#ssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (2, 3) => Some(
                "sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "sssssss###########sssssss#" ::
                "sssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########sssssss" ::
                "sssssss###########sssssss#" ::
                "ssssssss##########sssssss#" ::
                "ssssssss###########ssssss#" ::
                "#ssssss###########sssssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss###########ssssss#" ::
                "#sssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############sssssss" ::
                Nil)
            case (3, 3) => Some(
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "####################sssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                Nil)
            case (4, 3) => Some(
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "##ssss####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                Nil)
            case (5, 3) => Some(
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "##ssss####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "#ssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (6, 3) => Some(
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "###################ssssss#" ::
                "###################sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss############sssssss" ::
                "ssssssss##########ssssssss" ::
                "ssssssss##########ssssssss" ::
                "#ssssss#############sssss#" ::
                "#ssssss############ssssss#" ::
                "ssssssss##########ssssssss" ::
                "#sssssss###########sssssss" ::
                "ssssssss##########ssssssss" ::
                "sssssss###########sssssss#" ::
                Nil)
            case (7, 3) => Some(
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########sssssss" ::
                "sssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "####################sssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "###################sssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                Nil)
            case (8, 3) => Some(
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########sssssss" ::
                "sssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                "ssssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "ssssssss##################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "sssssss###################" ::
                Nil)
            case (9, 3) => Some(
                "#sss##sssssssssss####sss##" ::
                "#sss#sssssssssssss#ssssss#" ::
                "ssss#sssssssssssssssssssss" ::
                "#sss#ssssssssssssssssssss#" ::
                "#sss#ssssssssssssssssssss#" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssss##ss#ssssss#" ::
                "#sss#ssssssssssss##ssssss#" ::
                "#####s#####ss#############" ::
                "#ssssssss#ssssssssssss#ss#" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssss#ss#" ::
                "#ssssssss#sssssssssss##ss#" ::
                "###ssssss#sssssssssss##ss#" ::
                "##ss#########s###s########" ::
                "#ssss#ssssssssssss##sssss#" ::
                "sssss#sssssssssssss#ssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "sssss#sssssssssssssssssss#" ::
                "sssss#sssssssssssssssssss#" ::
                "#sss###ssssssssss###sssss#" ::
                "#####################ss###" ::
                "#s#####sss####sssss#######" ::
                Nil)
            case (10, 3) => Some(
                "##############ss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sss###s#####ss#######ssss" ::
                "#sss#ssssssssssssssss#ssss" ::
                "#sss#ssssssssssssssss#ssss" ::
                "ssss##ssssssssssssss##ssss" ::
                "ssss##s###sss##ssss###ssss" ::
                "ssss###ss#############ssss" ::
                "ssss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwwwwwsswwwwww#ssss" ::
                "ssss#wwwwwwwwwwwwwwww#ssss" ::
                "ssss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwwwwwwwwwwwwwsssss" ::
                "#sss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss###s########sss###ssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssss###ssssss##" ::
                Nil)
            case (11, 3) => Some(
                "#ssssssssssssssssssssssss#" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "#ssssss##ssssssss##ssssss#" ::
                "#ssssss##sssssss##sssssss#" ::
                "sssssss###########ssssssss" ::
                "#sssssss##########sssssss#" ::
                "#sssssss##########sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "#ssssss#ssssssssss#ssssss#" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#sssssssssssssssss#sssssss" ::
                "#ssssss#sssssssssssssssss#" ::
                "#ssssss#sssssssss##ssssss#" ::
                "#ss########sss######sss###" ::
                Nil)
            case (0, 4) => Some(
                "#ssssss############sssssss" ::
                "#ssssss############sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "#sssssss###########sssssss" ::
                "#sssssss###########sssssss" ::
                "#ssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "#ssssss############sssss##" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#sssssss##################" ::
                "ssssssss##################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "#sssssss##################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (1, 4) => Some(
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssss###########ssssssss" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########sssssss" ::
                "ssssssss###########sssssss" ::
                "sssssss############sssssss" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssss##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (2, 4) => Some(
                "sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########sssssss#" ::
                "sssssss###########ssssssss" ::
                "ssssssss###########ssssss#" ::
                "ssssssss###########ssssss#" ::
                "sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "##ssss#############sssssss" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################ssssssss" ::
                "##################ssssssss" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                "##################sssssss#" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "##################sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################sssssss" ::
                Nil)
            case (3, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "#########################s" ::
                "########################ss" ::
                "######################ssss" ::
                "#####################sssss" ::
                "####################ssssss" ::
                "sssssssssssssssssss#ssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "sssssss#ssssssssss#sssssss" ::
                "sssssss#ssssssssss##ssssss" ::
                "sssssssssssssssssssss##sss" ::
                "sssssss#sssssssss#ssssss##" ::
                "sssssss#sssssssss#sssssss#" ::
                "#ss########sss####sssssss#" ::
                Nil)
            case (4, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "######ssssssssssssss######" ::
                "###ss#sssssssssssssssss###" ::
                "#ssss#ssssssssssssss#ssss#" ::
                "ssssssssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss#ssssssssssss#ssssss" ::
                "ssssss##############ssssss" ::
                "sssss###ss###########sssss" ::
                "sss####ssssss####sss###sss" ::
                "sss####ssssss###sssss##sss" ::
                "s#####sss##ssss#ssssss###s" ::
                "s######ssssssss#sssssss##s" ::
                "#######sssssssssssssssss##" ::
                "##ss##sssssssss#ssssss#s##" ::
                "##sss#sssssssss#ssssss####" ::
                "##sss##ssssssss###s###ss##" ::
                Nil)
            case (5, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "######ssssssssssssss######" ::
                "###ss#sssssssssssssssss###" ::
                "#ssss#ssssssssssssss#ssss#" ::
                "ssssssssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssss#ssssssssssss#ssssss" ::
                "ssssss##############ssssss" ::
                "sssss################sssss" ::
                "sss#####sss##sssss#####sss" ::
                "sss####sss###ssssss####sss" ::
                "s####sssss#ssss##sss#####s" ::
                "s####sssss#ssssssss######s" ::
                "####sssssssssssssss#######" ::
                "####ssssss#sssssssss##ss##" ::
                "###sssssss#sssssssss#sss##" ::
                "#######s###ssssssss##sss##" ::
                Nil)
            case (6, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "s#########################" ::
                "ss########################" ::
                "ssss######################" ::
                "sssss#####################" ::
                "ssssss####################" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "sssssss#sssssssssssss#ssss" ::
                "sssss###sssssssssssss#ssss" ::
                "sss##ss#sssssssssssss#ssss" ::
                "##ssssssssssssssssssssssss" ::
                "ssssssss#sssssssssss##ssss" ::
                "ssssssss###sss#########ss#" ::
                Nil)
            case (7, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########sssss###########" ::
                "#########ssssssss#########" ::
                "######ss##ssssssssss######" ::
                "#####sssss#ssssss#sss#####" ::
                "####sssssssssssssssssss###" ::
                "####ssssssss#sssss#ssss###" ::
                "#####sssssssssssss#sss####" ::
                "#####s#sssssssssss#ssss###" ::
                "###ssss#ssss#ssssss#sss###" ::
                "##sssssssss##sssssssssss##" ::
                "##ssssssssssssssss#ssss###" ::
                "###sss#sssss##ssss#ssss###" ::
                "#############ssssss#######" ::
                "############ssssssss######" ::
                "#############ssssss#######" ::
                "##############ssss########" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (8, 4) => Some(
                "#####################w####" ::
                "####################ww####" ::
                "####################ww####" ::
                "###################www####" ::
                "##################ww#w####" ::
                "#################w#w#w####" ::
                "################w#w##w####" ::
                "###############w##wwww####" ::
                "#############www##w##w####" ::
                "############ww#www###w####" ::
                "##########ww##w#www##w####" ::
                "########www###w#w#wwww####" ::
                "#####www##wwww##w###ww####" ::
                "###www##w##w#www####ww####" ::
                "#wwww####ww####wwwww#w####" ::
                "ww###wwwwwwww##w##wwww####" ::
                "######ww#####ww###ww#ww###" ::
                "#####wwww#####w###w##ww###" ::
                "####ww###wwwww#w##w###w###" ::
                "###w########w###www###w###" ::
                "############w###ww#w##w###" ::
                "###########w##ww####www###" ::
                "###########www#######www##" ::
                "##########ww###########w##" ::
                "##########w#############w#" ::
                "#########w################" ::
                Nil)
            case (9, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "####w#####################" ::
                "#####w####################" ::
                "######wwwww###############" ::
                "www####w##wwwwwww#########" ::
                "###wwwww#ww###wwwwwwwwwwww" ::
                "#####ww#w###www######ww#ww" ::
                "#######w##www######ww###w#" ::
                "########wwwwwwwwwwwww##ww#" ::
                "##########w######wwwww#w##" ::
                "###########ww###ww#w#w#w##" ::
                "############w##ww####www##" ::
                "############wwww######w###" ::
                "#############www######w###" ::
                "##############ww##########" ::
                "###############w##########" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (10, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "#####wwwwww#######w#######" ::
                "###www###w#ww#####w#######" ::
                "##www####w##ww###www###w##" ::
                "##wwww###ww##wwww##w#ww###" ::
                "##w##ww###w##w##ww#w#w####" ::
                "#ww###wwwwwww####w#w#w####" ::
                "#w###www###ww####w##ww####" ::
                "#wwwwww##ww######w##ww####" ::
                "#ww##wwww########w#w#w####" ::
                "w####w###########w#w#w####" ::
                "w################www######" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (11, 4) => Some(
                "##########################" ::
                "##########################" ::
                "############w#############" ::
                "############w#############" ::
                "#############w############" ::
                "#############w############" ::
                "#####w#######w############" ::
                "##w###w#####w#w###########" ::
                "##ww##ww###ww#ww##########" ::
                "###www##wwww##www#########" ::
                "####w###ww###ww##w########" ::
                "####ww##wwwwww###ww#######" ::
                "####wwwwwww###w##www######" ::
                "####w#####w####www##ww####" ::
                "####www####wwwwww#########" ::
                "#####wwwwwwwww############" ::
                "#####w#######ww###########" ::
                "#####w#########ww#########" ::
                "####ww###########ww#######" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (0, 5) => Some(
                "#sss##sssssssssss####sssss" ::
                "#sss#sssssssssssss#sssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "#sss#sssssssssssssssssssss" ::
                "#sss#sssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssss##ss#sssssss" ::
                "#sss#ssssssssssss##sssssss" ::
                "#####s#####ss#############" ::
                "#ssssssss#ssssssssssss#sss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssss#sss" ::
                "#ssssssss#sssssssssss##sss" ::
                "###ssssss#sssssssssss##sss" ::
                "##ss#########s###s######s#" ::
                "#ssss#ssssssssssss##ssssss" ::
                "sssss#sssssssssssss#ssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "#sss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "#s#####sss####sssss#######" ::
                Nil)
            case (1, 5) => Some(
                "ssss##sssssssppss##pppppps" ::
                "ssss##ssspppppssss#sspppss" ::
                "ssss#spppppppppsssssssppss" ::
                "ssss#pp#sss#pppsssssssppss" ::
                "ssss#ps##sss#pppssppsspsss" ::
                "ssss##ss#ssss#ppsspsssssss" ::
                "ssss##sssssss#pps#psssssss" ::
                "ssss##ss#ssssspp#pp#ssssss" ::
                "#########sssspppp#########" ::
                "sssssss#######ppssssss#sss" ::
                "sssssssss#ssss#pssssssssss" ::
                "sssssssss#ssssspssssssssss" ::
                "ssssssssssssssspssssssssss" ::
                "sssssssss#ssssspssssss#sss" ::
                "sssssssss#ssssspsssss##sss" ::
                "s##ssssss#ssss#ssssss##sss" ::
                "##ss#########s###s######s#" ::
                "sssss#ssssssssssss##ssssss" ::
                "sssss#sssssssssssss#ssssss" ::
                "sssssssssssssssssss#ssssss" ::
                "ssssssssssssssss#sssssssss" ::
                "sssss#sssssssss##sssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (2, 5) => Some(
                "ssss##sssssssssss####sssss" ::
                "ssss#sssssssssssss#sssssss" ::
                "ssss#ssssssss#ssssssssssss" ::
                "ssss#sssssss##ssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssss##ss#sssssss" ::
                "ssss#ssssssssssss##sssssss" ::
                "#####s#####ss#############" ::
                "sssssssss#ssssssssssss#sss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssskpsssksssssss" ::
                "ssssssssssss#ksssk#sss#sss" ::
                "sssssssss#ss#ksssk#ss##sss" ::
                "s##ssssss#ss#k#sk#sss##sss" ::
                "##ss########pk##k#######s#" ::
                "sssss#ssss##kk#kks##ssssss" ::
                "sssss#ssss##kpkksss#ssssss" ::
                "ssssssssssp#kk#ssss#ssssss" ::
                "ssssssssssskk#psssssssssss" ::
                "sssss#ssss#kksssssssssssss" ::
                "sssss#ssspkk#sssssssssssss" ::
                "ssss###ss#kk#ssss###ssssss" ::
                "#########kkkk########ss###" ::
                "ss#####kkk##kk###ss#######" ::
                Nil)
            case (3, 5) => Some(
                "ssss##sssssssssss#sssssss#" ::
                "ssss#ssssssssssss#sssssss#" ::
                "ssss#ssssssssssss#####sss#" ::
                "ssss#ssssssssssss#sssss###" ::
                "ssss#ssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssss#sssssss#" ::
                "ssss#sssssssssss##ssss##s#" ::
                "#####s#####ss#####sssssss#" ::
                "sssssssss#sssssss#sssssss#" ::
                "sssssssssssssssss##s##ss##" ::
                "sssssssssssssssss#sssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssss#sssssss#" ::
                "sssssssss#sssssss#sssssss#" ::
                "s##ssssss#sssssss##ssssss#" ::
                "##ss#########s#####ssssss#" ::
                "sssss#sssssssssss####ss###" ::
                "sssss#sssssssssss#ssssss##" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssss#sssssssssss#sssssss#" ::
                "sssss#sssssssssss#sssssss#" ::
                "ssss###ssssssssss#sssssss#" ::
                "###################sss#ss#" ::
                "ss#####sss####sss#########" ::
                Nil)
            case (4, 5) => Some(
                "##sss##sssssss##ssssssss##" ::
                "#sss###ssss##sssssssssss##" ::
                "#sss###ss##s#sssssss#sss##" ::
                "#ss#####ssssssssssss#ss###" ::
                "#ss###ssssss#ssssssss#####" ::
                "#s###sssssss#ssss##ssss###" ::
                "#sss#sssssss###ssssssss#ss" ::
                "##ss#sssssss#sssssssss##ss" ::
                "##ss#sssss##ssssss##s##s##" ::
                "##s#ssss##sssssss#ssssss##" ::
                "#ss##s#ssssssssss###sssss#" ::
                "#s###sssss#sss#####s#sssss" ::
                "####ssssss#sssss###sss##ss" ::
                "####ssssssssssssss###sss##" ::
                "#s#ssssss##sssssssss###ss#" ::
                "#sss#ssssss##sssssssss####" ::
                "ssss#ssss#ssss##ssssssss##" ::
                "ssss##ss##ssssss##ssssssss" ::
                "#sss##s#######ssss##ssssss" ::
                "#ss####sssss#####ss###ssss" ::
                "#ss##sssssssssss#########s" ::
                "####ssssssssssssss########" ::
                "###ssssssssssssssssss#####" ::
                "##sssssssssssssssssssss###" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                Nil)
            case (5, 5) => Some(
                "###sssssss##sssssss##sss##" ::
                "###ssssssssss##ssss##ssss#" ::
                "##sss#sssssss#s##ss##ssss#" ::
                "##sss#ssssssssssss###ssss#" ::
                "######sssssss#ssssss##sss#" ::
                "###sss###ssss#sssssss###s#" ::
                "##sssss#sss###sssssss#s###" ::
                "##sssss#sssss#sssssss#ss##" ::
                "##sssss#ssssss##sssss#sss#" ::
                "##sssss#ssssssss##sss##ss#" ::
                "##sssss#sssssssssss####ss#" ::
                "####ss##sssssss#sssss###s#" ::
                "#########ssssss#ssssss####" ::
                "#####ss#####sss#ssssss####" ::
                "###ssss#ss######sssssss#s#" ::
                "###ssss#ssss####sssss#sss#" ::
                "####sss#ssssss###ssss#ssss" ::
                "######################ssss" ::
                "ss#ssss###ssssss#######ss#" ::
                "s#sss##sssssss###ssss###s#" ::
                "#ss##ssssss###sssssssss###" ::
                "#s#sssss##ssssssssssssss##" ::
                "##ssss##sssssssssssssssss#" ::
                "#sss##sssssssssssssssssss#" ::
                "###ssssssssssssssssssssss#" ::
                "##sssssssssssssssssssssss#" ::
                Nil)
            case (6, 5) => Some(
                "#sssssss#ssssssss####sssss" ::
                "#sssssss#sssssssss#sssssss" ::
                "#sssss###sssssssssssssssss" ::
                "###sssss#sssssssssssssssss" ::
                "#sssssss#sssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssss#sssss##ss#sssssss" ::
                "#sssssss#ssssssss##sssssss" ::
                "#sssssss###ss#############" ::
                "#sssssss##ssssssssssss#sss" ::
                "####ss###sssssssssssssssss" ::
                "#sssssss#sssssssssssssssss" ::
                "#sssssss#sssssssssssssssss" ::
                "#sssssss#sssssssssssss#sss" ::
                "#sssssss##sssssssssss##sss" ::
                "#sssssss##sssssssssss##sss" ::
                "#sssssss#####s###s######s#" ::
                "####sss##sssssssss##ssssss" ::
                "#sssssss#ssssssssss#ssssss" ::
                "#sssssss#ssssssssss#ssssss" ::
                "#sssssss#sssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssss#ssssssss###ssssss" ::
                "###sssss#############ss###" ::
                "##############sssss#######" ::
                Nil)
            case (7, 5) => Some(
                "ssss##sssssssssss####sssss" ::
                "sss#ksssssssssssss#sssssss" ::
                "sss#ksssssssssssssssssssss" ::
                "sss#kspsssssssssssssssssss" ::
                "sss#pksssspssspsssssssssss" ::
                "sss#kkssssskkk#sssssssssss" ::
                "ssss#kksskkk##ssss#sssssss" ::
                "ssss#kkkkkkssssss##sssssss" ::
                "###kkkpkk##ss#############" ::
                "sss###kkkkssssssssssss#sss" ::
                "ssss##k##kksssssssssssssss" ::
                "ssss#s#sssksssssssssssssss" ::
                "ssss#ssssskkspssssssssssss" ::
                "sss#sssss#skksssssssss#sss" ::
                "sssssssss#skkssssssss##sss" ::
                "s##ssssss##kkssssssss##sss" ::
                "##ss#######kks###s######s#" ::
                "sssss#sssss#ksssss##ssssss" ::
                "sssss#sssss#kssssss#ssssss" ::
                "ssssssssssss#ssssss#ssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (8, 5) => Some(
                "ssss##sssssssssss####sssss" ::
                "ssss#sssssssssssss#sssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssss##ss#sssssss" ::
                "ssss#ssssssssssss##sssssss" ::
                "#####s#####ss#############" ::
                "sssssssss#ssssssssssss#sss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssss#sss" ::
                "sssssssss#sssssssssss##sss" ::
                "s##ssssss#sssssssssss##sss" ::
                "##ss#########s###s######s#" ::
                "sssss#ssssssssssss##ssssss" ::
                "sssss#sssssssssssss#ssssss" ::
                "sssssssssssssssssss#ssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (9, 5) => Some(
                "ssss##sssssssssss####sssss" ::
                "ssss#sssssssssss###sssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssspssssssss" ::
                "ssssssssssssssssspssssssss" ::
                "ssssssssssssss##pp#sssssss" ::
                "ssss#ssssssssss#pp#sssssss" ::
                "#####s#####ss##ppp########" ::
                "sss#######sppppppppppp#sss" ::
                "ssssss####sppppppppppppsss" ::
                "ssssss##s#ssppppppps#ppsss" ::
                "ssssss#ss#sssssssssssppsss" ::
                "ssssss#ss#sssssssssss#psss" ::
                "sssssssss#sssssssssss#psss" ::
                "s##sssss##sssssssssss##sss" ::
                "##sssss######s###s######s#" ::
                "sssss##pppppppssss##ssssss" ::
                "sssss#pppppssssssss#ssssss" ::
                "ssssssppspsssssssss#ssssss" ::
                "ssssssppssssssssssssssssss" ::
                "sssss#psssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (10, 5) => Some(
                "ssss##sssssssssss####sssss" ::
                "ssss#sssssssssssss#sssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#sssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssss##ss#sssssss" ::
                "ssss#ssssssssssss##sssssss" ::
                "#####s#####ss#############" ::
                "sssssssss##############sss" ::
                "ssssssssss######s#ss##ssss" ::
                "ssssssssss###s###s#s##ssss" ::
                "sssssssss###s#sssssss#ssss" ::
                "sssssssss##ssssssssss##sss" ::
                "sssssssss##ssssssssss##sss" ::
                "s##ssssss###ssssssss###sss" ::
                "##ss####################s#" ::
                "sssss#ssssssssssss##ssssss" ::
                "sssss#sssssssssssss#ssssss" ::
                "sssssssssssssssssss#ssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "sssss#ssssssssssssssssssss" ::
                "ssss###ssssssssss###ssssss" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (11, 5) => Some(
                "ssss##sssssssssss####sss##" ::
                "ssss#sssssssssssss#ssssss#" ::
                "ssss#sssssssssssssssssssss" ::
                "ssss#ssssssssssssssssssss#" ::
                "ssss#ssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssss##ss#ssssss#" ::
                "ssss#ssssssssssss##ssssss#" ::
                "#####s#####ss#############" ::
                "sssssssss#ssssssssssss#ss#" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssssssssssssssss#" ::
                "ssssssssssssssssssssss#ss#" ::
                "sssssssss#sssssssssss##ss#" ::
                "s##ssssss#sssssssssss##ss#" ::
                "##ss#########s###s########" ::
                "sssss#ssssssssssss##sssss#" ::
                "sssss#sssssssssssss#ssssss" ::
                "sssssssssssssssssss#ssssss" ::
                "sssssssssssssssssssssssss#" ::
                "sssss#sssssssssssssssssss#" ::
                "sssss#sssssssssssssssssss#" ::
                "ssss###ssssssssss###sssss#" ::
                "#####################ss###" ::
                "ss#####sss####sssss#######" ::
                Nil)
            case (0, 6) => Some(
                "##############ss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sss###s######ss######s###" ::
                "#sss#sssssssssssssssssssss" ::
                "#sss#sssssssssssssssssssss" ::
                "ssss##ssssssssssssssss#sss" ::
                "ssss##s###sss##sssss######" ::
                "ssss###ss#######ss########" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwssswwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwssss" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwss" ::
                Nil)
            case (1, 6) => Some(
                "#########ssss#########ss##" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#####s#####ss#############" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ss#######ssssss####s#####s" ::
                "###########ss#########s###" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwsswwwwwwwwwwwwwwwwwsss" ::
                "swwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwswwwwwwwwwww" ::
                "wwwwwwwwswwwwwssswwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwssswwswwwwwwwww" ::
                Nil)
            case (2, 6) => Some(
                "##############ss######ss##" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#####s#####ss#########ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "ssssssssssss#sssssss##ssss" ::
                "sssss###sss###sssss###ssss" ::
                "#########s############ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wswwwwwwwwwwwwwwwwwww#ssss" ::
                "swwwwwwwwwwwwwwwwwwww#ssss" ::
                "swwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwsssswwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwswwww#ssss" ::
                "wwwwwwwwwwwwwwssssssw#ss##" ::
                Nil)
            case (3, 6) => Some(
                "#########sssssss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssssssssssss###" ::
                Nil)
            case (4, 6) => Some(
                "#########sssssss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "psssssssssssssssssssssssss" ::
                "psssssssssssssssssssssssss" ::
                "ppssssssssssssssssssssssss" ::
                "pppsssssssssssssssssssssss" ::
                "pppppppsssssssssssssssssss" ::
                "pppppsssssssssssssssssssss" ::
                "pppsssssssssssssssssssssss" ::
                "pppsssssssssssssssssssssss" ::
                "#pssssssssssssssssssssssss" ::
                "#pssssssssssssssssssssssss" ::
                "#pssssssssssssssssssssssss" ::
                "#pssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssssssssssss###" ::
                Nil)
            case (5, 6) => Some(
                "#########sssssss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssssssssssss###" ::
                Nil)
            case (6, 6) => Some(
                "#########sssssss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssssp" ::
                "#ssssssssssssssssssssssssp" ::
                "#ssssssssssssssssssssssspp" ::
                "#sssssssssssssssspsssspppp" ::
                "#ssssssssssssssssspssssspp" ::
                "ssssssssssssssssssppsssspp" ::
                "ssssssssssssssssssppppsppp" ::
                "sssssssssssssssssppppppppp" ::
                "sssssssssssssssssssspppppp" ::
                "#ssssssssssssssssssssssppp" ::
                "#ssssssssssssssssssssssspp" ::
                "sssssssssssssssssssssssppp" ::
                "sssssssssssssssssssssssssp" ::
                "#ssssssssssssssssssssssssp" ::
                "#ssssssssssssssssssssssssp" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssspsssss" ::
                "#ssssssssssssssssssppsssss" ::
                "#sssssssssssssssssppssssss" ::
                "#sssssssssssssssppppssssss" ::
                "#sssssssssssssssppppppssss" ::
                "sssssssssssssppppppppppppp" ::
                Nil)
            case (7, 6) => Some(
                "#########sss##ss######ss##" ::
                "##sssssssssss#sssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssss#ssssssssssss" ::
                "#ssssssssssss##sssssssssss" ::
                "##ssssssss#####sssssss##s#" ::
                "#ssssssssssss#ssssssssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "sssssssssssss#sss###sss###" ::
                Nil)
            case (8, 6) => Some(
                "#########sss##ss######ss##" ::
                "##sssssssssss#sssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssps" ::
                "sssssssssspsssssssssskkkks" ::
                "ssssskkkkkkks#ssssskkkpsss" ::
                "#sssss#kkkkkkkksspkkksssss" ::
                "##sssssps####kkkskkkksssss" ::
                "#ssssssssssss#kkkkkk#sssss" ::
                "#sssssssssssss#kkkk#####ss" ::
                "#ssssssssssssskkk######sss" ::
                "#ssssssssssspkkk######s#ss" ::
                "#ssssssssssskkk###s##s#sss" ::
                "#sssssssssskkks#ss##ssssss" ::
                "#sssssssssskssss##s#ssssss" ::
                "#ssssssssssssss#ss#sssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "#ssssssssssss##sss#sssssss" ::
                "#ssssssssssss###s#ssssssss" ::
                "ssssssssssssssssss##sss###" ::
                Nil)
            case (9, 6) => Some(
                "#########sss##ss######ss##" ::
                "##sssssssssss#sssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssssssss#ssssssssssss" ::
                "#ssssssssssss##sssssssssss" ::
                "##ssssssss#####sss##ss##s#" ::
                "#ssssssssssss#sss#ssssssss" ::
                "#ssssssssssss#ssss#sssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "sssssssssssss#sss###sss###" ::
                Nil)
            case (10, 6) => Some(
                "######ssssssssssss###sssss" ::
                "#sss#sssssssssssss#sssssss" ::
                "#sssssssssssssssssssssssss" ::
                "###s###sssssssssssssssssss" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#ssssss#ssssssssss#sssssss" ::
                "#ssssss#s####ssss##sssssss" ::
                "sssssss#sssss#s###########" ::
                "sssssssssssss#ssssssss#sss" ::
                "sssssssssssss#ssssssssssss" ::
                "sssssssssssss#s###ssssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssssssssss#ss#sss" ::
                "sssssssssssss#sssss#s##sss" ::
                "sssssssssssss#sssss#ssss#s" ::
                "#ssssssssssssssssssssssss#" ::
                "#ssssssssssssssssssssssss#" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssss#sssssssssssssssss#" ::
                "#ssssss#sssss#sssss#sssss#" ::
                "##sss####sss##sssss###sss#" ::
                "#####sss############ss####" ::
                Nil)
            case (11, 6) => Some(
                "#########sssssss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssssss###s#ssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssss#sssss#ssssss" ::
                "#ssssssss##s#sssssssssssss" ::
                "ssssssssssss#sssssssssssss" ::
                "sssssss#ssss#sssssssssssss" ::
                "sss###s#ssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssss#sssssssssss" ::
                "sssssssssssss#ssssssssssss" ::
                "sssssssssssss#ssssssssssss" ::
                "#ssssssssssssssssssssssss#" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssssssssss#ssssss" ::
                "#ssssssssssss#sssss##sssss" ::
                "#ssssssssssss#sssss##ssss#" ::
                "#sssss#ssssss#ssss#####ss#" ::
                "#sssss#ssss###sssssssss#s#" ::
                "#sss######ss##ssssssssss##" ::
                "###sssssssss###sss#sssss##" ::
                "##ssssss#############ss###" ::
                Nil)
            case (0, 7) => Some(
                "#####wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswswwwwwwwwwwwwwwwwwww" ::
                "#sssswswwwwwwwwwwwwwwwwwww" ::
                "ssssswwwwwwwwwwwwwwwwwwwww" ::
                "ssssswwsswwwwwwwwwwwwwwwww" ::
                "ssss#wwwswwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwssswwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwsswwwwwwwwwwwwwwww" ::
                "#sss#wswwwwwwwwwwwwwwwwwww" ::
                "#sss#wswwwwwwwwwwwwwwwwwww" ::
                "ssss#wswwwwwwwwwwwwwwwwwww" ::
                Nil)
            case (1, 7) => Some(
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwsswwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwsswwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                Nil)
            case (2, 7) => Some(
                "wwwwwwwwwwwwwwwwwsssw#####" ::
                "wwwwswwwwwwwwwwwwwwsw##sss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwsww#ssss" ::
                "wwwwwwwwwwwwwwwwwwswwsssss" ::
                "wwwwwwwwwwwwwwwwwwswwsssss" ::
                "wwwwwwwwwwwwwwwwwwswwsssss" ::
                "wwwwwwwwwwwwwwwwwwswwsssss" ::
                "wwwwwwwwwwwwwwwwwwsww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                Nil)
            case (3, 7) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "kkkkkkkkkkkkkkkkkkkkkkkkkk" ::
                "kkkkkkkkkkkkkkkkkkkkkkkkkk" ::
                "kkkkkkkkkkkkkkkkkkkkkkkkkk" ::
                "kkkkkkkkkkkkkkkkkkkkkkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "k#s#k#k#s#kk#k#s#kk#k#s#kk" ::
                "ksssk#kssskk#kssskk#kssskk" ::
                "k#m#k#k#m#kk#k#m#kk#k#m#kk" ::
                Nil)
            case (4, 7) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kk########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kk########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kk########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "#k########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                Nil)
            case (5, 7) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "#sss####sss####sss####sss#" ::
                "#sss####sss####sss####sss#" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "ssssssssssssssssssssssssss" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                Nil)
            case (6, 7) => Some(
                "##########################" ::
                "sss#######################" ::
                "sss#######################" ::
                "##########################" ::
                "#s########################" ::
                "#s########################" ::
                "##########################" ::
                "sss#######################" ::
                "sss#######################" ::
                "##########################" ::
                "#s########################" ::
                "#s########################" ::
                "##########################" ::
                "sss#######################" ::
                "sss#######################" ::
                "##########################" ::
                "#s########################" ::
                "#s########################" ::
                "##########################" ::
                "sss#######################" ::
                "sss#######################" ::
                "##########################" ::
                "ms########################" ::
                "m#########################" ::
                "ms########################" ::
                "ms########################" ::
                Nil)
            case (7, 7) => Some(
                "##########################" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkk############" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkk############" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkk############" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "##########################" ::
                Nil)
            case (8, 7) => Some(
                "##########################" ::
                "############sss###########" ::
                "############sss###########" ::
                "############sss###########" ::
                "##########################" ::
                "#############s############" ::
                "#############s############" ::
                "##########################" ::
                "############sss###########" ::
                "############sss###########" ::
                "############sss###########" ::
                "##########################" ::
                "#############s############" ::
                "#############s############" ::
                "##########################" ::
                "############sss###########" ::
                "############sss###########" ::
                "############sss###########" ::
                "##########################" ::
                "#############s############" ::
                "#############s############" ::
                "##########################" ::
                "############sss###########" ::
                "############sss###########" ::
                "############sss###########" ::
                "##########################" ::
                Nil)
            case (9, 7) => Some(
                "##############ss######ss##" ::
                "##sssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sss###s######ss######s###" ::
                "#sss#sssssssssssssssssssss" ::
                "#sss#sssssssssssssssssssss" ::
                "ssss##ssssssssssssssss#sss" ::
                "ssss##s###sss##sssss######" ::
                "ssss###ss#######ss########" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwssswwwwwwwwww" ::
                "ssssswwwwwwwwwwwwwwwwwssss" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss###s#########ss##sss##" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssss###sssss###" ::
                Nil)
            case (10, 7) => Some(
                "#########ssss#########ss##" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#####s#####ss#############" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "ss#######ssssss####s#####s" ::
                "###########ss#########s###" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwsswwwwwwwwwwwwwwwwwsss" ::
                "swwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "######s######ss######sss##" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssss###" ::
                Nil)
            case (11, 7) => Some(
                "##############ss######ss##" ::
                "#ssssssssssssssssssssssss#" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#####s#####ss#########ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "sssssssssssssssssssss#ssss" ::
                "ssssssssssss#sssssss##ssss" ::
                "sssss###sss###sssss###ssss" ::
                "#########s############ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wswwwwwwwwwwwwwwwwwww#ssss" ::
                "swwwwwwwwwwwwwwwwwwww#ssss" ::
                "swwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "#######sss#####ssss###ssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "##ssssssssssssss##ssssss##" ::
                Nil)
            case (0, 8) => Some(
                "#####wsswwwwwwwwwwwwwwwwww" ::
                "#sss#wsswwwwwwwwwwwwwwwwww" ::
                "#sss#wsswwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwwwwwwwwwwwwwwwwwww" ::
                "ssssswwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssswwwswwwwwwwwwwwwwwwww" ::
                "#sssswwwswwwwwwwwwwwwwwwww" ::
                "#sss#wswswwwwwwwwwwwwwwwww" ::
                "ssss#wsswwwwwwwwwwwwwwwwww" ::
                "ssss#wssswwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss###s#########ss##sss##" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "sssssssssssssss###sssss###" ::
                Nil)
            case (1, 8) => Some(
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wsswwwwwwwwwwwwwwwwwwwwwww" ::
                "ssssssswwwwwwwwwwwssssswww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "######s######ss######sss##" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssss###" ::
                Nil)
            case (2, 8) => Some(
                "sssswwwwwwwwwwwwwwwww#####" ::
                "wsswwwwwwwwwwwwwwwwww##sss" ::
                "wwwwwwwwwwwwwwwwwwssw#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwwwsssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwswsw#ssss" ::
                "wsswwwwwwwwwwwwwwsssw#ssss" ::
                "sssswwwwwwwwswwwwwwswsssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "#######sss#####ssss###ssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "##ssssssssssssss##sssss###" ::
                Nil)
            case (3, 8) => Some(
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "sskkk#kkkkkk#kkkkkk#kkkkkk" ::
                "msskk#kkkkkk#kkkkkk#kkkkkk" ::
                "#s#sk#kkkkkk#kkkkkk#kk#kkk" ::
                "###kk#kkkkkk#kkkkkk#kk#kkk" ::
                "##kkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#ksssss" ::
                "kkkkk#kkkkkk#kkkkkk#ksssss" ::
                "kkkkk#kkkkkk#kkkkkk#ks###s" ::
                "kkkkk#kkkkkk#kkkkkk#kss#ss" ::
                "kkkkk#kkkkkk#kkkkkk#kss#ss" ::
                "sskkk#kkkkkk#kkkkkk#ksssss" ::
                "msskk#kkkkkk#kk#kkk#kkkkkk" ::
                "#s#sk#kkkkkk#kk#kkk#kkkkkk" ::
                "###kk#kkkkkk#kkkkkk#kkkkkk" ::
                "##kkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "kkkkk#kkkkkk#kkkkkk#kkkkkk" ::
                "k#s#k#k#s#kk#k#s#kk#k#s#kk" ::
                "ksssk#kssskk#kssskk#kssskk" ::
                "k#m#k#k#m#kk#k#m#kk#k#m#kk" ::
                "kkkkk#kkkkkk#kk#kkk#kkkkkk" ::
                "##########################" ::
                Nil)
            case (4, 8) => Some(
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "k#k#######################" ::
                "sss#######################" ::
                "#sm#######################" ::
                "##########################" ::
                "k#k#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "k#k#######################" ::
                "sss#######################" ::
                "#sm#######################" ::
                "##########################" ::
                "k#k#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "##########################" ::
                Nil)
            case (5, 8) => Some(
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "ssssssssssssssssssssssssss" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms####sssss" ::
                "#ms#####ms#####ms####sssss" ::
                "ssssssssssssssssssssms###s" ::
                "#ms#####ms#####ms####ss#ss" ::
                "#ms#####ms#####ms####ss#ss" ::
                "#ms#####ms#####ms####sssss" ::
                "#ms#####ms#####ms#####mm##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "ssssssssssssssssssssssssss" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "#ms#####ms#####ms#####ms##" ::
                "##########################" ::
                Nil)
            case (6, 8) => Some(
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "m#########################" ::
                "ms########################" ::
                "##########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "m#########################" ::
                "ms########################" ::
                "##########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "m#########################" ::
                "ms########################" ::
                "##########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "ms########################" ::
                "##########################" ::
                Nil)
            case (7, 8) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###########s##############" ::
                "#########s#b##############" ::
                "##########bbb#s###########" ::
                "##########ssbbb##ss#######" ::
                "#########s#b#sbbbbb#######" ::
                "#######s#sbbb###bbb#######" ::
                "######sbbbb##sss#b#s######" ::
                "#######bb##s######s#######" ::
                "#########s################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (8, 8) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########s###s###########" ::
                "##########bbbbb###########" ::
                "########sbbbbbbbs#########" ::
                "#########bbbbbbb##########" ::
                "##########bb#sbb#ss#######" ::
                "#######s##bb##bb###b#s####" ::
                "########sb#bbbb#sbbbb#####" ::
                "######bbbsbbbs#bbss#######" ::
                "##############s#bbb#s#####" ::
                "######ssssssssss#bb#######" ::
                "###############ss##s######" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case (9, 8) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "#############s##s#########" ::
                "#############bbbb#########" ::
                "############bbbbbb########" ::
                "###########s#bbbbbbs######" ::
                "#########s###bbbbbb#######" ::
                "########s#sbbb#sbbb#######" ::
                "######s###bb#b##bbb#######" ::
                "#######bb#bbbbbbbbs#s#####" ::
                "#######s#s#bbbbs###s#s####" ::
                "######s#bbb#bs##sbbbb#####" ::
                "#######bbbss##bb###bb#####" ::
                "###########bbbb#sss##s####" ::
                "########sss###bb#ss#######" ::
                "############ss###s########" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                Nil)
            case _ => None
        }

    /// マスクの (lx,ly) 材質チャー。範囲外・マスク無しは '#'（虚空）。
    def maskCharAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Char =
        match tracedMask(col, row) {
            case None       => '#'
            case Some(mask) =>
                match List.nth(ly, mask) {
                    case Some(rowStr) => String.charAt(lx, rowStr)
                    case None         => '#'
                }
        }

    /// アトラス全体座標での材質チャー（セル跨ぎの近傍参照用。水の泡リムが枠石に接する判定）。
    def charAtGlobal(gx: Int32, gy: Int32): Char =
        if (gx < 0 or gy < 0 or gx >= atlasW() or gy >= atlasH()) '#'
        else maskCharAt(gx / cell(), gy / cell(), Int32.modulo(gx, cell()), Int32.modulo(gy, cell()))

    /// (col,row,lx,ly) が構造（true）か虚空（false）か。虚空チャー '#' 以外が構造。
    pub def structureAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Bool =
        maskCharAt(col, row, lx, ly) != '#'

    /// (col,row,lx,ly) の材質（材質 XOR 計測・塗り分けの共通経路）。
    pub def materialAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Material =
        charMaterial(maskCharAt(col, row, lx, ly))

    /// (col,row) → 意味名（ユーザー指示の語彙）。未命名セルは座標名。
    pub def cellName(col: Int32, row: Int32): String =
        match (col, row) {
            case (11, 0) => "wall_cap_c"
            case (11, 1) => "corridor_v"
            case (10, 3) => "panel_frame"
            case (0, 5)  => "floorcap_l"
            case (5, 6)  => "floor_base"
            case (0, 6)  => "water_edge_nw"
            case (1, 7)  => "water_c"
            case (10, 7) => "trough_c"
            case (3, 8)  => "door"
            case (5, 8)  => "gate"
            case (7, 7)  => "plank"
            case (8, 7)  => "chain"
            case (7, 4)  => "rock"
            case (9, 4)  => "web_b"
            case (7, 8)  => "bones"
            case (8, 8)  => "skull"
            case (4, 4)  => "arch_l"
            case (5, 4)  => "arch_r"
            case _       => "c${col}_r${row}"
        }

    // ════════════════════════════════════════════════════════
    // 石の手触り文脈（材質は全て石。床/壁/枠で手続きを変えるだけ = 質感の別軸）
    // ════════════════════════════════════════════════════════
    pub enum StoneKind {
        case Floor
        case Wall
        case Coping
    }

    /// 's'（石）を塗る手触り。床帯 / 水枠（コーピング）/ それ以外は壁レンガ。
    def stoneContext(col: Int32, row: Int32): StoneKind =
        let waterFrame =
            (col <= 2 and row >= 6) or (col >= 9 and col <= 11 and row == 7) or (col == 10 and row == 3);
        if (row == 5 or (row == 6 and col >= 3 and col <= 8)) StoneKind.Floor
        else if (waterFrame) StoneKind.Coping
        else StoneKind.Wall

    /// 蜘蛛の巣セル（r4 の右側 4 つ）。淡 teal の糸は water 分類域だが、web ランプで塗る。
    def isWebCell(col: Int32, row: Int32): Bool = row == 4 and col >= 8

    // ════════════════════════════════════════════════════════
    // レイヤー分解（layerArgb の出口）
    // ════════════════════════════════════════════════════════
    pub enum Layer {
        case Void
        case Ground
        case Arch
        case Weather
        case Light
    }

    type alias Stg = { ground = (Int32, Int32, Int32), arch = (Int32, Int32, Int32),
                       weather = (Int32, Int32, Int32), light = (Int32, Int32, Int32),
                       full = (Int32, Int32, Int32) }

    def neutralRelief(f: Float64): (Int32, Int32, Int32) =
        let v = Int32.max(0, Int32.min(255, ri(128.0 * f)));
        (v, v, v)

    /// 出力 ARGB（green テーマ）。虚空は虚空色、構造は量子化ランプの段。
    pub def pixelArgb(col: Int32, row: Int32, lx: Int32, ly: Int32): Int32 =
        pixelArgbWith(themeGreen(), col, row, lx, ly)

    /// 出力 ARGB（テーマ指定）。形は共通、材質ランプだけテーマで差し替わる。
    pub def pixelArgbWith(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32): Int32 =
        if (not structureAt(col, row, lx, ly))
            packArgb(255, rgbOf(t#voidC))
        else
            packArgb(255, stageOf(t, col, row, lx, ly)#full)

    /// レイヤー別 ARGB（カタログ出口・green テーマ）。
    pub def layerArgb(col: Int32, row: Int32, lx: Int32, ly: Int32, layer: Layer): Int32 =
        let t = themeGreen();
        let solid = structureAt(col, row, lx, ly);
        match layer {
            case Layer.Void =>
                if (solid) packArgb(255, (92, 100, 92)) else packArgb(255, rgbOf(t#voidC))
            case _          =>
                if (not solid) packArgb(255, rgbOf(t#voidC))
                else {
                    let s = stageOf(t, col, row, lx, ly);
                    let c = match layer {
                        case Layer.Ground  => s#ground
                        case Layer.Arch    => s#arch
                        case Layer.Weather => s#weather
                        case Layer.Light   => s#light
                        case _             => s#full
                    };
                    packArgb(255, c)
                }
        }

    /// 材質チャーで材質手続きへ分岐。石は文脈で床/壁/枠、'w' は蜘蛛の巣セルだけ web ランプ。
    def stageOf(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32): Stg =
        let gx = col * cell() + lx;
        let gy = row * cell() + ly;
        match maskCharAt(col, row, lx, ly) {
            case 'w' => if (isWebCell(col, row)) webStages(t, gx, gy) else waterStages(t, gx, gy)
            case 'k' => woodStages(t, gx, gy)
            case 'm' => metalStages(t, gx, gy)
            case 'b' => boneStages(t, gx, gy)
            case 'p' => plantStages(t, gx, gy)
            case 's' =>
                match stoneContext(col, row) {
                    case StoneKind.Floor  => floorStages(t, gx, gy)
                    case StoneKind.Coping => copingStages(t, gx, gy)
                    case StoneKind.Wall   => wallFaceStages(t, col, row, gx, gy, ly)
                }
            case _   =>
                let v = rgbOf(t#voidC);
                { ground = v, arch = v, weather = v, light = v, full = v }
        }

    // ════════════════════════════════════════════════════════
    // 石割りユーティリティ（周回レンガ規律 = TileLint wrapBrick が検査）
    // ════════════════════════════════════════════════════════
    def circDistCuts(v: Int32, cuts: List[Int32], period: Int32): Int32 =
        List.foldLeft((acc, c) -> {
            let d = Int32.abs(v - c);
            Int32.min(acc, Int32.min(d, period - d))
        }, period, cuts)

    def stoneId(v: Int32, cuts: List[Int32]): Int32 =
        List.count(c -> c <= v, cuts)

    pub def railCuts(): List[Int32]    = 4 :: 13 :: 22 :: Nil
    pub def faceCuts(): List[Int32]    = 6 :: 19 :: Nil
    pub def soldierCuts(): List[Int32] = 3 :: 8 :: 13 :: 18 :: 23 :: Nil

    pub def wrapStoneWidths(cuts: List[Int32], tiles: Int32): List[Int32] =
        let p = cell();
        let allCuts = List.flatMap(t -> List.map(c -> c + t * p, cuts), List.range(0, tiles)) |> List.sort;
        List.zip(allCuts, List.drop(1, allCuts)) |> List.map(pair -> { let (a, b) = pair; b - a })

    /// lyt の 1 つ上が横目地か（= 石の天辺行 → 1px 上辺ハイライトの位置）。
    def belowCut(lyt: Int32, cuts: List[Int32]): Bool =
        List.exists(c -> Int32.modulo(lyt - 1 - c, cell()) == 0, cuts)

    // ════════════════════════════════════════════════════════
    // 材質手続き（量子化: 出力は必ずランプの段。中間色を作らない）
    // ════════════════════════════════════════════════════════

    /// マスク行の構造画素数（'#' 以外）。壁の「全幅の帯（笠石/レール）」と「柱」の判別に使う。
    def maskRowSolidCount(col: Int32, row: Int32, ly: Int32): Int32 =
        match tracedMask(col, row) {
            case None       => 0
            case Some(mask) =>
                match List.nth(ly, mask) {
                    case None         => 0
                    case Some(rowStr) =>
                        List.range(0, cell()) |> List.count(i -> String.charAt(i, rowStr) != '#')
                }
        }

    // ── 石: 壁 ── 原本の規律をデータ駆動で再現: マスク行がほぼ全幅（≥18px）の帯 = 丸石コブル、
    // 幅の狭い行（柱・稜）= 縦石（soldier）。fire テーマは目地にまばらな ember（発光橙・控えめ）。
    def wallFaceStages(t: Theme, col: Int32, row: Int32, gx: Int32, gy: Int32, ly: Int32): Stg =
        if (maskRowSolidCount(col, row, ly) >= 18) bandCobbleStages(t, gx, gy)
        else pillarBrickStages(t, gx, gy)

    /// 横方向で最も近い虚空（'#'）までの距離（1..cap。cap=そばに刻みなし）。
    /// 原本トレースの石割り（マスクの '#' 刻み）に整列したシェーディングの物差し。
    def distToVoidH(gx: Int32, gy: Int32, cap: Int32): Int32 =
        List.range(1, cap)
            |> List.findLeft(d -> charAtGlobal(gx - d, gy) == '#' or charAtGlobal(gx + d, gy) == '#')
            |> Option.getWithDefault(cap)

    /// 帯（笠石/レール）の丸石: 手続き目地を置かず、原本トレースの刻み（'#'）に整列してドームを付ける。
    /// 刻みの隣 1px=縁の暗・上が虚空でかつ刻みから離れた中央=ドーム頂の明・下が虚空=裾の影。
    /// 石ごとの明度はブロックハッシュ（塊で振る）。二重石割りを避けるのが眼目。
    def bandCobbleStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let dh0 = distToVoidH(gx, gy, 4);
        let nx = circDistCuts(Int32.modulo(gx, cell()), railCuts(), cell());
        // 刻みが近くに無い区間だけ手続き分割（railCuts 9px）で石を切る。刻みと二重にしない。
        let procGrout = dh0 >= 4 and nx == 0;
        let dh = Int32.min(dh0, nx + 1);
        let voidAbove = charAtGlobal(gx, gy - 1) == '#';
        let voidBelow = charAtGlobal(gx, gy + 1) == '#';
        let j = hash01(gx / 8, gy / 10, 53);
        let base = 2 + (if (j > 0.55) 1 else 0);             // 2..3
        let idx0 =
            if (voidAbove and dh >= 2) base + 1              // ドーム頂（石の上面中央）
            else if (voidBelow or dh == 1) base - 1          // 裾・刻み際は暗
            else base;
        let idx = Int32.max(1, Int32.min(4, idx0));
        let emberOn = t#ember != 0 and dh <= 1 and hash01(gx / 5, gy / 5, 97) < 0.25;
        let full =
            if (emberOn) rgbOf(t#ember)
            else if (procGrout) rampAt(t#stone, 0)
            else rampAt(t#stone, idx);
        { ground = rampAt(t#stone, base), arch = full, weather = full,
          light = neutralRelief(if (procGrout) 0.6 else if (idx > base) 1.2 else if (idx < base) 0.8 else 1.0),
          full = full }

    /// 柱・稜の縦石（soldier）: 5px 縦石（soldierCuts）× 4 段コース・天辺行 +1・目地=最暗。
    def pillarBrickStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let p = cell();
        let cutsY = 4 :: 10 :: 16 :: 22 :: Nil;
        let lyt = Int32.modulo(gy, p);
        let courseIdx = stoneId(lyt, cutsY);
        let ny = circDistCuts(lyt, cutsY, p);
        let lxt = Int32.modulo(gx, p);
        let sidx = stoneId(lxt, soldierCuts());
        let nx = circDistCuts(lxt, soldierCuts(), p);
        let mortar = nx == 0 or ny == 0;
        let jj = hash01(sidx + (gx / p) * 5, courseIdx + (gy / p) * 7, 7);
        let baseIdx = 1 + qIdx(jj, 3);                       // 1..3
        let idx = if (belowCut(lyt, cutsY)) Int32.min(4, baseIdx + 1) else baseIdx;
        let emberOn = t#ember != 0 and hash01(gx / 5, gy / 5, 97) < 0.12;
        let grout = if (emberOn) rgbOf(t#ember) else rampAt(t#stone, 0);
        let full = if (mortar) grout else rampAt(t#stone, idx);
        { ground = rampAt(t#stone, baseIdx), arch = full, weather = full,
          light = neutralRelief(if (mortar) 0.6 else if (idx > baseIdx) 1.2 else 1.0), full = full }

    // ── 石: 床（石畳・静かに）── 13px スラブ 2×2/26 の静かな大石。セル境界の暗線は原本トレースの
    // 虚空が既に持つため、手続き目地は中央の 1 本だけ（cuts=13。二重グリッド化させない）。
    // 交点は角丸めの暗ブロック・内部はフラット（石ごとに段 1..2）・フレックは極少。
    def floorStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let p = cell();
        let cuts = 13 :: Nil;
        let lxt = Int32.modulo(gx, p);
        let lyt = Int32.modulo(gy, p);
        let sidx = stoneId(lxt, cuts) + (gx / p) * 2;
        let sidy = stoneId(lyt, cuts) + (gy / p) * 2;
        let j = hash01(sidx, sidy, 61);
        let baseIdx = if (j < 0.25) 1 else 2;
        let fleck = hash01(gx, gy, 67) < 0.015;
        let idx = if (fleck) 3 else baseIdx;
        let nx = circDistCuts(lxt, cuts, p);
        let ny = circDistCuts(lyt, cuts, p);
        let atSeam = nx == 0 or ny == 0;
        let corner = nx <= 1 and ny <= 1;                    // 交点の角丸め（スラブの丸い角）
        let full = if (atSeam or corner) rampAt(t#stone, 0) else rampAt(t#stone, idx);
        { ground = rampAt(t#stone, baseIdx), arch = full, weather = full,
          light = neutralRelief(if (atSeam or corner) 0.7 else 1.0), full = full }

    // ── 石: 枠石（コーピング）── 水を囲う縁石。壁より暗い段 1..2・天辺行 +1・目地=最暗段。
    def copingStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let p = cell();
        let cuts = 3 :: 10 :: 16 :: 23 :: Nil;
        let lxt = Int32.modulo(gx, p);
        let lyt = Int32.modulo(gy, p);
        let sidx = stoneId(lxt, cuts) + (gx / p) * 5;
        let sidy = stoneId(lyt, cuts) + (gy / p) * 5;
        let j = hash01(sidx, sidy, 71);
        let baseIdx = 1 + (if (j > 0.55) 1 else 0);          // 1..2
        let idx = if (belowCut(lyt, cuts)) Int32.min(3, baseIdx + 1) else baseIdx;
        let nx = circDistCuts(lxt, cuts, p);
        let ny = circDistCuts(lyt, cuts, p);
        let atSeam = nx == 0 or ny == 0;
        let full = if (atSeam) rampAt(t#stone, 0) else rampAt(t#stone, idx);
        { ground = rampAt(t#stone, baseIdx), arch = full, weather = full,
          light = neutralRelief(if (atSeam) 0.6 else 1.0), full = full }

    // ── 水 ── 基調 0/1 のゆらぎ・横方向のさざ波ダッシュ 2・まばらなきらめき 3。
    // 泡リム 4 は上に枠石があるときだけ（原本の水面上縁の淡い泡）。左右の枠際はまばらな明 2、
    // 全周を連続リムにしない（輪郭線に見える淡さの原因）。
    def waterStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let stoneUp = charAtGlobal(gx, gy - 1) == 's';
        let stoneSide = charAtGlobal(gx - 1, gy) == 's' or charAtGlobal(gx + 1, gy) == 's';
        let streak = tri((Int32.toFloat64(gx) * 0.7 + Int32.toFloat64(gy) * 2.1
                          + hash01(0, gy, 83) * 6.0) / 7.0);
        let baseIdx = if (streak < 0.35) 0 else 1;
        let ripple = hash01(gx / 7, gy, 91) < 0.10;          // 横に走る短いダッシュ
        let sparkle = hash01(gx, gy, 89) > 0.996;
        let idx =
            if (stoneUp) 4
            else if (stoneSide and hash01(gx, gy, 93) < 0.45) 2
            else if (sparkle) 3
            else if (ripple) 2
            else baseIdx;
        let full = rampAt(t#water, idx);
        { ground = rampAt(t#water, baseIdx), arch = full, weather = full,
          light = neutralRelief(if (stoneUp) 1.3 else 1.0), full = full }

    // ── 木（板）── 列ごとの縦グレイン 0..2・まばらな明スジ・節=最暗段。
    def woodStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let grain = hash01(gx, 0, 31);
        let baseIdx = if (grain < 0.18) 0 else if (grain < 0.80) 1 else 2;
        let streak = hash01(gx, gy / 5, 37) > 0.88;
        let knot = hash01(gx / 3, gy / 4, 39) < 0.05;
        let idx = if (streak) 2 else if (knot) 0 else baseIdx;
        let full = rampAt(t#wood, idx);
        { ground = rampAt(t#wood, baseIdx), arch = full, weather = full,
          light = neutralRelief(if (streak) 1.2 else 1.0), full = full }

    // ── 金属（棒/鋲）── 暗鉄 1 にまばらな光沢 2・影 0。
    def metalStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let sheen = hash01(gx, gy, 43);
        let idx = if (sheen > 0.90) 2 else if (sheen < 0.18) 0 else 1;
        let full = rampAt(t#metal, idx);
        { ground = rampAt(t#metal, 1), arch = full, weather = full,
          light = neutralRelief(if (idx == 2) 1.3 else 1.0), full = full }

    // ── 骨 ── 塊ハッシュで 1..3・暗斑 0。
    def boneStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let j = hash01(gx / 2, gy / 2, 51);
        let baseIdx = 1 + qIdx(j, 3);                        // 1..3
        let dk = hash01(gx / 2, gy / 2, 53) < 0.15;
        let idx = if (dk) 0 else baseIdx;
        let full = rampAt(t#bone, idx);
        { ground = rampAt(t#bone, 1), arch = full, weather = full,
          light = neutralRelief(if (dk) 0.75 else 1.1), full = full }

    // ── 植物（蔓）── 塊ハッシュで 0..2。
    def plantStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let j = hash01(gx / 2, gy / 2, 57);
        let idx = if (j < 0.25) 0 else if (j < 0.75) 1 else 2;
        let full = rampAt(t#plant, idx);
        { ground = rampAt(t#plant, 1), arch = full, weather = full,
          light = neutralRelief(if (idx == 2) 1.15 else 1.0), full = full }

    // ── 蜘蛛の巣 ── 淡ランプの糸。基調 1・明スジ 2/3・影 0（green では全段 water 分類域の淡 teal）。
    def webStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let j = hash01(gx, gy, 63);
        let idx = if (j > 0.85) 3 else if (j > 0.60) 2 else if (j < 0.15) 0 else 1;
        let full = rampAt(t#web, idx);
        { ground = rampAt(t#web, 1), arch = full, weather = full,
          light = neutralRelief(1.0), full = full }

}
