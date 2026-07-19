// スライダーの定義（key・ラベル・下限上限）と、World との読み書き、画面レイアウト。
// ここが「ツマミ」と「World のフィールド」をつなぐ一枚。
// ページごとにスライダーの並びが変わる（0=水・1=岸）。defsFor(page) がその並びを返す。

mod Sliders {

    /// スライダー1本ぶん。key で World のどのフィールドを触るか決まる。
    pub type alias Def = { key = String, label = String, lo = Float64, hi = Float64 }

    /// 水ページのスライダー全部（18本）。ラベルは英語（フォントに日本語グリフが無いため）。
    /// 上 11 本がシェーダー、次に水底色 3 本、下 4 本がプレビュー（草原色 3 ＋池の大きさ）。
    pub def waterDefs(): List[Def] =
        { key = "size",     label = "net size",      lo = 1.5,  hi = 16.0 } ::
        { key = "thick",    label = "net thickness", lo = 0.02, hi = 0.18 } ::
        { key = "bright",   label = "net glow",      lo = 0.0,  hi = 1.0  } ::
        { key = "warp",     label = "waver",         lo = 0.0,  hi = 0.40 } ::
        { key = "jag",      label = "roughness",     lo = 0.0,  hi = 0.15 } ::
        { key = "speed",    label = "flow speed",    lo = 0.0,  hi = 40.0 } ::
        { key = "mottle",   label = "mottle",        lo = 0.0,  hi = 0.4  } ::
        { key = "alpha",    label = "opacity",       lo = 0.0,  hi = 1.0  } ::
        { key = "colR",     label = "red",           lo = 0.0,  hi = 1.0  } ::
        { key = "colG",     label = "green",         lo = 0.0,  hi = 1.0  } ::
        { key = "colB",     label = "blue",          lo = 0.0,  hi = 1.0  } ::
        { key = "floorR",   label = "floor red",     lo = 0.0,  hi = 1.0  } ::
        { key = "floorG",   label = "floor green",   lo = 0.0,  hi = 1.0  } ::
        { key = "floorB",   label = "floor blue",    lo = 0.0,  hi = 1.0  } ::
        { key = "bgR",      label = "bg red",        lo = 0.0,  hi = 1.0  } ::
        { key = "bgG",      label = "bg green",      lo = 0.0,  hi = 1.0  } ::
        { key = "bgB",      label = "bg blue",       lo = 0.0,  hi = 1.0  } ::
        { key = "pondsize", label = "pond size",     lo = 0.3,  hi = 1.0  } :: Nil

    /// 岸ページのスライダー全部（17本）。上6本が草、下11本が土＋石。
    pub def shoreDefs(): List[Def] =
        { key = "gColR",    label = "grass red",     lo = 0.0,  hi = 1.0  } ::
        { key = "gColG",    label = "grass green",   lo = 0.0,  hi = 1.0  } ::
        { key = "gColB",    label = "grass blue",    lo = 0.0,  hi = 1.0  } ::
        { key = "gJagged",  label = "grass jagged",  lo = 0.0,  hi = 1.0  } ::
        { key = "gBumpH",   label = "grass bump h",  lo = 2.0,  hi = 14.0 } ::
        { key = "gOutline", label = "grass outline", lo = 0.0,  hi = 4.0  } ::
        { key = "dColR",     label = "dirt red",      lo = 0.0,  hi = 1.0  } ::
        { key = "dColG",     label = "dirt green",    lo = 0.0,  hi = 1.0  } ::
        { key = "dColB",     label = "dirt blue",     lo = 0.0,  hi = 1.0  } ::
        { key = "dirtH",     label = "dirt height",   lo = 10.0, hi = 70.0 } ::
        { key = "dirtBumpH", label = "dirt relief",   lo = 0.0,  hi = 20.0 } ::
        { key = "dirtJagged",label = "dirt jagged",   lo = 0.0,  hi = 1.0  } ::
        { key = "outColR",   label = "line red",      lo = 0.0,  hi = 1.0  } ::
        { key = "outColG",   label = "line green",    lo = 0.0,  hi = 1.0  } ::
        { key = "outColB",   label = "line blue",     lo = 0.0,  hi = 1.0  } :: Nil

    /// 表示中のページのスライダー並びを返す。0=水・それ以外=岸。
    pub def defsFor(page: Int32): List[Def] =
        if (page == 0) waterDefs() else shoreDefs()

    /// key に対応する World の今の値を読む。シェーダー系は params の中、
    /// プレビュー系（bg*・floor*・pondsize）は World 直下、岸系（g*・d*・dirt*・out*）は shore の中から。
    pub def get(w: World.World, key: String): Float64 =
        match key {
            case "bgR"      => w#bgR
            case "bgG"      => w#bgG
            case "bgB"      => w#bgB
            case "floorR"   => w#floorR
            case "floorG"   => w#floorG
            case "floorB"   => w#floorB
            case "pondsize" => w#pondScale
            case "gColR"    => w#shore#gColR
            case "gColG"    => w#shore#gColG
            case "gColB"    => w#shore#gColB
            case "gJagged"  => w#shore#gJagged
            case "gBumpH"   => w#shore#gBumpH
            case "gOutline" => w#shore#gOutline
            case "dColR"     => w#shore#dColR
            case "dColG"     => w#shore#dColG
            case "dColB"     => w#shore#dColB
            case "dirtH"     => w#shore#dirtH
            case "dirtBumpH" => w#shore#dirtBumpH
            case "dirtJagged"=> w#shore#dirtJagged
            case "outColR"  => w#shore#outColR
            case "outColG"  => w#shore#outColG
            case "outColB"  => w#shore#outColB
            case _          => getParam(w#params, key)
        }

    /// key に対応する World のフィールドを v に差し替えた新しい World を返す。
    pub def set(w: World.World, key: String, v: Float64): World.World =
        match key {
            case "bgR"      => { bgR = v | w }
            case "bgG"      => { bgG = v | w }
            case "bgB"      => { bgB = v | w }
            case "floorR"   => { floorR = v | w }
            case "floorG"   => { floorG = v | w }
            case "floorB"   => { floorB = v | w }
            case "pondsize" => { pondScale = v | w }
            case "gColR"    => { shore = { gColR = v | w#shore } | w }
            case "gColG"    => { shore = { gColG = v | w#shore } | w }
            case "gColB"    => { shore = { gColB = v | w#shore } | w }
            case "gJagged"  => { shore = { gJagged = v | w#shore } | w }
            case "gBumpH"   => { shore = { gBumpH = v | w#shore } | w }
            case "gOutline" => { shore = { gOutline = v | w#shore } | w }
            case "dColR"     => { shore = { dColR = v | w#shore } | w }
            case "dColG"     => { shore = { dColG = v | w#shore } | w }
            case "dColB"     => { shore = { dColB = v | w#shore } | w }
            case "dirtH"     => { shore = { dirtH = v | w#shore } | w }
            case "dirtBumpH" => { shore = { dirtBumpH = v | w#shore } | w }
            case "dirtJagged"=> { shore = { dirtJagged = v | w#shore } | w }
            case "outColR"  => { shore = { outColR = v | w#shore } | w }
            case "outColG"  => { shore = { outColG = v | w#shore } | w }
            case "outColB"  => { shore = { outColB = v | w#shore } | w }
            case _          => { params = setParam(w#params, key, v) | w }
        }

    /// key に対応する Params の今の値を読む。
    def getParam(p: World.Params, key: String): Float64 =
        match key {
            case "size"   => p#netSize
            case "thick"  => p#netThick
            case "bright" => p#netBright
            case "speed"  => p#flowSpeed
            case "warp"   => p#warpAmt
            case "jag"    => p#jag
            case "mottle" => p#mottle
            case "alpha"  => p#alpha
            case "colR"   => p#colR
            case "colG"   => p#colG
            case "colB"   => p#colB
            case _        => 0.0
        }

    /// key に対応する Params のフィールドを v に差し替えた新しい Params を返す。
    def setParam(p: World.Params, key: String, v: Float64): World.Params =
        match key {
            case "size"   => { netSize   = v | p }
            case "thick"  => { netThick  = v | p }
            case "bright" => { netBright = v | p }
            case "speed"  => { flowSpeed = v | p }
            case "warp"   => { warpAmt   = v | p }
            case "jag"    => { jag       = v | p }
            case "mottle" => { mottle    = v | p }
            case "alpha"  => { alpha     = v | p }
            case "colR"   => { colR      = v | p }
            case "colG"   => { colG      = v | p }
            case "colB"   => { colB      = v | p }
            case _        => p
        }

    // 画面レイアウト（design 560x480・下半分にスライダーを縦に並べる）。
    pub def labelX(): Float64 = 16.0
    pub def trackX(): Float64 = 150.0
    pub def trackW(): Float64 = 210.0
    pub def rowH(): Float64 = 14.0
    pub def y0(): Float64 = 200.0
    pub def valX(): Float64 = 372.0

    /// i 番目のスライダー行の中心 y。
    pub def rowY(i: Int32): Float64 = y0() + Int32.toFloat64(i) * rowH()
}
