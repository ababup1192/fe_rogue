// Light — 簡易2D光源から見せる絵の列を導く純関数。
// 光そのものは状態を持たない値（位置・半径・色・ハロの強さ）で、毎フレーム
// singleLightItems / multiLightItems に渡すだけで絵になる（他の Render 系と同じ並び）。
//
// 「穴あき暗幕」を描くための土台は RadialGlow が焼いた2種類の別規約テクスチャ
// （maskSprite=Multiply専用の暗幕、haloSprite=Add専用の暖色グロー）で、Light はその
// 2枚をどこに・どれだけ拡大して置くかだけを決める（画素の中身には触れない）。
mod Light {

    /// 簡易2D光源1個の値。at=位置、radius=光の届く目安半径、color=光の色、
    /// halo=Addハロの強さ0..1。
    pub type alias Light = { at = Vec2.Vec2, radius = Float64, color = Color, halo = Float64 }

    /// singleLightItems の設定。maskSprite/haloSprite は RadialGlow で焼いたテクスチャ名、
    /// maskSourceSize/haloSourceSize はそれぞれの元 px サイズ（正方形前提）。
    /// maskHoleFrac は maskSprite を焼いた RadialGlow.maskCurveWithHole の holeFrac と
    /// 同じ値（既定は RadialGlow.defaultHoleFrac()）— 「穴の実寸半径 = light#radius」を
    /// 逆算するのに使うため、焼く側と読む側で値が揃っていないと穴のサイズがずれる。
    /// darkness は mask 全体の暗さ0..1（1で穴の外が完全な黒。既定0.95）— 周囲4枚の黒帯と
    /// 同じ値を使うことで、mask の縁（完全減衰）と黒帯の濃度が連続する。
    /// z は暗幕→ハロの土台（cfg#z が暗幕、cfg#z + 1 がハロ）。
    /// 背景・目印など「穴の中に見せたい景色」は cfg#z 未満の zIndex に置くこと
    /// （Render.blended は自分より奥＝小さい zIndex にしか効かない）。
    pub type alias SingleLightConfig = {
        light = Light, viewport = Vec2.Vec2,
        maskSprite = String, maskSourceSize = Float64, maskHoleFrac = Float64,
        haloSprite = String, haloSourceSize = Float64,
        darkness = Float64,
        z = Int32
    }

    /// 単一光源の真の穴あき描画。中心の穴あき暗幕（Multiply, maskSprite）を「穴の実寸半径が
    /// light#radius になる」倍率へ引き伸ばして光の位置に1枚 → 四辺を敷き詰める黒帯4枚
    /// （mask 正方形の外側を隙間なく覆う。mask の縁と同じ darkness で連続に見える）→
    /// 色付きAddハロ（haloSprite, tint=light#color, alpha=light#halo）を光の半径ぶんに
    /// 拡大して同じ位置に重ねる。
    pub def singleLightItems(cfg: SingleLightConfig): List[Render.PlacedItem] =
        let scale = maskScale(cfg#light#radius, cfg#maskSourceSize, cfg#maskHoleFrac);
        let maskSize = cfg#maskSourceSize * scale;
        let mask = { at = cfg#light#at,
                      item = Render.sprite(cfg#maskSprite, cfg#z)
                          |> Render.scaled(scale)
                          |> Render.blended(DrawCmd.BlendMode.Multiply)
                          |> Render.fade(RenderUtil.f32(cfg#darkness)) };
        let surround = surroundBoxes(cfg#light#at, maskSize, cfg#viewport, cfg#darkness, cfg#z);
        let halo = { at = cfg#light#at,
                      item = Render.sprite(cfg#haloSprite, cfg#z + 1)
                          |> tintHalo(cfg#light)
                          |> Render.scaled(haloScale(cfg#light#radius, cfg#haloSourceSize))
                          |> Render.blended(DrawCmd.BlendMode.Add) };
        mask :: List.append(surround, halo :: Nil)

    /// 暗幕の拡大倍率。「穴の実寸半径 = light#radius」になる倍率のみ
    /// （maskCurveWithHole の平坦部 holeFrac が画像半径に占める割合なので、
    /// holeFrac × 画像半径 × scale = radius から逆算する）。画面対角線カバレッジの
    /// 下限は持たない — mask 正方形の外側は surroundBoxes が敷く黒帯が担うため、
    /// 「穴半径=radius」の不変条件を radius の大小に関わらず常に守れる。
    def maskScale(radius: Float64, maskSourceSize: Float64, holeFrac: Float64): Float64 =
        radius / (holeFrac * maskSourceSize / 2.0)

    /// mask 正方形（一辺 maskSize、at 中心）の外側を上下左右4枚の黒 box（Multiply,
    /// alpha=darkness）で隙間なく敷く。mask の縁（maskCurveWithHole の t=1 相当、
    /// 完全減衰=1−darkness）と黒帯（同じ darkness）の濃度が揃うことで、正方形の輪郭が
    /// 見えずに済む。viewport の外側まで大きめに伸ばし、画面のどの隅・どんな光位置でも
    /// 黒帯が画面全体を覆い切るようにする。
    def surroundBoxes(at: Vec2.Vec2, maskSize: Float64, viewport: Vec2.Vec2,
                       darkness: Float64, z: Int32): List[Render.PlacedItem] =
        let pad = Vec2.length(viewport);
        let half = maskSize / 2.0;
        let blackBox = (center: Vec2.Vec2, size: Vec2.Vec2) ->
            Render.boxAt(center, size, { r = 0.0f32, g = 0.0f32, b = 0.0f32 }, z)
                |> (placed -> { item = Render.blended(DrawCmd.BlendMode.Multiply, placed#item)
                                    |> Render.fade(RenderUtil.f32(darkness)) | placed });
        let wideW = maskSize + pad * 2.0;
        let tallH = maskSize + pad * 2.0;
        // 上下は mask 正方形と同じ横幅、左右は上下の帯も覆う縦幅（四隅の抜けを防ぐ）。
        blackBox({ x = at#x, y = at#y - half - pad / 2.0 }, { x = wideW, y = pad })            ::  // 上
        blackBox({ x = at#x, y = at#y + half + pad / 2.0 }, { x = wideW, y = pad })            ::  // 下
        blackBox({ x = at#x - half - pad / 2.0, y = at#y }, { x = pad, y = tallH })            ::  // 左
        blackBox({ x = at#x + half + pad / 2.0, y = at#y }, { x = pad, y = tallH })            ::  // 右
        Nil

    /// ハロを光の半径ぶんの直径へ拡大する倍率。
    def haloScale(radius: Float64, haloSourceSize: Float64): Float64 =
        radius * 2.0 / haloSourceSize

    /// ハロに光の色と強さを乗せる（Sprite の tint と alpha を差し替える薄い修飾）。
    def tintHalo(light: Light, item: Render.Item): Render.Item =
        match item {
            case Render.Item.Sprite(s) =>
                Render.Item.Sprite({ tint = light#color, alpha = RenderUtil.f32(light#halo) | s })
            case other => other
        }

    /// multiLightItems の設定。darkness は全面暗幕の濃さ0..1（1で真っ黒）。
    pub type alias MultiLightConfig = {
        lights = List[Light], darkness = Float64, viewport = Vec2.Vec2,
        haloSprite = String, haloSourceSize = Float64, z = Int32
    }

    /// 複数光源の近似。FBOが無いため複数の穴を同時には開けられない — 全面暗幕
    /// （Multiply, 一様darkness）+各光位置にAddハロ、という「暗闇の上に光が乗る」近似。
    /// 床は暗いまま見えない（真の穴あきが要らない松明集団シーン等向け）。
    /// ハロは全て同じ z+1（Add は加算合成のため奥行き順に依らず重なりは自然に足し合わさる）。
    pub def multiLightItems(cfg: MultiLightConfig): List[Render.PlacedItem] =
        let darkColor = { r = 0.0f32, g = 0.0f32, b = 0.0f32 };
        let cover = Render.boxAt(Vec2.mul(cfg#viewport, 0.5), cfg#viewport, darkColor, cfg#z)
            |> (placed -> { item = Render.blended(DrawCmd.BlendMode.Multiply, placed#item)
                                |> Render.fade(RenderUtil.f32(cfg#darkness)) | placed });
        let haloes = cfg#lights |> List.map(light -> {
            at = light#at,
            item = Render.sprite(cfg#haloSprite, cfg#z + 1)
                |> tintHalo(light)
                |> Render.scaled(haloScale(light#radius, cfg#haloSourceSize))
                |> Render.blended(DrawCmd.BlendMode.Add)
        });
        cover :: haloes
}
