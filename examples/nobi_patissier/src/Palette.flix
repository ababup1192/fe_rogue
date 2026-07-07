// Palette — この作品で使う色をぜんぶ名前で持つ（コード中に色リテラルを書かない）。
// 色は **PICO-8 パレット**（かわいい系の定番 16 色）から選ぶ。
//   #000000 黒 / #1d2b53 ネイビー / #7e2553 プラム / #008751 深緑 / #ab5236 茶 /
//   #5f574f 暗灰 / #c2c3c7 明灰 / #fff1e8 生成り白 / #ff004d 赤 / #ffa300 オレンジ /
//   #ffec27 黄 / #00e436 緑 / #29adff 青 / #83769c 藤 / #ff77a8 ピンク / #ffccaa ピーチ
mod Palette {

    // ── のび ──

    /// のびの塗り分け一式。body = 体、deep = 陰と背中の模様、belly = おなか、
    /// eye = 目、cheek = ほっぺ、claw = 爪。
    pub type alias NobiSkin = {
        body = Color, deep = Color, belly = Color, eye = Color, cheek = Color, claw = Color
    }

    /// 明るい緑ののび（基本）。
    pub def nobiBright(): NobiSkin =
        { body = {r = 0.000000f32, g = 0.894118f32, b = 0.211765f32},   // #00e436
          deep = {r = 0.000000f32, g = 0.529412f32, b = 0.317647f32},   // #008751
          belly = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32},  // #fff1e8
          eye = {r = 0.000000f32, g = 0.000000f32, b = 0.000000f32},    // #000000
          cheek = {r = 1.000000f32, g = 0.466667f32, b = 0.658824f32},  // #ff77a8
          claw = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32} }  // #ab5236

    /// 深緑ののび（色比較用）。
    pub def nobiDeep(): NobiSkin =
        { body = {r = 0.000000f32, g = 0.529412f32, b = 0.317647f32},   // #008751
          deep = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32},   // #1d2b53
          belly = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32},  // #fff1e8
          eye = {r = 0.000000f32, g = 0.000000f32, b = 0.000000f32},    // #000000
          cheek = {r = 1.000000f32, g = 0.466667f32, b = 0.658824f32},  // #ff77a8
          claw = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32} }  // #ab5236

    /// パティシエ帽（白トック帽）とその陰。
    pub def hat(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}      // #fff1e8
    pub def hatShade(): Color = {r = 0.760784f32, g = 0.764706f32, b = 0.780392f32} // #c2c3c7
    pub def glint(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}    // #fff1e8

    // ── キッチンの色調 3 案 ──

    pub type alias KitchenTone = {
        wall = Color, wallLine = Color, floorA = Color, floorB = Color,
        counter = Color, counterTop = Color, trim = Color
    }

    /// ピーチ系（あたたかいお菓子屋さん）。
    pub def toneCream(): KitchenTone =
        { wall = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32},      // #ffccaa
          wallLine = {r = 1.000000f32, g = 0.639216f32, b = 0.000000f32},  // #ffa300
          floorA = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32},    // #ffccaa
          floorB = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32},    // #fff1e8
          counter = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32},   // #ab5236
          counterTop = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32},// #ffccaa
          trim = {r = 0.372549f32, g = 0.341176f32, b = 0.309804f32} }     // #5f574f

    /// ソーダ系（すずしい洋菓子工房）。
    pub def toneMint(): KitchenTone =
        { wall = {r = 0.160784f32, g = 0.678431f32, b = 1.000000f32},      // #29adff
          wallLine = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32},  // #1d2b53
          floorA = {r = 0.760784f32, g = 0.764706f32, b = 0.780392f32},    // #c2c3c7
          floorB = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32},    // #fff1e8
          counter = {r = 0.513725f32, g = 0.462745f32, b = 0.611765f32},   // #83769c
          counterTop = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32},// #fff1e8
          trim = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32} }     // #1d2b53

    /// カントリー系（山小屋のパン屋）。
    pub def toneWood(): KitchenTone =
        { wall = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32},      // #ab5236
          wallLine = {r = 0.372549f32, g = 0.341176f32, b = 0.309804f32},  // #5f574f
          floorA = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32},    // #ffccaa
          floorB = {r = 1.000000f32, g = 0.639216f32, b = 0.000000f32},    // #ffa300
          counter = {r = 0.372549f32, g = 0.341176f32, b = 0.309804f32},   // #5f574f
          counterTop = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32},// #ffccaa
          trim = {r = 0.494118f32, g = 0.145098f32, b = 0.325490f32} }     // #7e2553

    // ── 持ち場・小物・生地 ──

    pub def ovenBody(): Color = {r = 0.372549f32, g = 0.341176f32, b = 0.309804f32}  // #5f574f
    pub def ovenDark(): Color = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32}  // #1d2b53
    pub def ovenWindow(): Color = {r = 0.000000f32, g = 0.000000f32, b = 0.000000f32}// #000000
    pub def fire(): Color = {r = 1.000000f32, g = 0.639216f32, b = 0.000000f32}      // #ffa300
    pub def fireHot(): Color = {r = 1.000000f32, g = 0.925490f32, b = 0.152941f32}   // #ffec27
    pub def metal(): Color = {r = 0.760784f32, g = 0.764706f32, b = 0.780392f32}     // #c2c3c7
    pub def metalDark(): Color = {r = 0.372549f32, g = 0.341176f32, b = 0.309804f32} // #5f574f
    pub def dough(): Color = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32}     // #ffccaa
    pub def counterBoard(): Color = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32} // #ab5236
    pub def cookie(): Color = {r = 1.000000f32, g = 0.639216f32, b = 0.000000f32}    // #ffa300
    pub def choco(): Color = {r = 0.670588f32, g = 0.321569f32, b = 0.211765f32}     // #ab5236

    // ── 品物アイコン ──

    pub def paper(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}     // #fff1e8
    pub def paperShade(): Color = {r = 0.760784f32, g = 0.764706f32, b = 0.780392f32}// #c2c3c7
    pub def butter(): Color = {r = 1.000000f32, g = 0.925490f32, b = 0.152941f32}    // #ffec27
    pub def sugar(): Color = {r = 0.760784f32, g = 0.764706f32, b = 0.780392f32}     // #c2c3c7
    pub def mitten(): Color = {r = 1.000000f32, g = 0.000000f32, b = 0.301961f32}    // #ff004d
    pub def fish(): Color = {r = 0.160784f32, g = 0.678431f32, b = 1.000000f32}      // #29adff
    pub def fishTail(): Color = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32}  // #1d2b53
    pub def soap(): Color = {r = 1.000000f32, g = 0.466667f32, b = 0.658824f32}      // #ff77a8
    pub def boot(): Color = {r = 1.000000f32, g = 0.925490f32, b = 0.152941f32}      // #ffec27
    pub def star(): Color = {r = 1.000000f32, g = 0.925490f32, b = 0.152941f32}      // #ffec27
    pub def heart(): Color = {r = 1.000000f32, g = 0.000000f32, b = 0.301961f32}     // #ff004d
    pub def milk(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}      // #fff1e8
    pub def milkCap(): Color = {r = 0.160784f32, g = 0.678431f32, b = 1.000000f32}   // #29adff
    pub def eggShell(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}  // #fff1e8

    // ── UI ──

    pub def hudBg(): Color = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32}     // #1d2b53
    pub def timeGauge(): Color = {r = 0.000000f32, g = 0.894118f32, b = 0.211765f32} // #00e436
    pub def timeLow(): Color = {r = 1.000000f32, g = 0.000000f32, b = 0.301961f32}   // #ff004d
    pub def uiAccent(): Color = {r = 1.000000f32, g = 0.925490f32, b = 0.152941f32}  // #ffec27
    pub def uiText(): Color = {r = 1.000000f32, g = 0.945098f32, b = 0.909804f32}    // #fff1e8
    pub def slotBg(): Color = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32}    // #1d2b53
    pub def slotEdge(): Color = {r = 1.000000f32, g = 0.800000f32, b = 0.666667f32}  // #ffccaa

    /// ギャラリーの背景（パステルが映える濃紺）。
    pub def galleryBg(): Color = {r = 0.113725f32, g = 0.168627f32, b = 0.325490f32} // #1d2b53
}
