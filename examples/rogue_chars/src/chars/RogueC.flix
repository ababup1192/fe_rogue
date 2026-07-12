// RogueC — 商人ギルドの暗部。山高帽をかぶった紳士で、袖から仕込みナイフが滑り出す。
// 一見ただの上品な商人。攻撃だけは無駄のない最小の一閃で正体を見せる。
//
// 個性は頭部の「山高帽（シルクハット）+ 細い口ひげ + 蝶タイ」。全クリップ・全方向に反映。
// Death 最終コマでは帽子が頭から外れて隣に転がり落ちる（帽子が個性なので死の記号に使う）。
//
// 色（RoguePalette から6色）:
//   darkSlate … 帽子とジャケット（黒っぽい濃色）
//   silver    … ベスト
//   paleBlue  … 白シャツの明色（襟・胸元）
//   skin      … 顔と手
//   red       … 蝶タイの差し色
//   darkBrown … 靴・輪郭（背景 night と同化しない濃色）
//   white     … ナイフの刃・攻撃軌跡・Damage フラッシュ
mod RogueC {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, discFill, arc, shift, overlay, hflip}

    pub def name(): String = "ROGUE C 澄まし顔の仕込みナイフ"

    // ── 色 ──
    def hatC(): Color = RoguePalette.darkSlate()   // 帽子＝ジャケットと同じ濃色
    def coatC(): Color = RoguePalette.darkSlate()  // ジャケット
    def vestC(): Color = RoguePalette.silver()     // ベスト
    def shirtC(): Color = RoguePalette.paleBlue()  // 白シャツ
    def skinC(): Color = RoguePalette.skin()       // 肌
    def tieC(): Color = RoguePalette.red()         // 蝶タイ
    def bootC(): Color = RoguePalette.darkBrown()  // 靴・輪郭（接地の濃色）
    def bladeC(): Color = RoguePalette.white()     // ナイフの刃
    def flashC(): Color = RoguePalette.white()     // 軌跡・被弾フラッシュ

    pub def draw(clip: RogueStage.Clip, frame: Int32): Canvas =
        let n = RogueStage.frameCount(clip);
        let f = Int32.remainder(Int32.remainder(frame, n) + n, n);
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
    //  頭部パーツ（個性）— 山高帽・すまし顔・口ひげ・蝶タイ
    // ════════════════════════════════════════════════════════════

    // 正面の頭（帽子＋顔）。bob は呼吸/歩行の上下オフセット。
    def headFront(bob: Int32): Canvas =
        let top = bob + 2;   // 頭上に 2px の余白（身長 ≤ 28px のアンカー規約）
        empty()
            // 山高帽: 円筒（クラウン）
            |> rectFill(12, top + 0, 8, 4, hatC())          // クラウン本体
            |> hline(12, top + 4, 8, RoguePalette.night())  // クラウン下の帯（陰で締める）
            // つば（クラウンより左右に張り出す）
            |> hline(10, top + 5, 12, hatC())
            |> dot(9, top + 5, bootC())                      // つばの輪郭端
            |> dot(22, top + 5, bootC())
            // 顔（帽子の下・skin）
            |> rectFill(12, top + 6, 8, 5, skinC())
            |> dot(11, top + 7, skinC())                     // ほほ
            |> dot(20, top + 7, skinC())
            // 目（すまし顔・細い）
            |> dot(13, top + 7, bootC())
            |> dot(18, top + 7, bootC())
            // 細い口ひげ（鼻下に左右へ伸びる1本線）
            |> hline(13, top + 9, 6, bootC())
            |> dot(12, top + 9, bootC())
            |> dot(19, top + 9, bootC())

    // 背面の頭（帽子の裏＋後頭部）。顔は見えない。
    def headBack(bob: Int32): Canvas =
        let top = bob + 2;   // 頭上余白を正面と揃える
        empty()
            |> rectFill(12, top + 0, 8, 4, hatC())
            |> hline(12, top + 4, 8, RoguePalette.night())
            |> hline(10, top + 5, 12, hatC())
            |> dot(9, top + 5, bootC())
            |> dot(22, top + 5, bootC())
            |> rectFill(12, top + 6, 8, 5, skinC())          // 後頭部（髪は帽子で隠れ肌色地）
            |> hline(12, top + 6, 8, hatC())                 // うなじ上の帽子影

    // 横向き（左向き）の頭。鼻・口ひげが左に出る。
    def headSide(bob: Int32): Canvas =
        let top = bob + 2;   // 頭上余白を正面と揃える
        empty()
            |> rectFill(12, top + 0, 7, 4, hatC())           // クラウン
            |> hline(12, top + 4, 7, RoguePalette.night())
            |> hline(10, top + 5, 11, hatC())                // つば（前=左に長め）
            |> dot(9, top + 5, bootC())
            |> dot(21, top + 5, bootC())
            |> rectFill(12, top + 6, 6, 5, skinC())          // 顔
            |> dot(11, top + 7, skinC())                     // 鼻先（左）
            |> dot(13, top + 7, bootC())                     // 目
            |> hline(11, top + 9, 4, bootC())                // 口ひげ（左へ）

    // 蝶タイ（正面・胸の上）。cx を中心に赤い蝶。
    def bowTie(cx: Int32, y: Int32): Canvas =
        empty()
            |> dot(cx - 1, y, tieC())
            |> dot(cx, y, tieC())
            |> dot(cx + 1, y, tieC())
            |> dot(cx - 1, y + 1, tieC())
            |> dot(cx + 1, y + 1, tieC())

    // ════════════════════════════════════════════════════════════
    //  胴・脚（正面/背面）— ジャケット＋ベスト＋シャツ襟
    // ════════════════════════════════════════════════════════════

    // 正面の胴。bob=上下、legPhase で脚の開き。
    def torsoFront(bob: Int32): Canvas =
        empty()
            // 肩〜胴（ジャケット）
            |> rectFill(11, bob + 11, 10, 8, coatC())
            |> dot(10, bob + 12, coatC())                    // 肩の張り出し
            |> dot(21, bob + 12, coatC())
            // 胸元の白シャツ（V字の襟）
            |> vline(15, bob + 12, 5, shirtC())
            |> vline(16, bob + 12, 5, shirtC())
            // ベスト（シャツの上・両脇）
            |> vline(14, bob + 13, 5, vestC())
            |> vline(17, bob + 13, 5, vestC())
            // 蝶タイ
            |> overlay(bowTie(15, bob + 11))
            // ボタン（ベストの前）
            |> dot(15, bob + 14, bootC())
            |> dot(16, bob + 16, bootC())

    def legsFront(bob: Int32, spread: Int32): Canvas =
        empty()
            // 左右の脚（ズボン＝ジャケットと同色）
            |> rectFill(12 - spread, bob + 19, 3, 8, coatC())
            |> rectFill(17 + spread, bob + 19, 3, 8, coatC())
            // 靴（接地・darkBrown）
            |> hline(11 - spread, 28, 4, bootC())
            |> hline(11 - spread, 29, 4, bootC())
            |> hline(17 + spread, 28, 4, bootC())
            |> hline(17 + spread, 29, 4, bootC())

    // 背面の胴（襟や蝶タイは見えず、背中のジャケット）。
    def torsoBack(bob: Int32): Canvas =
        empty()
            |> rectFill(11, bob + 11, 10, 8, coatC())
            |> dot(10, bob + 12, coatC())
            |> dot(21, bob + 12, coatC())
            |> vline(15, bob + 11, 8, RoguePalette.night())  // 背の中央シーム
            |> vline(16, bob + 11, 8, RoguePalette.night())

    // 正面の腕（肩から手まで2px幅・武器側の袖に刃先がのぞく）。
    // armX=肩x, handY=手先の下端。isKnife=true でナイフ側の袖から刃先を出す。
    def armFront(shoulderX: Int32, bob: Int32, swing: Int32, isKnife: Bool): Canvas =
        let sx = shoulderX;
        let hy = bob + 18 + swing;
        let base =
            empty()
                |> vline(sx, bob + 12, 6, coatC())           // 上腕（袖）
                |> vline(sx + 1, bob + 12, 6, coatC())
                |> dot(sx, hy, skinC())                      // 手
                |> dot(sx + 1, hy, skinC());
        if (isKnife)
            // 袖口から刃先が2pxだけのぞく（常時見える最小の武器）
            base
                |> dot(sx, hy + 1, bladeC())
                |> dot(sx, hy + 2, bladeC())
        else
            base

    // ════════════════════════════════════════════════════════════
    //  Idle（呼吸）
    // ════════════════════════════════════════════════════════════

    // 呼吸: f=0,2 で bob=0、f=1 で bob=1（1px 沈む）、f=3 で bob=0。足元は常に y=29 固定。
    def idleBob(f: Int32): Int32 = if (f == 1) 1 else 0

    def idleDown(f: Int32): Canvas =
        let bob = idleBob(f);
        let hatTouch = if (f == 3) 1 else 0;                 // f3 で帽子に手を添える余裕
        legsFront(0, 0)
            |> overlay(armFront(9, bob, 0, false))
            |> overlay(armFront(21, bob, 0 - hatTouch * 4, true)) // 右手（ナイフ側）
            |> overlay(torsoFront(bob))
            |> overlay(headFront(bob))
            |> overlay(if (hatTouch == 1) hatSalute(bob) else empty())

    // 帽子のつばに手を添える小さな仕草。
    def hatSalute(bob: Int32): Canvas =
        empty()
            |> vline(21, bob + 6, 6, coatC())
            |> dot(20, bob + 5, skinC())
            |> dot(21, bob + 5, skinC())

    def idleUp(f: Int32): Canvas =
        let bob = idleBob(f);
        legsFront(0, 0)
            |> overlay(armFront(9, bob, 0, false))
            |> overlay(armFront(21, bob, 0, false))
            |> overlay(torsoBack(bob))
            |> overlay(headBack(bob))

    def idleSide(f: Int32): Canvas =
        let bob = idleBob(f);
        idleSideBody(bob)

    // 左向きの立ち姿。手前の腕にナイフ袖。
    def idleSideBody(bob: Int32): Canvas =
        empty()
            // 脚（横向きは前後に少しずらす）
            |> rectFill(13, bob + 19, 3, 8, coatC())
            |> rectFill(16, bob + 19, 3, 8, coatC())
            |> hline(12, 28, 5, bootC())                     // 前足（左）
            |> hline(12, 29, 5, bootC())
            |> hline(16, 28, 4, bootC())                     // 後ろ足
            |> hline(16, 29, 4, bootC())
            // 胴（ジャケット）
            |> rectFill(13, bob + 11, 6, 8, coatC())
            |> vline(13, bob + 12, 6, shirtC())              // 前身頃の白シャツ（左端）
            |> vline(14, bob + 13, 5, vestC())               // ベスト
            |> overlay(bowTie(13, bob + 11))                 // 蝶タイ（左＝前）
            // 手前の腕＋ナイフ袖
            |> vline(14, bob + 12, 6, coatC())
            |> dot(13, bob + 18, skinC())
            |> dot(14, bob + 18, skinC())
            |> dot(13, bob + 19, bladeC())                   // 刃先のぞき
            |> dot(13, bob + 20, bladeC())
            |> overlay(headSide(bob))

    // ════════════════════════════════════════════════════════════
    //  Walk（歩き）— 4コマ全部違う・歩幅と腕振り・体の上下1px
    // ════════════════════════════════════════════════════════════

    // 歩行位相: f0=右足前, f1=通過(沈む), f2=左足前, f3=通過(浮く)
    def walkDown(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let (_spr, swL, swR) = match f {
            case 0 => (2, 1, 0 - 1)
            case 1 => (0, 0, 0)
            case 2 => (2, 0 - 1, 1)
            case _ => (0, 0, 0)
        };
        legsWalkFront(bob, f)
            |> overlay(armFront(9, bob, swL, false))
            |> overlay(armFront(21, bob, swR, true))
            |> overlay(torsoFront(bob))
            |> overlay(headFront(bob))

    // 歩行の脚（コマごとに前後に開く）。
    def legsWalkFront(bob: Int32, f: Int32): Canvas =
        match f {
            case 0 =>
                empty()
                    |> rectFill(11, bob + 19, 3, 8, coatC())   // 左足 前
                    |> rectFill(18, bob + 19, 3, 7, coatC())   // 右足 後
                    |> hline(10, 28, 4, bootC())
                    |> hline(10, 29, 4, bootC())
                    |> hline(18, 27, 4, bootC())
                    |> hline(18, 28, 4, bootC())
            case 2 =>
                empty()
                    |> rectFill(11, bob + 19, 3, 7, coatC())   // 左足 後
                    |> rectFill(18, bob + 19, 3, 8, coatC())   // 右足 前
                    |> hline(11, 27, 4, bootC())
                    |> hline(11, 28, 4, bootC())
                    |> hline(18, 28, 4, bootC())
                    |> hline(18, 29, 4, bootC())
            case _ =>
                empty()
                    |> rectFill(12, bob + 19, 3, 8, coatC())   // 通過（そろえる）
                    |> rectFill(17, bob + 19, 3, 8, coatC())
                    |> hline(11, 28, 4, bootC())
                    |> hline(11, 29, 4, bootC())
                    |> hline(17, 28, 4, bootC())
                    |> hline(17, 29, 4, bootC())
        }

    def walkUp(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        let (swL, swR) = match f {
            case 0 => (1, 0 - 1)
            case 2 => (0 - 1, 1)
            case _ => (0, 0)
        };
        legsWalkFront(bob, f)
            |> overlay(armFront(9, bob, swL, false))
            |> overlay(armFront(21, bob, swR, false))
            |> overlay(torsoBack(bob))
            |> overlay(headBack(bob))

    def walkSide(f: Int32): Canvas =
        let bob = if (f == 1 or f == 3) 1 else 0;
        // 左向きの歩き。前足＝左、腕振りは前後。
        let body =
            empty()
                |> rectFill(13, bob + 11, 6, 8, coatC())     // 胴
                |> vline(13, bob + 12, 6, shirtC())
                |> vline(14, bob + 13, 5, vestC())
                |> overlay(bowTie(13, bob + 11))
                |> overlay(headSide(bob));
        walkSideLegs(bob, f)
            |> overlay(walkSideArm(bob, f))
            |> overlay(body)

    // 左向きの歩行脚（f で前後入れ替え・非対称必須）。
    def walkSideLegs(bob: Int32, f: Int32): Canvas =
        match f {
            case 0 =>
                empty()
                    |> rectFill(11, bob + 19, 3, 8, coatC())   // 前足（左）大きく前
                    |> rectFill(17, bob + 19, 3, 7, coatC())   // 後ろ足
                    |> hline(10, 28, 5, bootC())
                    |> hline(10, 29, 5, bootC())
                    |> hline(17, 27, 4, bootC())
                    |> hline(17, 28, 4, bootC())
            case 2 =>
                empty()
                    |> rectFill(13, bob + 19, 3, 7, coatC())   // 前足 引き
                    |> rectFill(15, bob + 19, 3, 8, coatC())   // 後ろ足 前へ
                    |> hline(12, 27, 4, bootC())
                    |> hline(12, 28, 4, bootC())
                    |> hline(15, 28, 5, bootC())
                    |> hline(15, 29, 5, bootC())
            case _ =>
                empty()
                    |> rectFill(13, bob + 19, 3, 8, coatC())
                    |> rectFill(15, bob + 19, 3, 8, coatC())
                    |> hline(12, 28, 4, bootC())
                    |> hline(12, 29, 4, bootC())
                    |> hline(15, 28, 5, bootC())
                    |> hline(15, 29, 5, bootC())
        }

    // 左向きの手前の腕（前後に振る・ナイフ袖）。
    def walkSideArm(bob: Int32, f: Int32): Canvas =
        let dx = match f {
            case 0 => 0 - 2   // 前に振る
            case 2 => 1       // 後ろに振る
            case _ => 0
        };
        let ax = 14 + dx;
        empty()
            |> vline(ax, bob + 12, 6, coatC())
            |> dot(ax, bob + 18, skinC())
            |> dot(ax, bob + 19, bladeC())
            |> dot(ax, bob + 20, bladeC())

    // ════════════════════════════════════════════════════════════
    //  Attack（仕込みナイフの最小の一閃・6コマ）
    //  構え(0,1) → 袖から刃が滑り出す(2) → 一閃ピーク(3) → 引き(4,5)
    //  大振りせず素早く。刃がスッと伸び、明色の短い弧の軌跡。
    // ════════════════════════════════════════════════════════════

    def attackDown(f: Int32): Canvas =
        let bob = 0;
        let base =
            legsFront(0, 0)
                |> overlay(armFront(9, bob, 0, false))
                |> overlay(torsoFront(bob))
                |> overlay(headFront(bob));
        // 右手が前へ突き出し、刃が下方向へ伸びる
        match f {
            case 0 => base |> overlay(armFront(21, bob, 0, true))          // 構え
            case 1 => base |> overlay(armFront(21, bob, 0 - 1, true))      // 引き絞る
            case 2 =>                                                       // 刃が滑り出す
                base
                    |> vline(21, bob + 12, 7, coatC())
                    |> dot(21, bob + 19, skinC())
                    |> vline(21, bob + 20, 3, bladeC())
            case 3 =>                                                       // 一閃ピーク（下へ突く）
                base
                    |> vline(20, bob + 12, 7, coatC())
                    |> dot(20, bob + 19, skinC())
                    |> vline(20, bob + 20, 5, bladeC())
                    |> arc(20, bob + 20, 5, 250, 320, flashC())            // 短い明色の弧
            case 4 =>                                                       // 引き
                base
                    |> vline(21, bob + 12, 6, coatC())
                    |> dot(21, bob + 18, skinC())
                    |> vline(21, bob + 19, 3, bladeC())
            case _ => base |> overlay(armFront(21, bob, 0, true))          // 戻り
        }

    def attackUp(f: Int32): Canvas =
        let bob = 0;
        let base =
            legsFront(0, 0)
                |> overlay(armFront(9, bob, 0, false))
                |> overlay(torsoBack(bob))
                |> overlay(headBack(bob));
        // 刃を上へ突き上げる
        match f {
            case 0 => base |> overlay(armFront(21, bob, 0, true))
            case 1 => base |> overlay(armFront(21, bob, 0 - 1, true))
            case 2 =>
                base
                    |> vline(21, bob + 8, 8, coatC())
                    |> vline(21, bob + 5, 3, bladeC())
            case 3 =>
                base
                    |> vline(21, bob + 6, 8, coatC())
                    |> vline(21, bob + 1, 5, bladeC())
                    |> arc(21, bob + 6, 5, 40, 110, flashC())
            case 4 =>
                base
                    |> vline(21, bob + 8, 7, coatC())
                    |> vline(21, bob + 5, 3, bladeC())
            case _ => base |> overlay(armFront(21, bob, 0, true))
        }

    def attackSide(f: Int32): Canvas =
        let bob = 0;
        // 左向き。胴＋頭は共通、手前の腕が左へ突き出す。
        let body =
            empty()
                |> rectFill(13, bob + 11, 6, 8, coatC())
                |> vline(13, bob + 12, 6, shirtC())
                |> vline(14, bob + 13, 5, vestC())
                |> overlay(bowTie(13, bob + 11))
                |> overlay(headSide(bob));
        let legs =
            empty()
                |> rectFill(13, bob + 19, 3, 8, coatC())
                |> rectFill(16, bob + 19, 3, 8, coatC())
                |> hline(12, 28, 5, bootC())
                |> hline(12, 29, 5, bootC())
                |> hline(16, 28, 4, bootC())
                |> hline(16, 29, 4, bootC());
        let base = legs |> overlay(body);
        match f {
            case 0 =>                                                       // 構え（腕引く）
                base
                    |> vline(15, bob + 12, 6, coatC())
                    |> dot(15, bob + 18, skinC())
                    |> dot(15, bob + 19, bladeC())
            case 1 =>                                                       // ためる（さらに引く）
                base
                    |> vline(16, bob + 12, 6, coatC())
                    |> dot(16, bob + 18, skinC())
                    |> dot(16, bob + 19, bladeC())
            case 2 =>                                                       // 刃が滑り出す（前へ）
                base
                    |> hline(11, bob + 15, 4, coatC())
                    |> dot(10, bob + 15, skinC())
                    |> hline(6, bob + 15, 4, bladeC())
            case 3 =>                                                       // 一閃ピーク（水平の刺突）
                base
                    |> hline(10, bob + 15, 5, coatC())
                    |> dot(9, bob + 15, skinC())
                    |> hline(3, bob + 15, 6, bladeC())
                    |> arc(15, bob + 15, 10, 160, 200, flashC())           // 明色の短い水平弧
                    |> hline(4, bob + 14, 5, flashC())                     // 軌跡の芯
            case 4 =>                                                       // 引き戻し始め
                base
                    |> hline(11, bob + 15, 4, coatC())
                    |> dot(10, bob + 15, skinC())
                    |> hline(7, bob + 15, 3, bladeC())
            case _ =>                                                       // 収める
                base
                    |> vline(14, bob + 12, 6, coatC())
                    |> dot(14, bob + 18, skinC())
                    |> dot(14, bob + 19, bladeC())
        }

    // ════════════════════════════════════════════════════════════
    //  UseItem（掲げる→明色フラッシュ→使う・3拍・4コマ）
    // ════════════════════════════════════════════════════════════

    // 商人らしく「小瓶を掲げて飲む」仕草。
    def useItemDown(f: Int32): Canvas =
        let bob = 0;
        let base =
            legsFront(0, 0)
                |> overlay(armFront(9, bob, 0, false))
                |> overlay(torsoFront(bob))
                |> overlay(headFront(bob));
        match f {
            case 0 => base |> overlay(armFront(21, bob, 0, true))          // 通常
            case 1 =>                                                       // 掲げる
                base
                    |> vline(21, bob + 8, 4, coatC())
                    |> dot(21, bob + 7, skinC())
                    |> dot(21, bob + 5, vestC())                           // 小瓶
                    |> dot(21, bob + 6, shirtC())
            case 2 =>                                                       // 明色フラッシュ
                base
                    |> vline(21, bob + 8, 4, coatC())
                    |> dot(21, bob + 7, skinC())
                    |> discFill(21, bob + 5, 2, flashC())
            case _ =>                                                       // 使う（口元へ）
                base
                    |> vline(21, bob + 10, 3, coatC())
                    |> dot(20, bob + 9, skinC())
                    |> dot(20, bob + 8, shirtC())
        }

    def useItemUp(f: Int32): Canvas =
        let bob = 0;
        let base =
            legsFront(0, 0)
                |> overlay(armFront(9, bob, 0, false))
                |> overlay(armFront(21, bob, 0, false))
                |> overlay(torsoBack(bob))
                |> overlay(headBack(bob));
        match f {
            case 0 => base
            case 1 => base |> vline(21, bob + 6, 4, coatC()) |> dot(21, bob + 5, shirtC())
            case 2 => base |> vline(21, bob + 6, 4, coatC()) |> discFill(21, bob + 4, 2, flashC())
            case _ => base |> vline(21, bob + 8, 3, coatC()) |> dot(21, bob + 7, shirtC())
        }

    def useItemSide(f: Int32): Canvas =
        let bob = 0;
        let body =
            empty()
                |> rectFill(13, bob + 11, 6, 8, coatC())
                |> vline(13, bob + 12, 6, shirtC())
                |> vline(14, bob + 13, 5, vestC())
                |> overlay(bowTie(13, bob + 11))
                |> overlay(headSide(bob));
        let legs =
            empty()
                |> rectFill(13, bob + 19, 3, 8, coatC())
                |> rectFill(16, bob + 19, 3, 8, coatC())
                |> hline(12, 28, 5, bootC())
                |> hline(12, 29, 5, bootC())
                |> hline(16, 28, 4, bootC())
                |> hline(16, 29, 4, bootC());
        let base = legs |> overlay(body);
        match f {
            case 0 => base |> vline(14, bob + 12, 6, coatC()) |> dot(14, bob + 18, skinC())
            case 1 =>                                                       // 掲げる（前上へ）
                base
                    |> line(14, bob + 12, 11, bob + 8, coatC())
                    |> dot(10, bob + 7, shirtC())
            case 2 =>                                                       // フラッシュ
                base
                    |> line(14, bob + 12, 11, bob + 8, coatC())
                    |> discFill(10, bob + 6, 2, flashC())
            case _ =>                                                       // 使う（口元）
                base
                    |> line(14, bob + 12, 12, bob + 9, coatC())
                    |> dot(11, bob + 8, shirtC())
        }

    // ════════════════════════════════════════════════════════════
    //  Damage（f0=全身白フラッシュ+ノックバック → のけぞり・3コマ）
    // ════════════════════════════════════════════════════════════

    // 全身を白シルエットにする（既存の絵を白へ塗り替える）。
    def whiteOut(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> {
            let (x, y) = k;
            PixelCanvas.dot(x, y, flashC(), acc)
        }, PixelCanvas.empty(), cv)

    def damageDown(f: Int32): Canvas =
        // f0=手前へノックバック（下向きは手前=画面下へ沈む）
        let bob = if (f == 0) 1 else 0;
        let body =
            legsFront(0, 1)
                |> overlay(armFront(8, bob, 2, false))       // 腕がのけぞる
                |> overlay(armFront(22, bob, 2, true))
                |> overlay(torsoFront(bob))
                |> overlay(headFront(bob + 1));              // 頭が後ろへ
        match f {
            case 0 => whiteOut(shift(0, 1, body))            // 全身白フラッシュ+手前へ
            case 1 => shift(0, 0, body)                      // のけぞり
            case _ => body
        }

    def damageUp(f: Int32): Canvas =
        // 奥へノックバック（上向きは背中を見せて奥へ）
        let bob = 0;
        let body =
            legsFront(0, 1)
                |> overlay(armFront(8, bob, 2, false))
                |> overlay(armFront(22, bob, 2, false))
                |> overlay(torsoBack(bob))
                |> overlay(headBack(bob));
        match f {
            case 0 => whiteOut(shift(0, 0 - 1, body))        // 奥（上）へ+白
            case 1 => shift(0, 0 - 1, body)
            case _ => body
        }

    def damageSide(f: Int32): Canvas =
        // 横（右）へノックバック。左向きの体が右へ2pxずれてのけぞる。
        let bob = 0;
        let body =
            empty()
                |> rectFill(13, bob + 19, 3, 8, coatC())
                |> rectFill(16, bob + 19, 3, 8, coatC())
                |> hline(12, 28, 5, bootC())
                |> hline(12, 29, 5, bootC())
                |> hline(16, 28, 4, bootC())
                |> hline(16, 29, 4, bootC())
                |> rectFill(13, bob + 11, 6, 8, coatC())
                |> vline(13, bob + 12, 6, shirtC())
                |> vline(14, bob + 13, 5, vestC())
                |> overlay(bowTie(13, bob + 11))
                |> overlay(headSide(bob))
                // 手前の腕が跳ね上がる
                |> line(14, bob + 12, 17, bob + 9, coatC())
                |> dot(18, bob + 8, skinC());
        match f {
            case 0 => whiteOut(shift(2, 0, body))            // 右へ+白フラッシュ
            case 1 => shift(2, 0, body)                      // のけぞり保持
            case _ => shift(1, 0, body)                      // 戻り始め
        }

    // ════════════════════════════════════════════════════════════
    //  Death（膝どまり・正面・6コマ）
    //  よろめき(0,1) → 膝から崩れ(2,3) → 膝立ち前傾がくり(4,5)
    //  最終コマで山高帽が頭から外れて隣に転がり落ちる。倒れ伏さない。
    // ════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas = match f {
        case 0 => deathStagger(0)                            // よろめき（右へ傾ぐ）
        case 1 => deathStagger(1)                            // よろめき（左へ戻り膝ゆるむ）
        case 2 => deathCollapse(0)                           // 膝から崩れ始め
        case 3 => deathCollapse(1)                           // 膝がつく
        case 4 => deathKneel(0)                              // 膝立ち・前傾始め
        case _ => deathKneelHatOff()                         // 前傾がくり＋帽子が転がり落ちる
    }

    // よろめき（まだ立っている・上体が傾ぐ）。
    def deathStagger(phase: Int32): Canvas =
        let lean = if (phase == 0) 1 else 0 - 1;             // 左右に揺れる
        legsFront(0, 0)
            |> overlay(armFront(9 + lean, 0, 3, false))      // 腕がだらり
            |> overlay(armFront(21 + lean, 0, 3, true))
            |> overlay(shift(lean, 0, torsoFront(0)))
            |> overlay(shift(lean, 1, headFront(0)))         // 頭が垂れる

    // 膝から崩れ（腰が落ち、脚がたたまれる。足元は残る）。
    def deathCollapse(phase: Int32): Canvas =
        let drop = phase + 1;                                // 1..2px 腰が沈む
        empty()
            // たたまれた脚（膝が接地方向へ）
            |> rectFill(11, 24 + phase, 4, 5 - phase, coatC())
            |> rectFill(17, 24 + phase, 4, 5 - phase, coatC())
            |> hline(11, 28, 4, bootC())                     // 足はまだ地面
            |> hline(11, 29, 4, bootC())
            |> hline(17, 28, 4, bootC())
            |> hline(17, 29, 4, bootC())
            // 胴（沈む）
            |> overlay(shift(0, drop + 2, torsoFront(0)))
            |> overlay(shift(1, drop + 3, headFront(0)))     // 頭が前へ落ちる
            // だらりと下がる腕
            |> overlay(shift(0 - 1, drop + 2, armFront(9, 0, 4, false)))
            |> overlay(shift(1, drop + 2, armFront(21, 0, 4, true)))

    // 膝立ち（両膝つき・上体を立てて前傾）。
    def deathKneel(phase: Int32): Canvas =
        let fwd = phase;                                     // 前傾量
        empty()
            // 膝立ち: すね〜足が地面に折りたたまれる
            |> rectFill(11, 26, 4, 3, coatC())               // 折れた脚（左）
            |> rectFill(17, 26, 4, 3, coatC())               // 折れた脚（右）
            |> hline(10, 28, 5, bootC())                     // 甲・足先が地面
            |> hline(10, 29, 5, bootC())
            |> hline(17, 28, 5, bootC())
            |> hline(17, 29, 5, bootC())
            // 胴（膝の上に座り前へ傾ぐ）
            |> rectFill(11 + fwd, 15, 10, 8, coatC())
            |> vline(15 + fwd, 16, 5, shirtC())
            |> vline(16 + fwd, 16, 5, vestC())
            |> overlay(bowTie(15 + fwd, 15))
            // うなだれた腕
            |> vline(10 + fwd, 16, 8, coatC())
            |> dot(10 + fwd, 24, skinC())
            |> vline(21 + fwd, 16, 8, coatC())
            |> dot(21 + fwd, 24, skinC())
            |> dot(21 + fwd, 25, bladeC())                   // ナイフを取り落とす寸前
            // 前へ倒れた頭（帽子はまだ乗っている）
            |> overlay(shift(fwd + 2, 6, headFront(0)))

    // 最終コマ: 前傾がくり。頭から帽子が外れて右隣に転がり落ちる。
    // 帽子だけ地面に。体は膝立ちのまま（倒れ伏さない）。
    def deathKneelHatOff(): Canvas =
        empty()
            // 膝立ちの脚（前コマと同じ接地）
            |> rectFill(11, 26, 4, 3, coatC())
            |> rectFill(17, 26, 4, 3, coatC())
            |> hline(10, 28, 5, bootC())
            |> hline(10, 29, 5, bootC())
            |> hline(17, 28, 5, bootC())
            |> hline(17, 29, 5, bootC())
            // 前傾がくりと深く倒れた胴
            |> rectFill(13, 16, 10, 8, coatC())
            |> vline(17, 17, 5, shirtC())
            |> vline(18, 17, 5, vestC())
            |> overlay(bowTie(17, 16))
            // 帽子を失い、うつむいた素の頭（顔＝skin・髪なしの後頭部感）
            |> rectFill(14, 12, 7, 5, skinC())               // むき出しの頭（帽子なし）
            |> hline(14, 12, 7, RoguePalette.darkBrown())    // 髪の生え際
            |> dot(15, 14, bootC())                          // 伏せ目
            |> dot(19, 14, bootC())
            // うなだれた腕（ナイフを取り落とす）
            |> vline(12, 17, 8, coatC())
            |> dot(12, 25, skinC())
            |> vline(23, 17, 8, coatC())
            |> dot(23, 25, skinC())
            |> dot(24, 27, bladeC())                         // 落ちたナイフ
            // ── 転がり落ちた山高帽（右隣の地面・横倒し）──
            |> rectFill(25, 26, 5, 3, hatC())                // クラウンが横倒しに
            |> vline(24, 25, 5, hatC())                      // つばが立って見える
            |> hline(25, 25, 5, hatC())
            |> hline(24, 29, 6, bootC())                     // 帽子の接地影
    }
