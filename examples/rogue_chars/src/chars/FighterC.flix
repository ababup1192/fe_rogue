// FighterC — 双持ちの女戦士（片手剣 + 手斧）。低い重心・非対称の構え。
// 個性は頭部: 白い髪のサイドを刈り上げた短髪（アンダーカット）+ 鋭い目つき。
// 右手に剣・左手に斧。攻撃は剣→斧の二連斬りを 6 コマで流し、明色の交差する弧を見せる。
//
// 色（RoguePalette から 6 色）:
//   navy      … 暗い軽鎧の本体
//   darkSlate … 鎧の影・下地
//   white     … 刈り上げた白髪・武器のハイライト
//   paleBlue  … 髪の柔らかい面・斬撃の軌跡（明色弧）
//   skin      … 肌
//   silver    … 鋼（剣身・斧刃）
//   royalBlue … 差し色（マント裏・鞘の紐など小面積のアクセント）

mod FighterC {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, arc, hflip, overlay, shift}
    use RogueStage.Clip

    pub def name(): String = "FIGHTER C 双剣舞う刈り上げ"

    // ── 色（この 6 色だけを使う）──
    def armorC(): Color = RoguePalette.navy()
    def armorDarkC(): Color = RoguePalette.darkSlate()
    def hairC(): Color = RoguePalette.white()
    def hairSoftC(): Color = RoguePalette.paleBlue()
    def skinC(): Color = RoguePalette.skin()
    def steelC(): Color = RoguePalette.silver()
    def accentC(): Color = RoguePalette.royalBlue()
    def trailC(): Color = RoguePalette.paleBlue()
    def flashTrailC(): Color = RoguePalette.white()

    // frame を [0,n) に丸める（負数も正しく回す）。
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    pub def draw(clip: Clip, frame: Int32): Canvas = match clip {
        case Clip.IdleDown    => idleDown(wrap(frame, 4))
        case Clip.IdleUp      => idleUp(wrap(frame, 4))
        case Clip.IdleSide    => idleSide(wrap(frame, 4))
        case Clip.WalkDown    => walkDown(wrap(frame, 4))
        case Clip.WalkUp      => walkUp(wrap(frame, 4))
        case Clip.WalkSide    => walkSide(wrap(frame, 4))
        case Clip.AttackDown  => attackDown(wrap(frame, 6))
        case Clip.AttackUp    => attackUp(wrap(frame, 6))
        case Clip.AttackSide  => attackSide(wrap(frame, 6))
        case Clip.UseItemDown => useItemDown(wrap(frame, 4))
        case Clip.UseItemUp   => useItemUp(wrap(frame, 4))
        case Clip.UseItemSide => useItemSide(wrap(frame, 4))
        case Clip.DamageDown  => damageDown(wrap(frame, 3))
        case Clip.DamageUp    => damageUp(wrap(frame, 3))
        case Clip.DamageSide  => damageSide(wrap(frame, 3))
        case Clip.Death       => death(wrap(frame, 6))
    }

    // ════════════════════════════════════════════════════════════
    //  頭部パーツ（刈り上げ短髪 + 鋭い目）— 全方向で使い回す
    // ════════════════════════════════════════════════════════════

    // 正面の頭。bob は上下ゆれ量。x 中心は 15..16。
    def headDown(bob: Int32): Canvas =
        let cv0 = empty();
        // 顔の肌（幅 6・y=3..8）
        let cv1 = cv0
            |> rectFill(13, 3 + bob, 6, 6, skinC());
        // 白髪: 上面（刈り上げなのでサイドは薄く・トップに束）
        let cv2 = cv1
            |> hline(13, 2 + bob, 6, hairC())        // 前髪ライン（頭頂・頭上に 1px 余白を残す）
            |> hline(14, 3 + bob, 4, hairC())        // トップの束（前髪の下に厚みを見せる）
            |> dot(13, 3 + bob, hairSoftC())         // 左サイドは刈り上げ（薄い面）
            |> dot(18, 3 + bob, hairSoftC());        // 右サイド
        // 鋭い目（下がり気味の眉→つり目）
        let cv3 = cv2
            |> dot(14, 5 + bob, armorDarkC())        // 左目
            |> dot(17, 5 + bob, armorDarkC())        // 右目
            |> dot(15, 6 + bob, skinC())
            |> dot(16, 6 + bob, skinC());
        cv3

    // 背面の頭（後頭部の刈り上げが読める）。
    def headUp(bob: Int32): Canvas =
        empty()
            |> rectFill(13, 3 + bob, 6, 5, hairSoftC())   // 後頭部の刈り上げ面
            |> hline(13, 2 + bob, 6, hairC())
            |> hline(14, 1 + bob, 4, hairC())             // トップの束
            |> hline(14, 3 + bob, 4, hairC())             // 中央の毛流れ
            |> dot(13, 7 + bob, skinC())                  // うなじ
            |> dot(18, 7 + bob, skinC())

    // 左向きの頭（横顔）。
    def headSide(bob: Int32): Canvas =
        empty()
            |> rectFill(12, 3 + bob, 5, 6, skinC())       // 横顔の肌
            |> hline(12, 2 + bob, 6, hairC())             // 頭頂の髪
            |> hline(13, 1 + bob, 4, hairC())
            |> vline(17, 3 + bob, 3, hairC())             // 後頭部側の髪束
            |> dot(16, 4 + bob, hairSoftC())              // 刈り上げの薄い面
            |> dot(13, 5 + bob, armorDarkC())             // 目（前寄り・鋭い）
            |> dot(12, 6 + bob, skinC())                  // 鼻先

    // ════════════════════════════════════════════════════════════
    //  剣（片手剣・銀の刃 + 白ハイライト）— 端点を渡して描く
    // ════════════════════════════════════════════════════════════

    // (hx,hy)=柄, (tx,ty)=切っ先。刃は 2px 幅相当（本線 + ハイライト平行線）。
    def sword(hx: Int32, hy: Int32, tx: Int32, ty: Int32): Canvas =
        empty()
            |> line(hx, hy, tx, ty, steelC())             // 刃本体
            |> line(hx + 1, hy, tx + 1, ty, hairC())      // ハイライト（1px 平行）
            |> dot(hx, hy + 1, accentC())                 // 鍔（差し色）
            |> dot(hx - 1, hy, accentC())

    // 手斧（短い柄 + 三角の刃）。(hx,hy)=握り, dir=+1 で刃が右, -1 で左。
    def axe(hx: Int32, hy: Int32, headX: Int32, headY: Int32): Canvas =
        empty()
            |> line(hx, hy, headX, headY, armorDarkC())   // 柄
            |> line(headX, headY - 1, headX, headY + 1, steelC())  // 刃の背
            |> dot(headX + 1, headY, steelC())            // 刃先
            |> dot(headX + 1, headY - 1, hairC())         // 刃のハイライト
            |> dot(headX, headY, steelC())

    // ════════════════════════════════════════════════════════════
    //  胴・脚（低い重心）
    // ════════════════════════════════════════════════════════════

    // 正面の胴 + 脚。legPhase: 0=そろい, 1=右前, 2=左前。bob は体の上下。
    def torsoDown(bob: Int32, legPhase: Int32): Canvas =
        let body = empty()
            |> rectFill(13, 9 + bob, 6, 8, armorC())      // 胴（鎧）
            |> hline(13, 9 + bob, 6, armorDarkC())        // 肩の影
            |> vline(15, 10 + bob, 5, accentC())          // 胸の差し色ライン
            |> dot(16, 12 + bob, armorDarkC());
        overlay(legsDown(bob, legPhase), body)

    def legsDown(bob: Int32, legPhase: Int32): Canvas =
        let baseY = 17 + bob;
        match legPhase {
            case 1 => empty()                              // 右前・左後
                |> vline(13, baseY, 4, armorDarkC())
                |> vline(14, baseY, 5, armorDarkC())
                |> vline(17, baseY, 5, armorC())
                |> vline(18, baseY, 4, armorC())
                |> hline(12, 29, 3, armorDarkC())          // 足
                |> hline(17, 28, 3, armorC())
            case 2 => empty()                              // 左前・右後
                |> vline(13, baseY, 5, armorC())
                |> vline(14, baseY, 4, armorC())
                |> vline(17, baseY, 4, armorDarkC())
                |> vline(18, baseY, 5, armorDarkC())
                |> hline(12, 28, 3, armorC())
                |> hline(17, 29, 3, armorDarkC())
            case _ => empty()                              // そろい（低い構え・やや開脚）
                |> vline(13, baseY, 5, armorC())
                |> vline(14, baseY, 5, armorC())
                |> vline(17, baseY, 5, armorC())
                |> vline(18, baseY, 5, armorC())
                |> hline(12, 29, 3, armorDarkC())
                |> hline(17, 29, 3, armorDarkC())
        }

    // 背面の胴 + 脚（マント裏の差し色）。
    def torsoUp(bob: Int32, legPhase: Int32): Canvas =
        let body = empty()
            |> rectFill(13, 9 + bob, 6, 8, armorC())
            |> hline(13, 9 + bob, 6, armorDarkC())
            |> vline(15, 10 + bob, 6, accentC())          // 背筋の差し色（マント裏）
            |> vline(16, 10 + bob, 6, accentC());
        overlay(legsDown(bob, legPhase), body)

    // 左向きの胴 + 脚。
    def torsoSide(bob: Int32, legPhase: Int32): Canvas =
        let body = empty()
            |> rectFill(13, 9 + bob, 5, 8, armorC())
            |> hline(13, 9 + bob, 5, armorDarkC())
            |> vline(13, 10 + bob, 6, accentC());         // 前面の差し色
        overlay(legsSide(bob, legPhase), body)

    def legsSide(bob: Int32, legPhase: Int32): Canvas =
        let baseY = 17 + bob;
        match legPhase {
            case 1 => empty()                              // 前脚（左）を前に
                |> vline(12, baseY, 5, armorC())
                |> vline(16, baseY, 4, armorDarkC())
                |> hline(10, 29, 4, armorC())
                |> hline(16, 28, 3, armorDarkC())
            case 2 => empty()                              // 後脚を前に
                |> vline(14, baseY, 4, armorDarkC())
                |> vline(16, baseY, 5, armorC())
                |> hline(13, 28, 3, armorDarkC())
                |> hline(15, 29, 4, armorC())
            case _ => empty()                              // そろい（低い構え）
                |> vline(13, baseY, 5, armorC())
                |> vline(16, baseY, 5, armorDarkC())
                |> hline(11, 29, 3, armorC())
                |> hline(15, 29, 3, armorDarkC())
        }

    // ════════════════════════════════════════════════════════════
    //  IDLE（低い構えで揺れる・双武器を左右に）
    // ════════════════════════════════════════════════════════════

    def idleDown(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;         // ゆっくり呼吸
        let head = headDown(bob);
        let body = torsoDown(bob, 0);
        // 右腕（剣・下げ気味）・左腕（斧・下げ気味）
        let armR = empty() |> line(19, 11 + bob, 22, 15 + bob, skinC());
        let armL = empty() |> line(12, 11 + bob, 9, 15 + bob, skinC());
        let sw = sword(22, 15 + bob, 25, 20 + bob);      // 右下へ剣
        let ax = axe(9, 15 + bob, 6, 17 + bob);          // 左下へ斧
        empty()
            |> overlay(sw) |> overlay(ax)
            |> overlay(armR) |> overlay(armL)
            |> overlay(body) |> overlay(head)

    def idleUp(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let head = headUp(bob);
        let body = torsoUp(bob, 0);
        let armR = empty() |> line(19, 11 + bob, 22, 15 + bob, skinC());
        let armL = empty() |> line(12, 11 + bob, 9, 15 + bob, skinC());
        // 背面では武器は体の脇に見える（刃だけのぞく）
        let sw = sword(22, 15 + bob, 24, 19 + bob);
        let ax = axe(9, 15 + bob, 6, 17 + bob);
        empty()
            |> overlay(sw) |> overlay(ax)
            |> overlay(armR) |> overlay(armL)
            |> overlay(body) |> overlay(head)

    def idleSide(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let head = headSide(bob);
        let body = torsoSide(bob, 0);
        // 左向き: 剣は前（左）下へ、斧は後ろ（右）に構える
        let armFront = empty() |> line(13, 11 + bob, 9, 15 + bob, skinC());
        let armBack  = empty() |> line(16, 11 + bob, 19, 14 + bob, skinC());
        let sw = sword(9, 15 + bob, 5, 19 + bob);
        let ax = axe(19, 14 + bob, 22, 16 + bob);
        empty()
            |> overlay(ax) |> overlay(armBack)
            |> overlay(body) |> overlay(head)
            |> overlay(armFront) |> overlay(sw)

    // ════════════════════════════════════════════════════════════
    //  WALK（低く滑らかな歩き・腕振り・上下 1px）
    // ════════════════════════════════════════════════════════════

    def walkDown(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 0 else 1;         // 接地で沈む
        let legPhase = match f { case 0 => 1 case 1 => 0 case 2 => 2 case _ => 0 };
        let head = headDown(bob);
        let body = torsoDown(bob, legPhase);
        // 腕振り: f0=右前左後 f2=左前右後
        let swing = match f { case 0 => 1 case 2 => -1 case _ => 0 };
        let armR = empty() |> line(19, 11 + bob, 22 + swing, 15 + bob, skinC());
        let armL = empty() |> line(12, 11 + bob, 9 - swing, 15 + bob, skinC());
        let sw = sword(22 + swing, 15 + bob, 25 + swing, 20 + bob);
        let ax = axe(9 - swing, 15 + bob, 6 - swing, 17 + bob);
        empty()
            |> overlay(sw) |> overlay(ax)
            |> overlay(armR) |> overlay(armL)
            |> overlay(body) |> overlay(head)

    def walkUp(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 0 else 1;
        let legPhase = match f { case 0 => 1 case 1 => 0 case 2 => 2 case _ => 0 };
        let head = headUp(bob);
        let body = torsoUp(bob, legPhase);
        let swing = match f { case 0 => 1 case 2 => -1 case _ => 0 };
        let armR = empty() |> line(19, 11 + bob, 22 + swing, 15 + bob, skinC());
        let armL = empty() |> line(12, 11 + bob, 9 - swing, 15 + bob, skinC());
        let sw = sword(22 + swing, 15 + bob, 24 + swing, 19 + bob);
        let ax = axe(9 - swing, 15 + bob, 6 - swing, 17 + bob);
        empty()
            |> overlay(sw) |> overlay(ax)
            |> overlay(armR) |> overlay(armL)
            |> overlay(body) |> overlay(head)

    def walkSide(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 0 else 1;
        // 左向きの歩幅: f0 前脚出し, f2 後脚出し（左右非対称必須）
        let legPhase = match f { case 0 => 1 case 1 => 0 case 2 => 2 case _ => 0 };
        let head = headSide(bob);
        let body = torsoSide(bob, legPhase);
        // 前腕（剣）を歩幅にあわせて振る
        let swing = match f { case 0 => -1 case 2 => 1 case _ => 0 };
        let armFront = empty() |> line(13, 11 + bob, 9 + swing, 15 + bob, skinC());
        let armBack  = empty() |> line(16, 11 + bob, 19 - swing, 14 + bob, skinC());
        let sw = sword(9 + swing, 15 + bob, 5 + swing, 19 + bob);
        let ax = axe(19 - swing, 14 + bob, 22 - swing, 16 + bob);
        empty()
            |> overlay(ax) |> overlay(armBack)
            |> overlay(body) |> overlay(head)
            |> overlay(armFront) |> overlay(sw)

    // ════════════════════════════════════════════════════════════
    //  ATTACK（剣→斧の二連斬り・6 コマ・明色の交差弧）
    //  流れ: 溜め(0) → 剣・右斬り(1,2) → つなぎ(3) → 斧・左斬り(4,5)
    // ════════════════════════════════════════════════════════════

    def attackDown(f: Int32): Canvas =
        let head = headDown(0);
        let body = torsoDown(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        match f {
            case 0 =>                                       // 溜め: 双武器を引く
                base
                    |> overlay(empty() |> line(19, 11, 24, 9, skinC()))
                    |> overlay(sword(24, 9, 27, 6))
                    |> overlay(empty() |> line(12, 11, 8, 9, skinC()))
                    |> overlay(axe(8, 9, 5, 7))
            case 1 =>                                       // 剣・右斬り 振り下ろし
                base
                    |> overlay(arc(16, 14, 10, -20, 60, trailC(), empty()))    // 明色弧（右下へ）
                    |> overlay(arc(16, 14, 9, -20, 60, trailC(), empty()))
                    |> overlay(empty() |> line(19, 11, 24, 18, skinC()))
                    |> overlay(sword(24, 18, 27, 24))
            case 2 =>                                       // 剣・斬り抜け
                base
                    |> overlay(arc(16, 16, 11, -40, 30, trailC(), empty()))
                    |> overlay(arc(16, 16, 10, -40, 30, flashTrailC(), empty()))
                    |> overlay(empty() |> line(19, 12, 25, 22, skinC()))
                    |> overlay(sword(25, 22, 28, 27))
            case 3 =>                                       // つなぎ: 斧へ持ち替える気配
                base
                    |> overlay(empty() |> line(12, 11, 8, 10, skinC()))
                    |> overlay(axe(8, 10, 6, 7))
                    |> overlay(empty() |> line(19, 12, 22, 16, skinC()))
                    |> overlay(sword(22, 16, 24, 20))
            case 4 =>                                       // 斧・左斬り 振り下ろし（剣弧と交差）
                base
                    |> overlay(arc(16, 14, 10, 120, 200, trailC(), empty()))   // 左下への弧
                    |> overlay(arc(16, 14, 9, 120, 200, flashTrailC(), empty()))
                    |> overlay(empty() |> line(12, 11, 7, 18, skinC()))
                    |> overlay(axe(7, 18, 5, 22))
            case _ =>                                       // 斧・斬り抜け（残心）
                base
                    |> overlay(arc(16, 16, 11, 150, 230, trailC(), empty()))
                    |> overlay(empty() |> line(12, 12, 6, 22, skinC()))
                    |> overlay(axe(6, 22, 4, 26))
        }

    def attackUp(f: Int32): Canvas =
        let head = headUp(0);
        let body = torsoUp(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        match f {
            case 0 =>                                       // 溜め: 双武器を下げる
                base
                    |> overlay(empty() |> line(19, 12, 23, 16, skinC()))
                    |> overlay(sword(23, 16, 25, 20))
                    |> overlay(empty() |> line(12, 12, 9, 16, skinC()))
                    |> overlay(axe(9, 16, 7, 19))
            case 1 =>                                       // 剣・上へ振り上げ（右）
                base
                    |> overlay(arc(16, 12, 10, 20, 90, trailC(), empty()))
                    |> overlay(arc(16, 12, 9, 20, 90, trailC(), empty()))
                    |> overlay(empty() |> line(19, 11, 24, 6, skinC()))
                    |> overlay(sword(24, 6, 27, 2))
            case 2 =>                                       // 剣・頂点
                base
                    |> overlay(arc(16, 12, 11, 40, 120, flashTrailC(), empty()))
                    |> overlay(empty() |> line(19, 10, 22, 4, skinC()))
                    |> overlay(sword(22, 4, 24, 0))
            case 3 =>                                       // つなぎ
                base
                    |> overlay(empty() |> line(12, 11, 9, 14, skinC()))
                    |> overlay(axe(9, 14, 7, 11))
            case 4 =>                                       // 斧・上へ振り上げ（左・交差）
                base
                    |> overlay(arc(16, 12, 10, 90, 160, trailC(), empty()))
                    |> overlay(arc(16, 12, 9, 90, 160, flashTrailC(), empty()))
                    |> overlay(empty() |> line(12, 11, 8, 6, skinC()))
                    |> overlay(axe(8, 6, 6, 2))
            case _ =>                                       // 残心
                base
                    |> overlay(arc(16, 12, 11, 110, 170, trailC(), empty()))
                    |> overlay(empty() |> line(12, 10, 9, 4, skinC()))
                    |> overlay(axe(9, 4, 7, 1))
        }

    def attackSide(f: Int32): Canvas =
        // 左向き: 前（左）へ剣を振り抜く二連。
        let head = headSide(0);
        let body = torsoSide(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        match f {
            case 0 =>                                       // 溜め: 双武器を後ろ（右）へ引く
                base
                    |> overlay(empty() |> line(16, 11, 21, 9, skinC()))
                    |> overlay(sword(21, 9, 25, 7))
                    |> overlay(empty() |> line(15, 12, 19, 14, skinC()))
                    |> overlay(axe(19, 14, 22, 13))
            case 1 =>                                       // 剣・前へ横薙ぎ
                base
                    |> overlay(arc(14, 13, 11, 130, 210, trailC(), empty()))
                    |> overlay(arc(14, 13, 10, 130, 210, trailC(), empty()))
                    |> overlay(empty() |> line(15, 11, 8, 12, skinC()))
                    |> overlay(sword(8, 12, 3, 12))
            case 2 =>                                       // 剣・振り抜け
                base
                    |> overlay(arc(13, 14, 12, 150, 230, flashTrailC(), empty()))
                    |> overlay(empty() |> line(15, 12, 7, 16, skinC()))
                    |> overlay(sword(7, 16, 2, 18))
            case 3 =>                                       // つなぎ: 斧を前へ回す
                base
                    |> overlay(empty() |> line(15, 11, 11, 11, skinC()))
                    |> overlay(axe(11, 11, 8, 9))
            case 4 =>                                       // 斧・前へ打ち下ろし（剣弧と交差）
                base
                    |> overlay(arc(13, 12, 11, 170, 250, trailC(), empty()))
                    |> overlay(arc(13, 12, 10, 170, 250, flashTrailC(), empty()))
                    |> overlay(empty() |> line(15, 11, 7, 10, skinC()))
                    |> overlay(axe(7, 10, 3, 13))
            case _ =>                                       // 残心
                base
                    |> overlay(arc(13, 13, 12, 180, 250, trailC(), empty()))
                    |> overlay(empty() |> line(15, 12, 6, 14, skinC()))
                    |> overlay(axe(6, 14, 2, 18))
        }

    // ════════════════════════════════════════════════════════════
    //  USE ITEM（掲げる → 明色フラッシュ → 使う の 3 拍・4 コマ）
    // ════════════════════════════════════════════════════════════

    def useItemDown(f: Int32): Canvas =
        let head = headDown(0);
        let body = torsoDown(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        // 右手に剣は下げたまま、左手にアイテムを掲げる
        let sw = empty() |> overlay(empty() |> line(19, 12, 22, 16, skinC())) |> overlay(sword(22, 16, 24, 20));
        match f {
            case 0 =>                                       // 掲げる
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 10, 6, skinC()))
                    |> overlay(empty() |> dot(9, 5, accentC()) |> dot(10, 4, steelC()))
            case 1 =>                                       // 明色フラッシュ
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 10, 10, 4, skinC()))
                    |> overlay(arc(10, 4, 3, 0, 360, flashTrailC(), empty()))
                    |> overlay(empty() |> dot(10, 4, flashTrailC()))
            case 2 =>                                       // 効き広がる
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 10, 6, skinC()))
                    |> overlay(arc(15, 8, 6, 0, 360, hairSoftC(), empty()))
                    |> overlay(empty() |> dot(10, 5, hairSoftC()))
            case _ =>                                       // 使い終わり（構えに戻る）
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 9, 15, skinC()))
                    |> overlay(axe(9, 15, 6, 17))
        }

    def useItemUp(f: Int32): Canvas =
        let head = headUp(0);
        let body = torsoUp(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        let sw = empty() |> overlay(empty() |> line(19, 12, 22, 16, skinC())) |> overlay(sword(22, 16, 24, 20));
        match f {
            case 0 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 11, 6, skinC()))
                    |> overlay(empty() |> dot(11, 5, accentC()) |> dot(11, 4, steelC()))
            case 1 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 10, 11, 4, skinC()))
                    |> overlay(arc(11, 4, 3, 0, 360, flashTrailC(), empty()))
                    |> overlay(empty() |> dot(11, 4, flashTrailC()))
            case 2 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 11, 6, skinC()))
                    |> overlay(arc(15, 8, 6, 0, 360, hairSoftC(), empty()))
            case _ =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(12, 11, 9, 15, skinC()))
                    |> overlay(axe(9, 15, 6, 17))
        }

    def useItemSide(f: Int32): Canvas =
        let head = headSide(0);
        let body = torsoSide(0, 0);
        let base = empty() |> overlay(body) |> overlay(head);
        // 剣は下げ、前（左）へアイテムを掲げる
        let sw = empty() |> overlay(empty() |> line(16, 12, 19, 16, skinC())) |> overlay(sword(19, 16, 21, 20));
        match f {
            case 0 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(13, 11, 9, 7, skinC()))
                    |> overlay(empty() |> dot(8, 6, accentC()) |> dot(9, 5, steelC()))
            case 1 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(13, 10, 9, 5, skinC()))
                    |> overlay(arc(9, 5, 3, 0, 360, flashTrailC(), empty()))
                    |> overlay(empty() |> dot(9, 5, flashTrailC()))
            case 2 =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(13, 11, 9, 7, skinC()))
                    |> overlay(arc(12, 9, 6, 0, 360, hairSoftC(), empty()))
            case _ =>
                base |> overlay(sw)
                    |> overlay(empty() |> line(13, 11, 9, 15, skinC()))
                    |> overlay(sword(9, 15, 6, 19))
        }

    // ════════════════════════════════════════════════════════════
    //  DAMAGE（f0=全身白フラッシュ+ノックバック → のけぞり・3 コマ）
    // ════════════════════════════════════════════════════════════

    // シルエットを白 1 色で塗り直す（全身フラッシュ）。
    def flash(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> Map.insert(k, flashTrailC(), acc), Map.empty(), cv)

    def damageDown(f: Int32): Canvas =
        match f {
            case 0 =>                                       // 全身白 + 手前へ 2px ノックバック
                let sil = empty() |> overlay(torsoDown(0, 0)) |> overlay(headDown(0))
                    |> overlay(empty() |> line(19, 11, 23, 14, skinC()))
                    |> overlay(empty() |> line(12, 11, 8, 14, skinC()));
                shift(0, 2, flash(sil))
            case 1 =>                                       // のけぞり・武器を落としかける
                let head = headDown(1);
                let body = torsoDown(1, 0);
                empty()
                    |> overlay(sword(24, 19, 26, 24))       // 剣が手から離れ落ちる
                    |> overlay(axe(7, 19, 5, 23))
                    |> overlay(empty() |> line(19, 12, 23, 16, skinC()))
                    |> overlay(empty() |> line(12, 12, 8, 16, skinC()))
                    |> overlay(body) |> overlay(head)
            case _ =>                                       // 戻り
                let head = headDown(0);
                let body = torsoDown(0, 0);
                empty()
                    |> overlay(sword(22, 15, 25, 20))
                    |> overlay(axe(9, 15, 6, 17))
                    |> overlay(empty() |> line(19, 11, 22, 15, skinC()))
                    |> overlay(empty() |> line(12, 11, 9, 15, skinC()))
                    |> overlay(body) |> overlay(head)
        }

    def damageUp(f: Int32): Canvas =
        match f {
            case 0 =>                                       // 奥へ 2px ノックバック + 白
                let sil = empty() |> overlay(torsoUp(0, 0)) |> overlay(headUp(0));
                shift(0, -2, flash(sil))
            case 1 =>
                let head = headUp(1);
                let body = torsoUp(1, 0);
                empty()
                    |> overlay(sword(24, 19, 26, 23))
                    |> overlay(axe(7, 19, 5, 22))
                    |> overlay(body) |> overlay(head)
            case _ =>
                let head = headUp(0);
                let body = torsoUp(0, 0);
                empty()
                    |> overlay(sword(22, 15, 24, 19))
                    |> overlay(axe(9, 15, 6, 17))
                    |> overlay(body) |> overlay(head)
        }

    def damageSide(f: Int32): Canvas =
        match f {
            case 0 =>                                       // 横（右・後方）へ 2px ノックバック + 白
                let sil = empty() |> overlay(torsoSide(0, 0)) |> overlay(headSide(0))
                    |> overlay(empty() |> line(13, 11, 9, 15, skinC()));
                shift(2, 0, flash(sil))
            case 1 =>
                let head = headSide(1);
                let body = torsoSide(1, 0);
                empty()
                    |> overlay(sword(11, 18, 8, 23))        // 前の手から剣が滑り落ちる
                    |> overlay(axe(20, 16, 23, 19))
                    |> overlay(body) |> overlay(head)
            case _ =>
                let head = headSide(0);
                let body = torsoSide(0, 0);
                empty()
                    |> overlay(axe(19, 14, 22, 16))
                    |> overlay(body) |> overlay(head)
                    |> overlay(empty() |> line(13, 11, 9, 15, skinC()))
                    |> overlay(sword(9, 15, 5, 19))
        }

    // ════════════════════════════════════════════════════════════
    //  DEATH（6 コマ・膝どまり・正面）
    //  よろめき(0,1) → 膝から崩れ(2,3) → 膝立ち前傾がくり(4,5)
    //  武器を先に落としてから崩れる。倒れ伏さない。
    // ════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas = match f {
        case 0 =>                                           // よろめき・武器を取り落とす
            let head = headDown(1) |> shift(-1, 0);
            let body = torsoDown(1, 2) |> shift(-1, 0);
            empty()
                |> overlay(sword(24, 22, 26, 26))           // 剣が落ちていく
                |> overlay(axe(6, 22, 4, 25))               // 斧も落ちる
                |> overlay(body) |> overlay(head)
                |> overlay(empty() |> line(13, 12, 10, 16, skinC()))
                |> overlay(empty() |> line(18, 12, 21, 16, skinC()))
        case 1 =>                                           // 反対へよろめく・武器は地面
            let head = headDown(1) |> shift(1, 0);
            let body = torsoDown(1, 1) |> shift(1, 0);
            empty()
                |> overlay(empty() |> line(23, 27, 27, 28, steelC()))  // 落ちた剣
                |> overlay(empty() |> dot(5, 28, steelC()) |> dot(6, 27, steelC()))  // 落ちた斧
                |> overlay(body) |> overlay(head)
                |> overlay(empty() |> line(13, 12, 11, 17, skinC()))
                |> overlay(empty() |> line(19, 12, 22, 17, skinC()))
        case 2 =>                                           // 膝から崩れ始める（腰が落ちる）
            let head = headDown(3);
            // 上体を下げ、脚を折る
            let upper = empty()
                |> rectFill(13, 12, 6, 7, armorC())
                |> hline(13, 12, 6, armorDarkC());
            empty()
                |> overlay(kneelLegs(0))
                |> overlay(upper) |> overlay(head)
                |> overlay(empty() |> line(13, 14, 11, 19, skinC()))
                |> overlay(empty() |> line(18, 14, 21, 19, skinC()))
        case 3 =>                                           // 深く沈む（膝が地面へ）
            let head = headDown(4);
            let upper = empty()
                |> rectFill(13, 14, 6, 6, armorC())
                |> hline(13, 14, 6, armorDarkC());
            empty()
                |> overlay(kneelLegs(1))
                |> overlay(upper) |> overlay(head)
                |> overlay(empty() |> line(13, 16, 11, 22, skinC()))
                |> overlay(empty() |> line(18, 16, 21, 22, skinC()))
        case 4 =>                                           // 膝立ちのまま前傾（頭が垂れる）
            let head = headDown(5) |> shift(0, 1);
            let upper = empty()
                |> rectFill(13, 15, 6, 6, armorC())
                |> hline(13, 15, 6, armorDarkC())
                |> vline(15, 16, 4, accentC());
            empty()
                |> overlay(kneelLegs(1))
                |> overlay(upper) |> overlay(head)
                |> overlay(empty() |> line(13, 17, 11, 23, skinC()))
                |> overlay(empty() |> line(18, 17, 20, 23, skinC()))
        case _ =>                                           // 前傾がくり（膝立ち・立面が読める・最終）
            let head = headDown(6) |> shift(0, 2);          // 頭が最も垂れる
            let upper = empty()
                |> rectFill(13, 16, 6, 6, armorC())
                |> hline(13, 16, 6, armorDarkC())
                |> vline(15, 17, 4, accentC());
            empty()
                |> overlay(kneelLegs(1))
                |> overlay(upper) |> overlay(head)
                |> overlay(empty() |> line(13, 18, 12, 24, skinC()))
                |> overlay(empty() |> line(18, 18, 20, 24, skinC()))
    }

    // 膝立ちの脚（stage 0=崩れ始め, 1=完全に膝立ち）。足元は y=29。
    def kneelLegs(stage: Int32): Canvas =
        if (stage == 0)
            empty()
                |> vline(13, 20, 6, armorC())               // まだ立ち気味
                |> vline(14, 20, 6, armorC())
                |> vline(17, 21, 5, armorDarkC())
                |> hline(12, 28, 4, armorC())
                |> hline(16, 29, 3, armorDarkC())
        else
            empty()                                          // 膝立ち: すねを地面に伏せ膝で支える
                |> rectFill(12, 24, 3, 3, armorC())          // 手前の膝
                |> hline(11, 27, 5, armorDarkC())            // すね〜足の甲が地面に
                |> hline(11, 28, 6, armorC())
                |> hline(16, 26, 4, armorDarkC())            // 奥の脚は立てて支える
                |> vline(18, 22, 5, armorDarkC())
                |> hline(17, 29, 4, armorDarkC())
}
