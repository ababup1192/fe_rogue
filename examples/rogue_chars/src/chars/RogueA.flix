// RogueA — フードのシーフ（短剣）。目深なフードで顔が影に沈み、口元と鋭い目だけがのぞく。
// しなやかな体・濃紺のマント・逆手の短剣。姿勢を低く沈めて忍び歩き、二連刺しで攻める。
//
// 色: night(マント本体) / plum(マント裏) / darkBrown(革ブーツ・輪郭・接地部) /
//      skin(のぞく顔) / silver(短剣) / red(フードの結び目・差し色)。
// 接地は必ず y=29。輪郭と足には night と同化しない darkBrown を使い、闇に溶けないようにする。

mod RogueA {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, discFill, arc, overlay}

    pub def name(): String = "ROGUE A 影より来たる短剣"

    // ── 色 ──
    def cloak(): Color = RoguePalette.night()       // マント本体（濃紺）
    def lining(): Color = RoguePalette.plum()       // マント裏・フードの内側の陰
    def leather(): Color = RoguePalette.darkBrown() // 革ブーツ・帯・輪郭（接地部）
    def flesh(): Color = RoguePalette.skin()        // のぞく顔・手
    def steel(): Color = RoguePalette.silver()      // 短剣の刃
    def accent(): Color = RoguePalette.red()        // フードの結び目・目の光の差し色
    def hilt(): Color = RoguePalette.darkBrown()    // 短剣の柄（革巻き）

    // ── 描画本体: 16 クリップを全部 match で分岐 ──
    pub def draw(clip: RogueStage.Clip, frame: Int32): Canvas =
        match clip {
            case RogueStage.Clip.IdleDown    => idleDown(wrap(frame, 4))
            case RogueStage.Clip.IdleUp      => idleUp(wrap(frame, 4))
            case RogueStage.Clip.IdleSide    => idleSide(wrap(frame, 4))
            case RogueStage.Clip.WalkDown    => walkDown(wrap(frame, 4))
            case RogueStage.Clip.WalkUp      => walkUp(wrap(frame, 4))
            case RogueStage.Clip.WalkSide    => walkSide(wrap(frame, 4))
            case RogueStage.Clip.AttackDown  => attackDown(wrap(frame, 6))
            case RogueStage.Clip.AttackUp    => attackUp(wrap(frame, 6))
            case RogueStage.Clip.AttackSide  => attackSide(wrap(frame, 6))
            case RogueStage.Clip.UseItemDown => useItemDown(wrap(frame, 4))
            case RogueStage.Clip.UseItemUp   => useItemUp(wrap(frame, 4))
            case RogueStage.Clip.UseItemSide => useItemSide(wrap(frame, 4))
            case RogueStage.Clip.DamageDown  => damageDown(wrap(frame, 3))
            case RogueStage.Clip.DamageUp    => damageUp(wrap(frame, 3))
            case RogueStage.Clip.DamageSide  => damageSide(wrap(frame, 3))
            case RogueStage.Clip.Death       => death(wrap(frame, 6))
        }

    /// フレーム番号を 0..n-1 に丸める（負数も正しく折り返す）。
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    // ════════════════════════════════════════════════════════════════
    //  頭部パーツ — 目深なフード。顔は影に沈み、鋭い目と口元だけのぞく。
    // ════════════════════════════════════════════════════════════════

    /// 正面フード（Down 向き）。頭頂 y=6 付近から始まり、目元まで深くかぶる。
    /// フードの陰(lining)を目の上に落とし、その下に顔(flesh)を細くのぞかせる。
    def hoodDown(): Canvas =
        empty()
            |> hline(13, 6, 6, cloak())                 // 頭頂の丸み
            |> hline(12, 7, 8, cloak())
            |> hline(11, 8, 10, cloak())                // フードが左右に張り出す
            |> hline(11, 9, 10, cloak())
            |> hline(11, 10, 10, cloak())
            |> vline(11, 11, 2, cloak())                // フードの両裾（頬を包む）
            |> vline(20, 11, 2, cloak())
            |> hline(13, 11, 6, lining())               // 目の上に落ちるフードの陰
            |> hline(13, 12, 6, flesh())                // のぞく顔（細い帯）
            |> (cv -> dot(14, 12, accent(), cv))        // 鋭い目（右）
            |> (cv -> dot(17, 12, accent(), cv))        // 鋭い目（左）
            |> hline(14, 13, 4, flesh())                // 口元
            |> (cv -> dot(15, 13, leather(), cv))       // 口の陰
            |> (cv -> dot(16, 13, leather(), cv))
            |> (cv -> dot(12, 7, accent(), cv))         // フード横の結び目（差し色）

    /// 背面フード（Up 向き）。後頭部の被り物の裏。顔は見えず、フードの縫い目だけ。
    def hoodUp(): Canvas =
        empty()
            |> hline(13, 6, 6, cloak())
            |> hline(12, 7, 8, cloak())
            |> hline(11, 8, 10, cloak())
            |> hline(11, 9, 10, cloak())
            |> hline(11, 10, 10, cloak())
            |> hline(11, 11, 10, cloak())
            |> hline(12, 12, 8, cloak())                // 後頭部はすっぽり覆う
            |> vline(15, 8, 5, lining())                // フードの中央縫い目（裏の陰）
            |> vline(16, 8, 5, lining())
            |> (cv -> dot(19, 7, accent(), cv))         // 結び目が後ろからのぞく

    /// 左向きフード（Side 向き）。フードの尖りが後方(右)へ流れ、前(左)に顔が細くのぞく。
    def hoodSide(): Canvas =
        empty()
            |> hline(13, 6, 6, cloak())
            |> hline(12, 7, 8, cloak())
            |> hline(11, 8, 9, cloak())
            |> hline(11, 9, 9, cloak())
            |> hline(11, 10, 9, cloak())
            |> (cv -> dot(20, 9, cloak(), cv))          // 後方へ尖るフードの先
            |> (cv -> dot(20, 10, cloak(), cv))
            |> vline(11, 11, 2, cloak())                // 前の裾（頬を包む）
            |> (cv -> dot(12, 11, lining(), cv))        // 目の上の陰
            |> (cv -> dot(13, 11, lining(), cv))
            |> hline(11, 12, 3, flesh())                // のぞく横顔（鼻先が左）
            |> (cv -> dot(12, 12, accent(), cv))        // 鋭い目
            |> (cv -> dot(11, 13, flesh(), cv))         // 口元
            |> (cv -> dot(12, 13, leather(), cv))
            |> (cv -> dot(18, 7, accent(), cv))         // 後ろの結び目

    // ════════════════════════════════════════════════════════════════
    //  胴・マント・脚パーツ
    // ════════════════════════════════════════════════════════════════

    /// 正面の胴とマント。肩 y=14 から裾 y=25 まで。裾(lining)だけが揺れる。
    /// dxHem で裾の左右揺れ、bob で全体の上下を与える（呼び側が shift 済みの前提）。
    def torsoDown(dxHem: Int32): Canvas =
        empty()
            |> hline(12, 14, 8, cloak())                // 肩
            |> hline(11, 15, 10, cloak())               // マントが肩から広がる
            |> rectFill(11, 16, 10, 7, cloak())         // マント本体 y=16..22
            |> vline(15, 15, 8, lining())               // 前合わせの陰（中央）
            |> vline(16, 15, 8, lining())
            |> hline(11 + dxHem, 23, 10, cloak())       // 裾 y=23
            |> hline(11 + dxHem, 24, 10, lining())      // 裾の裏地がめくれる y=24
            |> (cv -> dot(11 + dxHem, 25, lining(), cv))// 裾の角
            |> (cv -> dot(20 + dxHem, 25, lining(), cv))
            |> hline(13, 20, 6, leather())              // 帯（差し色でくびれを作る）

    /// 正面の脚（革ブーツ）。足元は必ず darkBrown・接地 y=29。
    /// lift= 上げる脚の側（0=両足接地, 1=右足上げ, 2=左足上げ）。
    def legsDown(lift: Int32): Canvas =
        let base =
            empty()
                |> vline(13, 26, 3, cloak())            // 右脚
                |> vline(18, 26, 3, cloak());
        match lift {
            case 1 =>                                    // 右足を一歩前へ
                base
                    |> hline(12, 29, 3, leather())       // 右ブーツ（前・接地）
                    |> hline(17, 28, 3, leather())       // 左ブーツ（浮き気味）
                    |> hline(17, 29, 3, leather())
            case 2 =>                                    // 左足を一歩前へ
                base
                    |> hline(12, 28, 3, leather())
                    |> hline(12, 29, 3, leather())
                    |> hline(17, 29, 3, leather())
            case _ =>                                    // 両足そろえて接地
                base
                    |> hline(12, 29, 3, leather())
                    |> hline(17, 29, 3, leather())
        }

    // ── 左向き（Side）の胴・脚 ──

    /// 左向きの胴とマント。マントは後方(右)へ長く垂れ、その裾だけ揺れる。
    def torsoSide(dxHem: Int32): Canvas =
        empty()
            |> hline(13, 14, 5, cloak())                // 肩
            |> rectFill(12, 15, 7, 8, cloak())          // 胴 y=15..22
            |> vline(19, 16, 7, cloak())                // 背中側のマントの張り
            |> vline(20, 17, 6, lining())               // マント裏（後方に流れる）
            |> hline(13 + dxHem, 23, 7, cloak())        // 裾
            |> hline(15 + dxHem, 24, 6, lining())       // 後方へ長い裾裏
            |> (cv -> dot(20 + dxHem, 24, lining(), cv))
            |> (cv -> dot(21 + dxHem, 23, lining(), cv))// 後ろへなびく先
            |> hline(13, 20, 5, leather())              // 帯

    /// 左向きの脚。step で前後の踏み出し（前脚=左x側, 後脚=右x側）。接地 y=29。
    def legsSide(step: Int32): Canvas =
        match step {
            case 1 =>                                    // 前脚を踏み出す
                empty()
                    |> vline(13, 26, 3, cloak())
                    |> vline(17, 26, 2, cloak())
                    |> hline(12, 29, 3, leather())       // 前ブーツ（接地）
                    |> hline(17, 28, 3, leather())       // 後ブーツ（つま先立ち気味）
                    |> hline(17, 29, 2, leather())
            case 2 =>                                    // 後脚を踏み出す
                empty()
                    |> vline(14, 26, 2, cloak())
                    |> vline(17, 26, 3, cloak())
                    |> hline(13, 28, 3, leather())
                    |> hline(13, 29, 2, leather())
                    |> hline(17, 29, 3, leather())
            case _ =>                                    // そろえて接地
                empty()
                    |> vline(14, 26, 3, cloak())
                    |> vline(17, 26, 3, cloak())
                    |> hline(13, 29, 3, leather())
                    |> hline(17, 29, 3, leather())
        }

    // ════════════════════════════════════════════════════════════════
    //  短剣パーツ — 常時見える主役。刃(steel)2px+ハイライト、柄(hilt)。
    // ════════════════════════════════════════════════════════════════

    /// 短剣を1本、点 (bx,by) を柄頭として角度方向に描く簡易版（逆手構え用）。
    /// ここでは向きごとに専用に置くので、汎用化せず各ポーズで直に描く。

    /// 逆手に短剣を構える手元（正面 Idle 用）。刃は下向きに沿わせる。
    def daggerDownGuard(): Canvas =
        empty()
            |> (cv -> dot(20, 18, flesh(), cv))         // 握る手
            |> (cv -> dot(21, 18, hilt(), cv))          // 柄
            |> vline(21, 19, 5, steel())                // 刃（下へ・逆手）
            |> vline(22, 19, 4, steel())
            |> vline(22, 19, 3, RoguePalette.white())   // 刃のハイライト

    // ════════════════════════════════════════════════════════════════
    //  IDLE — 姿勢を低く沈め、フードの奥で呼吸。逆手の短剣。
    // ════════════════════════════════════════════════════════════════

    /// 呼吸の上下: f0,f2=沈む / f1,f3=わずかに伸びる（±1px）。
    def breath(f: Int32): Int32 = if (f == 1 or f == 3) -1 else 0

    def idleDown(f: Int32): Canvas =
        let dy = breath(f);
        let body =
            torsoDown(0)
                |> overlay(hoodDown())
                |> overlay(armDownIdle(f))
                |> overlay(daggerDownGuard());
        PixelCanvas.shift(0, dy, body)
            |> overlay(legsDown(0))                     // 脚は動かさず接地を固定

    /// 正面 Idle の腕（肩から手へ2px・呼吸で微動）。
    def armDownIdle(f: Int32): Canvas =
        let dy = if (f == 1 or f == 3) -1 else 0;
        empty()
            |> line(12, 16, 11, 20 + dy, flesh())       // 左腕（体側に垂らす）
            |> line(19, 16, 20, 18 + dy, flesh())       // 右腕（短剣を握る側）

    def idleUp(f: Int32): Canvas =
        let dy = breath(f);
        let body =
            torsoDown(0)
                |> overlay(hoodUp())
                |> overlay(armDownIdle(f))
                |> overlay(daggerUpGuard());
        PixelCanvas.shift(0, dy, body)
            |> overlay(legsDown(0))

    /// 背面 Idle の短剣（逆手・後ろ手に隠すように刃を上へ）。
    def daggerUpGuard(): Canvas =
        empty()
            |> (cv -> dot(20, 17, hilt(), cv))
            |> vline(20, 13, 4, steel())                // 刃を上へ
            |> vline(21, 13, 4, steel())
            |> vline(20, 13, 3, RoguePalette.white())

    def idleSide(f: Int32): Canvas =
        let dy = breath(f);
        let body =
            torsoSide(0)
                |> overlay(hoodSide())
                |> overlay(armSideIdle(f))
                |> overlay(daggerSideGuard());
        PixelCanvas.shift(0, dy, body)
            |> overlay(legsSide(0))

    /// 左向き Idle の腕（前方=左へ短剣を低く構える）。
    def armSideIdle(f: Int32): Canvas =
        let dy = if (f == 1 or f == 3) -1 else 0;
        empty()
            |> line(13, 16, 10, 19 + dy, flesh())       // 前腕を低く前へ

    /// 左向き Idle の短剣（逆手・刃を前方=左下へ沿わせる）。
    def daggerSideGuard(): Canvas =
        empty()
            |> (cv -> dot(10, 19, hilt(), cv))
            |> line(9, 20, 9, 23, steel())              // 刃（下前方へ・逆手）
            |> line(10, 20, 10, 22, steel())
            |> (cv -> dot(9, 20, RoguePalette.white(), cv))
            |> (cv -> dot(9, 21, RoguePalette.white(), cv))

    // ════════════════════════════════════════════════════════════════
    //  WALK — 忍び足。頭はほぼ固定、マントの裾だけ揺れる。足は接地 y=29。
    // ════════════════════════════════════════════════════════════════

    def walkDown(f: Int32): Canvas =
        let hem = walkHem(f);
        let lift = walkLift(f);
        let bob = if (f == 1 or f == 3) -1 else 0;      // 上下は忍び足なので抑えめ
        let upper =
            torsoDown(hem)
                |> overlay(hoodDown())
                |> overlay(armDownWalk(f))
                |> overlay(daggerDownGuard());
        PixelCanvas.shift(0, bob, upper)
            |> overlay(legsDown(lift))                   // 脚は接地を保つ

    /// 裾の揺れ: f1=左, f3=右, f0/f2=中央。
    def walkHem(f: Int32): Int32 =
        if (f == 1) -1 else if (f == 3) 1 else 0

    /// 踏み出す足: f0/f1=右足前, f2/f3=左足前。
    def walkLift(f: Int32): Int32 =
        if (f == 0 or f == 1) 1 else 2

    /// 正面歩きの腕振り（歩幅に合わせ手を前後）。
    def armDownWalk(f: Int32): Canvas =
        let swing = if (f == 0 or f == 1) 1 else -1;
        empty()
            |> line(12, 16, 11 - swing, 20, flesh())    // 左腕
            |> line(19, 16, 20 + swing, 19, flesh())    // 右腕（短剣側）

    def walkUp(f: Int32): Canvas =
        let hem = walkHem(f);
        let lift = walkLift(f);
        let bob = if (f == 1 or f == 3) -1 else 0;
        let upper =
            torsoDown(hem)
                |> overlay(hoodUp())
                |> overlay(armDownWalk(f))
                |> overlay(daggerUpGuard());
        PixelCanvas.shift(0, bob, upper)
            |> overlay(legsDown(lift))

    def walkSide(f: Int32): Canvas =
        let hem = walkHem(f);
        let bob = if (f == 1 or f == 3) -1 else 0;
        let step = walkSideStep(f);
        let upper =
            torsoSide(hem)
                |> overlay(hoodSide())
                |> overlay(armSideWalk(f))
                |> overlay(daggerSideGuard());
        PixelCanvas.shift(0, bob, upper)
            |> overlay(legsSide(step))

    /// 左向き歩きの脚: f0=そろえ, f1=前踏み, f2=そろえ, f3=後踏み（f0とf3で左右非対称に）。
    def walkSideStep(f: Int32): Int32 =
        match f {
            case 0 => 0
            case 1 => 1
            case 2 => 0
            case _ => 2
        }

    /// 左向き歩きの腕振り（短剣を持つ前腕が前後に）。
    def armSideWalk(f: Int32): Canvas =
        let reach = if (f == 1) 1 else if (f == 3) -1 else 0;
        empty()
            |> line(13, 16, 10 - reach, 19, flesh())

    // ════════════════════════════════════════════════════════════════
    //  ATTACK — 姿勢を沈めての二連刺し。踏み込み→刺突→引き→もう一刺し。
    //  6コマ: f0 沈み込み / f1 一刺し目(伸びきり) / f2 引き戻し /
    //         f3 沈み直し / f4 二刺し目(さらに伸びる) / f5 引き上げ・残身
    //  刃の軌跡は arc/line で明色の鋭い短い弧。
    // ════════════════════════════════════════════════════════════════

    /// 沈み込みの深さ（低く踏み込むほど体が下がる）。刺突コマは低く前傾。
    def crouch(f: Int32): Int32 =
        match f {
            case 0 => 1     // 沈む
            case 1 => 2     // 一刺し（さらに低く踏み込む）
            case 2 => 1
            case 3 => 1
            case 4 => 2     // 二刺し
            case _ => 0     // 残身で戻す
        }

    def attackDown(f: Int32): Canvas =
        let cy = crouch(f);
        let upper =
            torsoDown(0)
                |> overlay(hoodDown())
                |> overlay(attackDownArm(f));
        // 沈み込みは上体だけ下げ、脚は接地を固定。
        PixelCanvas.shift(0, cy, upper)
            |> overlay(legsDown(if (f == 1 or f == 4) 1 else 0))
            |> overlay(attackDownDaggerAndTrail(f))

    /// 正面攻撃の腕（刺突コマは腕を大きく手前=下へ突き出す）。
    def attackDownArm(f: Int32): Canvas =
        match f {
            case 1 => line(19, 15, 22, 24, flesh(), empty())     // 一刺し・伸びきり
            case 4 => line(19, 15, 23, 25, flesh(), empty())     // 二刺し・さらに深く
            case 2 => line(19, 16, 20, 19, flesh(), empty())     // 引き
            case _ => line(19, 16, 21, 20, flesh(), empty())     // 構え
        }

    /// 短剣と刺突の軌跡（明色の短い弧/線）。刺突向き=手前(下)。
    def attackDownDaggerAndTrail(f: Int32): Canvas =
        match f {
            case 1 =>                                    // 一刺し目・下へ深く突く
                empty()
                    |> (cv -> dot(22, 23, hilt(), cv))
                    |> vline(22, 24, 5, steel())         // 刃
                    |> vline(23, 25, 4, steel())
                    |> vline(22, 24, 4, RoguePalette.white())
                    |> arc(22, 22, 6, 250, 290, RoguePalette.paleBlue()) // 突きの軌跡
            case 4 =>                                    // 二刺し目・さらに深く
                empty()
                    |> (cv -> dot(23, 24, hilt(), cv))
                    |> vline(23, 25, 5, steel())
                    |> vline(24, 26, 3, steel())
                    |> vline(23, 25, 4, RoguePalette.white())
                    |> arc(23, 23, 7, 250, 300, RoguePalette.white())
            case 2 =>                                    // 引き戻し
                empty()
                    |> (cv -> dot(20, 18, hilt(), cv))
                    |> vline(20, 19, 3, steel())
                    |> vline(20, 19, 2, RoguePalette.white())
            case _ => daggerDownGuard()                  // f0/f3/f5 は沈めた構え
        }

    def attackUp(f: Int32): Canvas =
        let cy = crouch(f);
        let upper =
            torsoDown(0)
                |> overlay(hoodUp())
                |> overlay(attackUpArm(f));
        PixelCanvas.shift(0, cy, upper)
            |> overlay(legsDown(if (f == 1 or f == 4) 2 else 0))
            |> overlay(attackUpDaggerAndTrail(f))

    def attackUpArm(f: Int32): Canvas =
        match f {
            case 1 => line(19, 15, 21, 8, flesh(), empty())       // 奥(上)へ突き上げ
            case 4 => line(19, 15, 22, 6, flesh(), empty())
            case 2 => line(19, 16, 20, 13, flesh(), empty())
            case _ => line(19, 16, 20, 14, flesh(), empty())
        }

    /// 背面攻撃の短剣と軌跡（刺突向き=奥/上）。
    def attackUpDaggerAndTrail(f: Int32): Canvas =
        match f {
            case 1 =>
                empty()
                    |> (cv -> dot(21, 8, hilt(), cv))
                    |> vline(21, 3, 5, steel())          // 上へ突く刃
                    |> vline(22, 3, 4, steel())
                    |> vline(21, 3, 4, RoguePalette.white())
                    |> arc(21, 9, 6, 70, 110, RoguePalette.paleBlue())
            case 4 =>
                empty()
                    |> (cv -> dot(22, 6, hilt(), cv))
                    |> vline(22, 1, 5, steel())
                    |> vline(23, 1, 3, steel())
                    |> vline(22, 1, 4, RoguePalette.white())
                    |> arc(22, 7, 7, 60, 120, RoguePalette.white())
            case 2 =>
                empty()
                    |> (cv -> dot(20, 13, hilt(), cv))
                    |> vline(20, 10, 3, steel())
                    |> vline(20, 11, 2, RoguePalette.white())
            case _ => daggerUpGuard()
        }

    def attackSide(f: Int32): Canvas =
        let cy = crouch(f);
        let upper =
            torsoSide(0)
                |> overlay(hoodSide())
                |> overlay(attackSideArm(f));
        PixelCanvas.shift(0, cy, upper)
            |> overlay(legsSide(if (f == 1 or f == 4) 1 else 0))
            |> overlay(attackSideDaggerAndTrail(f))

    /// 左向き攻撃の腕（刺突コマは前方=左へ大きく伸ばす）。
    def attackSideArm(f: Int32): Canvas =
        match f {
            case 1 => line(13, 15, 4, 18, flesh(), empty())       // 前方へ深く刺す
            case 4 => line(13, 15, 3, 19, flesh(), empty())       // 二刺し・さらに前へ
            case 2 => line(13, 16, 9, 18, flesh(), empty())        // 引き
            case _ => line(13, 16, 10, 18, flesh(), empty())       // 構え
        }

    /// 左向き攻撃の短剣と軌跡（刺突向き=前方/左）。刃と腕が大きな弧を描く。
    def attackSideDaggerAndTrail(f: Int32): Canvas =
        match f {
            case 1 =>                                    // 一刺し目・前方へ突き
                empty()
                    |> (cv -> dot(4, 18, hilt(), cv))
                    |> hline(0, 18, 4, steel())          // 刃（前へ伸びる）
                    |> hline(1, 19, 3, steel())
                    |> hline(0, 18, 3, RoguePalette.white())
                    |> arc(6, 18, 6, 150, 210, RoguePalette.paleBlue()) // 突きの弧
            case 4 =>                                    // 二刺し目・さらに前へ
                empty()
                    |> (cv -> dot(3, 19, hilt(), cv))
                    |> hline(0, 19, 3, steel())
                    |> hline(0, 20, 2, steel())
                    |> hline(0, 19, 3, RoguePalette.white())
                    |> arc(5, 19, 7, 150, 220, RoguePalette.white())
            case 2 =>                                    // 引き戻し
                empty()
                    |> (cv -> dot(9, 18, hilt(), cv))
                    |> hline(7, 18, 3, steel())
                    |> hline(7, 18, 2, RoguePalette.white())
            case _ => daggerSideGuard()
        }

    // ════════════════════════════════════════════════════════════════
    //  USE ITEM — 掲げる → 明色フラッシュ → 使う の3拍（+戻し）。
    //  短剣は腰に戻し、代わりに小瓶を掲げる。
    // ════════════════════════════════════════════════════════════════

    def useItemDown(f: Int32): Canvas =
        let body =
            torsoDown(0)
                |> overlay(hoodDown())
                |> overlay(useArmDown(f))
                |> overlay(daggerDownGuard());
        body |> overlay(legsDown(0)) |> overlay(itemDown(f))

    /// アイテムを掲げる腕（f1で高く上げる）。
    def useArmDown(f: Int32): Canvas =
        match f {
            case 0 => line(12, 16, 12, 12, flesh(), empty())      // 掲げ始め
            case 1 => line(12, 16, 13, 9, flesh(), empty())       // 高く掲げる
            case 2 => line(12, 16, 13, 10, flesh(), empty())      // フラッシュ
            case _ => line(12, 16, 13, 13, flesh(), empty())      // 使う（下ろす）
        }

    /// 掲げる小瓶。f2=明色フラッシュ。
    def itemDown(f: Int32): Canvas =
        match f {
            case 0 => empty() |> discFill(12, 11, 1, accent())
            case 1 => empty() |> discFill(13, 8, 1, accent()) |> (cv -> dot(13, 7, RoguePalette.white(), cv))
            case 2 =>                                    // フラッシュ（明色の輝き）
                empty()
                    |> discFill(13, 9, 2, RoguePalette.white())
                    |> (cv -> dot(13, 6, RoguePalette.paleBlue(), cv))
                    |> (cv -> dot(11, 9, RoguePalette.paleBlue(), cv))
                    |> (cv -> dot(15, 9, RoguePalette.paleBlue(), cv))
            case _ => empty() |> discFill(13, 12, 1, accent())
        }

    def useItemUp(f: Int32): Canvas =
        let body =
            torsoDown(0)
                |> overlay(hoodUp())
                |> overlay(useArmDown(f))
                |> overlay(daggerUpGuard());
        body |> overlay(legsDown(0)) |> overlay(itemDown(f))

    def useItemSide(f: Int32): Canvas =
        let body =
            torsoSide(0)
                |> overlay(hoodSide())
                |> overlay(useArmSide(f))
                |> overlay(daggerSideGuard());
        body |> overlay(legsSide(0)) |> overlay(itemSide(f))

    def useArmSide(f: Int32): Canvas =
        match f {
            case 0 => line(13, 16, 12, 12, flesh(), empty())
            case 1 => line(13, 16, 12, 9, flesh(), empty())
            case 2 => line(13, 16, 12, 10, flesh(), empty())
            case _ => line(13, 16, 12, 13, flesh(), empty())
        }

    def itemSide(f: Int32): Canvas =
        match f {
            case 0 => empty() |> discFill(12, 11, 1, accent())
            case 1 => empty() |> discFill(12, 8, 1, accent()) |> (cv -> dot(12, 7, RoguePalette.white(), cv))
            case 2 =>
                empty()
                    |> discFill(12, 9, 2, RoguePalette.white())
                    |> (cv -> dot(12, 6, RoguePalette.paleBlue(), cv))
                    |> (cv -> dot(10, 9, RoguePalette.paleBlue(), cv))
                    |> (cv -> dot(14, 9, RoguePalette.paleBlue(), cv))
            case _ => empty() |> discFill(12, 12, 1, accent())
        }

    // ════════════════════════════════════════════════════════════════
    //  DAMAGE — f0 全身白フラッシュ+ノックバック → のけぞり(2コマ)。
    //  Down=手前へ, Up=奥へ, Side=横へ。フードが少しめくれる。
    // ════════════════════════════════════════════════════════════════

    /// 全身シルエットを白1色で塗る（フラッシュ用）。base の全ピクセルを white に。
    def whiteFlash(base: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> Map.insert(k, RoguePalette.white(), acc), Map.empty(), base)

    def damageDown(f: Int32): Canvas =
        let pose =
            torsoDown(0)
                |> overlay(hoodDown())
                |> overlay(armDownIdle(0))
                |> overlay(daggerDownGuard())
                |> overlay(legsDown(0));
        match f {
            case 0 => PixelCanvas.shift(0, 2, whiteFlash(pose)) |> overlay(legsDown(0)) // 手前へ+白+足接地維持
            case 1 => PixelCanvas.shift(1, 1, pose) |> overlay(damageHoodFlip()) |> overlay(legsDown(0)) // のけぞり
            case _ => PixelCanvas.shift(0, 1, pose) |> overlay(legsDown(0))              // 戻り始め
        }

    /// のけぞりでフードが少しめくれる（後方へ1px）。
    def damageHoodFlip(): Canvas =
        empty()
            |> (cv -> dot(19, 6, lining(), cv))
            |> (cv -> dot(20, 7, lining(), cv))

    def damageUp(f: Int32): Canvas =
        let pose =
            torsoDown(0)
                |> overlay(hoodUp())
                |> overlay(armDownIdle(0))
                |> overlay(daggerUpGuard())
                |> overlay(legsDown(0));
        match f {
            case 0 => PixelCanvas.shift(0, -2, whiteFlash(pose)) |> overlay(legsDown(0)) // 奥へ
            case 1 => PixelCanvas.shift(-1, -1, pose) |> overlay(legsDown(0))
            case _ => PixelCanvas.shift(0, -1, pose) |> overlay(legsDown(0))
        }

    def damageSide(f: Int32): Canvas =
        let pose =
            torsoSide(0)
                |> overlay(hoodSide())
                |> overlay(armSideIdle(0))
                |> overlay(daggerSideGuard())
                |> overlay(legsSide(0));
        match f {
            case 0 => PixelCanvas.shift(2, 0, whiteFlash(pose)) |> overlay(legsSide(0)) // 横(後方)へ
            case 1 => PixelCanvas.shift(2, -1, pose) |> overlay(damageHoodFlip()) |> overlay(legsSide(0))
            case _ => PixelCanvas.shift(1, 0, pose) |> overlay(legsSide(0))
        }

    // ════════════════════════════════════════════════════════════════
    //  DEATH — 6コマ・正面のみ・膝どまり。
    //  よろめき(f0,f1) → 膝から崩れ(f2,f3) → 膝立ちのまま前傾がくり(f4,f5)。
    //  フードが脱げかけ、短剣を落とす。倒れ伏さない。
    // ════════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas =
        match f {
            case 0 => deathStagger(1)    // よろめき（右へ傾く）
            case 1 => deathStagger(-1)   // よろめき（戻し・逆へ）
            case 2 => deathCollapse(0)   // 膝から崩れ始め
            case 3 => deathCollapse(1)   // 膝をつく
            case 4 => deathKneel(0)      // 膝立ち前傾
            case _ => deathKneel(1)      // さらに前傾がくり（最終・膝立ちシルエット）
        }

    /// よろめき: 立ったまま体が左右に傾く。短剣はまだ握っている。
    def deathStagger(tilt: Int32): Canvas =
        let body =
            torsoDown(tilt)
                |> overlay(hoodDown())
                |> overlay(line(12, 16, 11, 21, flesh(), empty()))       // だらりと下がる腕
                |> overlay(line(19, 16, 21, 22, flesh(), empty()))
                |> overlay(daggerDownGuard());
        PixelCanvas.shift(tilt, 0, body)
            |> overlay(legsDown(0))                              // 足は接地を保つ

    /// 膝から崩れ: 上体が沈み、片膝が地に近づく。フードがめくれ始める。stage 0→1 で深く。
    def deathCollapse(stage: Int32): Canvas =
        let sink = 3 + stage * 2;                                // 上体を大きく沈める
        let hood = if (stage == 1) hoodSlipped() else hoodDown();
        let upper =
            torsoDown(0)
                |> overlay(hood)
                |> overlay(line(12, 16, 10, 22, flesh(), empty()))        // 崩れる腕
                |> overlay(line(19, 16, 22, 23, flesh(), empty()));
        PixelCanvas.shift(0, sink, upper)
            |> overlay(kneelLegs(stage))                          // 膝立ちの脚（接地）
            |> overlay(fallenDagger(stage))                       // 短剣を落とす

    /// 膝立ちのまま前傾してがくりと崩れる（最終形）。倒れ伏さず膝で止まる。
    def deathKneel(stage: Int32): Canvas =
        let lean = stage;                                         // さらに前傾（前へ1px）
        let sink = 6;
        let upper =
            torsoDown(0)
                |> overlay(hoodSlipped())                         // フード脱げかけ
                |> overlay(line(12, 16, 9 + lean, 23, flesh(), empty()))   // 前へ投げ出す腕
                |> overlay(line(19, 16, 21 + lean, 23, flesh(), empty()));
        PixelCanvas.shift(lean, sink, upper)
            |> overlay(kneelLegs(1))                              // 膝は地に・脛は接地 y=29
            |> overlay(fallenDagger(1))

    /// 脱げかけたフード（後方へずれ、後頭部の髪がのぞく=lining）。
    def hoodSlipped(): Canvas =
        empty()
            |> hline(14, 5, 6, cloak())                          // フードが後ろへずれ上がる
            |> hline(13, 6, 8, cloak())
            |> hline(13, 7, 8, cloak())
            |> hline(13, 8, 8, lining())                         // ずれた下からのぞく頭（陰）
            |> hline(13, 9, 6, flesh())                          // あらわになる顔
            |> (cv -> dot(14, 9, accent(), cv))                  // 見開いた目
            |> (cv -> dot(17, 9, accent(), cv))
            |> hline(14, 10, 4, flesh())

    /// 膝立ちの脚。膝(y=27付近)と脛が地面 y=29 に残る。stage で沈み具合。
    def kneelLegs(stage: Int32): Canvas =
        let base =
            empty()
                |> vline(13, 24, 3, cloak())                     // 立てた片膝の腿
                |> (cv -> dot(13, 27, leather(), cv))            // 膝頭
                |> hline(12, 28, 3, leather());                  // 立て膝の足
        // つく側の膝と脛は地面に沿う。
        base
            |> hline(16, 27, 3, cloak())                         // つく脚の腿（畳む）
            |> hline(16, 28, 4, leather())                       // 脛が地に沿う
            |> hline(16, 29, 5, leather())                       // 接地 y=29
            |> hline(12, 29, 3, leather())                       // 立て膝側の足も接地
            |> (cv -> dot(11 + stage, 29, leather(), cv))        // 崩れで足先が広がる

    /// 取り落とした短剣（地面近くに転がる）。stage 0=手放す途中, 1=床に落ちる。
    def fallenDagger(stage: Int32): Canvas =
        match stage {
            case 1 =>                                            // 床に転がる短剣
                empty()
                    |> (cv -> dot(21, 28, hilt(), cv))
                    |> hline(22, 28, 4, steel())                 // 刃が横倒しに
                    |> hline(23, 28, 2, RoguePalette.white())
            case _ =>                                            // 手から滑り落ちる途中
                empty()
                    |> (cv -> dot(22, 24, hilt(), cv))
                    |> vline(22, 25, 3, steel())
                    |> vline(22, 25, 2, RoguePalette.white())
        }
}
