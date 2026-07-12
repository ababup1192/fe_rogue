// KnightA — パイロットキャラ「歴戦の若きロード」。
// 黒髪ショートに金の細いサークレット（額 1px・後頭部まで一周）、
// 青いサーコート（royalBlue）に銀の胸当て（silver）、片手剣。姿勢が良く、
// 待機でも剣を提げて刃がきらめく。剣が主役: 全クリップで刃 2px + ハイライト
// 1px が常時見え、攻撃は大振りかぶり → 3px 幅の連続した弧の斬撃。
//
// 作画はパーツ合成: 頭・胴・腕・脚・剣を部品 Canvas で作り、overlay/shift で
// ポーズを組む。腕は胴（x=12..19）の外側 x=10..11 / 20..21 に 2px 幅で置き、
// 胴から独立して読めるようにする。アンカーは RogueStage の規約
// （足元 y=29・中心 x=15..16・横向きは左向き作画）。
// 接地する部位（ブーツ・膝・転がる剣）には背景 #222034 と同化する night を使わない。

mod KnightA {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, rectFill, hline, vline, line, arc, shift, overlay}
    use RogueStage.Clip

    pub def name(): String = "Knight A"

    // ── 配色（DB32 のロール名。TestLint が全ピクセルの所属を検査する）──
    def ol(): Color = RoguePalette.night()          // 目・ベルト（非接地部のみ）
    def bootC(): Color = RoguePalette.plum()        // ブーツ（背景の night と混ざらない暗色）
    def coatC(): Color = RoguePalette.royalBlue()   // サーコート・腕
    def shadeC(): Color = RoguePalette.navy()       // 裾の影・脚
    def steelC(): Color = RoguePalette.silver()     // 胸当て・剣身
    def glintC(): Color = RoguePalette.paleBlue()   // 刃のハイライト・斬撃の弧（外側）
    def trailC(): Color = RoguePalette.cyan()       // 斬撃の弧（内側）
    def skinC(): Color = RoguePalette.skin()        // 顔・手
    def hairC(): Color = RoguePalette.black()       // 黒髪ショート
    def circletC(): Color = RoguePalette.yellow()   // 金の細いサークレット（額と後頭部を一周）
    def hiltC(): Color = RoguePalette.darkBrown()   // 剣の柄・小瓶のコルク
    def potionC(): Color = RoguePalette.salmon()    // 小瓶（UseItem）
    def sparkC(): Color = RoguePalette.white()      // 被弾フラッシュ・剣のきらめき
    def starC(): Color = RoguePalette.yellow()      // 衝撃の星（Death）
    def dustC(): Color = RoguePalette.gray()        // 倒れ込みの土煙

    // 3 方向すべて本作画。UseItemSide だけは正面の飲み芝居を共用する
    // （掲げて飲む芝居は向きより手元が主役で、正面絵が最も読めるため）。
    pub def draw(clip: Clip, frame: Int32): Canvas = match clip {
        case Clip.IdleDown    => idle(frame)
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
        case Clip.UseItemSide => useItemDown(frame)
        case Clip.DamageDown  => damageDown(frame)
        case Clip.DamageUp    => damageUp(frame)
        case Clip.DamageSide  => damageSide(frame)
        case Clip.Death       => death(frame)
    }

    // ══ 正面のパーツ（Idle / WalkDown / UseItem / Death）══

    /// 正面の頭（黒髪ショート・両目・額に金のサークレット 1px）。y=7..13。
    def headFront(): Canvas =
        empty()
            |> hline(13, 7, 6, hairC())
            |> hline(12, 8, 8, hairC())
            |> hline(12, 9, 8, circletC())
            |> dot(12, 10, hairC()) |> hline(13, 10, 6, skinC()) |> dot(19, 10, hairC())
            |> hline(12, 11, 8, skinC())
            |> hline(12, 12, 8, skinC())
            |> hline(13, 13, 6, skinC())
            |> dot(13, 11, ol()) |> dot(18, 11, ol())
            |> dot(13, 12, ol()) |> dot(18, 12, ol())

    /// 正面の胴（腕なし・x=12..19 の 8px 幅）: 肩線・胸当て・ベルト・サーコート。y=14..23。
    /// 腕はこの外側（x=10..11 / 20..21）に置くので、胴と混ざらず読める。
    def torsoFrontCore(): Canvas =
        empty()
            |> hline(11, 14, 10, steelC())
            |> rectFill(12, 15, 8, 3, steelC())
            |> dot(13, 15, glintC()) |> dot(14, 16, glintC())
            |> hline(12, 18, 8, ol())
            |> rectFill(12, 19, 8, 4, coatC())
            |> hline(12, 23, 8, shadeC())

    /// 正面の腕（左右共用・x は腕の左端・2px 幅）。raise>0 で前振り（上へ）、
    /// raise<0 で後ろ振り（下へ）。肩 y=16 から手 y=19 まで。
    def armFront(x: Int32, raise: Int32): Canvas =
        empty()
            |> rectFill(x, 16 - raise, 2, 3, coatC())
            |> hline(x, 19 - raise, 2, skinC())

    /// 正面の剣持ち腕（彼の右手 = 画面左）。手が柄（x=8..9）へ届く。
    def swordArmFront(): Canvas =
        empty() |> rectFill(10, 16, 2, 3, coatC()) |> hline(9, 19, 2, skinC())

    /// 正面の脚 1 本（x は左端・3px 幅）。lift=1 で足を 1px 持ち上げる。底は y=29。
    def legFront(x: Int32, lift: Int32): Canvas =
        empty()
            |> rectFill(x, 24, 3, 3 - lift, shadeC())
            |> rectFill(x, 27 - lift, 3, 3, bootC())

    def legsFrontAt(xL: Int32, xR: Int32, liftL: Int32, liftR: Int32): Canvas =
        overlay(legFront(xL, liftL), legFront(xR, liftR))

    def legsFront(liftL: Int32, liftR: Int32): Canvas =
        legsFrontAt(12, 17, liftL, liftR)

    // ══ 剣のパーツ ══

    /// 縦持ちの剣: 刃 2px（steel）+ 左縁のハイライト 1px（glint）+ 切っ先の光 + 鍔 + 柄。
    /// x = ハイライト列。yTip = 刃の上端、yGuard = 鍔の行（手はそのすぐ下）。
    def swordUpright(x: Int32, yTip: Int32, yGuard: Int32): Canvas =
        let len = yGuard - yTip;
        empty()
            |> vline(x, yTip + 1, len - 1, glintC())
            |> vline(x + 1, yTip, len, steelC())
            |> vline(x + 2, yTip + 1, len - 1, steelC())
            |> dot(x + 1, yTip - 1, glintC())
            |> hline(x - 1, yGuard, 5, steelC())
            |> vline(x + 1, yGuard + 1, 2, hiltC())

    /// 斜め持ちの剣: 刃（steel）+ 上縁のハイライト（glint）の 2px 幅。柄 (hx,hy)・切っ先 (tx,ty)。
    def swordHeld(hx: Int32, hy: Int32, tx: Int32, ty: Int32): Canvas =
        empty()
            |> line(hx, hy - 1, tx, ty - 1, glintC())
            |> line(hx, hy, tx, ty, steelC())
            |> dot(tx, ty - 1, glintC())
            |> dot(hx, hy, hiltC())

    // ══ 背面のパーツ（WalkUp）══

    /// 背面の頭（黒髪一色・サークレットは後頭部にも一周して見える）。y=7..13。
    def headBack(): Canvas =
        empty()
            |> hline(13, 7, 6, hairC())
            |> hline(12, 8, 8, hairC())
            |> hline(12, 9, 8, circletC())
            |> rectFill(12, 10, 8, 3, hairC())
            |> hline(14, 13, 4, skinC())

    /// 背面の胴（たすき掛けの背帯）。幅は正面と同じ x=12..19。
    def torsoBack(): Canvas =
        empty()
            |> hline(11, 14, 10, steelC())
            |> rectFill(12, 15, 8, 3, steelC())
            |> line(12, 15, 19, 17, ol())
            |> hline(12, 18, 8, ol())
            |> rectFill(12, 19, 8, 4, coatC())
            |> hline(12, 23, 8, shadeC())

    /// 背面の剣持ち腕（彼の右手 = 背面では画面右）。手が柄（x=22..23）へ届く。
    def swordArmBack(): Canvas =
        empty() |> rectFill(20, 16, 2, 3, coatC()) |> hline(21, 19, 2, skinC())

    // ══ 横向きのパーツ（左向き。WalkSide / Attack / Damage）══

    /// 横向きの頭。顔は前方 x=12..14・後頭部は髪。サークレットの帯が y=9 を一周。y=7..13。
    def headSide(): Canvas =
        empty()
            |> hline(13, 7, 6, hairC())
            |> hline(12, 8, 8, hairC())
            |> hline(12, 9, 8, circletC())
            |> hline(12, 10, 3, skinC()) |> hline(15, 10, 5, hairC())
            |> hline(12, 11, 3, skinC()) |> hline(15, 11, 4, hairC())
            |> hline(12, 12, 4, skinC()) |> hline(16, 12, 2, hairC())
            |> hline(13, 13, 3, skinC())
            |> dot(13, 11, ol())

    /// 横向きの胴（腕なし）。幅 6（x=12..17）・y=14..23。
    def torsoSideCore(): Canvas =
        empty()
            |> hline(12, 14, 6, steelC())
            |> rectFill(12, 15, 6, 3, steelC())
            |> dot(13, 15, glintC())
            |> hline(12, 18, 6, ol())
            |> rectFill(12, 19, 6, 4, coatC())
            |> hline(12, 23, 6, shadeC())

    /// 横向きの腕。sw で前後に振る（前 = 負・facing 左）。肩 y=16 から手 y=19。
    def armSideSwing(sw: Int32): Canvas =
        empty()
            |> rectFill(14 + sw, 16, 2, 3, coatC())
            |> hline(14 + sw, 19, 2, skinC())

    /// 横向きの脚 1 本。腿の左端 xTop・足の左端 xFoot で開脚を表す（3px 幅・底 y=29）。
    def legSide(xTop: Int32, xFoot: Int32): Canvas =
        empty()
            |> rectFill(xTop, 24, 3, 2, shadeC())
            |> line(xTop + 1, 26, xFoot + 1, 27, shadeC())
            |> rectFill(xFoot, 28, 3, 2, bootC())

    /// 横向きの立ち脚（前後の脚をほぼ揃える）。
    def legsSideStand(): Canvas =
        overlay(legSide(13, 12), legSide(14, 15))

    // ══ Idle: 4 コマ・呼吸で肩が ±1px 上下 + 刃のきらめきが走る ══

    def idle(f: Int32): Canvas =
        let breathe = if (f == 2 or f == 3) 1 else 0;
        let shimmerY = match f {
            case 0 => 9
            case 1 => 11
            case 2 => 13
            case _ => 11
        };
        let sword = swordUpright(7, 8, 18) |> dot(8, shimmerY, sparkC());
        let upper =
            overlay(sword, overlay(swordArmFront(),
                overlay(armFront(20, 0), overlay(torsoFrontCore(), headFront()))))
            |> shift(0, breathe);
        overlay(upper, legsFront(0, 0))

    // ══ IdleUp: 背中と後頭部。呼吸で肩まわりが ±1px 上下し、右手の剣がきらめく ══

    def idleUp(f: Int32): Canvas =
        let breathe = if (f == 2 or f == 3) 1 else 0;
        let shimmerY = match f {
            case 0 => 9
            case 1 => 11
            case 2 => 13
            case _ => 11
        };
        let sword = swordUpright(22, 8, 18) |> dot(23, shimmerY, sparkC());
        let upper =
            overlay(sword, overlay(swordArmBack(),
                overlay(armFront(10, 0), overlay(torsoBack(), headBack()))))
            |> shift(0, breathe);
        overlay(upper, legsFront(0, 0))

    // ══ IdleSide: 左向き。剣は体の前の下段提げで、刃をきらめきが走り下りる ══

    def idleSide(f: Int32): Canvas =
        let breathe = if (f == 2 or f == 3) 1 else 0;
        let (sx, sy) = match f {
            case 0 => (11, 20)
            case 1 => (9, 21)
            case 2 => (7, 23)
            case _ => (9, 21)
        };
        let core = overlay(torsoSideCore(), headSide());
        let sword = swordHeld(13, 20, 6, 25) |> dot(sx, sy, sparkC());
        let up = overlay(sword, overlay(armSideSwing(0), core)) |> shift(0, breathe);
        overlay(up, legsSideStand())

    // ══ WalkDown: 4 コマ全部違う絵（脚の運び + 腕振り + 剣の上下 + 体の沈み）══

    def walkDown(f: Int32): Canvas =
        let (legs, bob, raiseL, raiseR) = match f {
            case 0 => (legsFrontAt(12, 17, 1, 0), 0, 1, -1)
            case 1 => (legsFrontAt(12, 17, 0, 0), 1, 0, 0)
            case 2 => (legsFrontAt(12, 17, 0, 1), 0, -1, 1)
            case _ => (legsFrontAt(13, 16, 0, 0), 1, 0, 0)
        };
        let sword = overlay(swordUpright(7, 8, 18), swordArmFront()) |> shift(0, -raiseL);
        let upper =
            overlay(sword, overlay(armFront(20, raiseR),
                overlay(torsoFrontCore(), headFront())))
            |> shift(0, bob);
        overlay(upper, legs)

    // ══ WalkUp: 背中。剣は彼の右手（画面右）に提げたまま腕振り ══

    def walkUp(f: Int32): Canvas =
        let (legs, bob, raiseL, raiseR) = match f {
            case 0 => (legsFrontAt(12, 17, 1, 0), 0, 1, -1)
            case 1 => (legsFrontAt(12, 17, 0, 0), 1, 0, 0)
            case 2 => (legsFrontAt(12, 17, 0, 1), 0, -1, 1)
            case _ => (legsFrontAt(13, 16, 0, 0), 1, 0, 0)
        };
        let sword = overlay(swordUpright(22, 8, 18), swordArmBack()) |> shift(0, -raiseR);
        let upper =
            overlay(sword, overlay(armFront(10, raiseL),
                overlay(torsoBack(), headBack())))
            |> shift(0, bob);
        overlay(upper, legs)

    // ══ WalkSide: 歩幅 7px の開脚 ⇄ すれ違い + 体の上下 1px + 腕振り + 剣が前方で揺れる ══

    def walkSide(f: Int32): Canvas =
        let core = overlay(torsoSideCore(), headSide());
        match f {
            case 0 =>
                let up = overlay(swordHeld(11, 20, 4, 24), overlay(armSideSwing(-2), core))
                    |> shift(0, 1);
                overlay(up, overlay(legSide(13, 10), legSide(14, 17)))
            case 1 =>
                let up = overlay(swordHeld(13, 20, 6, 25), overlay(armSideSwing(0), core));
                overlay(up, overlay(legSide(13, 12), legSide(14, 15)))
            case 2 =>
                let up = overlay(swordHeld(15, 20, 8, 26), overlay(armSideSwing(2), core))
                    |> shift(0, 1);
                overlay(up, overlay(legSide(13, 16), legSide(14, 11)))
            case _ =>
                let up = overlay(swordHeld(14, 20, 7, 25), overlay(armSideSwing(1), core));
                overlay(up, overlay(legSide(13, 13), legSide(14, 14)))
        }

    // ══ AttackSide: 大振りかぶり（剣が頭上〜背後）→ 3px 幅の弧の斬撃 → 追い斬り → 戻り ══

    def attackSide(f: Int32): Canvas =
        let core = overlay(torsoSideCore(), headSide());
        match f {
            case 0 =>
                // 構え: 剣を前上段へ持ち上げ、体はわずかに引く。
                let arm = empty() |> rectFill(15, 13, 2, 2, coatC()) |> dot(16, 12, skinC());
                let up = overlay(swordHeld(17, 11, 22, 5), overlay(arm, core)) |> shift(1, 0);
                overlay(up, legsSideStand())
            case 1 =>
                // 振りかぶり最大: 剣が頭上を越えて背後まで倒れる。体は 2px 後傾、切っ先に溜めの光。
                let arm = empty() |> rectFill(16, 11, 2, 2, coatC()) |> dot(17, 10, skinC());
                let blade = empty()
                    |> line(18, 8, 26, 2, glintC())
                    |> line(18, 9, 26, 3, steelC())
                    |> line(18, 10, 26, 4, steelC())
                    |> dot(18, 10, hiltC())
                    |> dot(26, 2, sparkC());
                let up = overlay(blade, overlay(arm, core)) |> shift(2, 0);
                overlay(up, overlay(legSide(13, 12), legSide(14, 16)))
            case 2 =>
                // 斬撃インパクト: 2px 踏み込み + 大開脚。頭上背後から前方下段まで、
                // 3px 幅の連続した弧（外 2 本 = paleBlue・内 1 本 = cyan）が走る。
                let arm = empty() |> hline(10, 16, 4, coatC()) |> dot(9, 16, skinC());
                let blade = empty()
                    |> line(9, 16, 2, 20, glintC())
                    |> line(9, 17, 2, 21, steelC())
                    |> line(9, 18, 2, 22, steelC())
                    |> dot(9, 17, hiltC())
                    |> dot(2, 20, sparkC());
                let slash = empty()
                    |> line(25, 6, 19, 2, glintC()) |> line(19, 2, 12, 1, glintC())
                    |> line(12, 1, 5, 4, glintC()) |> line(5, 4, 1, 10, glintC())
                    |> line(24, 7, 19, 3, glintC()) |> line(19, 3, 12, 2, glintC())
                    |> line(12, 2, 6, 5, glintC()) |> line(6, 5, 2, 11, glintC())
                    |> line(23, 8, 18, 4, trailC()) |> line(18, 4, 12, 3, trailC())
                    |> line(12, 3, 7, 6, trailC()) |> line(7, 6, 3, 12, trailC())
                    |> dot(1, 11, sparkC());
                let up = overlay(blade, overlay(arm, core)) |> shift(-2, 0);
                overlay(slash, overlay(up, overlay(legSide(12, 8), legSide(15, 18))))
            case 3 =>
                // 振り抜き: 剣は下段前へ抜け、弧の下半分が cyan の残光として残る。
                let arm = empty() |> rectFill(11, 17, 2, 2, coatC()) |> dot(11, 19, skinC());
                let blade = empty()
                    |> line(10, 18, 4, 24, glintC())
                    |> line(10, 19, 4, 25, steelC())
                    |> line(11, 19, 5, 25, steelC())
                    |> dot(10, 19, hiltC())
                    |> dot(4, 24, glintC());
                let after = empty()
                    |> line(2, 12, 3, 18, trailC()) |> line(3, 18, 6, 23, trailC());
                let up = overlay(blade, overlay(arm, core)) |> shift(-2, 1);
                overlay(after, overlay(up, overlay(legSide(12, 9), legSide(15, 17))))
            case 4 =>
                // 戻し: 足を寄せながら剣を引き上げる。
                let up = overlay(swordHeld(12, 19, 6, 24), overlay(armSideSwing(-1), core))
                    |> shift(-1, 0);
                overlay(up, overlay(legSide(13, 11), legSide(14, 16)))
            case _ =>
                // 構え直し: 歩き携行と同じ下段前の持ちへ戻る。
                let up = overlay(swordHeld(13, 20, 6, 25), overlay(armSideSwing(0), core));
                overlay(up, legsSideStand())
        }

    // ══ AttackDown: 正面。頭上に立てた剣を手前（画面下）へ振り下ろし、
    // 左半身の外を回る大弧（外 = paleBlue 2 本・内 = cyan）が画面下端まで走る ══

    def attackDown(f: Int32): Canvas =
        let base = overlay(torsoFrontCore(), headFront());
        match f {
            case 0 =>
                // 構え: 剣腕を胸の高さへ引き上げ、剣は斜め上を向く。
                let arm = empty() |> rectFill(10, 15, 2, 2, coatC()) |> dot(10, 14, skinC());
                let blade = swordHeld(9, 13, 4, 6);
                let up = overlay(arm, overlay(blade, base));
                overlay(up, overlay(armFront(20, 0), legsFront(0, 0)))
            case 1 =>
                // 振りかぶり最大: 頭の左脇で剣が垂直に立ち、切っ先に溜めの光。
                let blade = swordUpright(8, 1, 9) |> dot(12, 1, sparkC());
                let arm = empty() |> rectFill(10, 12, 2, 3, coatC()) |> hline(9, 11, 2, skinC());
                let up = overlay(arm, overlay(blade, base));
                overlay(up, overlay(armFront(20, 0), legsFront(0, 0)))
            case 2 =>
                // 斬撃インパクト: 体が 1px 沈み、剣が左下段へ走る。頭上から下端まで
                // 3px 幅の連続した弧。
                let arm = empty() |> rectFill(9, 17, 3, 2, coatC()) |> dot(8, 18, skinC());
                let blade = empty()
                    |> line(7, 17, 2, 25, glintC())
                    |> line(8, 18, 3, 26, steelC())
                    |> line(9, 18, 4, 26, steelC())
                    |> dot(8, 18, hiltC())
                    |> dot(2, 25, sparkC());
                let slash = empty()
                    |> arc(13, 16, 13, 95, 265, glintC())
                    |> arc(13, 16, 12, 95, 265, glintC())
                    |> arc(13, 16, 11, 100, 260, trailC())
                    |> dot(12, 29, sparkC());
                let up = overlay(blade, overlay(arm, base |> shift(0, 1)));
                overlay(slash, overlay(up, legsFrontAt(11, 18, 0, 0)))
            case 3 =>
                // 振り抜き: 切っ先が下端 y=29 へ達し、弧の下半分が cyan の残光で残る。
                let arm = empty() |> rectFill(9, 19, 2, 2, coatC()) |> dot(8, 20, skinC());
                let blade = empty()
                    |> vline(6, 21, 7, glintC())
                    |> vline(7, 21, 8, steelC())
                    |> vline(8, 22, 7, steelC())
                    |> dot(7, 20, hiltC())
                    |> dot(7, 29, glintC())
                    |> dot(5, 28, sparkC());
                let after = empty() |> arc(13, 16, 12, 205, 265, trailC());
                let up = overlay(blade, overlay(arm, base |> shift(0, 2)));
                overlay(after, overlay(up, legsFrontAt(11, 18, 0, 0)))
            case 4 =>
                // 戻し: 腰を上げながら剣を体側の下段へ引き寄せる。
                let sword = swordHeld(8, 20, 3, 26);
                let up = overlay(sword, overlay(swordArmFront(),
                    overlay(armFront(20, 0), base))) |> shift(0, 1);
                overlay(up, legsFront(0, 0))
            case _ =>
                // 構え直し: 待機と同じ提げ持ちへ戻る。
                let up = overlay(swordUpright(7, 8, 18), overlay(swordArmFront(),
                    overlay(armFront(20, 0), base)));
                overlay(up, legsFront(0, 0))
        }

    // ══ AttackUp: 背面。腰だめに溜めてから肩越しに奥（画面上）へ斬り上げ、
    // 頭上を 3px 幅の弧が右から左へ走り抜ける ══

    def attackUp(f: Int32): Canvas =
        let base = overlay(torsoBack(), headBack());
        match f {
            case 0 =>
                // 構え: 剣を右腰の後ろへ引いて溜める。
                let blade = swordHeld(22, 20, 27, 25);
                let up = overlay(blade, overlay(swordArmBack(),
                    overlay(armFront(10, 0), base)));
                overlay(up, legsFront(0, 0))
            case 1 =>
                // 溜め最大: 体が 1px 沈み、剣先はさらに低く。切っ先に溜めの光。
                let blade = swordHeld(22, 20, 28, 26) |> dot(27, 24, sparkC());
                let up = overlay(blade, overlay(swordArmBack(),
                    overlay(armFront(10, 0), base))) |> shift(0, 1);
                overlay(up, legsFront(0, 0))
            case 2 =>
                // 斬り上げインパクト: 伸び上がって剣が右肩越しに奥（上）へ走り、
                // 頭上に 3px 幅の弧がかかる。
                let arm = empty() |> rectFill(20, 11, 2, 3, coatC()) |> hline(21, 10, 2, skinC());
                let blade = empty()
                    |> line(22, 8, 26, 1, glintC())
                    |> line(23, 9, 27, 2, steelC())
                    |> line(24, 10, 28, 3, steelC())
                    |> dot(23, 10, hiltC())
                    |> dot(27, 0, sparkC());
                let slash = empty()
                    |> arc(16, 13, 11, 10, 150, glintC())
                    |> arc(16, 13, 10, 10, 150, glintC())
                    |> arc(16, 13, 9, 15, 145, trailC());
                let up = overlay(blade, overlay(arm,
                    overlay(armFront(10, 1), base |> shift(0, -1))));
                overlay(slash, overlay(up, legsFrontAt(12, 17, 0, 1)))
            case 3 =>
                // 振り抜き: 剣は頭上を越えて左上へ抜け、弧の左端が残光で残る。
                let arm = empty() |> rectFill(20, 12, 2, 2, coatC()) |> dot(20, 11, skinC());
                let blade = swordHeld(19, 10, 11, 2);
                let after = empty() |> arc(16, 13, 10, 95, 150, trailC());
                let up = overlay(blade, overlay(arm, overlay(armFront(10, 0), base)));
                overlay(after, overlay(up, legsFront(0, 0)))
            case 4 =>
                // 戻し: 剣を立てて右手元へ引き戻す（まだ握りが浅い）。
                let up = overlay(swordUpright(22, 10, 18), overlay(swordArmBack(),
                    overlay(armFront(10, 0), base))) |> shift(0, 1);
                overlay(up, legsFront(0, 0))
            case _ =>
                // 構え直し: 歩き携行と同じ提げ持ちへ戻る。
                let up = overlay(swordUpright(22, 8, 18), overlay(swordArmBack(),
                    overlay(armFront(10, 0), base)));
                overlay(up, legsFront(0, 0))
        }

    // ══ UseItemDown: 掲げる（2 コマ）→ 明色フラッシュ 1 コマ → 飲む、の 3 拍（正面）══

    def useItemDown(f: Int32): Canvas =
        let base = overlay(swordUpright(7, 8, 18),
            overlay(swordArmFront(), overlay(torsoFrontCore(), headFront())));
        match f {
            case 0 =>
                // 小瓶を胸の高さへ持ち上げ始める。
                let arm = empty() |> rectFill(20, 14, 2, 2, coatC()) |> dot(20, 13, skinC());
                let vial = empty() |> dot(20, 10, hiltC()) |> vline(20, 11, 2, potionC());
                overlay(overlay(vial, overlay(arm, base)), legsFront(0, 0))
            case 1 =>
                // 頭上高く掲げる。
                let arm = empty() |> rectFill(20, 12, 2, 2, coatC()) |> dot(21, 11, skinC());
                let vial = empty() |> dot(21, 7, hiltC()) |> vline(21, 8, 2, potionC());
                overlay(overlay(vial, overlay(arm, base)), legsFront(0, 0))
            case 2 =>
                // フラッシュ: 掲げた瓶が白く光り、放射光が飛ぶ。
                let arm = empty() |> rectFill(20, 12, 2, 2, coatC()) |> dot(21, 11, skinC());
                let flash = empty()
                    |> vline(21, 8, 2, sparkC())
                    |> dot(21, 5, sparkC())
                    |> dot(19, 6, glintC()) |> dot(23, 6, glintC())
                    |> dot(18, 9, glintC()) |> dot(24, 9, glintC());
                overlay(overlay(flash, overlay(arm, base)), legsFront(0, 0))
            case _ =>
                // あおって飲む: 頭がのけぞり、瓶は口元で傾く。
                let head = headFront() |> shift(0, -1);
                let bodyBase = overlay(swordUpright(7, 8, 18),
                    overlay(swordArmFront(), overlay(torsoFrontCore(), head)));
                let arm = empty() |> rectFill(18, 12, 2, 2, coatC()) |> dot(17, 11, skinC());
                let vial = empty()
                    |> dot(16, 9, potionC()) |> dot(15, 10, potionC()) |> dot(14, 7, sparkC());
                overlay(overlay(vial, overlay(arm, bodyBase)), legsFront(0, 0))
        }

    // ══ UseItemUp: 背面。左手の小瓶を肩の高さ→頭上へ掲げ、光ったあと
    // 左肩越しにあおる（頭がのけぞって後頭部が下がる）══

    def useItemUp(f: Int32): Canvas =
        let base = overlay(swordUpright(22, 8, 18),
            overlay(swordArmBack(), overlay(torsoBack(), headBack())));
        match f {
            case 0 =>
                // 小瓶を左肩の高さへ持ち上げ始める。
                let arm = empty() |> rectFill(10, 14, 2, 2, coatC()) |> dot(11, 13, skinC());
                let vial = empty() |> dot(11, 10, hiltC()) |> vline(11, 11, 2, potionC());
                overlay(overlay(vial, overlay(arm, base)), legsFront(0, 0))
            case 1 =>
                // 頭上高く掲げる。
                let arm = empty() |> rectFill(10, 12, 2, 2, coatC()) |> dot(10, 11, skinC());
                let vial = empty() |> dot(10, 7, hiltC()) |> vline(10, 8, 2, potionC());
                overlay(overlay(vial, overlay(arm, base)), legsFront(0, 0))
            case 2 =>
                // フラッシュ: 掲げた瓶が白く光り、放射光が飛ぶ。
                let arm = empty() |> rectFill(10, 12, 2, 2, coatC()) |> dot(10, 11, skinC());
                let flash = empty()
                    |> vline(10, 8, 2, sparkC())
                    |> dot(10, 5, sparkC())
                    |> dot(8, 6, glintC()) |> dot(12, 6, glintC())
                    |> dot(7, 9, glintC()) |> dot(13, 9, glintC());
                overlay(overlay(flash, overlay(arm, base)), legsFront(0, 0))
            case _ =>
                // 肩越しにあおる: 頭がのけぞって 1px 上がり、瓶が後頭部の脇で傾く。
                let head = headBack() |> shift(0, -1);
                let bodyBase = overlay(swordUpright(22, 8, 18),
                    overlay(swordArmBack(), overlay(torsoBack(), head)));
                let arm = empty() |> rectFill(12, 12, 2, 2, coatC()) |> dot(13, 11, skinC());
                let vial = empty()
                    |> dot(15, 9, potionC()) |> dot(16, 10, potionC()) |> dot(17, 7, sparkC());
                overlay(overlay(vial, overlay(arm, bodyBase)), legsFront(0, 0))
        }

    // ══ DamageSide: 全身白フラッシュ + 3px ノックバック → のけぞり 2 コマ ══

    /// 全ピクセルを白 1 色に写した被弾フラッシュのシルエット。
    def whiteout(cv: Canvas): Canvas = Map.map(_ -> sparkC(), cv)

    def damageSide(f: Int32): Canvas =
        let core = overlay(torsoSideCore(), headSide());
        match f {
            case 0 =>
                // 白シルエットのフラッシュ + 3px 後方ノックバック。前面に火花。
                let arm = empty() |> rectFill(16, 13, 2, 2, coatC()) |> dot(17, 12, skinC());
                let pose = overlay(swordHeld(18, 12, 22, 7), overlay(arm, core));
                let full = overlay(pose, overlay(legSide(12, 10), legSide(15, 17)));
                let ghost = whiteout(full) |> shift(3, 0);
                let sparks = empty()
                    |> dot(7, 13, sparkC()) |> dot(6, 16, sparkC()) |> dot(8, 19, sparkC());
                overlay(sparks, ghost)
            case 1 =>
                // 最大のけぞり: 体が沈み、剣ごと腕が跳ね上がり、足を踏ん張る。
                let arm = empty() |> rectFill(17, 12, 2, 2, coatC()) |> dot(18, 11, skinC());
                let up = overlay(swordHeld(19, 11, 23, 6), overlay(arm, core)) |> shift(2, 1);
                let sparks = empty() |> dot(8, 14, sparkC()) |> dot(7, 18, sparkC());
                overlay(sparks, overlay(up, overlay(legSide(12, 10), legSide(15, 17))))
            case _ =>
                // 半戻り: まだ 1px 引いた姿勢で剣を提げ直す。
                let up = overlay(swordHeld(14, 20, 7, 25), overlay(armSideSwing(1), core))
                    |> shift(1, 0);
                overlay(up, legsSideStand())
        }

    // ══ DamageDown: 正面。白シルエットで手前（画面下）へ 2px 沈み込み →
    // 頭が跳ねて腕が開く最大のけぞり → 半戻り ══

    def damageDown(f: Int32): Canvas =
        let base = overlay(torsoFrontCore(), headFront());
        match f {
            case 0 =>
                // 白シルエットのフラッシュ + 手前（下）へ 2px 沈む。胸元に火花。
                let sword = swordHeld(8, 18, 3, 12);
                let arm = empty() |> rectFill(10, 16, 2, 2, coatC()) |> dot(9, 17, skinC());
                let pose = overlay(sword, overlay(arm, overlay(armFront(20, 2), base)));
                let full = overlay(pose, legsFrontAt(11, 18, 0, 0));
                let ghost = whiteout(full) |> shift(0, 2);
                let sparks = empty()
                    |> dot(8, 20, sparkC()) |> dot(23, 19, sparkC()) |> dot(15, 4, sparkC());
                overlay(sparks, ghost)
            case 1 =>
                // 最大のけぞり: あごが上がって頭が沈み、両腕が開き、剣は握ったまま外へ跳ねる。
                let head = headFront() |> shift(0, 1);
                let sword = swordHeld(8, 16, 3, 10);
                let arms = overlay(armFront(10, 2), armFront(20, 2)) |> dot(9, 16, skinC());
                let upper = overlay(sword, overlay(arms,
                    overlay(torsoFrontCore(), head))) |> shift(0, 1);
                let sparks = empty() |> dot(12, 21, sparkC()) |> dot(19, 20, sparkC());
                overlay(sparks, overlay(upper, legsFrontAt(11, 18, 0, 0)))
            case _ =>
                // 半戻り: まだ 1px 沈んだまま剣を提げ直す。
                let upper = overlay(swordUpright(7, 10, 18), overlay(swordArmFront(),
                    overlay(armFront(20, 1), base))) |> shift(0, 1);
                overlay(upper, legsFront(0, 0))
        }

    // ══ DamageUp: 背面。白シルエットで奥（画面上）へ 2px 突き飛ばされ →
    // 足がもつれるよろめき → 半戻り ══

    def damageUp(f: Int32): Canvas =
        let base = overlay(torsoBack(), headBack());
        match f {
            case 0 =>
                // 白シルエットのフラッシュ + 奥（上）へ 2px 浮く。背中の下に火花。
                let sword = swordHeld(23, 18, 28, 12);
                let arm = empty() |> rectFill(20, 16, 2, 2, coatC()) |> dot(22, 17, skinC());
                let pose = overlay(sword, overlay(arm, overlay(armFront(10, 2), base)));
                let full = overlay(pose, legsFrontAt(11, 18, 0, 0));
                let ghost = whiteout(full) |> shift(0, -2);
                let sparks = empty()
                    |> dot(13, 28, sparkC()) |> dot(18, 28, sparkC()) |> dot(15, 29, sparkC());
                overlay(sparks, ghost)
            case 1 =>
                // 最大よろめき: 頭が奥へ突っ込んで上がり、左足がもつれて浮く。剣は外へ跳ねる。
                let head = headBack() |> shift(0, -1);
                let sword = swordHeld(22, 15, 27, 9);
                let arm = empty() |> rectFill(20, 13, 2, 2, coatC()) |> dot(21, 15, skinC());
                let upper = overlay(sword, overlay(arm,
                    overlay(armFront(10, 2), overlay(torsoBack(), head)))) |> shift(0, -1);
                let sparks = empty() |> dot(13, 22, sparkC()) |> dot(18, 21, sparkC());
                overlay(sparks, overlay(upper, legsFrontAt(12, 17, 1, 0)))
            case _ =>
                // 半戻り: 握りの浅い剣を提げ直して立て直す。
                let upper = overlay(swordUpright(22, 10, 18), overlay(swordArmBack(),
                    overlay(armFront(10, 1), base)));
                overlay(upper, legsFront(0, 0))
        }

    // ══ Death: 6 コマ・正面・膝どまり ══
    // よろめき(2) → 膝から崩れ(2) → 膝立ちのまま前傾がくり(2)。
    // 倒れ伏す姿は描かない — この後は共通の白骨（Skeleton）へ差し替わるので、
    // 最終コマも膝立ちの立面シルエットで止める。剣は途中で手からこぼれ、
    // 傍らの地面に転がったままになる。

    def death(f: Int32): Canvas = match f {
        case 0 =>
            // 被弾のよろめき: 体が右へ傾ぎつつ 1px 沈み、剣先が下がる。胸に着弾の星。
            let upper =
                overlay(overlay(swordUpright(7, 10, 18) |> shift(0, 1), swordArmFront()),
                    overlay(armFront(20, -1), overlay(torsoFrontCore(), headFront())))
                |> shift(1, 1);
            let hit = empty()
                |> dot(15, 15, sparkC()) |> dot(14, 16, starC()) |> dot(17, 14, starC());
            overlay(hit, overlay(upper, legsFront(0, 0)))
        case 1 =>
            // 大きくのけぞる: 両腕が跳ね上がり、剣が手を離れて宙に浮く。
            let head = headFront() |> shift(0, -1);
            let upper = overlay(armFront(10, 3), overlay(armFront(20, 3),
                overlay(torsoFrontCore(), head)));
            let loose = swordHeld(8, 9, 12, 4);
            let stars = empty() |> dot(13, 3, starC()) |> dot(20, 5, sparkC());
            overlay(stars, overlay(loose, overlay(upper, legsFront(1, 0))))
        case 2 =>
            // 膝から崩れる（片膝）: 体が 3px 沈み、剣を地に突いて支える。頭はうなだれて +1px。
            let upper = overlay(armFront(20, -3), torsoFrontCore()) |> shift(0, 3);
            let head2 = headFront() |> shift(0, 4);
            let prop = empty()
                |> vline(8, 23, 7, glintC())
                |> vline(9, 23, 7, steelC())
                |> hline(7, 22, 4, steelC())
                |> vline(9, 20, 2, hiltC())
                |> dot(8, 21, skinC()) |> dot(10, 21, skinC());
            let propArm = empty() |> rectFill(10, 18, 2, 3, coatC());
            let kneeL = empty() |> rectFill(12, 26, 3, 2, shadeC()) |> rectFill(12, 28, 3, 2, bootC());
            let legR = empty() |> rectFill(17, 25, 3, 2, shadeC()) |> rectFill(17, 27, 3, 3, bootC());
            overlay(prop, overlay(propArm, overlay(head2, overlay(upper, overlay(kneeL, legR)))))
        case 3 =>
            // 両膝をつく: 体が 5px 沈んで頭がうなだれ、剣が手からこぼれ落ちる。
            let upper = overlay(torsoFrontCore(), headFront() |> shift(0, 2)) |> shift(0, 5);
            let armL = empty() |> rectFill(10, 21, 2, 3, coatC()) |> hline(10, 24, 2, skinC());
            let armR = empty() |> rectFill(20, 21, 2, 3, coatC()) |> hline(20, 24, 2, skinC());
            let falling = swordHeld(7, 24, 3, 28);
            let kneeL = empty() |> rectFill(12, 26, 3, 2, shadeC()) |> rectFill(12, 28, 3, 2, bootC());
            let kneeR = empty() |> rectFill(17, 26, 3, 2, shadeC()) |> rectFill(17, 28, 3, 2, bootC());
            let dust = empty() |> dot(11, 28, dustC());
            overlay(dust, overlay(falling,
                overlay(armL, overlay(armR, overlay(upper, overlay(kneeL, kneeR))))))
        case 4 =>
            // 膝立ち前傾（浅）: 剣は足元へ落ちきり、両腕がだらりと垂れる。
            // 頭はさらにうなだれ、額のサークレットだけが金色に光る。
            let upper = overlay(torsoFrontCore(), headFront() |> shift(0, 3)) |> shift(0, 5);
            let armL = empty() |> rectFill(10, 21, 2, 4, coatC()) |> hline(10, 25, 2, skinC());
            let armR = empty() |> rectFill(20, 21, 2, 4, coatC()) |> hline(20, 25, 2, skinC());
            let kneeL = empty() |> rectFill(12, 26, 3, 2, shadeC()) |> rectFill(12, 28, 3, 2, bootC());
            let kneeR = empty() |> rectFill(17, 26, 3, 2, shadeC()) |> rectFill(17, 28, 3, 2, bootC());
            let dust = empty() |> dot(11, 28, dustC()) |> dot(21, 28, dustC());
            overlay(dust, overlay(swordFallen(),
                overlay(armL, overlay(armR, overlay(upper, overlay(kneeL, kneeR))))))
        case _ =>
            // がくり（最終コマ）: 頭が 1px 落ちて黒髪の頭頂だけが見え、腕も 1px 沈む。
            // 膝立ちのシルエットのまま静止（この後 Skeleton へ差し替わる）。
            let upper = overlay(torsoFrontCore(), headFront() |> shift(0, 4)) |> shift(0, 5);
            let armL = empty() |> rectFill(10, 22, 2, 4, coatC()) |> hline(10, 26, 2, skinC());
            let armR = empty() |> rectFill(20, 22, 2, 4, coatC()) |> hline(20, 26, 2, skinC());
            let kneeL = empty() |> rectFill(12, 26, 3, 2, shadeC()) |> rectFill(12, 28, 3, 2, bootC());
            let kneeR = empty() |> rectFill(17, 26, 3, 2, shadeC()) |> rectFill(17, 28, 3, 2, bootC());
            let dust = empty() |> dot(10, 28, dustC()) |> dot(22, 28, dustC());
            overlay(dust, overlay(swordFallen(),
                overlay(armL, overlay(armR, overlay(upper, overlay(kneeL, kneeR))))))
    }

    /// 手から離れて地面に転がった剣。膝立ちの体の左脇（画面左）に、
    /// 柄を手側へ向けて横たわる（刃 2px + ハイライト・切っ先にきらり）。
    def swordFallen(): Canvas =
        empty()
            |> hline(3, 26, 5, glintC())
            |> hline(3, 27, 5, steelC())
            |> dot(8, 27, hiltC())
            |> dot(3, 26, sparkC())
}
