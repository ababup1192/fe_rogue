// KnightC — 白羽の儀礼姫騎士。
// 白いマント + ロイヤルブルーの軍服 + 肩の白い羽飾り + 細い儀礼剣。
// 歩きはすり足（頭の高さは一定・マントと羽だけが揺れる）。
// 攻撃は踏み込んでの刺突：細い剣が一直線に伸び、切っ先に星の煌めき。
// Death は正面向きの見せ場：崩れ落ちてマントが広がり、羽が舞い、
// 白いマントが体を覆ううつ伏せの遺体で終わる。
//
// 使用色（RoguePalette）: white / paleBlue / royalBlue / navy / yellow / skin

mod KnightC {

    use PixelCanvas.{dot, hline, vline, rectFill, line, shift, overlay}

    pub def name(): String = "KNIGHT C 白羽の儀礼姫騎士"

    // v3 契約の暫定マイグレーション: 方向別（Down/Up/Side）は当面同じ絵を返す。
    // 方向ごとの本作画は次の改稿ラウンドで行う。
    pub def draw(clip: RogueStage.Clip, frame: Int32): PixelCanvas.Canvas =
        let f = clampFrame(clip, frame);
        match clip {
            case RogueStage.Clip.IdleDown    => idle(f)
            case RogueStage.Clip.IdleUp      => idle(f)
            case RogueStage.Clip.IdleSide    => idle(f)
            case RogueStage.Clip.WalkDown    => walkDown(f)
            case RogueStage.Clip.WalkUp      => walkUp(f)
            case RogueStage.Clip.WalkSide    => walkSide(f)
            case RogueStage.Clip.AttackDown  => attack(f)
            case RogueStage.Clip.AttackUp    => attack(f)
            case RogueStage.Clip.AttackSide  => attack(f)
            case RogueStage.Clip.UseItemDown => useItem(f)
            case RogueStage.Clip.UseItemUp   => useItem(f)
            case RogueStage.Clip.UseItemSide => useItem(f)
            case RogueStage.Clip.DamageDown  => damage(f)
            case RogueStage.Clip.DamageUp    => damage(f)
            case RogueStage.Clip.DamageSide  => damage(f)
            case RogueStage.Clip.Death       => death(f)
        }

    // 範囲外 frame はクリップの有効範囲に丸める。
    def clampFrame(clip: RogueStage.Clip, frame: Int32): Int32 =
        Int32.max(0, Int32.min(frame, RogueStage.frameCount(clip) - 1))

    // ── 色（短い別名）──
    def cw(): Color = RoguePalette.white()      // マント・羽・刃のハイライト
    def cp(): Color = RoguePalette.paleBlue()   // 刃の影・マントの陰・軌跡
    def cb(): Color = RoguePalette.royalBlue()  // 軍服
    def cn(): Color = RoguePalette.navy()       // 脚衣・目・柄
    def cy(): Color = RoguePalette.yellow()     // 金髪・金モール・鍔
    def cs(): Color = RoguePalette.skin()       // 顔・手

    // ══════════════ 正面パーツ（Idle / WalkDown / Death）══════════════

    // 白マント（肩から羽織る）。sway で裾が左右に流れる。
    def frontMantle(sway: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(11, 16, 10, 9, cw())
           |> hline(11 + sway, 25, 10, cw())
           |> dot(11 + sway, 25, cp())
           |> dot(20 + sway, 25, cp())

    // 軍服の胴（金の肩章・飾緒・ベルト）。
    def frontTorso(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(13, 16, 6, 5, cb())
           |> dot(13, 16, cy())
           |> dot(18, 16, cy())
           |> dot(15, 17, cy())
           |> dot(15, 19, cy())
           |> hline(13, 21, 6, cy())

    // 頭（金髪ロング・白い襟）。blink=true で目を閉じる。
    def frontHead(blink: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> rectFill(13, 8, 6, 1, cy())
            |> rectFill(12, 9, 8, 2, cy())
            |> vline(12, 11, 5, cy())
            |> vline(19, 11, 5, cy())
            |> rectFill(13, 11, 6, 3, cs())
            |> hline(14, 14, 4, cs())
            |> hline(14, 15, 4, cw());
        if (blink) base else base |> dot(14, 12, cn()) |> dot(17, 12, cn())

    // 肩の白い羽飾り（正面では向かって左肩）。flick=true で羽先が跳ねる。
    def frontPlume(flick: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> dot(10, 13, cw()) |> dot(11, 13, cw())
            |> dot(10, 14, cw()) |> dot(11, 14, cp())
            |> dot(10, 15, cw());
        if (flick) base |> dot(9, 12, cw()) else base

    // 儀礼剣（正面：向かって右で切っ先を上に保持）。sparkle=true で切っ先が煌めく。
    def frontSword(sparkle: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> vline(21, 9, 10, cw())
            |> vline(22, 10, 9, cp())
            |> hline(20, 19, 4, cy())
            |> dot(21, 20, cn())
            |> dot(21, 21, cn());
        if (sparkle)
            base |> dot(21, 7, cw()) |> dot(20, 8, cw()) |> dot(22, 8, cw()) |> dot(21, 8, cy())
        else base

    // 両腕（正面）。左手は handY で振り、右手は剣の柄を握る。
    def frontArms(handY: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(11, 17, 2, 3, cb())
           |> dot(11, handY, cs())
           |> rectFill(19, 17, 2, 3, cb())
           |> dot(20, 20, cs())
           |> dot(21, 20, cs())

    // 直立の脚（すり足の基本形）。
    def frontLegsIdle(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(14, 26, 2, 2, cn())
           |> rectFill(16, 26, 2, 2, cn())
           |> rectFill(13, 28, 3, 2, cw())
           |> rectFill(16, 28, 3, 2, cw())

    // 歩行の脚。0=左足前 / 2=右足前 / それ以外=揃え。すり足なので高さは変えない。
    def frontLegsStride(f: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas = match f {
        case 0 => cv |> rectFill(13, 26, 2, 2, cn()) |> rectFill(16, 26, 2, 2, cn())
                     |> rectFill(12, 28, 3, 2, cw()) |> rectFill(16, 28, 3, 2, cw())
        case 2 => cv |> rectFill(14, 26, 2, 2, cn()) |> rectFill(17, 26, 2, 2, cn())
                     |> rectFill(13, 28, 3, 2, cw()) |> rectFill(17, 28, 3, 2, cw())
        case _ => frontLegsIdle(cv)
    }

    // ── Idle: 頭は静止、マントと羽だけが揺れ、剣先が時折煌めく ──
    def idle(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 1) -1 else if (f == 3) 1 else 0;
        PixelCanvas.empty()
            |> frontMantle(sway)
            |> frontLegsIdle
            |> frontTorso
            |> frontSword(f == 3)
            |> frontArms(20)
            |> frontHead(f == 2)
            |> frontPlume(f == 1)

    // ── WalkDown: すり足で頭は上下せず、脚と腕振り・マントの流れで歩きを見せる ──
    def walkDown(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let handY = if (f == 0) 21 else if (f == 2) 19 else 20;
        let base = PixelCanvas.empty()
            |> frontMantle(sway)
            |> frontLegsStride(f)
            |> frontTorso
            |> frontSword(false)
            |> frontArms(handY)
            |> frontHead(false)
            |> frontPlume(f == 3);
        if (f == 3) base |> dot(10, 24, cw()) |> dot(21, 24, cw()) else base

    // ══════════════ 背面パーツ（WalkUp）══════════════

    // 後頭部と背に流れる金髪。
    def backHead(hairFlick: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> rectFill(13, 8, 6, 1, cy())
            |> rectFill(12, 9, 8, 7, cy())
            |> rectFill(14, 16, 4, 3, cy());
        if (hairFlick) base |> dot(13, 18, cy()) |> dot(12, 17, cy()) else base

    // 背面の羽飾り（向かって右肩）。
    def backPlume(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> dot(20, 13, cw()) |> dot(21, 13, cw())
           |> dot(21, 14, cw()) |> dot(20, 14, cp())
           |> dot(21, 15, cw())

    // ── WalkUp: 背中一面の白マント。剣の切っ先が左肩の上に覗く ──
    def walkUp(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let base = PixelCanvas.empty()
            |> vline(10, 9, 6, cw())
            |> vline(11, 10, 5, cp())
            |> frontMantle(sway)
            |> frontLegsStride(f)
            |> backHead(f == 3)
            |> backPlume;
        if (f == 3) base |> dot(10, 24, cw()) |> dot(21, 24, cw()) else base

    // ══════════════ 横向きパーツ（左向き・単独キャンバスとして作り overlay で重ねる）══════════════

    // マント（体の後ろ = 右側にたなびく）。
    def sideMantleC(hemFlow: Int32, billow: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> rectFill(17, 16, 4, 9, cw())
            |> hline(17 + hemFlow, 25, 4, cw())
            |> dot(17 + hemFlow, 25, cp())
            |> dot(20 + hemFlow, 25, cp());
        if (billow) base |> dot(21, 17, cw()) |> dot(21, 18, cw()) else base

    // 軍服の胴（横）。
    def sideTorsoC(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> rectFill(13, 16, 4, 5, cb())
            |> dot(14, 17, cy())
            |> hline(13, 21, 4, cy())

    // 頭（横・左向き）。open=false で目を閉じる。
    def sideHeadC(open: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> rectFill(13, 8, 6, 1, cy())
            |> rectFill(12, 9, 8, 2, cy())
            |> rectFill(12, 11, 4, 3, cs())
            |> rectFill(16, 11, 4, 3, cy())
            |> hline(13, 14, 3, cs())
            |> hline(16, 14, 2, cy())
            |> dot(17, 15, cy())
            |> dot(17, 16, cy())
            |> hline(13, 15, 4, cw());
        if (open) base |> dot(13, 12, cn()) else base

    // 羽飾り（横・後ろ髪の上に乗る）。
    def sidePlumeC(flick: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> dot(18, 10, cw()) |> dot(19, 10, cw())
            |> dot(19, 11, cw()) |> dot(18, 11, cp());
        if (flick) base |> dot(20, 9, cw()) else base

    // 脚（横）。0=前脚前 / 2=逆脚前 / それ以外=揃え。すり足で高さ一定。
    def sideLegsC(pose: Int32): PixelCanvas.Canvas = match pose {
        case 0 => PixelCanvas.empty()
            |> hline(13, 22, 4, cn())
            |> rectFill(12, 23, 2, 5, cn())
            |> rectFill(16, 23, 2, 5, cn())
            |> rectFill(11, 28, 3, 2, cw())
            |> rectFill(16, 28, 3, 2, cw())
        case 2 => PixelCanvas.empty()
            |> hline(13, 22, 4, cn())
            |> rectFill(11, 23, 2, 5, cn())
            |> rectFill(15, 23, 2, 5, cn())
            |> rectFill(10, 28, 3, 2, cw())
            |> rectFill(15, 28, 3, 2, cw())
        case _ => PixelCanvas.empty()
            |> hline(13, 22, 4, cn())
            |> rectFill(14, 23, 3, 5, cn())
            |> rectFill(13, 28, 4, 2, cw())
    }

    // 前腕 + 儀礼剣（携行姿勢：切っ先を斜め前下に下げて持つ）。
    def sideArmSwordC(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> rectFill(12, 16, 2, 3, cb())
            |> dot(12, 19, cs())
            |> hline(10, 20, 4, cy())
            |> line(11, 21, 8, 26, cw())
            |> line(12, 21, 9, 26, cp())

    // 素体（腕・剣なし）。攻撃/ダメージが shift して流用する。
    def sideStand(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> overlay(sideMantleC(0, false))
            |> overlay(sideLegsC(1))
            |> overlay(sideTorsoC())
            |> overlay(sideHeadC(true))
            |> overlay(sidePlumeC(false))

    // ── WalkSide: すり足の滑走。脚は入れ替わるが頭の高さは不変、マントが後ろに流れる ──
    def walkSide(f: Int32): PixelCanvas.Canvas =
        let hemFlow = if (f == 1) 1 else 0;
        PixelCanvas.empty()
            |> overlay(sideMantleC(hemFlow, f == 3))
            |> overlay(sideLegsC(f))
            |> overlay(sideTorsoC())
            |> overlay(sideHeadC(true))
            |> overlay(sidePlumeC(f == 3))
            |> overlay(sideArmSwordC())

    // ══════════════ Attack: 踏み込みの刺突（6コマ）══════════════
    // f0-f1 溜め（剣を後ろへ引き絞る）→ f2-f3 突き（体ごと3px踏み込み・刃が一直線
    // に伸び切り、白い直線軌跡と切っ先の星）→ f4 引き戻し → f5 残心。

    def attack(f: Int32): PixelCanvas.Canvas = match f {
        case 0 => attackWind(false)
        case 1 => attackWind(true)
        case 2 => attackThrust(false)
        case 3 => attackThrust(true)
        case 4 => attackRecover()
        case _ => attackGuard()
    }

    // 溜め：半歩引いて剣を水平に後ろへ。deep で柄頭に光が走る。
    def attackWind(deep: Bool): PixelCanvas.Canvas =
        let base = sideStand() |> shift(1, 0)
            |> rectFill(13, 16, 2, 2, cb())
            |> dot(14, 18, cs())
            |> vline(15, 18, 2, cy())
            |> hline(16, 18, 6, cw())
            |> hline(16, 19, 6, cp());
        if (deep) base |> dot(22, 17, cw()) |> dot(23, 18, cw()) |> dot(22, 19, cw()) else base

    // 突き：ランジで沈み込み、刃と腕が一直線。軌跡は白+淡青の連続バンド3px幅。
    def attackThrust(hold: Bool): PixelCanvas.Canvas =
        let trail = PixelCanvas.empty()
            |> hline(6, 16, 9, cp())
            |> hline(6, 17, 10, cw())
            |> hline(6, 18, 9, cp());
        let mantleStream = PixelCanvas.empty()
            |> rectFill(14, 14, 7, 4, cw())
            |> hline(15, 18, 6, cp())
            |> dot(21, 15, cw())
            |> dot(22, 16, cp());
        let legs = PixelCanvas.empty()
            |> line(11, 23, 8, 26, cn())
            |> line(12, 23, 9, 26, cn())
            |> dot(7, 27, cn()) |> dot(8, 27, cn())
            |> line(13, 23, 17, 26, cn())
            |> line(13, 24, 17, 27, cn())
            |> rectFill(6, 28, 3, 2, cw())
            |> rectFill(17, 28, 3, 2, cw());
        let arm = PixelCanvas.empty()
            |> hline(7, 17, 4, cb())
            |> hline(7, 18, 4, cb())
            |> dot(6, 17, cs()) |> dot(6, 18, cs())
            |> vline(5, 16, 3, cy())
            |> hline(1, 17, 4, cw())
            |> hline(1, 18, 4, cp());
        let star = PixelCanvas.empty()
            |> dot(0, 17, cw()) |> dot(1, 16, cw())
            |> dot(1, 18, cw()) |> dot(2, 17, cw())
            |> dot(1, 17, cy());
        let base = trail
            |> overlay(mantleStream)
            |> overlay(legs)
            |> overlay(sideTorsoC() |> shift(-3, 1))
            |> overlay(sideHeadC(true) |> shift(-3, 1))
            |> overlay(arm)
            |> overlay(star);
        if (hold)
            base |> hline(15, 17, 3, cp())
                 |> dot(2, 15, cw()) |> dot(2, 19, cw())
                 |> dot(0, 16, cw()) |> dot(0, 18, cw())
        else base

    // 引き戻し：体を起こし、刃を斜め上へ払い上げる。
    def attackRecover(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> overlay(sideMantleC(1, false) |> shift(-1, 0))
            |> overlay(sideLegsC(1) |> shift(-1, 0))
            |> overlay(sideTorsoC() |> shift(-1, 0))
            |> overlay(sideHeadC(true) |> shift(-1, 0))
            |> overlay(sidePlumeC(false) |> shift(-1, 0))
            |> dot(11, 16, cb()) |> dot(12, 16, cb()) |> dot(12, 17, cb())
            |> dot(11, 17, cs())
            |> hline(10, 18, 3, cy())
            |> line(9, 16, 5, 10, cw())
            |> line(10, 16, 6, 10, cp())

    // 残心：切っ先を天へ立てる構え。
    def attackGuard(): PixelCanvas.Canvas =
        sideStand()
            |> rectFill(12, 16, 2, 3, cb())
            |> dot(11, 20, cs()) |> dot(12, 20, cs())
            |> vline(10, 11, 8, cw())
            |> vline(11, 12, 7, cp())
            |> hline(9, 19, 4, cy())
            |> dot(10, 21, cn())

    // ══════════════ UseItem: 掲げる → 閃光 → 胸元で使う（3拍・4コマ）══════════════
    // 剣は前手に提げたまま、後ろ手で小瓶を頭上に掲げる。

    def useItem(f: Int32): PixelCanvas.Canvas =
        let base = sideStand() |> overlay(sideArmSwordC());
        match f {
            case 0 => base
                |> dot(16, 15, cb()) |> dot(17, 14, cb())
                |> dot(17, 13, cs())
                |> dot(17, 12, cp()) |> dot(18, 12, cp())
                |> dot(17, 11, cw())
            case 1 => base
                |> dot(16, 15, cb()) |> dot(16, 14, cb()) |> dot(16, 13, cb())
                |> dot(16, 12, cs())
                |> dot(16, 11, cp()) |> dot(17, 11, cp())
                |> dot(16, 10, cw())
            case 2 => base
                |> dot(16, 15, cb()) |> dot(16, 14, cb()) |> dot(16, 13, cb())
                |> dot(16, 12, cs())
                |> rectFill(16, 10, 2, 2, cw())
                |> dot(16, 9, cy()) |> dot(17, 12, cy())
                |> dot(16, 7, cw()) |> dot(17, 7, cw())
                |> dot(13, 10, cw()) |> dot(14, 10, cw())
                |> dot(19, 10, cw()) |> dot(20, 10, cw())
                |> dot(15, 8, cw()) |> dot(18, 8, cw())
            case _ => base
                |> dot(16, 15, cb())
                |> dot(15, 16, cs())
                |> dot(14, 16, cp())
                |> dot(14, 15, cw())
                |> dot(13, 13, cp()) |> dot(12, 14, cw())
        }

    // ══════════════ Damage: 白フラッシュ → 後方ノックバック+のけぞり → 羽が1枚舞う ══════════════

    // 剣を握ったまま腕が垂れた被弾姿勢。
    def looseArmSwordC(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> dot(12, 16, cb()) |> dot(12, 17, cb())
            |> dot(12, 18, cs())
            |> hline(10, 19, 3, cy())
            |> line(10, 20, 8, 25, cw())
            |> line(11, 20, 9, 25, cp())

    def damage(f: Int32): PixelCanvas.Canvas = match f {
        case 0 =>
            sideStand()
                |> overlay(looseArmSwordC())
                |> shift(2, 0)
                |> Map.map(_ -> cw())
        case 1 => PixelCanvas.empty()
            |> overlay(sideMantleC(0, true) |> shift(2, 0))
            |> overlay(sideLegsC(1) |> shift(3, 0))
            |> overlay(sideTorsoC() |> shift(3, 0))
            |> overlay(sideHeadC(true) |> shift(4, -1))
            |> overlay(sidePlumeC(true) |> shift(4, -1))
            |> overlay(looseArmSwordC() |> shift(3, 0))
            |> dot(12, 9, cw()) |> dot(13, 9, cw()) |> dot(13, 10, cp())
        case _ => PixelCanvas.empty()
            |> overlay(sideMantleC(0, false) |> shift(2, 0))
            |> overlay(sideLegsC(1) |> shift(2, 0))
            |> overlay(sideTorsoC() |> shift(2, 0))
            |> overlay(sideHeadC(false) |> shift(3, 1))
            |> overlay(sidePlumeC(false) |> shift(3, 1))
            |> overlay(looseArmSwordC() |> shift(2, 0))
            |> dot(9, 14, cw()) |> dot(10, 14, cw()) |> dot(10, 15, cp())
    }

    // ══════════════ Death: 正面向きの見せ場（8コマ）══════════════
    // よろめき → 膝が落ちる → 深い崩れ・マント拡がる → 前のめりに宙 → 着地バウンド+土煙
    // → 沈み込み → 白いマントの遺体+落剣 → 羽が全て落ちて静止。

    def death(f: Int32): PixelCanvas.Canvas = match f {
        case 0 => PixelCanvas.empty()
            |> frontMantle(1)
            |> frontLegsIdle
            |> frontTorso
            |> line(22, 11, 25, 18, cw())
            |> line(23, 11, 26, 18, cp())
            |> hline(21, 19, 3, cy())
            |> frontArms(20)
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(-1, 0))
            |> frontPlume(false)
            |> dot(10, 11, cw())
        case 1 => PixelCanvas.empty()
            |> overlay(frontMantle(0, PixelCanvas.empty()) |> shift(0, 2))
            |> dot(13, 26, cn()) |> dot(14, 26, cn()) |> dot(13, 27, cn())
            |> dot(17, 26, cn()) |> dot(18, 26, cn()) |> dot(18, 27, cn())
            |> rectFill(12, 28, 3, 2, cw())
            |> rectFill(17, 28, 3, 2, cw())
            |> overlay(frontTorso(PixelCanvas.empty()) |> shift(0, 2))
            |> rectFill(11, 19, 2, 3, cb()) |> dot(11, 22, cs())
            |> rectFill(19, 19, 2, 3, cb()) |> dot(20, 22, cs())
            |> dot(22, 19, cy())
            |> line(22, 20, 25, 26, cw())
            |> line(23, 20, 26, 26, cp())
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 2))
            |> overlay(frontPlume(false, PixelCanvas.empty()) |> shift(0, 2))
            |> dot(9, 10, cw()) |> dot(10, 10, cw()) |> dot(10, 11, cp())
        case 2 => PixelCanvas.empty()
            |> rectFill(9, 22, 14, 5, cw())
            |> hline(9, 27, 14, cp())
            |> rectFill(12, 28, 3, 2, cw())
            |> rectFill(17, 28, 3, 2, cw())
            |> overlay(frontTorso(PixelCanvas.empty()) |> shift(0, 5))
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 5))
            |> overlay(frontPlume(false, PixelCanvas.empty()) |> shift(0, 5))
            |> dot(10, 22, cb()) |> dot(9, 23, cb()) |> dot(9, 24, cs())
            |> dot(21, 22, cb()) |> dot(22, 23, cb()) |> dot(22, 24, cs())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
            |> dot(8, 12, cw()) |> dot(9, 12, cw()) |> dot(9, 13, cp())
            |> dot(20, 9, cw()) |> dot(21, 9, cw())
        case 3 => PixelCanvas.empty()
            |> rectFill(10, 14, 12, 4, cw())
            |> hline(10, 18, 12, cp())
            |> rectFill(13, 18, 6, 3, cb())
            |> rectFill(13, 21, 6, 3, cy())
            |> dot(11, 21, cb()) |> dot(11, 22, cb()) |> dot(10, 23, cs())
            |> dot(20, 21, cb()) |> dot(20, 22, cb()) |> dot(21, 23, cs())
            |> rectFill(14, 24, 4, 3, cn())
            |> dot(14, 27, cn()) |> dot(17, 27, cn())
            |> rectFill(13, 28, 2, 2, cw())
            |> rectFill(17, 28, 2, 2, cw())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
            |> dot(7, 13, cw()) |> dot(8, 13, cw()) |> dot(8, 14, cp())
            |> dot(23, 10, cw()) |> dot(24, 10, cw())
        case 4 => PixelCanvas.empty()
            |> rectFill(13, 22, 6, 2, cy())
            |> rectFill(10, 24, 12, 3, cw())
            |> hline(10, 27, 12, cp())
            |> dot(10, 25, cb()) |> dot(8, 25, cs()) |> dot(9, 25, cs())
            |> dot(21, 25, cb()) |> dot(22, 25, cs())
            |> dot(12, 27, cn()) |> dot(19, 27, cn())
            |> dot(8, 28, cp()) |> dot(7, 29, cw()) |> dot(9, 29, cp())
            |> dot(27, 28, cw()) |> dot(28, 29, cp())
            |> dot(6, 17, cw()) |> dot(7, 17, cw())
            |> dot(25, 14, cw()) |> dot(26, 14, cw()) |> dot(26, 15, cp())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
        case 5 => PixelCanvas.empty()
            |> rectFill(13, 24, 6, 2, cy())
            |> rectFill(10, 26, 12, 3, cw())
            |> hline(10, 29, 12, cp())
            |> dot(10, 27, cb()) |> dot(8, 27, cs()) |> dot(9, 27, cs())
            |> dot(21, 27, cb()) |> dot(22, 27, cs())
            |> dot(7, 29, cp()) |> dot(27, 29, cp())
            |> dot(5, 22, cw()) |> dot(6, 22, cw())
            |> dot(26, 19, cw()) |> dot(27, 19, cw())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
        case 6 => PixelCanvas.empty()
            |> hline(12, 25, 8, cw())
            |> hline(10, 26, 11, cw())
            |> rectFill(9, 27, 12, 2, cw())
            |> hline(10, 29, 11, cp())
            |> rectFill(7, 27, 3, 2, cy())
            |> dot(8, 26, cy())
            |> dot(14, 24, cw()) |> dot(15, 24, cp())
            |> dot(25, 20, cw()) |> dot(26, 20, cw())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
        case _ => PixelCanvas.empty()
            |> hline(12, 25, 8, cw())
            |> hline(10, 26, 11, cw())
            |> rectFill(9, 27, 12, 2, cw())
            |> hline(9, 29, 13, cp())
            |> rectFill(6, 27, 3, 2, cy())
            |> dot(8, 26, cy()) |> dot(5, 29, cy()) |> dot(9, 29, cy())
            |> dot(21, 26, cb()) |> dot(22, 26, cs()) |> dot(23, 26, cs())
            |> dot(21, 28, cy())
            |> hline(22, 28, 5, cw())
            |> hline(22, 29, 5, cp())
            |> dot(13, 24, cw()) |> dot(14, 24, cp())
            |> dot(4, 28, cw()) |> dot(5, 28, cp())
            |> dot(27, 26, cw()) |> dot(28, 26, cp())
    }
}
