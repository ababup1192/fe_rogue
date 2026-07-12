// KnightC — 白羽の儀礼姫騎士。
// 白いマント + ロイヤルブルーの軍服 + 白金の髪を頭頂で結った高いポニーテール + 白い羽飾り。
// 歩きはすり足（頭の高さは一定）。ポニーテールは体より一拍遅れて揺れるフォロースルー。
// 攻撃は踏み込んでの刺突：細い剣が一直線に伸び、切っ先に星の煌めき。
// 刃は白 1px + paleBlue の影 1px の 2 列組。白いマントに重なる行には
// さらに paleBlue の分離影を敷き、どのクリップでも剣が読めるようにする。
// Death は膝どまり：よろめき → 膝から崩れ → 膝立ちのまま前傾がくり（倒れ伏さない）。
//
// 使用色（RoguePalette）: white / paleBlue / royalBlue / navy / yellow / skin

mod KnightC {

    use PixelCanvas.{dot, hline, vline, rectFill, line, shift, overlay}

    pub def name(): String = "KNIGHT C 白羽の儀礼姫騎士"

    // 16 クリップ全てを方向別の本作画で持つ（Side 系は左向き・右は実行時 hflip）。
    pub def draw(clip: RogueStage.Clip, frame: Int32): PixelCanvas.Canvas =
        let f = clampFrame(clip, frame);
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

    // 範囲外 frame はクリップの有効範囲に丸める。
    def clampFrame(clip: RogueStage.Clip, frame: Int32): Int32 =
        Int32.max(0, Int32.min(frame, RogueStage.frameCount(clip) - 1))

    // ── 色（短い別名）──
    def cw(): Color = RoguePalette.white()      // マント・羽・白金の髪の明部・刃
    def cp(): Color = RoguePalette.paleBlue()   // 髪と刃の影・マントの陰・軌跡
    def cb(): Color = RoguePalette.royalBlue()  // 軍服
    def cn(): Color = RoguePalette.navy()       // 脚衣・目・柄
    def cy(): Color = RoguePalette.yellow()     // 金モール・鍔・髪留め
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

    // 頭（正面・白金の髪: 明部 white / 影 paleBlue）。blink=true で目を閉じる。
    def frontHead(blink: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> rectFill(13, 8, 6, 1, cw())
            |> rectFill(12, 9, 8, 2, cw())
            |> dot(12, 10, cp())
            |> dot(19, 10, cp())
            |> vline(12, 11, 5, cw())
            |> vline(19, 11, 5, cp())
            |> rectFill(13, 11, 6, 3, cs())
            |> hline(14, 14, 4, cs())
            |> hline(14, 15, 4, cw());
        if (blink) base else base |> dot(14, 12, cn()) |> dot(17, 12, cn())

    // 頭頂の高いポニーテール（正面）+ 白い羽飾り。swing は房の先の横ずれ（-1/0/1）。
    // 体の揺れより一拍遅らせて渡すとフォロースルー（遅れて付いてくる揺れ）になる。
    def frontPony(swing: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> dot(15, 7, cy())                                          // 金の髪留め
           |> dot(15 + swing, 6, cw()) |> dot(16 + swing, 6, cp())
           |> dot(15 + swing, 5, cw()) |> dot(16 + swing, 5, cp())
           |> dot(15 + swing, 4, cw())                                  // 房の先
           |> dot(17, 6, cw()) |> dot(18, 5, cw()) |> dot(18, 6, cp())  // 白い羽飾り

    // 肩の白い羽飾り（正面では向かって左肩）。flick=true で羽先が跳ねる。
    def frontPlume(flick: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> dot(10, 13, cw()) |> dot(11, 13, cw())
            |> dot(10, 14, cw()) |> dot(11, 14, cp())
            |> dot(10, 15, cw());
        if (flick) base |> dot(9, 12, cw()) else base

    // 儀礼剣（正面：向かって右で切っ先を上に保持）。sparkle=true で切っ先が煌めく。
    // 白マントと重なる行（16..18）に paleBlue の分離影を敷き、白い刃が溶けないようにする。
    def frontSword(sparkle: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let base = cv
            |> vline(20, 16, 3, cp())
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

    // ── IdleDown: 頭は静止、マント・羽・ポニーテールが揺れ、剣先が時折煌めく ──
    // ポニーテールはマントの sway（f1/f3）より一拍遅れて f2/f0 に振れる。
    def idleDown(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 1) -1 else if (f == 3) 1 else 0;
        let pony = if (f == 2) -1 else if (f == 0) 1 else 0;
        PixelCanvas.empty()
            |> frontMantle(sway)
            |> frontLegsIdle
            |> frontTorso
            |> frontSword(f == 3)
            |> frontArms(20)
            |> frontHead(f == 2)
            |> frontPony(pony)
            |> frontPlume(f == 1)

    // ── IdleUp: 背中一面の白マントの落ち感。ポニーテールが主役で呼吸に合わせて揺れる ──
    def idleUp(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 1) -1 else if (f == 3) 1 else 0;
        let pony = if (f == 2) -1 else if (f == 0) 1 else 0;
        PixelCanvas.empty()
            |> vline(10, 9, 6, cw())      // 左肩越しに立てた剣先（刃 1px + 影 1px）
            |> vline(11, 10, 5, cp())
            |> frontMantle(sway)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(pony)
            |> backPlume

    // ── IdleSide: 左向き。剣を前に提げ、瞬きと裾の流れだけで立ち姿を保つ ──
    def idleSide(f: Int32): PixelCanvas.Canvas =
        let hemFlow = if (f == 1) 1 else 0;
        let tail = if (f == 2) 1 else 0;
        PixelCanvas.empty()
            |> overlay(sideMantleC(hemFlow, f == 3))
            |> overlay(sideLegsC(1))
            |> overlay(sideTorsoC())
            |> overlay(sideHeadC(f != 2, tail))
            |> overlay(sidePlumeC(f == 1))
            |> overlay(sideArmSwordC())

    // ── WalkDown: すり足で頭は上下せず、脚と腕振り・マントの流れで歩きを見せる ──
    // ポニーテールは sway（f0/f2）より一拍遅れて f1/f3 に振れるフォロースルー。
    def walkDown(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let pony = if (f == 1) -1 else if (f == 3) 1 else 0;
        let handY = if (f == 0) 21 else if (f == 2) 19 else 20;
        let base = PixelCanvas.empty()
            |> frontMantle(sway)
            |> frontLegsStride(f)
            |> frontTorso
            |> frontSword(false)
            |> frontArms(handY)
            |> frontHead(false)
            |> frontPony(pony)
            |> frontPlume(f == 3);
        if (f == 3) base |> dot(10, 24, cw()) |> dot(21, 24, cw()) else base

    // ══════════════ 背面パーツ（IdleUp / WalkUp / AttackUp / UseItemUp / DamageUp）══════════════

    // 後頭部（白金の髪）。ポニーテールは backPony で別に重ねる。
    def backHead(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(13, 8, 6, 1, cw())
           |> rectFill(12, 9, 8, 7, cw())
           |> vline(19, 10, 6, cp())
           |> dot(12, 15, cp())

    // 背中へ長く落ちるポニーテール（背面の主役）+ 白い羽飾り。swing は房の横ずれ。
    // 白い髪・マントの上を通るので、両脇に paleBlue の影を敷いて輪郭を立てる。
    // 房の先は付け根の 2 倍振れて「遅れて付いてくる」重さを出す。
    def backPony(swing: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> dot(15, 7, cy())                                          // 金の髪留め
           |> dot(15, 6, cw()) |> dot(16, 6, cp())                      // 結び上の立ち上がり
           |> vline(14 + swing, 10, 10, cp())
           |> vline(15 + swing, 8, 13, cw())
           |> vline(16 + swing, 10, 10, cp())
           |> dot(15 + 2 * swing, 21, cw())
           |> dot(15 + 2 * swing, 22, cp())                             // 房の先
           |> dot(17, 6, cw()) |> dot(18, 5, cw()) |> dot(18, 6, cp())  // 白い羽飾り

    // 背面マントの落ち感（縦の折り目影 2 本）。
    def backMantleFolds(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> vline(12, 18, 6, cp())
           |> vline(19, 18, 6, cp())

    // 背面の羽飾り（向かって右肩）。
    def backPlume(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> dot(20, 13, cw()) |> dot(21, 13, cw())
           |> dot(21, 14, cw()) |> dot(20, 14, cp())
           |> dot(21, 15, cw())

    // ── WalkUp: 背中一面の白マント。剣の切っ先が左肩の上に覗き、尾が一拍遅れて振れる ──
    def walkUp(f: Int32): PixelCanvas.Canvas =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let pony = if (f == 1) -1 else if (f == 3) 1 else 0;
        let base = PixelCanvas.empty()
            |> vline(10, 9, 6, cw())
            |> vline(11, 10, 5, cp())
            |> frontMantle(sway)
            |> backMantleFolds
            |> frontLegsStride(f)
            |> backHead
            |> backPony(pony)
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

    // 頭（横・左向き・白金の髪）。open=false で目を閉じる。
    // tail はポニーテールの姿勢: -1=前へ跳ね返る / 0=垂れる / 1=後ろへ流れる。
    def sideHeadC(open: Bool, tail: Int32): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> rectFill(13, 8, 6, 1, cw())
            |> rectFill(12, 9, 8, 2, cw())
            |> dot(19, 9, cp()) |> dot(19, 10, cp())
            |> rectFill(12, 11, 4, 3, cs())
            |> rectFill(16, 11, 4, 3, cw())
            |> vline(19, 11, 3, cp())
            |> hline(13, 14, 3, cs())
            |> hline(16, 14, 2, cp())
            |> hline(13, 15, 4, cw())
            |> dot(16, 7, cy())            // 金の髪留め
            |> sidePony(tail);
        if (open) base |> dot(13, 12, cn()) else base

    // 横向きのポニーテール（頭頂から後ろへ）。
    def sidePony(tail: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas = match tail {
        case 1  => cv |> dot(17, 6, cw()) |> dot(18, 6, cw()) |> dot(19, 6, cp())
                      |> dot(20, 7, cw()) |> dot(21, 7, cp()) |> dot(22, 8, cw())
        case -1 => cv |> dot(16, 5, cw()) |> dot(17, 5, cp())
                      |> dot(15, 4, cw()) |> dot(16, 4, cp())
        case _  => cv |> dot(17, 6, cw()) |> dot(18, 7, cw()) |> dot(19, 7, cp())
                      |> dot(20, 8, cw()) |> dot(20, 9, cp())
                      |> dot(21, 10, cw()) |> dot(21, 11, cp())
    }

    // 羽飾り（横・後ろ髪の上に乗る）。白い髪と溶けないよう paleBlue の縁を敷く。
    def sidePlumeC(flick: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> dot(17, 10, cp())
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
            |> overlay(sideHeadC(true, 0))
            |> overlay(sidePlumeC(false))

    // ── WalkSide: すり足の滑走。脚は入れ替わるが頭の高さは不変、マントと尾が後ろに流れる ──
    def walkSide(f: Int32): PixelCanvas.Canvas =
        let hemFlow = if (f == 1) 1 else 0;
        let tail = if (Int32.remainder(f, 2) == 1) 1 else 0;   // 歩調の合間に尾が流れる
        PixelCanvas.empty()
            |> overlay(sideMantleC(hemFlow, f == 3))
            |> overlay(sideLegsC(f))
            |> overlay(sideTorsoC())
            |> overlay(sideHeadC(true, tail))
            |> overlay(sidePlumeC(f == 3))
            |> overlay(sideArmSwordC())

    // ══════════════ AttackSide: 踏み込みの刺突（6コマ）══════════════
    // f0-f1 溜め（剣を後ろへ引き絞る）→ f2-f3 突き（体ごと3px踏み込み・刃が一直線
    // に伸び切り、白い直線軌跡と切っ先の星）→ f4 引き戻し → f5 残心。

    def attackSide(f: Int32): PixelCanvas.Canvas = match f {
        case 0 => attackWind(false)
        case 1 => attackWind(true)
        case 2 => attackThrust(false)
        case 3 => attackThrust(true)
        case 4 => attackRecover()
        case _ => attackGuard()
    }

    // 溜め：半歩引いて剣を水平に後ろへ。deep で柄頭に光が走る。
    // 刃の上の行はマントの白と接するので paleBlue の分離影を敷く。
    def attackWind(deep: Bool): PixelCanvas.Canvas =
        let base = sideStand() |> shift(1, 0)
            |> rectFill(13, 16, 2, 2, cb())
            |> dot(14, 18, cs())
            |> vline(15, 18, 2, cy())
            |> hline(16, 17, 6, cp())
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
            |> overlay(sideHeadC(true, 1) |> shift(-3, 1))   // 尾は後ろへ流れ切る
            |> overlay(arm)
            |> overlay(star);
        if (hold)
            base |> hline(15, 17, 3, cp())
                 |> dot(2, 15, cw()) |> dot(2, 19, cw())
                 |> dot(0, 16, cw()) |> dot(0, 18, cw())
        else base

    // 引き戻し：体を起こし、刃を斜め上へ払い上げる。尾は前へ跳ね返るフォロースルー。
    def attackRecover(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> overlay(sideMantleC(1, false) |> shift(-1, 0))
            |> overlay(sideLegsC(1) |> shift(-1, 0))
            |> overlay(sideTorsoC() |> shift(-1, 0))
            |> overlay(sideHeadC(true, -1) |> shift(-1, 0))
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

    // ══════════════ AttackDown: 正面から手前への突き下ろし（6コマ）══════════════
    // f0-f1 頭上に振りかぶる → f2-f3 沈み込んで画面手前（右下）へ突き下ろす。
    // 通り道に淡青の直線残像を敷き、切っ先に星 → f4 引き戻し → f5 残心。

    def attackDown(f: Int32): PixelCanvas.Canvas = match f {
        case 0 => attackDownWind(false)
        case 1 => attackDownWind(true)
        case 2 => attackDownThrust(false)
        case 3 => attackDownThrust(true)
        case 4 => attackDownRecover()
        case _ => attackDownGuard()
    }

    // 振りかぶり：右腕で剣を頭上高くへ。deep で切っ先に光、尾は後ろへ引かれる。
    def attackDownWind(deep: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> frontMantle(-1)
            |> frontLegsIdle
            |> frontTorso
            |> frontHead(false)
            |> frontPony(if (deep) -1 else 0)
            |> frontPlume(false)
            |> rectFill(11, 17, 2, 3, cb())          // 左腕は体側
            |> dot(11, 20, cs())
            |> rectFill(19, 14, 2, 3, cb())          // 右腕を突き上げる
            |> dot(20, 13, cs()) |> dot(21, 13, cs())
            |> vline(21, 4, 8, cw())                 // 頭上の刃
            |> vline(22, 5, 7, cp())
            |> hline(20, 12, 3, cy());               // 鍔
        if (deep) base |> dot(21, 3, cw()) |> dot(20, 4, cw()) |> dot(22, 4, cw()) else base

    // 突き下ろし：体を 1px 沈め、頭上からの通り道に残像を敷いて切っ先は右下へ。
    // 尾は上へ跳ね上がるフォロースルー。
    def attackDownThrust(hold: Bool): PixelCanvas.Canvas =
        let upper = PixelCanvas.empty()
            |> frontMantle(1)
            |> frontTorso
            |> frontHead(false)
            |> frontPony(1)
            |> shift(0, 1);                          // 沈み込み（足は地面に残す）
        let base = PixelCanvas.empty()
            |> vline(21, 6, 12, cp())                // 振り下ろしの直線残像
            |> overlay(upper)
            |> frontLegsStride(0)
            |> rectFill(11, 19, 2, 3, cb())          // 左腕（沈んだ肩の位置）
            |> dot(11, 22, cs())
            |> dot(19, 19, cb()) |> dot(20, 19, cb())
            |> dot(20, 20, cb()) |> dot(21, 20, cb())    // 右腕を右下へ伸ばす
            |> dot(21, 21, cs()) |> dot(22, 21, cs())    // 手
            |> hline(22, 22, 2, cy())                    // 鍔
            |> line(23, 23, 26, 27, cw())                // 刃（右下へ一直線）
            |> line(24, 23, 27, 27, cp())
            |> dot(26, 26, cw()) |> dot(25, 27, cw())
            |> dot(27, 27, cw()) |> dot(26, 28, cw())
            |> dot(26, 27, cy());                        // 切っ先の星
        if (hold)
            base |> dot(28, 26, cw()) |> dot(24, 28, cw()) |> dot(28, 28, cw())
                 |> vline(20, 7, 10, cp())               // 残像が 1 列広がる
        else base

    // 引き戻し：体を起こし、刃を斜め上へ引き上げる。尾は前へ跳ね返る。
    def attackDownRecover(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> frontMantle(0)
            |> frontLegsIdle
            |> frontTorso
            |> frontHead(false)
            |> frontPony(-1)
            |> frontPlume(false)
            |> rectFill(11, 17, 2, 3, cb())
            |> dot(11, 20, cs())
            |> rectFill(19, 16, 2, 3, cb())
            |> dot(21, 18, cs())
            |> dot(21, 17, cy())                    // 鍔
            |> line(22, 16, 26, 10, cw())           // 刃を斜め上へ
            |> line(23, 16, 27, 10, cp())

    // 残心：正面の構えに戻り、切っ先の煌めきで締める。
    def attackDownGuard(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> frontMantle(0)
            |> frontLegsIdle
            |> frontTorso
            |> frontSword(true)
            |> frontArms(20)
            |> frontHead(false)
            |> frontPony(0)
            |> frontPlume(false)

    // ══════════════ AttackUp: 背面から奥への刺突（6コマ）══════════════
    // f0-f1 柄を右腰へ引き絞る → f2-f3 左肩越しに剣線が画面奥（左上）へ伸び、
    // 奥の切っ先に星 → f4 引き戻し → f5 残心（剣を肩に立て直す）。

    def attackUp(f: Int32): PixelCanvas.Canvas = match f {
        case 0 => attackUpWind(false)
        case 1 => attackUpWind(true)
        case 2 => attackUpThrust(false)
        case 3 => attackUpThrust(true)
        case 4 => attackUpRecover()
        case _ => attackUpGuard()
    }

    // 腰だめ：柄を右腰の後ろへ引き絞る。deep で切っ先に光、尾は前へ引かれる。
    def attackUpWind(deep: Bool): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> frontMantle(-1)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(if (deep) -1 else 0)
            |> backPlume
            |> rectFill(19, 17, 2, 2, cb())          // 右腕がマントの上に見える
            |> dot(21, 18, cs())
            |> dot(22, 18, cy())                     // 鍔
            |> line(23, 19, 26, 23, cw())            // 引き絞った刃は腰の後ろへ
            |> line(24, 19, 27, 23, cp());
        if (deep) base |> dot(26, 24, cw()) |> dot(27, 23, cw()) else base

    // 奥への刺突：踏み込み、左肩越しの剣線が画面奥（左上）へ伸び切る。
    // 尾は手前へ遅れて流れるフォロースルー。
    def attackUpThrust(hold: Bool): PixelCanvas.Canvas =
        let head = PixelCanvas.empty()
            |> backHead
            |> backPony(1)
            |> backPlume
            |> shift(0, -1);                         // 奥へ伸び上がる
        let base = PixelCanvas.empty()
            |> frontMantle(1)
            |> backMantleFolds
            |> frontLegsStride(0)
            |> overlay(head)
            |> hline(13, 15, 6, cw())                // 伸びた首元の髪を埋める
            |> dot(12, 14, cs())                     // 左手が肩の上に覗く
            |> dot(11, 13, cy())                     // 鍔
            |> line(10, 12, 4, 4, cw())              // 肩越しの剣線
            |> line(11, 12, 5, 4, cp())
            |> dot(4, 3, cw()) |> dot(3, 4, cw())
            |> dot(5, 4, cw()) |> dot(4, 5, cw())
            |> dot(4, 4, cy());                      // 奥の切っ先の星
        if (hold)
            base |> dot(2, 2, cw()) |> dot(6, 6, cp()) |> dot(2, 6, cw()) |> dot(6, 2, cw())
        else base

    // 引き戻し：刃が肩の高さへ戻る途中。尾は逆へ跳ね返る。
    def attackUpRecover(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> vline(10, 10, 7, cw())
            |> vline(11, 11, 6, cp())
            |> frontMantle(0)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(-1)
            |> backPlume

    // 残心：肩に剣を立てた背面の立ち姿。切っ先に名残の煌めき。
    def attackUpGuard(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> vline(10, 9, 6, cw())
            |> vline(11, 10, 5, cp())
            |> dot(10, 8, cw())
            |> frontMantle(0)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(0)
            |> backPlume

    // ══════════════ UseItemDown: 正面。小瓶を掲げ → 閃光 → 口元へ（4コマ）══════════════
    // 剣は右手に提げたまま（常時見える）。左手だけで小瓶を扱う。

    def useItemDown(f: Int32): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> frontMantle(0)
            |> frontLegsIdle
            |> frontTorso
            |> frontSword(false)
            |> rectFill(19, 17, 2, 3, cb())          // 右腕は柄を握ったまま
            |> dot(20, 20, cs()) |> dot(21, 20, cs())
            |> frontHead(false)
            |> frontPony(0)
            |> frontPlume(false);
        match f {
            case 0 => base
                |> rectFill(11, 16, 2, 2, cb())      // 左腕を持ち上げ始める
                |> dot(11, 15, cs())
                |> dot(11, 14, cp()) |> dot(11, 13, cw())   // 小瓶
            case 1 => base
                |> rectFill(10, 13, 2, 3, cb())      // 頭より高く掲げる
                |> dot(10, 12, cs())
                |> dot(10, 11, cp()) |> dot(10, 10, cw())
            case 2 => base
                |> rectFill(10, 13, 2, 3, cb())
                |> dot(10, 12, cs())
                |> rectFill(9, 9, 2, 2, cw())        // 閃光
                |> dot(9, 9, cy())
                |> dot(7, 8, cw()) |> dot(12, 7, cw())
                |> dot(7, 11, cw()) |> dot(13, 7, cw())
            case _ => base
                |> rectFill(11, 15, 2, 2, cb())      // 口元へ運ぶ
                |> dot(12, 14, cs())
                |> dot(12, 13, cp())                 // 口元の小瓶
                |> dot(10, 12, cw())                 // 残り火の煌めき
        }

    // ══════════════ UseItemUp: 背面。右手で小瓶を頭上へ掲げ → 閃光（4コマ）══════════════
    // 剣は左肩越しに立てたまま（常時見える）。

    def useItemUp(f: Int32): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> vline(10, 9, 6, cw())
            |> vline(11, 10, 5, cp())
            |> frontMantle(0)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(0)
            |> backPlume;
        match f {
            case 0 => base
                |> rectFill(20, 15, 2, 2, cb())      // 右腕を持ち上げ始める
                |> dot(21, 14, cs())
                |> dot(21, 13, cp()) |> dot(21, 12, cw())   // 小瓶
            case 1 => base
                |> rectFill(20, 12, 2, 3, cb())      // 頭より高く掲げる
                |> dot(21, 11, cs())
                |> dot(21, 10, cp()) |> dot(21, 9, cw())
            case 2 => base
                |> rectFill(20, 12, 2, 3, cb())
                |> dot(21, 11, cs())
                |> rectFill(20, 7, 2, 2, cw())       // 閃光
                |> dot(20, 7, cy())
                |> dot(23, 6, cw()) |> dot(24, 9, cw()) |> dot(21, 5, cw())
            case _ => base
                |> rectFill(20, 16, 2, 2, cb())      // 腕を下ろす
                |> dot(21, 15, cs())
                |> dot(22, 12, cp()) |> dot(23, 14, cw())   // 残り火の煌めき
        }

    // ══════════════ UseItemSide: 掲げる → 閃光 → 胸元で使う（3拍・4コマ）══════════════
    // 剣は前手に提げたまま、後ろ手で小瓶を頭上に掲げる。

    def useItemSide(f: Int32): PixelCanvas.Canvas =
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

    // ══════════════ Damage: 白フラッシュ → 後方ノックバック+のけぞり → 羽が1枚舞う（各3コマ）══════════════

    // 剣を握ったまま腕が垂れた被弾姿勢（横）。
    def looseArmSwordC(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> dot(12, 16, cb()) |> dot(12, 17, cb())
            |> dot(12, 18, cs())
            |> hline(10, 19, 3, cy())
            |> line(10, 20, 8, 25, cw())
            |> line(11, 20, 9, 25, cp())

    // ── DamageSide: 左向き。白フラッシュ+後方ノックバック → のけぞり → 羽が1枚舞う ──
    // f0 は全身を白で塗り潰した被弾フラッシュ。後方（右）へ 2px 弾かれる。
    def damageSide(f: Int32): PixelCanvas.Canvas = match f {
        case 0 =>
            sideStand()
                |> overlay(looseArmSwordC())
                |> shift(2, 0)
                |> Map.map(_ -> cw())
        case 1 => PixelCanvas.empty()
            |> overlay(sideMantleC(0, true) |> shift(2, 0))
            |> overlay(sideLegsC(1) |> shift(3, 0))
            |> overlay(sideTorsoC() |> shift(3, 0))
            |> overlay(sideHeadC(true, 1) |> shift(4, -1))   // 後ろへのけぞり・尾は後ろへ流れる
            |> overlay(sidePlumeC(true) |> shift(4, -1))
            |> overlay(looseArmSwordC() |> shift(3, 0))
            |> dot(12, 9, cw()) |> dot(13, 9, cw()) |> dot(13, 10, cp())   // 舞う羽（頭上）
        case _ => PixelCanvas.empty()
            |> overlay(sideMantleC(0, false) |> shift(2, 0))
            |> overlay(sideLegsC(1) |> shift(2, 0))
            |> overlay(sideTorsoC() |> shift(2, 0))
            |> overlay(sideHeadC(false, 0) |> shift(3, 1))   // 目を閉じ半戻り・尾は垂れる
            |> overlay(sidePlumeC(false) |> shift(3, 1))
            |> overlay(looseArmSwordC() |> shift(2, 0))
            |> dot(9, 14, cw()) |> dot(10, 14, cw()) |> dot(10, 15, cp())   // 羽が斜め下へ流れる
    }

    // 剣を握ったまま腕が垂れた被弾姿勢（正面）。柄を右手に提げたまま。
    def frontLooseSword(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> rectFill(11, 17, 2, 3, cb())              // 左腕は体側で脱力
           |> dot(11, 20, cs())
           |> rectFill(19, 18, 2, 2, cb())              // 右腕が垂れる
           |> dot(20, 20, cs()) |> dot(21, 20, cs())
           |> hline(20, 21, 2, cy())                    // 鍔
           |> vline(20, 22, 6, cw())                    // 提げた刃（白 1px）
           |> vline(21, 22, 6, cp())                    // 分離影（paleBlue 1px）

    // ── DamageDown: 正面。白シルエット+後方(下)ノックバック → のけぞり → 半戻り ──
    // f0 は全身を白で塗った被弾シルエット。手前（下）へ 2px 弾かれる。
    def damageDown(f: Int32): PixelCanvas.Canvas = match f {
        case 0 =>
            PixelCanvas.empty()
                |> frontMantle(0)
                |> frontLegsIdle
                |> frontTorso
                |> frontLooseSword
                |> frontHead(true)
                |> frontPony(0)
                |> frontPlume(false)
                |> shift(0, 2)                          // 手前へノックバック
                |> Map.map(_ -> cw())                   // 全身白シルエット
        case 1 => PixelCanvas.empty()
            |> frontMantle(1)                           // 裾がめくれる
            |> frontLegsIdle
            |> frontTorso
            |> frontLooseSword
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(-1, 1))   // 大きくのけぞる
            |> frontPony(-1)
            |> frontPlume(true)
            |> dot(9, 11, cw()) |> dot(10, 11, cw()) |> dot(10, 12, cp())       // 舞う羽（頭の脇）
        case _ => PixelCanvas.empty()
            |> frontMantle(0)
            |> frontLegsIdle
            |> frontTorso
            |> frontLooseSword
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 1))     // 半分戻る
            |> frontPony(1)
            |> frontPlume(false)
            |> dot(8, 15, cw()) |> dot(9, 15, cw()) |> dot(9, 16, cp())         // 羽が斜め下へ流れる
    }

    // ── DamageUp: 背面。白シルエット+奥(上)へよろめき → のけぞり → 半戻り ──
    // 左肩越しに立てた剣は常時見える。
    def damageUp(f: Int32): PixelCanvas.Canvas = match f {
        case 0 =>
            PixelCanvas.empty()
                |> vline(10, 9, 6, cw())                // 左肩越しの剣先
                |> vline(11, 10, 5, cp())
                |> frontMantle(0)
                |> backMantleFolds
                |> frontLegsIdle
                |> backHead
                |> backPony(0)
                |> backPlume
                |> shift(0, -1)                         // 奥（上）へよろめく
                |> Map.map(_ -> cw())                   // 全身白シルエット
        case 1 => PixelCanvas.empty()
            |> vline(10, 8, 6, cw())                    // 剣先も一緒に上へ
            |> vline(11, 9, 5, cp())
            |> frontMantle(-1)
            |> backMantleFolds
            |> frontLegsIdle
            |> overlay(backHead(PixelCanvas.empty()) |> shift(0, -1))   // 首をのけぞらせる
            |> backPony(-1)
            |> backPlume
            |> dot(9, 9, cw()) |> dot(10, 9, cw()) |> dot(10, 10, cp())  // 舞う羽（頭の脇）
        case _ => PixelCanvas.empty()
            |> vline(10, 9, 6, cw())
            |> vline(11, 10, 5, cp())
            |> frontMantle(0)
            |> backMantleFolds
            |> frontLegsIdle
            |> backHead
            |> backPony(1)                              // 尾が遅れて振れる
            |> backPlume
            |> dot(22, 13, cw()) |> dot(23, 13, cw()) |> dot(23, 14, cp())   // 羽が斜め下へ流れる
    }

    // ══════════════ Death: 膝どまりの見せ場（6コマ・正面）══════════════
    // f0-f1 よろめき（剣が手から離れ始める）→ f2-f3 膝から崩れ（マント拡がる・羽が舞う）
    // → f4-f5 膝立ちのまま前傾がくり（頭が落ちる・剣は足元に転がる）。
    // 倒れ伏さない。最終コマも膝立ちの立面シルエットが読める。

    def death(f: Int32): PixelCanvas.Canvas = match f {
        // f0: 直立からわずかによろめく。剣を握る手が緩み始める。
        case 0 => PixelCanvas.empty()
            |> frontMantle(1)
            |> frontLegsIdle
            |> frontTorso
            |> rectFill(11, 17, 2, 3, cb()) |> dot(11, 20, cs())    // 左腕は脱力
            |> rectFill(19, 18, 2, 2, cb())                        // 右手が下がる
            |> dot(20, 20, cs()) |> dot(21, 20, cs())
            |> hline(20, 21, 2, cy())                              // 鍔
            |> vline(20, 22, 6, cw()) |> vline(21, 22, 6, cp())    // 提げた剣（緩む握り）
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(-1, 0))   // 頭が傾く
            |> frontPony(1)
            |> frontPlume(false)
        // f1: よろめきが深まり、剣が手を離れて傾く。膝が緩み始める。
        case 1 => PixelCanvas.empty()
            |> frontMantle(1)
            |> frontLegsIdle
            |> frontTorso
            |> rectFill(11, 18, 2, 2, cb()) |> dot(11, 20, cs())   // 両腕が力なく下がる
            |> rectFill(19, 19, 2, 2, cb()) |> dot(20, 21, cs())
            |> dot(22, 20, cy())                                   // 離れゆく剣の鍔
            |> line(22, 21, 25, 27, cw())                          // 剣が斜めに傾き落ちかける
            |> line(23, 21, 26, 27, cp())
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(-1, 1))   // 頭が前に落ちる
            |> frontPony(-1)
            |> frontPlume(true)
            |> dot(9, 11, cw()) |> dot(10, 11, cw()) |> dot(10, 12, cp())      // 羽が1枚舞い始める
        // f2: 膝から崩れ始める。上体が沈み、マントが左右に拡がる。
        case 2 => PixelCanvas.empty()
            |> rectFill(10, 20, 12, 4, cw())                       // 拡がるマント
            |> hline(10, 24, 12, cp())
            |> dot(9, 21, cw()) |> dot(22, 21, cw())               // 裾の張り出し
            |> rectFill(14, 24, 2, 2, cn()) |> rectFill(16, 24, 2, 2, cn())    // 折り曲げた膝
            |> rectFill(13, 28, 3, 2, cw()) |> rectFill(16, 28, 3, 2, cw())    // 接地する足（白）
            |> overlay(frontTorso(PixelCanvas.empty()) |> shift(0, 4))
            |> rectFill(11, 22, 2, 2, cb()) |> dot(11, 24, cs())   // 沈んだ肩の左腕
            |> rectFill(19, 22, 2, 2, cb()) |> dot(20, 24, cs())   // 右腕
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 5))    // 頭がさらに落ちる
            |> overlay(frontPony(-1, PixelCanvas.empty()) |> shift(0, 5))
            |> dot(23, 27, cy())                                   // 足元に転がる剣の鍔
            |> hline(24, 27, 4, cw()) |> hline(24, 28, 4, cp())    // 転がった刃
            |> dot(8, 13, cw()) |> dot(9, 13, cw()) |> dot(9, 14, cp())        // 舞う羽
            |> dot(21, 10, cw()) |> dot(22, 10, cw())              // もう1枚の羽
        // f3: 膝立ちが定まる。上体が起き、マントが最も広がる。
        case 3 => PixelCanvas.empty()
            |> rectFill(10, 18, 12, 5, cw())                       // 最大に広がるマント
            |> hline(9, 23, 14, cp())
            |> dot(9, 19, cw()) |> dot(22, 19, cw())
            |> rectFill(13, 17, 6, 4, cb())                        // 軍服の胴（膝立ちで見える）
            |> hline(13, 21, 6, cy())
            |> rectFill(14, 23, 2, 2, cn()) |> rectFill(16, 23, 2, 2, cn())    // 膝
            |> rectFill(13, 28, 3, 2, cw()) |> rectFill(16, 28, 3, 2, cw())    // 接地する足
            |> rectFill(11, 18, 2, 3, cb()) |> dot(11, 21, cs())   // 垂れた左腕
            |> rectFill(19, 18, 2, 3, cb()) |> dot(20, 21, cs())   // 垂れた右腕
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 4))    // 頭が胸元に落ちる
            |> overlay(frontPony(0, PixelCanvas.empty()) |> shift(0, 4))
            |> dot(23, 27, cy())                                   // 足元の剣の鍔
            |> hline(24, 27, 4, cw()) |> hline(24, 28, 4, cp())
            |> dot(7, 12, cw()) |> dot(8, 12, cw()) |> dot(8, 13, cp())        // 高く舞う羽
            |> dot(24, 13, cw()) |> dot(25, 13, cw())
        // f4: 膝立ちのまま前傾のがくり。頭が深く落ちる。
        case 4 => PixelCanvas.empty()
            |> rectFill(11, 19, 10, 5, cw())                       // 前傾で狭まるマント
            |> hline(10, 24, 12, cp())
            |> rectFill(13, 18, 6, 3, cb())                        // 前かがみの胴
            |> hline(13, 20, 6, cy())
            |> rectFill(14, 24, 2, 2, cn()) |> rectFill(16, 24, 2, 2, cn())    // 膝
            |> rectFill(13, 28, 3, 2, cw()) |> rectFill(16, 28, 3, 2, cw())    // 接地する足
            |> rectFill(11, 20, 2, 3, cb()) |> dot(11, 23, cs())   // 前に垂れる腕
            |> rectFill(19, 20, 2, 3, cb()) |> dot(20, 23, cs())
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 6))    // 頭が深く前に落ちる
            |> overlay(frontPony(1, PixelCanvas.empty()) |> shift(0, 6))       // 尾が前へ垂れる
            |> dot(23, 27, cy())                                   // 足元の剣
            |> hline(24, 27, 4, cw()) |> hline(24, 28, 4, cp())
            |> dot(6, 15, cw()) |> dot(7, 15, cw()) |> dot(7, 16, cp())        // 舞い落ちる羽
            |> dot(25, 16, cw()) |> dot(26, 16, cw())
        // f5: 最終コマ。膝立ちのまま頭を深く垂れて静止（立面シルエットが読める）。
        case _ => PixelCanvas.empty()
            |> rectFill(11, 20, 10, 4, cw())                       // 垂れ落ちたマント
            |> hline(10, 24, 12, cp())
            |> rectFill(13, 19, 6, 3, cb())                        // うなだれた胴
            |> hline(13, 21, 6, cy())
            |> rectFill(14, 24, 2, 2, cn()) |> rectFill(16, 24, 2, 2, cn())    // 膝
            |> rectFill(13, 28, 3, 2, cw()) |> rectFill(16, 28, 3, 2, cw())    // 接地する足
            |> rectFill(11, 21, 2, 3, cb()) |> dot(11, 24, cs())   // 力なく垂れた腕
            |> rectFill(19, 21, 2, 3, cb()) |> dot(20, 24, cs())
            |> overlay(frontHead(true, PixelCanvas.empty()) |> shift(0, 7))    // 頭が最も低く落ちる
            |> overlay(frontPony(1, PixelCanvas.empty()) |> shift(0, 7))
            |> dot(23, 27, cy())                                   // 足元に転がる剣
            |> hline(24, 27, 4, cw()) |> hline(24, 28, 4, cp())
            |> dot(5, 19, cw()) |> dot(6, 19, cp())                // 名残の羽（静かに落ちる）
            |> dot(26, 18, cw()) |> dot(27, 18, cp())
    }
}
