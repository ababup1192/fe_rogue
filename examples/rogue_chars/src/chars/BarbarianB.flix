// BarbarianB — 北方の女バーサーカー。金髪の長い三つ編みと頬の水色戦化粧が目印。
// 右手に手斧・左手に投げ斧の二刀流。攻撃は体ごと回る回転斬りで、
// 斧の軌跡（シアンの円弧）が体の周りを一周する。
//
// 作画規約: 足元 y=29・中心 x=15..16・横向き系は左向き。
// 部品(頭/三つ編み/胴/腕/脚/斧)を関数で持ち、ポーズごとに座標をずらして合成する。

mod BarbarianB {

    pub def name(): String = "BARBARIAN B 三つ編みなびく回転斬りの戦乙女"

    // ── 色（すべて RoguePalette 参照・5系統）──

    def hairC(): Color  = RoguePalette.yellow()    // 金髪
    def hairD(): Color  = RoguePalette.mustard()   // 三つ編みの編み目・革帯
    def fleshC(): Color = RoguePalette.skin()      // 肌
    def paintC(): Color = RoguePalette.cyan()      // 戦化粧・斬撃軌跡
    def glowC(): Color  = RoguePalette.paleBlue()  // 軌跡のきらめき・薬瓶
    def furC(): Color   = RoguePalette.darkBrown() // 毛皮ベスト・ブーツ
    def furH(): Color   = RoguePalette.brown()     // 毛皮の毛先・斧の柄・ズボン
    def steelC(): Color = RoguePalette.silver()    // 斧の鋼
    def shineC(): Color = RoguePalette.white()     // 刃のハイライト・被弾フラッシュ
    def inkC(): Color   = RoguePalette.black()     // 目
    def dustC(): Color  = RoguePalette.gray()      // 土煙

    // ── ポーズのパラメタ（引数が多いのでレコードで名前渡し）──

    // 正面/背面共通: dy=上体の沈み込み, sway=三つ編みの横揺れ,
    // armR/armL=腕の振り(下+/上-), leg=脚モード, headDx=頭の横ずれ
    pub type alias FPose = { dy = Int32, sway = Int32, armR = Int32, armL = Int32,
                             leg = Int32, headDx = Int32, axeR = Bool, axeL = Bool }

    def fBase(): FPose = { dy = 0, sway = 0, armR = 0, armL = 0,
                           leg = 0, headDx = 0, axeR = true, axeL = true }

    // 横向き(左): lag=三つ編みの遅れ(後方+), stride=脚の歩容, swing=前腕の振り(後方+)
    pub type alias SPose = { dy = Int32, lag = Int32, stride = Int32,
                             swing = Int32, headDx = Int32, axe = Bool }

    def sBase(): SPose = { dy = 0, lag = 0, stride = 1, swing = 0, headDx = 0, axe = true }

    pub type alias BPose = { dy = Int32, sway = Int32, armR = Int32, armL = Int32, leg = Int32 }

    // ── 正面の部品 ──

    // 頭: 金髪+顔+目+頬の水色戦化粧（2px の斜めストライプ）
    def headFront(dy: Int32, hx: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12 + hx, 9 + dy, 8, 3, hairC())
           |> PixelCanvas.dot(13 + hx, 11 + dy, hairD())
           |> PixelCanvas.dot(16 + hx, 11 + dy, hairD())
           |> PixelCanvas.rectFill(13 + hx, 12 + dy, 6, 4, fleshC())
           |> PixelCanvas.vline(12 + hx, 12 + dy, 2, hairC())
           |> PixelCanvas.vline(19 + hx, 12 + dy, 2, hairC())
           |> PixelCanvas.dot(14 + hx, 13 + dy, inkC())
           |> PixelCanvas.dot(17 + hx, 13 + dy, inkC())
           |> PixelCanvas.dot(13 + hx, 14 + dy, paintC())
           |> PixelCanvas.dot(14 + hx, 15 + dy, paintC())
           |> PixelCanvas.dot(18 + hx, 14 + dy, paintC())
           |> PixelCanvas.dot(17 + hx, 15 + dy, paintC())

    // 三つ編み(正面): 右肩の外へ垂れる。下半分が sway で遅れて揺れる
    def braidFront(dy: Int32, sway: Int32, hx: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.dot(20 + hx, 10 + dy, hairC())
           |> PixelCanvas.dot(21 + hx, 11 + dy, hairC())
           |> PixelCanvas.dot(21 + hx, 12 + dy, hairD())
           |> PixelCanvas.dot(21 + hx + sway, 13 + dy, hairC())
           |> PixelCanvas.dot(21 + hx + sway, 14 + dy, hairC())
           |> PixelCanvas.dot(21 + hx + sway, 15 + dy, hairD())
           |> PixelCanvas.dot(21 + hx + sway, 16 + dy, hairC())
           |> PixelCanvas.dot(21 + hx + sway, 17 + dy, hairD())
           |> PixelCanvas.dot(21 + hx + sway, 18 + dy, hairC())

    // 胴: 毛皮ベスト+肩の毛先+革帯
    def torsoFront(dy: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12, 16 + dy, 8, 6, furC())
           |> PixelCanvas.dot(11, 16 + dy, furH())
           |> PixelCanvas.dot(20, 16 + dy, furH())
           |> PixelCanvas.dot(13, 17 + dy, furH())
           |> PixelCanvas.dot(16, 18 + dy, furH())
           |> PixelCanvas.dot(18, 17 + dy, furH())
           |> PixelCanvas.dot(14, 20 + dy, furH())
           |> PixelCanvas.dot(17, 20 + dy, furH())
           |> PixelCanvas.hline(12, 22 + dy, 8, hairD())

    // 右腕(画面左)+手斧: 柄は縦 7px・刃は 2x2+刃先 1px・ハイライト白 1px
    def armFrontR(ady: Int32, withAxe: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let arm = cv |> PixelCanvas.rectFill(10, 17 + ady, 2, 4, fleshC());
        if (withAxe)
            arm |> PixelCanvas.vline(9, 14 + ady, 7, furH())
                |> PixelCanvas.rectFill(7, 14 + ady, 2, 2, steelC())
                |> PixelCanvas.dot(7, 16 + ady, steelC())
                |> PixelCanvas.dot(7, 14 + ady, shineC())
                |> PixelCanvas.dot(9, 20 + ady, fleshC())
        else
            arm

    // 左腕(画面右)+投げ斧(小ぶり)
    def armFrontL(ady: Int32, withAxe: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let arm = cv |> PixelCanvas.rectFill(20, 17 + ady, 2, 4, fleshC());
        if (withAxe)
            arm |> PixelCanvas.hline(22, 15 + ady, 2, steelC())
                |> PixelCanvas.dot(23, 15 + ady, shineC())
                |> PixelCanvas.vline(22, 16 + ady, 5, furH())
        else
            arm

    // 脚: 0=直立 1=左足接地/右足蹴り上げ 2=すれ違い(両足そろえ) 3=右足接地/左足蹴り上げ
    def legsFront(mode: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        match mode {
            case 1 =>
                cv |> PixelCanvas.rectFill(13, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(13, 27, 2, 3, furC())
                   |> PixelCanvas.rectFill(17, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(17, 27, 2, 2, furC())
            case 2 =>
                cv |> PixelCanvas.rectFill(13, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(13, 27, 2, 3, furC())
                   |> PixelCanvas.rectFill(17, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(17, 27, 2, 3, furC())
            case 3 =>
                cv |> PixelCanvas.rectFill(13, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(13, 27, 2, 2, furC())
                   |> PixelCanvas.rectFill(17, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(17, 27, 2, 3, furC())
            case _ =>
                cv |> PixelCanvas.rectFill(13, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(13, 27, 2, 3, furC())
                   |> PixelCanvas.rectFill(17, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(17, 27, 2, 3, furC())
        }

    // 正面の全身合成。腕→頭→三つ編みの順に重ねる（三つ編みが肩の上に乗る）
    def frontFigure(p: FPose): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> legsFront(p#leg)
            |> torsoFront(p#dy)
            |> armFrontL(p#dy + p#armL, p#axeL)
            |> armFrontR(p#dy + p#armR, p#axeR)
            |> headFront(p#dy, p#headDx)
            |> braidFront(p#dy, p#sway, p#headDx)

    // ── 背面の部品（WalkUp）──

    def headBack(dy: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12, 9 + dy, 8, 3, hairC())
           |> PixelCanvas.rectFill(13, 12 + dy, 6, 3, hairC())
           |> PixelCanvas.dot(15, 10 + dy, hairD())
           |> PixelCanvas.dot(14, 11 + dy, hairD())
           |> PixelCanvas.dot(17, 12 + dy, hairD())

    // 三つ編み(背面): 背中の真ん中を垂れて歩きで大きく揺れる主役
    def braidBack(dy: Int32, sway: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.vline(15, 13 + dy, 3, hairC())
           |> PixelCanvas.dot(15, 14 + dy, hairD())
           |> PixelCanvas.vline(15 + sway, 16 + dy, 4, hairC())
           |> PixelCanvas.dot(15 + sway, 17 + dy, hairD())
           |> PixelCanvas.dot(16 + sway, 18 + dy, hairC())
           |> PixelCanvas.dot(15 + sway, 20 + dy, hairD())
           |> PixelCanvas.dot(15 + sway, 21 + dy, hairC())

    def torsoBack(dy: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12, 16 + dy, 8, 6, furC())
           |> PixelCanvas.dot(11, 16 + dy, furH())
           |> PixelCanvas.dot(20, 16 + dy, furH())
           |> PixelCanvas.dot(12, 17 + dy, furH())
           |> PixelCanvas.dot(15, 19 + dy, furH())
           |> PixelCanvas.dot(18, 18 + dy, furH())
           |> PixelCanvas.hline(12, 22 + dy, 8, hairD())

    // 背面では左右が入れ替わる: 手斧は画面右・投げ斧は画面左
    def armBackR(ady: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(20, 17 + ady, 2, 4, fleshC())
           |> PixelCanvas.vline(22, 14 + ady, 7, furH())
           |> PixelCanvas.rectFill(23, 14 + ady, 2, 2, steelC())
           |> PixelCanvas.dot(24, 16 + ady, steelC())
           |> PixelCanvas.dot(24, 14 + ady, shineC())

    def armBackL(ady: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(10, 17 + ady, 2, 4, fleshC())
           |> PixelCanvas.hline(8, 15 + ady, 2, steelC())
           |> PixelCanvas.dot(8, 15 + ady, shineC())
           |> PixelCanvas.vline(9, 16 + ady, 5, furH())

    def backFigure(p: BPose): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> legsFront(p#leg)
            |> torsoBack(p#dy)
            |> armBackL(p#dy + p#armL)
            |> armBackR(p#dy + p#armR)
            |> headBack(p#dy)
            |> braidBack(p#dy, p#sway)

    // ── 横向き(左)の部品 ──

    def headSide(dy: Int32, hx: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12 + hx, 9 + dy, 6, 3, hairC())
           |> PixelCanvas.rectFill(16 + hx, 12 + dy, 2, 3, hairC())
           |> PixelCanvas.rectFill(11 + hx, 12 + dy, 5, 4, fleshC())
           |> PixelCanvas.dot(12 + hx, 11 + dy, hairD())
           |> PixelCanvas.dot(12 + hx, 13 + dy, inkC())
           |> PixelCanvas.dot(11 + hx, 14 + dy, paintC())
           |> PixelCanvas.dot(12 + hx, 15 + dy, paintC())

    // 三つ編み(横): 進行方向と逆へ遅れてなびく（フォロースルーは lag で）
    def braidSide(dy: Int32, lag: Int32, hx: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.dot(18 + hx, 10 + dy, hairC())
           |> PixelCanvas.dot(19 + hx, 11 + dy, hairC())
           |> PixelCanvas.dot(19 + hx, 12 + dy, hairD())
           |> PixelCanvas.dot(20 + hx + lag, 13 + dy, hairC())
           |> PixelCanvas.dot(20 + hx + lag, 14 + dy, hairC())
           |> PixelCanvas.dot(20 + hx + lag, 15 + dy, hairD())
           |> PixelCanvas.dot(21 + hx + lag, 16 + dy, hairC())
           |> PixelCanvas.dot(21 + hx + lag, 17 + dy, hairD())
           |> PixelCanvas.dot(21 + hx + lag, 18 + dy, hairC())

    // 胴(横): x=11 の胸列で前傾を出す。背中に投げ斧を背負う
    def torsoSide(dy: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.rectFill(12, 16 + dy, 6, 6, furC())
           |> PixelCanvas.vline(11, 17 + dy, 3, furC())
           |> PixelCanvas.dot(13, 17 + dy, furH())
           |> PixelCanvas.dot(16, 19 + dy, furH())
           |> PixelCanvas.dot(14, 20 + dy, furH())
           |> PixelCanvas.hline(12, 22 + dy, 6, hairD())
           |> PixelCanvas.dot(18, 16 + dy, steelC())
           |> PixelCanvas.dot(19, 16 + dy, shineC())
           |> PixelCanvas.dot(18, 17 + dy, furH())

    def armSideFront(dy: Int32, swing: Int32, withAxe: Bool, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let arm = cv |> PixelCanvas.rectFill(10 + swing, 17 + dy, 2, 4, fleshC());
        if (withAxe)
            arm |> PixelCanvas.vline(9 + swing, 14 + dy, 7, furH())
                |> PixelCanvas.rectFill(7 + swing, 14 + dy, 2, 2, steelC())
                |> PixelCanvas.dot(7 + swing, 16 + dy, steelC())
                |> PixelCanvas.dot(7 + swing, 14 + dy, shineC())
                |> PixelCanvas.dot(9 + swing, 20 + dy, fleshC())
        else
            arm

    // 脚(横): 0=接地(大股) 1=すれ違いA 2=接地(逆脚) 3=すれ違いB
    def legsSide(stride: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        match stride {
            case 0 =>
                cv |> PixelCanvas.line(13, 23, 10, 26, furH())
                   |> PixelCanvas.line(14, 23, 11, 26, furH())
                   |> PixelCanvas.rectFill(10, 27, 2, 3, furC())
                   |> PixelCanvas.line(15, 23, 18, 26, furH())
                   |> PixelCanvas.line(16, 23, 19, 26, furH())
                   |> PixelCanvas.rectFill(18, 27, 2, 3, furC())
            case 2 =>
                cv |> PixelCanvas.line(15, 23, 18, 26, furH())
                   |> PixelCanvas.line(16, 23, 19, 26, furH())
                   |> PixelCanvas.rectFill(18, 27, 2, 3, furC())
                   |> PixelCanvas.line(13, 23, 11, 25, furH())
                   |> PixelCanvas.line(14, 23, 12, 25, furH())
                   |> PixelCanvas.rectFill(11, 26, 2, 2, furC())
            case 3 =>
                cv |> PixelCanvas.rectFill(15, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(15, 27, 2, 3, furC())
                   |> PixelCanvas.rectFill(12, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(12, 27, 2, 2, furC())
            case _ =>
                cv |> PixelCanvas.rectFill(13, 23, 2, 4, furH())
                   |> PixelCanvas.rectFill(13, 27, 2, 3, furC())
                   |> PixelCanvas.rectFill(15, 24, 2, 3, furH())
                   |> PixelCanvas.rectFill(15, 27, 2, 2, furC())
        }

    def sideFigure(p: SPose): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> legsSide(p#stride)
            |> torsoSide(p#dy)
            |> headSide(p#dy, p#headDx)
            |> braidSide(p#dy, p#lag, p#headDx)
            |> armSideFront(p#dy, p#swing, p#axe)

    // ── 斬撃軌跡: 中心(15,18)・半径 9..11 の帯を四分円ごとに描く ──
    // quad: 0=左上 1=左下 2=右下 3=右上（回転斬りの通過跡）

    def keepQuad(quad: Int32, ox: Int32, oy: Int32): Bool =
        match quad {
            case 0 => ox <= 0 and oy <= 0
            case 1 => ox <= 0 and oy >= 0
            case 2 => ox >= 0 and oy >= 0
            case _ => ox >= 0 and oy <= 0
        }

    def arcBand(cx: Int32, cy: Int32, rIn: Int32, rOut: Int32, quad: Int32,
                c: Color, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        List.range(-rOut, rOut + 1) |> List.foldLeft((accY, oy) ->
            List.range(-rOut, rOut + 1) |> List.foldLeft((accX, ox) -> {
                let d2 = ox * ox + oy * oy;
                let inBand = d2 >= rIn * rIn and d2 <= rOut * rOut;
                if (inBand and keepQuad(quad, ox, oy))
                    PixelCanvas.dot(cx + ox, cy + oy, c, accX)
                else
                    accX
            }, accY), cv)

    // ── クリップ: Idle（前傾の待機・呼吸と斧の小さな上下）──

    def idle(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => frontFigure(fBase())
            case 1 => frontFigure({ dy = 1, sway = 1 | fBase() })
            case 2 => frontFigure({ armR = -1 | fBase() })
            case _ => frontFigure({ sway = -1, armL = -1 | fBase() })
        }

    // ── IdleUp: 背面の待機。背中の三つ編みが主役で、呼吸に合わせて振り子に揺れる ──

    def idleUp(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => backFigure({ dy = 0, sway = 0, armR = 0, armL = 0, leg = 0 })
            case 1 => backFigure({ dy = 1, sway = 1, armR = 0, armL = 0, leg = 0 })
            case 2 => backFigure({ dy = 1, sway = 0, armR = -1, armL = 0, leg = 0 })
            case _ => backFigure({ dy = 0, sway = -1, armR = 0, armL = -1, leg = 0 })
        }

    // ── IdleSide: 横向き(左)の待機。前傾スタンス(headDx=-1)のまま静かに呼吸する ──

    def idleSide(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => sideFigure({ headDx = -1 | sBase() })
            case 1 => sideFigure({ dy = 1, lag = 1, headDx = -1 | sBase() })
            case 2 => sideFigure({ dy = 1, swing = -1, headDx = -1 | sBase() })
            case _ => sideFigure({ lag = -1, headDx = -1 | sBase() })
        }

    // ── WalkDown: 歩幅と 1px の上下動・三つ編みが遅れて揺れる ──

    def walkDown(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => frontFigure({ sway = 1, armR = -1, armL = 1, leg = 1 | fBase() })
            case 1 => frontFigure({ dy = 1, leg = 2 | fBase() })
            case 2 => frontFigure({ sway = -1, armR = 1, armL = -1, leg = 3 | fBase() })
            case _ => frontFigure({ dy = 1, armR = 1, armL = 1, leg = 2 | fBase() })
        }

    // ── WalkUp: 背中の三つ編みが主役。大きな横揺れで速歩感を出す ──

    def walkUp(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => backFigure({ dy = 0, sway = 2, armR = -1, armL = 1, leg = 1 })
            case 1 => backFigure({ dy = 1, sway = 1, armR = 0, armL = 0, leg = 2 })
            case 2 => backFigure({ dy = 0, sway = -2, armR = 1, armL = -1, leg = 3 })
            case _ => backFigure({ dy = 1, sway = -1, armR = 1, armL = 1, leg = 2 })
        }

    // ── WalkSide: 前傾の速歩（headDx=-1）。接地で低く・すれ違いで高く ──

    def walkSide(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 => sideFigure({ lag = 1, stride = 0, swing = -1, headDx = -1 | sBase() })
            case 1 => sideFigure({ dy = -1, stride = 1, headDx = -1 | sBase() })
            case 2 => sideFigure({ lag = -1, stride = 2, swing = 1, headDx = -1 | sBase() })
            case _ => sideFigure({ dy = -1, stride = 3, headDx = -1 | sBase() })
        }

    // ── AttackSide: 6コマで一回転する回転斬り（横向きの見せ場）──
    // 溜め→左→下→右→頭上と斧が一周し、通過した四分円にシアンの軌跡帯が残る。
    // 三つ編みは遠心力で常に斧と反対側へ水平に流れる。

    def attack(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 溜め: 低く沈み、手斧を胸の前へ引きつける
                sideFigure({ dy = 1, lag = -2, stride = 1, swing = 5 | sBase() })
                    |> PixelCanvas.dot(11, 14, paintC())
                    |> PixelCanvas.dot(12, 17, paintC())
            case 1 =>
                // 振り出し: 正面で右腕を真横(左)へ・軌跡は左上の弧
                (PixelCanvas.empty()
                    |> legsFront(2)
                    |> torsoFront(0)
                    |> PixelCanvas.rectFill(20, 17, 2, 3, fleshC())
                    |> PixelCanvas.rectFill(6, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(5, 15, 6, furH())
                    |> PixelCanvas.rectFill(3, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(3, 17, steelC())
                    |> PixelCanvas.dot(3, 15, shineC())
                    |> headFront(0, -1)
                    |> PixelCanvas.hline(20, 10, 5, hairC())
                    |> PixelCanvas.dot(21, 10, hairD())
                    |> PixelCanvas.dot(23, 10, hairD())
                    |> PixelCanvas.dot(25, 11, hairC()))
                    |> arcBand(15, 18, 9, 11, 0, paintC())
                    |> PixelCanvas.dot(4, 18, shineC())
                    |> PixelCanvas.dot(6, 13, shineC())
                    |> PixelCanvas.dot(9, 10, glowC())
                    |> PixelCanvas.dot(12, 8, glowC())
            case 2 =>
                // 背中を見せて半回転: 斧は足元を薙ぐ・軌跡は左下の弧
                (PixelCanvas.empty()
                    |> legsFront(2)
                    |> torsoBack(0)
                    |> PixelCanvas.rectFill(20, 18, 2, 3, fleshC())
                    |> PixelCanvas.rectFill(9, 20, 3, 2, fleshC())
                    |> PixelCanvas.dot(13, 22, furH())
                    |> PixelCanvas.dot(12, 23, furH())
                    |> PixelCanvas.dot(11, 24, furH())
                    |> PixelCanvas.rectFill(9, 25, 2, 2, steelC())
                    |> PixelCanvas.dot(9, 25, shineC())
                    |> headBack(0)
                    |> PixelCanvas.hline(7, 10, 5, hairC())
                    |> PixelCanvas.dot(8, 10, hairD())
                    |> PixelCanvas.dot(10, 10, hairD())
                    |> PixelCanvas.dot(6, 11, hairC()))
                    |> arcBand(15, 18, 9, 11, 1, paintC())
                    |> PixelCanvas.dot(12, 28, shineC())
                    |> PixelCanvas.dot(8, 26, shineC())
                    |> PixelCanvas.dot(6, 22, glowC())
            case 3 =>
                // 右向きの側面(反転作画): 斧は右へ一閃・軌跡は右下の弧
                (PixelCanvas.empty()
                    |> legsSide(1)
                    |> torsoSide(0)
                    |> headSide(0, 0)
                    |> braidSide(0, 2, 0)
                    |> PixelCanvas.hflip
                    |> PixelCanvas.rectFill(20, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(26, 15, 6, furH())
                    |> PixelCanvas.rectFill(27, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(28, 17, steelC())
                    |> PixelCanvas.dot(28, 15, shineC()))
                    |> arcBand(15, 18, 9, 11, 2, paintC())
                    |> PixelCanvas.dot(25, 24, shineC())
                    |> PixelCanvas.dot(22, 27, shineC())
                    |> PixelCanvas.dot(18, 28, glowC())
            case 4 =>
                // 振り上げ: 斧が頭上を通過・軌跡は右上の弧
                (PixelCanvas.empty()
                    |> legsSide(1)
                    |> torsoSide(0)
                    |> headSide(0, 0)
                    |> braidSide(0, 3, 0)
                    |> PixelCanvas.rectFill(15, 11, 2, 6, fleshC())
                    |> PixelCanvas.vline(15, 6, 5, furH())
                    |> PixelCanvas.rectFill(13, 4, 2, 2, steelC())
                    |> PixelCanvas.dot(13, 6, steelC())
                    |> PixelCanvas.dot(13, 4, shineC()))
                    |> arcBand(15, 18, 9, 11, 3, paintC())
                    |> PixelCanvas.dot(22, 10, shineC())
                    |> PixelCanvas.dot(25, 14, shineC())
                    |> PixelCanvas.dot(24, 7, glowC())
            case _ =>
                // 残心: 低く構え直す。余韻の火花と足元の土煙
                frontFigure({ dy = 1, sway = 1, leg = 2 | fBase() })
                    |> PixelCanvas.dot(5, 13, glowC())
                    |> PixelCanvas.dot(25, 9, glowC())
                    |> PixelCanvas.dot(24, 21, glowC())
                    |> PixelCanvas.dot(9, 29, dustC())
                    |> PixelCanvas.dot(22, 29, dustC())
        }

    // ── AttackDown: 回転斬りの正面版 ──
    // 手斧が 左→手前(足元の前)→右→頭上 と一周し、軌跡の弧は体より手前
    // （描画順で体の後 = 画面の上層）に大きく描く。arc 2 本(半径10/11)で帯にする。
    // 三つ編みは遠心力で常に斧の反対側へ鞭る。

    def attackDown(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 溜め: 低く沈んで両斧を引きつける・刃に戦化粧色の火花
                frontFigure({ dy = 1, sway = -1, armR = 1, armL = 1, leg = 2 | fBase() })
                    |> PixelCanvas.dot(6, 17, paintC())
                    |> PixelCanvas.dot(24, 17, paintC())
            case 1 =>
                // 振り出し: 手斧を真横(左)へ一閃・軌跡は頭上から左へ立ち上がる
                PixelCanvas.empty()
                    |> legsFront(2)
                    |> torsoFront(0)
                    |> armFrontL(0, true)
                    |> PixelCanvas.rectFill(6, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(5, 15, 6, furH())
                    |> PixelCanvas.rectFill(3, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(3, 17, steelC())
                    |> PixelCanvas.dot(3, 15, shineC())
                    |> headFront(0, -1)
                    |> PixelCanvas.hline(19, 10, 5, hairC())
                    |> PixelCanvas.dot(20, 10, hairD())
                    |> PixelCanvas.dot(22, 10, hairD())
                    |> PixelCanvas.dot(24, 11, hairC())
                    |> PixelCanvas.arc(15, 18, 10, 95, 185, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 110, 175, paintC())
                    |> PixelCanvas.dot(6, 10, glowC())
                    |> PixelCanvas.dot(11, 6, glowC())
            case 2 =>
                // 見せ場: 斧が足元の手前を薙ぎ、弧は体の手前(下)で最大になる
                PixelCanvas.empty()
                    |> legsFront(2)
                    |> torsoFront(0)
                    |> armFrontL(-1, true)
                    |> headFront(0, 0)
                    |> PixelCanvas.dot(20, 9, hairC())
                    |> PixelCanvas.dot(21, 8, hairC())
                    |> PixelCanvas.dot(22, 7, hairD())
                    |> PixelCanvas.dot(23, 7, hairC())
                    |> PixelCanvas.line(11, 18, 14, 23, fleshC())
                    |> PixelCanvas.line(12, 18, 15, 23, fleshC())
                    |> PixelCanvas.vline(15, 24, 3, furH())
                    |> PixelCanvas.rectFill(14, 27, 2, 2, steelC())
                    |> PixelCanvas.dot(14, 27, shineC())
                    |> PixelCanvas.arc(15, 18, 10, 180, 275, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 185, 270, paintC())
                    |> PixelCanvas.dot(4, 21, glowC())
                    |> PixelCanvas.dot(7, 26, shineC())
            case 3 =>
                // 右へ抜ける: 弧は手前から右へ・投げ斧の腕は引き上げて逃がす
                PixelCanvas.empty()
                    |> legsFront(2)
                    |> torsoFront(0)
                    |> PixelCanvas.rectFill(10, 15, 2, 3, fleshC())
                    |> PixelCanvas.vline(9, 12, 4, furH())
                    |> PixelCanvas.hline(8, 11, 2, steelC())
                    |> PixelCanvas.dot(8, 11, shineC())
                    |> PixelCanvas.rectFill(20, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(26, 15, 6, furH())
                    |> PixelCanvas.rectFill(27, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(27, 17, steelC())
                    |> PixelCanvas.dot(28, 15, shineC())
                    |> headFront(0, 1)
                    |> PixelCanvas.hline(8, 10, 5, hairC())
                    |> PixelCanvas.dot(9, 10, hairD())
                    |> PixelCanvas.dot(11, 10, hairD())
                    |> PixelCanvas.dot(7, 11, hairC())
                    |> PixelCanvas.arc(15, 18, 10, 265, 355, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 270, 350, paintC())
                    |> PixelCanvas.dot(25, 26, shineC())
                    |> PixelCanvas.dot(27, 21, glowC())
            case 4 =>
                // 振り抜き: 一周して斧は左上へ・軌跡は頭上で薄れる
                PixelCanvas.empty()
                    |> legsFront(1)
                    |> torsoFront(0)
                    |> armFrontL(0, true)
                    |> PixelCanvas.rectFill(10, 12, 2, 4, fleshC())
                    |> PixelCanvas.vline(9, 8, 5, furH())
                    |> PixelCanvas.rectFill(7, 6, 2, 2, steelC())
                    |> PixelCanvas.dot(7, 8, steelC())
                    |> PixelCanvas.dot(7, 6, shineC())
                    |> headFront(0, 0)
                    |> braidFront(0, 2, 0)
                    |> PixelCanvas.arc(15, 18, 10, 60, 150, glowC())
                    |> PixelCanvas.dot(4, 12, paintC())
                    |> PixelCanvas.dot(24, 7, glowC())
            case _ =>
                // 残心: 沈んで構え直し・足元に土煙
                frontFigure({ dy = 1, sway = 1, leg = 2 | fBase() })
                    |> PixelCanvas.dot(5, 14, glowC())
                    |> PixelCanvas.dot(26, 10, glowC())
                    |> PixelCanvas.dot(9, 29, dustC())
                    |> PixelCanvas.dot(22, 29, dustC())
        }

    // ── AttackUp: 回転斬りの背面版 ──
    // 振りは体の向こう側(彼女の前面)を通るので、軌跡の弧は先に描いてから
    // 体を重ねる = 胴に隠れて頭の上と肩の外だけ弧が覗く。回りは 右→頭上→左。

    def attackUp(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 溜め: 背中を丸めて沈む
                backFigure({ dy = 1, sway = -1, armR = 1, armL = 1, leg = 2 })
                    |> PixelCanvas.dot(25, 17, paintC())
                    |> PixelCanvas.dot(7, 17, paintC())
            case 1 =>
                // 振り出し: 手斧(画面右)を真横へ・軌跡は足元から右へ立ち上がる
                PixelCanvas.empty()
                    |> PixelCanvas.arc(15, 18, 10, 275, 355, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 285, 350, paintC())
                    |> legsFront(2)
                    |> torsoBack(0)
                    |> armBackL(0)
                    |> PixelCanvas.rectFill(20, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(26, 15, 6, furH())
                    |> PixelCanvas.rectFill(27, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(27, 17, steelC())
                    |> PixelCanvas.dot(28, 15, shineC())
                    |> headBack(0)
                    |> PixelCanvas.hline(8, 12, 4, hairC())
                    |> PixelCanvas.dot(10, 12, hairD())
                    |> PixelCanvas.dot(7, 13, hairC())
                    |> PixelCanvas.dot(28, 22, glowC())
            case 2 =>
                // 頭上通過: 向こう側の大弧が頭の上に覗く・三つ編みは真横へ流れる
                PixelCanvas.empty()
                    |> PixelCanvas.arc(15, 18, 10, 10, 160, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 20, 150, paintC())
                    |> legsFront(2)
                    |> torsoBack(0)
                    |> armBackL(0)
                    |> PixelCanvas.rectFill(11, 12, 2, 4, fleshC())
                    |> PixelCanvas.vline(10, 8, 5, furH())
                    |> PixelCanvas.rectFill(8, 6, 2, 2, steelC())
                    |> PixelCanvas.dot(8, 8, steelC())
                    |> PixelCanvas.dot(8, 6, shineC())
                    |> headBack(0)
                    |> braidBack(0, 3)
                    |> PixelCanvas.dot(21, 4, glowC())
                    |> PixelCanvas.dot(25, 9, glowC())
            case 3 =>
                // 左へ抜ける: 投げ斧の腕は胸元へ引きつけ・三つ編みは右へ鞭る
                PixelCanvas.empty()
                    |> PixelCanvas.arc(15, 18, 10, 100, 190, paintC())
                    |> PixelCanvas.arc(15, 18, 11, 105, 180, paintC())
                    |> legsFront(2)
                    |> torsoBack(0)
                    |> PixelCanvas.rectFill(20, 17, 2, 3, fleshC())
                    |> PixelCanvas.hline(23, 15, 2, steelC())
                    |> PixelCanvas.dot(24, 15, shineC())
                    |> PixelCanvas.vline(23, 16, 4, furH())
                    |> PixelCanvas.rectFill(6, 18, 6, 2, fleshC())
                    |> PixelCanvas.vline(5, 15, 6, furH())
                    |> PixelCanvas.rectFill(3, 15, 2, 2, steelC())
                    |> PixelCanvas.dot(3, 17, steelC())
                    |> PixelCanvas.dot(3, 15, shineC())
                    |> headBack(0)
                    |> PixelCanvas.hline(20, 12, 4, hairC())
                    |> PixelCanvas.dot(22, 12, hairD())
                    |> PixelCanvas.dot(24, 13, hairC())
                    |> PixelCanvas.dot(3, 22, glowC())
            case 4 =>
                // 振り抜き: 左下へ薄れる残光・三つ編みが戻ってくる
                backFigure({ dy = 0, sway = 2, armR = -1, armL = 0, leg = 1 })
                    |> PixelCanvas.arc(15, 18, 10, 150, 230, glowC())
                    |> PixelCanvas.dot(4, 10, paintC())
                    |> PixelCanvas.dot(6, 24, glowC())
            case _ =>
                // 残心: 背面で沈み直す・足元に土煙
                backFigure({ dy = 1, sway = 1, armR = 1, armL = 1, leg = 2 })
                    |> PixelCanvas.dot(9, 29, dustC())
                    |> PixelCanvas.dot(22, 29, dustC())
                    |> PixelCanvas.dot(25, 12, glowC())
        }

    // ── UseItem: 薬瓶を掲げ→白いフラッシュ→ぐいっと飲む→化粧が輝く ──

    // 左腕は上げるので投げ斧は腰の革帯に差しておく（斧2本は常に見える）。
    // 三つ編みは腕を避けて外側(x22)へ
    def useBase(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> legsFront(0)
            |> torsoFront(0)
            |> PixelCanvas.hline(20, 21, 2, steelC())
            |> PixelCanvas.dot(20, 21, shineC())
            |> PixelCanvas.dot(22, 22, furH())
            |> armFrontR(0, true)
            |> headFront(0, 0)
            |> braidFront(0, 1, 0)

    def useItem(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                useBase()
                    |> PixelCanvas.rectFill(20, 12, 2, 5, fleshC())
                    |> PixelCanvas.rectFill(20, 10, 2, 2, glowC())
                    |> PixelCanvas.dot(21, 10, shineC())
            case 1 =>
                // フラッシュ: 瓶が白熱し、光の筋が放射する
                useBase()
                    |> PixelCanvas.rectFill(20, 12, 2, 5, fleshC())
                    |> PixelCanvas.rectFill(20, 10, 2, 2, shineC())
                    |> PixelCanvas.dot(18, 8, shineC())
                    |> PixelCanvas.dot(23, 8, shineC())
                    |> PixelCanvas.dot(17, 11, shineC())
                    |> PixelCanvas.dot(24, 11, shineC())
                    |> PixelCanvas.dot(20, 6, shineC())
                    |> PixelCanvas.dot(23, 13, shineC())
                    |> PixelCanvas.dot(19, 9, glowC())
                    |> PixelCanvas.dot(22, 9, glowC())
                    |> PixelCanvas.dot(18, 12, glowC())
                    |> PixelCanvas.dot(23, 12, glowC())
            case 2 =>
                // 口元へ運んで飲む
                useBase()
                    |> PixelCanvas.dot(21, 16, fleshC())
                    |> PixelCanvas.dot(21, 15, fleshC())
                    |> PixelCanvas.dot(20, 14, fleshC())
                    |> PixelCanvas.dot(19, 14, fleshC())
                    |> PixelCanvas.rectFill(17, 12, 2, 2, glowC())
                    |> PixelCanvas.dot(18, 12, shineC())
            case _ =>
                // 効果が満ちて戦化粧が淡く輝く
                frontFigure(fBase())
                    |> PixelCanvas.dot(12, 14, glowC())
                    |> PixelCanvas.dot(19, 14, glowC())
                    |> PixelCanvas.dot(13, 6, glowC())
                    |> PixelCanvas.dot(18, 5, glowC())
        }

    // ── UseItemUp: 背面で呷る ──
    // 投げ斧は背中に背負い直し（斧2本は常に見える）、画面左の手で薬瓶を掲げる。

    def useBackBase(): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> legsFront(0)
            |> torsoBack(0)
            |> PixelCanvas.hline(13, 17, 2, steelC())
            |> PixelCanvas.dot(13, 17, shineC())
            |> PixelCanvas.vline(14, 18, 3, furH())
            |> armBackR(0)
            |> headBack(0)
            |> braidBack(0, 1)

    def useItemUp(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 掲げる: 肩の上に薬瓶が覗く
                useBackBase()
                    |> PixelCanvas.rectFill(10, 13, 2, 4, fleshC())
                    |> PixelCanvas.rectFill(9, 11, 2, 2, glowC())
                    |> PixelCanvas.dot(10, 11, shineC())
            case 1 =>
                // フラッシュ: 瓶が白熱し、光の筋が頭の向こうへ放射する
                useBackBase()
                    |> PixelCanvas.rectFill(10, 13, 2, 4, fleshC())
                    |> PixelCanvas.rectFill(9, 11, 2, 2, shineC())
                    |> PixelCanvas.dot(7, 9, shineC())
                    |> PixelCanvas.dot(12, 9, shineC())
                    |> PixelCanvas.dot(6, 12, shineC())
                    |> PixelCanvas.dot(13, 12, shineC())
                    |> PixelCanvas.dot(9, 7, shineC())
                    |> PixelCanvas.dot(8, 10, glowC())
                    |> PixelCanvas.dot(11, 10, glowC())
                    |> PixelCanvas.dot(7, 13, glowC())
                    |> PixelCanvas.dot(12, 13, glowC())
            case 2 =>
                // 呷る: 瓶が頭の縁へ傾く（顔は見えないが仕草で伝える）
                useBackBase()
                    |> PixelCanvas.dot(10, 14, fleshC())
                    |> PixelCanvas.dot(11, 13, fleshC())
                    |> PixelCanvas.rectFill(11, 11, 2, 2, glowC())
                    |> PixelCanvas.dot(12, 11, shineC())
            case _ =>
                // 余韻: 頭の縁から戦化粧の輝きが漏れる
                backFigure({ dy = 0, sway = 1, armR = 0, armL = 0, leg = 0 })
                    |> PixelCanvas.dot(11, 10, glowC())
                    |> PixelCanvas.dot(20, 10, glowC())
                    |> PixelCanvas.dot(12, 8, glowC())
                    |> PixelCanvas.dot(19, 7, glowC())
        }

    // ── Damage: 白シルエット+ノックバック→のけぞり→よろけ ──

    def whiteout(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        Map.map(_ -> shineC(), cv)

    def damage(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 全身が真っ白に発光し 2px 後方(右)へ飛ぶ
                sideFigure(sBase()) |> whiteout |> PixelCanvas.shift(2, 0)
            case 1 =>
                // のけぞり: 頭が後ろへ倒れ三つ編みが前へ鞭のように回る
                sideFigure({ lag = -2, swing = -2, headDx = 2 | sBase() })
                    |> PixelCanvas.shift(2, 0)
                    |> PixelCanvas.dot(10, 11, shineC())
                    |> PixelCanvas.dot(8, 13, shineC())
            case _ =>
                // 片膝を折って踏みとどまる
                sideFigure({ dy = 1, lag = -1, swing = 1, headDx = 1 | sBase() })
                    |> PixelCanvas.shift(1, 0)
        }

    // ── DamageDown: 正面。白フラッシュ→三つ編みが顔の前へ鞭る→踏み耐え ──

    def damageDown(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 全身が真っ白に発光し、左へ 2px よろめく
                frontFigure({ leg = 2 | fBase() })
                    |> whiteout
                    |> PixelCanvas.shift(-2, 0)
            case 1 =>
                // のけぞり: 頭は右へ飛び、三つ編み(sway=-3)が顔の前へ鞭のように回る
                frontFigure({ dy = 1, sway = -3, armR = -1, armL = 1, leg = 1, headDx = 1 | fBase() })
                    |> PixelCanvas.shift(-1, 0)
                    |> PixelCanvas.dot(24, 13, shineC())
                    |> PixelCanvas.dot(26, 16, shineC())
            case _ =>
                // 足を開いて踏み耐える
                frontFigure({ dy = 1, sway = -1, leg = 3 | fBase() })
                    |> PixelCanvas.dot(20, 29, dustC())
        }

    // ── DamageUp: 背面。三つ編みが頭越しに前(奥)へ跳ね上がる ──

    def damageUp(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 白シルエットで右へ 2px 飛ぶ
                backFigure({ dy = 0, sway = 0, armR = 0, armL = 0, leg = 2 })
                    |> whiteout
                    |> PixelCanvas.shift(2, 0)
            case 1 =>
                // のけぞり: 三つ編みの先が肩越しに跳ね上がる
                backFigure({ dy = 1, sway = 3, armR = -1, armL = 1, leg = 1 })
                    |> PixelCanvas.shift(1, 0)
                    |> PixelCanvas.dot(21, 8, hairC())
                    |> PixelCanvas.dot(22, 7, hairD())
                    |> PixelCanvas.dot(23, 8, hairC())
                    |> PixelCanvas.dot(8, 14, shineC())
                    |> PixelCanvas.dot(6, 17, shineC())
            case _ =>
                // 踏み耐える
                backFigure({ dy = 1, sway = 1, armR = 1, armL = 0, leg = 3 })
                    |> PixelCanvas.dot(11, 29, dustC())
        }

    // ── Death: 6コマ・正面・膝どまり ──
    // 踏鞴(2) → 膝から崩れ(2) → 膝立ちのまま前傾がくり(2)。
    // 手斧は f1 で手から滑り落ち、以後ずっと足元に転がる。投げ斧は左手に
    // 握ったまま切っ先が下がっていく（斧2本は常に見える）。
    // 倒れ伏した遺体は描かない — 最終コマも膝立ちの立面シルエットで止まる。

    // 落とした手斧: 刃を下に地面へ転がる（f1 以降ずっと同じ場所）
    def droppedHandAxe(cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        cv |> PixelCanvas.hline(3, 27, 2, steelC())
           |> PixelCanvas.dot(3, 27, shineC())
           |> PixelCanvas.dot(5, 26, furH())
           |> PixelCanvas.dot(6, 25, furH())

    // 膝立ちの姿勢: 上体を dy2 だけ落とし、脚は折り畳んだブーツだけ見せる。
    // 投げ斧は垂れた左手に握られ、刃が dy2 と一緒に沈む
    def kneeling(dy2: Int32, sway: Int32, hx: Int32): PixelCanvas.Canvas =
        PixelCanvas.empty()
            |> PixelCanvas.rectFill(12, 27, 2, 3, furC())
            |> PixelCanvas.rectFill(18, 27, 2, 3, furC())
            |> torsoFront(dy2)
            |> PixelCanvas.rectFill(10, 18 + dy2, 2, 4, fleshC())
            |> PixelCanvas.rectFill(20, 18 + dy2, 2, 4, fleshC())
            |> PixelCanvas.vline(22, 18 + dy2, 4, furH())
            |> PixelCanvas.hline(22, 22 + dy2, 2, steelC())
            |> PixelCanvas.dot(23, 22 + dy2, shineC())
            |> headFront(dy2, hx)
            |> braidFront(dy2, sway, hx)

    // 前傾がくり: 頭が胸へ落ち、三つ編みが顔の横へ落ちてくる。
    // drop=三つ編みの段階（0=まだ宙に浮く / 1=ぱさりと落ち切る）
    def slump(drop: Int32): PixelCanvas.Canvas =
        let base = PixelCanvas.empty()
            |> PixelCanvas.rectFill(12, 27, 2, 3, furC())
            |> PixelCanvas.rectFill(18, 27, 2, 3, furC())
            |> torsoFront(6)
            |> PixelCanvas.rectFill(10, 24, 2, 4, fleshC())
            |> PixelCanvas.rectFill(20, 24, 2, 4, fleshC())
            |> PixelCanvas.vline(22, 24, 3, furH())
            |> PixelCanvas.hline(22, 27, 2, steelC())
            |> PixelCanvas.dot(23, 27, shineC())
            |> headFront(7 + drop, 0);
        if (drop == 0)
            base
                |> PixelCanvas.dot(20, 14, hairC())
                |> PixelCanvas.dot(21, 15, hairC())
                |> PixelCanvas.dot(21, 16, hairD())
                |> PixelCanvas.dot(20, 17, hairC())
                |> PixelCanvas.dot(20, 18, hairC())
        else
            base
                |> PixelCanvas.dot(20, 17, hairC())
                |> PixelCanvas.dot(20, 18, hairD())
                |> PixelCanvas.dot(19, 19, hairC())
                |> PixelCanvas.dot(19, 20, hairC())
                |> PixelCanvas.dot(19, 21, hairD())
                |> PixelCanvas.dot(19, 22, hairC())

    def death(f: Int32): PixelCanvas.Canvas =
        match f {
            case 0 =>
                // 踏鞴: 左へよろめき、ほつれ毛が浮く
                frontFigure({ sway = -2, armR = -1, armL = -1, headDx = -1 | fBase() })
                    |> PixelCanvas.dot(10, 7, hairC())
                    |> PixelCanvas.dot(22, 7, hairC())
            case 1 =>
                // 逆へ踏鞴・手斧が手から滑り落ちる
                frontFigure({ dy = 1, sway = 2, armR = 1, leg = 1, headDx = 1,
                              axeR = false | fBase() })
                    |> droppedHandAxe
                    |> PixelCanvas.dot(6, 28, dustC())
            case 2 =>
                // 膝から崩れる: ブーツだけ残して上体が落ちる
                kneeling(4, 1, 0)
                    |> droppedHandAxe
                    |> PixelCanvas.dot(10, 29, dustC())
                    |> PixelCanvas.dot(21, 29, dustC())
            case 3 =>
                // さらに沈み、頭が傾き始める
                kneeling(5, -1, -1)
                    |> droppedHandAxe
                    |> PixelCanvas.dot(10, 29, dustC())
            case 4 =>
                // 前傾がくり: 頭が胸へ落ち、三つ編みが宙で顔の横へ回り込む
                slump(0)
                    |> droppedHandAxe
                    |> PixelCanvas.dot(21, 28, dustC())
            case _ =>
                // 静止: 三つ編みが顔の横へぱさりと落ち切り、膝立ちのまま止まる
                slump(1)
                    |> droppedHandAxe
        }

    // ── 入口: frame をコマ数に丸めてクリップへ振り分ける ──

    def wrapFrame(f: Int32, n: Int32): Int32 =
        let m = Int32.remainder(f, n);
        if (m < 0) m + n else m

    // v3 契約: 全方向とも本作画。横向き系は左向きで描き、右向きは実行時 hflip。
    // UseItemSide は正面の呷り芝居を流用する（瓶と化粧の見せ場が横では潰れるため）。
    pub def draw(clip: RogueStage.Clip, frame: Int32): PixelCanvas.Canvas =
        let f = wrapFrame(frame, RogueStage.frameCount(clip));
        match clip {
            case RogueStage.Clip.IdleDown    => idle(f)
            case RogueStage.Clip.IdleUp      => idleUp(f)
            case RogueStage.Clip.IdleSide    => idleSide(f)
            case RogueStage.Clip.WalkDown    => walkDown(f)
            case RogueStage.Clip.WalkUp      => walkUp(f)
            case RogueStage.Clip.WalkSide    => walkSide(f)
            case RogueStage.Clip.AttackDown  => attackDown(f)
            case RogueStage.Clip.AttackUp    => attackUp(f)
            case RogueStage.Clip.AttackSide  => attack(f)
            case RogueStage.Clip.UseItemDown => useItem(f)
            case RogueStage.Clip.UseItemUp   => useItemUp(f)
            case RogueStage.Clip.UseItemSide => useItem(f)
            case RogueStage.Clip.DamageDown  => damageDown(f)
            case RogueStage.Clip.DamageUp    => damageUp(f)
            case RogueStage.Clip.DamageSide  => damage(f)
            case RogueStage.Clip.Death       => death(f)
        }
}
