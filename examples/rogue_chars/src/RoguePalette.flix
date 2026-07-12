// RoguePalette — DB32（DawnBringer 32）全 32 色。キャラの描画コードは色リテラルを直接
// 書かず、必ずここの色名を参照する（TestLint が全ピクセルの所属を機械検査する）。
// 各 def は /255 で正規化した DB32 の正確な 16 進値を返す。

mod RoguePalette {

    pub def black(): Color = {r = 0.000000f32, g = 0.000000f32, b = 0.000000f32}      // #000000
    pub def night(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}      // #222034
    pub def plum(): Color = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}       // #45283c
    pub def darkBrown(): Color = {r = 0.400000f32, g = 0.223529f32, b = 0.192157f32}  // #663931
    pub def brown(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}      // #8f563b
    pub def orange(): Color = {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}     // #df7126
    pub def tan(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32}        // #d9a066
    pub def skin(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}       // #eec39a
    pub def yellow(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}     // #fbf236
    pub def lightGreen(): Color = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32} // #99e550
    pub def green(): Color = {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32}      // #6abe30
    pub def teal(): Color = {r = 0.215686f32, g = 0.580392f32, b = 0.431373f32}       // #37946e
    pub def darkGreen(): Color = {r = 0.294118f32, g = 0.411765f32, b = 0.184314f32}  // #4b692f
    pub def olive(): Color = {r = 0.321569f32, g = 0.294118f32, b = 0.141176f32}      // #524b24
    pub def darkSlate(): Color = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32}  // #323c39
    pub def navy(): Color = {r = 0.247059f32, g = 0.247059f32, b = 0.454902f32}       // #3f3f74
    pub def seaBlue(): Color = {r = 0.188235f32, g = 0.376471f32, b = 0.509804f32}    // #306082
    pub def royalBlue(): Color = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    pub def skyBlue(): Color = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}    // #639bff
    pub def cyan(): Color = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}       // #5fcde4
    pub def paleBlue(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}   // #cbdbfc
    pub def white(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}      // #ffffff
    pub def silver(): Color = {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}     // #9badb7
    pub def gray(): Color = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}       // #847e87
    pub def dimGray(): Color = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}    // #696a6a
    pub def darkGray(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}   // #595652
    pub def purple(): Color = {r = 0.462745f32, g = 0.258824f32, b = 0.541176f32}     // #76428a
    pub def red(): Color = {r = 0.674510f32, g = 0.196078f32, b = 0.196078f32}        // #ac3232
    pub def salmon(): Color = {r = 0.850980f32, g = 0.341176f32, b = 0.388235f32}     // #d95763
    pub def pink(): Color = {r = 0.843137f32, g = 0.482353f32, b = 0.729412f32}       // #d77bba
    pub def moss(): Color = {r = 0.560784f32, g = 0.592157f32, b = 0.290196f32}       // #8f974a
    pub def mustard(): Color = {r = 0.541176f32, g = 0.435294f32, b = 0.188235f32}    // #8a6f30

    /// 全 32 色。TestLint がキャラの全ピクセルの所属を照合する正典。
    pub def all(): List[Color] =
        black() :: night() :: plum() :: darkBrown() :: brown() :: orange() :: tan() ::
        skin() :: yellow() :: lightGreen() :: green() :: teal() :: darkGreen() :: olive() ::
        darkSlate() :: navy() :: seaBlue() :: royalBlue() :: skyBlue() :: cyan() ::
        paleBlue() :: white() :: silver() :: gray() :: dimGray() :: darkGray() ::
        purple() :: red() :: salmon() :: pink() :: moss() :: mustard() :: Nil
}
