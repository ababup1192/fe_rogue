// RangerC — 遊牧の騎射手。頭にターバン（前に赤い宝石飾り）、浅黒い肌、短い複合弓。
// 弓は常に見え、攻撃は「引く→放つ→もう一度引く→放つ」の速射二連。
// 死は膝どまり（砂に還るように弓を落とし前傾がくり）。倒れ伏さない。
//
// アンカー: 足元 y=29・中心 x=15..16・身長 ≤28px。色は RoguePalette のみ。
// Side 系は左向きで作画（右向きは実行時 hflip）。
//
// 縦の骨格（Down 正面・呼吸 dy=0 のとき）:
//   ターバン y=4..9 / 顔 y=8..11 / 胴 y=12..16 / 腰布 y=17..20 / 脚 y=21..29(接地)

mod RangerC {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, arc, overlay, shift}

    pub def name(): String = "RANGER C 遊牧の騎射手"

    // ── 色 ──
    def skinC(): Color = RoguePalette.tan()          // 浅黒い肌
    def skinShade(): Color = RoguePalette.brown()    // 肌の影
    def turbanC(): Color = RoguePalette.royalBlue()  // ターバン本体
    def turbanShade(): Color = RoguePalette.navy()   // ターバンの影
    def gemC(): Color = RoguePalette.red()           // 前の宝石飾り（差し色）
    def sashC(): Color = RoguePalette.mustard()      // 腰布
    def sashHi(): Color = RoguePalette.orange()      // 腰布のハイライト
    def bowC(): Color = RoguePalette.brown()         // 弓本体
    def bowHi(): Color = RoguePalette.tan()          // 弓のハイライト
    def arrowC(): Color = RoguePalette.yellow()      // 矢（明色の直線）
    def braceC(): Color = RoguePalette.yellow()      // 腕輪
    def flashC(): Color = RoguePalette.white()       // 被弾フラッシュ

    // frame を [0, n) に丸める（負数補正つき）。
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    pub def draw(clip: RogueStage.Clip, frame: Int32): Canvas =
        let n = RogueStage.frameCount(clip);
        let f = wrap(frame, n);
        match clip {
            case RogueStage.Clip.IdleDown    => idleDown(f)
            case RogueStage.Clip.IdleUp      => idleUp(f)
            case RogueStage.Clip.IdleSide    => idleSide(f)
            case RogueStage.Clip.WalkDown    => walkDown(f)
            case RogueStage.Clip.WalkUp      => walkUp(f)
            case RogueStage.Clip.WalkSide    => walkSide(f)
            case RogueStage.Clip.AttackDown  => attackDown(f)
            case RogueStage.Clip.AttackUp    => attackUp(f)
            case RogueStage.Clip.AttackSide  => attackSide(f)
            case RogueStage.Clip.UseItemDown => useItemDown(f)
            case RogueStage.Clip.UseItemUp   => useItemUp(f)
            case RogueStage.Clip.UseItemSide => useItemSide(f)
            case RogueStage.Clip.DamageDown  => damageDown(f)
            case RogueStage.Clip.DamageUp    => damageUp(f)
            case RogueStage.Clip.DamageSide  => damageSide(f)
            case RogueStage.Clip.Death       => death(f)
        }

    // ════════════════════════════════════════════════════════════
    // 頭部（個性）: ターバン。前面=正面顔、背面=後頭部の巻き、
    // 側面=横顔＋前に宝石。全方向で同じ布の巻きと宝石を見せる。
    // 顔の中心 x=15。dy で上下呼吸をつける。
    // ════════════════════════════════════════════════════════════

    // 正面のターバン頭（Down 用）。
    def headDown(dy: Int32): Canvas =
        empty()
            // ターバンの巻き（頭頂〜側頭）
            |> hline(12, 4 + dy, 8, turbanC())
            |> hline(11, 5 + dy, 10, turbanC())
            |> hline(11, 6 + dy, 10, turbanC())
            |> (cv -> dot(11, 7 + dy, turbanShade(), cv))
            |> (cv -> dot(20, 7 + dy, turbanShade(), cv))
            // 巻きの段差（布が重なった線）
            |> hline(12, 7 + dy, 8, turbanShade())
            // 前の宝石飾り（額の中央）
            |> (cv -> dot(15, 5 + dy, gemC(), cv))
            |> (cv -> dot(16, 5 + dy, gemC(), cv))
            // 顔（浅黒い肌）
            |> hline(12, 8 + dy, 8, skinC())
            |> hline(12, 9 + dy, 8, skinC())
            |> hline(12, 10 + dy, 8, skinC())
            // 鋭い目（左右）
            |> (cv -> dot(13, 9 + dy, skinShade(), cv))
            |> (cv -> dot(18, 9 + dy, skinShade(), cv))
            // 顎の影
            |> (cv -> dot(13, 10 + dy, skinShade(), cv))
            |> (cv -> dot(18, 10 + dy, skinShade(), cv))

    // 背面のターバン頭（Up 用）。後頭部の布の巻きが見える・顔なし。
    def headUp(dy: Int32): Canvas =
        empty()
            |> hline(12, 4 + dy, 8, turbanC())
            |> hline(11, 5 + dy, 10, turbanC())
            |> hline(11, 6 + dy, 10, turbanC())
            |> hline(11, 7 + dy, 10, turbanShade())     // 巻きの裏の段
            // 後頭部（首元だけ肌がのぞく）
            |> hline(12, 8 + dy, 8, turbanC())
            |> hline(13, 9 + dy, 6, turbanShade())      // うなじの布
            |> hline(14, 10 + dy, 4, skinShade())       // 首

    // 側面（左向き）のターバン頭（Side 用）。横顔＋前（左）に宝石。
    def headSide(dy: Int32): Canvas =
        empty()
            |> hline(12, 4 + dy, 7, turbanC())
            |> hline(11, 5 + dy, 8, turbanC())
            |> hline(11, 6 + dy, 8, turbanC())
            |> hline(12, 7 + dy, 7, turbanShade())      // 巻きの段
            // 前（左）に垂れる宝石飾り
            |> (cv -> dot(11, 6 + dy, gemC(), cv))
            // 横顔（左が前）
            |> hline(11, 8 + dy, 7, skinC())
            |> hline(11, 9 + dy, 7, skinC())
            |> hline(12, 10 + dy, 6, skinC())
            |> (cv -> dot(12, 9 + dy, skinShade(), cv)) // 目
            |> (cv -> dot(11, 10 + dy, skinShade(), cv))// 顎先の影

    // ════════════════════════════════════════════════════════════
    // 胴・脚の基礎パーツ（軽装＋腰布）。dy で全身の上下呼吸。
    // ════════════════════════════════════════════════════════════

    // 正面の胴（Down/Up 共通の軽装トルソ）。y=12..20。
    def torsoDown(dy: Int32): Canvas =
        empty()
            // 素肌の上半身（軽装）
            |> hline(13, 12 + dy, 6, skinC())
            |> hline(12, 13 + dy, 8, skinC())
            |> hline(12, 14 + dy, 8, skinC())
            |> (cv -> dot(12, 14 + dy, skinShade(), cv))  // 脇の影
            |> (cv -> dot(19, 14 + dy, skinShade(), cv))
            // 腰布（mustard）
            |> hline(12, 16 + dy, 8, sashC())
            |> hline(12, 17 + dy, 8, sashC())
            |> hline(13, 18 + dy, 6, sashC())
            |> hline(13, 16 + dy, 2, sashHi())            // 腰布のハイライト
            |> (cv -> dot(15, 18 + dy, sashHi(), cv))

    // 正面の両脚（腰布の下 y=19 から足元 y=29 まで）。offL/offR は左右足の x 微調整。
    def legsDown(dy: Int32, offL: Int32, offR: Int32): Canvas =
        empty()
            // 左脚
            |> vline(13 + offL, 19 + dy, 10 - dy, skinC())
            |> (cv -> dot(13 + offL, 29, skinShade(), cv))   // 足先（接地）
            |> (cv -> dot(14 + offL, 29, skinShade(), cv))
            // 右脚
            |> vline(18 + offR, 19 + dy, 10 - dy, skinC())
            |> (cv -> dot(17 + offR, 29, skinShade(), cv))   // 足先（接地）
            |> (cv -> dot(18 + offR, 29, skinShade(), cv))

    // ════════════════════════════════════════════════════════════
    // 弓（リカーブボウ）。常に見える。arc で反り返った弧を描き、
    // 弦（string）を直線で張る。基本は体の左手側に構える。
    // ════════════════════════════════════════════════════════════

    // 縦に構えた弓（Down/Up の正面ポーズ用）。体の左脇に立てる。
    // by = 弓の握りの上端。上下リムが反り返り、弦がまっすぐ縦に張る。
    def bowVertical(bx: Int32, by: Int32): Canvas =
        empty()
            // 上のリム（反り返る弧・上向き）
            |> arc(bx + 3, by + 2, 4, 60, 170, bowC())
            // 下のリム（下向き）
            |> arc(bx + 3, by + 10, 4, 190, 300, bowC())
            // 握り（グリップ）
            |> vline(bx, by + 4, 4, bowHi())
            // 弦（まっすぐ縦）
            |> vline(bx + 1, by - 2, 16, bowHi())

    // 横に構えた弓（歩き・待機の Side 用。左向きに突き出す）。
    def bowHorizontalSide(bx: Int32, by: Int32): Canvas =
        empty()
            |> arc(bx + 3, by + 3, 4, 100, 210, bowC())   // 左のリム
            |> arc(bx + 11, by + 3, 4, 0 - 30, 80, bowC())// 右のリム
            |> hline(bx, by, 12, bowHi())                  // グリップ帯
            |> hline(bx, by + 2, 12, bowHi())              // 弦

    // ════════════════════════════════════════════════════════════
    // Idle（呼吸）: 肩で息をする軽やかな佇み。弓は縦／横に構え。
    // ════════════════════════════════════════════════════════════

    def breathDy(f: Int32): Int32 = match f {
        case 0 => 0
        case 1 => 0
        case 2 => 1   // 息を吸って肩が下がる（体が 1px 沈む・足は接地のまま）
        case _ => 0
    }

    def idleDown(f: Int32): Canvas =
        let dy = breathDy(f);
        legsDown(dy, 0, 0)
            |> overlay(torsoDown(dy))
            |> overlay(armDown(dy, f))
            |> overlay(headDown(dy))
            |> overlay(bowVertical(9, 8 + dy))

    // 正面の腕（弓を持つ左手＋添える右手）。肩から手まで2px幅。
    def armDown(dy: Int32, f: Int32): Canvas =
        let swing = if (f == 2) 1 else 0;
        empty()
            // 左腕（弓側・下へ伸ばす）
            |> vline(11, 13 + dy, 4, skinC())
            |> (cv -> dot(10, 13 + dy, skinShade(), cv))
            |> (cv -> dot(10, 14 + dy + swing, braceC(), cv)) // 腕輪
            // 右腕
            |> vline(20, 13 + dy, 4, skinC())
            |> (cv -> dot(21, 14 + dy + swing, braceC(), cv)) // 腕輪

    def idleUp(f: Int32): Canvas =
        let dy = breathDy(f);
        legsDown(dy, 0, 0)
            |> overlay(torsoDown(dy))
            |> overlay(armUp(dy))
            |> overlay(headUp(dy))
            |> overlay(bowVertical(9, 8 + dy))

    // 背面の腕（背中側から弓を持つ）。
    def armUp(dy: Int32): Canvas =
        empty()
            |> vline(11, 13 + dy, 4, turbanShade())   // 背に回した左腕（衣に隠れ気味）
            |> vline(20, 13 + dy, 4, skinC())
            |> (cv -> dot(21, 15 + dy, braceC(), cv))

    def idleSide(f: Int32): Canvas =
        let dy = breathDy(f);
        legsSide(dy, 0, 0)
            |> overlay(torsoSide(dy))
            |> overlay(armSide(dy, 0))
            |> overlay(headSide(dy))
            |> overlay(bowHorizontalSide(6, 13 + dy))

    // 側面（左向き）の胴。y=12..20。
    def torsoSide(dy: Int32): Canvas =
        empty()
            |> hline(13, 12 + dy, 5, skinC())
            |> hline(12, 13 + dy, 6, skinC())
            |> hline(12, 14 + dy, 6, skinC())
            |> (cv -> dot(17, 14 + dy, skinShade(), cv))  // 背側の影
            // 腰布
            |> hline(12, 16 + dy, 6, sashC())
            |> hline(12, 17 + dy, 6, sashC())
            |> hline(13, 18 + dy, 4, sashC())
            |> (cv -> dot(13, 16 + dy, sashHi(), cv))

    // 側面の脚（左向き・前脚が左）。y=19 から足元 y=29 まで。
    def legsSide(dy: Int32, offFront: Int32, offBack: Int32): Canvas =
        empty()
            // 後脚（右寄り・影色）
            |> vline(16 + offBack, 19 + dy, 10 - dy, skinShade())
            |> (cv -> dot(16 + offBack, 29, skinShade(), cv))
            |> (cv -> dot(17 + offBack, 29, skinShade(), cv))
            // 前脚（左寄り）
            |> vline(13 + offFront, 19 + dy, 10 - dy, skinC())
            |> (cv -> dot(12 + offFront, 29, skinShade(), cv))
            |> (cv -> dot(13 + offFront, 29, skinShade(), cv))

    // 側面の腕（弓を前へ突き出す左腕）。extend で前方に伸ばす量。
    def armSide(dy: Int32, extend: Int32): Canvas =
        empty()
            |> hline(9 - extend, 13 + dy, 4, skinC())     // 前へ伸ばす腕
            |> (cv -> dot(9 - extend, 14 + dy, braceC(), cv)) // 腕輪
            |> vline(15, 13 + dy, 3, skinC())             // 弦を引く後ろ手

    // ════════════════════════════════════════════════════════════
    // Walk（軽快でリズミカル・弾む）: 歩幅2〜3px + 体の上下1px。
    // 足は接地(y=29)を保つ。4コマ全部違う絵。
    // ════════════════════════════════════════════════════════════

    // 弾む上下: f1,f3 で上体が 1px 弾む（足は接地のまま脚が縮む）。
    def bounceDy(f: Int32): Int32 = match f {
        case 0 => 0
        case 1 => 0 - 1
        case 2 => 0
        case _ => 0 - 1
    }

    // 歩きの脚オフセット（前後の踏み出し）。
    def walkLegOff(f: Int32): (Int32, Int32) = match f {
        case 0 => (0 - 2, 2)    // 左足前・右足後
        case 1 => (0, 0)        // 交差
        case 2 => (2, 0 - 2)    // 右足前・左足後
        case _ => (0, 0)
    }

    def walkDown(f: Int32): Canvas =
        let dy = bounceDy(f);
        let (offL, offR) = walkLegOff(f);
        legsDown(dy, offL, offR)
            |> overlay(torsoDown(dy))
            |> overlay(walkArmDown(dy, f))
            |> overlay(headDown(dy))
            |> overlay(bowVertical(9, 8 + dy))

    // 歩きの腕振り（前後）。
    def walkArmDown(dy: Int32, f: Int32): Canvas =
        let swing = match f { case 0 => 1  case 2 => 0 - 1  case _ => 0 };
        empty()
            |> vline(11, 13 + dy, 4, skinC())
            |> (cv -> dot(10, 14 + dy + swing, braceC(), cv))
            |> vline(20, 13 + dy, 4, skinC())
            |> (cv -> dot(21, 14 + dy - swing, braceC(), cv))

    def walkUp(f: Int32): Canvas =
        let dy = bounceDy(f);
        let (offL, offR) = walkLegOff(f);
        legsDown(dy, offL, offR)
            |> overlay(torsoDown(dy))
            |> overlay(walkArmDown(dy, f))
            |> overlay(headUp(dy))
            |> overlay(bowVertical(9, 8 + dy))

    // 側面歩き（左向き）。前後脚が大きく開く。f0 は左右非対称必須。
    def walkSide(f: Int32): Canvas =
        let dy = bounceDy(f);
        let (offF, offB) = match f {
            case 0 => (0 - 2, 3)   // 前脚を前へ・後脚を後ろへ（非対称）
            case 1 => (0, 0)
            case 2 => (2, 0 - 2)
            case _ => (0 - 1, 1)
        };
        let armExt = match f { case 0 => 1  case 2 => 0 - 1  case _ => 0 };
        legsSide(dy, offF, offB)
            |> overlay(torsoSide(dy))
            |> overlay(armSide(dy, armExt))
            |> overlay(headSide(dy))
            |> overlay(bowHorizontalSide(6, 13 + dy))

    // ════════════════════════════════════════════════════════════
    // Attack（速射二連・6コマ）: 引く→放つ→引く→放つ。
    //   f0 引き構え  f1 放つ①(矢1)  f2 次を番える  f3 引き直し
    //   f4 放つ②(矢2)  f5 残心
    // 矢は明色(yellow)の直線2px幅で連続して飛ぶ。方向で狙いを変える。
    // ════════════════════════════════════════════════════════════

    // Down: 手前（下）へ狙う。矢は下方向へ飛ぶ。
    def attackDown(f: Int32): Canvas =
        let base =
            legsDown(0, 0 - 1, 1)               // 踏ん張り足
                |> overlay(torsoDown(0))
                |> overlay(headDown(0));
        let bow = bowVertical(9, 9);
        let arms = match f {
            case 0 => attackDrawArmDown(3)                       // 深く引く
            case 1 => attackDrawArmDown(0) |> overlay(arrowLineDown(15, 20, 8))
            case 2 => attackDrawArmDown(1)                       // 次を番える
            case 3 => attackDrawArmDown(3)                       // 引き直し
            case 4 => attackDrawArmDown(0) |> overlay(arrowLineDown(15, 20, 8))
            case _ => attackDrawArmDown(0)                       // 残心
        };
        base |> overlay(bow) |> overlay(arms)

    // 引き腕（弦を引く右手）。pull が引きの深さ。
    def attackDrawArmDown(pull: Int32): Canvas =
        empty()
            |> vline(11, 12, 5, skinC())                 // 弓を保持する左腕
            |> (cv -> dot(10, 13, braceC(), cv))
            |> hline(15 + pull, 11, 4, skinC())          // 引く右腕（後方へ）
            |> (cv -> dot(15 + pull + 3, 11, braceC(), cv))

    // 下向きに飛ぶ矢（明色2px幅の直線）。
    def arrowLineDown(ax: Int32, ay: Int32, len: Int32): Canvas =
        empty()
            |> vline(ax, ay, len, arrowC())
            |> vline(ax + 1, ay, len, arrowC())
            |> (cv -> dot(ax, ay + len, arrowC(), cv))       // 鏃
            |> (cv -> dot(ax + 1, ay + len, arrowC(), cv))
            |> (cv -> dot(ax - 1, ay, arrowC(), cv))         // 矢羽根
            |> (cv -> dot(ax + 2, ay, arrowC(), cv))

    // Up: 奥（上）へ狙う。矢は上方向へ飛ぶ。背面ポーズ。
    def attackUp(f: Int32): Canvas =
        let base =
            legsDown(0, 0 - 1, 1)
                |> overlay(torsoDown(0))
                |> overlay(headUp(0));
        let bow = bowVertical(9, 5);
        let arms = match f {
            case 0 => attackDrawArmUp(3)
            case 1 => attackDrawArmUp(0) |> overlay(arrowLineUp(15, 12, 8))
            case 2 => attackDrawArmUp(1)
            case 3 => attackDrawArmUp(3)
            case 4 => attackDrawArmUp(0) |> overlay(arrowLineUp(15, 12, 8))
            case _ => attackDrawArmUp(0)
        };
        base |> overlay(bow) |> overlay(arms)

    def attackDrawArmUp(pull: Int32): Canvas =
        empty()
            |> vline(11, 12, 5, turbanShade())
            |> hline(15 + pull, 12, 4, skinC())
            |> (cv -> dot(15 + pull + 3, 12, braceC(), cv))

    // 上向きに飛ぶ矢。
    def arrowLineUp(ax: Int32, ayBottom: Int32, len: Int32): Canvas =
        let ayTop = ayBottom - len;
        empty()
            |> vline(ax, ayTop, len, arrowC())
            |> vline(ax + 1, ayTop, len, arrowC())
            |> (cv -> dot(ax, ayTop, arrowC(), cv))          // 鏃（上）
            |> (cv -> dot(ax + 1, ayTop, arrowC(), cv))
            |> (cv -> dot(ax - 1, ayBottom, arrowC(), cv))   // 矢羽根（下）
            |> (cv -> dot(ax + 2, ayBottom, arrowC(), cv))

    // Side（左向き）: 左へ狙う。矢が左へ飛ぶ。腕と弓が大きく開く見得。
    def attackSide(f: Int32): Canvas =
        let base =
            legsSide(0, 0 - 2, 2)               // 踏ん張り（前後開脚）
                |> overlay(torsoSide(0))
                |> overlay(headSide(0));
        let action = match f {
            case 0 => bowDrawnSide(4) |> overlay(drawArmSide(4))              // 深く引く
            case 1 => bowDrawnSide(0) |> overlay(releaseArmSide())
                          |> overlay(arrowLineSide(2, 14, 9))                 // 矢1発射
            case 2 => bowDrawnSide(2) |> overlay(drawArmSide(2))              // 次を番える
            case 3 => bowDrawnSide(4) |> overlay(drawArmSide(4))              // 引き直し
            case 4 => bowDrawnSide(0) |> overlay(releaseArmSide())
                          |> overlay(arrowLineSide(2, 14, 9))                 // 矢2発射
            case _ => bowDrawnSide(0) |> overlay(restArmSide())              // 残心
        };
        base |> overlay(action)

    // 引き絞った弓（左へ突き出す・pull ぶん弦が奥へ）。大きな弧の見得。
    def bowDrawnSide(pull: Int32): Canvas =
        empty()
            // 前へ突き出す弓（左）。リムが大きく反る。
            |> arc(8, 13, 5, 100, 210, bowC())            // 上リム
            |> arc(8, 13, 5, 150, 260, bowC())            // 下リム（厚み2px）
            |> vline(8, 9, 9, bowHi())                     // 弓の握り帯
            // 弦（引くと V 字に折れる）
            |> line(8, 9, 15 + pull, 13, bowHi())
            |> line(8, 17, 15 + pull, 13, bowHi())

    // 弦を引く後ろ手。
    def drawArmSide(pull: Int32): Canvas =
        empty()
            |> hline(15 + pull, 13, 3, skinC())
            |> (cv -> dot(15 + pull, 14, braceC(), cv))
            |> hline(9, 12, 5, skinC())                    // 弓を保持する前腕
            |> (cv -> dot(9, 13, braceC(), cv))

    // 放った直後の後ろ手（開いて残る）。
    def releaseArmSide(): Canvas =
        empty()
            |> hline(16, 13, 3, skinC())
            |> hline(9, 12, 5, skinC())
            |> (cv -> dot(9, 13, braceC(), cv))

    // 残心の腕（弓を戻す）。
    def restArmSide(): Canvas =
        empty()
            |> hline(9, 13, 4, skinC())
            |> (cv -> dot(9, 14, braceC(), cv))
            |> vline(15, 13, 3, skinC())

    // 左へ飛ぶ矢（明色2px幅の直線）。axLeft（左先端）から右へ len。
    def arrowLineSide(axLeft: Int32, ay: Int32, len: Int32): Canvas =
        empty()
            |> hline(axLeft, ay, len, arrowC())
            |> hline(axLeft, ay + 1, len, arrowC())
            |> (cv -> dot(axLeft, ay, arrowC(), cv))              // 鏃（左先端）
            |> (cv -> dot(axLeft, ay + 1, arrowC(), cv))
            |> (cv -> dot(axLeft + len, ay - 1, arrowC(), cv))    // 矢羽根（右端）
            |> (cv -> dot(axLeft + len, ay + 2, arrowC(), cv))

    // ════════════════════════════════════════════════════════════
    // UseItem（3拍・掲げる→明色フラッシュ→使う）: 水袋を掲げて飲む所作。
    // ════════════════════════════════════════════════════════════

    def useItemDown(f: Int32): Canvas =
        let base =
            legsDown(0, 0, 0)
                |> overlay(torsoDown(0))
                |> overlay(headDown(0))
                |> overlay(bowVertical(9, 8));
        match f {
            case 0 => base |> overlay(raiseArmDown(0))                 // 掲げる
            case 1 => base |> overlay(raiseArmDown(0))
                          |> overlay(flashItemDown())                  // フラッシュ
            case _ => base |> overlay(raiseArmDown(1))                 // 使う（口元へ）
        }

    def raiseArmDown(near: Int32): Canvas =
        empty()
            |> vline(20, 10 + near, 4, skinC())                       // 掲げた右腕
            |> (cv -> dot(19, 9 + near, sashC(), cv))                 // 水袋
            |> (cv -> dot(20, 8 + near, sashHi(), cv))
            |> vline(11, 13, 4, skinC())

    def flashItemDown(): Canvas =
        empty()
            |> (cv -> dot(20, 7, flashC(), cv))
            |> (cv -> dot(19, 8, flashC(), cv))
            |> (cv -> dot(21, 8, flashC(), cv))

    def useItemUp(f: Int32): Canvas =
        let base =
            legsDown(0, 0, 0)
                |> overlay(torsoDown(0))
                |> overlay(headUp(0))
                |> overlay(bowVertical(9, 8));
        match f {
            case 0 => base |> overlay(raiseArmUp(0))
            case 1 => base |> overlay(raiseArmUp(0)) |> overlay(flashItemUp())
            case _ => base |> overlay(raiseArmUp(1))
        }

    def raiseArmUp(near: Int32): Canvas =
        empty()
            |> vline(20, 10 + near, 4, skinC())
            |> (cv -> dot(20, 8 + near, sashC(), cv))
            |> vline(11, 13, 4, turbanShade())

    def flashItemUp(): Canvas =
        empty()
            |> (cv -> dot(20, 7, flashC(), cv))
            |> (cv -> dot(20, 8, flashC(), cv))

    def useItemSide(f: Int32): Canvas =
        let base =
            legsSide(0, 0, 0)
                |> overlay(torsoSide(0))
                |> overlay(headSide(0))
                |> overlay(bowHorizontalSide(6, 13));
        match f {
            case 0 => base |> overlay(raiseArmSideUse(0))
            case 1 => base |> overlay(raiseArmSideUse(0)) |> overlay(flashItemSide())
            case _ => base |> overlay(raiseArmSideUse(1))
        }

    def raiseArmSideUse(near: Int32): Canvas =
        empty()
            |> line(15, 13, 13, 9 - near, skinC())        // 口元へ運ぶ腕
            |> (cv -> dot(13, 8 - near, sashC(), cv))     // 水袋
            |> (cv -> dot(13, 7 - near, sashHi(), cv))

    def flashItemSide(): Canvas =
        empty()
            |> (cv -> dot(13, 7, flashC(), cv))
            |> (cv -> dot(12, 8, flashC(), cv))
            |> (cv -> dot(14, 8, flashC(), cv))

    // ════════════════════════════════════════════════════════════
    // Damage（3コマ）: f0=全身白フラッシュ+ノックバック → のけぞり。
    //   Down=手前へ / Up=奥へ / Side=横へ。
    // ════════════════════════════════════════════════════════════

    // 全身を白シルエットで塗る（そのコマの通常絵を flashC で置き換え）。
    def whiteOut(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> {
            let (x, y) = k;
            PixelCanvas.dot(x, y, flashC(), acc)
        }, empty(), cv)

    def damageDown(f: Int32): Canvas =
        let body =
            legsDown(0, 0, 0)
                |> overlay(torsoDown(0))
                |> overlay(armDown(0, 0))
                |> overlay(headDown(0))
                |> overlay(bowVertical(9, 8));
        match f {
            case 0 => whiteOut(body)                    // 白フラッシュ（足は接地のまま）
            case 1 => leanBackDown()                     // のけぞり
            case _ => leanBackDown()
        }

    // 手前へのけぞる（上体が後ろに反る・脚は接地）。
    def leanBackDown(): Canvas =
        legsDown(0, 0, 0)
            |> overlay(torsoDown(0))
            |> overlay(vline(11, 13, 3, skinC(), empty()))
            |> overlay(vline(21, 14, 3, skinC(), empty()))
            |> overlay(headDown(0 - 1))                  // 頭だけ後ろへ反る
            |> overlay(bowVertical(9, 7))

    def damageUp(f: Int32): Canvas =
        let body =
            legsDown(0, 0, 0)
                |> overlay(torsoDown(0))
                |> overlay(armUp(0))
                |> overlay(headUp(0))
                |> overlay(bowVertical(9, 8));
        match f {
            case 0 => whiteOut(body)                     // 白（奥へ）
            case 1 => shift(0 - 1, 0, body)
            case _ => body
        }

    def damageSide(f: Int32): Canvas =
        let body =
            legsSide(0, 0, 0)
                |> overlay(torsoSide(0))
                |> overlay(armSide(0, 0))
                |> overlay(headSide(0))
                |> overlay(bowHorizontalSide(6, 13));
        match f {
            case 0 => whiteOut(body)                     // 白（横へ吹き飛ぶ）
            case 1 => leanBackSide()
            case _ => leanBackSide()
        }

    def leanBackSide(): Canvas =
        legsSide(0, 1, 0 - 1)
            |> overlay(torsoSide(0))
            |> overlay(armSide(0, 0 - 1))
            |> overlay(headSide(0 - 1))
            |> overlay(bowHorizontalSide(7, 13))

    // ════════════════════════════════════════════════════════════
    // Death（6コマ・膝どまり・正面）: よろめき(2)→膝から崩れ(2)→
    //   膝立ちのまま前傾がくり(2)。弓を落とす。倒れ伏さない。
    //   最終コマも膝立ちの立面シルエットが読めること。膝/足は地面付近に残る。
    // ════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas = match f {
        case 0 => deathStagger(0)          // よろめき（弓まだ持つ）
        case 1 => deathStagger(1)          // よろめき（弓を落とし始める）
        case 2 => deathKneel(0)            // 膝から崩れる
        case 3 => deathKneel(1)
        case 4 => deathBow(0)              // 膝立ち前傾がくり
        case _ => deathBow(1)
    }

    // よろめき: 立ったまま上体が傾ぐ。lean=1 で弓を落とす。脚は接地。
    def deathStagger(lean: Int32): Canvas =
        let tilt = lean;
        let bow =
            if (lean == 0) bowVertical(9, 8)
            else bowVertical(6, 16);   // 手を離れて下へ落ちる弓
        legsDown(0, 0, 0)
            |> overlay(shift(tilt, 0, torsoDown(0)))
            |> overlay(vline(11 + tilt, 13, 4, skinC(), empty()))    // 力なく垂れる腕
            |> overlay(vline(20 + tilt, 14, 3, skinC(), empty()))
            |> overlay(headDown(0 - tilt))
            |> overlay(bow)

    // 膝から崩れる: 脚をたたみ全高が縮む。膝下は接地(y=27..29)に残す。step=1 でさらに沈む。
    def deathKneel(step: Int32): Canvas =
        let drop = 4 + step * 2;   // 上体が下がる量
        empty()
            // 落ちた弓（地面近く）
            |> vline(5, 26, 3, bowC())
            |> hline(5, 28, 3, bowHi())
            // たたんだ膝下（接地・y=25..29）
            |> hline(13, 25, 6, skinShade())
            |> vline(13, 25, 5, skinShade())               // 折れた脚
            |> vline(18, 25, 5, skinShade())
            |> hline(13, 29, 6, skinShade())               // 足元（接地）
            // 腰布（下がった位置）
            |> hline(13, 22 + step, 6, sashC())
            |> hline(13, 23 + step, 6, sashC())
            // 縮んだ胴（下へ）
            |> overlay(shift(1, drop, torsoDown(0)))
            // 力なく垂れる腕
            |> overlay(vline(12, 13 + drop, 3, skinC(), empty()))
            |> overlay(vline(20, 13 + drop, 3, skinC(), empty()))
            // 前傾した頭
            |> overlay(headDown(drop))

    // 膝立ちのまま前傾がくり（最終姿勢）。膝は接地・上体が大きく前へ折れる。
    // 膝立ちの立面シルエットが読める（倒れ伏さない）。足元は y=29 接地。
    def deathBow(step: Int32): Canvas =
        let fwd = step;   // 前傾が深まる
        empty()
            // 落ちた弓
            |> vline(4, 27, 2, bowC())
            |> hline(4, 28, 3, bowHi())
            // 接地した膝下（脛が地面 y=25..29 に立つ）
            |> vline(13, 24, 6, skinShade())
            |> vline(18, 24, 6, skinShade())
            |> hline(13, 29, 6, skinShade())               // 足元（接地）
            |> hline(13, 24, 6, skinShade())               // 膝
            // 腰布（膝立ちの腰位置）
            |> hline(13, 21, 6, sashC())
            |> hline(13, 22, 6, sashC())
            |> (cv -> dot(14, 21, sashHi(), cv))
            // 前傾した胴（前へ倒れるが膝で止まる）
            |> hline(13 + fwd, 17, 6, skinC())
            |> hline(13 + fwd, 18, 6, skinC())
            |> hline(13 + fwd, 19, 6, skinC())
            |> (cv -> dot(13 + fwd, 18, skinShade(), cv))
            // 深く垂れた頭（ターバンは前へ傾ぐ・宝石は下向き）
            |> hline(13 + fwd * 2, 13, 7, turbanC())
            |> hline(13 + fwd * 2, 14, 7, turbanC())
            |> hline(14 + fwd * 2, 15, 5, turbanShade())
            |> (cv -> dot(13 + fwd * 2, 14, gemC(), cv))   // 前に垂れた宝石
            |> hline(14 + fwd * 2, 16, 4, skinC())         // うつむいた顔
            // がくりと落ちた両腕（地に向かう）
            |> line(13 + fwd, 19, 12 + fwd, 23, skinC())
            |> line(19 + fwd, 19, 20 + fwd, 23, skinC())
}
