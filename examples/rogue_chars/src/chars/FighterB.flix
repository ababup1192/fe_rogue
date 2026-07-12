// FighterB — 若い新兵。体に見合わない大斧を担ぐ元気な少年剣士。
// 個性は頭部で出す: ボサボサの茶髪 + 額あて（headband）+ 頬の絆創膏。
// 武器は主役 = 両刃の大斧（木柄 brown + 鋼 silver/white）。腰に短い剣。
// 色は RoguePalette のみ: green/darkGreen（チュニック）・brown/darkBrown（髪・柄）・
//     silver/white（鋼）・skin（肌）・salmon（絆創膏/頬）。

mod FighterB {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, arc, shift, overlay}
    use RogueStage.Clip

    pub def name(): String = "FIGHTER B おれ、まだまだいける！"

    // ── 色 ──
    def tunic(): Color = RoguePalette.green()          // 緑チュニック（主）
    def tunicDk(): Color = RoguePalette.darkGreen()    // チュニックの影
    def skinC(): Color = RoguePalette.skin()           // 肌
    def hairC(): Color = RoguePalette.brown()          // ボサボサ茶髪
    def hairDk(): Color = RoguePalette.darkBrown()     // 髪の影・額あての結び
    def band(): Color = RoguePalette.salmon()          // 額あて（headband）
    def patch(): Color = RoguePalette.salmon()         // 頬の絆創膏
    def haft(): Color = RoguePalette.brown()           // 斧の木柄
    def haftDk(): Color = RoguePalette.darkBrown()     // 柄の影
    def steel(): Color = RoguePalette.silver()         // 鋼（斧・剣）
    def steelHi(): Color = RoguePalette.white()        // 鋼のハイライト・攻撃軌跡
    def flash(): Color = RoguePalette.white()          // 被弾フラッシュ

    // ── エントリ: 全クリップの絵を一律 8px 下げて足元を地面 y=29 に接地させる。 ──
    // 各クリップの作画は原点まわり（足元 y≈21）で描き、ここでまとめて下げる方が
    // コマごとの個別調整より安全（宙に浮く取りこぼしが起きない）。
    pub def draw(clip: Clip, frame: Int32): Canvas =
        baseDraw(clip, frame) |> shift(0, 8)

    def baseDraw(clip: Clip, frame: Int32): Canvas =
        let n = RogueStage.frameCount(clip);
        let f = Int32.modulo(frame, n);   // modulo は常に 0..n-1 を返す
        match clip {
            case Clip.IdleDown    => idleDown(f)
            case Clip.IdleUp      => idleUp(f)
            case Clip.IdleSide    => idleSide(f)
            case Clip.WalkDown    => walkDown(f)
            case Clip.WalkUp      => walkUp(f)
            case Clip.WalkSide    => walkSide(f)
            case Clip.AttackDown  => attackDown(f)
            case Clip.AttackUp    => attackUp(f)
            case Clip.AttackSide  => attackSide(f)
            case Clip.UseItemDown => useItemDown(f)
            case Clip.UseItemUp   => useItemUp(f)
            case Clip.UseItemSide => useItemSide(f)
            case Clip.DamageDown  => damageDown(f)
            case Clip.DamageUp    => damageUp(f)
            case Clip.DamageSide  => damageSide(f)
            case Clip.Death       => death(f)
        }

    // ════════════════════════════════════════════════════════════════════
    // 頭部パーツ（個性の核）— 全クリップ・全方向で使い回す
    // ════════════════════════════════════════════════════════════════════

    /// 正面の頭（茶髪ボサボサ + 額あて + 顔 + 頬の絆創膏）。頭頂 y=6..13。
    def headDown(bob: Int32): Canvas =
        let y = 6 + bob;
        empty()
            // ボサボサ茶髪の輪郭（外にはねる毛束）
            |> (cv -> dot(11, y, hairC(), cv))
            |> hline(12, y, 8, hairC())
            |> (cv -> dot(20, y, hairC(), cv))
            |> (cv -> dot(10, y + 1, hairC(), cv))
            |> hline(11, y + 1, 10, hairC())
            |> (cv -> dot(21, y + 1, hairC(), cv))
            // 額あて（headband）: 髪の下を横断する帯
            |> hline(11, y + 2, 10, band())
            |> (cv -> dot(10, y + 2, hairDk(), cv))
            |> (cv -> dot(21, y + 2, hairDk(), cv))        // 帯の結び目
            // 顔（肌）+ もみあげの髪
            |> (cv -> dot(11, y + 3, hairC(), cv))
            |> hline(12, y + 3, 8, skinC())
            |> (cv -> dot(20, y + 3, hairC(), cv))
            |> (cv -> dot(11, y + 4, hairC(), cv))
            |> hline(12, y + 4, 8, skinC())
            |> (cv -> dot(20, y + 4, hairC(), cv))
            |> hline(12, y + 5, 8, skinC())
            // 目（あどけない大きめの点目）
            |> (cv -> dot(14, y + 4, hairDk(), cv))
            |> (cv -> dot(17, y + 4, hairDk(), cv))
            // 頬の絆創膏（左頬に1枚・×印風に2px）
            |> (cv -> dot(12, y + 5, patch(), cv))
            |> (cv -> dot(13, y + 5, patch(), cv))
            // 口（小さく）
            |> (cv -> dot(15, y + 5, hairDk(), cv))
            |> (cv -> dot(16, y + 5, hairDk(), cv))

    /// 背面の頭（後頭部 = 髪で埋まる + 額あての結び目が裏に見える）。
    def headUp(bob: Int32): Canvas =
        let y = 6 + bob;
        empty()
            |> (cv -> dot(11, y, hairC(), cv))
            |> hline(12, y, 8, hairC())
            |> (cv -> dot(20, y, hairC(), cv))
            |> hline(11, y + 1, 10, hairC())
            // 額あての帯（裏側）+ 結び目とたれ
            |> hline(11, y + 2, 10, band())
            |> (cv -> dot(15, y + 2, hairDk(), cv))        // 結び目
            |> (cv -> dot(16, y + 2, hairDk(), cv))
            |> (cv -> dot(15, y + 3, band(), cv))          // 帯のたれ端
            |> (cv -> dot(16, y + 3, band(), cv))
            // 後頭部の髪（全部茶髪）
            |> hline(11, y + 3, 10, hairC())
            |> hline(11, y + 4, 10, hairC())
            |> hline(12, y + 5, 8, hairDk())               // 襟足の影

    /// 左向きの頭（横顔 + 額あて + 後ろにはねる毛先）。
    def headSide(bob: Int32): Canvas =
        let y = 6 + bob;
        empty()
            // 髪（後頭部は右へ、前髪は左の額に垂れる）
            |> (cv -> dot(12, y, hairC(), cv))
            |> hline(13, y, 7, hairC())
            |> (cv -> dot(20, y, hairC(), cv))             // 後ろへはねる毛
            |> hline(11, y + 1, 10, hairC())
            |> (cv -> dot(21, y + 1, hairC(), cv))
            // 額あて（横断・後ろで結ぶ）
            |> hline(11, y + 2, 9, band())
            |> (cv -> dot(20, y + 2, hairDk(), cv))        // 後ろの結び目
            |> (cv -> dot(21, y + 2, band(), cv))          // たれ
            // 横顔（左が前・肌／右は髪）
            |> hline(11, y + 3, 4, skinC())
            |> hline(15, y + 3, 5, hairC())
            |> hline(11, y + 4, 4, skinC())
            |> hline(15, y + 4, 5, hairC())
            |> hline(11, y + 5, 3, skinC())
            // 目（前寄り）+ 絆創膏（頬）
            |> (cv -> dot(12, y + 4, hairDk(), cv))
            |> (cv -> dot(11, y + 5, patch(), cv))

    // ════════════════════════════════════════════════════════════════════
    // 胴・脚・腰の剣（方向共通の土台）
    // ════════════════════════════════════════════════════════════════════

    /// 正面/背面の胴（緑チュニック）。肩 y=13、裾 y=21。leftLegDx/rightLegDx で歩幅。
    def bodyFront(bob: Int32, leftLegDx: Int32, rightLegDx: Int32): Canvas =
        let y = 13 + bob;
        empty()
            // チュニックの胴
            |> rectFill(12, y, 8, 6, tunic())
            |> vline(12, y, 6, tunicDk())                  // 左端の影
            |> hline(13, y + 5, 6, tunicDk())              // 裾の影
            // ベルト（腰の剣を提げる帯）
            |> hline(12, y + 4, 8, haftDk())
            // 脚（darkGreen ズボン + skin すね）
            |> vline(13 + leftLegDx, y + 6, 2, tunicDk())
            |> vline(13 + leftLegDx, y + 8, 1, skinC())
            |> vline(18 + rightLegDx, y + 6, 2, tunicDk())
            |> vline(18 + rightLegDx, y + 8, 1, skinC())
            // 足
            |> hline(12 + leftLegDx, y + 8, 2, hairDk())
            |> hline(18 + rightLegDx, y + 8, 2, hairDk())

    /// 腰の短い剣（正面: 右腰に鞘・柄が斜めに出る）。
    def sheathFront(bob: Int32): Canvas =
        let y = 17 + bob;
        empty()
            |> vline(20, y, 3, steel())                    // 鞘
            |> (cv -> dot(20, y - 1, haft(), cv))          // 柄
            |> (cv -> dot(21, y - 1, steelHi(), cv))       // つば

    /// 左向きの胴（緑チュニック・横身）。
    def bodySide(bob: Int32, frontLegDx: Int32, backLegDx: Int32): Canvas =
        let y = 13 + bob;
        empty()
            |> rectFill(13, y, 6, 6, tunic())
            |> vline(13, y, 6, tunicDk())                  // 前側（左）の影
            |> hline(13, y + 5, 6, tunicDk())
            |> hline(13, y + 4, 6, haftDk())               // ベルト
            // 奥脚（背面側・暗め）
            |> vline(16 + backLegDx, y + 6, 2, tunicDk())
            |> vline(16 + backLegDx, y + 8, 1, skinC())
            |> hline(15 + backLegDx, y + 8, 2, hairDk())
            // 手前脚
            |> vline(14 + frontLegDx, y + 6, 2, tunicDk())
            |> vline(14 + frontLegDx, y + 8, 1, skinC())
            |> hline(13 + frontLegDx, y + 8, 2, hairDk())

    /// 腰の短い剣（左向き: 背中側に鞘が出る）。
    def sheathSide(bob: Int32): Canvas =
        let y = 17 + bob;
        empty()
            |> line(18, y, 20, y + 3, steel())             // 斜めの鞘
            |> (cv -> dot(18, y - 1, haft(), cv))          // 柄

    // ════════════════════════════════════════════════════════════════════
    // 大斧（主役の武器）— 担ぎ姿と振り姿
    // ════════════════════════════════════════════════════════════════════

    /// 肩に担いだ大斧（正面/背面共通・右肩の上に斧頭）。tiltは重さのゆらぎ。
    def axeShouldered(bob: Int32, tilt: Int32): Canvas =
        let y = 13 + bob;
        empty()
            // 木柄: 右腰から右肩の上へ斜めに（2px幅）
            |> line(19, y + 4, 22 + tilt, y - 6, haft())
            |> line(20, y + 4, 23 + tilt, y - 6, haftDk())
            // 斧頭（両刃・右肩の上）— 幅広の鋼
            |> overlay(axeHead(22 + tilt, y - 7))

    /// 斧頭を (cx,cy) 中心に描く（両刃・扇形・鋼にハイライト）。
    def axeHead(cx: Int32, cy: Int32): Canvas =
        empty()
            // 上刃
            |> hline(cx - 2, cy, 5, steel())
            |> hline(cx - 3, cy + 1, 7, steel())
            |> hline(cx - 3, cy + 2, 7, steel())
            |> hline(cx - 2, cy + 3, 5, steel())
            // 刃先のハイライト（左右の尖り）
            |> (cv -> dot(cx - 3, cy + 1, steelHi(), cv))
            |> (cv -> dot(cx - 3, cy + 2, steelHi(), cv))
            |> (cv -> dot(cx + 3, cy + 1, steelHi(), cv))
            |> (cv -> dot(cx + 3, cy + 2, steelHi(), cv))
            // 中央のソケット（柄が通る影）
            |> vline(cx, cy, 4, haftDk())

    // ════════════════════════════════════════════════════════════════════
    // IDLE（呼吸 + 斧の重さでゆらぐ）— 4コマ
    // ════════════════════════════════════════════════════════════════════

    def idleDown(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;         // 肩で息（上下1px）
        let tilt = if (f == 2) 1 else 0;                  // 斧の重さで少し傾く
        axeShouldered(bob, tilt)
            |> overlay(rightArmDown(bob, false))
            |> overlay(sheathFront(bob))
            |> overlay(bodyFront(bob, 0, 0))
            |> overlay(headDown(bob))

    def idleUp(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let tilt = if (f == 2) 1 else 0;
        axeShouldered(bob, tilt)
            |> overlay(bodyFront(bob, 0, 0))
            |> overlay(headUp(bob))

    def idleSide(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let tilt = if (f == 2) 1 else 0;
        axeShoulderedSide(bob, tilt)
            |> overlay(armSide(bob, 0))
            |> overlay(sheathSide(bob))
            |> overlay(bodySide(bob, 0, 0))
            |> overlay(headSide(bob))

    /// 左向きに担いだ大斧（斧頭が背中側＝右上に出る）。
    def axeShoulderedSide(bob: Int32, tilt: Int32): Canvas =
        let y = 13 + bob;
        empty()
            |> line(15, y + 3, 19 + tilt, y - 6, haft())
            |> line(16, y + 3, 20 + tilt, y - 6, haftDk())
            |> overlay(axeHead(20 + tilt, y - 7))

    /// 正面/背面の右腕（肩から手まで2px幅・斧の柄を握る）。raised=攻撃用の上げ腕。
    def rightArmDown(bob: Int32, raised: Bool): Canvas =
        let y = 13 + bob;
        if (raised)
            empty()
                |> line(19, y + 1, 22, y - 4, skinC())
                |> line(20, y + 1, 23, y - 4, skinC())
        else
            empty()
                |> line(19, y + 1, 20, y + 4, skinC())     // 右腕（柄側）
                |> line(12, y + 1, 11, y + 4, skinC())     // 左腕（添える）

    /// 左向きの腕（swingで前後）。
    def armSide(bob: Int32, swing: Int32): Canvas =
        let y = 13 + bob;
        empty()
            |> line(15, y + 1, 15 + swing, y + 4, skinC())
            |> (cv -> dot(15 + swing, y + 4, skinC(), cv))

    // ════════════════════════════════════════════════════════════════════
    // WALK（腕と斧を大きく振る元気な歩き）— 各4コマ全部違う絵
    // ════════════════════════════════════════════════════════════════════

    // 歩幅テーブル: (左脚dx, 右脚dx, 上下bob, 斧の振れtilt)
    def walkStep(f: Int32): (Int32, Int32, Int32, Int32) = match f {
        case 0 => (-1, 1, 0, -1)     // 左脚前・右脚後
        case 1 => (0, 0, 1, 0)       // 通過（体が浮く）
        case 2 => (1, -1, 0, 1)      // 右脚前・左脚後
        case _ => (0, 0, 1, 0)       // 通過
    }

    def walkDown(f: Int32): Canvas =
        let (l, r, bob, tilt) = walkStep(f);
        axeShouldered(bob, tilt)
            |> overlay(rightArmDown(bob, false))
            |> overlay(sheathFront(bob))
            |> overlay(bodyFront(bob, l, r))
            |> overlay(headDown(bob))

    def walkUp(f: Int32): Canvas =
        let (l, r, bob, tilt) = walkStep(f);
        axeShouldered(bob, tilt)
            |> overlay(bodyFront(bob, l, r))
            |> overlay(headUp(bob))

    def walkSide(f: Int32): Canvas =
        // f0 は左右非対称必須（lint）: 手前脚前・奥脚後・腕は後ろ振り
        let (fr, bk, bob, tilt, sw) = match f {
            case 0 => (2, -1, 0, -1, -1)    // 手前脚を前・腕後ろ
            case 1 => (0, 0, 1, 0, 0)       // 通過
            case 2 => (-1, 2, 0, 1, 1)      // 奥脚を前・腕前
            case _ => (0, 0, 1, 0, 0)
        };
        axeShoulderedSide(bob, tilt)
            |> overlay(armSide(bob, sw))
            |> overlay(sheathSide(bob))
            |> overlay(bodySide(bob, fr, bk))
            |> overlay(headSide(bob))

    // ════════════════════════════════════════════════════════════════════
    // ATTACK（全身を使った大斧の大振り）— 各6コマ
    // 拍: 0=構え(振りかぶり) 1=振りかぶり最大 2=振り下ろし(軌跡) 3=命中
    //     4=よろけ(愛嬌) 5=戻り
    // ════════════════════════════════════════════════════════════════════

    // ── AttackDown（手前へ振り下ろす）──
    def attackDown(f: Int32): Canvas = match f {
        case 0 => atkDownWindup(0)
        case 1 => atkDownWindup(1)
        case 2 => atkDownSwing(0)      // 頭上→前 軌跡
        case 3 => atkDownSwing(1)      // 命中（斧が下）
        case 4 => atkDownStagger()     // よろけ
        case _ => idleDown(0)          // 戻り
    }

    def atkDownWindup(k: Int32): Canvas =
        // 斧を頭上へ大きく振りかぶる（背をそらす）
        let cx = 15;
        let cy = 3 - k;
        empty()
            |> line(15, 15, cx, cy + 3, haft())            // 柄を上へ
            |> line(16, 15, cx + 1, cy + 3, haftDk())
            |> overlay(axeHead(cx, cy))
            |> overlay(bodyFront(0, -1, 1))
            |> overlay(rightArmDown(0, true))
            |> overlay(headDown(0))

    def atkDownSwing(k: Int32): Canvas =
        // 明色の弧（頭上から手前下へ大きく）+ 斧が前方低くへ
        let axeY = 18 + k * 3;
        arc(15, 14, 11, 300, 60, steelHi(), empty())       // 大きな軌跡弧
            |> overlay(arc(15, 14, 10, 300, 40, steel(), empty()))
            |> overlay(line(15, 15, 16, axeY, haft(), empty()))
            |> overlay(line(16, 15, 17, axeY, haftDk(), empty()))
            |> overlay(axeHead(16, axeY))
            |> overlay(bodyFront(0, 1, -1))
            |> overlay(line(13, 14, 16, axeY - 2, skinC(), empty())) // 伸びた腕
            |> overlay(headDown(0))

    def atkDownStagger(): Canvas =
        // よろけ: 斧の重さで前のめり・体が傾く（愛嬌の1コマ）
        empty()
            |> line(14, 16, 18, 22, haft())
            |> line(15, 16, 19, 22, haftDk())
            |> overlay(axeHead(19, 22))
            |> overlay(shift(1, 1, bodyFront(0, 2, -2)))
            |> overlay(line(14, 15, 17, 20, skinC(), empty()))
            |> overlay(shift(1, 1, headDown(1)))

    // ── AttackUp（奥へ振り上げる）──
    def attackUp(f: Int32): Canvas = match f {
        case 0 => atkUpWindup(0)
        case 1 => atkUpWindup(1)
        case 2 => atkUpSwing(0)
        case 3 => atkUpSwing(1)
        case 4 => atkUpStagger()
        case _ => idleUp(0)
    }

    def atkUpWindup(k: Int32): Canvas =
        // 斧を後ろ（下・手前）へ引く
        let ay = 16 + k;
        empty()
            |> line(14, 15, 12, ay + 3, haft())
            |> overlay(axeHead(11, ay + 3))
            |> overlay(bodyFront(0, 1, -1))
            |> overlay(headUp(0))

    def atkUpSwing(k: Int32): Canvas =
        // 明色の弧を頭の奥（上）へ振り上げる
        let cy = 2 - k;
        arc(15, 13, 11, 40, 140, steelHi(), empty())
            |> overlay(arc(15, 13, 10, 60, 140, steel(), empty()))
            |> overlay(line(15, 14, 15, cy + 3, haft(), empty()))
            |> overlay(line(16, 14, 16, cy + 3, haftDk(), empty()))
            |> overlay(axeHead(15, cy))
            |> overlay(bodyFront(0, -1, 1))
            |> overlay(headUp(0))

    def atkUpStagger(): Canvas =
        empty()
            |> line(15, 14, 15, 6, haft())
            |> overlay(axeHead(15, 3))
            |> overlay(shift(-1, 1, bodyFront(0, -2, 1)))
            |> overlay(shift(-1, 0, headUp(1)))

    // ── AttackSide（左向き・横薙ぎの大振り）──
    def attackSide(f: Int32): Canvas = match f {
        case 0 => atkSideWindup(0)
        case 1 => atkSideWindup(1)
        case 2 => atkSideSwing(0)
        case 3 => atkSideSwing(1)
        case 4 => atkSideStagger()
        case _ => idleSide(0)
    }

    def atkSideWindup(k: Int32): Canvas =
        // 斧を右後方・上へ大きく振りかぶる
        let cx = 22 + k;
        empty()
            |> line(16, 14, cx - 1, 6, haft())
            |> line(17, 14, cx, 6, haftDk())
            |> overlay(axeHead(cx, 5))
            |> overlay(bodySide(0, -1, 1))
            |> overlay(line(15, 14, cx - 2, 8, skinC(), empty()))
            |> overlay(headSide(0))

    def atkSideSwing(k: Int32): Canvas =
        // 左前へ薙ぐ大きな明色弧（右上→左下）
        let ax = 7 - k * 2;
        arc(15, 15, 12, 20, 200, steelHi(), empty())
            |> overlay(arc(15, 15, 11, 40, 180, steel(), empty()))
            |> overlay(line(15, 15, ax + 1, 18, haft(), empty()))
            |> overlay(line(15, 16, ax + 1, 19, haftDk(), empty()))
            |> overlay(axeHead(ax, 18))
            |> overlay(bodySide(0, 2, -1))
            |> overlay(line(15, 14, ax + 3, 17, skinC(), empty()))
            |> overlay(headSide(0))

    def atkSideStagger(): Canvas =
        // 振り切って前のめりによろける
        empty()
            |> line(13, 17, 8, 21, haft())
            |> overlay(axeHead(6, 21))
            |> overlay(shift(-1, 1, bodySide(0, 2, -2)))
            |> overlay(line(13, 16, 9, 20, skinC(), empty()))
            |> overlay(shift(-1, 1, headSide(1)))

    // ════════════════════════════════════════════════════════════════════
    // USE ITEM（薬などを掲げて使う）— 各4コマ
    // 拍: 0=掲げる 1=明色フラッシュ 2=使う 3=下ろす
    // 斧は肩に担いだまま、空いた手でアイテムを扱う。
    // ════════════════════════════════════════════════════════════════════

    /// 掲げるアイテム（小瓶）。flashで白く光る。
    def vial(x: Int32, y: Int32, lit: Bool): Canvas =
        let body = if (lit) flash() else RoguePalette.cyan();
        let glow =
            if (lit)
                empty() |> dot(x - 1, y, flash()) |> dot(x + 1, y, flash())  // 光の粒
            else
                empty();
        empty()
            |> vline(x, y, 2, body)
            |> dot(x, y - 1, haftDk())                     // 栓
            |> overlay(glow)

    def useItemDown(f: Int32): Canvas =
        let (armTopY, lit) = match f {
            case 0 => (8, false)     // 掲げ始め
            case 1 => (6, true)      // 高く掲げて光る
            case 2 => (6, false)     // 使う
            case _ => (12, false)    // 下ろす
        };
        axeShouldered(0, 0)
            |> overlay(sheathFront(0))
            |> overlay(bodyFront(0, 0, 0))
            |> overlay(line(12, 15, 11, armTopY, skinC(), empty()))  // 左腕を上げる
            |> overlay(vial(11, armTopY - 1, lit))
            |> overlay(headDown(0))

    def useItemUp(f: Int32): Canvas =
        let (armTopY, lit) = match f {
            case 0 => (8, false)
            case 1 => (6, true)
            case 2 => (6, false)
            case _ => (12, false)
        };
        axeShouldered(0, 0)
            |> overlay(bodyFront(0, 0, 0))
            |> overlay(line(19, 15, 20, armTopY, skinC(), empty()))  // 背面なので右手を上げる
            |> overlay(vial(20, armTopY - 1, lit))
            |> overlay(headUp(0))

    def useItemSide(f: Int32): Canvas =
        let (armTopY, lit) = match f {
            case 0 => (8, false)
            case 1 => (6, true)
            case 2 => (6, false)
            case _ => (12, false)
        };
        axeShoulderedSide(0, 0)
            |> overlay(sheathSide(0))
            |> overlay(bodySide(0, 0, 0))
            |> overlay(line(14, 15, 13, armTopY, skinC(), empty()))  // 前手を上げる
            |> overlay(vial(13, armTopY - 1, lit))
            |> overlay(headSide(0))

    // ════════════════════════════════════════════════════════════════════
    // DAMAGE（白フラッシュ + 尻もち気味ののけぞり）— 各3コマ
    // f0 = 全身白シルエット + 後方ノックバック / f1,f2 = のけぞり戻り
    // ════════════════════════════════════════════════════════════════════

    /// あるコマの絵を全ピクセル white に潰したシルエット（フラッシュ用）。
    def whiteOut(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> {
            let (x, y) = k;
            PixelCanvas.dot(x, y, flash(), acc)
        }, PixelCanvas.empty(), cv)

    def damageDown(f: Int32): Canvas = match f {
        // 手前へ = 下（+y方向）へ尻もち気味にのけぞる
        case 0 => whiteOut(shift(0, 2, idleDown(0)))
        case 1 => shift(0, 1, hurtDown())
        case _ => hurtDown()
    }

    /// のけぞり姿（上体を反らせ・斧を落としかける）。
    def hurtDown(): Canvas =
        axeShouldered(0, 2)                                 // 斧が大きく傾く
            |> overlay(sheathFront(0))
            |> overlay(bodyFront(0, -2, 2))                 // 脚を広げて踏ん張る
            |> overlay(line(11, 14, 9, 12, skinC(), empty()))        // 腕が跳ねる
            |> overlay(shift(0, -1, headDown(0)))           // 顎が上がる

    def damageUp(f: Int32): Canvas = match f {
        // 奥へ = 上（-y方向）へノックバック
        case 0 => whiteOut(shift(0, -2, idleUp(0)))
        case 1 => shift(0, -1, hurtUp())
        case _ => hurtUp()
    }

    def hurtUp(): Canvas =
        axeShouldered(0, 2)
            |> overlay(bodyFront(0, 2, -2))
            |> overlay(headUp(0))

    def damageSide(f: Int32): Canvas = match f {
        // 横へ = 左向き作画なので右（+x方向）へ弾かれる
        case 0 => whiteOut(shift(2, 0, idleSide(0)))
        case 1 => shift(1, 0, hurtSide())
        case _ => hurtSide()
    }

    def hurtSide(): Canvas =
        axeShoulderedSide(0, 2)
            |> overlay(sheathSide(0))
            |> overlay(bodySide(0, -2, 1))                  // 後ろへのけぞる
            |> overlay(line(15, 14, 17, 11, skinC(), empty()))       // 腕が跳ねる
            |> overlay(shift(1, -1, headSide(0)))           // 頭が後ろへ

    // ════════════════════════════════════════════════════════════════════
    // DEATH（正面・膝どまり）— 6コマ
    // 0,1 よろめき → 2,3 膝から崩れ → 4,5 膝立ちのまま前傾がくり
    // 斧は途中で取り落とす。倒れ伏さない（この後 Skeleton に差し替わる）。
    // ════════════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas = match f {
        case 0 => deathStagger(0)
        case 1 => deathStagger(1)
        case 2 => deathCollapse(0)
        case 3 => deathCollapse(1)
        case 4 => deathKneel(0)
        case _ => deathKneel(1)
    }

    /// よろめき: 立ったまま体が左右に揺れ、斧が肩から滑り落ちる。
    def deathStagger(k: Int32): Canvas =
        let sway = if (k == 0) -1 else 1;
        // 斧が肩からずり落ちていく（k で下へ）
        let axeY = -6 + k * 4;
        empty()
            |> line(20, 15, 23, 8 + axeY, haft())
            |> overlay(axeHead(23, 7 + axeY))
            |> overlay(shift(sway, 0, bodyFront(0, -1, 1)))
            |> overlay(shift(sway, 0, line(12, 14, 10, 12, skinC(), empty())))  // 腕が力なく
            |> overlay(shift(sway, k, headDown(k)))                    // 頭が垂れ始める

    /// 膝から崩れ: 上体が沈み、脚が折れて膝立ちへ。斧は取り落とし地面に。
    def deathCollapse(k: Int32): Canvas =
        let sink = 3 + k * 2;                              // 体が沈む量
        empty()
            // 取り落とした斧（地面に転がる）
            |> line(3, 27, 7, 26, haft())
            |> overlay(axeHead(9, 25))
            // 膝立ちの胴（脚を折る = 短く）
            |> overlay(kneelBody(sink))
            |> overlay(line(13, 15 + sink, 11, 18 + sink, skinC(), empty()))  // 腕がだらり
            |> overlay(shift(0, sink, headDown(1)))

    /// 膝立ちのまま前傾してがくりとうなだれる（最終姿）。倒れ伏さない。
    def deathKneel(k: Int32): Canvas =
        let lean = k;                                     // k=1 でさらに前傾
        empty()
            // 取り落とした斧
            |> line(3, 27, 7, 26, haft())
            |> overlay(axeHead(9, 25))
            |> overlay(kneelBody(5))
            // うなだれた頭（前へ + 下へ）
            |> overlay(shift(lean, 5 + lean, headDown(1)))
            |> overlay(line(13, 20, 14 + lean, 23, skinC(), empty()))  // 前へ垂れた腕

    /// 膝立ちの胴（腰から下は折りたたまれ・膝が接地 y=29）。
    def kneelBody(sink: Int32): Canvas =
        let y = 13 + sink;
        empty()
            |> rectFill(12, y, 8, 5, tunic())
            |> vline(12, y, 5, tunicDk())
            |> hline(13, y + 4, 6, tunicDk())
            // 折った脚（膝が前・すねが下に接地）
            |> hline(13, 27, 2, tunicDk())                 // 左膝
            |> hline(17, 27, 2, tunicDk())                 // 右膝
            |> vline(13, 27, 2, tunicDk())                 // すね
            |> vline(18, 27, 2, tunicDk())
            |> hline(12, 29, 3, hairDk())                  // 足（接地 y=29）
            |> hline(17, 29, 3, hairDk())
}
