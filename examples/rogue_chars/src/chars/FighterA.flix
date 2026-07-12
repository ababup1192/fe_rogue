// FighterA — 大柄な歴戦傭兵（剣+斧の使い手）。
// 黒髪に赤いバンダナ、無精髭の厳つい顔。革鎧に片肩だけ金属の肩当て、
// 背中に剣と斧を×字に背負う。待機/歩行でも背中の武器が見え、攻撃は剣の大きな横薙ぎ。

mod FighterA {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, discFill, arc, overlay, shift}
    use RogueStage.Clip

    // ── 色（革+鋼+肌+バンダナ+影の 6 色）──
    def leather(): Color = RoguePalette.darkBrown()   // 革鎧の本体
    def leatherLit(): Color = RoguePalette.brown()    // 革のハイライト
    def steel(): Color = RoguePalette.silver()        // 鋼（刃・肩当て）のハイライト
    def steelDark(): Color = RoguePalette.gray()      // 鋼の影
    def skinC(): Color = RoguePalette.skin()          // 日焼け肌のハイライト
    def skinDark(): Color = RoguePalette.tan()        // 肌の影
    def bandana(): Color = RoguePalette.red()         // 赤いバンダナ
    def hairC(): Color = RoguePalette.black()         // 黒髪・無精髭
    def shadowC(): Color = RoguePalette.darkBrown()   // 接地影・輪郭
    def trail(): Color = RoguePalette.paleBlue()      // 斬撃軌跡の明色

    pub def name(): String = "FIGHTER A 歴戦の傭兵"

    pub def draw(clip: Clip, frame: Int32): Canvas =
        let f = frameCount(clip);
        let n = if (f <= 0) 0 else Int32.remainder(Int32.remainder(frame, f) + f, f);
        match clip {
            case Clip.IdleDown    => idleDown(n)
            case Clip.IdleUp      => idleUp(n)
            case Clip.IdleSide    => idleSide(n)
            case Clip.WalkDown    => walkDown(n)
            case Clip.WalkUp      => walkUp(n)
            case Clip.WalkSide    => walkSide(n)
            case Clip.AttackDown  => attackDown(n)
            case Clip.AttackUp    => attackUp(n)
            case Clip.AttackSide  => attackSide(n)
            case Clip.UseItemDown => useItemDown(n)
            case Clip.UseItemUp   => useItemUp(n)
            case Clip.UseItemSide => useItemSide(n)
            case Clip.DamageDown  => damageDown(n)
            case Clip.DamageUp    => damageUp(n)
            case Clip.DamageSide  => damageSide(n)
            case Clip.Death       => death(n)
        }

    def frameCount(c: Clip): Int32 = RogueStage.frameCount(c)

    // 接地影（全クリップ共通・足元 y=29 の下地）。
    def groundShadow(): Canvas =
        empty() |> hline(10, 29, 12, shadowC())

    // ══════════════════════════════════════════════════════════
    //  頭部パーツ（個性）— 黒髪・赤バンダナ・無精髭・厳つい顔
    // ══════════════════════════════════════════════════════════

    // 正面の頭（Down/Idle 用）。中心 x=15..16、頭頂 y=4 付近。
    // bob=息づかいの上下・sq=顔をしかめる差分。
    def headFront(topY: Int32): Canvas =
        let y = topY;
        empty()
            // 黒髪の輪郭（頭頂）
            |> hline(12, y, 8, hairC())
            |> hline(11, y + 1, 10, hairC())
            // 赤いバンダナ（額に巻いた布・後ろで結び目）
            |> hline(11, y + 2, 10, bandana())
            |> dot(20, y + 2, bandana())
            |> hline(11, y + 3, 10, bandana())
            |> dot(21, y + 3, bandana())          // 結び目の垂れ
            // 顔（日焼け肌）
            |> hline(12, y + 4, 8, skinC())
            |> hline(12, y + 5, 8, skinC())
            // 目（厳つい・眉のかげ）
            |> dot(13, y + 5, hairC())
            |> dot(18, y + 5, hairC())
            |> hline(12, y + 6, 8, skinC())
            // 鼻筋の影
            |> dot(15, y + 6, skinDark())
            |> dot(16, y + 6, skinDark())
            // 無精髭（頬〜顎を黒でざらつかせる）
            |> dot(12, y + 7, hairC())
            |> dot(14, y + 7, hairC())
            |> dot(16, y + 7, hairC())
            |> dot(19, y + 7, hairC())
            |> hline(13, y + 7, 6, skinDark())
            |> hline(13, y + 8, 6, skinDark())

    // 背面の頭（Up 用）。後頭部の黒髪とバンダナの裏・結び目。
    def headBack(topY: Int32): Canvas =
        let y = topY;
        empty()
            |> hline(12, y, 8, hairC())
            |> hline(11, y + 1, 10, hairC())
            |> hline(11, y + 2, 10, bandana())    // バンダナの裏
            |> dot(21, y + 2, bandana())          // 結び目
            |> dot(22, y + 3, bandana())          // 垂れた端
            |> hline(11, y + 3, 10, hairC())      // 後頭部の黒髪
            |> hline(11, y + 4, 10, hairC())
            |> hline(12, y + 5, 8, hairC())
            |> hline(13, y + 6, 6, hairC())
            |> hline(13, y + 7, 6, hairC())

    // 横向きの頭（左向き・Side 用）。顔は左（x 小）へ・後頭部にバンダナ結び目。
    def headSide(topY: Int32): Canvas =
        let y = topY;
        empty()
            |> hline(12, y, 7, hairC())            // 頭頂の黒髪
            |> hline(11, y + 1, 8, hairC())
            |> hline(11, y + 2, 8, bandana())      // バンダナ
            |> dot(19, y + 2, bandana())           // 後ろの結び目
            |> dot(20, y + 3, bandana())           // 垂れ
            |> hline(11, y + 3, 8, hairC())        // 後頭部
            // 顔（左側・鼻が左へ出る）
            |> hline(11, y + 4, 6, skinC())
            |> dot(10, y + 4, skinC())             // 鼻先
            |> dot(12, y + 4, hairC())             // 眉/目
            |> hline(11, y + 5, 6, skinC())
            |> dot(10, y + 5, skinDark())          // 鼻下
            // 無精髭（顎ライン）
            |> dot(11, y + 6, hairC())
            |> dot(13, y + 6, hairC())
            |> dot(15, y + 6, hairC())
            |> hline(11, y + 6, 6, skinDark())
            |> hline(12, y + 7, 5, skinDark())

    // ══════════════════════════════════════════════════════════
    //  背中の武器（剣+斧の×字・待機/歩行で常時見える）
    // ══════════════════════════════════════════════════════════

    // 正面・背面から見た背中の×字（肩の後ろから両側へ柄が突き出す）。
    // dx=胴の左右揺れに追従。
    def backWeapons(dx: Int32): Canvas =
        empty()
            // 剣の柄（右肩上へ突き出す・鋼＋革巻き）
            |> line(20 + dx, 12, 23 + dx, 8, steelDark())
            |> line(21 + dx, 12, 24 + dx, 8, steel())      // 刃のハイライト
            |> dot(24 + dx, 7, steel())                    // 剣先
            |> hline(22 + dx, 9, 2, leather())             // 柄頭の革
            // 斧の柄（左肩上へ・木＋鋼の刃）
            |> line(11 + dx, 12, 8 + dx, 8, leatherLit())
            |> line(12 + dx, 12, 9 + dx, 8, leather())     // 柄の陰
            |> vline(7 + dx, 7, 3, steelDark())            // 斧頭
            |> dot(7 + dx, 7, steel())                     // 斧刃の光
            |> dot(6 + dx, 8, steel())

    // 横向き（左向き）で背中に×字を背負う。背中は右側（x 大）。
    def backWeaponsSide(dx: Int32): Canvas =
        empty()
            // 剣（背中の上方へ）
            |> line(19 + dx, 11, 22 + dx, 6, steelDark())
            |> line(20 + dx, 11, 23 + dx, 6, steel())
            |> dot(23 + dx, 5, steel())
            // 斧（背中の下方へ交差）
            |> line(19 + dx, 13, 22 + dx, 17, leather())
            |> vline(22 + dx, 16, 3, steelDark())
            |> dot(23 + dx, 16, steel())

    // ══════════════════════════════════════════════════════════
    //  胴体パーツ（革鎧＋片肩の金属肩当て）
    // ══════════════════════════════════════════════════════════

    // 正面の胴（Down/Idle 用）。大柄でどっしり・肩幅広め。
    def torsoFront(topY: Int32): Canvas =
        let y = topY;
        empty()
            // 肩幅の広い革鎧
            |> hline(11, y, 10, leather())
            |> hline(10, y + 1, 12, leather())
            |> hline(10, y + 2, 12, leather())
            |> hline(10, y + 3, 12, leatherLit())      // 胸のハイライト帯
            |> hline(10, y + 4, 12, leather())
            |> hline(11, y + 5, 10, leather())
            // 金属の肩当て（右肩=x 大側だけ）
            |> hline(19, y, 3, steel())
            |> hline(20, y + 1, 2, steelDark())
            // ベルト（革の締め）
            |> hline(11, y + 6, 10, darkLeather())
            |> hline(11, y + 7, 10, leather())

    def darkLeather(): Color = RoguePalette.plum()   // ベルト/深い影

    // 横向き（左向き）の胴。背中は右側。
    def torsoSide(topY: Int32): Canvas =
        let y = topY;
        empty()
            |> hline(12, y, 7, leather())
            |> hline(11, y + 1, 8, leather())
            |> hline(11, y + 2, 8, leatherLit())
            |> hline(11, y + 3, 8, leather())
            |> hline(11, y + 4, 8, leather())
            |> hline(12, y + 5, 7, leather())
            // 肩当て（前肩）
            |> hline(11, y, 3, steel())
            |> dot(11, y + 1, steelDark())
            // ベルト
            |> hline(11, y + 6, 8, darkLeather())
            |> hline(12, y + 7, 6, leather())

    // 脚（両脚・step で歩幅を付ける）。正面/背面共通の下半身。
    // lx/rx = 左右の足の x 位置オフセット。footY=足底（通常 29）。
    def legsFront(footY: Int32, lx: Int32, rx: Int32): Canvas =
        empty()
            // 左脚
            |> vline(12 + lx, footY - 4, 4, leather())
            |> vline(13 + lx, footY - 4, 4, leatherLit())
            |> hline(11 + lx, footY, 3, hairC())        // ブーツ
            // 右脚
            |> vline(18 + rx, footY - 4, 4, leather())
            |> vline(19 + rx, footY - 4, 4, leatherLit())
            |> hline(17 + rx, footY, 3, hairC())        // ブーツ

    // 横向きの脚（前脚 fx・後脚 bx）。
    def legsSide(footY: Int32, fx: Int32, bx: Int32): Canvas =
        empty()
            // 後脚（奥・暗め）
            |> vline(15 + bx, footY - 4, 4, darkLeather())
            |> hline(14 + bx, footY, 3, hairC())
            // 前脚（手前）
            |> vline(13 + fx, footY - 4, 4, leather())
            |> vline(14 + fx, footY - 4, 4, leatherLit())
            |> hline(12 + fx, footY, 3, hairC())

    // ══════════════════════════════════════════════════════════
    //  腕パーツ（肩から手まで 2px・胴から独立して読める）
    // ══════════════════════════════════════════════════════════

    // 正面の腕（左右）。手の位置を (hx,hy) で指定して肩から線を引く。
    def armFront(shoulderX: Int32, shoulderY: Int32, handX: Int32, handY: Int32): Canvas =
        empty()
            |> line(shoulderX, shoulderY, handX, handY, leather())
            |> line(shoulderX + 1, shoulderY, handX + 1, handY, leatherLit())
            |> dot(handX, handY, skinC())              // 手
            |> dot(handX + 1, handY, skinDark())

    // ══════════════════════════════════════════════════════════
    //  Idle Down（呼吸・4 コマ）
    // ══════════════════════════════════════════════════════════
    def idleDown(n: Int32): Canvas =
        let bob = if (n == 1 or n == 3) 1 else 0;   // 肩で息をする上下
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsFront(29, 0, 0))
            |> overlay(backWeapons(0))
            |> overlay(torsoFront(topY + 6))
            |> overlay(armFront(11, topY + 7, 10, topY + 12))  // 左腕
            |> overlay(armFront(20, topY + 7, 21, topY + 12))  // 右腕
            |> overlay(headFront(topY))

    // ── Idle Up（背面・4 コマ）──
    def idleUp(n: Int32): Canvas =
        let bob = if (n == 1 or n == 3) 1 else 0;
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsFront(29, 0, 0))
            |> overlay(backWeapons(0))
            |> overlay(torsoFront(topY + 6))
            |> overlay(armFront(11, topY + 7, 10, topY + 12))
            |> overlay(armFront(20, topY + 7, 21, topY + 12))
            |> overlay(headBack(topY))

    // ── Idle Side（左向き・4 コマ）──
    def idleSide(n: Int32): Canvas =
        let bob = if (n == 1 or n == 3) 1 else 0;
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsSide(29, 0, 0))
            |> overlay(backWeaponsSide(0))
            |> overlay(torsoSide(topY + 6))
            |> overlay(armFront(12, topY + 7, 11, topY + 12))  // 前腕
            |> overlay(headSide(topY))

    // ══════════════════════════════════════════════════════════
    //  Walk Down（のしのし・肩を揺らす・4 コマ）
    // ══════════════════════════════════════════════════════════
    def walkDown(n: Int32): Canvas =
        // 歩幅と体の上下・左右の揺れ（肩を振る大柄な歩き）
        let (lx, rx, bob, sway) = match n {
            case 0 => (-2,  2, 1, -1)   // 左足前・右へ傾く
            case 1 => ( 0,  0, 0,  0)   // 通過
            case 2 => ( 2, -2, 1,  1)   // 右足前・左へ傾く
            case _ => ( 0,  0, 0,  0)
        };
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsFront(29, lx, rx))
            |> overlay(backWeapons(sway))
            |> overlay(torsoFront(topY + 6))
            // 腕は脚と逆に振る
            |> overlay(armFront(11 + sway, topY + 7, 9 + sway + rx, topY + 12))
            |> overlay(armFront(20 + sway, topY + 7, 22 + sway + lx, topY + 12))
            |> overlay(headFront(topY))

    // ── Walk Up（背面・4 コマ）──
    def walkUp(n: Int32): Canvas =
        let (lx, rx, bob, sway) = match n {
            case 0 => (-2,  2, 1, -1)
            case 1 => ( 0,  0, 0,  0)
            case 2 => ( 2, -2, 1,  1)
            case _ => ( 0,  0, 0,  0)
        };
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsFront(29, lx, rx))
            |> overlay(backWeapons(sway))
            |> overlay(torsoFront(topY + 6))
            |> overlay(armFront(11 + sway, topY + 7, 9 + sway + rx, topY + 12))
            |> overlay(armFront(20 + sway, topY + 7, 22 + sway + lx, topY + 12))
            |> overlay(headBack(topY))

    // ── Walk Side（左向き・4 コマ・f0 は左右非対称必須）──
    def walkSide(n: Int32): Canvas =
        // 前脚 fx・後脚 bx・体の上下 bob・腕の手 hx
        let (fx, bx, bob, hx) = match n {
            case 0 => (-3,  3, 0, -2)   // 大股（前脚を前・後脚を後ろ・非対称）
            case 1 => (-1,  1, 1, -1)   // 引き付け・体持ち上がる
            case 2 => ( 3, -3, 0,  2)   // 逆の大股
            case _ => ( 1, -1, 1,  1)   // 引き付け
        };
        let topY = 4 + bob;
        groundShadow()
            |> overlay(legsSide(29, fx, bx))
            |> overlay(backWeaponsSide(0))
            |> overlay(torsoSide(topY + 6))
            |> overlay(armFront(12, topY + 7, 11 + hx, topY + 12))  // 腕を前後に振る
            |> overlay(headSide(topY))

    // ══════════════════════════════════════════════════════════
    //  Attack — 剣の横薙ぎ（大きな弧・6 コマ）
    //  構え(0-1) → 振り抜き(2-3・軌跡) → 戻し(4-5)
    // ══════════════════════════════════════════════════════════

    // Down: 手前へ振り下ろす横薙ぎ。剣が右上から左下へ弧を描く。
    def attackDown(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsFront(29, -1, 1))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(headFront(4));
        match n {
            case 0 =>  // 振りかぶり（剣を右上へ）
                base
                    |> overlay(armFront(20, 11, 24, 6))
                    |> overlay(swordDown(24, 6, 27, 3))
            case 1 =>  // ため
                base
                    |> overlay(armFront(20, 11, 25, 8))
                    |> overlay(swordDown(25, 8, 28, 6))
            case 2 =>  // 振り抜き開始（軌跡）
                base
                    |> overlay(swingArc(15, 16, 11, 350, 30))
                    |> overlay(armFront(20, 11, 22, 14))
                    |> overlay(swordDown(22, 14, 27, 18))
            case 3 =>  // 振り切り（大きな弧の軌跡）
                base
                    |> overlay(swingArc(15, 16, 12, 300, 20))
                    |> overlay(armFront(19, 11, 12, 18))
                    |> overlay(swordDown(12, 18, 6, 22))
            case 4 =>  // 戻し
                base
                    |> overlay(armFront(11, 11, 8, 16))
                    |> overlay(swordDown(8, 16, 5, 12))
            case _ =>  // 構えに戻る
                base
                    |> overlay(armFront(11, 11, 9, 14))
                    |> overlay(swordDown(9, 14, 6, 11))
        }

    // Up: 奥へ薙ぐ横薙ぎ。剣が左上から右上へ。
    def attackUp(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsFront(29, 1, -1))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(headBack(4));
        match n {
            case 0 =>
                base
                    |> overlay(armFront(11, 11, 7, 7))
                    |> overlay(swordUp(7, 7, 4, 4))
            case 1 =>
                base
                    |> overlay(armFront(11, 11, 6, 9))
                    |> overlay(swordUp(6, 9, 3, 6))
            case 2 =>
                base
                    |> overlay(swingArc(15, 13, 11, 150, 210))
                    |> overlay(armFront(11, 11, 10, 5))
                    |> overlay(swordUp(10, 5, 15, 2))
            case 3 =>
                base
                    |> overlay(swingArc(15, 13, 12, 340, 40))
                    |> overlay(armFront(20, 11, 24, 6))
                    |> overlay(swordUp(24, 6, 28, 3))
            case 4 =>
                base
                    |> overlay(armFront(20, 11, 24, 10))
                    |> overlay(swordUp(24, 10, 27, 7))
            case _ =>
                base
                    |> overlay(armFront(20, 11, 23, 12))
                    |> overlay(swordUp(23, 12, 26, 9))
        }

    // Side（左向き）: 左へ大きく横薙ぎ。剣が頭上から前方へ弧を切る。
    def attackSide(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsSide(29, -1, 2))
                |> overlay(backWeaponsSide(0))
                |> overlay(torsoSide(10))
                |> overlay(headSide(4));
        match n {
            case 0 =>  // 頭上に振りかぶる
                base
                    |> overlay(armFront(16, 11, 20, 5))
                    |> overlay(swordUp(20, 5, 24, 2))
            case 1 =>  // ため（さらに後ろへ）
                base
                    |> overlay(armFront(16, 11, 22, 6))
                    |> overlay(swordUp(22, 6, 26, 4))
            case 2 =>  // 振り出し（軌跡・前方=左へ）
                base
                    |> overlay(swingArc(14, 12, 12, 40, 140))
                    |> overlay(armFront(15, 11, 14, 5))
                    |> overlay(swordUp(14, 5, 10, 3))
            case 3 =>  // 振り抜き（前方へ大弧）
                base
                    |> overlay(swingArc(13, 14, 13, 90, 190))
                    |> overlay(armFront(14, 12, 6, 12))
                    |> overlay(swordUp(6, 12, 2, 15))
            case 4 =>  // 振り切り下段
                base
                    |> overlay(swingArc(13, 15, 12, 140, 200))
                    |> overlay(armFront(13, 13, 7, 18))
                    |> overlay(swordUp(7, 18, 3, 21))
            case _ =>  // 戻し
                base
                    |> overlay(armFront(13, 12, 9, 16))
                    |> overlay(swordUp(9, 16, 6, 18))
        }

    // 剣（Down 用・柄から刃先へ線 2px＋刃のハイライト）。
    def swordDown(x0: Int32, y0: Int32, x1: Int32, y1: Int32): Canvas =
        empty()
            |> line(x0, y0, x1, y1, steelDark())
            |> line(x0, y0 - 1, x1, y1 - 1, steel())
            |> dot(x1, y1, steel())
            |> dot(x0, y0, leather())          // 柄

    // 剣（Up/Side 用・同じ形）。
    def swordUp(x0: Int32, y0: Int32, x1: Int32, y1: Int32): Canvas =
        empty()
            |> line(x0, y0, x1, y1, steelDark())
            |> line(x0 + 1, y0, x1 + 1, y1, steel())
            |> dot(x1, y1, steel())
            |> dot(x0, y0, leather())

    // 斬撃軌跡（明色の連続弧・2px 幅）。
    def swingArc(cx: Int32, cy: Int32, r: Int32, a0: Int32, a1: Int32): Canvas =
        empty()
            |> arc(cx, cy, r, a0, a1, trail())
            |> arc(cx, cy, r - 1, a0, a1, trail())

    // ══════════════════════════════════════════════════════════
    //  UseItem — 掲げる → 明色フラッシュ → 使う（3 拍・4 コマ）
    // ══════════════════════════════════════════════════════════

    // 小瓶（ポーション）を持つ手。
    def potion(x: Int32, y: Int32, lit: Bool): Canvas =
        let glass = if (lit) trail() else RoguePalette.cyan();
        empty()
            |> dot(x, y - 1, steelDark())      // 栓
            |> vline(x, y, 2, glass)           // 瓶
            |> dot(x, y + 2, steelDark())

    def useItemDown(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsFront(29, 0, 0))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(headFront(4));
        match n {
            case 0 =>  // 手に取る（胸元）
                base |> overlay(armFront(20, 11, 21, 14)) |> overlay(potion(21, 12, false))
            case 1 =>  // 掲げる
                base |> overlay(armFront(20, 11, 23, 5)) |> overlay(potion(23, 3, false))
            case 2 =>  // 明色フラッシュ
                base
                    |> overlay(flashDisc(23, 3))
                    |> overlay(armFront(20, 11, 23, 5))
                    |> overlay(potion(23, 3, true))
            case _ =>  // 飲む（口元へ）
                base |> overlay(armFront(20, 11, 17, 11)) |> overlay(potion(17, 10, false))
        }

    // 掲げたアイテムの明色フラッシュ（独立レイヤー）。
    def flashDisc(x: Int32, y: Int32): Canvas =
        discFill(x, y, 3, trail(), empty())

    def useItemUp(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsFront(29, 0, 0))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(headBack(4));
        match n {
            case 0 =>
                base |> overlay(armFront(20, 11, 21, 14)) |> overlay(potion(21, 12, false))
            case 1 =>
                base |> overlay(armFront(20, 11, 23, 5)) |> overlay(potion(23, 3, false))
            case 2 =>
                base
                    |> overlay(flashDisc(23, 3))
                    |> overlay(armFront(20, 11, 23, 5))
                    |> overlay(potion(23, 3, true))
            case _ =>
                base |> overlay(armFront(20, 11, 22, 10)) |> overlay(potion(22, 9, false))
        }

    def useItemSide(n: Int32): Canvas =
        let base =
            groundShadow()
                |> overlay(legsSide(29, 0, 0))
                |> overlay(backWeaponsSide(0))
                |> overlay(torsoSide(10))
                |> overlay(headSide(4));
        match n {
            case 0 =>
                base |> overlay(armFront(14, 11, 13, 14)) |> overlay(potion(13, 12, false))
            case 1 =>
                base |> overlay(armFront(14, 11, 15, 5)) |> overlay(potion(15, 3, false))
            case 2 =>
                base
                    |> overlay(flashDisc(15, 3))
                    |> overlay(armFront(14, 11, 15, 5))
                    |> overlay(potion(15, 3, true))
            case _ =>  // 口元（左）へ
                base |> overlay(armFront(14, 11, 11, 11)) |> overlay(potion(11, 10, false))
        }

    // ══════════════════════════════════════════════════════════
    //  Damage — f0 全身白フラッシュ + ノックバック → のけぞり（3 コマ）
    // ══════════════════════════════════════════════════════════

    // シルエットを白で塗る（フラッシュ用）。base を白一色に。
    def whiteFlash(base: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> Map.insert(k, RoguePalette.white(), acc),
            Map.empty(), base)

    def damageDown(n: Int32): Canvas =
        // Down=手前(下)へノックバック
        let body =
            legsFront(29, 0, 0)
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(armFront(11, 11, 8, 15))
                |> overlay(armFront(20, 11, 23, 15))
                |> overlay(headFront(4));
        match n {
            case 0 => groundShadow() |> overlay(shift(0, 2, whiteFlash(body)))   // 白+手前へ
            case 1 => groundShadow() |> overlay(shift(0, 1, body))               // のけぞり残り
            case _ => groundShadow() |> overlay(body)
        }

    def damageUp(n: Int32): Canvas =
        // Up=奥(上)へノックバック
        let body =
            legsFront(29, 0, 0)
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(10))
                |> overlay(armFront(11, 11, 8, 15))
                |> overlay(armFront(20, 11, 23, 15))
                |> overlay(headBack(4));
        match n {
            case 0 => groundShadow() |> overlay(shift(0, -2, whiteFlash(body)))
            case 1 => groundShadow() |> overlay(shift(0, -1, body))
            case _ => groundShadow() |> overlay(body)
        }

    def damageSide(n: Int32): Canvas =
        // Side(左向き)=横(右=後方)へノックバック
        let body =
            legsSide(29, 0, 0)
                |> overlay(backWeaponsSide(0))
                |> overlay(torsoSide(10))
                |> overlay(armFront(14, 11, 11, 15))
                |> overlay(headSide(4));
        match n {
            case 0 => groundShadow() |> overlay(shift(3, 0, whiteFlash(body)))   // 白+後方へ
            case 1 => groundShadow() |> overlay(shift(2, 0, body))
            case _ => groundShadow() |> overlay(body)
        }

    // ══════════════════════════════════════════════════════════
    //  Death — 膝どまり・正面（6 コマ）
    //  よろめき(0-1) → 膝から崩れ(2-3) → 膝立ち前傾がくり(4-5)
    //  剣を取り落とす。倒れ伏さない。
    // ══════════════════════════════════════════════════════════
    def death(n: Int32): Canvas = match n {
        case 0 =>  // よろめき（のけぞる・上体後傾）
            groundShadow()
                |> overlay(legsFront(29, -1, 1))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(9))
                |> overlay(armFront(11, 10, 7, 6))     // 腕が跳ねる
                |> overlay(armFront(20, 10, 24, 6))
                |> overlay(headFront(3))
        case 1 =>  // よろめき戻り（前へ傾き始め）
            groundShadow()
                |> overlay(legsFront(29, -1, 1))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(11))
                |> overlay(armFront(11, 12, 8, 17))
                |> overlay(armFront(20, 12, 23, 17))
                |> overlay(headFront(5))
        case 2 =>  // 膝から崩れ（片膝を落とす・全体沈む）
            groundShadow()
                |> overlay(kneelLegs(1))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(14))
                |> overlay(armFront(11, 15, 9, 20))
                |> overlay(armFront(20, 15, 22, 22))   // 剣を落とし始める手
                |> overlay(fallingSword(24, 20))
                |> overlay(headFront(8))
        case 3 =>  // 両膝つく（さらに沈む）
            groundShadow()
                |> overlay(kneelLegs(2))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(15))
                |> overlay(armFront(11, 16, 8, 22))
                |> overlay(armFront(20, 16, 22, 22))
                |> overlay(fallingSword(25, 26))       // 剣が地に転がる
                |> overlay(headFront(9))
        case 4 =>  // 膝立ちのまま前傾（首うなだれ）
            groundShadow()
                |> overlay(kneelLegs(2))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(16))
                |> overlay(armFront(11, 17, 10, 24))
                |> overlay(armFront(20, 17, 21, 24))
                |> overlay(droopHead(11))
        case _ =>  // 前傾がくり（最終・膝立ちの立面が読める）
            groundShadow()
                |> overlay(kneelLegs(2))
                |> overlay(backWeapons(0))
                |> overlay(torsoFront(17))
                |> overlay(armFront(11, 18, 11, 25))
                |> overlay(armFront(20, 18, 20, 25))
                |> overlay(droopHead(12))
    }

    // 膝立ちの脚（depth=1 片膝・2 両膝）。足底は 29 のまま座り込む。
    def kneelLegs(depth: Int32): Canvas =
        if (depth <= 1)
            empty()
                |> vline(13, 24, 5, leather())          // 立てた脚（膝を折る）
                |> vline(14, 24, 5, leatherLit())
                |> hline(12, 29, 4, hairC())            // 足
                |> hline(17, 27, 4, leather())          // 落とした膝（横倒し）
                |> hline(17, 28, 4, hairC())
        else
            empty()
                |> hline(12, 26, 4, leather())          // 両膝を折り畳む
                |> hline(12, 27, 4, leatherLit())
                |> hline(12, 28, 5, hairC())            // 折った脛
                |> hline(17, 26, 4, leather())
                |> hline(17, 27, 4, leatherLit())
                |> hline(16, 28, 5, hairC())
                |> hline(12, 29, 9, shadowC())          // 座り込む接地

    // うなだれた頭（前傾・顔が下を向く）。
    def droopHead(topY: Int32): Canvas =
        let y = topY;
        empty()
            |> hline(12, y, 8, hairC())
            |> hline(11, y + 1, 10, hairC())
            |> hline(11, y + 2, 10, bandana())
            |> dot(21, y + 2, bandana())
            |> hline(12, y + 3, 8, hairC())            // うつむいて後頭部が見える
            |> hline(13, y + 4, 6, skinDark())         // かげる顔

    // 取り落とした剣（落下中/転がる）。
    def fallingSword(x: Int32, y: Int32): Canvas =
        empty()
            |> line(x, y, x + 4, y + 3, steelDark())
            |> line(x, y - 1, x + 4, y + 2, steel())
            |> dot(x, y, leather())
}
