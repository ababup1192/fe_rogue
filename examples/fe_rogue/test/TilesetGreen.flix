// TilesetGreen — 手続きタイルセット生成器 v7（純粋・決定論・全108セル・固定ランプ量子化・線画レイヤー・テーマ差替）。
//
// v5 で確立した最低保証（全 108 セルを原本実測の材質辞書でトレースし、シルエット/材質の二重 XOR を
// ワーストセルで assert）の上に、v6 は「パキッと感」とテーマ展開を、v7 は「線画（意図を持った輪郭・段差線）」を載せる:
//
//   1. 固定ランプ量子化: 原本はアトラス全体で実測 31 色しかないドット絵。手続き陰影が連続階調の
//      中間色を量産すると少色数規律が崩れて淡くぼやける。よって各材質の出力は 3〜5 段の固定ランプ
//      （目地/最暗 → 影 → 地 → 光 → 最明）に量子化し、連続値（ハッシュ・ドーム）は段の選択にだけ使う。
//      緑テーマのランプは原本の実測色そのもの。
//   2. 線画レイヤー（v7・本丸）: 原本ドット絵は「最暗段の線で形を宣言し、中を塗る」構造。塗りだけでは
//      形が締まらず階段・窓・アーチが潰れる。そこでトレース階層を 虚空 → 材質領域 → 線画 → 塗り に拡張: jargon-ok: 建物のドット絵に描く実在の窓（建築要素）で UI/clip/ビューポートの用法ではない
//      各材質の最暗段に落ちる画素（構造内の輪郭・段差・意図的な目地線。原本で ~20% を占める設計線）を
//      tracedMask に大文字チャーとしてデータ化する。描画順は「量子化ランプで塗る（塗りは最暗段を出さない）
//      → 線画をテーマ最暗色で上描き」。線画の位置は絵の設計ゆえテーマ非依存・色だけテーマで変わる。
//      塗り側の手続き目地を廃したので二重グリッドにならない。
//   3. テーマ差替（Theme レコード）: 材質領域マップ・線画（形）はテーマ共通、材質ランプだけ差し替える。
//      green=原本実測 / fire=黒玄武岩+溶岩 / forest=苔石+青水 / ruins=砂岩+濁り水。
//      「石で囲われた水」の役割分離により、枠=石系ランプ・中身=液体系ランプが独立に切り替わる。
//
//   形・材質・線画 = tracedMask: (col,row) -> 26×26 チャー（小文字=材質塗り・大文字=同材質の線画画素）
//   材質辞書       = classify(argb): 実測 31 色を 虚空/石/水/木/金属/骨/植物 に分類する閾値関数。
//                    水際の淡緑（泡）は teal 寄り実測により水へ（蔓の真緑 b-r≤9 とは b-r で分離）。
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
    // テーマ（材質ランプ + モチーフ画家。形=材質領域マップはテーマ共通）
    // ════════════════════════════════════════════════════════
    /// 塗りの流儀。石領域（線画マスクで区切った連結成分）を 1 単位に見立てて、
    /// 内部の線と塗りをどう描くかを選ぶ。Lamp は材質ランプ＋立体面シェーディング。
    /// 以下のモチーフは同じシルエット・材質領域を共有したまま「形を真似て見せ方を変える」。
    pub enum MotifKind {
        case Lamp        // 原本忠実再現（材質ランプ＋作業A の立体面シェーディング。green）
        case Flower      // お花畑（作業B のセル別設計。花/蕾/葉/茎/草/蔓をセルごとに構成）
    }

    /// 各ランプは暗→明の固定段。stone/water は 5 段（0=目地/最暗 .. 4=最明/泡）、
    /// wood/metal/plant は 3 段、bone/web は 4 段。ember は石目地の発光色（0=なし・fire 用）。
    /// accentA/B/C はモチーフ画家の主役色（花芯 / 発光目地・リベット / 蝶・サボテン等）。
    /// Lamp テーマでは accent は未使用（0 で埋める）。
    pub type alias Theme = {
        name    = String,
        motif   = MotifKind,
        stone   = List[Int32],
        water   = List[Int32],
        wood    = List[Int32],
        metal   = List[Int32],
        bone    = List[Int32],
        plant   = List[Int32],
        web     = List[Int32],
        ember   = Int32,
        accentA = Int32,
        accentB = Int32,
        accentC = Int32,
        voidC   = Int32
    }

    /// green = 原本 tileset_dungeon_green.png の実測 31 色から組んだランプ（再現の基準テーマ）。
    pub def themeGreen(): Theme = {
        name    = "green",
        motif   = MotifKind.Lamp,
        stone   = 0x2d2f37 :: 0x373e3f :: 0x424949 :: 0x475752 :: 0x5a6763 :: Nil,
        water   = 0x293e3f :: 0x2b4644 :: 0x3d6056 :: 0x486f62 :: 0x62967e :: Nil,
        wood    = 0x472a22 :: 0x5a392c :: 0x6f4a37 :: Nil,
        metal   = 0x2c2934 :: 0x302d37 :: 0x3a3642 :: Nil,
        bone    = 0x423f3d :: 0x5e5956 :: 0x746f6c :: 0x8b8582 :: Nil,
        plant   = 0x18381d :: 0x28562e :: 0x3c7638 :: Nil,
        web     = 0x3d6056 :: 0x486f62 :: 0x62967e :: 0x95c5a3 :: Nil,
        ember   = 0,
        accentA = 0, accentB = 0, accentC = 0,
        voidC   = 0x19201a
    }

    // ── モチーフテーマ（形＝シルエット/材質領域は共有・内部の塗りをセル別設計で差し替える）──

    /// flower_field = お花畑（作業B）。石領域をセルごとに花/蕾/葉/茎/草/蔓で装飾する。
    /// stone=花弁ランプ・bone=白花・plant=草/葉・wood=茎/蔓・water=池・accentA/B/C=花芯。
    pub def themeFlower(): Theme = {
        name    = "flower",
        motif   = MotifKind.Flower,
        stone   = 0x7a2f4a :: 0x9c3d5e :: 0xc25278 :: 0xdd7396 :: 0xf0a6c0 :: Nil,  // 花弁（暗→明）
        water   = 0x214a6e :: 0x2f6a9c :: 0x4a90c0 :: 0x74b4dc :: 0xa8d8f0 :: Nil,  // 澄んだ池
        wood    = 0x2e4a1e :: 0x3e5e26 :: 0x527a34 :: Nil,                          // 蔓/茎
        metal   = 0x5a2f6e :: 0x7a3f92 :: 0x9c58b4 :: Nil,                          // 紫花（稀）
        bone    = 0xd0d0c0 :: 0xe4e4d4 :: 0xf0f0e8 :: 0xffffff :: Nil,              // 白い小花
        plant   = 0x1e4a1e :: 0x2e6e2e :: 0x46a046 :: Nil,                          // 草
        web     = 0xc0a0d0 :: 0xd4b8e0 :: 0xe8d4f0 :: 0xfff0ff :: Nil,              // 蝶（淡）
        ember   = 0,
        accentA = 0xf2c033, accentB = 0xfff0a0, accentC = 0xf0f0f0,                 // 花芯/芯明/白
        voidC   = 0x1c2418
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

    /// 線画チャー（大文字 = 塗りの最暗段で締める輪郭・段差・目地の画素）を材質チャー（小文字）へ落とす。
    /// 線画は「塗りのどこを最暗段で締めるか」の設計データで、材質そのものは塗りと同じ（材質 XOR に影響しない）。
    def baseChar(ch: Char): Char = match ch {
        case 'S' => 's'
        case 'W' => 'w'
        case 'K' => 'k'
        case 'M' => 'm'
        case 'B' => 'b'
        case 'P' => 'p'
        case _   => ch
    }

    /// 線画画素か（tracedMask の大文字 = 最暗段で締める輪郭/段差/目地）。
    def isLineChar(ch: Char): Bool =
        ch == 'S' or ch == 'W' or ch == 'K' or ch == 'M' or ch == 'B' or ch == 'P'

    /// 材質チャー → 材質。tracedMask のチャーと classify の値を一致させる橋。線画チャー（大文字）は塗りと同材質。
    pub def charMaterial(ch: Char): Material = match baseChar(ch) {
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
    // 大文字（S/W/K/M/B/P）は同材質の「線画画素」= 原本でその材質の最暗段に落ちる画素（構造内の輪郭・
    // 段差・意図的な目地線。虚空 '#' とは別物）。原本は既に各材質 4〜5 段に量子化されており、最暗段は
    // ちょうど面積の ~20%（石で 20%）を占める設計線。この一段をデータとして持ち、塗りは最暗段を出さず、
    // 線画画素だけをテーマ最暗色で締める（手続き目地は廃し二重グリッドを断つ）。線画は蜘蛛の巣セルには
    // 置かない（糸は webStages が淡ランプで描く）。
    // 原本が全面虚空のセル（c6/r1・c10/r8・c11/r8）だけ None（全面虚空で塗る・case _ で受ける）。
    // 形（シルエット）も材質も線画もこの一枚のデータで決まる。多セル建築（中央アーチ門 c3-6/r4 等）は
    // 原本の連続画像から切り出しているため、隣接セルのマスクが自然に整合する。
    pub def tracedMask(col: Int32, row: Int32): Option[List[String]] =
        match (col, row) {
            case (0, 0) => Some(
                "#ssssssSsssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "Ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssSssssssssssssssssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "#SsssSS##SsssssSSSS###SssS" ::
                "#ssssss###SSSSSSSSSS###SSS" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS###########sssssss" ::
                "#ssssss############sssssss" ::
                "#SsSssS###########Ssssssss" ::
                "#ssssss###########Ssssssss" ::
                "#ssssssS###########sssssss" ::
                "#ssssssS##########Ssssssss" ::
                "#ssssssS##########Ssssssss" ::
                "Sssssss#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "#SssSsS###########SssssssS" ::
                "Sssssss############ssssssS" ::
                "#ssssss###########SssssssS" ::
                "#ssssss###########Sssssss#" ::
                Nil)
            case (1, 0) => Some(
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "#SSSS#####SSSSSSSSSS###SSS" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "##SsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (2, 0) => Some(
                "sssssssSSsssssssssSssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssssS" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "SSssSS###SSssssSS##SsssSS#" ::
                "#SSSS#####SSSSSS###ssssssS" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssss############ssssss#" ::
                "sssssssS###########SsSssS#" ::
                "sssssssS###########ssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssssS###########ssssss#" ::
                "sssssssS###########ssssss#" ::
                "##SsssS###########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "SssssssS###########SssSsS#" ::
                "#ssssssS###########ssssss#" ::
                "SssssssS###########ssssss#" ::
                "Sssssss############ssssssS" ::
                Nil)
            case (3, 0) => Some(
                "#ssssssSSssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "Ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssSssssssssssssssssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "#SsssSS###SSSsssssSSS##SSS" ::
                "#ssssss##SSSSSSSSSSS####SS" ::
                "#ssssss##################S" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "#ssssss###################" ::
                "#SsSssS###################" ::
                "#ssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "#ssssss###################" ::
                "#SssSsS###################" ::
                "Sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (4, 0) => Some(
                "sssssss#SsssssssssSssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssssS" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSsssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "SsssSS###SsssssSS##SsssSS#" ::
                "SSSS####SSSSSSSS###ssssssS" ::
                "SS#################ssssss#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SsSssS#" ::
                "###################ssssssS" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SssSsS#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssssS" ::
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
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "####################SsssS#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "###################ssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
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
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
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
                "sssssssS##################" ::
                "sssssssS##################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "##SsssS###################" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "Sssssss###################" ::
                Nil)
            case (8, 0) => Some(
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "#SSSS#####SSSSSSSSSS###SSS" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "####################SsssS#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "###################ssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                Nil)
            case (9, 0) => Some(
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "#SSSS#####SSSSSSSSSS###SSS" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "##SsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (10, 0) => Some(
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "#SSSS#####SSSSSSSSSS###SSS" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "##SsssS###################" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "Sssssss###################" ::
                Nil)
            case (11, 0) => Some(
                "#ssssssSSsssssssssSssssss#" ::
                "#ssssssSssssssssssSssssss#" ::
                "SsssssssssssssssssSssssss#" ::
                "SssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssSsssssssssssssssss#" ::
                "SssssssSssssssssssSssssss#" ::
                "#SsssSS##SSssssSS##SsssSS#" ::
                "#ssssss##SSSSSSS###ssssssS" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS##########SssssssS" ::
                "SssssssS##########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#SsSssS############SsSssS#" ::
                "#ssssss############ssssssS" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS###########ssssss#" ::
                "Sssssss###########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#SssSsS############SssSsS#" ::
                "Sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssssS" ::
                Nil)
            case (0, 1) => Some(
                "#ssssssS###########sssssss" ::
                "#ssssssS###########ssssssS" ::
                "Sssssss###########SssssssS" ::
                "Sssssss###########Ssssssss" ::
                "#ssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "#ssssss############SSssSS#" ::
                "#SsssSS#############SSSSS#" ::
                "#sssssS###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssss###################" ::
                "#ssssss#SssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "SssssssSssssssssssssssssss" ::
                "SssssssSsssssssssssssSssss" ::
                "#ssssss#Sssssssssssss#ssss" ::
                "#ssssss#ssssssssssssS#ssss" ::
                "#ssssssSssssssssssssS#ssss" ::
                "#sssssS#ssssssssssssSSssss" ::
                "#ssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (1, 1) => Some(
                "Sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########Sssssss#" ::
                "sssssss###########SssssssS" ::
                "sssssssS###########ssssss#" ::
                "sssssssS###########ssssss#" ::
                "Sssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (2, 1) => Some(
                "Sssssss############ssssss#" ::
                "sssssssS##########Sssssss#" ::
                "sssssss###########Sssssss#" ::
                "SssssssS###########ssssssS" ::
                "SssssssS###########ssssssS" ::
                "SssssssS###########ssssss#" ::
                "#SSsssS############ssssss#" ::
                "##SSSS#############SsssSS#" ::
                "##################Sssssss#" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#Ssssssssss#ssssssS" ::
                "sssssssSssssssssssSssssssS" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSsssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "sssssss#Ssssssssss#ssssss#" ::
                "sssssss#sssssssssS#ssssssS" ::
                "sssssssSsssssssssS#ssssssS" ::
                "ssssssS#sssssssssSSssssss#" ::
                "sssssSS#SSSSssSSS##Ssssss#" ::
                "#SS########SSS######SSS###" ::
                Nil)
            case (3, 1) => Some(
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "Sssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#SsssSS###################" ::
                "#sssssS###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssss###################" ::
                "#ssssss#SssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "SssssssSssssssssssssssssss" ::
                "SssssssSsssssssssssssSssss" ::
                "#ssssss#Sssssssssssss#ssss" ::
                "#ssssss#ssssssssssssS#ssss" ::
                "#ssssssSssssssssssssS#ssss" ::
                "#sssssS#ssssssssssssSSssss" ::
                "#ssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (4, 1) => Some(
                "###################ssssss#" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################SsssSS#" ::
                "##################Sssssss#" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#Ssssssssss#ssssssS" ::
                "sssssssSssssssssssSssssssS" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSsssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "sssssss#Ssssssssss#ssssss#" ::
                "sssssss#sssssssssS#ssssssS" ::
                "sssssssSsssssssssS#ssssssS" ::
                "ssssssS#sssssssssSSssssss#" ::
                "sssssSS#SSSSssSSS##Ssssss#" ::
                "#SS########SSS######SSS###" ::
                Nil)
            case (5, 1) => Some(
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################Sssssss#" ::
                "##################SssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################SsssSS#" ::
                "###################ssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SsSssS#" ::
                "###################ssssssS" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SssSsS#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssssS" ::
                Nil)
            case (7, 1) => Some(
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#SsssSS###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "#ssssss###################" ::
                "#SsSssS###################" ::
                "#ssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "Sssssss###################" ::
                "#ssssss###################" ::
                "#SssSsS###################" ::
                "Sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (8, 1) => Some(
                "###################ssssssS" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################SsssSS#" ::
                "###################SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (9, 1) => Some(
                "Sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########Sssssss#" ::
                "sssssss###########SssssssS" ::
                "sssssssS###########ssssss#" ::
                "sssssssS###########ssssss#" ::
                "Sssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (10, 1) => Some(
                "Sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "Sssssss###################" ::
                "#SsssSS###################" ::
                "##SSSS####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (11, 1) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "Sssssss###########Sssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS###########ssssss#" ::
                "#ssssssS###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "#ssssss############ssssssS" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS##########SssssssS" ::
                "SssssssS##########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#SsSssS############SsSssS#" ::
                "#ssssss############ssssssS" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS###########ssssss#" ::
                "Sssssss###########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#SssSsS############SssSsS#" ::
                "Sssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss############ssssssS" ::
                Nil)
            case (0, 2) => Some(
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssss###################" ::
                "#SsssSS###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "SssssssS###########sssssss" ::
                "#ssssss############sssssss" ::
                "#SsSssS###########Ssssssss" ::
                "#ssssss###########Ssssssss" ::
                "#ssssssS###########sssssss" ::
                "#ssssssS##########Ssssssss" ::
                "#ssssssS##########Ssssssss" ::
                "Sssssss#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "#SssSsS###########SssssssS" ::
                "Sssssss############ssssssS" ::
                "#ssssss###########SssssssS" ::
                "#ssssss###########Sssssss#" ::
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
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "##SsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (2, 2) => Some(
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################Sssssss#" ::
                "##################SssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################SsssSS#" ::
                "###################ssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssss############ssssss#" ::
                "sssssssS###########SsSssS#" ::
                "sssssssS###########ssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssssS##########Sssssss#" ::
                "sssssssS###########ssssss#" ::
                "#SSsssS###########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "SssssssS###########SssSsS#" ::
                "#ssssssS###########ssssss#" ::
                "SssssssS###########ssssss#" ::
                "Sssssss############ssssssS" ::
                Nil)
            case (3, 2) => Some(
                "Sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "Sssssss###################" ::
                "#SsssSS###################" ::
                "##SSSS####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "####################SsssS#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "###################ssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                Nil)
            case (4, 2) => Some(
                "###################ssssssS" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################SsssSS#" ::
                "###################SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "##SsssS###################" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "Sssssss###################" ::
                Nil)
            case (5, 2) => Some(
                "###################ssssssS" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################SsssSS#" ::
                "###################SSSSS##" ::
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
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "#SSSS#####SSSSSSSSSS###SSS" ::
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
                "Sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "Sssssss###################" ::
                "#SsssSS###################" ::
                "##SSSS####################" ::
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
                "#ssssssSSssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "Ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssSssssssssssssssssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "#SsssSS###SSSsssssSSS##SSS" ::
                "#sssssS##SSSSSSSSSSS####SS" ::
                "Sssssss##################S" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssss###################" ::
                "#ssssss#SssssssssssssSssss" ::
                "#ssssssSsssssssssssssSssss" ::
                "SssssssssssssssssssssSssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "SssssssSssssssssssssssssss" ::
                "SssssssSsssssssssssssSssss" ::
                "#ssssss#Sssssssssssss#ssss" ::
                "#ssssss#ssssssssssssS#ssss" ::
                "#ssssssSssssssssssssS#ssss" ::
                "#sssssS#ssssssssssssSSssss" ::
                "#ssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (9, 2) => Some(
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "SSssSS###SSssssSSSS###SssS" ::
                "SSSSS#####SSSSSSSSSS###SSS" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssssSSssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssssssssssssssssSssss" ::
                "ssssssssssssssssssssssssss" ::
                "ssssssssssssssssssssssssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssss#Sssssssssssss#ssss" ::
                "sssssss#ssssssssssssS#ssss" ::
                "sssssssSssssssssssssS#ssss" ::
                "ssssssS#ssssssssssssSSssss" ::
                "sssssSS#SSSSssssSSSS##Ssss" ::
                "#SS########SSS#########SS#" ::
                Nil)
            case (10, 2) => Some(
                "sssssss#SsssssssssSssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssssS" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSsssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "SsssSS###SsssssSS##SsssSS#" ::
                "SSSS####SSSSSSSS##Sssssss#" ::
                "SS################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "sssssss#Ssssssssss#ssssssS" ::
                "sssssssSssssssssssSssssssS" ::
                "ssssssssssssssssssSssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssssssssssssssssssss#" ::
                "sssssssSsssssssssssssssss#" ::
                "sssssssSssssssssssSssssss#" ::
                "sssssss#Ssssssssss#ssssss#" ::
                "sssssss#sssssssssS#ssssssS" ::
                "sssssssSsssssssssS#ssssssS" ::
                "ssssssS#sssssssssSSssssss#" ::
                "sssssSS#SSSSssSSS##Ssssss#" ::
                "#SS########SSS######SSS###" ::
                Nil)
            case (11, 2) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "Sssssss###########Sssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS###########ssssss#" ::
                "#ssssssS###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "#sssssS###########Sssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss#Ssssssssss#ssssssS" ::
                "#ssssssSssssssssssSssssssS" ::
                "SsssssssssssssssssSssssss#" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssss#" ::
                "SssssssSsssssssssssssssss#" ::
                "SssssssSssssssssssSssssss#" ::
                "#ssssss#Ssssssssss#ssssss#" ::
                "#ssssss#sssssssssS#ssssssS" ::
                "#ssssssSsssssssssS#ssssssS" ::
                "#sssssS#sssssssssSSssssss#" ::
                "#ssssSS#SSSSssSSS##Ssssss#" ::
                "#SS########SSS######SSS###" ::
                Nil)
            case (0, 3) => Some(
                "#ssssss############ssssss#" ::
                "#ssssss############ssssss#" ::
                "Sssssss###########Sssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS###########ssssss#" ::
                "#ssssssS###########ssssss#" ::
                "#ssssss############ssssss#" ::
                "#SsssSS############SSsssS#" ::
                "#ssssss#############SSSSS#" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "SssssssS###########sssssss" ::
                "#ssssss############sssssss" ::
                "#SsSssS###########Ssssssss" ::
                "#ssssss###########Ssssssss" ::
                "#ssssssS###########sssssss" ::
                "#ssssssS##########Ssssssss" ::
                "#ssssssS##########Ssssssss" ::
                "Sssssss#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "#SssSsS###########SssssssS" ::
                "Sssssss############ssssssS" ::
                "#ssssss###########SssssssS" ::
                "#ssssss###########Sssssss#" ::
                Nil)
            case (1, 3) => Some(
                "Sssssss############ssssssS" ::
                "sssssss############sssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssssS###########sssssss" ::
                "sssssssS###########ssssssS" ::
                "Sssssss############ssssssS" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "#SSsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (2, 3) => Some(
                "Sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########Sssssss#" ::
                "sssssss###########SssssssS" ::
                "sssssssS###########ssssss#" ::
                "sssssssS###########ssssss#" ::
                "Sssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############ssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssss############ssssss#" ::
                "sssssssS###########SsSssS#" ::
                "sssssssS###########ssssssS" ::
                "sssssss###########Sssssss#" ::
                "sssssssS##########Sssssss#" ::
                "sssssssS###########ssssss#" ::
                "#SSsssS###########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "SssssssS###########SssSsS#" ::
                "#ssssssS###########ssssss#" ::
                "SssssssS###########ssssss#" ::
                "Sssssss############ssssssS" ::
                Nil)
            case (3, 3) => Some(
                "###################ssssssS" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################SsssSS#" ::
                "###################SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "####################SsssS#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "###################ssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                Nil)
            case (4, 3) => Some(
                "Sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "Sssssss###################" ::
                "#SsssSS###################" ::
                "##SSSS####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "#SSsssS###################" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "Sssssss###################" ::
                Nil)
            case (5, 3) => Some(
                "Sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "Sssssss###################" ::
                "#SsssSS###################" ::
                "##SSSS####################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "#SSsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (6, 3) => Some(
                "###################ssssssS" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "###################ssssssS" ::
                "###################ssssssS" ::
                "###################SsssSS#" ::
                "###################SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss############sssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssss############sssssss" ::
                "sssssssS##########Ssssssss" ::
                "sssssssS##########Ssssssss" ::
                "#SSsssS#############SsssS#" ::
                "#ssssss############ssssss#" ::
                "SssssssS##########SssssssS" ::
                "#ssssssS###########ssssssS" ::
                "SssssssS##########SssssssS" ::
                "Sssssss###########Sssssss#" ::
                Nil)
            case (7, 3) => Some(
                "Sssssss############ssssssS" ::
                "sssssss############sssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssssS###########sssssss" ::
                "sssssssS###########ssssssS" ::
                "Sssssss############ssssssS" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "###################sssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "###################sssssss" ::
                "##################Ssssssss" ::
                "##################Ssssssss" ::
                "####################SsssS#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "###################ssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                Nil)
            case (8, 3) => Some(
                "Sssssss############ssssssS" ::
                "sssssss############sssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssssS###########sssssss" ::
                "sssssssS###########ssssssS" ::
                "Sssssss############ssssssS" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "sssssss###################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "sssssss###################" ::
                "sssssssS##################" ::
                "sssssssS##################" ::
                "#SSsssS###################" ::
                "#ssssss###################" ::
                "SssssssS##################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "Sssssss###################" ::
                Nil)
            case (9, 3) => Some(
                "#sSS##SssssssssSS####SSS##" ::
                "#sss#Sssssssssssss#Ssssss#" ::
                "Ssss#sssssssssssssSssssssS" ::
                "#sss#sssssssssssssSssssss#" ::
                "#sss#sssSSssssssssSssssss#" ::
                "#sssSsssssssssssssSsssssS#" ::
                "#sssSSSssssSSS##SS#SSsssS#" ::
                "#sSS#SSSsssssSSSS##SSSSSs#" ::
                "#####S#####SS#############" ::
                "#ssssssss#SssssssssssS#ss#" ::
                "SssssssssSssssssssssssSssS" ::
                "#ssssssssSssssssssssssSssS" ::
                "#ssssssssSSsssssssssssSss#" ::
                "SssssssssSSssssssssssS#SS#" ::
                "#sssssssS#SSSssssssSs##Ss#" ::
                "###SssssS#SSSSSssSSSS##ss#" ::
                "##SS#########S###S########" ::
                "#ssss#Ssssssssssss##Sssss#" ::
                "Sssss#SsssssssssssS#SssssS" ::
                "#ssssSsssssssssssss#SssssS" ::
                "#ssssSsssssssssssssSsssss#" ::
                "SsssS#sssssssssssssSsssss#" ::
                "SsssS#ssssssssssssSSssssS#" ::
                "#sSS###ssssSSSSSS###SsssS#" ::
                "#####################SS###" ::
                "#S#####SSS####SSSSS#######" ::
                Nil)
            case (10, 3) => Some(
                "##############SS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SSssssssssssssssssssssssS" ::
                "#SsssssssssssssssssssssssS" ::
                "#Sssssssssssssssssssssssss" ::
                "#sss###S#####SS#######ssss" ::
                "#sss#SsssssssssSSsssS#ssss" ::
                "#sss#SSSssSsssSSSSsSS#ssss" ::
                "Ssss##SSSSSSSSSSSSSS##ssss" ::
                "Ssss##S###SSS##SSSS###ssss" ::
                "Ssss###SS#############ssss" ::
                "Ssss#wwwwwwwwwwwwwwww#ssss" ::
                "#sss#wwwwWWWWWWWWwwww#Ssss" ::
                "#sss#wwwwWwWWSSwwWWww#Ssss" ::
                "Ssss#wwWWwwWwwwwwwWww#Ssss" ::
                "Ssss#wwwwwwwwwwwwwwWw#SssS" ::
                "#sss#wwwwwwwwwwwwwwWw#SssS" ::
                "#sss#wwwwwwwwwwwwwwWw#sssS" ::
                "#sss#wwwwwwwwwwwwwwwwSsssS" ::
                "#sss#wwwwwwwwwwwwwwww#sssS" ::
                "#sss###S########SSS###sssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SsssssssssssssssssssssssS" ::
                "#SSSssssssssssssssssssSsSS" ::
                "#SSsSSSsssssssssssSSSsSSSS" ::
                "SssssSSSSssssSS###SSSSSS##" ::
                Nil)
            case (11, 3) => Some(
                "#ssssssSSsssssssssSssssss#" ::
                "#ssssssSssssssssssSssssss#" ::
                "SsssssssssssssssssSssssss#" ::
                "SssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssSsssssssssssssssss#" ::
                "SssssssSssssssssssSssssss#" ::
                "#SsssSS##SSssssSS##SsssSS#" ::
                "#sssssS##SSSSSSS##Sssssss#" ::
                "Sssssss###########SssssssS" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssssS##########Sssssss#" ::
                "#ssssss############ssssss#" ::
                "#ssssss#Ssssssssss#ssssssS" ::
                "#ssssssSssssssssssSssssssS" ::
                "SsssssssssssssssssSssssss#" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssss#" ::
                "SssssssSsssssssssssssssss#" ::
                "SssssssSssssssssssSssssss#" ::
                "#ssssss#Ssssssssss#ssssss#" ::
                "#ssssss#sssssssssS#ssssssS" ::
                "#ssssssSsssssssssS#ssssssS" ::
                "#sssssS#sssssssssSSssssss#" ::
                "#ssssSS#SSSSssSSS##Ssssss#" ::
                "#SS########SSS######SSS###" ::
                Nil)
            case (0, 4) => Some(
                "#ssssss############ssssssS" ::
                "#ssssss############sssssss" ::
                "Sssssss###########Ssssssss" ::
                "Sssssss###########Ssssssss" ::
                "#ssssssS###########sssssss" ::
                "#ssssssS###########ssssssS" ::
                "#ssssss############ssssssS" ::
                "#SsssSS############SsssSS#" ::
                "#ssssss############SSSSS##" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                "Sssssss###################" ::
                "#ssssssS##################" ::
                "SssssssS##################" ::
                "#ssssss###################" ::
                "#SsSssS###################" ::
                "#ssssss###################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "#ssssssS##################" ::
                "Sssssss###################" ::
                "#ssssss###################" ::
                "#SssSsS###################" ::
                "Sssssss###################" ::
                "#ssssss###################" ::
                "#ssssss###################" ::
                Nil)
            case (1, 4) => Some(
                "Sssssss############ssssssS" ::
                "sssssss############sssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssss###########Ssssssss" ::
                "sssssssS###########sssssss" ::
                "sssssssS###########ssssssS" ::
                "Sssssss############ssssssS" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############SSSSS##" ::
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
                "Sssssss############ssssss#" ::
                "sssssss############ssssss#" ::
                "sssssss###########Sssssss#" ::
                "sssssss###########SssssssS" ::
                "sssssssS###########ssssss#" ::
                "sssssssS###########ssssss#" ::
                "Sssssss############ssssss#" ::
                "#SsssSS############SsssSS#" ::
                "##SSSS#############ssssssS" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "##################SssssssS" ::
                "##################SssssssS" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SsSssS#" ::
                "###################ssssssS" ::
                "##################Sssssss#" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "##################Sssssss#" ::
                "###################ssssss#" ::
                "###################SssSsS#" ::
                "###################ssssss#" ::
                "###################ssssss#" ::
                "###################ssssssS" ::
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
                "#########################S" ::
                "########################ss" ::
                "######################Ssss" ::
                "#####################Sssss" ::
                "####################Ssssss" ::
                "sssssssSSsssssssssS#ssssss" ::
                "sssssssSssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "ssssssssssssssssss#sssssss" ::
                "ssssssssssssssssssSsssssss" ::
                "sssssssSssssssssssSsssssss" ::
                "sssssssSssssssssss#sssssss" ::
                "sssssss#Ssssssssss#sssssss" ::
                "sssssss#ssssssssss##Ssssss" ::
                "sssssssSsssssssssSSSS##Sss" ::
                "ssssssS#sssssssss#sssssS##" ::
                "sssssSS#SSSSssssS#ssssssS#" ::
                "#SS########SSS####SSSssss#" ::
                Nil)
            case (4, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "######SssssssssssssS######" ::
                "###Ss#ssssssssssssssSsS###" ::
                "#Ssss#ssssssssssssss#sssS#" ::
                "sssssSssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssssSsssss" ::
                "sssssSssssssssssssssSsssss" ::
                "sssssSssssssssssssssSsssss" ::
                "ssssssSssssssssssssSssssss" ::
                "ssssss#ssssssssssss#ssssss" ::
                "ssssss##############ssssss" ::
                "ssssS###SS###########Sssss" ::
                "sss####SSssss####SSS###sss" ::
                "ssS####SsssSS###SssSS##Sss" ::
                "s#####SSS##SssS#ssssSS###s" ::
                "S######SSSssssS#ssssSSS##S" ::
                "#######SSssssssSsssssSSS##" ::
                "##SS##SSSssssss#sssssS#S##" ::
                "##SsS#SSsssssss#SSssSS####" ::
                "##ssS##Ssssssss###S###SS##" ::
                Nil)
            case (5, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "######SssssssssssssS######" ::
                "###Ss#ssssssssssssssSsS###" ::
                "#Ssss#ssssssssssssss#sssS#" ::
                "sssssSssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssss#sssss" ::
                "sssss#ssssssssssssssSsssss" ::
                "sssssSssssssssssssssSsssss" ::
                "sssssSssssssssssssssSsssss" ::
                "ssssssSssssssssssssSssssss" ::
                "ssssss#ssssssssssss#ssssss" ::
                "ssssss##############ssssss" ::
                "ssssS################Sssss" ::
                "sss#####SSS##ssssS#####sss" ::
                "ssS####SsS###SSsssS####Sss" ::
                "s####SSsss#SssS##SSS#####s" ::
                "S####Sssss#SssssSSS######S" ::
                "####SsssssSssssssSS#######" ::
                "####Ssssss#ssssssSSS##SS##" ::
                "###SSSssSS#sssssssSS#SsS##" ::
                "#######S###sssssssS##Sss##" ::
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
                "S#########################" ::
                "ss########################" ::
                "sssS######################" ::
                "ssssS#####################" ::
                "sssssS####################" ::
                "ssssssS#SssssssssssssSssss" ::
                "sssssss#sssssssssssssSssss" ::
                "sssssssSsssssssssssssSssss" ::
                "sssssssSssssssssssssssssss" ::
                "sssssss#ssssssssssssssssss" ::
                "ssssssS#ssssssssssssssssss" ::
                "ssssssS#sssssssssssssSssss" ::
                "ssssssS#Sssssssssssss#ssss" ::
                "ssssS###ssssssssssssS#ssss" ::
                "ssS##Ss#SsssssssssssS#ssss" ::
                "##SSsssSSsssssssssssSSssss" ::
                "Ssssssss#SSSssssSSSS##Ssss" ::
                "Ssssssss###SSS#########SS#" ::
                Nil)
            case (7, 4) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "##########SSSSS###########" ::
                "#########SsssssSS#########" ::
                "######SS##sssssssSSS######" ::
                "#####Sssss#sssssS#ssS#####" ::
                "####SssssssSsssSSSssssS###" ::
                "####Ssssssss#Sssss#ssSS###" ::
                "#####ssssssSSsssss#SSS####" ::
                "#####S#sssSSSsssSS#SSSS###" ::
                "###Ssss#SSSS#sssssS#sss###" ::
                "##SssssSsss##sssSSSssssS##" ::
                "##SsssSsssssSssSSS#sssS###" ::
                "###SSS#sssSS##Ssss#ssSS###" ::
                "#############sssssS#######" ::
                "############SsssssSS######" ::
                "#############SssssS#######" ::
                "##############sSsS########" ::
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
                "#sSS##SssssssssSS####SSsss" ::
                "#sss#Sssssssssssss#Sssssss" ::
                "Ssss#sssssssssssssSsssssss" ::
                "#sss#sssssssssssssSsssssss" ::
                "#sss#sssSSssssssssSsssssss" ::
                "#sssSsssssssssssssSsssssSS" ::
                "#sssSSSssssSSS##SS#SSsssSS" ::
                "#sSS#SSSsssssSSSS##SSSSSss" ::
                "#####S#####SS#############" ::
                "#ssssssss#SssssssssssS#sss" ::
                "SssssssssSssssssssssssSsss" ::
                "#ssssssssSssssssssssssSsss" ::
                "#ssssssssSSsssssssssssSsss" ::
                "SssssssssSSssssssssssS#SSs" ::
                "#sssssssS#SSSssssssSs##Sss" ::
                "###SssssS#SSSSSssSSSS##sss" ::
                "##SS#########S###S######S#" ::
                "#ssss#Ssssssssssss##Ssssss" ::
                "Sssss#SsssssssssssS#Ssssss" ::
                "#ssssSsssssssssssss#Ssssss" ::
                "#ssssSsssssssssssssSssssss" ::
                "SsssS#sssssssssssssSssssss" ::
                "SsssS#ssssssssssssSSssssSs" ::
                "#sSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "#S#####SSS####SSSSS#######" ::
                Nil)
            case (1, 5) => Some(
                "ssSS##SsssssSppSS##PppppPS" ::
                "ssss##ssSpppppSsss#SSPppSs" ::
                "ssss#SpppPPPPppSssSssSppss" ::
                "ssss#pP#SSS#PPpSssSssSpPss" ::
                "ssss#pS##sss#PppsSppsSPSss" ::
                "Ssss##SS#ssss#ppsSpSssssSS" ::
                "ssss##SSSssss#pPS#pSSsssSS" ::
                "ssSS##SS#sssSSpP#pP#SSSSss" ::
                "#########SSSSPppP#########" ::
                "sssssSS#######PpsssssS#sss" ::
                "ssssssSSS#Ssss#pssssssSsss" ::
                "ssssssssS#ssssSpssssssSsss" ::
                "ssssssssSSSsssSpssssssSsss" ::
                "sssssssss#SsssSpsssssS#SSs" ::
                "ssssssssS#SSSsSPsssSs##Sss" ::
                "S##SssssS#SSSS#SsSSSS##sss" ::
                "##SS#########S###S######S#" ::
                "sssss#Ssssssssssss##Ssssss" ::
                "sssss#SsssssssssssS#Ssssss" ::
                "sssssSsssssssssSsss#Ssssss" ::
                "sssssSssssssssSS#ssSssssss" ::
                "ssssS#ssssssssS##ssSssssss" ::
                "ssssS#ssssssssssssSSssssSs" ::
                "ssSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (2, 5) => Some(
                "ssSS##SssssssssSS####SSsss" ::
                "ssss#Sssssssssssss#Sssssss" ::
                "ssss#sssssssS#ssssSsssssss" ::
                "ssss#sssssss##ssssSsssssss" ::
                "ssss#sssssssssssssSsssssss" ::
                "SsssSsssssssssssssSsssssSS" ::
                "ssssSSSssssSSS##SS#SSsssSS" ::
                "ssSS#SSSsssssSSSS##SSSSSss" ::
                "#####S#####SS#############" ::
                "sssssssss#SssssssssssS#sss" ::
                "sssssssssSssssssssssssSsss" ::
                "sssssssssSsssSSsssssssSsss" ::
                "sssssssssSSsSKpSssksssSsss" ::
                "sssssssssSSs#kSssk#ssS#SSs" ::
                "ssssssssS#SS#kSssK#Ss##Sss" ::
                "S##SssssS#SS#k#sk#SSS##sss" ::
                "##SS########pk##k#######S#" ::
                "sssss#SssS##kk#kKS##Ssssss" ::
                "sssss#SssS##kpkKSsS#Ssssss" ::
                "sssssSssssp#kK#Ssss#Ssssss" ::
                "sssssSssssSkk#pssssSssssss" ::
                "ssssS#ssss#kKSsssssSssssss" ::
                "ssssS#ssspKk#SssssSSssssSs" ::
                "ssSS###ss#kk#SSSS###SsssSS" ::
                "#########kkKk########SS###" ::
                "SS#####KkK##KK###SS#######" ::
                Nil)
            case (3, 5) => Some(
                "ssSS##SssssssssSS#SSsssss#" ::
                "ssss#Ssssssssssss#SsssssS#" ::
                "ssss#ssssssssssss#####SsS#" ::
                "ssss#ssssssssssss#SssSS###" ::
                "ssss#sssSSssssssSSsssssss#" ::
                "SsssSsssssssssssSSsssssss#" ::
                "ssssSSSssssssssSS#ssssSss#" ::
                "ssSS#SSSsssssSSS##Ssss##S#" ::
                "#####S#####SS#####SsssSSS#" ::
                "sssssssss#Sssssss#SSsssSS#" ::
                "sssssssssSsssssss##S##SS##" ::
                "sssssssssSsssssss#ssssssS#" ::
                "sssssssssSSssssssSsssssss#" ::
                "sssssssssSSssssss#sssssss#" ::
                "ssssssssS#SSSssss#Sssssss#" ::
                "S##SssssS#SSSSSss##SssssS#" ::
                "##SS#########S#####SsssSS#" ::
                "sssss#Sssssssssss####SS###" ::
                "sssss#Sssssssssss#Ssssss##" ::
                "sssssSsssssssssssSssssssS#" ::
                "sssssSsssssssssssSsssssss#" ::
                "ssssS#sssssssssss#sssssss#" ::
                "ssssS#sssssssssss#SssssSs#" ::
                "ssSS###ssssSSSSSS#SssSSSs#" ::
                "###################sSS#SS#" ::
                "SS#####SSS####SSS#########" ::
                Nil)
            case (4, 5) => Some(
                "##ssS##SssssSS##SSssSSsS##" ::
                "#Sss###SssS##SssssssSssS##" ::
                "#SSs###SS##s#ssssssS#sSS##" ::
                "#SS#####SsssSssssssS#SS###" ::
                "#Ss###Ssssss#SssssSSS#####" ::
                "#S###SSsssss#SssS##SssS###" ::
                "#SSS#Sssssss###SSSssssS#ss" ::
                "##SS#SsssssS#SsssSsssS##SS" ::
                "##SS#SsssS##sssssS##S##S##" ::
                "##S#SssS##SsssssS#SssssS##" ::
                "#SS##S#SsSSssssSS###ssssS#" ::
                "#S###Sssss#SSS#####S#SsssS" ::
                "####Ssssss#SsssS###SSS##SS" ::
                "####SssssSsssssssS###SSS##" ::
                "#S#SSssss##ssssssssS###SS#" ::
                "#SSs#SssSSS##ssssssssS####" ::
                "SSss#SsSS#SSSS##sssssssS##" ::
                "SSsS##SS##SSSSSS##SsssssSS" ::
                "#SsS##S#######SSSS##SssssS" ::
                "#Ss####SSSSS#####SS###SSSS" ::
                "#SS##SSSSSSSSSSS#########S" ::
                "####SSSSssssssSSSS########" ::
                "###SSssssssssssssSSSS#####" ::
                "##SSSSSssssssssssssSSSS###" ::
                "#SSSSssSSssssssssssssSSSS#" ::
                "#SSSSSSSSSSSsssssSSSSSSSSS" ::
                Nil)
            case (5, 5) => Some(
                "###SSSssSS##SSssssS##Sss##" ::
                "###SsSssssssS##SssS##sssS#" ::
                "##SSs#Sssssss#s##SS##ssSS#" ::
                "##SSS#SssssssSsssS###ssSS#" ::
                "######SSssssS#sssssS##ssS#" ::
                "###SsS###SssS#sssssSS###S#" ::
                "##sssss#SSS###ssssssS#s###" ::
                "##Sssss#SsssS#SsssssS#sS##" ::
                "##SSsSS#ssssss##SsssS#SsS#" ::
                "##SSSSS#sssssssS##Sss##sS#" ::
                "##SSSSS#sssssssSSsS####SS#" ::
                "####SS##SSssssS#ssssS###S#" ::
                "#########SSsSsS#sssssS####" ::
                "#####SS#####SSS#SssssS####" ::
                "###SSSS#SS######SssssSS#S#" ::
                "###SSSS#SSSS####SSssS#sSS#" ::
                "####SSS#SSSSSS###SSsS#ssSS" ::
                "######################SsSS" ::
                "SS#SSSS###sssSSS#######SS#" ::
                "S#SSS##ssssSSS###SSSS###S#" ::
                "#SS##sssSSS###SssssSSSS###" ::
                "#S#sssSS##SSsssssSssssSS##" ::
                "##SSSS##ssssssssssSSsssSS#" ::
                "#SSS##sssssssssssssSSSsSS#" ::
                "###SsssssssssssssSSssSSSS#" ::
                "##SssssSSsssssSSSSSSSSSSS#" ::
                Nil)
            case (6, 5) => Some(
                "#SsssssS#SsssssSS####SSsss" ::
                "#SsssssS#sssssssss#Sssssss" ::
                "#SssSS###sssssssssSsssssss" ::
                "###SsssS#sssssssssSsssssss" ::
                "#sssssss#sssssssssSsssssss" ::
                "#sssssssSsssssssssSsssssSS" ::
                "#sssssss#SsSSS##SS#SSsssSS" ::
                "#ssssssS#SSssSSSS##SSSSSss" ::
                "#ssssssS###SS#############" ::
                "#SsssSSS##SssssssssssS#sss" ::
                "####SS###SssssssssssssSsss" ::
                "#ssssssS#SssssssssssssSsss" ::
                "#sssssss#SSsssssssssssSsss" ::
                "#SssssSS#SSssssssssssS#SSs" ::
                "#SSssSSS##SSSssssssSs##Sss" ::
                "#sSssssS##SSSSSssSSSS##sss" ::
                "#sSSssss#####S###S######S#" ::
                "####SSS##Sssssssss##Ssssss" ::
                "#SsssssS#sssssssssS#Ssssss" ::
                "#SsssssS#ssssssssss#Ssssss" ::
                "#ssssssS#ssssssssssSssssss" ::
                "#sssssssSssssssssssSssssss" ::
                "#ssSssssSsssssssssSSssssSs" ::
                "#SSSssss#SsSSSSSS###SsssSS" ::
                "###SSSSs#############SS###" ::
                "##############SSSSS#######" ::
                Nil)
            case (7, 5) => Some(
                "ssSS##SssssssssSS####SSsss" ::
                "sss#kSssssssssssss#Sssssss" ::
                "sss#kSssssssssssssSsssssss" ::
                "sss#kSpsssssssssssSsssssss" ::
                "sss#pkSsSSpssspSssSsssssss" ::
                "Sss#KkSsssSkkK#sssSsssssSS" ::
                "sssS#KksskkK##SSSS#SSsssSS" ::
                "ssSS#KkkkkKSsSSSS##SSSSSss" ::
                "###KKKpkk##SS#############" ::
                "ssS###KKkkSssssssssssS#sss" ::
                "sssS##K##KkSssssssssssSsss" ::
                "sssS#S#ssSkSssssssssssSsss" ::
                "ssSS#SsssSKkspssssssssSsss" ::
                "ssS#sssss#SkkSsssssssS#SSs" ::
                "ssssssssS#SKkssssssSs##Sss" ::
                "S##SsssSS##KkSSssSSSS##sss" ::
                "##SS#######KkS###S######S#" ::
                "sssss#Sssss#ksssss##Ssssss" ::
                "sssss#Sssss#KsssssS#Ssssss" ::
                "sssssSsssssS#ssssss#Ssssss" ::
                "sssssSsssssssssssssSssssss" ::
                "ssssS#sssssssssssssSssssss" ::
                "ssssS#ssssssssssssSSssssSs" ::
                "ssSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (8, 5) => Some(
                "ssSS##SssssssssSS####SSsss" ::
                "ssss#Sssssssssssss#Sssssss" ::
                "ssss#sssssssssssssSsssssss" ::
                "ssss#sssssssssssssSsssssss" ::
                "ssss#sssSSssssssssSsssssss" ::
                "SsssSsssssssssssssSsssssSS" ::
                "ssssSSSssssSSS##SS#SSsssSS" ::
                "ssSS#SSSsssssSSSS##SSSSSss" ::
                "#####S#####SS#############" ::
                "sssssssss#SssssssssssS#sss" ::
                "sssssssssSssssssssssssSsss" ::
                "sssssssssSssssssssssssSsss" ::
                "sssssssssSSsssssssssssSsss" ::
                "sssssssssSSssssssssssS#SSs" ::
                "ssssssssS#SSSssssssSs##Sss" ::
                "S##SssssS#SSSSSssSSSS##sss" ::
                "##SS#########S###S######S#" ::
                "sssss#Ssssssssssss##Ssssss" ::
                "sssss#SsssssssssssS#Ssssss" ::
                "sssssSsssssssssssss#Ssssss" ::
                "sssssSsssssssssssssSssssss" ::
                "ssssS#sssssssssssssSssssss" ::
                "ssssS#ssssssssssssSSssssSs" ::
                "ssSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (9, 5) => Some(
                "ssSS##SssssssssSS####SSsss" ::
                "ssss#Sssssssssss###Sssssss" ::
                "ssss#ssssssssssSssSsssssss" ::
                "ssss#sssssssssSssSSsssssss" ::
                "ssss#sssSSssssssspSsssssss" ::
                "SsssSsssssssssssSpSsssssSS" ::
                "ssssSSSssssSSS##pp#SSsssSS" ::
                "ssSS#SSSsssssSS#pP#SSSSSss" ::
                "#####S#####SS##ppP########" ::
                "SSS#######SppppppPpppp#sss" ::
                "ssSSSS####sPpppPppPPPppsss" ::
                "ssssss##S#sSPPPPpPPS#Ppsss" ::
                "ssssss#SS#SsSSSSSSSsSPpsss" ::
                "ssssss#SS#Sssssssssss#pSSs" ::
                "ssssssSSS#SSSssssssSs#PSss" ::
                "S##SssSS##SSSSSssSSSS##sss" ::
                "##SSSSS######S###S######S#" ::
                "sssss##ppppppPssss##Ssssss" ::
                "sssss#ppppPSSsssssS#Ssssss" ::
                "sssssSpPSPSssssssss#Ssssss" ::
                "sssssSpPSssssssssssSssssss" ::
                "ssssS#PSSssssssssssSssssss" ::
                "ssssS#SSssssssssssSSssssSs" ::
                "ssSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (10, 5) => Some(
                "ssSS##SssssssssSS####SSsss" ::
                "ssss#Sssssssssssss#Sssssss" ::
                "ssss#sssssssssssssSsssssss" ::
                "ssss#sssssssssssssSsssssss" ::
                "ssss#sssSSssssssssSsssssss" ::
                "SsssSsssssssssssssSsssssSS" ::
                "ssssSSSssssSSS##SS#SSsssSS" ::
                "ssSS#SSSsssssSSSS##SSSSSss" ::
                "#####S#####SS#############" ::
                "sssssssss##############sss" ::
                "sssssssssS######S#SS##Ssss" ::
                "sssssssssS###S###S#S##Ssss" ::
                "sssssssss###S#SSSSSSS#Ssss" ::
                "sssssssss##SSSSSSsSsS##SSs" ::
                "ssssssssS##SSsSsssssS##Sss" ::
                "S##SssssS###SsssssSS###sss" ::
                "##SS####################S#" ::
                "sssss#Ssssssssssss##Ssssss" ::
                "sssss#SsssssssssssS#Ssssss" ::
                "sssssSsssssssssssss#Ssssss" ::
                "sssssSsssssssssssssSssssss" ::
                "ssssS#sssssssssssssSssssss" ::
                "ssssS#ssssssssssssSSssssSs" ::
                "ssSS###ssssSSSSSS###SsssSS" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (11, 5) => Some(
                "ssSS##SssssssssSS####SSS##" ::
                "ssss#Sssssssssssss#Ssssss#" ::
                "ssss#sssssssssssssSssssssS" ::
                "ssss#sssssssssssssSssssss#" ::
                "ssss#sssSSssssssssSssssss#" ::
                "SsssSsssssssssssssSsssssS#" ::
                "ssssSSSssssSSS##SS#SSsssS#" ::
                "ssSS#SSSsssssSSSS##SSSSSs#" ::
                "#####S#####SS#############" ::
                "sssssssss#SssssssssssS#ss#" ::
                "sssssssssSssssssssssssSssS" ::
                "sssssssssSssssssssssssSssS" ::
                "sssssssssSSsssssssssssSss#" ::
                "sssssssssSSssssssssssS#SS#" ::
                "ssssssssS#SSSssssssSs##Ss#" ::
                "S##SssssS#SSSSSssSSSS##ss#" ::
                "##SS#########S###S########" ::
                "sssss#Ssssssssssss##Sssss#" ::
                "sssss#SsssssssssssS#SssssS" ::
                "sssssSsssssssssssss#SssssS" ::
                "sssssSsssssssssssssSsssss#" ::
                "ssssS#sssssssssssssSsssss#" ::
                "ssssS#ssssssssssssSSssssS#" ::
                "ssSS###ssssSSSSSS###SsssS#" ::
                "#####################SS###" ::
                "SS#####SSS####SSSSS#######" ::
                Nil)
            case (0, 6) => Some(
                "##############SS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SSsssssssssssssssssssssSS" ::
                "#Sssssssssssssssssssssssss" ::
                "#SssssssssssssssssssssssSS" ::
                "#sss###S######SS######S###" ::
                "#sss#SsssssssssSSSssSSsssS" ::
                "#sss#SSSssSsssSSsssSSSSSSS" ::
                "Ssss##SSSSSSSSSSSsSSSS#SSS" ::
                "Ssss##S###SSS##SSSSS######" ::
                "Ssss###SS#######SS########" ::
                "Ssss#wwwwwwwwwwwwwWWWWwwww" ::
                "#sss#wwwwWWWWwWWwwwwwwwwwW" ::
                "#sss#wwwwWwWWSSSwwwwwwwwww" ::
                "Ssss#wwWWwwWWWWWWWWWWWSSSS" ::
                "Ssss#wwwwwWWwwwwwwwwwWWWWW" ::
                "#sss#wwwwWWwwwwwwwwwwwwwww" ::
                "#sss#wwwwwWwwwwwwwwWWWwwww" ::
                "#sss#wwwwwwwwwwwwwWWWwwwww" ::
                "#sss#wwWwwwwwwwWWWWwwwwwww" ::
                "#sssSwwwwwwwwwwwwWWWwwwwww" ::
                "#sssSwWWwwwwwwwwwwwwWwwwwW" ::
                "#Sss#wWWwwwwwwwwwwwWwwWWWW" ::
                "#SSS#wWWWWWWwwwwwWWwwwwwww" ::
                "#SSs#wWWwWWWwwWWwwwwwwwwww" ::
                "Ssss#wWWwWwWWWwwwwwwwWWWSS" ::
                Nil)
            case (1, 6) => Some(
                "#########SSSS#########SS##" ::
                "#SSSssssssssSSSSSSSSsssSS#" ::
                "#SssssssssssssssssssssssSS" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssSS" ::
                "#####S#####SS#############" ::
                "SsssssSSSSssssssSSSsssssss" ::
                "SsssSSsssssSssSSSsssssSSSS" ::
                "SSSSSSSSSSSSSsSSSSSSSSSSSS" ::
                "SS#######SSSSSS####S#####S" ::
                "###########SS#########S###" ::
                "wwwwwWWWWWwwwwwwwwwwWwwwww" ::
                "WWwwWwwwwwwwwwwwWwwwwwwwww" ::
                "wwWWSSwwwwwwwwwwwwWWwwwSSS" ::
                "SWWWWWWWWWWWWWwwwwwWWWWWWW" ::
                "wwwwwwwWWWwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwWWWWWWWWww" ::
                "wwwwwWwwwwwwwwwwwwwwWWWWWW" ::
                "wwwwwWWWwwwwwwwwwwwwwwwwww" ::
                "wwwWWwwWWwwwwwwwwwwwwwwwww" ::
                "WWwwwwwwwwwwwWSwwwwwwwwwww" ::
                "WWWWWWWWSWWWWwSSSWwwWWWWww" ::
                "WwwWWWWWWWwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwWWWWWWWWwwwwwwwww" ::
                "WWwwwwwWWWWSSSWWSWWWWWwwWW" ::
                Nil)
            case (2, 6) => Some(
                "##############SS######SS##" ::
                "#SSSssssssssSSSSSSSSsssSS#" ::
                "#SsssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#####S#####SS#########ssss" ::
                "SSssssssSSssssssSsssS#ssss" ::
                "SSSSsssssSSSSSSSSSsSS#ssss" ::
                "SSSSSSSSSSSS#SSSSSSS##ssss" ::
                "SSSSS###SSS###SSSSS###ssss" ::
                "#########S############ssss" ::
                "wwwwWWWWWwwwwwwwwwwww#ssss" ::
                "wSWwwwwwwwwwwWWWwwwww#Ssss" ::
                "SWwwwWWWWWwwwwwwwwwww#Ssss" ::
                "SWWwwWWWwWWWWWWWwwwww#Ssss" ::
                "wwwwwwwwwwwWWWWWwwwWw#SssS" ::
                "wwwwwwwwwwwwwWWWWwwWw#SssS" ::
                "WwwwwwwwwwwwwwwwWWwww#sssS" ::
                "wwwwwwwwwwwwwwwwwwWwwSsssS" ::
                "wwwwwwwwwwwwwwwwwwWwwSsssS" ::
                "wwwwwwwwwwwwwwwwwwwww#sssS" ::
                "wwwWWWWwwwwwwwwwwwwWw#sssS" ::
                "wWWWWSSSSwwwwwwwwwwWw#sssS" ::
                "wwwwWWWWWWwwwwwwwwwww#SssS" ::
                "wwwwwwwwwwwwwWWWSWwww#SSSS" ::
                "WWWWwwwwwwWWWWSSSSSSw#SS##" ::
                Nil)
            case (3, 6) => Some(
                "#########SSSSSSS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SssssssssssssssssssssssSS" ::
                "#SsSssssssssssssSSSsssssSS" ::
                "#sSssssssssssssssSSssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#Sssssssssssssssssssssssss" ::
                "#Sssssssssssssssssssssssss" ::
                "SSssssssssSsssssssssssssss" ::
                "SssssssssssSSssssssssssssS" ::
                "SssssssssssssSsssssssssssS" ::
                "SsssssssssssssssSSssssssSS" ::
                "#ssssssssssssssSSssssssSSS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssssssSssssSssssssssssSs" ::
                "#SssssssSSssSssssssssssssS" ::
                "#SSSsssssSSSsssssssssssssS" ::
                "SSSsssssssSssssssssssssssS" ::
                "SSssssssssSssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssSsssssssssssS" ::
                "#sssssssssssSSssssssssssSS" ::
                "#SsssssssssSSssssssssssSSS" ::
                "#SSsssssssSSssssssssssSssS" ::
                "#SSSsssSSSSSSsssssssSSsssS" ::
                "SsssSSSSSSSSsSSSSSSSSSS###" ::
                Nil)
            case (4, 6) => Some(
                "#########SSSSSSS######SS##" ::
                "##SssssssssSSSssSSSSsssSS#" ::
                "#SSsssssssssSssSSSSsssssSS" ::
                "#SssssssssssssssSSssssssSS" ::
                "#SssssssssssssssSssssssssS" ::
                "#ssssssssssssssSssssssssss" ::
                "#sssssssssssssSSssssssssss" ::
                "#sssssssssssssSsssssssssss" ::
                "PssssssssssssSssssssssssss" ::
                "pssssssssssssssssssssssssS" ::
                "ppSssssssssssSsssssssssssS" ::
                "pppSssssssssssSsssssssssss" ::
                "PpppppPsssssssssssssssssss" ::
                "PppPPSSsssssssssssssssssss" ::
                "PppSssssssssssssssssssssss" ::
                "PpPsssSssssssssssssssssssS" ::
                "#pSssssSSssssssssssssssssS" ::
                "#pSssssSsSsssssssssssssssS" ::
                "#pSsssssSSsssssssssssssssS" ::
                "#PssssssSsssssssSSsssssssS" ::
                "#ssssssssssssssSSSssSssssS" ::
                "#ssssssssssssSsssssssSSssS" ::
                "#SssssssssssSsssssssssSSSS" ::
                "#SssssssssssSssssssssssSSS" ::
                "#SssssssssssssssssSSSSssSS" ::
                "SSSssssssssssSSSSSSSSSS###" ::
                Nil)
            case (5, 6) => Some(
                "#########SSSSSSS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SSsssssssssssssssssssssSS" ::
                "#SssssssssssssssssssssssSS" ::
                "#SsssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "Ssssssssssssssssssssssssss" ::
                "Ssssssssssssssssssssssssss" ::
                "Ssssssssssssssssssssssssss" ::
                "Ssssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssss" ::
                "Ssssssssssssssssssssssssss" ::
                "SssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssssssssssssssssssssSSSS" ::
                "#SSSsssssssssssssssssSsssS" ::
                "#SSsSSSsssssssssssSSSssssS" ::
                "SssssSSSSssssSSSSSSSSSS###" ::
                Nil)
            case (6, 6) => Some(
                "#########SSSSSSS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SSsssssssssssssssssssssSS" ::
                "#SssssssssssssssssssssssSp" ::
                "#SssssssssssssssssssssssSp" ::
                "#ssssssssssssssssssssssSpp" ::
                "#sssssssssssssssspsssspppP" ::
                "#ssssssssssssssssSpSsssSpP" ::
                "SssssssssssssssssSpPSssSpp" ::
                "SssssssssssssssssSpppPSppp" ::
                "SssssssssssssssssPPppppppP" ::
                "SsssssssssssssssssSSPPpppP" ::
                "#sssssssssssssssssssssSppP" ::
                "#ssssssssssssssssssssssSpp" ::
                "Sssssssssssssssssssssssppp" ::
                "SsssssssssssssssssssssssSp" ::
                "#sssssssssssssssssssssssSP" ::
                "#sssssssssssssssssssssssSp" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssSssssS" ::
                "#ssssssssssssssssssspSsssS" ::
                "#sssssssssssssssssSpPSsssS" ::
                "#SsssssssssssssssSppSSssSS" ::
                "#SSSssssssssssssPpppSssssS" ::
                "#SSsSSSsssssssSSpppppPSSSS" ::
                "SssssSSSSsssSPppPPppppppPP" ::
                Nil)
            case (7, 6) => Some(
                "#########SSS##SS######SS##" ::
                "##SssssssssSS#SSSssssssSS#" ::
                "#SSssssssssssSSsssssssssSS" ::
                "#SsssssssssssSssssssssssSS" ::
                "#ssssssssssssSsssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "SssssssssssssSssssssssssss" ::
                "SsssssssssssSSssssssssssss" ::
                "SsssssssssssSSssssssssssss" ::
                "SsssssssssssS#Ssssssssssss" ::
                "#ssssssssssSS##Sssssssssss" ::
                "##SSSsssSS#####SSSssSS##S#" ::
                "#SssssssssssS#Ssssssssssss" ::
                "#ssssssssssss#Ssssssssssss" ::
                "#ssssssssssss#ssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#sssssssssssSSssssssssssss" ::
                "#SssssssssssSSSsssssssssss" ::
                "#SsSSSssssssSSsSsssssssssS" ::
                "#SSsssSSsssss#ssssSSSSssSS" ::
                "SssssSSSSsssS#SSS###SSS###" ::
                Nil)
            case (8, 6) => Some(
                "#########SSS##SS######SS##" ::
                "##SssssssssSS#SSSssssssSS#" ::
                "#SSssssssssssSSsssssssssSS" ::
                "#SsssssssssssSssssssssssSS" ::
                "#ssssssssssssSsssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "SssssssssssssSssssssssssss" ::
                "SsssssssssssSSsssssssSSSps" ::
                "SsssssSSSSpSSSssssssSkkkKs" ::
                "SsssskkkkkkkS#SsssSKkKpSSs" ::
                "#ssssS#KKKKkkkkSSpKkKSSsss" ::
                "##SSSsspS####KkkSKkkKSSSss" ::
                "#SssssssssSSS#KkkkkK#SSSSs" ::
                "#sssssssssssSS#kKKK#####SS" ::
                "#sssssssssssSSkKK######SSS" ::
                "#ssssssssssspKkK######S#SS" ::
                "#sssssssssssKkK###S##S#ssS" ::
                "#sssssssssskkKS#SS##Ssssss" ::
                "#sssssssssskSSSS##S#ssssss" ::
                "#ssssssssssSSSS#SS#sssssss" ::
                "#SssssssssssS#SSSSSsssssss" ::
                "#SsSSSssssssS##SsS#ssssssS" ::
                "#SSsssSSsssss###S#SSSSssSS" ::
                "SssssSSSSsssSSSSSS##SSS###" ::
                Nil)
            case (9, 6) => Some(
                "#########SSS##SS######SS##" ::
                "##SssssssssSS#SSSssssssSS#" ::
                "#SSssssssssssSSsssssssssSS" ::
                "#SsssssssssssSssssssssssSS" ::
                "#ssssssssssssSsssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "SsssssssSssssSssssssssssss" ::
                "SsssssssssssSSssssssssssss" ::
                "SssssSssssssSSssssssssssss" ::
                "SsssssssssssS#SssssSssssss" ::
                "#ssssssssssSS##SssSSssssss" ::
                "##SSSsssSS#####SSS##SS##S#" ::
                "#SssssssssssS#SsS#Ssssssss" ::
                "#ssssssssssss#SssS#sssssss" ::
                "#ssssssssssss#sssssSssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#ssssssssssssSssssssssssss" ::
                "#sssssssssssSSssssssssssss" ::
                "#SssssssssssSSSsssssssssss" ::
                "#SsSSSssssssSSsSsssssssssS" ::
                "#SSsssSSsssss#ssssSSSSssSS" ::
                "SssssSSSSsssS#SSS###SSS###" ::
                Nil)
            case (10, 6) => Some(
                "######SssssssssSSS###SSsss" ::
                "#Sss#SssssssssssSS#Sssssss" ::
                "#sssSSsssssssssssSSsssssss" ::
                "###S###SsssssssssSSsssssss" ::
                "#Ssssss#ssssssssss#sssssss" ::
                "#ssssss#SsssssSssS#ssssssS" ::
                "#ssssss#SSSSSSSSSS#SSssSSS" ::
                "#ssssss#S####SSSS##SSSSSSS" ::
                "Sssssss#sssss#S###########" ::
                "SssssssSsssss#SSsssssS#sss" ::
                "SssssssSsssss#SSSssssSSsss" ::
                "SssssssSsssss#S###SSssSsss" ::
                "#ssssssSsssssSsssss#SsSsss" ::
                "#ssssssSsssssssssss#SS#Sss" ::
                "SsssssSSssssS#sssss#S##SSS" ::
                "SssssSsSssssS#sssss#ssss#S" ::
                "#ssssssSsssssSsssssSssssS#" ::
                "#sssssssSssssssssssSsssss#" ::
                "#sssssssSssssSsssssssssss#" ::
                "#ssssssSSssssSsssssssssssS" ::
                "#ssssssSSssssSsssssSsssssS" ::
                "#ssssssSsssssSsssssSsssssS" ::
                "#sssssS#sssssSsssssSssSSS#" ::
                "#SSSsSS#SSSsS#ssssS#sSsss#" ::
                "##SSS####SSS##SssSS###SSS#" ::
                "#####SSS############SS####" ::
                Nil)
            case (11, 6) => Some(
                "#########SSSSSSS######SS##" ::
                "##SsssssssssSSSSsssSSssSS#" ::
                "#SSssssssssssssssssSsssssS" ::
                "#Ssssssssssssssssss#sssssS" ::
                "#sssssssssssssS###S#ssssss" ::
                "#ssssssssssssSsssss#ssssss" ::
                "#ssssssssssss#sssss#ssssss" ::
                "#sssssssS##S#ssssssSssssss" ::
                "SssssssSssss#ssssssSssssss" ::
                "Sssssss#ssss#sssssssssssss" ::
                "SsS###S#ssssSsssssssSsssss" ::
                "SSssssS#ssssSsssssssSsssss" ::
                "#ssssssSssssssssssssSsssss" ::
                "#ssssssSsssssS#sssssssssss" ::
                "SssssssSsssss#SssssSssssss" ::
                "SssssssSsssss#sssssSssssss" ::
                "#ssssssSsssssSsssssSSSSSS#" ::
                "#ssssssSsssssSsssss#SSSsss" ::
                "#ssssssSsssssSsssSS#SSssss" ::
                "#sssssSssssss#ssssS##SsssS" ::
                "#SssssSssssss#SssSS##SSss#" ::
                "#Sssss#sSsssS#SSSS#####Ss#" ::
                "#Sssss#SSsS###SSSSSssSS#S#" ::
                "#sSS######SS##SSSSSSSSSS##" ::
                "###ssSSSSSSS###SSS#SSSSS##" ::
                "##SSSSSS#############SS###" ::
                Nil)
            case (0, 7) => Some(
                "#####wWWWWwwwwwwwwwwwwwWWW" ::
                "#ssS#wWWWwwwwwwwwwwwwwwwww" ::
                "#sss#wwwWwwwwwwwwwwWwwwWww" ::
                "#sssSwwwWwwwwwwwwwwwwwwwww" ::
                "#sssSwwwWwwwwwwwwwwwwwwwww" ::
                "#sssSwwWwwwwwwwwwwwwwwwwww" ::
                "#sssSwSWwwwwwwwwwwwwwwwwww" ::
                "#sssSwSWwwwwwwwwwwwwwwwwww" ::
                "SsssSwWWWwwwwwwwwwwwwwwwww" ::
                "SsssSwwSSWwwwwwwwwwwwwwwww" ::
                "Ssss#wwwSWwwwwwwwwwwwwwwww" ::
                "Ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "#ssS#wWwwwwwwwwwwwwwwwwwww" ::
                "#ssS#wWwwwwwwwwwwwwwwwwwww" ::
                "SssS#wWwwwwwwwwwwwwwwwwwww" ::
                "SssS#wwwwwwwwwwwwwwwwwwwww" ::
                "#ssS#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwWWWWWWWWww" ::
                "#sssSwwwwwwwwwWWWWSSSWwwww" ::
                "#sssSwwwwwwwwwwwwwWWWwwwww" ::
                "#sssSwwwwwwwwwwwwWWWwwwwww" ::
                "#sssSwwwWWwwwwwwwwwwwwwwww" ::
                "#sss#wWWSSwwwwwwwwwwwwwwww" ::
                "#ssS#wSWWWWwwwwwwwwwwwwwww" ::
                "#SSS#wSWwwWWwwwwwwwwwwwwww" ::
                "SSSS#wSWwwwwwwwwwwwwwwwwww" ::
                Nil)
            case (1, 7) => Some(
                "WwwwwwwwwwwwwWWWWWWwwwwwwW" ::
                "wwwwwwwwwwwwwwwWwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwWWWwwwwwwwwwwwwww" ::
                "wwwwwwwWWWWWWWWWwwwwwwwwww" ::
                "wwwwWWWWWWSSWWwwwwwwwwwwww" ::
                "wwwwwwwWWWWWWwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwWWWWWwwwwwwwwwwwwwww" ::
                "wwwWWWSSWwwwwwwwwwwwwwwwww" ::
                "wwwwWWWWWWwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwWWWW" ::
                "wwwwwwwwwwwwwwwwwwwWWWWWWw" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "WWwwwwwwwwwwwwwwwwwwwwwwww" ::
                "WWWWwwwwwWWWWWWwWWwwwwwwww" ::
                Nil)
            case (2, 7) => Some(
                "WwwwwwwwwwwWWwwwwSSSw#####" ::
                "wWWWSwwwwwwwwwwwwwWSw##SsS" ::
                "wwwwWwwwwwwwwwwwwwwww#SSss" ::
                "wwwwwwwwwwwwwwwwwwwww#SSsS" ::
                "wwwwwwwwwwwwwwwwwwwww#SssS" ::
                "wwwwwwwwwwwwwwwwwwWww#sssS" ::
                "wwwwwwwwWWWWWWWwwwWww#sssS" ::
                "wwwwwwwwwwwWWWWwwWSWw#sssS" ::
                "wwwwwwwwwwwwwwwwwWSWwSsssS" ::
                "wwwwwwwwwwwwwwwwWWSwwSsssS" ::
                "wwwwwwwwwwwwwwwwwWSwwSsssS" ::
                "wwwwwwwwwwwwwwwwWWSwwSssss" ::
                "wwWWWWwwwwwwwwWWWWSww#ssss" ::
                "wwwwwWWWwwwwwwwwwWwww#ssss" ::
                "wwwwwwwwwwwwwwwwwWwwwSssss" ::
                "wwwwwwwwwwwwwwwwwWWwwSssss" ::
                "wwwwwwwwwwwwwwwwwWwWwSssss" ::
                "wwwwwwwwwwwwwwwwwWwwwSssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwww#ssss" ::
                "wwwwwwwwwwwwwwwwwwwWw#ssss" ::
                "wwwwwwwwwwwwwwwwwwwWw#ssss" ::
                "wwwwwwwwwwwwwwwwwwwWw#Ssss" ::
                "wwwwwwwwwwwwwwwwwwwWw#SSsS" ::
                "wwwWWWWWwwwwwwwwwwwWw#SSsS" ::
                "WWWWWWWwwwwwwwwwwwWwwSssSS" ::
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
                "kkkkkKkkkkkkKkkkkkkKkkkkkk" ::
                "kkkkkKkkkkkkKkkkkkkKkkkkkk" ::
                "kkkkkKkkkkkkKkkkkkkKkkkkkk" ::
                "kkkkkKkkkkkkKkkkkkkKkkkkkk" ::
                "kKKkk#kkKKkK#kkkkkK#kkkkkK" ::
                "k#s#k#k#s#kK#k#s#kK#k#s#kK" ::
                "ksssk#kssskK#kssskK#ksssKK" ::
                "k#m#K#k#m#kK#k#m#kK#k#m#KK" ::
                Nil)
            case (4, 7) => Some(
                "##########################" ::
                "##########################" ::
                "##########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "KK########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "KK########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "KK########################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "#K########################" ::
                "kkK#######################" ::
                "kkK#######################" ::
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
                "###########KKK############" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########KKK############" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########kkkk###########" ::
                "###########KKK############" ::
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
                "##############SS######SS##" ::
                "##SsssssssssSSSSSSSSsssSS#" ::
                "#SSsssssssssssssssssssssSS" ::
                "#Sssssssssssssssssssssssss" ::
                "#SssssssssssssssssssssssSS" ::
                "#sss###S######SS######S###" ::
                "#sss#SsssssssssSSSssSSsssS" ::
                "#sss#SSSssSsssSSsssSSSSSSS" ::
                "Ssss##SSSSSSSSSSSsSSSS#SSS" ::
                "Ssss##S###SSS##SSSSS######" ::
                "Ssss###SS#######SS########" ::
                "Ssss#wwwwwwwwwwwwwWWWWwwww" ::
                "#sss#wwwwWWWWwWWwwwwwwwwwW" ::
                "#sssSwwwwWwWWSSSwwwwwwwwww" ::
                "SsssSwwWWwwWwwwwWWWWWWSSSS" ::
                "Ssss#wwwwwwwwwwwwwwwwwwWWW" ::
                "#sss#wwwwWWwwwwwwwwwwwwwWw" ::
                "#sss#wwwwwWwwwWWWWWWWWwwww" ::
                "#sss#wwwwwwwwWWWWWWWWwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss###S#########SS##SSS##" ::
                "#ssssssssssssssssssssssssS" ::
                "#SsssssssssssssssssssssssS" ::
                "#SSSsssssssssssssssssSsssS" ::
                "#SSsSSSsssssssssssSSSssssS" ::
                "SssssSSSSssssSS###SSSSS###" ::
                Nil)
            case (10, 7) => Some(
                "#########SSSS#########SS##" ::
                "#SSSssssssssSSSSSSSSsssSS#" ::
                "#SssssssssssssssssssssssSS" ::
                "#sssssssssssssssssssssssss" ::
                "#sssssssssssssssssssssssSS" ::
                "#####S#####SS#############" ::
                "SsssssSSSSssssssSSSsssssss" ::
                "SsssSSsssssSssSSSsssssSSSS" ::
                "SSSSSSSSSSSSSsSSSSSSSSSSSS" ::
                "SS#######SSSSSS####S#####S" ::
                "###########SS#########S###" ::
                "wwwwwWWWWWwwwwwwwwwwWwwwww" ::
                "WWwwWwwwwwwwwwwwWwwwwwwwww" ::
                "wwWWSSwwwwwwwwwwwwWWwwwSSS" ::
                "SWWWWWWWWWWWWWwwwwwWWWWWWW" ::
                "WwwwwwwWwwwwwwwwwwwwwwwwww" ::
                "wwwwwwwwwwwwwwwwwWWWWWWWww" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwWWwWWwwwwwwwwWWWWWwwww" ::
                "wwwwwwWWWWWWWWWWWWWWwwwwww" ::
                "######S######SS######SSS##" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssSsssssssssssssssssSssS" ::
                "#SsSSSSsssssssssssSSSSsssS" ::
                "#SSssSSSSssssSSSSSSSSSS###" ::
                Nil)
            case (11, 7) => Some(
                "##############SS######SS##" ::
                "#SSSssssssssSSSSSSSSsssSS#" ::
                "#SsssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#sssssssssssssssssssssssss" ::
                "#####S#####SS#########ssss" ::
                "SSssssssSSssssssSsssS#ssss" ::
                "SSSSsssssSSSSSSSSSsSS#ssss" ::
                "SSSSSSSSSSSS#SSSSSSS##ssss" ::
                "SSSSS###SSS###SSSSS###ssss" ::
                "#########S############ssss" ::
                "wwwwWWWWWwwwwwwwwwwww#ssss" ::
                "wSWwwwwwwwwwwWWWwwwww#Ssss" ::
                "SWwwwWWWWWwwwwwwwwwww#Ssss" ::
                "SWWwwWWWwWWwwwwWWWWww#Ssss" ::
                "wwwwwwwwwwwwWWWWwWWWw#SssS" ::
                "wwwwwwwwwwwWWWWWWwWWw#SssS" ::
                "wwwwwwwwwwwwwwwwwWWWw#sssS" ::
                "wwwwwwwwwwwWWWWWwwWwwSsssS" ::
                "wwwwwwwwwwwwwwwwwwwww#sssS" ::
                "#######SSS#####SSSS###sssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssSsssssssssssssssssSsSS" ::
                "#SsSSSSsssssssssssSSSsSSSS" ::
                "##SssSSSSssssSSS##SSSSSS##" ::
                Nil)
            case (0, 8) => Some(
                "#####wSSwwwwwwwwwwwwwwwwwW" ::
                "#sss#wSSWwwwwwwwwwwwwwwwww" ::
                "#sss#wSSwwwwwwwwwwwwwwwwww" ::
                "#sss#wWWwwwwwwwwwwwwwwwwww" ::
                "#sss#wwWwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sss#wwwwwwwwwwwwwwwwwwwww" ::
                "#sssSwwwwwwwwwwwwwwwwwwwww" ::
                "SsssSwwwwwwwwwwwwwwwwwwwww" ::
                "Ssss#wwwwwwwwwwwwwwwwwwwww" ::
                "Ssss#wwwwWwwwwwwwwwwwwwwww" ::
                "Ssss#wwwwWwwwwwwwwwwwwwwww" ::
                "Ssss#wwwWWwwwwwWWWwwwwwwww" ::
                "Ssss#wwwWWwwwWWWwwwwwwwwww" ::
                "#sssSwwWSWwWWWWwwWwwwwwwww" ::
                "#sssSwwWSWwWWWWwwWwwwwwwww" ::
                "#sss#wSWSwwwwwwwWWWWwwwwww" ::
                "Ssss#wSSWWWWwwWWWwwWWWWwww" ::
                "Ssss#wSSSwwwwwWWwwwwWWWWWW" ::
                "#sss#wwwwwwwwwwwwwwwwwWWww" ::
                "#sss###S#########SS##SSS##" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SSSsssssssssssssssssSsssS" ::
                "#SSsSSSsssssssssssSSSssssS" ::
                "SssssSSSSssssSS###SSSSS###" ::
                Nil)
            case (1, 8) => Some(
                "WWWwwwwwwwWWWWWWwwwwwwwwwW" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwWW" ::
                "wwwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wwwwwwWWWWwwwwwwwwwwwwwwww" ::
                "wwwwwwwWWWWWwwwwwwwwwwwwww" ::
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
                "wWwwwwwwwwwwwwwwwwwwwwwwww" ::
                "wWWwWwwwwwWWwwwwwwwwWWwwww" ::
                "WSSWWWWWWWWWWwwwwWWWWWWWww" ::
                "SSSSSSSWWWwwwwwwwwSSSSSWww" ::
                "wwwwWWwwwwwwwwwwwwwwwwwwww" ::
                "######S######SS######SSS##" ::
                "#ssssssssssssssssssssssssS" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssSsssssssssssssssssSssS" ::
                "#SsSSSSsssssssssssSSSSsssS" ::
                "#SSssSSSSssssSSSSSSSSSS###" ::
                Nil)
            case (2, 8) => Some(
                "SSSSWwwwwwwwwwwwwwWww#####" ::
                "WSSwwwwwwwwwwwwwwWWww##SsS" ::
                "wWWWWWwwwwwwwwwwwWSSw#SSss" ::
                "wwwWWwwwwwwwwwwwwWWWw#SSsS" ::
                "wwwwwwwwwwwwwwwwwWwWw#SssS" ::
                "wwwwwwwwwwwwwwwwwwwWw#sssS" ::
                "wwwwwwwwwwwwwwwwwwwww#sssS" ::
                "wwwwwwwwwwwwwwwwwwwww#sssS" ::
                "wwwwwwwwwwwwwwwwwwwww#sssS" ::
                "wwwwwwwwwwwwwwwwwwwwwSsssS" ::
                "wwwwwwwwwwwwwwwwwwwwwSsssS" ::
                "wwwwwwwwwwwwwwWWwwwwwSsssS" ::
                "wwWwwwwwwwwwwwwWWwwWwSssss" ::
                "wwWwwwwwwwwwwwwWWwWWw#ssss" ::
                "wwWWwwwWWWWWwwwwWWWWw#ssss" ::
                "wwWWWwwwWWWwwwwwWWWWw#ssss" ::
                "WWWWWWwwwwwwWwwWWSWSw#ssss" ::
                "WSSWWWwwwwwWWWWWwSSSw#ssss" ::
                "SSSSWWWWWWWWSwwwwwwSwSssss" ::
                "wwwwwwwwwwwwWwwwwwwww#ssss" ::
                "#######SSS#####SSSS###ssss" ::
                "#sssssssssssssssssssssssss" ::
                "#ssssssssssssssssssssssssS" ::
                "#SssSsssssssssssssssssSssS" ::
                "#SsSSSSsssssssssssSSSSsssS" ::
                "##SssSSSSssssSSS##SSSSS###" ::
                Nil)
            case (3, 8) => Some(
                "kkkkK#kkKkkK#kKKKkK#kkkkKK" ::
                "kkkkK#kkKkkK#kkKKkK#kkkkKK" ::
                "KKkkK#kkkkkK#kkKKkK#kkkkkK" ::
                "ssKKK#kkkKkK#kkkKkK#kkkkkK" ::
                "mssKK#kkkKkK#kkkkkK#kKKkkK" ::
                "#s#sK#kkkKkK#kkKkkK#kK#kkK" ::
                "###KK#kkKKkK#kkKkkK#kK#kkK" ::
                "##KKK#kkKKkK#kkKkkK#kkKkkK" ::
                "KKKKk#kkKkkK#kkKkkK#kkKKkK" ::
                "KKkKk#kkKkkK#kkKKkK#Ksssss" ::
                "kKkKk#kkkkkK#kkkKkK#Ksssss" ::
                "kkkKk#kKkkkK#kKkkkK#Ks###s" ::
                "kkkKk#kKkKkK#kKkKkK#Kss#ss" ::
                "KKkkk#kKKKkK#kkKKkK#kss#ss" ::
                "ssKKk#kkKKkK#kKKKkK#ksssss" ::
                "mssKk#kkKKkK#kK#KkK#kKKKKK" ::
                "#s#sk#kkKKkK#kK#KkK#kkkkKK" ::
                "###Kk#kkkKkK#kkKKkK#kkkKkK" ::
                "##KKk#kkkKkK#kkkkkK#kkKKkK" ::
                "KKKKk#kkKKkK#kkKkkK#kkKKkK" ::
                "KkKkk#KkKKkK#kkKkkK#kkKKkK" ::
                "k#s#k#K#s#kK#k#s#kK#k#s#kK" ::
                "ksssk#KssskK#kssskK#kssskK" ::
                "k#m#K#K#m#kK#k#m#kK#k#m#kK" ::
                "kkkKK#KKKKkK#kK#KkK#kKKkkK" ::
                "##########################" ::
                Nil)
            case (4, 8) => Some(
                "kkk#######################" ::
                "kkK#######################" ::
                "KKK#######################" ::
                "K#K#######################" ::
                "sss#######################" ::
                "#sm#######################" ::
                "##########################" ::
                "K#K#######################" ::
                "KKk#######################" ::
                "KKk#######################" ::
                "kKk#######################" ::
                "kKk#######################" ::
                "kKk#######################" ::
                "kkk#######################" ::
                "K#K#######################" ::
                "sss#######################" ::
                "#sm#######################" ::
                "##########################" ::
                "K#K#######################" ::
                "KKk#######################" ::
                "Kkk#######################" ::
                "kkk#######################" ::
                "kkk#######################" ::
                "kkK#######################" ::
                "kKK#######################" ::
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
                "###########S##############" ::
                "#########s#b##############" ::
                "##########Bbb#S###########" ::
                "##########SSBbb##SS#######" ::
                "#########s#B#SBbbbb#######" ::
                "#######S#SbBB###Bbb#######" ::
                "######SbbbB##sss#B#s######" ::
                "#######bB##s######S#######" ::
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
                "##########S###S###########" ::
                "##########bbbbB###########" ::
                "########SbbbbbbBS#########" ::
                "#########bbbbbbb##########" ::
                "##########bb#SbB#ss#######" ::
                "#######s##bb##bB###b#s####" ::
                "########SB#bBBB#SBBBb#####" ::
                "######bbBSBBBS#BbSS#######" ::
                "##############s#Bbb#s#####" ::
                "######ssssssssss#Bb#######" ::
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
                "#############S##S#########" ::
                "#############BbbB#########" ::
                "############bbbbbB########" ::
                "###########S#bbbbbBS######" ::
                "#########s###bbbbbB#######" ::
                "########s#Sbbb#SbbB#######" ::
                "######s###Bb#b##bBB#######" ::
                "#######bB#BbBbBBBBS#s#####" ::
                "#######S#S#BbBBS###S#s####" ::
                "######s#BbB#BS##SBbbb#####" ::
                "#######bbBSS##BB###Bb#####" ::
                "###########BbbB#sss##s####" ::
                "########sss###bB#ss#######" ::
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
    /// 線画（大文字）は材質チャー（小文字）へ落として返す — 近傍判定は「石か水か虚空か」だけを見るため。
    def charAtGlobal(gx: Int32, gy: Int32): Char =
        if (gx < 0 or gy < 0 or gx >= atlasW() or gy >= atlasH()) '#'
        else baseChar(maskCharAt(gx / cell(), gy / cell(), Int32.modulo(gx, cell()), Int32.modulo(gy, cell())))

    /// (col,row,lx,ly) が構造（true）か虚空（false）か。虚空チャー '#' 以外（線画の大文字も含む）が構造。
    pub def structureAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Bool =
        maskCharAt(col, row, lx, ly) != '#'

    /// (col,row,lx,ly) の材質（材質 XOR 計測・塗り分けの共通経路）。線画大文字は塗りと同材質。
    pub def materialAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Material =
        charMaterial(maskCharAt(col, row, lx, ly))

    /// (col,row,lx,ly) が線画画素か（塗りの最暗段で締める輪郭・段差・目地）。材質 XOR には効かない明度の話。
    pub def isLineAt(col: Int32, row: Int32, lx: Int32, ly: Int32): Bool =
        isLineChar(maskCharAt(col, row, lx, ly))

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
            case (10, 6) => "stairs_l"
            case (11, 6) => "stairs_r"
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
        case Line
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

    /// 出力 ARGB（テーマ指定）。green も flower も原本と同一シルエット（花はその内側を塗り替えるだけ）。
    pub def pixelArgbWith(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32): Int32 =
        if (not structureAt(col, row, lx, ly))
            packArgb(255, rgbOf(t#voidC))
        else
            packArgb(255, stageOf(t, col, row, lx, ly)#full)

    /// アトラス座標が構造画素か（近傍走査の共通経路）。
    def solidGlobal(gx: Int32, gy: Int32): Bool =
        gx >= 0 and gy >= 0 and gx < atlasW() and gy < atlasH() and charAtGlobal(gx, gy) != '#'

    /// レイヤー別 ARGB（カタログ出口・green テーマ）。Line は線画画素のみを最暗色で示す（塗りは地色）。
    pub def layerArgb(col: Int32, row: Int32, lx: Int32, ly: Int32, layer: Layer): Int32 =
        let t = themeGreen();
        let solid = structureAt(col, row, lx, ly);
        match layer {
            case Layer.Void =>
                if (solid) packArgb(255, (92, 100, 92)) else packArgb(255, rgbOf(t#voidC))
            case Layer.Line =>
                if (not solid) packArgb(255, rgbOf(t#voidC))
                else if (isLineAt(col, row, lx, ly)) packArgb(255, lineColorOf(t, col, row, lx, ly, gxOf(col, lx), gyOf(row, ly)))
                else packArgb(255, (150, 158, 150))
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

    def gxOf(col: Int32, lx: Int32): Int32 = col * cell() + lx
    def gyOf(row: Int32, ly: Int32): Int32 = row * cell() + ly

    /// 材質チャー（線画は小文字に落とす）→ その材質のランプ。線画を最暗段で締める出口。
    def lineRamp(t: Theme, ch: Char): List[Int32] = match baseChar(ch) {
        case 'w' => t#water
        case 'k' => t#wood
        case 'm' => t#metal
        case 'b' => t#bone
        case 'p' => t#plant
        case _   => t#stone
    }

    /// 線画色 = その材質ランプの最暗段（テーマ最暗色）。fire は石の目地がまばらに ember 発光する。
    def lineColorOf(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let ch = maskCharAt(col, row, lx, ly);
        if (t#ember != 0 and baseChar(ch) == 's' and hash01(gx / 5, gy / 5, 97) < 0.20) rgbOf(t#ember)
        else rampAt(lineRamp(t, ch), 0)

    /// テーマの流儀 motif で塗りの画家を選ぶ。Lamp は材質ランプ＋立体面シェーディング、
    /// その他は材質領域を 1 単位に描くモチーフ画家（花/金属パネル/砂岩…）。シルエットと材質領域は共通。
    def stageOf(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32): Stg =
        let gx = col * cell() + lx;
        let gy = row * cell() + ly;
        let raw = maskCharAt(col, row, lx, ly);
        match t#motif {
            case MotifKind.Lamp   => lampStage(t, col, row, lx, ly, gx, gy, raw)
            case MotifKind.Flower => flowerStage(t, col, row, gx, gy, raw)
        }

    /// Lamp テーマ: 石は文脈で床/壁/枠、'w' は蜘蛛の巣セルだけ web ランプ。
    /// 線画画素（大文字）は塗りの上からテーマ最暗色で締める（塗り側は最暗段を出さない = 二重目地を断つ）。
    def lampStage(t: Theme, col: Int32, row: Int32, lx: Int32, ly: Int32, gx: Int32, gy: Int32, raw: Char): Stg =
        let fill = match baseChar(raw) {
            case 'w' => if (isWebCell(col, row)) webStages(t, gx, gy) else waterStages(t, gx, gy)
            case 'k' => woodStages(t, gx, gy)
            case 'm' => metalStages(t, gx, gy)
            case 'b' => boneStages(t, gx, gy)
            case 'p' => plantStages(t, gx, gy)
            case 's' =>
                // row5 = 壁前面の暗レンガ帯（floorcap）だけ brick。他は文脈で床(丸石)/枠(loaf)/壁(loaf)。
                if (row == 5) brickStages(t, gx, gy)
                else match stoneContext(col, row) {
                    case StoneKind.Floor  => cobbleStages(t, gx, gy)
                    case StoneKind.Coping => loafStages(t, gx, gy, 71)
                    case StoneKind.Wall   => loafStages(t, gx, gy, 53)
                }
            case _   =>
                let v = rgbOf(t#voidC);
                { ground = v, arch = v, weather = v, light = v, full = v }
        };
        if (isLineChar(raw)) {
            let lc = lineColorOf(t, col, row, lx, ly, gx, gy);
            { ground = fill#ground, arch = lc, weather = lc, light = neutralRelief(0.55), full = lc }
        } else fill

    // ════════════════════════════════════════════════════════
    // 石割りユーティリティ（周回レンガ規律 = TileLint wrapBrick が検査）
    // ════════════════════════════════════════════════════════
    pub def railCuts(): List[Int32]    = 4 :: 13 :: 22 :: Nil
    pub def faceCuts(): List[Int32]    = 6 :: 19 :: Nil
    pub def soldierCuts(): List[Int32] = 3 :: 8 :: 13 :: 18 :: 23 :: Nil

    pub def wrapStoneWidths(cuts: List[Int32], tiles: Int32): List[Int32] =
        let p = cell();
        let allCuts = List.flatMap(t -> List.map(c -> c + t * p, cuts), List.range(0, tiles)) |> List.sort;
        List.zip(allCuts, List.drop(1, allCuts)) |> List.map(pair -> { let (a, b) = pair; b - a })

    // ════════════════════════════════════════════════════════
    // 立体面シェーディング（作業A: 石を平板でなく塊に見せる）
    // ════════════════════════════════════════════════════════
    // 原本の石は「上面が受光・中央が地・底が影の塊」。連続階調を避ける量子化塗りは平坦に見えがちだった。
    // そこで各石領域（線画マスクと虚空で区切った同材質の連結成分）内での画素の位置を測り、
    // 上端を明段・下端を暗段・左右端をわずかに暗へ寄せる。光は常に上から一貫（craft 規則）。

    /// 石領域内の位置を測る物差し。上下左右それぞれ、同じ石（＝同材質の塗り画素。線画・虚空・別材質で途切れる）が
    /// 何画素続くか。連結成分ラベルは持たず、十字方向の走査で塊の広がりを近似する（純粋・軽量）。
    type alias Probe = { up = Int32, down = Int32, left = Int32, right = Int32 }

    /// アトラス座標 (gx,gy) が base 材質の「塗り画素」か。線画（大文字）・虚空・別材質は石の境界なので false。
    def isFillOf(gx: Int32, gy: Int32, base: Char): Bool =
        if (gx < 0 or gy < 0 or gx >= atlasW() or gy >= atlasH()) false
        else {
            let raw = maskCharAt(gx / cell(), gy / cell(), Int32.modulo(gx, cell()), Int32.modulo(gy, cell()));
            raw != '#' and not isLineChar(raw) and baseChar(raw) == base
        }

    /// (gx,gy) から方向 (dx,dy) へ、同じ石の塗り画素が続く数（0..cap）。境界に達したら止まる。
    def runOf(gx: Int32, gy: Int32, dx: Int32, dy: Int32, base: Char, cap: Int32): Int32 =
        List.range(1, cap + 1)
            |> List.findLeft(d -> not isFillOf(gx + dx * d, gy + dy * d, base))
            |> Option.map(d -> d - 1)
            |> Option.getWithDefault(cap)

    /// (gx,gy) を含む石の十字方向の広がり（cap 7 で壁石の中心まで届く）。
    def stoneProbe(gx: Int32, gy: Int32, base: Char): Probe =
        { up    = runOf(gx, gy, 0, -1, base, 7),
          down  = runOf(gx, gy, 0,  1, base, 7),
          left  = runOf(gx, gy, -1, 0, base, 7),
          right = runOf(gx, gy,  1, 0, base, 7) }

    /// ランプ段 idx→光レイヤの相対輝度（tileset_layers 診断用）。
    def reliefOfIdx(idx: Int32): Float64 = 0.5 + Int32.toFloat64(idx) * 0.2

    // ════════════════════════════════════════════════════════
    // 立体面シェーディング（作業A: 原本の画素実測から導いた面ごとの光配分）
    // ════════════════════════════════════════════════════════
    // tileset_dungeon_green.png を 1 画素ずつランプ段へ分類して導いた面の作り方（面ごとに光配分が違う）:
    //   ・loaf（笠石帯・柱・既定壁）= 手前に膨らむ塊。地は明段 3、底縁 1 行に最明 4 の破線リム、
    //     天端 1 行はすぐ上の段の影でやや暗 2、目地（線画）で締まる。塊の主調は 3（従来の 2 は暗すぎた）。
    //   ・brick（壁前面帯・row5 floorcap）= 縦の前面。全体に暗く（段 0-2）、レンガ上辺が明 3・下辺が暗 0 の上受光。
    //   ・cobble（床石・row6）= 丸石。地は中段 2、上左が受光 3-4・下右が影 1。明暗差は控えめ。
    // 段は必ずランプ量子化（中間色を作らない）。走査 stoneProbe は線画/虚空で途切れるので「塊内の位置」を測る。

    /// loaf: 明段 3 の塊 + 底縁の最明 4 リム + 天端の陰 2 + 側縁/石ごとの控えめな差。
    def loafStages(t: Theme, gx: Int32, gy: Int32, seed: Int32): Stg =
        let p = stoneProbe(gx, gy, 's');
        let i1 = if (p#down <= 0 and hash01(gx, gy, seed + 1) < 0.60) 4 else 3;              // 底縁リム（破線状）
        let i2 = if (p#up <= 0 and p#down >= 2 and hash01(gx, gy, seed + 2) < 0.55) 2 else i1; // 天端の陰
        let i3 = if ((p#left <= 0 or p#right <= 0) and p#down >= 2 and p#up >= 1) Int32.min(i2, 2) else i2; // 側縁
        let j  = hash01(gx / 7, gy / 7, seed);
        let i4 = if (j > 0.90 and i3 == 3) 4 else if (j < 0.14 and i3 == 3) 2 else i3;       // 石ごとの色差
        let idx = Int32.max(1, Int32.min(4, i4));
        let full = rampAt(t#stone, idx);
        { ground = rampAt(t#stone, 3), arch = full, weather = full,
          light = neutralRelief(reliefOfIdx(idx)), full = full }

    /// brick: 暗い縦前面。レンガ上辺が受光・下辺が影の上受光。
    def brickStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let p = stoneProbe(gx, gy, 's');
        let base =
            if (p#up <= 0)      3        // レンガ上辺 = 受光
            else if (p#up <= 1) 2
            else if (p#down <= 0) 0      // レンガ底 = 影
            else if (p#down <= 1) 1
            else                1;       // 前面の地（暗）
        let j = hash01(gx, gy, 29);
        let i = if (j > 0.85 and base <= 1) base + 1 else if (j < 0.12 and base >= 1) base - 1 else base;
        let idx = Int32.max(0, Int32.min(3, i));
        let full = rampAt(t#stone, idx);
        { ground = rampAt(t#stone, 1), arch = full, weather = full,
          light = neutralRelief(reliefOfIdx(idx)), full = full }

    /// cobble: 中段 2 の丸石。上左受光・角のきらめき・下右の影。
    def cobbleStages(t: Theme, gx: Int32, gy: Int32): Stg =
        let p = stoneProbe(gx, gy, 's');
        let s2 = if (p#up <= 1 and p#left <= 2) 3 else 2;                    // 上左受光
        let s3 = if (p#up <= 0 and p#left <= 0) 4 else s2;                   // 角のきらめき
        let s4 = if (p#down <= 0 or p#right <= 0) Int32.min(s3, 1) else s3;  // 下右の影
        let j  = hash01(gx, gy, 61);
        let i  = if (j > 0.92 and s4 == 2) 3 else if (j < 0.10) Int32.max(1, s4 - 1) else s4;
        let idx = Int32.max(1, Int32.min(4, i));
        let full = rampAt(t#stone, idx);
        { ground = rampAt(t#stone, 2), arch = full, weather = full,
          light = neutralRelief(reliefOfIdx(idx)), full = full }

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

    // ════════════════════════════════════════════════════════
    // モチーフ画家（作業B: 材質領域の上に本物のモチーフを描く）
    // ════════════════════════════════════════════════════════
    // 保つのはセルの意味（壁/床/水/虚空の粗い材質分類）とタイル境界の接続互換だけ。原本の線画・石割りは
    // 使わず、壁帯にはグローバル格子（隣接タイルで共有 = 継ぎ目で割れない）でモチーフの部品を敷き詰める:
    // 花は花の頭（花弁リング＋花芯）、金属パネルは矩形の面バンド＋発光目地、砂岩は丸石積みの面バンド。

    /// 全チャンネル同色の Stg（モチーフの塗り。層分解診断は Lamp/green のみ使うので light は一定）。
    def flatStg(c: (Int32, Int32, Int32)): Stg =
        { ground = c, arch = c, weather = c, light = neutralRelief(1.0), full = c }

    def voidStg(t: Theme): Stg = flatStg(rgbOf(t#voidC))

    // ── お花畑（作業B: セル別に石領域を花で装飾する）──
    // 咲く生け垣: 壁石は連続する葉のテクスチャ（生け垣）に、大輪(桃)/中輪(紫)/小花(白)/蕾を配置した
    // 「庭の一区画」を敷く。同じ花の等間隔並べを避け、部品の種類と大きさの変化を主役にする。
    // 床石→草地(クローバー斑+稀に小花)、水→澄んだ池(睡蓮)、木→緑の茎、骨→白い小花。
    // 継ぎ目互換: 壁の内部画素（4 近傍が非虚空 = tileSeamBreaks の検査対象）は 26px 周期の庭配置だけを描き、
    // 縁画素（虚空に接する）にだけ位置ハッシュで種類が変わる花を足す（縁は継ぎ目非対象 = セル間の変化を作れる）。
    // 部品ランプ: 大輪=stone(桃)・中輪=metal(紫)・小花/骨=bone(白)・葉/草=plant・池=water・茎=wood・芯=accentA/B/C。

    def fdiv(a: Int32, b: Int32): Int32 = if (a >= 0) a / b else 0 - (((0 - a) + b - 1) / b)

    type alias PxOpt = Option[(Int32, Int32, Int32)]
    def petalCol(t: Theme, i: Int32): (Int32, Int32, Int32) = rampAt(t#stone, i)
    def lilacCol(t: Theme, i: Int32): (Int32, Int32, Int32) = rampAt(t#metal, i)
    def whiteCol(t: Theme, i: Int32): (Int32, Int32, Int32) = rampAt(t#bone, i)
    def leafCol(t: Theme, i: Int32): (Int32, Int32, Int32)  = rampAt(t#plant, i)

    /// 大輪（桃・6 弁・黄芯）。中心からの (dx,dy) → 花弁/芯色 or None。花弁分割は |sin(3θ)|²（三角関数不使用）。
    def bigFlowerAt(t: Theme, dx: Int32, dy: Int32): PxOpt =
        let d2 = dx * dx + dy * dy;
        if (d2 <= 1) Some(rgbOf(t#accentB))
        else if (d2 <= 4) Some(rgbOf(t#accentA))
        else if (d2 <= 30) {
            let t3 = 3 * dx * dx - dy * dy;
            let sep = Int32.toFloat64(dy * dy * t3 * t3);
            let dd3 = Int32.toFloat64(d2 * d2 * d2);
            let lit = if (dy <= -1) 4 else if (dy >= 2) 2 else 3;
            let rim = if (d2 > 22) lit - 1 else lit;
            let idx = if (sep < 0.02 * dd3) rim - 2 else if (sep < 0.30 * dd3) rim - 1 else rim;
            Some(petalCol(t, idx))
        } else None

    /// 中輪（紫・丸め・黄芯）。
    def medFlowerAt(t: Theme, dx: Int32, dy: Int32): PxOpt =
        let d2 = dx * dx + dy * dy;
        if (d2 <= 1) Some(rgbOf(t#accentA))
        else if (d2 <= 11) {
            let lit = if (dy <= -1) 2 else if (dy >= 2) 0 else 1;
            let t3 = 2 * dx * dx - dy * dy;
            let idx = if (d2 > 6 and Int32.toFloat64(t3 * t3) > 0.55 * Int32.toFloat64(d2 * d2)) lit - 1 else lit;
            Some(lilacCol(t, idx))
        } else None

    /// 小花（白・雛菊・黄芯）。
    def smallFlowerAt(t: Theme, dx: Int32, dy: Int32): PxOpt =
        let d2 = dx * dx + dy * dy;
        if (d2 <= 0) Some(rgbOf(t#accentA))
        else if (d2 <= 5) Some(whiteCol(t, if (dy <= 0) 3 else 2))
        else None

    /// 蕾（緑の萼 + 桃の先が覗く）。
    def budAt(t: Theme, dx: Int32, dy: Int32): PxOpt =
        if (dy <= -2 and dy >= -4 and Int32.abs(dx) <= 1) Some(petalCol(t, if (dx == 0) 3 else 2))
        else if (dx * dx + dy * dy <= 4 and dy >= -1) Some(leafCol(t, if (dx - dy <= 0) 2 else 1))
        else None

    def partByTag(t: Theme, tag: Int32, dx: Int32, dy: Int32): PxOpt = match tag {
        case 0 => bigFlowerAt(t, dx, dy)
        case 1 => medFlowerAt(t, dx, dy)
        case 2 => smallFlowerAt(t, dx, dy)
        case _ => budAt(t, dx, dy)
    }

    /// 葉の生け垣（連続テクスチャ）。13px ずらし格子の 4 小葉の最寄りで陰影。
    /// tone/tilt は (ai+aj) の偶奇＝26px 周期ゆえ内部画素でも継ぎ目安全。
    def foliageAt(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let li = fdiv(gx, 13); let lj = fdiv(gy, 13);
        let subs = (2, 2) :: (8, 4) :: (4, 9) :: (10, 10) :: Nil;
        let cands = List.flatMap(aj ->
            List.flatMap(ai -> {
                let off  = if (Int32.modulo(aj, 2) != 0) 6 else 0;
                let tilt = if (Int32.modulo(ai + aj, 2) == 0) 1 else -1;
                List.map(s -> { let (sx, sy) = s; (ai * 13 + sx + off, aj * 13 + sy, tilt) }, subs)
            }, (li - 1) :: li :: (li + 1) :: Nil),
            (lj - 1) :: lj :: (lj + 1) :: Nil);
        let (_, tone) = List.foldLeft((acc, c) -> {
            let (bd, _) = acc;
            let (cx, cy, tilt) = c;
            let dx = gx - cx; let dy = gy - cy;
            let q = 2 * dx * dx + dy * dy + tilt * dx * dy;
            let d = dx * dx + dy * dy;
            if (q <= 7 and d < bd) (d, if (dy + tilt * dx <= -1) 2 else if (q >= 6) 0 else 1) else acc
        }, (999, 0), cands);
        leafCol(t, tone)

    /// 26px 周期の庭配置（大輪/中輪/小花/蕾を離れた位置に固定）。(kindTag, ox, oy)。
    def gardenAnchors(): List[(Int32, Int32, Int32)] =
        (0, 7, 6) :: (1, 20, 12) :: (2, 13, 21) :: (3, 3, 17) :: (2, 24, 3) :: Nil

    /// 最寄りの庭花（各アンカーの 4 近傍タイルを走査）。(最短二乗距離, 色 or None)。
    def gardenFlower(t: Theme, gx: Int32, gy: Int32): (Int32, PxOpt) =
        List.foldLeft((acc, a) -> {
            let (kind, ox, oy) = a;
            let ci = fdiv(gx - ox, 26); let cj = fdiv(gy - oy, 26);
            let cells = (ci, cj) :: (ci + 1, cj) :: (ci, cj + 1) :: (ci + 1, cj + 1) :: Nil;
            List.foldLeft((acc2, cc) -> {
                let (bd, _) = acc2;
                let (ai, aj) = cc;
                let dx = gx - (ai * 26 + ox); let dy = gy - (aj * 26 + oy);
                let d = dx * dx + dy * dy;
                if (d < bd)
                    match partByTag(t, kind, dx, dy) {
                        case Some(c) => (d, Some(c))
                        case None    => acc2
                    }
                else acc2
            }, acc, cells)
        }, (999999, None), gardenAnchors())

    /// 縁画素だけの追加花（13px 格子・位置ハッシュで種類が変わる）。基準 (bd0,c0) より近い花で上書き。
    def edgeFlower(t: Theme, gx: Int32, gy: Int32, seed: (Int32, PxOpt)): (Int32, PxOpt) =
        let ci = fdiv(gx - 6, 13); let cj = fdiv(gy - 6, 13);
        let cells = List.flatMap(aj -> List.map(ai -> (ai, aj), (ci - 1) :: ci :: (ci + 1) :: Nil),
                                 (cj - 1) :: cj :: (cj + 1) :: Nil);
        List.foldLeft((acc, cc) -> {
            let (bd, _) = acc;
            let (ai, aj) = cc;
            let r = hash01(ai, aj, 7);
            let tag = if (r < 0.16) 0 else if (r < 0.30) 1 else if (r < 0.42) 2 else -1;
            if (tag < 0) acc
            else {
                let jx = ri(hash01(ai, aj, 11) * 7.0) - 3;
                let jy = ri(hash01(ai, aj, 13) * 7.0) - 3;
                let dx = gx - (ai * 13 + 6 + jx); let dy = gy - (aj * 13 + 6 + jy);
                let d = dx * dx + dy * dy;
                if (d < bd)
                    match partByTag(t, tag, dx, dy) {
                        case Some(c) => (d, Some(c))
                        case None    => acc
                    }
                else acc
            }
        }, seed, cells)

    /// tileSeamBreaks の interior と一致: 壁石(row5/床でない)かつ 4 近傍が非虚空。
    def interiorWall(col: Int32, row: Int32, gx: Int32, gy: Int32): Bool =
        let raw = maskCharAt(col, row, Int32.modulo(gx, cell()), Int32.modulo(gy, cell()));
        if (baseChar(raw) != 's') false
        else if (row == 5 or (row == 6 and col >= 3 and col <= 8)) false
        else solidGlobal(gx, gy - 1) and solidGlobal(gx, gy + 1)
             and solidGlobal(gx - 1, gy) and solidGlobal(gx + 1, gy)

    /// 壁石（生け垣）= 庭花（26 周期）+ 縁の追加花、無ければ葉。
    def gardenAt(t: Theme, col: Int32, row: Int32, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let base = gardenFlower(t, gx, gy);
        let (_, c) = if (interiorWall(col, row, gx, gy)) base else edgeFlower(t, gx, gy, base);
        match c {
            case Some(cc) => cc
            case None     => foliageAt(t, gx, gy)
        }

    /// row5 前面帯 → 葉の生け垣にまばらな小花を散らす。
    def hedgeAt(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        if (hash01(fdiv(gx, 4), fdiv(gy, 4), 23) > 0.86 and hash01(gx, gy, 29) > 0.55)
            match smallFlowerAt(t, gx - (fdiv(gx, 4) * 4 + 2), gy - (fdiv(gy, 4) * 4 + 2)) {
                case Some(c) => c
                case None    => foliageAt(t, gx, gy)
            }
        else foliageAt(t, gx, gy)

    /// 骨 → 白い小花の群れ（4px 格子）。
    def whiteSmallAt(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        match smallFlowerAt(t, gx - (fdiv(gx, 4) * 4 + 2), gy - (fdiv(gy, 4) * 4 + 2)) {
            case Some(c) => c
            case None    => foliageAt(t, gx, gy)
        }

    /// 床 → 草地。稀に小花、クローバー斑、基調 2 段の緑。
    def floorGrassAt(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        if (hash01(fdiv(gx, 5), fdiv(gy, 5), 47) > 0.95 and hash01(gx, gy, 53) > 0.7) whiteCol(t, 2)
        else if (hash01(fdiv(gx, 4), fdiv(gy, 4), 41) > 0.8 and hash01(gx, gy, 43) > 0.5) leafCol(t, 2)
        else leafCol(t, if (hash01(gx, fdiv(gy, 2), 31) < 0.45) 0 else 1)

    /// 水 → 澄んだ池。石の真下は泡リム、まばらに睡蓮、基調はさざ波。
    def pondRipple(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let ripple = hash01(fdiv(gx, 2), fdiv(gy, 3), 91);
        rampAt(t#water, if (hash01(gx, gy, 89) > 0.985) 4 else if (ripple < 0.33) 2 else 3)
    def pondAt(t: Theme, gx: Int32, gy: Int32, stoneUp: Bool): (Int32, Int32, Int32) =
        if (stoneUp) rampAt(t#water, 4)
        else if (hash01(fdiv(gx, 9), fdiv(gy, 9), 59) > 0.7) {
            let lcx = fdiv(gx, 9) * 9 + 4; let lcy = fdiv(gy, 9) * 9 + 4;
            let dd = (gx - lcx) * (gx - lcx) + (gy - lcy) * (gy - lcy);
            if (dd <= 1) rgbOf(t#accentC) else if (dd <= 6) leafCol(t, 1) else pondRipple(t, gx, gy)
        } else pondRipple(t, gx, gy)

    /// 木 → 緑の茎/蔓。
    def stemAt(t: Theme, gx: Int32, gy: Int32): (Int32, Int32, Int32) =
        let j = hash01(gx, fdiv(gy, 3), 43);
        rampAt(t#wood, if (j < 0.4) 0 else if (j < 0.85) 1 else 2)

    /// 壁 → 生け垣の花、床/植物 → 草地、水 → 池、木 → 茎、骨 → 白い小花。
    def flowerStage(t: Theme, col: Int32, row: Int32, gx: Int32, gy: Int32, raw: Char): Stg =
        match baseChar(raw) {
            case 's' =>
                if (row == 6 and col >= 3 and col <= 8) flatStg(floorGrassAt(t, gx, gy))
                else if (row == 5) flatStg(hedgeAt(t, gx, gy))
                else flatStg(gardenAt(t, col, row, gx, gy))
            case 'w' => flatStg(pondAt(t, gx, gy, charAtGlobal(gx, gy - 1) == 's'))
            case 'k' => flatStg(stemAt(t, gx, gy))
            case 'p' => flatStg(floorGrassAt(t, gx, gy))
            case 'b' => flatStg(whiteSmallAt(t, gx, gy))
            case 'm' => flatStg(gardenAt(t, col, row, gx, gy))
            case _   => voidStg(t)
        }

}
