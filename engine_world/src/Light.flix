// Light — 簡易2D光源から見せる絵の列を導く純関数。
// 光そのものは状態を持たない値（位置・半径・色・ハロの強さ）で、毎フレーム
// items に渡すだけで絵になる（他の Render 系と同じ並び）。
//
// 「穴あき暗幕」を描くための土台は RadialGlow が焼いた2種類の別規約テクスチャ
// （maskSprite=Multiply専用の暗幕、haloSprite=Add専用の暖色グロー）で、Light はその
// 2枚をどこに・どれだけ拡大して置くかだけを決める（画素の中身には触れない）。
mod Light {

    /// 簡易2D光源1個の値。at=位置、radius=光の届く目安半径、color=光の色、
    /// halo=Addハロの強さ0..1。
    pub type alias Light = { at = Vec2.Vec2, radius = Float64, color = Color, halo = Float64 }

    /// RadialGlow で焼いた既定テクスチャの参照一式。sprite 名・元 px サイズ・穴の広さは
    /// 「焼く側（bake の RadialGlow 呼び出し）」と「読む側（items のスケール計算）」で
    /// 値が揃っていないと穴のサイズがずれるため、1 レコードにまとめて受け渡しの分裂を防ぐ。
    pub type alias GlowAssets = {
        maskSprite = String, maskSourceSize = Float64, maskHoleFrac = Float64,
        haloSprite = String, haloSourceSize = Float64
    }

    /// RadialGlow の既定値で焼いたときの GlowAssets（sprite名は bake 側の慣習
    /// "glow_mask"/"glow_halo" 固定）。別名のテクスチャを焼いたゲームは自分で
    /// GlowAssets を組み立てて items に渡せばよい。
    /// maskHoleFrac=0.5 は engine_tools（bake 専用パッケージ、engine_world から依存できない）
    /// の RadialGlow.defaultHoleFrac() と同じ値 — 焼く側を変えたらここも合わせて直すこと。
    pub def defaultGlowAssets(): GlowAssets =
        { maskSprite = "glow_mask", maskSourceSize = 512.0, maskHoleFrac = 0.5,
          haloSprite = "glow_halo", haloSourceSize = 256.0 }

    /// シーン全体の光源設定（items の唯一の入口）。lights は 0〜N 個、occluders は
    /// 遮蔽ポリゴンの列（Shadow.occluderOf 系で作る絶対座標の頂点列）。
    /// darkness/z は暗幕・影・ハロの土台を貫く共通値（暗幕の縁と影の濃さを合わせて
    /// 「同じ暗闇の一部」に見せるため、光源ごとにばらけさせない）。
    /// rimWidth/rimStrength は Shadow.itemsFor に渡す照り返しフチのノブ、
    /// haloDiameterFactor はハロの見た目直径を「2×radius（穴の直径）」からさらに
    /// 拡大する倍率（1.0 で拡大なし。既定は defaultHaloDiameterFactor）— 穴の縁ぴったりに
    /// ハロを合わせると光が穴の輪郭で唐突に途切れて見えるため、ひとまわり大きく余す。
    /// lights が2個以上のとき occluders を渡しても影は描かれない（items の doc を参照）。
    pub type alias SceneLightConfig = {
        lights = List[Light], occluders = List[List[Vec2.Vec2]],
        viewport = Vec2.Vec2, glow = GlowAssets,
        darkness = Float64, z = Int32,
        rimWidth = Float64, rimStrength = Float64, haloDiameterFactor = Float64
    }

    /// haloDiameterFactor の既定の目安。穴（2×radius）よりひとまわり大きい見た目にする
    /// （ホラー演出での実運用値。ちょうど穴の縁で光が切れると不自然に見える）。
    pub def defaultHaloDiameterFactor(): Float64 = 1.25

    /// シーンの光源一式を絵にする唯一の入口。lights が
    ///   - 0 個なら全面暗幕のみ（multiLightItems を lights=Nil で呼ぶのと同じ）
    ///   - 1 個なら真の穴あき暗幕+ハロ（singleLightItems）に、occluders があれば
    ///     Shadow.itemsFor の影・フチを合成する（呼び側の手動 append が不要になる）
    ///   - 2 個以上なら全面暗幕+各光のハロ（multiLightItems）の近似に振り分ける
    /// **複数光源では影が出ない**（FBO が無く Multiply の穴あきを同時に複数開けられない
    /// 制約による。occluders を渡しても黙って無視される — 松明集団シーンのような
    /// 「影は要らないが灯りだけ複数欲しい」用途向けの割り切り）。
    pub def items(cfg: SceneLightConfig): List[Render.PlacedItem] =
        match cfg#lights {
            case light :: Nil => singleWithShadow(cfg, light)
            case lights       => multiLightItems({
                lights = lights, darkness = cfg#darkness, viewport = cfg#viewport,
                haloSprite = cfg#glow#haloSprite, haloSourceSize = cfg#glow#haloSourceSize, z = cfg#z })
        }

    /// items の単一光源ぶん: singleLightItems（GlowAssets → SingleLightConfig の変換は
    /// ここだけが知っていればよい）にハロの追加拡大を掛け、occluders があれば
    /// Shadow.itemsFor の影を同じ darkness/z で合成する。
    def singleWithShadow(cfg: SceneLightConfig, light: Light): List[Render.PlacedItem] =
        let lightItems = singleLightItems({
            light = light, viewport = cfg#viewport,
            maskSprite = cfg#glow#maskSprite, maskSourceSize = cfg#glow#maskSourceSize,
            maskHoleFrac = cfg#glow#maskHoleFrac,
            haloSprite = cfg#glow#haloSprite, haloSourceSize = cfg#glow#haloSourceSize,
            darkness = cfg#darkness, z = cfg#z })
            |> growHalo(cfg#haloDiameterFactor);
        let shadows = if (List.isEmpty(cfg#occluders))
                List.empty()
            else
                Shadow.itemsFor(light, cfg#occluders,
                    { darkness = cfg#darkness, z = cfg#z, extrudeLength = Shadow.infiniteExtrude(),
                      rimWidth = cfg#rimWidth, rimStrength = cfg#rimStrength });
        List.append(lightItems, shadows)

    /// singleLightItems が返す列の末尾（ハロ）だけを factor 倍する（先頭の暗幕・周囲黒帯は
    /// そのまま）。末尾がハロであることは singleLightItems の実装順序に依存するので、
    /// この関数を単独で公開はせず items の内部でだけ使う。
    def growHalo(factor: Float64, items: List[Render.PlacedItem]): List[Render.PlacedItem] =
        match List.reverse(items) {
            case Nil          => Nil
            case halo :: rest =>
                let grown = { item = Render.scaled(factor, halo#item) | halo };
                List.reverse(grown :: rest)
        }

    // ── 低レベル口（通常は items を使う。影や haloDiameterFactor が要らず、
    //    穴あき暗幕+ハロだけをピンポイントに組みたいときに使う） ──

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

    // ── 低レベル口（通常は items を使う。多灯シーンで occluders 判定を挟まず
    //    直接呼びたいときに使う） ──

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
