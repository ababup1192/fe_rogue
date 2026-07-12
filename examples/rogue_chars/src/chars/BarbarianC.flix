// BarbarianC — 老いた呪い戦士。白髪を逆立てた骨飾りの頭、灰色の肌、
// 落ち窪んだ眼窩に時々灯る光。曲がった背中に不釣り合いなほど巨大な斧。
// 斧を杖代わりに引きずり、攻撃の瞬間だけ思いがけない速さで横薙ぎする。
//
// 色: gray/darkGray=灰肌・white/paleBlue=白髪と骨飾り・olive/mustard=ボロ布・
//     silver=斧鋼・yellow=溜めと眼光・purple/pink=斬撃の弧。

mod BarbarianC {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, discFill, arc, hflip, overlay, shift}
    use RogueStage.Clip

    pub def name(): String = "BARBARIAN C 呪われし老斧"

    // ── 色 ──
    def skinC(): Color = RoguePalette.gray()        // 灰色がかった肌
    def skinShadeC(): Color = RoguePalette.darkGray() // 肌の影
    def hairC(): Color = RoguePalette.white()       // 逆立つ白髪
    def boneC(): Color = RoguePalette.paleBlue()     // 骨の髪飾り
    def clothC(): Color = RoguePalette.olive()       // ボロ布の腰巻
    def clothLitC(): Color = RoguePalette.mustard()  // 布のハイライト
    def steelC(): Color = RoguePalette.silver()      // 斧の鋼
    def hafC(): Color = RoguePalette.darkGray()      // 斧の柄
    def glowC(): Color = RoguePalette.yellow()       // 溜め・眼光
    def arcC(): Color = RoguePalette.pink()          // 斬撃の弧（明色）
    def arcDeepC(): Color = RoguePalette.purple()    // 斬撃の弧（濃色）

    // ── 範囲外frameの丸め（負数補正つき剰余）──
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    // ══════════════════════════════════════════════════════
    //  頭部（個性）: 白髪逆立ち・骨飾り・灰肌・落ち窪んだ眼窩
    //  cx=頭の中心x, topY=髪の一番上のy, eyeGlow=眼窩に光が灯るか
    // ══════════════════════════════════════════════════════

    // 正面/背面向きの顔。faceFront=true で顔（眼窩）、false で後頭部。
    def headFront(cx: Int32, topY: Int32, eyeGlow: Bool, cv: Canvas): Canvas =
        let hy = topY;
        cv
            // 逆立つ白髪（上へ跳ねる3本）
            |> (c -> dot(cx - 2, hy, hairC(), c))
            |> (c -> dot(cx, hy, hairC(), c))
            |> (c -> dot(cx + 2, hy, hairC(), c))
            |> (c -> dot(cx - 2, hy + 1, hairC(), c))
            |> (c -> dot(cx - 1, hy + 1, hairC(), c))
            |> (c -> dot(cx, hy + 1, hairC(), c))
            |> (c -> dot(cx + 1, hy + 1, hairC(), c))
            |> (c -> dot(cx + 2, hy + 1, hairC(), c))
            // 骨の髪飾り（左右に突き出す）
            |> (c -> dot(cx - 3, hy + 1, boneC(), c))
            |> (c -> dot(cx + 3, hy + 1, boneC(), c))
            // 灰色の顔（幅5px・2..4行）
            |> hline(cx - 2, hy + 2, 5, skinC())
            |> hline(cx - 2, hy + 3, 5, skinC())
            |> hline(cx - 2, hy + 4, 5, skinC())
            // 落ち窪んだ眼窩（影・光が灯れば黄色）
            |> (c -> dot(cx - 1, hy + 3, if (eyeGlow) glowC() else skinShadeC(), c))
            |> (c -> dot(cx + 1, hy + 3, if (eyeGlow) glowC() else skinShadeC(), c))
            // こけた頬の影
            |> (c -> dot(cx - 2, hy + 4, skinShadeC(), c))
            |> (c -> dot(cx + 2, hy + 4, skinShadeC(), c))

    def headBack(cx: Int32, topY: Int32, cv: Canvas): Canvas =
        let hy = topY;
        cv
            |> (c -> dot(cx - 2, hy, hairC(), c))
            |> (c -> dot(cx, hy, hairC(), c))
            |> (c -> dot(cx + 2, hy, hairC(), c))
            |> hline(cx - 2, hy + 1, 5, hairC())
            // 骨飾りの裏（後頭部でも見える）
            |> (c -> dot(cx - 3, hy + 1, boneC(), c))
            |> (c -> dot(cx + 3, hy + 1, boneC(), c))
            // 後頭部（白髪が覆う・下だけ灰肌の首）
            |> hline(cx - 2, hy + 2, 5, hairC())
            |> hline(cx - 2, hy + 3, 5, hairC())
            |> hline(cx - 2, hy + 4, 5, skinC())

    // 横向き（左向き）の頭。骨飾りは後ろへ、白髪は上と後ろへ跳ねる。
    def headSide(cx: Int32, topY: Int32, eyeGlow: Bool, cv: Canvas): Canvas =
        let hy = topY;
        cv
            // 白髪（上と後方=右へ跳ねる）
            |> (c -> dot(cx - 1, hy, hairC(), c))
            |> (c -> dot(cx + 1, hy, hairC(), c))
            |> (c -> dot(cx + 2, hy, hairC(), c))
            |> hline(cx - 1, hy + 1, 4, hairC())
            // 骨飾り（後方へ突き出す）
            |> (c -> dot(cx + 3, hy + 1, boneC(), c))
            // 灰肌の横顔（幅4px・鼻先は左=cx-2）
            |> hline(cx - 2, hy + 2, 4, skinC())
            |> hline(cx - 2, hy + 3, 4, skinC())
            |> hline(cx - 1, hy + 4, 3, skinC())
            // 落ち窪んだ眼窩（前寄り）
            |> (c -> dot(cx - 1, hy + 3, if (eyeGlow) glowC() else skinShadeC(), c))
            // あご/頬の影
            |> (c -> dot(cx + 1, hy + 4, skinShadeC(), c))

    // ══════════════════════════════════════════════════════
    //  胴と腰布・脚（前傾した曲がった背中）
    //  leanX=前傾で頭～肩をどれだけ前へずらすか
    //  legPhase: 歩行の脚の開き（-1,0,1）
    // ══════════════════════════════════════════════════════

    // 正面の胴（曲がった背中・ボロ布の腰巻）
    def torsoFront(cx: Int32, shoulderY: Int32, cv: Canvas): Canvas =
        cv
            // 灰肌の胴（肩幅6→腰4へすぼまる）
            |> hline(cx - 3, shoulderY, 6, skinC())
            |> hline(cx - 3, shoulderY + 1, 6, skinC())
            |> (c -> dot(cx - 3, shoulderY + 1, skinShadeC(), c))  // 曲がった背の影
            |> hline(cx - 2, shoulderY + 2, 5, skinC())
            |> hline(cx - 2, shoulderY + 3, 5, skinC())
            // ボロ布の腰巻（ぼろぼろの裾）
            |> hline(cx - 3, shoulderY + 4, 6, clothC())
            |> hline(cx - 3, shoulderY + 5, 6, clothC())
            |> (c -> dot(cx - 2, shoulderY + 4, clothLitC(), c))
            |> (c -> dot(cx + 1, shoulderY + 4, clothLitC(), c))
            |> hline(cx - 2, shoulderY + 6, 5, clothC())
            // ぼろの垂れ
            |> (c -> dot(cx - 3, shoulderY + 6, clothC(), c))
            |> (c -> dot(cx + 2, shoulderY + 7, clothC(), c))

    // 正面の脚（legPhase で左右の開き）
    def legsFront(cx: Int32, hipY: Int32, legPhase: Int32, cv: Canvas): Canvas =
        let lx = cx - 2 - (if (legPhase > 0) 1 else 0);
        let rx = cx + 2 + (if (legPhase < 0) 1 else 0);
        cv
            |> vline(lx, hipY, 2, skinC())
            |> vline(rx, hipY, 2, skinC())
            |> (c -> dot(lx, hipY + 2, skinShadeC(), c))  // 足
            |> (c -> dot(rx, hipY + 2, skinShadeC(), c))

    // 横向き（左向き）の胴（前傾が強い）
    def torsoSide(cx: Int32, shoulderY: Int32, cv: Canvas): Canvas =
        cv
            |> hline(cx - 2, shoulderY, 4, skinC())
            |> hline(cx - 2, shoulderY + 1, 4, skinC())
            |> (c -> dot(cx + 1, shoulderY + 1, skinShadeC(), c))  // 曲がった背（後ろ側）
            |> hline(cx - 2, shoulderY + 2, 4, skinC())
            |> hline(cx - 2, shoulderY + 3, 4, skinC())
            // 腰布
            |> hline(cx - 2, shoulderY + 4, 4, clothC())
            |> hline(cx - 2, shoulderY + 5, 4, clothC())
            |> (c -> dot(cx - 1, shoulderY + 4, clothLitC(), c))
            |> hline(cx - 2, shoulderY + 6, 3, clothC())

    def legsSide(cx: Int32, hipY: Int32, legPhase: Int32, cv: Canvas): Canvas =
        let frontX = cx - 1 - (if (legPhase > 0) 1 else 0);
        let backX = cx + 1 + (if (legPhase < 0) 1 else 0);
        cv
            |> vline(frontX, hipY, 2, skinC())
            |> vline(backX, hipY, 2, skinShadeC())
            |> (c -> dot(frontX, hipY + 2, skinShadeC(), c))
            |> (c -> dot(backX, hipY + 2, skinShadeC(), c))

    // ══════════════════════════════════════════════════════
    //  巨大な斧（主役・常時見える）
    //  柄の2点(x0,y0)-(x1,y1)を結び、頭(hx,hy)に鋼の刃を置く。
    // ══════════════════════════════════════════════════════

    // 斧の柄（幅2px+芯のハイライト）
    def haft(x0: Int32, y0: Int32, x1: Int32, y1: Int32, cv: Canvas): Canvas =
        cv
            |> line(x0, y0, x1, y1, hafC())
            |> line(x0 + 1, y0, x1 + 1, y1, hafC())
            |> line(x0, y0, x1, y1, steelC())  // 芯のハイライト1px

    // 斧の刃（頭 hx,hy を中心に三日月形の鋼・幅を持たせる）
    def axeHead(hx: Int32, hy: Int32, cv: Canvas): Canvas =
        cv
            |> hline(hx - 1, hy - 2, 4, steelC())
            |> hline(hx - 2, hy - 1, 6, steelC())
            |> hline(hx - 2, hy, 6, steelC())
            |> hline(hx - 1, hy + 1, 5, steelC())
            |> (c -> dot(hx, hy + 2, steelC(), c))
            // 刃先のハイライト
            |> (c -> dot(hx - 2, hy - 1, hairC(), c))
            |> (c -> dot(hx - 2, hy, hairC(), c))
            // 峰の影
            |> (c -> dot(hx + 3, hy - 1, hafC(), c))
            |> (c -> dot(hx + 3, hy, hafC(), c))

    // ══════════════════════════════════════════════════════
    //  腕（肩から手まで2px幅・胴から独立）
    // ══════════════════════════════════════════════════════
    def arm(x0: Int32, y0: Int32, x1: Int32, y1: Int32, cv: Canvas): Canvas =
        cv
            |> line(x0, y0, x1, y1, skinC())
            |> line(x0, y0 + 1, x1, y1 + 1, skinShadeC())

    // ══════════════════════════════════════════════════════
    //  IdleDown — 荒い呼吸で肩が上下、斧を杖に引きずる
    // ══════════════════════════════════════════════════════
    def idleDown(frame: Int32): Canvas =
        // 呼吸: f1,f3 で肩が1px下がる（力なく沈む）
        let breath = if (frame == 1 or frame == 3) 1 else 0;
        let cx = 15;
        let sy = 12 + breath;
        empty()
            |> legsFront(cx, 23, 0)
            |> torsoFront(cx, sy)
            |> headFront(cx, sy - 6, frame == 2)  // f2で眼窩に光
            // 左手は胸に、右腕で斧を杖代わりに（右下へ）
            |> arm(cx + 2, sy + 1, cx + 4, sy + 4)
            // 斧を杖に: 柄を地面近くまで、刃は上・肩の高さ
            |> haft(cx + 4, sy - 2, cx + 4, 24)
            |> axeHead(cx + 4, sy - 3)

    // ══════════════════════════════════════════════════════
    //  IdleUp — 背面。肩が呼吸で上下、斧を背側で引きずる
    // ══════════════════════════════════════════════════════
    def idleUp(frame: Int32): Canvas =
        let breath = if (frame == 1 or frame == 3) 1 else 0;
        let cx = 15;
        let sy = 12 + breath;
        empty()
            |> legsFront(cx, 23, 0)
            |> backTorso(cx, sy)
            |> headBack(cx, sy - 6)
            |> arm(cx + 2, sy + 1, cx + 4, sy + 4)
            |> haft(cx + 4, sy - 2, cx + 4, 24)
            |> axeHead(cx + 4, sy - 3)

    // ══════════════════════════════════════════════════════
    //  IdleSide — 左向き。前傾で斧を杖に、肩の呼吸
    // ══════════════════════════════════════════════════════
    def idleSide(frame: Int32): Canvas =
        let breath = if (frame == 1 or frame == 3) 1 else 0;
        let cx = 15;
        let sy = 12 + breath;
        empty()
            |> legsSide(cx, 23, 0)
            |> torsoSide(cx, sy)
            |> headSide(cx - 1, sy - 6, frame == 2)
            // 腕が前へ、斧を杖に前方(左)で支える
            |> arm(cx - 1, sy + 1, cx - 3, sy + 3)
            |> haft(cx - 4, sy - 3, cx - 3, 24)
            |> axeHead(cx - 4, sy - 4)

    // ══════════════════════════════════════════════════════
    //  WalkDown — 斧を引きずる重い歩き・前傾・体の上下
    // ══════════════════════════════════════════════════════
    def walkDown(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let bob = if (f == 1 or f == 3) 0 else 1;  // 体の上下1px
        let legPh = match f { case 0 => 1 case 1 => 0 case 2 => -1 case _ => 0 };
        let cx = 15;
        let sy = 12 + bob;
        // 腕振り: 左腕（斧を持たない側）が前後
        let armDx = match f { case 0 => -1 case 2 => 1 case _ => 0 };
        empty()
            |> legsFront(cx, 23, legPh)
            |> torsoFront(cx, sy)
            |> headFront(cx, sy - 6, false)
            |> arm(cx - 3, sy + 1, cx - 4 + armDx, sy + 4)  // 振る腕
            // 斧を右手で引きずる（刃が地面近く・重そうに後ろへ）
            |> arm(cx + 2, sy + 1, cx + 4, sy + 3)
            |> haft(cx + 4, sy, cx + 6, 25)
            |> axeHead(cx + 5, 26)

    // ══════════════════════════════════════════════════════
    //  WalkUp — 背面の重い歩き
    // ══════════════════════════════════════════════════════
    def walkUp(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let bob = if (f == 1 or f == 3) 0 else 1;
        let legPh = match f { case 0 => 1 case 1 => 0 case 2 => -1 case _ => 0 };
        let cx = 15;
        let sy = 12 + bob;
        let armDx = match f { case 0 => -1 case 2 => 1 case _ => 0 };
        empty()
            |> legsFront(cx, 23, legPh)
            |> backTorso(cx, sy)
            |> headBack(cx, sy - 6)
            |> arm(cx - 3, sy + 1, cx - 4 + armDx, sy + 4)
            |> arm(cx + 2, sy + 1, cx + 4, sy + 3)
            |> haft(cx + 4, sy, cx + 6, 25)
            |> axeHead(cx + 5, 26)

    // ══════════════════════════════════════════════════════
    //  WalkSide — 左向きの重い歩き。斧を後ろへ引きずる
    //  f0 は左右非対称必須（前脚が明確に前へ）
    // ══════════════════════════════════════════════════════
    def walkSide(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let bob = if (f == 1 or f == 3) 0 else 1;
        let legPh = match f { case 0 => 1 case 1 => 0 case 2 => -1 case _ => 0 };
        let cx = 15;
        let sy = 12 + bob;
        empty()
            |> legsSide(cx, 23, legPh)
            |> torsoSide(cx, sy)
            |> headSide(cx - 1, sy - 6, false)
            // 前腕は前(左)へ振る
            |> arm(cx - 2, sy + 1, cx - 3 + (if (f == 0) -1 else 0), sy + 3)
            // 斧を右手で後方(右)へ引きずる
            |> arm(cx + 1, sy + 1, cx + 3, sy + 3)
            |> haft(cx + 3, sy + 1, cx + 6, 26)
            |> axeHead(cx + 5, 27)

    // ══════════════════════════════════════════════════════
    //  AttackDown — 溜め(静止・眼光)→思いがけない速さの横薙ぎ
    //  斧を頭上から手前・下へ振り下ろす。軌跡は紫～桃の弧。
    //  6コマ: 0-1溜め / 2 振り始め / 3-4 斬撃(弧) / 5 振り切り
    // ══════════════════════════════════════════════════════
    def attackDown(frame: Int32): Canvas =
        let f = wrap(frame, 6);
        let cx = 15;
        let sy = 12;
        let bodyGlowEye = f <= 1;  // 溜めの間は目が黄色
        let base =
            empty()
                |> legsFront(cx, 23, if (f >= 4) -1 else 0)
                |> torsoFront(cx, sy)
                |> headFront(cx, sy - 6, bodyGlowEye);
        match f {
            // 溜め: 斧を高く頭上へ・目が光る
            case 0 =>
                base
                    |> arm(cx + 2, sy + 1, cx + 5, sy - 3)
                    |> haft(cx + 5, sy - 8, cx + 5, sy - 2)
                    |> axeHead(cx + 5, sy - 9)
            case 1 =>
                // わずかに引き絞る（さらに後ろへ）
                base
                    |> arm(cx + 2, sy + 1, cx + 6, sy - 3)
                    |> haft(cx + 6, sy - 9, cx + 6, sy - 2)
                    |> axeHead(cx + 6, sy - 10)
            // 振り下ろし始め（斜め上へ）
            case 2 =>
                base
                    |> arc(cx, sy + 2, 12, 20, 80, arcDeepC())
                    |> arm(cx + 1, sy + 1, cx + 6, sy - 4)
                    |> haft(cx + 6, sy - 8, cx + 5, sy - 3)
                    |> axeHead(cx + 7, sy - 8)
            // 斬撃の弧（手前・下へ薙ぐ・明色の連続弧）
            case 3 =>
                base
                    |> arc(cx, sy + 1, 13, 300, 30, arcDeepC())
                    |> arc(cx, sy + 1, 12, 300, 40, arcC())
                    |> arc(cx, sy + 1, 11, 310, 30, arcC())
                    |> arm(cx + 1, sy + 2, cx + 5, sy + 4)
                    |> haft(cx + 5, sy + 3, cx + 9, sy + 8)
                    |> axeHead(cx + 8, sy + 9)
            case 4 =>
                base
                    |> arc(cx, sy + 2, 12, 250, 350, arcC())
                    |> arc(cx, sy + 2, 11, 260, 350, arcDeepC())
                    |> arm(cx + 1, sy + 3, cx + 3, sy + 6)
                    |> haft(cx + 2, sy + 6, cx - 2, 27)
                    |> axeHead(cx - 3, 27)
            // 振り切り（斧が地に近い・残心）
            case _ =>
                base
                    |> arm(cx, sy + 3, cx - 2, sy + 5)
                    |> haft(cx - 2, sy + 5, cx - 5, 27)
                    |> axeHead(cx - 6, 27)
        }

    // ══════════════════════════════════════════════════════
    //  AttackUp — 背面。斧を頭上から奥へ振り上げる薙ぎ
    // ══════════════════════════════════════════════════════
    def attackUp(frame: Int32): Canvas =
        let f = wrap(frame, 6);
        let cx = 15;
        let sy = 12;
        let base =
            empty()
                |> legsFront(cx, 23, if (f >= 4) -1 else 0)
                |> backTorso(cx, sy)
                |> headBack(cx, sy - 6);
        match f {
            case 0 =>
                base
                    |> arm(cx + 2, sy + 1, cx + 5, sy + 3)
                    |> haft(cx + 5, sy + 2, cx + 5, sy + 8)
                    |> axeHead(cx + 5, sy + 8)
            case 1 =>
                base
                    |> arm(cx + 2, sy + 1, cx + 6, sy + 4)
                    |> haft(cx + 6, sy + 3, cx + 6, sy + 9)
                    |> axeHead(cx + 6, sy + 9)
            case 2 =>
                base
                    |> arc(cx, sy + 1, 12, 280, 340, arcDeepC())
                    |> arm(cx + 1, sy + 1, cx + 6, sy)
                    |> haft(cx + 6, sy - 4, cx + 5, sy + 1)
                    |> axeHead(cx + 7, sy - 4)
            case 3 =>
                base
                    |> arc(cx, sy - 1, 13, 40, 140, arcC())
                    |> arc(cx, sy - 1, 12, 40, 140, arcDeepC())
                    |> arm(cx + 1, sy, cx + 4, sy - 4)
                    |> haft(cx + 4, sy - 4, cx + 7, sy - 8)
                    |> axeHead(cx + 6, sy - 9)
            case 4 =>
                base
                    |> arc(cx, sy - 1, 12, 110, 200, arcC())
                    |> arm(cx - 1, sy, cx - 4, sy - 3)
                    |> haft(cx - 4, sy - 3, cx - 7, sy - 6)
                    |> axeHead(cx - 8, sy - 7)
            case _ =>
                base
                    |> arm(cx - 1, sy + 1, cx - 4, sy - 1)
                    |> haft(cx - 4, sy - 1, cx - 6, sy - 3)
                    |> axeHead(cx - 7, sy - 4)
        }

    // ══════════════════════════════════════════════════════
    //  AttackSide — 左向き。溜め→思いがけぬ速さの横薙ぎ（左へ）
    // ══════════════════════════════════════════════════════
    def attackSide(frame: Int32): Canvas =
        let f = wrap(frame, 6);
        let cx = 15;
        let sy = 12;
        let base =
            empty()
                |> legsSide(cx, 23, if (f >= 4) -1 else 0)
                |> torsoSide(cx, sy)
                |> headSide(cx - 1, sy - 6, f <= 1);
        match f {
            // 溜め: 斧を後ろ(右)高くへ振りかぶる・目が光る
            case 0 =>
                base
                    |> arm(cx + 1, sy + 1, cx + 4, sy - 3)
                    |> haft(cx + 4, sy - 8, cx + 4, sy - 2)
                    |> axeHead(cx + 4, sy - 9)
            case 1 =>
                base
                    |> arm(cx + 1, sy + 1, cx + 5, sy - 4)
                    |> haft(cx + 5, sy - 9, cx + 5, sy - 3)
                    |> axeHead(cx + 5, sy - 10)
            // 振り始め（頭上）
            case 2 =>
                base
                    |> arc(cx, sy, 13, 40, 110, arcDeepC())
                    |> arm(cx, sy + 1, cx + 2, sy - 5)
                    |> haft(cx + 2, sy - 8, cx, sy - 3)
                    |> axeHead(cx + 1, sy - 9)
            // 斬撃の弧（前=左へ薙ぐ・明色の連続弧2〜3px幅）
            case 3 =>
                base
                    |> arc(cx, sy, 14, 90, 180, arcDeepC())
                    |> arc(cx, sy, 13, 90, 180, arcC())
                    |> arc(cx, sy, 12, 100, 180, arcC())
                    |> arm(cx - 1, sy, cx - 5, sy - 1)
                    |> haft(cx - 5, sy - 1, cx - 9, sy - 3)
                    |> axeHead(cx - 10, sy - 4)
            case 4 =>
                base
                    |> arc(cx, sy + 1, 13, 150, 220, arcC())
                    |> arc(cx, sy + 1, 12, 160, 220, arcDeepC())
                    |> arm(cx - 1, sy + 2, cx - 5, sy + 3)
                    |> haft(cx - 5, sy + 3, cx - 9, sy + 5)
                    |> axeHead(cx - 10, sy + 5)
            // 振り切り（斧が前の地に近い・残心）
            case _ =>
                base
                    |> arm(cx - 1, sy + 3, cx - 4, sy + 5)
                    |> haft(cx - 4, sy + 5, cx - 7, 27)
                    |> axeHead(cx - 8, 27)
        }

    // ══════════════════════════════════════════════════════
    //  UseItem — 掲げる→明色フラッシュ→使う（3拍）
    //  呪いの品を掲げて発動する。斧は杖の位置に据える。
    // ══════════════════════════════════════════════════════
    def useItemDown(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let cx = 15;
        let sy = 12;
        let base =
            empty()
                |> legsFront(cx, 23, 0)
                |> torsoFront(cx, sy)
                |> headFront(cx, sy - 6, f == 1 or f == 2)
                // 斧は右で杖に
                |> haft(cx + 4, sy - 2, cx + 4, 24)
                |> axeHead(cx + 4, sy - 3);
        match f {
            // 掲げる
            case 0 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 3)
                    |> (c -> dot(cx - 3, sy - 4, boneC(), c))
            // 明色フラッシュ（掲げた品が白く輝く）
            case 1 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 4)
                    |> discFill(cx - 3, sy - 5, 2, glowC())
                    |> (c -> dot(cx - 3, sy - 5, hairC(), c))
            case 2 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 4)
                    |> discFill(cx - 3, sy - 5, 1, hairC())
            // 使う（手を下ろす）
            case _ =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy + 1)
                    |> (c -> dot(cx - 3, sy + 2, boneC(), c))
        }

    def useItemUp(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let cx = 15;
        let sy = 12;
        let base =
            empty()
                |> legsFront(cx, 23, 0)
                |> backTorso(cx, sy)
                |> headBack(cx, sy - 6)
                |> haft(cx + 4, sy - 2, cx + 4, 24)
                |> axeHead(cx + 4, sy - 3);
        match f {
            case 0 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 3)
                    |> (c -> dot(cx - 3, sy - 4, boneC(), c))
            case 1 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 4)
                    |> discFill(cx - 3, sy - 5, 2, glowC())
                    |> (c -> dot(cx - 3, sy - 5, hairC(), c))
            case 2 =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy - 4)
                    |> discFill(cx - 3, sy - 5, 1, hairC())
            case _ =>
                base
                    |> arm(cx - 2, sy + 1, cx - 3, sy + 1)
                    |> (c -> dot(cx - 3, sy + 2, boneC(), c))
        }

    def useItemSide(frame: Int32): Canvas =
        let f = wrap(frame, 4);
        let cx = 15;
        let sy = 12;
        let base =
            empty()
                |> legsSide(cx, 23, 0)
                |> torsoSide(cx, sy)
                |> headSide(cx - 1, sy - 6, f == 1 or f == 2)
                // 斧は後方(右)で杖に
                |> haft(cx + 3, sy - 2, cx + 3, 24)
                |> axeHead(cx + 3, sy - 3);
        match f {
            // 掲げる（前=左へ）
            case 0 =>
                base
                    |> arm(cx - 1, sy + 1, cx - 3, sy - 3)
                    |> (c -> dot(cx - 3, sy - 4, boneC(), c))
            case 1 =>
                base
                    |> arm(cx - 1, sy + 1, cx - 4, sy - 4)
                    |> discFill(cx - 4, sy - 5, 2, glowC())
                    |> (c -> dot(cx - 4, sy - 5, hairC(), c))
            case 2 =>
                base
                    |> arm(cx - 1, sy + 1, cx - 4, sy - 4)
                    |> discFill(cx - 4, sy - 5, 1, hairC())
            case _ =>
                base
                    |> arm(cx - 1, sy + 1, cx - 3, sy + 1)
                    |> (c -> dot(cx - 4, sy + 1, boneC(), c))
        }

    // ══════════════════════════════════════════════════════
    //  Damage — 白フラッシュ+よろめき（3コマ）
    //  f0=全身白シルエット+後方ノックバック / f1-2=のけぞり戻り
    // ══════════════════════════════════════════════════════

    // 全身を白で塗ったフラッシュ用シルエット（正面）
    def whiteFront(cx: Int32, sy: Int32): Canvas =
        empty()
            |> legsFront(cx, 23, 0)
            |> torsoFront(cx, sy)
            |> headFront(cx, sy - 6, false)
            |> arm(cx + 2, sy + 1, cx + 4, sy + 4)
            |> haft(cx + 4, sy - 2, cx + 4, 24)
            |> axeHead(cx + 4, sy - 3)
            |> Map.map(_ -> hairC())  // 全ピクセルを白に

    def damageDown(frame: Int32): Canvas =
        let f = wrap(frame, 3);
        let cx = 15;
        match f {
            // 全身白フラッシュ+手前へ2px（Down=手前=下へ）
            case 0 => shift(0, 2, whiteFront(cx, 12))
            // のけぞり（頭が手前へ倒れ気味）
            case 1 =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> torsoFront(cx, 13)
                    |> headFront(cx + 1, 8, false)
                    |> arm(cx - 3, 14, cx - 5, 16)  // 腕が跳ねる
                    |> haft(cx + 4, 11, cx + 5, 25)
                    |> axeHead(cx + 4, 10)
            case _ =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> torsoFront(cx, 12)
                    |> headFront(cx, 6, false)
                    |> arm(cx + 2, 13, cx + 4, 16)
                    |> haft(cx + 4, 10, cx + 4, 24)
                    |> axeHead(cx + 4, 9)
        }

    // 背面の胴（肩y=sy2）。UseItemUp/AttackUp/DamageUp/WalkUp/IdleUp で共用。
    def backTorso(cx: Int32, sy2: Int32, cv: Canvas): Canvas =
        cv
            |> hline(cx - 3, sy2, 6, skinC())
            |> hline(cx - 3, sy2 + 1, 6, skinC())
            |> hline(cx - 2, sy2 + 2, 5, skinC())
            |> hline(cx - 2, sy2 + 3, 5, skinC())
            |> hline(cx - 3, sy2 + 4, 6, clothC())
            |> hline(cx - 3, sy2 + 5, 6, clothC())
            |> hline(cx - 2, sy2 + 6, 5, clothC())

    def damageUp(frame: Int32): Canvas =
        let f = wrap(frame, 3);
        let cx = 15;
        match f {
            // 白フラッシュ+奥へ2px（Up=奥=上へ）
            case 0 =>
                let sil =
                    empty()
                        |> legsFront(cx, 23, 0)
                        |> backTorso(cx, 12)
                        |> headBack(cx, 6)
                        |> haft(cx + 4, 10, cx + 4, 24)
                        |> axeHead(cx + 4, 9);
                shift(0, -2, Map.map(_ -> hairC(), sil))
            case 1 =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> backTorso(cx, 11)
                    |> headBack(cx - 1, 4)
                    |> arm(cx + 3, 12, cx + 5, 10)
                    |> haft(cx + 4, 9, cx + 5, 23)
                    |> axeHead(cx + 4, 8)
            case _ =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> backTorso(cx, 12)
                    |> headBack(cx, 6)
                    |> haft(cx + 4, 10, cx + 4, 24)
                    |> axeHead(cx + 4, 9)
        }

    def damageSide(frame: Int32): Canvas =
        let f = wrap(frame, 3);
        let cx = 15;
        match f {
            // 白フラッシュ+横(後方=右)へ2px（Side=横へ）
            case 0 =>
                let sil =
                    empty()
                        |> legsSide(cx, 23, 0)
                        |> torsoSide(cx, 12)
                        |> headSide(cx - 1, 6, false)
                        |> haft(cx + 3, 10, cx + 3, 24)
                        |> axeHead(cx + 3, 9);
                shift(2, 0, Map.map(_ -> hairC(), sil))
            case 1 =>
                empty()
                    |> legsSide(cx, 23, 0)
                    |> torsoSide(cx + 1, 13)
                    |> headSide(cx + 1, 8, false)  // 頭が後ろへのけぞる
                    |> arm(cx - 1, 14, cx - 3, 12)
                    |> haft(cx + 4, 11, cx + 4, 25)
                    |> axeHead(cx + 4, 10)
            case _ =>
                empty()
                    |> legsSide(cx, 23, 0)
                    |> torsoSide(cx, 12)
                    |> headSide(cx - 1, 6, false)
                    |> haft(cx + 3, 10, cx + 3, 24)
                    |> axeHead(cx + 3, 9)
        }

    // ══════════════════════════════════════════════════════
    //  Death — よろめき(2)→膝から崩れ(2)→膝立ち前傾がくり(2)
    //  倒れ伏さない。骨飾りが揺れ、途中で斧が手を離れ地に落ちる。
    // ══════════════════════════════════════════════════════
    def death(frame: Int32): Canvas =
        let f = wrap(frame, 6);
        let cx = 15;
        match f {
            // よろめき0: 立ったまま後ろへ傾く・斧まだ手に
            case 0 =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> torsoFront(cx + 1, 13)
                    |> headFront(cx + 2, 7, false)
                    |> arm(cx + 3, 14, cx + 5, 16)
                    |> haft(cx + 5, 12, cx + 6, 25)
                    |> axeHead(cx + 5, 11)
            // よろめき1: 反対へよろける・骨飾り揺れ
            case 1 =>
                empty()
                    |> legsFront(cx, 23, 0)
                    |> torsoFront(cx - 1, 13)
                    |> headFront(cx - 2, 7, false)
                    |> arm(cx - 3, 14, cx - 5, 15)
                    |> haft(cx + 4, 12, cx + 6, 25)
                    |> axeHead(cx + 5, 11)
            // 膝から崩れ2: 体が沈む・斧が手を離れ落ち始める
            case 2 =>
                empty()
                    // 膝立ちへ: 脚を折り、腰を下げる
                    |> vline(cx - 2, 20, 3, skinC())
                    |> vline(cx + 2, 20, 3, skinC())
                    |> (c -> dot(cx - 2, 23, skinShadeC(), c))
                    |> (c -> dot(cx + 2, 23, skinShadeC(), c))
                    |> torsoFront(cx, 15)
                    |> headFront(cx, 9, false)
                    |> arm(cx - 3, 16, cx - 5, 19)
                    // 斧が落下中（手前・下へ・傾く）
                    |> haft(cx + 5, 20, cx + 8, 27)
                    |> axeHead(cx + 7, 27)
            // 崩れ3: さらに沈む・斧は地に着いた
            case 3 =>
                empty()
                    |> vline(cx - 2, 21, 2, skinC())
                    |> vline(cx + 2, 21, 2, skinC())
                    |> hline(cx - 3, 23, 7, skinShadeC())  // 膝が地に
                    |> torsoFront(cx, 17)
                    |> headFront(cx, 11, false)
                    |> arm(cx - 3, 18, cx - 5, 21)
                    // 斧は地に横たわる
                    |> haft(cx + 4, 27, cx + 9, 28)
                    |> axeHead(cx + 9, 27)
            // 膝立ち前傾がくり4: 前へ折れる・骨飾り垂れる
            case 4 =>
                empty()
                    |> hline(cx - 3, 23, 7, skinShadeC())  // 膝立ち
                    |> hline(cx - 3, 22, 6, skinC())
                    // 前傾した胴（頭が前=下がる）
                    |> hline(cx - 2, 18, 5, skinC())
                    |> hline(cx - 2, 19, 5, skinC())
                    |> hline(cx - 3, 20, 6, clothC())
                    |> hline(cx - 3, 21, 6, clothC())
                    // 前へ垂れた頭（骨飾り揺れ）
                    |> headFront(cx - 1, 13, false)
                    |> (c -> dot(cx - 4, 15, boneC(), c))  // 揺れる骨飾り
                    |> arm(cx - 2, 19, cx - 4, 22)
                    |> haft(cx + 4, 27, cx + 9, 28)
                    |> axeHead(cx + 9, 27)
            // 前傾がくり5: 最深部・膝立ちシルエットは保つ
            case _ =>
                empty()
                    |> hline(cx - 3, 23, 7, skinShadeC())
                    |> hline(cx - 3, 22, 6, skinC())
                    |> hline(cx - 2, 19, 5, skinC())
                    |> hline(cx - 2, 20, 5, skinC())
                    |> hline(cx - 3, 21, 6, clothC())
                    |> hline(cx - 3, 22, 6, clothC())
                    // さらに深く前傾（頭が膝近くへ）
                    |> headFront(cx - 1, 15, false)
                    |> (c -> dot(cx - 4, 17, boneC(), c))
                    |> arm(cx - 1, 20, cx - 3, 23)
                    |> haft(cx + 4, 27, cx + 9, 28)
                    |> axeHead(cx + 9, 27)
        }

    // ══════════════════════════════════════════════════════
    //  ディスパッチ
    // ══════════════════════════════════════════════════════
    // 各クリップの絵を一律 4px 下げて足元を地面 y=29 に接地させる。
    // コマごとの個別調整より安全（宙に浮く取りこぼしが起きない）。
    pub def draw(clip: Clip, frame: Int32): Canvas =
        baseDraw(clip, frame) |> shift(0, 4)

    def baseDraw(clip: Clip, frame: Int32): Canvas = match clip {
        case Clip.IdleDown    => idleDown(frame)
        case Clip.IdleUp      => idleUp(frame)
        case Clip.IdleSide    => idleSide(frame)
        case Clip.WalkDown    => walkDown(frame)
        case Clip.WalkUp      => walkUp(frame)
        case Clip.WalkSide    => walkSide(frame)
        case Clip.AttackDown  => attackDown(frame)
        case Clip.AttackUp    => attackUp(frame)
        case Clip.AttackSide  => attackSide(frame)
        case Clip.UseItemDown => useItemDown(frame)
        case Clip.UseItemUp   => useItemUp(frame)
        case Clip.UseItemSide => useItemSide(frame)
        case Clip.DamageDown  => damageDown(frame)
        case Clip.DamageUp    => damageUp(frame)
        case Clip.DamageSide  => damageSide(frame)
        case Clip.Death       => death(frame)
    }
}
