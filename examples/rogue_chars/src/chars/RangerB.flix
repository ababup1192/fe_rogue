// RangerB — 山岳の猟師（クロスボウ）。毛皮帽(ushanka)の耳あてが左右に垂れ、
// 鼻が赤い、ずんぐりした体型。鉄のクロスボウを常に構え気味に携える。
//
// アンカー規約（RogueStage 準拠）:
//   足元 y=29 接地・体の中心 x=15..16・身長 ≤28px・Side は左向き作画。
// 色は RoguePalette の関数のみ（リテラル禁止）。
//
// 描き方の芯:
//   - クロスボウは主役。待機/歩行でも横棒(prod)と弦(string)が常時見える。
//   - 攻撃は「装填2コマ→構え2コマ→発射(ボルト飛翔)2コマ」のメカ感で見得を切る。
//   - 個性は頭部(ushanka+赤鼻)で出す。全方向・全クリップに反映（背面は帽子の裏）。

mod RangerB {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, discFill, overlay, hflip, shift}

    pub def name(): String = "RANGER B もう獲物は逃さん"

    // ── 色（毛皮/外套/肌/赤鼻/鉄）──
    def furC(): Color = RoguePalette.brown()        // 毛皮帽・襟の毛
    def furHiC(): Color = RoguePalette.tan()        // 毛皮のハイライト
    def coatC(): Color = RoguePalette.darkBrown()   // 外套
    def coatShadeC(): Color = RoguePalette.olive()  // 外套の陰
    def skinC(): Color = RoguePalette.skin()        // 肌
    def noseC(): Color = RoguePalette.salmon()      // 赤い鼻
    def ironC(): Color = RoguePalette.silver()      // クロスボウの鉄
    def ironShadeC(): Color = RoguePalette.gray()   // 鉄の陰
    def stringC(): Color = RoguePalette.paleBlue()  // 弦（明色の細い線）
    def boltC(): Color = RoguePalette.yellow()      // 飛ぶボルト（明色）
    def flashC(): Color = RoguePalette.white()      // 被弾フラッシュ/使用フラッシュ

    // 範囲外frame を各クリップのコマ数に丸める（負数補正つき）。
    def wrap(n: Int32, count: Int32): Int32 =
        let m = Int32.remainder(n, count);
        if (m < 0) m + count else m

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

    // ══════════════════════════════════════════════════════════════
    //  頭部パーツ（ushanka + 赤鼻）。dy で全身の上下バウンドに追従。
    // ══════════════════════════════════════════════════════════════

    // 正面の頭: 毛皮帽の丸い天+耳あてが左右に垂れる。顔は中央、鼻が赤い。
    def headDown(dy: Int32): Canvas =
        empty()
            // 毛皮帽の丸い天（もこもこ）
            |> hline(12, 3 + dy, 8, furC())
            |> hline(11, 4 + dy, 10, furC())
            |> dotAt(11, 4 + dy, furHiC())
            |> dotAt(13, 3 + dy, furHiC())
            |> hline(11, 5 + dy, 10, furC())
            // 帽子の前ひさし（毛の陰）
            |> hline(12, 6 + dy, 8, furHiC())
            // 顔（肌）
            |> hline(13, 7 + dy, 6, skinC())
            |> hline(13, 8 + dy, 6, skinC())
            |> hline(13, 9 + dy, 6, skinC())
            // 目（陰で 2 点）
            |> dotAt(14, 8 + dy, coatShadeC())
            |> dotAt(17, 8 + dy, coatShadeC())
            // 赤い鼻（中央・でっぷり）
            |> dotAt(15, 9 + dy, noseC())
            |> dotAt(16, 9 + dy, noseC())
            // 左右に垂れる耳あて
            |> vline(11, 6 + dy, 4, furC())
            |> vline(20, 6 + dy, 4, furC())
            |> dotAt(11, 9 + dy, furHiC())
            |> dotAt(20, 9 + dy, furHiC())

    // 背面の頭: 帽子の裏（後頭部）+ 垂れた耳あての裏。顔は見えない。
    def headUp(dy: Int32): Canvas =
        empty()
            |> hline(12, 3 + dy, 8, furC())
            |> hline(11, 4 + dy, 10, furC())
            |> dotAt(18, 4 + dy, furHiC())
            |> hline(11, 5 + dy, 10, furC())
            |> hline(11, 6 + dy, 10, furC())
            // 後頭部の毛皮の陰
            |> hline(12, 7 + dy, 8, furHiC())
            |> hline(13, 8 + dy, 6, furC())
            |> hline(13, 9 + dy, 6, furHiC())
            // 垂れた耳あての裏
            |> vline(11, 6 + dy, 4, furC())
            |> vline(20, 6 + dy, 4, furC())

    // 左向きの頭: 帽子の天+うなじ側の耳あて+前に突き出た赤鼻。
    def headSide(dy: Int32): Canvas =
        empty()
            |> hline(12, 3 + dy, 7, furC())
            |> hline(11, 4 + dy, 8, furC())
            |> dotAt(12, 3 + dy, furHiC())
            |> hline(11, 5 + dy, 8, furC())
            |> hline(11, 6 + dy, 8, furHiC())
            // 顔（左が前）
            |> hline(11, 7 + dy, 6, skinC())
            |> hline(12, 8 + dy, 5, skinC())
            |> hline(12, 9 + dy, 5, skinC())
            // 目（1 点・前寄り）
            |> dotAt(13, 8 + dy, coatShadeC())
            // 赤い鼻が前(左)へ突き出る
            |> dotAt(10, 8 + dy, noseC())
            |> dotAt(11, 8 + dy, noseC())
            // うなじ側に垂れる耳あて（後ろ=右）
            |> vline(18, 6 + dy, 5, furC())
            |> dotAt(18, 10 + dy, furHiC())

    // ══════════════════════════════════════════════════════════════
    //  胴（ずんぐりした毛皮外套）。ox/oy で微妙な傾き・上下に使う。
    // ══════════════════════════════════════════════════════════════

    // 正面の胴: 幅広の外套。肩に毛皮の襟。足元は y=29 まで。
    def torsoDown(dy: Int32): Canvas =
        empty()
            // 毛皮の襟
            |> hline(11, 10 + dy, 10, furC())
            |> dotAt(12, 10 + dy, furHiC())
            |> dotAt(19, 10 + dy, furHiC())
            // 外套の胴（ずんぐり）
            |> rectFill(11, 11 + dy, 10, 8, coatC())
            // 前合わせの陰
            |> vline(15, 11 + dy, 8, coatShadeC())
            |> vline(16, 11 + dy, 8, coatShadeC())
            // 裾の陰
            |> hline(11, 18 + dy, 10, coatShadeC())

    // 正面の脚（足元 y=29 接地）。lx/rx で歩幅を作る。
    def legsDown(lx: Int32, rx: Int32): Canvas =
        empty()
            |> vline(12 + lx, 19, 10, coatC())
            |> vline(13 + lx, 19, 10, coatShadeC())
            |> vline(18 + rx, 19, 10, coatC())
            |> vline(19 + rx, 19, 10, coatShadeC())
            // ブーツ（接地）
            |> hline(12 + lx, 28, 2, darkFur())
            |> hline(18 + rx, 28, 2, darkFur())
            |> hline(12 + lx, 29, 2, darkFur())
            |> hline(18 + rx, 29, 2, darkFur())

    def darkFur(): Color = RoguePalette.olive()

    // 背面の胴
    def torsoUp(dy: Int32): Canvas =
        empty()
            |> hline(11, 10 + dy, 10, furC())
            |> dotAt(13, 10 + dy, furHiC())
            |> rectFill(11, 11 + dy, 10, 8, coatC())
            // 背中の縦じわ
            |> vline(13, 11 + dy, 7, coatShadeC())
            |> vline(18, 11 + dy, 7, coatShadeC())
            |> hline(11, 18 + dy, 10, coatShadeC())

    // 左向きの胴（外套は前後に厚み）
    def torsoSide(dy: Int32): Canvas =
        empty()
            |> hline(11, 10 + dy, 9, furC())
            |> dotAt(12, 10 + dy, furHiC())
            // 外套本体
            |> rectFill(11, 11 + dy, 9, 8, coatC())
            // 前面(左)の明るい面
            |> vline(11, 11 + dy, 7, furHiC())
            // 背面(右)の陰
            |> vline(19, 11 + dy, 7, coatShadeC())
            |> hline(11, 18 + dy, 9, coatShadeC())

    // 左向きの脚（前=左脚 fx・後=右脚 bx）
    def legsSide(fx: Int32, bx: Int32): Canvas =
        empty()
            |> vline(13 + bx, 19, 10, coatShadeC())
            |> vline(14 + bx, 19, 10, coatShadeC())
            |> vline(15 + fx, 19, 10, coatC())
            |> vline(16 + fx, 19, 10, coatShadeC())
            |> hline(13 + bx, 28, 2, darkFur())
            |> hline(13 + bx, 29, 2, darkFur())
            |> hline(15 + fx, 28, 2, darkFur())
            |> hline(15 + fx, 29, 2, darkFur())

    // ══════════════════════════════════════════════════════════════
    //  クロスボウ（横棒 prod + ストック + 弦）。向き別に置く。
    // ══════════════════════════════════════════════════════════════

    // 正面: 体の前に水平に構える横棒。中央にストック、弦は横棒の内側。
    def crossbowDown(dy: Int32): Canvas =
        empty()
            // 横棒（prod）: 幅広の弓 y=13
            |> hline(9, 13 + dy, 14, ironC())
            |> dotAt(9, 13 + dy, ironShadeC())
            |> dotAt(22, 13 + dy, ironShadeC())
            |> hline(10, 14 + dy, 12, ironShadeC())
            // 弦（横棒の少し内側）
            |> hline(11, 12 + dy, 10, stringC())
            // ストック（中央・下へ握り）
            |> vline(15, 13 + dy, 4, ironShadeC())
            |> vline(16, 13 + dy, 4, ironC())

    // 背面: 横棒は肩越しに見える（体の奥）。弦は見えにくいので細く。
    def crossbowUp(dy: Int32): Canvas =
        empty()
            |> hline(9, 12 + dy, 14, ironShadeC())
            |> dotAt(9, 12 + dy, ironC())
            |> dotAt(22, 12 + dy, ironC())
            |> hline(10, 13 + dy, 12, ironC())
            |> vline(15, 12 + dy, 3, ironShadeC())
            |> vline(16, 12 + dy, 3, ironC())

    // 左向き: ストックが後ろ(右)、横棒が前(左)へ突き出る。弦が縦に張る。
    def crossbowSide(dy: Int32): Canvas =
        empty()
            // ストック（後ろ=右・肩に当てる）
            |> hline(14, 13 + dy, 6, ironC())
            |> hline(14, 14 + dy, 6, ironShadeC())
            // 前へ伸びる本体
            |> hline(7, 13 + dy, 8, ironShadeC())
            // 前端の横棒（縦に立つ弓）
            |> vline(7, 10 + dy, 8, ironC())
            |> dotAt(7, 10 + dy, ironShadeC())
            |> dotAt(7, 17 + dy, ironShadeC())
            // 弦（前端で縦に張る）
            |> vline(9, 11 + dy, 6, stringC())

    // ══════════════════════════════════════════════════════════════
    //  腕（肩から手・2px 幅）。武器を握る手を強調。
    // ══════════════════════════════════════════════════════════════

    // 正面: 両腕を前へ、武器を支える。
    def armsDown(dy: Int32, swing: Int32): Canvas =
        empty()
            |> vline(10, 12 + dy, 4 + swing, coatC())
            |> vline(11, 12 + dy, 4 + swing, coatShadeC())
            |> vline(20, 12 + dy - swing, 4 + swing, coatC())
            |> vline(21, 12 + dy - swing, 4 + swing, coatShadeC())
            // 手（肌）
            |> dotAt(10, 15 + dy + swing, skinC())
            |> dotAt(21, 15 + dy - swing, skinC())

    def armsUp(dy: Int32, swing: Int32): Canvas =
        empty()
            |> vline(10, 12 + dy, 4 + swing, coatC())
            |> vline(11, 12 + dy, 4 + swing, coatShadeC())
            |> vline(20, 12 + dy - swing, 4 + swing, coatC())
            |> vline(21, 12 + dy - swing, 4 + swing, coatShadeC())

    // ══════════════════════════════════════════════════════════════
    //  IdleDown — どっしり、肩で息（2px の上下呼吸）。
    // ══════════════════════════════════════════════════════════════

    def breathDy(f: Int32): Int32 = match f {
        case 0 => 0
        case 1 => 1
        case 2 => 1
        case _ => 0
    }

    def idleDown(f: Int32): Canvas =
        let dy = breathDy(f);
        legsDown(0, 0)
            |> overlay(torsoDown(dy))
            |> overlay(armsDown(dy, 0))
            |> overlay(crossbowDown(dy))
            |> overlay(headDown(dy))

    def idleUp(f: Int32): Canvas =
        let dy = breathDy(f);
        legsDown(0, 0)
            |> overlay(crossbowUp(dy))
            |> overlay(torsoUp(dy))
            |> overlay(armsUp(dy, 0))
            |> overlay(headUp(dy))

    def idleSide(f: Int32): Canvas =
        let dy = breathDy(f);
        legsSide(0, 0)
            |> overlay(torsoSide(dy))
            |> overlay(crossbowSide(dy))
            |> overlay(armSideHold(dy))
            |> overlay(headSide(dy))

    // 左向きで武器を支える前腕（肩から前へ）。
    def armSideHold(dy: Int32): Canvas =
        empty()
            |> line(15, 12 + dy, 10, 13 + dy, coatC())
            |> line(15, 13 + dy, 10, 14 + dy, coatShadeC())
            |> dotAt(10, 13 + dy, skinC())
            |> dotAt(10, 14 + dy, skinC())

    // ══════════════════════════════════════════════════════════════
    //  Walk — 雪を踏む確かめ歩き。足は常に接地・体が 1px 上下。
    //  4 コマ全部違う絵。歩幅 2〜3px + 腕振り。
    // ══════════════════════════════════════════════════════════════

    // 正面歩き: 左右の足が前後に開く（接地維持）。
    def walkDown(f: Int32): Canvas =
        let dy = match f { case 0 => 0 case 1 => 1 case 2 => 0 case _ => 1 };
        let (lx, rx) = match f {
            case 0 => (-1, 1)   // 左足前・右足後
            case 1 => (0, 0)    // そろえる（沈む）
            case 2 => (1, -1)   // 右足前・左足後
            case _ => (0, 0)
        };
        let sw = match f { case 0 => 1 case 2 => -1 case _ => 0 };
        legsDownWalk(lx, rx)
            |> overlay(torsoDown(dy))
            |> overlay(armsDown(dy, sw))
            |> overlay(crossbowDown(dy))
            |> overlay(headDown(dy))

    // 歩行専用の脚（前後に踏み出す・両足とも y=29 接地）。
    def legsDownWalk(lx: Int32, rx: Int32): Canvas =
        empty()
            |> vline(12 + lx, 19, 10, coatC())
            |> vline(13 + lx, 19, 10, coatShadeC())
            |> vline(18 + rx, 19, 10, coatC())
            |> vline(19 + rx, 19, 10, coatShadeC())
            |> hline(12 + lx, 28, 3, darkFur())
            |> hline(12 + lx, 29, 3, darkFur())
            |> hline(18 + rx, 28, 3, darkFur())
            |> hline(18 + rx, 29, 3, darkFur())

    def walkUp(f: Int32): Canvas =
        let dy = match f { case 0 => 0 case 1 => 1 case 2 => 0 case _ => 1 };
        let (lx, rx) = match f {
            case 0 => (-1, 1)
            case 1 => (0, 0)
            case 2 => (1, -1)
            case _ => (0, 0)
        };
        let sw = match f { case 0 => 1 case 2 => -1 case _ => 0 };
        legsDownWalk(lx, rx)
            |> overlay(crossbowUp(dy))
            |> overlay(torsoUp(dy))
            |> overlay(armsUp(dy, sw))
            |> overlay(headUp(dy))

    // 左向き歩き: 前脚と後脚が交互に踏み出す。f0 は左右非対称（lint 要件）。
    def walkSide(f: Int32): Canvas =
        let dy = match f { case 0 => 0 case 1 => 1 case 2 => 0 case _ => 1 };
        let (fx, bx) = match f {
            case 0 => (2, -3)   // 前脚を大きく前へ（非対称）
            case 1 => (0, 0)
            case 2 => (-2, 3)   // 後脚が前へ
            case _ => (0, 0)
        };
        legsSide(fx, bx)
            |> overlay(torsoSide(dy))
            |> overlay(crossbowSide(dy))
            |> overlay(armSideWalk(dy, f))
            |> overlay(headSide(dy))

    // 左向きの腕振り（前後に振れる）。
    def armSideWalk(dy: Int32, f: Int32): Canvas =
        let ax = match f { case 0 => -1 case 2 => 1 case _ => 0 };
        empty()
            |> line(15, 12 + dy, 10 + ax, 14 + dy, coatC())
            |> line(15, 13 + dy, 10 + ax, 15 + dy, coatShadeC())
            |> dotAt(10 + ax, 14 + dy, skinC())
            |> dotAt(10 + ax, 15 + dy, skinC())

    // ══════════════════════════════════════════════════════════════
    //  Attack (6 コマ): 装填(0,1) → 構え(2,3) → 発射(4,5)。
    //  発射コマでボルト(太い明色の直線)が向きへ飛ぶ。見得を極端に。
    // ══════════════════════════════════════════════════════════════

    // ── AttackDown: ボルトは下(手前)へ飛ぶ ──
    def attackDown(f: Int32): Canvas =
        let base = legsDown(0, 0) |> overlay(torsoDown(0));
        match f {
            case 0 =>
                // 装填1: 弓を体に引き寄せ、レバーを引く手が上に
                base
                    |> overlay(crossbowDown(1))
                    |> overlay(loadArmsDown(0))
                    |> overlay(headDown(0))
            case 1 =>
                // 装填2: レバー引き切り（弦が起きる=stringを高く）
                base
                    |> overlay(crossbowLoadedDown(1))
                    |> overlay(loadArmsDown(1))
                    |> overlay(headDown(0))
            case 2 =>
                // 構え1: 前へ突き出す
                base
                    |> overlay(shift(0, 1, crossbowDown(0)))
                    |> overlay(armsDown(0, 0))
                    |> overlay(headDown(0))
            case 3 =>
                // 構え2: ぐっと狙い（弦を最大に張る）
                base
                    |> overlay(shift(0, 2, crossbowDown(0)))
                    |> overlay(armsDown(1, 0))
                    |> overlay(headDown(0))
            case 4 =>
                // 発射: ボルトが下へ飛ぶ（弦は弾け戻る）
                base
                    |> overlay(crossbowDown(0))
                    |> overlay(armsDown(0, 0))
                    |> overlay(boltVertical(15, 20, 27, true))
                    |> overlay(headDown(0))
            case _ =>
                // 余韻: ボルトさらに前・反動で弓が少し戻る
                base
                    |> overlay(crossbowDown(-1))
                    |> overlay(armsDown(0, 0))
                    |> overlay(boltVertical(15, 24, 29, true))
                    |> overlay(headDown(0))
        }

    // 装填中の腕（片手が上=レバー引き）。
    def loadArmsDown(pull: Int32): Canvas =
        empty()
            |> vline(10, 12, 4, coatC())
            |> vline(11, 12, 4, coatShadeC())
            |> dotAt(10, 15, skinC())
            // 引き手（上へ）
            |> vline(20, 9 - pull, 5, coatC())
            |> vline(21, 9 - pull, 5, coatShadeC())
            |> dotAt(21, 9 - pull, skinC())

    // 弦を起こした（張った）状態の弓。
    def crossbowLoadedDown(dy: Int32): Canvas =
        crossbowDown(dy)
            |> hline(11, 10 + dy, 10, stringC())   // 弦が高く起きる

    // 縦に飛ぶ太いボルト（明色 2px + 先端）。downwards なら y0<y1。
    def boltVertical(cx: Int32, y0: Int32, y1: Int32, _down: Bool): Canvas =
        empty()
            |> vline(cx, y0, y1 - y0 + 1, boltC())
            |> vline(cx + 1, y0, y1 - y0 + 1, boltC())
            // 矢じり（先端を太く）
            |> hline(cx - 1, y1, 4, boltC())
            |> dotAt(cx, y1 + 1, ironC())

    // ── AttackUp: ボルトは上(奥)へ飛ぶ ──
    def attackUp(f: Int32): Canvas =
        let base = legsDown(0, 0);
        match f {
            case 0 =>
                base
                    |> overlay(crossbowUp(1))
                    |> overlay(torsoUp(0))
                    |> overlay(loadArmsUp(0))
                    |> overlay(headUp(0))
            case 1 =>
                base
                    |> overlay(crossbowUp(1))
                    |> overlay(torsoUp(0))
                    |> overlay(loadArmsUp(1))
                    |> overlay(headUp(0))
            case 2 =>
                base
                    |> overlay(shift(0, -1, crossbowUp(0)))
                    |> overlay(torsoUp(0))
                    |> overlay(armsUp(0, 0))
                    |> overlay(headUp(0))
            case 3 =>
                base
                    |> overlay(shift(0, -2, crossbowUp(0)))
                    |> overlay(torsoUp(0))
                    |> overlay(armsUp(1, 0))
                    |> overlay(headUp(0))
            case 4 =>
                base
                    |> overlay(boltVertical(15, 2, 9, false))
                    |> overlay(crossbowUp(0))
                    |> overlay(torsoUp(0))
                    |> overlay(armsUp(0, 0))
                    |> overlay(headUp(0))
            case _ =>
                base
                    |> overlay(boltVertical(15, 0, 5, false))
                    |> overlay(crossbowUp(0))
                    |> overlay(torsoUp(0))
                    |> overlay(armsUp(0, 0))
                    |> overlay(headUp(0))
        }

    def loadArmsUp(pull: Int32): Canvas =
        empty()
            |> vline(10, 12, 4, coatC())
            |> vline(11, 12, 4, coatShadeC())
            |> vline(20, 9 - pull, 5, coatC())
            |> vline(21, 9 - pull, 5, coatShadeC())

    // ── AttackSide: ボルトは左(前)へ飛ぶ。腕と弓が大きく前へ伸びる ──
    def attackSide(f: Int32): Canvas =
        let base = legsSide(0, 0) |> overlay(torsoSide(0));
        match f {
            case 0 =>
                // 装填1: 弓を引き寄せ、後ろ手で弦を引く
                base
                    |> overlay(crossbowSide(0))
                    |> overlay(loadArmSide(0))
                    |> overlay(headSide(0))
            case 1 =>
                // 装填2: 引き切り（弦を後ろへ）
                base
                    |> overlay(crossbowLoadedSide(0))
                    |> overlay(loadArmSide(2))
                    |> overlay(headSide(0))
            case 2 =>
                // 構え1: 前へ突き出す
                base
                    |> overlay(shift(-2, 0, crossbowSide(0)))
                    |> overlay(aimArmSide(0))
                    |> overlay(headSide(0))
            case 3 =>
                // 構え2: 狙い定める（さらに前へ）
                base
                    |> overlay(shift(-3, 0, crossbowSide(0)))
                    |> overlay(aimArmSide(1))
                    |> overlay(headSide(0))
            case 4 =>
                // 発射: ボルトが前(左)へ飛ぶ
                base
                    |> overlay(shift(-2, 0, crossbowSide(0)))
                    |> overlay(aimArmSide(0))
                    |> overlay(boltHorizontalLeft(2, 9, 14))
                    |> overlay(headSide(0))
            case _ =>
                // 余韻: ボルトさらに前・反動で弓が戻る
                base
                    |> overlay(crossbowSide(0))
                    |> overlay(aimArmSide(0))
                    |> overlay(boltHorizontalLeft(0, 5, 14))
                    |> overlay(headSide(0))
        }

    // 左向き装填の腕（後ろ手を後方=右へ引く）。
    def loadArmSide(pull: Int32): Canvas =
        empty()
            |> line(15, 12, 20 + pull, 12, coatC())
            |> line(15, 13, 20 + pull, 13, coatShadeC())
            |> dotAt(20 + pull, 12, skinC())
            |> dotAt(20 + pull, 13, skinC())

    // 左向き狙いの腕（前へ真っ直ぐ支える）。
    def aimArmSide(ext: Int32): Canvas =
        empty()
            |> line(15, 13, 9 - ext, 13, coatC())
            |> line(15, 14, 9 - ext, 14, coatShadeC())
            |> dotAt(9 - ext, 13, skinC())
            |> dotAt(9 - ext, 14, skinC())

    // 弦を後方へ引いた左向きの弓。
    def crossbowLoadedSide(dy: Int32): Canvas =
        crossbowSide(dy)
            |> line(9, 11 + dy, 14, 13 + dy, stringC())   // 弦が後方へ張る

    // 左へ飛ぶ太いボルト（明色 2px + 矢じり）。x1<x0 の向き。
    def boltHorizontalLeft(x0: Int32, x1: Int32, cy: Int32): Canvas =
        empty()
            |> hline(x0, cy, x1 - x0 + 1, boltC())
            |> hline(x0, cy + 1, x1 - x0 + 1, boltC())
            |> vline(x0, cy - 1, 4, boltC())              // 矢じり
            |> dotAt(x0 - 1, cy, ironC())

    // ══════════════════════════════════════════════════════════════
    //  UseItem (4 コマ): 掲げる → 明色フラッシュ → 使う。方向別。
    //  猟師らしく「携行食/薬を口へ」の3拍。
    // ══════════════════════════════════════════════════════════════

    def useItemDown(f: Int32): Canvas =
        let base = legsDown(0, 0) |> overlay(torsoDown(0)) |> overlay(crossbowDown(0));
        match f {
            case 0 =>
                // 掲げる: 片手を高く上げる（アイテムを持つ）
                base
                    |> overlay(raiseArmDown(3))
                    |> overlay(itemBundle(20, 6))
                    |> overlay(headDown(0))
            case 1 =>
                // フラッシュ: アイテムが白く光る
                base
                    |> overlay(raiseArmDown(3))
                    |> overlay(flashBurst(20, 5))
                    |> overlay(headDown(0))
            case 2 =>
                // 使う: 手を口元へ下ろす
                base
                    |> overlay(raiseArmDown(1))
                    |> overlay(itemBundle(19, 8))
                    |> overlay(headDown(0))
            case _ =>
                // 余韻: 手を戻す
                base
                    |> overlay(armsDown(0, 0))
                    |> overlay(headDown(0))
        }

    // 掲げる腕（up 分だけ上へ）。
    def raiseArmDown(up: Int32): Canvas =
        empty()
            |> vline(10, 12, 4, coatC())
            |> vline(11, 12, 4, coatShadeC())
            |> dotAt(10, 15, skinC())
            |> line(20, 12, 20, 12 - up, coatC())
            |> line(21, 12, 21, 12 - up, coatShadeC())
            |> dotAt(20, 12 - up, skinC())

    // 携行品の包み（tan の小さな塊）。
    def itemBundle(x: Int32, y: Int32): Canvas =
        empty()
            |> rectFill(x, y, 3, 2, furHiC())
            |> dotAt(x + 1, y, furC())

    // 明色フラッシュ（白い十字の光）。
    def flashBurst(cx: Int32, cy: Int32): Canvas =
        empty()
            |> hline(cx - 2, cy, 5, flashC())
            |> vline(cx, cy - 2, 5, flashC())
            |> dotAt(cx, cy, flashC())

    def useItemUp(f: Int32): Canvas =
        let base = legsDown(0, 0) |> overlay(crossbowUp(0)) |> overlay(torsoUp(0));
        match f {
            case 0 =>
                base
                    |> overlay(raiseArmUp(3))
                    |> overlay(itemBundle(20, 6))
                    |> overlay(headUp(0))
            case 1 =>
                base
                    |> overlay(raiseArmUp(3))
                    |> overlay(flashBurst(21, 5))
                    |> overlay(headUp(0))
            case 2 =>
                base
                    |> overlay(raiseArmUp(1))
                    |> overlay(headUp(0))
            case _ =>
                base
                    |> overlay(armsUp(0, 0))
                    |> overlay(headUp(0))
        }

    def raiseArmUp(up: Int32): Canvas =
        empty()
            |> vline(10, 12, 4, coatC())
            |> vline(11, 12, 4, coatShadeC())
            |> line(20, 12, 20, 12 - up, coatC())
            |> line(21, 12, 21, 12 - up, coatShadeC())
            |> dotAt(20, 12 - up, skinC())

    def useItemSide(f: Int32): Canvas =
        let base = legsSide(0, 0) |> overlay(torsoSide(0)) |> overlay(crossbowSide(0));
        match f {
            case 0 =>
                // 掲げる: 前手を口元(左)へ上げる
                base
                    |> overlay(raiseArmSide(3))
                    |> overlay(itemBundle(9, 5))
                    |> overlay(headSide(0))
            case 1 =>
                base
                    |> overlay(raiseArmSide(3))
                    |> overlay(flashBurst(10, 5))
                    |> overlay(headSide(0))
            case 2 =>
                // 使う: 口元へ寄せる
                base
                    |> overlay(raiseArmSide(1))
                    |> overlay(itemBundle(10, 7))
                    |> overlay(headSide(0))
            case _ =>
                base
                    |> overlay(armSideHold(0))
                    |> overlay(headSide(0))
        }

    // 左向きで前手を上げる（口元へ）。
    def raiseArmSide(up: Int32): Canvas =
        empty()
            |> line(15, 13, 11, 13 - up, coatC())
            |> line(15, 14, 11, 14 - up, coatShadeC())
            |> dotAt(11, 13 - up, skinC())

    // ══════════════════════════════════════════════════════════════
    //  Damage (3 コマ): f0=全身白フラッシュ+ノックバック → のけぞり。
    //  Down=手前へ・Up=奥へ・Side=横へ。足は接地維持。
    // ══════════════════════════════════════════════════════════════

    // 全身シルエットを白で塗る（今のポーズの形をそのまま白フラッシュに）。
    def whitenAll(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, _) -> Map.insert(k, flashC(), acc), Map.empty(), cv)

    def damageDown(f: Int32): Canvas =
        match f {
            case 0 =>
                // 全身白フラッシュ + 手前(下)へ2px + のけぞり開始
                let body = legsDown(0, 0)
                    |> overlay(shift(0, 2, torsoDown(0)))
                    |> overlay(shift(0, 2, crossbowDown(0)))
                    |> overlay(shift(0, 2, armsDown(0, 0)))
                    |> overlay(shift(0, 3, headDown(0)));
                whitenAll(body)
            case 1 =>
                // のけぞり（上体が後ろへ反る）
                legsDown(0, 0)
                    |> overlay(shift(0, 1, torsoDown(0)))
                    |> overlay(shift(0, 1, crossbowDown(0)))
                    |> overlay(shift(-1, 1, armsDown(0, 0)))
                    |> overlay(shift(0, 1, headDown(0)))
            case _ =>
                // 戻り
                idleDown(0)
        }

    def damageUp(f: Int32): Canvas =
        match f {
            case 0 =>
                let body = legsDown(0, 0)
                    |> overlay(shift(0, -1, crossbowUp(0)))
                    |> overlay(shift(0, -1, torsoUp(0)))
                    |> overlay(shift(0, -1, armsUp(0, 0)))
                    |> overlay(shift(0, -2, headUp(0)));
                whitenAll(body)
            case 1 =>
                legsDown(0, 0)
                    |> overlay(shift(0, -1, crossbowUp(0)))
                    |> overlay(torsoUp(0))
                    |> overlay(armsUp(0, 0))
                    |> overlay(shift(0, -1, headUp(0)))
            case _ =>
                idleUp(0)
        }

    def damageSide(f: Int32): Canvas =
        match f {
            case 0 =>
                // 横(右=後方)へノックバック2px + 全身白
                let body = legsSide(0, 0)
                    |> overlay(shift(2, 0, torsoSide(0)))
                    |> overlay(shift(2, 0, crossbowSide(0)))
                    |> overlay(shift(2, 0, armSideHold(0)))
                    |> overlay(shift(3, 0, headSide(0)));
                whitenAll(body)
            case 1 =>
                // のけぞり（上体が右=後ろへ反る）
                legsSide(0, 0)
                    |> overlay(shift(1, 0, torsoSide(0)))
                    |> overlay(shift(1, 0, crossbowSide(0)))
                    |> overlay(shift(1, 0, armSideHold(0)))
                    |> overlay(shift(2, -1, headSide(0)))
            case _ =>
                idleSide(0)
        }

    // ══════════════════════════════════════════════════════════════
    //  Death (6 コマ・正面のみ): よろめき(0,1)→膝から崩れ(2,3)→
    //  膝立ち前傾がくり(4,5)。倒れ伏さない・膝は地面付近に残す。
    //  クロスボウを取り落とす演出。
    // ══════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas =
        match f {
            case 0 =>
                // よろめき1: 上体が右へ傾く、弓が手から離れかける
                legsDown(0, 0)
                    |> overlay(shift(1, 0, torsoDown(0)))
                    |> overlay(shift(1, -1, crossbowDown(0)))
                    |> overlay(shift(1, 0, armsDown(0, 0)))
                    |> overlay(shift(1, 0, headDown(0)))
            case 1 =>
                // よろめき2: 左へ揺り戻し、弓を取り落とす（下へ落下開始）
                legsDown(0, 0)
                    |> overlay(shift(-1, 0, torsoDown(0)))
                    |> overlay(shift(-1, 0, armsDown(1, 0)))
                    |> overlay(droppedBow(6, 22))
                    |> overlay(shift(-1, 0, headDown(0)))
            case 2 =>
                // 膝から崩れ1: 全体が沈む（脚を折る=短く）、弓は地面近く
                kneelLegs(2)
                    |> overlay(shift(0, 3, torsoDown(0)))
                    |> overlay(shift(0, 3, slumpArms(0)))
                    |> overlay(droppedBow(5, 27))
                    |> overlay(shift(0, 3, headDown(0)))
            case 3 =>
                // 膝から崩れ2: さらに沈む
                kneelLegs(4)
                    |> overlay(shift(0, 5, torsoDown(0)))
                    |> overlay(shift(0, 5, slumpArms(0)))
                    |> overlay(droppedBow(5, 28))
                    |> overlay(shift(0, 5, headDown(0)))
            case 4 =>
                // 膝立ち前傾1: 膝は地面、上体が前(下)へがくりと折れる
                kneelLegs(4)
                    |> overlay(shift(0, 6, bowTorso()))
                    |> overlay(shift(0, 6, slumpArms(1)))
                    |> overlay(droppedBow(5, 28))
                    |> overlay(shift(1, 8, headDown(0)))
            case _ =>
                // 膝立ち前傾2: 深くうなだれる（それでも膝立ちの立面が読める）
                kneelLegs(4)
                    |> overlay(shift(0, 6, bowTorso()))
                    |> overlay(shift(0, 7, slumpArms(1)))
                    |> overlay(droppedBow(5, 28))
                    |> overlay(shift(2, 9, headDown(0)))
        }

    // 膝立ちの脚（腿は残し、脛を折りたたむ。fold で短くする。接地維持）。
    def kneelLegs(fold: Int32): Canvas =
        empty()
            // 腿（腰から膝へ・fold 分短く）
            |> vline(12, 19 + fold, 10 - fold, coatC())
            |> vline(13, 19 + fold, 10 - fold, coatShadeC())
            |> vline(18, 19 + fold, 10 - fold, coatC())
            |> vline(19, 19 + fold, 10 - fold, coatShadeC())
            // 膝（地面に着く・y=29 付近）
            |> hline(12, 29, 2, darkFur())
            |> hline(18, 29, 2, darkFur())
            // 折りたたんだ脛（横に広がる）
            |> hline(10, 28, 3, coatShadeC())
            |> hline(19, 28, 3, coatShadeC())
            |> hline(10, 29, 12, darkFur())

    // 崩れる腕（だらりと下がる）。
    def slumpArms(droop: Int32): Canvas =
        empty()
            |> vline(10, 12 + droop, 5, coatC())
            |> vline(11, 12 + droop, 5, coatShadeC())
            |> vline(20, 12 + droop, 5, coatC())
            |> vline(21, 12 + droop, 5, coatShadeC())
            |> dotAt(10, 16 + droop, skinC())
            |> dotAt(21, 16 + droop, skinC())

    // 前傾した胴（下側がすぼまる台形）。
    def bowTorso(): Canvas =
        empty()
            |> hline(11, 10, 10, furC())
            |> rectFill(11, 11, 10, 5, coatC())
            |> vline(15, 11, 5, coatShadeC())
            |> vline(16, 11, 5, coatShadeC())
            |> hline(12, 16, 8, coatShadeC())

    // 取り落としたクロスボウ（地面に転がる・横向きの塊）。
    def droppedBow(x: Int32, y: Int32): Canvas =
        empty()
            |> hline(x, y, 8, ironC())
            |> hline(x, y + 1, 8, ironShadeC())
            |> vline(x, y - 1, 3, ironC())
            |> dotAt(x + 3, y, stringC())
            |> dotAt(x + 4, y, stringC())

    // ── 小ヘルパ: dot を pipe 部分適用で使う ──
    def dotAt(x: Int32, y: Int32, c: Color, cv: Canvas): Canvas =
        dot(x, y, c, cv)
}
