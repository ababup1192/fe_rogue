// ShaderDoc — 面（矩形）を GPU シェーダーで塗るための「宣言データ」。
// 生の GLSL を書かず、少数の部品（値の場・色・出力）を組み合わせて水面のような
// 連続した見た目を作る。ここでは部品の型（Spec）と、それを GLSL 文字列へ変換する
// codegen（ShaderGen）、CPU で同じ式を評価する検証用の評価器（ShaderEval）を持つ。
// 実際に GPU で走らせる仕事はバックエンド（render_gl）が担う。
// 利用例: 水面の網目（Worley F2−F1）を時間で揺らしながら塗る / 位置に応じたグラデを塗る。
//
// 語彙は「値の場（スカラー）」→「色」→「出力」の三段。任意 GLSL は書けない — 語彙の合成だけが
// GLSL になる。座標変換（Scaled/Warp）は inner の場が見る uv を差し替える形で表す。
// 時間は uTime uniform として codegen が差し込む（Scroll / cycleRate がこれに掛かる）。

mod ShaderDoc {

    /// 位置 (u,v) のどちらの軸を読むか。
    pub enum Axis with Eq, ToString {
        case U
        case V
    }

    /// Worley（セルノイズ）の出力の選び方。F2mF1 が網目（水面の目地）。
    pub enum WorleyOut with Eq, ToString {
        case F1     // 一番近いセル点までの距離（斑点）
        case F2     // 二番目に近い点までの距離
        case F2mF1  // F2 − F1（セル境界＝網目）
    }

    /// 値の場（スカラー・0..1 目安）。GPU では 1 個の float、CPU では Float64 になる。
    /// Scaled / Warp は「inner が見る座標」を変える座標変換ノード（uv を差し替える）。
    pub enum Field {
        /// どこでも同じ値。
        case Const(Float64)
        /// 位置 (u,v) の指定軸（0..1）。
        case Uv({ axis = Axis })
        /// セルノイズ。out=F2mF1 で網目。seed で模様が変わる。
        case Worley({ scale = Float64, seed = Int32, out = WorleyOut })
        /// 雲状ノイズ（オクターブを重ねた value noise・octaves は小さめに）。
        case Fbm({ octaves = Int32, scale = Float64, seed = Int32 })
        /// lo..hi の間でなめらかに 0→1（それ以外は 0 か 1 にクランプ）。
        case Smoothstep({ lo = Float64, hi = Float64, of = Field })
        /// inner の場を、uv を factor 倍 + 時刻スクロールした座標で読む
        /// （scroll は uv に uTime*scroll を足す・タイル密度と流れを与える）。
        case Scaled({ factor = Float64, scroll = Vec2.Vec2, of = Field })
        /// ドメインワープ。inner を、fbm で amount だけ揺らした座標で読む（網目をうねらせる）。
        case Warp({ amount = Float64, scale = Float64, seed = Int32, of = Field })
        /// 定数比 t で 2 つの場を混ぜる（線形補間）。
        case Mix({ a = Field, b = Field, t = Float64 })
        /// 場 by（0..1）で 2 つの場を混ぜる（by=0 で a・1 で b）。
        case Blend({ a = Field, b = Field, by = Field })
        /// 丸マスク。uv 空間で中心 (cx,cy) から radius 以内は 1、radius→radius+feather で
        /// なめらかに 0（縁が soft に消える）。矩形の描画枠の中を丸い池型に抜く alpha に使う。
        case Disk({ cx = Float64, cy = Float64, radius = Float64, feather = Float64 })
    }

    /// 面の色（rgb）。
    pub enum Shade {
        /// 単色。
        case Solid(Color)
        /// 2 色を field（0..1）で補間する。cycleRate>0 なら時間で位相が回る（パレット循環）。
        case Ramp({ lo = Color, hi = Color, field = Field })
    }

    /// 面の出力（このピクセルの最終色とアルファ）。
    pub enum Out {
        /// 面全体を shade で塗る（alpha は場で決める）。
        case Fill({ shade = Shade, alpha = Field })
    }

    /// シェーダー面 1 枚ぶんの宣言（theme.json の materials[i].surface に対応する予定）。
    /// cycleRate = パレット循環の速さ（Ramp の位相 uniform に掛かる。0 で静止）。
    pub type alias Spec = {
        name = String,
        cycleRate = Float64,
        out = Out
    }

    /// 動作確認用の最小 Spec: 時間で lo↔hi を行き来する横グラデ（Uv U + 位相回し）。
    /// codegen と GPU 配管を端から端まで通すための「一番危なくない絵」。
    pub def demoSurface(): Spec =
        { name = "demo",
          cycleRate = 0.5,
          out = Out.Fill({
              shade = Shade.Ramp({ lo = { r = 0.15f32, g = 0.35f32, b = 0.55f32 },
                                   hi = { r = 0.55f32, g = 0.85f32, b = 0.95f32 },
                                   field = Field.Uv({ axis = Axis.U }) }),
              alpha = Field.Const(1.0) }) }

    /// 水のリアル版: Worley F2−F1 の網目（目地）を、ドメインワープでうねらせ、
    /// 時刻スクロールで流し、低彩度ティール→淡シアン白の 2 色パレットで塗る。
    /// パレットは cycleRate で位相が回る（時間で色が呼吸する）。
    ///   veins = Worley(F2mF1) を Warp でうねらせる
    ///   line  = Smoothstep(0, 0.06, veins) で細い目地に絞る
    ///   pool  = Warp(Disk) で真円を崩した不定形の丸マスク（縁がゆらぐ水たまり）
    pub def waterVeins(): Spec =
        let veins =
            Field.Warp({ amount = 0.08, scale = 4.0, seed = 7,
                of = Field.Scaled({ factor = 5.0, scroll = { x = 0.11, y = 0.07 },
                    of = Field.Worley({ scale = 1.0, seed = 42, out = WorleyOut.F2mF1 }) }) });
        let line = Field.Smoothstep({ lo = 0.0, hi = 0.06, of = veins });
        let pool = Field.Warp({ amount = 0.06, scale = 3.0, seed = 11,
                    of = Field.Disk({ cx = 0.5, cy = 0.5, radius = 0.42, feather = 0.12 }) });
        { name = "water_veins",
          cycleRate = 0.25,
          out = Out.Fill({
              shade = Shade.Ramp({ lo = { r = 0.35f32, g = 0.55f32, b = 0.60f32 },
                                   hi = { r = 0.80f32, g = 0.95f32, b = 0.98f32 },
                                   field = line }),
              alpha = pool }) }

    /// マグマの正典 Spec（水と同じ骨格を熱いパレットで組み替えた対の素材）。
    /// 冷えた岩盤のひび割れ = Worley(F2mF1) を Warp でうねらせ（重い対流）、岩肌のムラ = Fbm を
    /// Blend で混ぜて割れ目以外ものっぺりさせない。割れ目を太めの光る帯（Smoothstep hi 大）にして
    /// 黒い殻→橙→黄白の Ramp で「割れ目が明るく光る」向きに塗る。cycleRate で発光が脈打つ。
    /// alpha は Disk で丸い溶岩溜まりにする（水の丸池と対で見せられる）。
    pub def lavaVeins(): Spec =
        let cracks =
            Field.Warp({ amount = 0.14, scale = 3.0, seed = 3,
                of = Field.Scaled({ factor = 5.0, scroll = { x = 0.01, y = 0.008 },
                    of = Field.Worley({ scale = 1.0, seed = 17, out = WorleyOut.F2mF1 }) }) });
        // 割れ目を太めの光る帯に絞りつつ、岩肌のムラ(Fbm)を薄く混ぜてのっぺりを崩す。
        let mottle = Field.Fbm({ octaves = 3, scale = 4.0, seed = 23 });
        let glow = Field.Blend({ a = Field.Smoothstep({ lo = 0.0, hi = 0.12, of = cracks }),
                                 b = mottle, by = Field.Const(0.25) });
        let pool = Field.Warp({ amount = 0.06, scale = 3.0, seed = 29,
                    of = Field.Disk({ cx = 0.5, cy = 0.5, radius = 0.42, feather = 0.12 }) });
        { name = "lava",
          cycleRate = 0.35,
          out = Out.Fill({
              shade = Shade.Ramp({ lo = { r = 0.10f32, g = 0.04f32, b = 0.02f32 },
                                   hi = { r = 1.0f32,  g = 0.88f32, b = 0.54f32 },
                                   field = glow }),
              alpha = pool }) }

    /// この Spec を塗ったときの「代表色」（F8 注釈・SoftRaster など GLSL を走らせられない
    /// 経路のベタ塗り用）。網目までは写せないが「そこに面がある」ことは絵に残る。
    /// lo/hi の中点を返す（Solid はその色そのもの）。
    pub def representativeColor(spec: Spec): Color =
        match spec#out {
            case Out.Fill(f) => shadeColor(f#shade)
        }

    def shadeColor(shade: Shade): Color =
        match shade {
            case Shade.Solid(c) => c
            case Shade.Ramp(r)  =>
                { r = (r#lo#r + r#hi#r) / 2.0f32,
                  g = (r#lo#g + r#hi#g) / 2.0f32,
                  b = (r#lo#b + r#hi#b) / 2.0f32 }
        }
}
