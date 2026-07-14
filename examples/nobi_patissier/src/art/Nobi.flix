// Nobi — 主役の恐竜「のび」の手続き描画（ベジエ曲線版）。
// 体 = 楕円ブロブ、首 = 先細りのベジエ帯（前へ弧を描く）、しっぽ = 先細りの帯 + 丸い先端。
// ぬいぐるみ参考: 黄緑の体・白いおなか・長い首・小さな頭・つぶらな目・ずんぐり4本足。
// プロポーションは Build レコードに集約し、4 案（A忠実/B2頭身/C首長/Dまんまる）は数値だけの違い。
// 32 ユニットのグリッド（左向き基準）で組み、要求サイズへスケールする。
mod Nobi {

    /// 見た目の指定一式。design = 体型案、skin = 色、look = 顔の向き、hat = パティシエ帽、
    /// detail = 模様と白の入り方（baseDetail を record update で微調整して渡す）。
    pub type alias Style = {
        design = Design,
        skin = Palette.NobiSkin,
        look = Look,
        hat = Bool,
        detail = Detail
    }

    /// 模様と白の入り方の微調整パラメータ。体型はそのままに「柄」だけを動かす。
    pub type alias Detail = {
        stripeCount = Int32,     // 背中の斑の数
        stripeCenter = Float64,  // 斑の並びの中心（体幅比。正 = 尻尾寄り）
        stripeGap = Float64,     // 斑の間隔（体幅比）
        stripeW = Float64,       // 斑の幅（グリッド）
        stripeD = Float64,       // 斑の深さ（内側へのふくらみ）
        stripeDrop = Float64,    // 稜線からの沈み（0 = 稜線で切る / 正 = 内側に浮かす）
        stripeLean = Float64,    // 斑の後ろ倒し（ラジアン。しずく風になる）
        whiteBase = Float64,     // 白ラインの胸側の幅（首幅比）
        whiteTip = Float64,      // 白ラインの顎側の幅（首幅比）
        jawR = Float64,          // 顎白の大きさ（頭高比。0 で無し）
        underside = Bool,        // 白を腹の下辺〜尻尾の付け根まで回すか
        bellyW = Float64,        // おなか楕円の幅（体幅比。0 で無し）
        bellyH = Float64,        // おなか楕円の高さ（体高比）
        neckSpot = Bool          // 首の付け根の後ろにも斑を 1 つ置くか
    }

    /// 現行基準の柄（V01）。variants はこれを record update で少しずつ動かす。
    pub def baseDetail(): Detail =
        { stripeCount = 3, stripeCenter = 0.10, stripeGap = 0.27, stripeW = 1.15, stripeD = 1.9,
          stripeDrop = -0.25, stripeLean = 0.0, whiteBase = 0.44, whiteTip = 0.24, jawR = 0.26,
          underside = false, bellyW = 0.13, bellyH = 0.09, neckSpot = false }

    /// 体型のデザイン案（A 系の磨き込み 5 パターン。基準は P1）。
    pub enum Design with Eq {
        /// 基準（現行の A）。
        case P1
        /// 首太ショート — IKEA JATTELIK 系ぬいぐるみの「首の付け根が太い」感じ。
        case P2
        /// 首長エレガント — ブラキオらしい高い首。
        case P3
        /// ロー&ロング — 胴長・低姿勢・傾き強め。
        case P4
        /// すっくと胸張り — 首を立てて傾きひかえめ。
        case P5
    }

    /// 顔の向き。Side = 横向き（基準）、Front = こっちを見る。
    pub enum Look with Eq {
        case Side
        case Front
    }

    /// 体型の寸法一式（単位はグリッド）。lean = 首が前へ倒れる量、bow = 首の弧のふくらみ。
    type alias Build = {
        bodyW = Float64, bodyH = Float64,
        neckW = Float64, neckLen = Float64, lean = Float64, bow = Float64,
        headW = Float64, headH = Float64, eyeR = Float64,
        legW = Float64, legH = Float64, tailLen = Float64,
        tilt = Float64
    }

    def buildOf(design: Design): Build = match design {
        case Design.P1 =>
            { bodyW = 18.0, bodyH = 9.0, neckW = 4.8, neckLen = 9.5, lean = 3.2, bow = 2.2,
              headW = 7.4, headH = 5.2, eyeR = 0.85, legW = 3.0, legH = 3.8, tailLen = 8.0,
              tilt = 0.17 }
        case Design.P2 =>
            { bodyW = 17.5, bodyH = 9.6, neckW = 6.0, neckLen = 8.0, lean = 2.6, bow = 1.8,
              headW = 8.0, headH = 5.8, eyeR = 0.95, legW = 3.4, legH = 3.8, tailLen = 8.0,
              tilt = 0.13 }
        case Design.P3 =>
            { bodyW = 16.5, bodyH = 8.8, neckW = 4.2, neckLen = 11.5, lean = 4.0, bow = 3.2,
              headW = 6.8, headH = 4.8, eyeR = 0.8, legW = 2.9, legH = 3.8, tailLen = 9.0,
              tilt = 0.15 }
        case Design.P4 =>
            { bodyW = 19.0, bodyH = 8.4, neckW = 4.8, neckLen = 8.5, lean = 3.6, bow = 2.8,
              headW = 7.2, headH = 5.0, eyeR = 0.85, legW = 3.2, legH = 3.0, tailLen = 7.5,
              tilt = 0.18 }
        case Design.P5 =>
            { bodyW = 17.0, bodyH = 9.0, neckW = 4.8, neckLen = 10.5, lean = 1.6, bow = 1.4,
              headW = 7.4, headH = 5.4, eyeR = 0.9, legW = 3.0, legH = 4.4, tailLen = 7.5,
              tilt = 0.09 }
    }

    /// `center` を中心に `size` px の正方タイルへ、のび一体ぶんの描画アイテムを返す。
    pub def parts(center: Vec2.Vec2, size: Float64, style: Style): List[Render.PlacedItem] =
        let b = buildOf(style#design);
        let skin = style#skin;
        let s = size / 32.0;
        let tl = { x = center#x - size / 2.0, y = center#y - size / 2.0 };
        // 地面 y=25.5。しっぽの先を右端へ寄せ、体の右端から左へ組み立てる。
        let groundY = 25.5;
        let legTop = groundY - b#legH;
        let bodyBottom = legTop + 1.6;
        let bodyCy = bodyBottom - b#bodyH / 2.0;
        let bodyRight = 31.0 - b#tailLen;
        let bodyLeft = bodyRight - b#bodyW;
        let bodyCx = bodyLeft + b#bodyW / 2.0;
        let bodyTop = bodyBottom - b#bodyH;
        // 首: 体の前上から生え、bow ぶん後ろへふくらみながら lean ぶん前へ倒れて立ち上がる。
        let neckBase0 = (bodyLeft + b#neckW / 2.0 + 0.8, bodyTop + 1.2);
        let (neckBaseX, neckBaseY) = tiltP(b#tilt, bodyCx, bodyCy, fst(neckBase0), snd(neckBase0));
        let neckTopX = neckBaseX - b#lean;
        let neckTopY = neckBaseY - 0.6 - b#neckLen;
        let gp = p -> { x = tl#x + fst(p) * s, y = tl#y + snd(p) * s };
        let d = style#detail;
        List.flatten(
            boxes(b, skin, style, bodyLeft, legTop, neckTopX, neckTopY)
                |> List.map(toItem(tl, s)) ::
            tailBand(b, skin, gp, s, bodyRight, bodyTop, groundY, bodyCx, bodyCy) ::
            bodyBlob(b, skin, gp, s, bodyCx, bodyCy) ::
            backStripes(b, d, skin, gp, bodyCx, bodyCy) ::
            neckSpotFill(b, d, skin, gp, s, neckBaseX, neckBaseY, neckTopY) ::
            neckBand(b, skin, gp, s, neckBaseX, neckBaseY, neckTopX, neckTopY) ::
            frontWhite(b, d, skin, gp, s, neckBaseX, neckBaseY, neckTopX, neckTopY,
                       bodyLeft, bodyBottom, bodyCx, bodyRight) ::
            muzzleBand(b, d, skin, gp, s, style#look, neckTopX, neckTopY) ::
            bellyBlob(b, d, skin, gp, s, bodyCx, bodyBottom) :: Nil)

    // ── 曲線パーツ ──

    /// 点 (x, y) を (cx, cy) まわりに theta（ラジアン・後ろ下がり）だけ回す（グリッド座標）。
    def tiltP(theta: Float64, cx: Float64, cy: Float64, x: Float64, y: Float64): (Float64, Float64) =
        let p = Vec2.rotated({ x = x - cx, y = y - cy }, theta);
        (cx + p#x, cy + p#y)

    /// 体: 後ろ下がりに少し傾いた楕円ブロブ。
    def bodyBlob(b: Build, skin: Palette.NobiSkin, gp: ((Float64, Float64)) -> Vec2.Vec2,
                 s: Float64, cx: Float64, cy: Float64): List[Render.PlacedItem] =
        Bezier.fill(
            Bezier.ellipseRot(gp((cx, cy)), b#bodyW / 2.0 * s, b#bodyH / 2.0 * s, b#tilt, 22),
            skin#body, 2)

    /// 背中の深緑の斑。基本は背のライン上でスパッと切れた半楕円（反対側へ続いて見える）。
    /// Detail で数・位置・大きさ・沈み（内側に浮かす）・後ろ倒し（しずく風）を動かせる。
    def backStripes(b: Build, d: Detail, skin: Palette.NobiSkin,
                    gp: ((Float64, Float64)) -> Vec2.Vec2,
                    cx: Float64, cy: Float64): List[Render.PlacedItem] =
        // 等間隔: 並びの中心 stripeCenter から stripeGap 刻み。x で刻んで背の輪郭の高さに乗せる。
        let half = Int32.toFloat64(d#stripeCount - 1) / 2.0;
        List.range(0, d#stripeCount) |> List.flatMap(i -> {
            let fx = d#stripeCenter + (Int32.toFloat64(i) - half) * d#stripeGap;
            let rx = b#bodyW / 2.0;
            let ry = b#bodyH / 2.0;
            let px0 = cx + fx * b#bodyW;
            let u = (px0 - cx) / rx;
            let py0 = cy - ry * Vec2.sqrt(Float64.max(0.05, 1.0 - u * u));
            let (px1, py1) = tiltP(b#tilt, cx, cy, px0, py0);
            let inLen = Vec2.sqrt((cx - px1) * (cx - px1) + (cy - py1) * (cy - py1));
            let ux0 = (cx - px1) / inLen;
            let uy0 = (cy - py1) / inLen;
            // 後ろ倒し: 内向き・稜線方向の軸を stripeLean だけ回す。
            let ca = RenderUtil.cosF(d#stripeLean);
            let sa = RenderUtil.sinF(d#stripeLean);
            let ux = ux0 * ca - uy0 * sa;
            let uy = ux0 * sa + uy0 * ca;
            let vx = -uy;
            let vy = ux;
            // 沈み: 稜線から内側へ stripeDrop ぶんずらす（0 なら稜線で切れる）。
            let px = px1 + ux * d#stripeDrop;
            let py = py1 + uy * d#stripeDrop;
            // 手前（頭側）の斑は細く、中央へ行くほど太い。
            let grow = 0.62 + 0.38 * RenderUtil.sinF(3.14159265 * Int32.toFloat64(i)
                / Float64.max(1.0, Int32.toFloat64(d#stripeCount - 1)));
            let outline = List.range(0, 9) |> List.map(k -> {
                let t = 3.14159265 * Int32.toFloat64(k) / 8.0;
                let along = d#stripeW * grow * RenderUtil.cosF(t);
                let inward = d#stripeD * grow * RenderUtil.sinF(t);
                gp((px + vx * along + ux * inward, py + vy * along + uy * inward))
            });
            Bezier.fill(outline, skin#deep, 3)
        })

    /// 首の付け根の後ろの斑（Detail.neckSpot が真のときだけ）。
    def neckSpotFill(b: Build, d: Detail, skin: Palette.NobiSkin,
                     gp: ((Float64, Float64)) -> Vec2.Vec2, s: Float64,
                     neckBaseX: Float64, neckBaseY: Float64, neckTopY: Float64): List[Render.PlacedItem] =
        if (not d#neckSpot)
            Nil
        else {
            let spotX = neckBaseX + b#bow * 0.55 + b#neckW * 0.18;
            let spotY = neckBaseY - (neckBaseY - neckTopY) * 0.30;
            Bezier.fill(
                Bezier.ellipseRot(gp((spotX, spotY)), 0.7 * s, 1.1 * s, -0.35, 10), skin#deep, 3)
        }

    /// マズル（横向きのみ）: 頭のドームから前へスッと細る帯。先端はほんの少しだけ丸い。
    /// 顎の白の大きさは Detail.jawR（0 なら無し）。
    def muzzleBand(b: Build, d: Detail, skin: Palette.NobiSkin,
                   gp: ((Float64, Float64)) -> Vec2.Vec2,
                   s: Float64, look: Look, neckTopX: Float64, neckTopY: Float64): List[Render.PlacedItem] =
        match look {
            case Look.Front =>
                // 正面（傾き顔）の下 1/3 の白。境界の高さは口のあったラインに合わせる。
                let tilt = b#headW * 0.10;
                let hcx = neckTopX - tilt;
                let hcy = neckTopY - b#headH * 0.02;
                let _ = d;
                jawWhite(skin, gp, hcx - tilt * 0.4, hcy + b#headH * 0.22,
                         b#headH * 0.53, b#headH * 0.38)
            case Look.Side  =>
                let hcx = neckTopX - b#headW * 0.10;
                let hcy = neckTopY + b#headH * 0.02;
                let tip = gp((hcx - b#headW * 0.62, hcy + b#headH * 0.10));
                let spine =
                    gp((hcx + b#headW * 0.02, hcy - b#headH * 0.02)) ::
                    gp((hcx - b#headW * 0.28, hcy + b#headH * 0.04)) ::
                    tip :: Nil;
                let band = Bezier.stroke({ spine = spine, color = skin#body, z = 4 },
                    t -> (b#headH * 1.02 - b#headH * 0.42 * t) * s);
                let capR = b#headH * 0.29;
                let cap = Bezier.fill(
                    Bezier.ellipse(tip, capR * s, capR * s, 10), skin#body, 4);
                let _ = d;
                List.flatten(band :: cap ::
                    jawWhite(skin, gp, hcx - b#headW * 0.10, hcy + b#headH * 0.16,
                             b#headW * 0.48, b#headH * 0.42) :: Nil)
        }

    /// 顔の下 1/3 の白（平らな上辺 = ちょうど口があったはずのライン）。ry<=0 なら描かない。
    def jawWhite(skin: Palette.NobiSkin, gp: ((Float64, Float64)) -> Vec2.Vec2,
                 cx: Float64, topY: Float64, rx: Float64, ry: Float64): List[Render.PlacedItem] =
        if (ry <= 0.0)
            Nil
        else {
            let outline = List.range(0, 11) |> List.map(i -> {
                let t = 3.14159265 * Int32.toFloat64(i) / 10.0;
                gp((cx + rx * RenderUtil.cosF(t), topY + ry * RenderUtil.sinF(t)))
            });
            Bezier.fill(outline, skin#belly, 5)
        }

    /// おなか: 体のいちばん下にうっすら見えるだけの白（脚は緑の部分から生える）。
    /// 大きさは Detail.bellyW/bellyH（bellyW<=0 なら無し — 下面白と使い分ける）。
    def bellyBlob(b: Build, d: Detail, skin: Palette.NobiSkin,
                  gp: ((Float64, Float64)) -> Vec2.Vec2,
                  s: Float64, bodyCx: Float64, bodyBottom: Float64): List[Render.PlacedItem] =
        if (d#bellyW <= 0.0)
            Nil
        else
            Bezier.fill(Bezier.ellipse(gp((bodyCx - b#bodyW * 0.08, bodyBottom - b#bodyH * 0.16)),
                b#bodyW * d#bellyW * s, b#bodyH * d#bellyH * s, 16), skin#belly, 3)

    /// 首: 先細りのベジエ帯（前傾の弧）+ 首の前側だけ細く白いすじ（喉から胸の白）。
    def neckBand(b: Build, skin: Palette.NobiSkin, gp: ((Float64, Float64)) -> Vec2.Vec2,
                 s: Float64, neckBaseX: Float64, neckBaseY: Float64, neckTopX: Float64,
                 neckTopY: Float64): List[Render.PlacedItem] =
        let spine = Bezier.quadratic(
            gp((neckBaseX, neckBaseY + 1.4)),
            gp((neckBaseX + b#bow, neckTopY + b#neckLen * 0.38)),
            gp((neckTopX, neckTopY + 1.2)), 12);
        Bezier.stroke({ spine = spine, color = skin#body, z = 2 },
            t -> (b#neckW * 1.08 - b#neckW * 0.28 * t) * s)

    /// 首からお腹への白いライン: 顎の下 → 首の前側 → 胸 → おなかの白まで一続き。
    /// 首の背骨を前へずらした帯に、胸〜おなかの点を足して 1 本のストロークで描く。
    /// Detail.underside が真なら、さらに腹の下辺をなぞって尻尾の付け根まで白を回す。
    def frontWhite(b: Build, d: Detail, skin: Palette.NobiSkin,
                   gp: ((Float64, Float64)) -> Vec2.Vec2,
                   s: Float64, neckBaseX: Float64, neckBaseY: Float64, neckTopX: Float64,
                   neckTopY: Float64, bodyLeft: Float64, bodyBottom: Float64,
                   bodyCx: Float64, bodyRight: Float64): List[Render.PlacedItem] =
        let spine = Bezier.quadratic(
            gp((neckBaseX, neckBaseY + 1.4)),
            gp((neckBaseX + b#bow, neckTopY + b#neckLen * 0.38)),
            gp((neckTopX, neckTopY + 1.2)), 12);
        let jawJoin = gp((neckTopX - b#headW * 0.10, neckTopY + b#headH * 0.42));
        let underside =
            if (d#underside)
                gp((bodyRight - 1.0, bodyBottom - b#bodyH * 0.24)) ::
                gp((bodyCx + b#bodyW * 0.22, bodyBottom - b#bodyH * 0.02)) :: Nil
            else
                Nil;
        // 足の周りに白を見せない: 白は肩（前脚の上）で止める。
        let chest = gp((bodyLeft + 1.8, bodyBottom - b#bodyH * 0.42)) :: Nil;
        // 白の前縁を首の前縁にぴったり合わせる（緑がはみ出さないように点ごとにオフセット）。
        let lastIx = Int32.toFloat64(List.length(spine) - 1);
        let neckFront = spine |> List.zipWithIndex |> List.map(entry -> {
            let (i, p) = entry;
            let t = Int32.toFloat64(i) / lastIx;
            let off = b#neckW * ((1.08 - 0.28 * t) - (d#whiteBase + (d#whiteTip - d#whiteBase) * t)) / 2.0;
            ({x = p#x - off * s, y = p#y + 0.4 * s}: Vec2.Vec2)
        });
        let frontSpine = List.flatten(underside :: chest :: neckFront :: (jawJoin :: Nil) :: Nil);
        // おなか側は太く、顎に向かって細く。
        Bezier.stroke({ spine = frontSpine, color = skin#belly, z = 3 },
            t -> b#neckW * (d#whiteBase + (d#whiteTip - d#whiteBase) * t) * s)

    /// しっぽ: 体のカーブに従って下り、後半（体の 1/3 くらいの長さ）は地面に
    /// 完全についたまま横たわり、先端が丸く終わる。
    def tailBand(b: Build, skin: Palette.NobiSkin, gp: ((Float64, Float64)) -> Vec2.Vec2,
                 s: Float64, bodyRight: Float64, bodyTop: Float64,
                 groundY: Float64, bodyCx: Float64, bodyCy: Float64): List[Render.PlacedItem] =
        let dragLen = b#bodyW / 3.0;
        let tipX = bodyRight + b#tailLen - 0.3;
        let touchX = tipX - dragLen;
        // 接地区間の背骨は太さの半分だけ床から浮かせる = 帯の下辺がちょうど床につく。
        let restY = groundY - 1.0;
        // 尻尾は体の延長: 体の内側から太いまま生え、体の線をなぞってなだらかに床へ。
        let root = tiltP(b#tilt, bodyCx, bodyCy, bodyRight - 4.5, bodyTop + b#bodyH * 0.42);
        let flow = tiltP(b#tilt, bodyCx, bodyCy, bodyRight + 1.0, bodyTop + b#bodyH * 0.60);
        let descend = Bezier.cubic(
            gp(root),
            gp(flow),
            gp((touchX - 2.5, restY - 1.4)),
            gp((touchX, restY)), 10);
        let drag = gp((touchX + dragLen * 0.5, restY)) :: gp((tipX, restY)) :: Nil;
        let spine = List.append(descend, drag);
        let band = Bezier.stroke({ spine = spine, color = skin#body, z = 1 },
            t -> (b#bodyH * 0.62 * (1.0 - t) + 1.8 * t) * s);
        let cap = Bezier.fill(Bezier.ellipse(gp((tipX, restY)), 0.9 * s, 0.9 * s, 8), skin#body, 1);
        List.append(band, cap)

    // ── ボックス/円パーツ（脚・頭・顔・帽子）──

    type alias Part = {
        x = Float64, y = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    def boxes(b: Build, skin: Palette.NobiSkin, style: Style, bodyLeft: Float64,
              legTop: Float64, neckTopX: Float64, neckTopY: Float64): List[Part] =
        List.flatten(
            legs(b, skin, bodyLeft, legTop) ::
            headOf(b, skin, style#look, neckTopX, neckTopY) ::
            (if (style#hat) hatOf(b, style#look, neckTopX, neckTopY) else Nil) :: Nil)

    /// 4 本脚（奥 2 本は濃色で少し上・内側に）。手前の脚には前側に 3 本の茶色い爪。
    def legs(b: Build, skin: Palette.NobiSkin, bodyLeft: Float64, legTop: Float64): List[Part] =
        let frontLegX = bodyLeft + b#bodyW * 0.10;
        let rearLegX = bodyLeft + b#bodyW * 0.58;
        List.flatten(
            (rrect(bodyLeft + b#bodyW * 0.22 + 1.2, legTop - 0.8, b#legW, b#legH + 0.8,
                   b#legW / 2.0, skin#deep, 0) ::
             rrect(bodyLeft + b#bodyW * 0.68 + 1.2, legTop - 0.8, b#legW, b#legH + 0.8,
                   b#legW / 2.0, skin#deep, 0) ::
             rrect(frontLegX, legTop, b#legW, b#legH, b#legW / 2.0, skin#body, 3) ::
             rrect(rearLegX, legTop, b#legW, b#legH, b#legW / 2.0, skin#body, 3) :: Nil) ::
            claws(b, skin, frontLegX, legTop) ::
            claws(b, skin, rearLegX, legTop) :: Nil)

    /// 足先の爪 3 本（足の前側 = 左寄りに、茶色の小さな粒）。
    def claws(b: Build, skin: Palette.NobiSkin, legX: Float64, legTop: Float64): List[Part] =
        let footY = legTop + b#legH - 1.1;
        (0 :: 1 :: 2 :: Nil) |> List.map(i ->
            rrect(legX - 0.2 + Int32.toFloat64(i) * (b#legW * 0.34), footY,
                  0.75, 1.2, 0.35, skin#claw, 4))

    /// 頭。Side = 丸頭 + 鼻先のふくらみ、Front = こっちを見た顔。
    def headOf(b: Build, skin: Palette.NobiSkin, look: Look,
               neckTopX: Float64, neckTopY: Float64): List[Part] =
        match look {
            case Look.Side =>
                // 丸くポコッとするのは頭のてっぺんのドームだけ。マズルは muzzleBand（曲線側）が
                // スッと前へ細らせる。ここではドーム・目・鼻の穴・ほっぺ・顎下の白だけ置く。
                let hcx = neckTopX - b#headW * 0.10;
                let hcy = neckTopY + b#headH * 0.02;
                let hr = b#headH * 0.56;
                circle(hcx, hcy, hr, skin#body, 4) ::
                circle(hcx - b#headW * 0.14, hcy - b#headH * 0.12, b#eyeR, skin#eye, 6) ::
                circle(hcx - b#headW * 0.14 - b#eyeR * 0.25, hcy - b#headH * 0.12 - b#eyeR * 0.3,
                       b#eyeR * 0.35, Palette.glint(), 7) ::
                circle(hcx - b#headW * 0.58, hcy + b#headH * 0.02, 0.35, skin#deep, 6) :: Nil // 鼻の穴
            case Look.Front =>
                // こっちを見る = 顔をちょっと傾けてこちらへ向ける。右目がこちらに見え、
                // 左目は頭の縁にほぼ隠れる。口は描かない — 顔の下 1/3 の白との境界が
                // 口のラインの位置に重なる（白は muzzleBand 側で描く）。
                let tilt = b#headW * 0.10;
                let hcx = neckTopX - tilt;
                let hcy = neckTopY - b#headH * 0.02;
                let hr = b#headH * 0.58;
                circle(hcx, hcy, hr, skin#body, 4) ::
                circle(hcx - tilt * 0.7, hcy + b#headH * 0.30, hr * 0.62, skin#body, 4) ::   // 短く見える鼻先
                circle(hcx - hr * 0.99, hcy + b#headH * 0.02, b#eyeR * 0.45, skin#eye, 6) :: // 左目（ほぼ見えない）
                circle(hcx + hr * 0.86, hcy + b#headH * 0.06, b#eyeR * 0.5, skin#eye, 6) ::  // 右目（左目より少し下）
                circle(hcx + hr * 0.86 - b#eyeR * 0.15, hcy + b#headH * 0.06 - b#eyeR * 0.2,
                       b#eyeR * 0.22, Palette.glint(), 7) :: Nil
        }

    /// パティシエ帽（白トック帽）。頭の上にふくらみ + 縁の帯。
    def hatOf(b: Build, look: Look, neckTopX: Float64, neckTopY: Float64): List[Part] =
        let (headTopY, hcx, hw) = match look {
            case Look.Side  => (neckTopY + b#headH * 0.02 - b#headH * 0.56,
                                neckTopX - b#headW * 0.10, b#headW)
            case Look.Front => (neckTopY - b#headH * 0.02 - b#headH * 0.58,
                                neckTopX - b#headW * 0.10, b#headW)
        };
        let brimW = hw * 0.74;
        let brimX = hcx - brimW * 0.5;
        rrect(brimX, headTopY - 0.6, brimW, 1.4, 0.5, Palette.hatShade(), 7) ::
        rrect(brimX + 0.3, headTopY - 3.1, brimW - 0.6, 2.8, 1.2, Palette.hat(), 7) ::
        circle(brimX + 0.9, headTopY - 2.6, 1.0, Palette.hat(), 8) ::
        circle(brimX + brimW - 0.8, headTopY - 2.4, 0.9, Palette.hat(), 8) :: Nil

    // ── ヘルパー ──

    def rrect(x: Float64, y: Float64, w: Float64, h: Float64, r: Float64,
              c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = Float64.min(r, Float64.min(w, h) / 2.0), color = c, z = z }

    def circle(cx: Float64, cy: Float64, r: Float64, c: Color, z: Int32): Part =
        { x = cx - r, y = cy - r, w = r * 2.0, h = r * 2.0, r = r, color = c, z = z }

    def toItem(tl: Vec2.Vec2, s: Float64, p: Part): Render.PlacedItem =
        let pos = {x = tl#x + p#x * s, y = tl#y + p#y * s};
        let dim = {x = p#w * s, y = p#h * s};
        if (p#r <= 0.0)
            { at = pos, item = Render.box(dim, p#color, p#z) }
        else
            { at = pos, item = Render.box(dim, p#color, p#z) |> Render.rounded(p#r * s) }
}
