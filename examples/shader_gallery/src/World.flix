// エディタ全体の状態。左上の「池」タイルはこの Params から毎フレーム組み立てる。
// 右上のマグマ2枚は JSON から一度読むだけの静的な絵。dragging はいまマウスで
// 掴んでいるスライダーの key（掴んでいなければ None）。
// page はいま見ているページ（0=水エディタ・1=岸エディタ）。Space で切り替える。

mod World {

    /// 池シェーダーのツマミ一式。スライダー9本がこの値を上下させる。
    pub type alias Params = {
        netSize = Float64, netThick = Float64, netBright = Float64,
        flowSpeed = Float64, warpAmt = Float64, jag = Float64, mottle = Float64,
        alpha = Float64, colR = Float64, colG = Float64, colB = Float64 }

    /// 岸（池の縁）のツマミ一式。草の凸凹と、土の帯（下端が凸凹する面）をまとめて持つ。
    /// gCol* は草の色、gJagged は凸凹の尖り具合(0=丸/1=三角・連続)、gBumpH は凸凹の高さ px、
    /// gOutline は草の下側の縁取り太さ px。
    /// dCol* は土の色、dirtH は土の帯の高さ px、dirtBumpH は土の下端（水との境）が
    /// 手前(下)に出たり奥(上)に引っ込んだりする凸凹の大きさ px、
    /// dirtJagged は土の下端の凸凹の尖り具合(0=丸/1=三角・連続)、outCol* は縁取りの色。
    pub type alias Shore = {
        gColR = Float64, gColG = Float64, gColB = Float64,
        gJagged = Float64, gBumpH = Float64, gOutline = Float64,
        dColR = Float64, dColG = Float64, dColB = Float64,
        dirtH = Float64, dirtBumpH = Float64, dirtJagged = Float64,
        outColR = Float64, outColG = Float64, outColB = Float64 }

    /// エディタ全体。time でシェーダーが動き、params で池が変わる。
    /// bgR/bgG/bgB は池の外に見える草原色。pondScale は池プレビュー矩形の大きさ（0.3..1 で縮む）。
    /// floorR/floorG/floorB は水底の背景色。opacity を下げるとこの色が透けて見える。
    /// 網の細かさは pondScale（＝池の大きさ）に連動して見える（dungeon と同じ・UV は矩形内 0..1）。
    /// shore は岸ページのツマミ。page は表示中のページ（0=水・1=岸）。
    pub type alias World = {
        time = Float64, params = Params, dragging = Option[String], page = Int32,
        bgR = Float64, bgG = Float64, bgB = Float64, pondScale = Float64,
        floorR = Float64, floorG = Float64, floorB = Float64, shore = Shore,
        moltenFlow = ShaderDoc.Spec, moltenMetal = ShaderDoc.Spec }

    /// 保存する 18 個のツマミをひとまとめにしたスナップショット。
    /// シェーダー 11 個（params）＋ 草原色 3 個＋池の大きさ 1 個＋水底色 3 個。
    pub type alias Settings = {
        params = Params, bgR = Float64, bgG = Float64, bgB = Float64, pondScale = Float64,
        floorR = Float64, floorG = Float64, floorB = Float64 }

    /// スライダーの初期位置（ユーザーが気に入って保存した値）。
    pub def initialParams(): Params =
        { netSize = 5.4596, netThick = 0.02, netBright = 0.4713, flowSpeed = 4.0,
          warpAmt = 0.1879, jag = 0.0839, mottle = 0.2657, alpha = 0.969,
          colR = 0.29, colG = 0.42, colB = 0.5837 }

    /// 岸ツマミの初期値。草＝緑・土＝茶・縁取り＝暗い色。
    pub def initialShore(): Shore =
        { gColR = 0.36, gColG = 0.61, gColB = 0.32,
          gJagged = 0.3, gBumpH = 6.0, gOutline = 1.5,
          dColR = 0.42, dColG = 0.29, dColB = 0.16,
          dirtH = 40.0, dirtBumpH = 8.0, dirtJagged = 0.3,
          outColR = 0.12, outColG = 0.12, outColB = 0.12 }

    /// 全ツマミの初期スナップショット。草原は dungeon の草原色 #4f7a3a、
    /// 水底は dungeon の水色 #2b6d8c。
    pub def initialSettings(): Settings =
        { params = initialParams(), bgR = 0.31, bgG = 0.478, bgB = 0.227, pondScale = 0.85,
          floorR = 0.169, floorG = 0.427, floorB = 0.549 }

    /// 保存済みの Settings・Shore（無ければ初期値）とマグマ2枚から初期状態を作る。
    pub def initial(s: Settings, shore: Shore, flow: ShaderDoc.Spec, metal: ShaderDoc.Spec): World =
        { time = 0.0, params = s#params, dragging = None, page = 0,
          bgR = s#bgR, bgG = s#bgG, bgB = s#bgB, pondScale = s#pondScale,
          floorR = s#floorR, floorG = s#floorG, floorB = s#floorB, shore = shore,
          moltenFlow = flow, moltenMetal = metal }

    /// Settings を「1行1数値・固定順」のテキストにする（保存用・18 行）。
    pub def settingsToText(s: Settings): String =
        let p = s#params;
        Float64.toString(p#netSize)   + "\n" + Float64.toString(p#netThick) + "\n" +
        Float64.toString(p#netBright) + "\n" + Float64.toString(p#flowSpeed) + "\n" +
        Float64.toString(p#warpAmt)   + "\n" + Float64.toString(p#jag)       + "\n" +
        Float64.toString(p#mottle)    + "\n" + Float64.toString(p#alpha)     + "\n" +
        Float64.toString(p#colR)      + "\n" + Float64.toString(p#colG)      + "\n" +
        Float64.toString(p#colB)      + "\n" +
        Float64.toString(s#bgR)       + "\n" + Float64.toString(s#bgG)       + "\n" +
        Float64.toString(s#bgB)       + "\n" + Float64.toString(s#pondScale) + "\n" +
        Float64.toString(s#floorR)    + "\n" + Float64.toString(s#floorG)    + "\n" +
        Float64.toString(s#floorB)

    /// Shore を「1行1数値・固定順」のテキストにする（保存用・15 行）。
    pub def shoreToText(s: Shore): String =
        Float64.toString(s#gColR)        + "\n" + Float64.toString(s#gColG)     + "\n" +
        Float64.toString(s#gColB)        + "\n" + Float64.toString(s#gJagged)   + "\n" +
        Float64.toString(s#gBumpH)       + "\n" + Float64.toString(s#gOutline)  + "\n" +
        Float64.toString(s#dColR)        + "\n" + Float64.toString(s#dColG)     + "\n" +
        Float64.toString(s#dColB)        + "\n" + Float64.toString(s#dirtH)     + "\n" +
        Float64.toString(s#dirtBumpH)    + "\n" + Float64.toString(s#dirtJagged) + "\n" +
        Float64.toString(s#outColR)      + "\n" + Float64.toString(s#outColG)   + "\n" +
        Float64.toString(s#outColB)

    /// 保存テキストを Settings に戻す。先頭 15 個（params 11 ＋ 草原色 3 ＋池の大きさ）が
    /// 揃えば Some。水底色 3 個は 16..18 番目があればそれ、無ければ初期値（古い 15 値ファイルも読める）。
    pub def settingsFromText(s: String): Option[Settings] =
        let nums = String.splitOn({ substr = "\n" }, s)
            |> List.filterMap(x -> Float64.fromString(String.trim(x)));
        let init = initialSettings();
        match nums {
            case a0 :: a1 :: a2 :: a3 :: a4 :: a5 :: a6 :: a7 :: a8 :: a9 :: a10 ::
                 b0 :: b1 :: b2 :: b3 :: rest =>
                // rest の先頭 3 個が揃えば水底色に、足りなければ初期値で埋める。
                let (fr, fg, fb) = match rest {
                    case c0 :: c1 :: c2 :: _ => (c0, c1, c2)
                    case _                   => (init#floorR, init#floorG, init#floorB)
                };
                Some({ params = { netSize = a0, netThick = a1, netBright = a2, flowSpeed = a3,
                                  warpAmt = a4, jag = a5, mottle = a6, alpha = a7,
                                  colR = a8, colG = a9, colB = a10 },
                       bgR = b0, bgG = b1, bgB = b2, pondScale = b3,
                       floorR = fr, floorG = fg, floorB = fb })
            case _ => None
        }

    /// 保存テキストを Shore に戻す。15 個の数値が揃えば Some、足りなければ None（初期値へ倒れる）。
    pub def shoreFromText(s: String): Option[Shore] =
        let nums = String.splitOn({ substr = "\n" }, s)
            |> List.filterMap(x -> Float64.fromString(String.trim(x)));
        match nums {
            case a0 :: a1 :: a2 :: a3 :: a4 :: a5 :: a6 :: a7 :: a8 :: a9 :: a10 ::
                 a11 :: a12 :: a13 :: a14 :: _ =>
                Some({ gColR = a0, gColG = a1, gColB = a2,
                       gJagged = a3, gBumpH = a4, gOutline = a5,
                       dColR = a6, dColG = a7, dColB = a8,
                       dirtH = a9, dirtBumpH = a10, dirtJagged = a11,
                       outColR = a12, outColG = a13, outColB = a14 })
            case _ => None
        }
}
