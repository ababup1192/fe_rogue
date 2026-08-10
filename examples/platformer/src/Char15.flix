// 行商のツヅラ婆 — 自分より大きい行李を背負う小柄な旅商人。
// 深い前かがみの小さな体に、寝袋と鍋と提灯を積んだ籠の行李がそびえる。
// 走りは杖で地面を突く速足の刻み。急停止は杖を突き立てて踏ん張るが、
// 荷は勢いで頭上へずり上がる。跳ぶと荷が背中から浮き、着地でどすんと沈む。

mod Char15 {

    pub def name(): String = "15 PEDDLER"

    // ── 色（DB32・体色は不変）──
    def skin(): Color    = { r = 0.933333f32, g = 0.764706f32, b = 0.603922f32 } // eec39a
    def kimono(): Color  = { r = 0.462745f32, g = 0.266667f32, b = 0.384314f32 } // 764462
    def sash(): Color    = { r = 0.188235f32, g = 0.376471f32, b = 0.509804f32 } // 306082
    def legging(): Color = { r = 0.196078f32, g = 0.235294f32, b = 0.223529f32 } // 323c39
    def sandal(): Color  = { r = 0.400000f32, g = 0.223529f32, b = 0.192157f32 } // 663931
    def hair(): Color    = { r = 0.607843f32, g = 0.678431f32, b = 0.717647f32 } // 9badb7
    def blush(): Color   = { r = 0.850980f32, g = 0.341176f32, b = 0.388235f32 } // d95763
    def wicker(): Color  = { r = 0.560784f32, g = 0.337255f32, b = 0.231373f32 } // 8f563b
    def weave(): Color   = { r = 0.850980f32, g = 0.627451f32, b = 0.400000f32 } // d9a066
    def roll(): Color    = { r = 0.294118f32, g = 0.411765f32, b = 0.184314f32 } // 4b692f
    def potC(): Color    = { r = 0.517647f32, g = 0.494118f32, b = 0.529412f32 } // 847e87
    def knobC(): Color   = { r = 0.349020f32, g = 0.337255f32, b = 0.321569f32 } // 595652
    def strap(): Color   = { r = 0.321569f32, g = 0.294118f32, b = 0.141176f32 } // 524b24
    def stickC(): Color  = { r = 0.541176f32, g = 0.435294f32, b = 0.188235f32 } // 8a6f30
    def lampY(): Color   = { r = 0.984314f32, g = 0.949020f32, b = 0.211765f32 } // fbf236
    def frameC(): Color  = { r = 0.133333f32, g = 0.125490f32, b = 0.203922f32 } // 222034
    def dustC(): Color   = { r = 0.411765f32, g = 0.415686f32, b = 0.415686f32 } // 696a6a
    def whiteC(): Color  = { r = 1.000000f32, g = 1.000000f32, b = 1.000000f32 } // ffffff
    def blackC(): Color  = { r = 0.000000f32, g = 0.000000f32, b = 0.000000f32 } // 000000

    // ── 配置ヘルパ（足元中心のローカル座標・facing で x を鏡映）──

    def at(stage: CharStage.Stage, dx: Float64, dy: Float64): Vec2.Vec2 =
        { x = stage#pos#x + stage#facing * dx, y = stage#pos#y + dy }

    /// 中心 (dx, dy) の矩形。
    def boxC(stage: CharStage.Stage, dx: Float64, dy: Float64,
             w: Float64, h: Float64, c: Color, z: Int32): Render.PlacedItem =
        let p = at(stage, dx, dy);
        { at = { x = p#x - w / 2.0, y = p#y - h / 2.0 }, item = Render.box({ x = w, y = h }, c, z) }

    /// 中心 (dx, dy) の円。
    def circC(stage: CharStage.Stage, dx: Float64, dy: Float64,
              r: Float64, c: Color, z: Int32): Render.PlacedItem =
        let p = at(stage, dx, dy);
        { at = { x = p#x - r, y = p#y - r }, item = Render.circle(r, c, z) }

    /// 2 点を結ぶ太さ th の棒（腕・杖・肩ひもを斜めに描く）。
    def strut(stage: CharStage.Stage, ax: Float64, ay: Float64,
              bx: Float64, by: Float64, th: Float64, c: Color, z: Int32): Render.PlacedItem =
        let ddx = bx - ax;
        let ddy = by - ay;
        let len0 = RenderUtil.sqrtF(ddx * ddx + ddy * ddy);
        let len = if (len0 < 0.001) 0.001 else len0;
        let nx = (0.0 - ddy) / len * th / 2.0;
        let ny = ddx / len * th / 2.0;
        let p = at(stage, ax, ay);
        let f = stage#facing;
        { at = { x = p#x, y = p#y },
          item = Render.polygon({ x = f * nx, y = ny } :: { x = f * (ddx + nx), y = ddy + ny } ::
                         { x = f * (ddx - nx), y = ddy - ny } :: { x = f * (0.0 - nx), y = 0.0 - ny } :: Nil,
                         c, z) }

    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))

    def fadeP(a: Float64, pl: Render.PlacedItem): Render.PlacedItem =
        { item = Render.fade(clamp01(a), pl#item) | pl }

    def roundP(r: Float64, pl: Render.PlacedItem): Render.PlacedItem =
        { item = Render.rounded(r, pl#item) | pl }

    // ── 本人（bob = 上下動・lean = 前かがみの深さ・sq = 縦つぶし）──

    def granny(stage: CharStage.Stage,
               p: { bob = Float64, lean = Float64, sq = Float64,
                    legF = (Float64, Float64), legFh = Float64,
                    legB = (Float64, Float64), legBh = Float64,
                    handF = (Float64, Float64), handB = (Float64, Float64),
                    eyeWide = Bool }): List[Render.PlacedItem] =
        let (lfx, lfy) = p#legF;
        let (lbx, lby) = p#legB;
        let (hfx, hfy) = p#handF;
        let (hbx, hby) = p#handB;
        let bob = p#bob;
        let lean = p#lean;
        let sq = p#sq;
        let bodyX = 1.2 + lean;
        let bodyY = (0.0 - 8.2) * sq + bob;
        let headX = 3.8 + lean * 1.5;
        let headY = (0.0 - 12.8) * sq + bob;
        // 脚 + 草履（小さく速い足）
        let legs =
            boxC(stage, lfx, lfy, 2.6, p#legFh, legging(), 11) ::
            boxC(stage, lbx, lby, 2.6, p#legBh, legging(), 11) ::
            boxC(stage, lfx + 0.4, lfy + p#legFh / 2.0, 3.2, 1.2, sandal(), 12) ::
            boxC(stage, lbx + 0.4, lby + p#legBh / 2.0, 3.2, 1.2, sandal(), 12) :: Nil;
        // 胴 = 丸い着物 + 帯。
        let torso =
            roundP(2.0, boxC(stage, bodyX, bodyY, 7.5, 7.5 * sq, kimono(), 11)) ::
            boxC(stage, bodyX, bodyY + 1.6 * sq, 7.6, 1.6, sash(), 12) :: Nil;
        // 腕は着物の袖の棒 + 素肌の手。
        let arms =
            strut(stage, 2.0 + lean, (0.0 - 9.8) * sq + bob, hfx, hfy, 2.2, kimono(), 12) ::
            circC(stage, hfx, hfy, 1.1, skin(), 12) ::
            strut(stage, 1.2 + lean, (0.0 - 9.4) * sq + bob, hbx, hby, 2.2, kimono(), 10) ::
            circC(stage, hbx, hby, 1.1, skin(), 10) :: Nil;
        // 頭: 白髪のまげ + ほっぺの赤み + 目（驚くと白目が開く）。
        let eye =
            if (p#eyeWide)
                circC(stage, headX + 1.5, headY - 0.4, 1.1, whiteC(), 12) ::
                circC(stage, headX + 1.5, headY - 0.4, 0.55, blackC(), 13) :: Nil
            else
                circC(stage, headX + 1.5, headY - 0.4, 0.55, blackC(), 13) :: Nil;
        let head =
            circC(stage, headX, headY, 3.3, skin(), 11) ::
            circC(stage, headX - 1.6, headY - 2.6, 1.7, hair(), 12) ::
            circC(stage, headX + 1.0, headY + 1.1, 0.7, blush(), 12) :: Nil;
        List.flatten(legs :: torso :: arms :: head :: eye :: Nil)

    /// 背中の行李ひとそろい。packDx/packDy = 荷全体のずれ、itemsDx/itemsDy = 上に積んだ
    /// 荷物のずれ（荷の傾きの誇張）、lanSway/lanDy = 提灯の揺れ。
    def pack(stage: CharStage.Stage,
             p: { packDx = Float64, packDy = Float64, itemsDx = Float64, itemsDy = Float64,
                  lanSway = Float64, lanDy = Float64 }): List[Render.PlacedItem] =
        let pdx = p#packDx;
        let pdy = p#packDy;
        let idx = p#itemsDx;
        let idy = p#itemsDy;
        // 籠の行李本体 + 編み目。
        let basket =
            roundP(1.5, boxC(stage, -3.0 + pdx, 0.0 - 13.5 + pdy, 10.0, 15.0, wicker(), 9)) ::
            boxC(stage, -3.0 + pdx, 0.0 - 9.5 + pdy, 10.0, 1.0, weave(), 10) ::
            boxC(stage, -3.0 + pdx, 0.0 - 13.5 + pdy, 10.0, 1.0, weave(), 10) ::
            boxC(stage, -3.0 + pdx, 0.0 - 17.5 + pdy, 10.0, 1.0, weave(), 10) :: Nil;
        // 肩ひも 2 本。荷が浮くと自然に伸びて見える。
        let straps =
            strut(stage, -1.0 + pdx, 0.0 - 18.0 + pdy, 2.4, -9.5, 1.0, strap(), 12) ::
            strut(stage, -1.0 + pdx, 0.0 - 10.5 + pdy, 2.0, -6.0, 1.0, strap(), 12) :: Nil;
        // 上に積んだ荷物: 寝袋の筒 + 鍋。
        let items =
            roundP(1.6, boxC(stage, -3.0 + idx, 0.0 - 22.6 + pdy + idy, 9.0, 3.2, roll(), 10)) ::
            circC(stage, -5.0 + idx, 0.0 - 25.4 + pdy + idy, 1.8, potC(), 10) ::
            circC(stage, -5.0 + idx, 0.0 - 27.5 + pdy + idy, 0.6, knobC(), 11) :: Nil;
        // 後ろへ突き出した竿から提灯が下がる。
        let lx = 0.0 - 6.3 + pdx + p#lanSway;
        let ly = 0.0 - 22.2 + pdy + p#lanDy;
        let lantern =
            strut(stage, -5.3 + pdx, 0.0 - 21.5 + pdy, -6.3 + pdx, 0.0 - 25.0 + pdy, 1.0, stickC(), 10) ::
            strut(stage, -6.3 + pdx, 0.0 - 25.0 + pdy, lx, ly - 2.0, 0.6, knobC(), 10) ::
            roundP(1.0, boxC(stage, lx, ly, 3.2, 4.0, frameC(), 10)) ::
            boxC(stage, lx, ly, 2.0, 2.6, lampY(), 11) :: Nil;
        List.flatten(basket :: straps :: items :: lantern :: Nil)

    /// 旅の杖: 手元 (hx,hy) から先端 (tx,ty) へ。手元に握りこぶを添える。
    def stickAt(stage: CharStage.Stage, hx: Float64, hy: Float64,
                tx: Float64, ty: Float64): List[Render.PlacedItem] =
        strut(stage, hx, hy, tx, ty, 1.3, stickC(), 12) ::
        circC(stage, hx, hy - 0.9, 0.9, stickC(), 12) :: Nil

    // ── モードごとの演技 ──

    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        match stage#mode {
            case CharStage.Mode.IdleMode => idle(stage)
            case CharStage.Mode.RunMode  => runPose(stage)
            case CharStage.Mode.DashMode => dash(stage)
            case CharStage.Mode.SkidMode => skid(stage)
            case CharStage.Mode.JumpMode => jump(stage)
            case CharStage.Mode.FallMode => fall(stage)
            case CharStage.Mode.LandMode => land(stage)
        }

    /// 待機: 杖に体重を預けて一息。後手で肩ひもを締め直して荷がひょいと持ち上がり、
    /// 続けて荷をぽんぽんと労う。提灯はゆっくり揺れる。
    def idle(stage: CharStage.Stage): List[Render.PlacedItem] =
        let b = Curve.tri(1.4, stage#t) * 0.5;
        let m = stage#modeT;
        let sway = Curve.triWave(stage#t * 0.45) * 0.9;
        let hitch = if (m >= 0.5 and m <= 0.9) Curve.tri(0.4, m - 0.5) else 0.0;
        let pat = if (m >= 0.95 and m <= 1.25) Curve.tri(0.3, m - 0.95) else 0.0;
        let hb =
            if (m >= 0.5 and m <= 0.9) (2.0, 0.0 - 10.8 + b)
            else if (m >= 0.95 and m <= 1.25) (-1.5, 0.0 - 13.2 + pat * 0.6)
            else (0.0, 0.0 - 8.0 + b);
        let core = granny(stage, { bob = b, lean = 0.0, sq = 1.0,
                                   legF = (1.6, -2.4), legFh = 4.4,
                                   legB = (-1.4, -2.4), legBh = 4.4,
                                   handF = (4.2, 0.0 - 8.8 + b), handB = hb,
                                   eyeWide = false });
        let load = pack(stage, { packDx = 0.0, packDy = 0.0 - hitch * 1.0 + pat * 0.4,
                                 itemsDx = 0.0, itemsDy = 0.0 - hitch * 0.5,
                                 lanSway = sway, lanDy = 0.0 });
        let cane = stickAt(stage, 4.2, 0.0 - 8.8 + b, 6.8, -0.2);
        List.flatten(core :: load :: cane :: Nil)

    /// 走り: 距離駆動の速足の刻み。一歩ごとに杖の先で地面をつつき、
    /// 荷は半分の周期で左右に遅れて揺れ、提灯が反対へ振れる。
    def runPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let ph = stage#pos#x * 0.16;
        let sw = Curve.triWave(ph);
        let bob = 0.0 - Float64.abs(sw) * 0.7;
        let packSway = Curve.triWave(ph * 0.5);
        let tap = Float64.max(0.0, sw);
        let hf = (3.8 + sw * 0.6, 0.0 - 8.6 + bob);
        let (hfx, hfy) = hf;
        let core = granny(stage, { bob = bob, lean = 1.6, sq = 1.0,
                                   legF = (1.2 + sw * 2.2, 0.0 - 2.4 - tap * 1.2), legFh = 4.4,
                                   legB = (1.2 - sw * 2.2, 0.0 - 2.4 - Float64.max(0.0, 0.0 - sw) * 1.2), legBh = 4.4,
                                   handF = hf,
                                   handB = (0.0 - 1.5 - sw * 1.5, 0.0 - 7.8 + bob),
                                   eyeWide = false });
        let load = pack(stage, { packDx = 0.0 - packSway * 0.8,
                                 packDy = Float64.abs(packSway) * 0.8 - 0.4,
                                 itemsDx = 0.0 - packSway * 1.5,
                                 itemsDy = 0.0,
                                 lanSway = 0.0 - packSway * 2.2, lanDy = 0.0 });
        let cane = stickAt(stage, hfx, hfy, 6.4 + sw * 1.8, 0.0 - 0.3 - tap * 2.6);
        let a = (0.0 - sw - 0.7) / 0.3;
        let tapDust =
            if (a > 0.0) fadeP(a * 0.35, circC(stage, 6.0, -0.9, 1.1, dustC(), 8)) :: Nil
            else Nil;
        List.flatten(core :: load :: cane :: tapDust :: Nil)

    /// ダッシュ: ほぼ水平まで前のめり。行李の荷物がガタガタと跳ね、鍋の残像が
    /// 後ろへ尾を引き、足元から土煙が巻き上がる。杖は浮かせて構える。
    def dash(stage: CharStage.Stage): List[Render.PlacedItem] =
        let bandV = clamp01((Float64.abs(stage#vx) - 160.0) / 120.0);
        let sw = Curve.triWave(stage#pos#x * 0.16);
        let bob = 0.0 - Float64.abs(sw) * 0.5;
        let j = Curve.triWave(stage#t * 9.0) * 0.8 * bandV;
        let itemsDx = j * 2.0 + 0.9 * bandV;
        let itemsDy = 0.0 - Float64.abs(Curve.triWave(stage#t * 9.0 + 0.25)) * 1.4 * bandV;
        let core = granny(stage, { bob = bob, lean = 2.8, sq = 1.0,
                                   legF = (1.6 + sw * 2.6, 0.0 - 2.4 - Float64.max(0.0, sw) * 1.4), legFh = 4.4,
                                   legB = (1.6 - sw * 2.6, 0.0 - 2.4 - Float64.max(0.0, 0.0 - sw) * 1.4), legBh = 4.4,
                                   handF = (4.6, 0.0 - 8.2 + bob),
                                   handB = (0.0 - 2.0, 0.0 - 7.4 + bob),
                                   eyeWide = false });
        let load = pack(stage, { packDx = 0.5, packDy = j,
                                 itemsDx = itemsDx, itemsDy = itemsDy,
                                 lanSway = 0.0 - 2.2 * bandV - 0.6, lanDy = -0.8 });
        let cane = stickAt(stage, 4.6, 0.0 - 8.2 + bob, 7.6, -4.0);
        let cloud = List.map(kk ->
            fadeP((0.4 - 0.1 * kk) * bandV,
                  circC(stage, 0.0 - 8.0 - 4.0 * kk, 0.0 - 1.8 - 0.6 * kk, 1.6 + 0.8 * kk, dustC(), 8)),
            0.0 :: 1.0 :: 2.0 :: Nil);
        let trail =
            fadeP(0.28 * bandV, circC(stage, -5.0 + itemsDx - 4.5, 0.0 - 24.4 + itemsDy, 1.8, potC(), 8)) ::
            fadeP(0.14 * bandV, circC(stage, -5.0 + itemsDx - 9.0, 0.0 - 23.4 + itemsDy, 1.8, potC(), 8)) :: Nil;
        List.flatten(core :: load :: cane :: cloud :: trail :: Nil)

    /// スキッド: 杖を前方の地面へ突き立てて両手で踏ん張る。荷は勢いで頭上へ
    /// ずり上がって前へ傾き、杖の先に土埃と小石が跳ねる。強さは残速度に比例。
    def skid(stage: CharStage.Stage): List[Render.PlacedItem] =
        let sI = clamp01(Float64.abs(stage#vx) / 280.0);
        let lurch = 6.0 * sI;
        let core = granny(stage, { bob = 0.2, lean = -0.8, sq = 1.0,
                                   legF = (3.4, -2.4), legFh = 4.6,
                                   legB = (-2.0, -2.6), legBh = 4.2,
                                   handF = (3.6, -7.6), handB = (2.6, -8.4),
                                   eyeWide = true });
        let load = pack(stage, { packDx = lurch, packDy = 0.0 - 1.6 * sI,
                                 itemsDx = lurch * 1.25, itemsDy = 0.0 - 0.8 * sI,
                                 lanSway = 2.2 * sI, lanDy = 0.0 - 0.6 * sI });
        let cane = stickAt(stage, 3.6, -7.6, 8.2, -0.1);
        let hop = Curve.tri(0.12, stage#t) * 2.2;
        let fx =
            fadeP(0.35 * sI, circC(stage, 8.8, -1.0, 1.5, dustC(), 8)) ::
            fadeP(0.22 * sI, circC(stage, 7.0, -0.6, 1.0, dustC(), 8)) ::
            fadeP(0.8 * sI, boxC(stage, 9.6, 0.0 - 1.6 - hop, 1.1, 1.1, knobC(), 13)) :: Nil;
        List.flatten(core :: load :: cane :: fx :: Nil)

    /// ジャンプ: 体を丸めて膝を抱え、荷が背中からふわりと浮く（肩ひもが伸びる）。
    /// 提灯も遅れて浮き上がり、杖は斜め上へ掲げる。
    def jump(stage: CharStage.Stage): List[Render.PlacedItem] =
        let core = granny(stage, { bob = 0.0, lean = 0.6, sq = 1.0,
                                   legF = (1.8, -3.2), legFh = 3.2,
                                   legB = (-1.0, -3.4), legBh = 3.0,
                                   handF = (4.6, -9.5), handB = (-2.2, -10.5),
                                   eyeWide = false });
        let load = pack(stage, { packDx = -0.6, packDy = -3.2,
                                 itemsDx = -0.6, itemsDy = -1.2,
                                 lanSway = 0.5, lanDy = -1.8 });
        let cane = stickAt(stage, 4.6, -9.5, 7.8, -14.0);
        List.flatten(core :: load :: cane :: Nil)

    /// 落下: 浮いていた荷が背中へのしかかり、体が押しつぶされ気味に縮む。
    /// 目を丸くして杖の先を地面へ向け、着地に備える。
    def fall(stage: CharStage.Stage): List[Render.PlacedItem] =
        let core = granny(stage, { bob = 0.3, lean = 0.8, sq = 0.94,
                                   legF = (1.6, -2.2), legFh = 4.4,
                                   legB = (-1.2, -2.4), legBh = 4.6,
                                   handF = (4.4, -8.0), handB = (-2.0, -9.0),
                                   eyeWide = true });
        let load = pack(stage, { packDx = 0.3, packDy = 1.2,
                                 itemsDx = 0.3, itemsDy = -0.4,
                                 lanSway = 0.4, lanDy = -0.8 });
        let cane = stickAt(stage, 4.4, -8.0, 6.9, -0.9);
        List.flatten(core :: load :: cane :: Nil)

    /// 着地: 荷がどすんと沈んで婆を押しつぶし、上の荷物と提灯が一拍遅れて跳ねる。
    /// 左右へ土煙が広がり、杖にすがって耐える。
    def land(stage: CharStage.Stage): List[Render.PlacedItem] =
        let k = 1.0 - clamp01(stage#modeT / 0.2);
        let sq = 1.0 - 0.35 * k;
        let bounce = Curve.tri(0.2, stage#modeT);
        let core = granny(stage, { bob = 0.0, lean = 0.5, sq = sq,
                                   legF = (2.6, (0.0 - 2.2) * sq), legFh = 4.4 * sq,
                                   legB = (-2.2, (0.0 - 2.2) * sq), legBh = 4.4 * sq,
                                   handF = (4.0, (0.0 - 7.2) * sq), handB = (-1.6, (0.0 - 6.4) * sq),
                                   eyeWide = true });
        let load = pack(stage, { packDx = 0.0, packDy = 3.0 * k,
                                 itemsDx = 0.0, itemsDy = 3.0 * k - bounce * 2.4,
                                 lanSway = 0.3, lanDy = 3.0 * k - bounce * 3.0 });
        let cane = stickAt(stage, 4.0, (0.0 - 7.2) * sq, 6.6, -0.2);
        let e = 1.0 - k;
        let smokeR = List.map(i -> {
            let dxD = 2.5 + e * 4.5 + i * 1.4;
            fadeP((0.4 - 0.1 * i) * k, circC(stage, dxD, 0.0 - 1.2 - i * 0.6, 1.8 - 0.4 * i, dustC(), 8))
            }, 0.0 :: 1.0 :: 2.0 :: Nil);
        let smokeL = List.map(i -> {
            let dxD = 2.5 + e * 4.5 + i * 1.4;
            fadeP((0.4 - 0.1 * i) * k, circC(stage, 0.0 - dxD, 0.0 - 1.2 - i * 0.6, 1.8 - 0.4 * i, dustC(), 8))
            }, 0.0 :: 1.0 :: 2.0 :: Nil);
        List.flatten(core :: load :: cane :: smokeR :: smokeL :: Nil)
}
