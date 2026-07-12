// RogueB — サーカス出身の軽業師。投げナイフと短剣で戦う、にやりと笑う道化。
//
// 個性は頭部で出す: ピンクの逆立った短髪・片目を覆う黒いアイマスク・にやり顔。
// 衣装は紫×黄の派手な軽業着。武器は右手の短剣（常時見える）と腰の投げナイフ。
// 攻撃は「小さく踏み込んでからの投げナイフ + 短剣の一閃」。ナイフは明色の直線で飛ぶ。

mod RogueB {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, arc, shift, overlay}

    pub def name(): String = "ROGUE B くるくる回る投げナイフ使い"

    // ── 色（RoguePalette から 6 色）──
    def hair(): Color = RoguePalette.pink()        // 逆立ったピンク髪
    def mask(): Color = RoguePalette.black()       // 片目のアイマスク帯
    def skin(): Color = RoguePalette.skin()        // 肌
    def suit(): Color = RoguePalette.purple()      // 軽業着の主色（紫）
    def suitDark(): Color = RoguePalette.plum()    // 衣装の影（暗い紫）
    def trim(): Color = RoguePalette.yellow()      // 差し色（黄）
    def blade(): Color = RoguePalette.silver()     // 短剣・投げナイフの刃
    def flash(): Color = RoguePalette.white()      // 白フラッシュ・刃のハイライト

    // ── 出口: draw で全 16 クリップを分岐 ──
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

    /// frame を 0..n-1 に丸める（負数も正しく循環）。
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    // ════════════════════════════════════════════════════════════
    //  頭部パーツ（個性の核）
    // ════════════════════════════════════════════════════════════

    /// 正面顔（Down 用）。中心 x=15..16。topY = 髪の一番上の行。
    /// 逆立ったピンク髪 + 片目のアイマスク帯 + にやり顔。
    def headDown(topY: Int32): Canvas =
        // 逆立った髪の毛先（3 本のトゲ）
        empty()
            |> dot(13, topY, hair())
            |> dot(15, topY - 1, hair())          // 中央の 1 本を高く
            |> dot(18, topY, hair())
            |> hline(13, topY + 1, 7, hair())     // 髪の塊
            |> hline(12, topY + 2, 9, hair())
            |> hline(12, topY + 3, 9, hair())
            // 顔（肌）— y は髪の下
            |> hline(13, topY + 4, 6, skin())
            |> hline(12, topY + 5, 8, skin())
            |> hline(12, topY + 6, 8, skin())
            // 片目のアイマスク（黒帯・左目 x=12..14 を覆う）
            |> hline(12, topY + 5, 3, mask())
            |> dot(12, topY + 4, mask())          // マスクの吊り上がり
            // 見えている右目（にやり）
            |> dot(17, topY + 5, mask())
            // にやり口（左上がりの笑み）
            |> dot(14, topY + 7, mask())
            |> dot(15, topY + 7, mask())
            |> dot(16, topY + 6, mask())
            // 頬の肌を口の下まで
            |> hline(13, topY + 7, 1, skin())
            |> dot(18, topY + 7, skin())

    /// 背面頭部（Up 用）。後頭部のピンク髪 + アイマスクの黒帯が後ろから見える。
    def headUp(topY: Int32): Canvas =
        empty()
            |> dot(13, topY, hair())
            |> dot(15, topY - 1, hair())
            |> dot(18, topY, hair())
            |> hline(13, topY + 1, 7, hair())
            |> hline(12, topY + 2, 9, hair())
            |> hline(12, topY + 3, 9, hair())
            |> hline(12, topY + 4, 9, hair())     // 後頭部は髪で厚め
            |> hline(13, topY + 5, 7, hair())
            // アイマスクの黒い留め帯が後ろに回っている
            |> hline(12, topY + 5, 9, mask())
            |> hline(13, topY + 6, 7, hair())     // 襟足

    /// 左向き横顔（Side 用・左向き作画）。マスクは手前（左）の目に。
    def headSide(topY: Int32): Canvas =
        empty()
            // 逆立った髪（後ろ = 右に流れる）
            |> dot(19, topY, hair())
            |> dot(16, topY - 1, hair())
            |> dot(13, topY, hair())
            |> hline(13, topY + 1, 8, hair())
            |> hline(12, topY + 2, 9, hair())
            |> hline(13, topY + 3, 8, hair())     // 前髪は左が短い
            // 顔（左向き = 左に鼻先）
            |> hline(11, topY + 4, 6, skin())
            |> hline(11, topY + 5, 6, skin())
            |> hline(12, topY + 6, 5, skin())
            |> dot(11, topY + 4, skin())          // 鼻先
            // アイマスク帯（手前の目 x=12..14 を覆い、後ろへ帯が伸びる）
            |> hline(12, topY + 4, 4, mask())
            |> dot(16, topY + 4, mask())          // 帯が後頭部へ
            // にやり口（横顔・左端）
            |> dot(11, topY + 6, mask())
            |> dot(12, topY + 6, mask())

    // ════════════════════════════════════════════════════════════
    //  胴体・脚パーツ（紫の軽業着 + 黄の差し色）
    // ════════════════════════════════════════════════════════════

    /// 正面胴体。torsoY = 胴の一番上の行（肩）。高さ 8px。
    /// 中央に黄の縦ストライプ（軽業着の飾り）。
    def torsoDown(torsoY: Int32): Canvas =
        empty()
            |> hline(12, torsoY, 8, suit())           // 肩
            |> rectFill(12, torsoY + 1, 8, 7, suit())  // 胴
            |> vline(15, torsoY + 1, 6, trim())        // 黄ストライプ
            |> vline(16, torsoY + 1, 6, trim())
            |> vline(12, torsoY + 1, 7, suitDark())    // 左脇の影
            |> vline(19, torsoY + 1, 7, suitDark())    // 右脇の影
            |> hline(12, torsoY + 7, 8, trim())        // 腰の黄ベルト

    /// 背面胴体。飾りは背中側なので黄ストライプは無く、影多め。
    def torsoUp(torsoY: Int32): Canvas =
        empty()
            |> hline(12, torsoY, 8, suit())
            |> rectFill(12, torsoY + 1, 8, 7, suit())
            |> vline(12, torsoY + 1, 7, suitDark())
            |> vline(19, torsoY + 1, 7, suitDark())
            |> vline(15, torsoY + 1, 6, suitDark())    // 背中の縫い目
            |> hline(12, torsoY + 7, 8, trim())        // 腰の黄ベルト

    /// 横向き胴体（左向き・幅を細く）。torsoY = 肩の行。
    def torsoSide(torsoY: Int32): Canvas =
        empty()
            |> hline(12, torsoY, 6, suit())
            |> rectFill(12, torsoY + 1, 6, 7, suit())
            |> vline(13, torsoY + 1, 6, trim())        // 前面の黄ライン
            |> vline(12, torsoY + 1, 7, suitDark())    // 背面の影
            |> hline(12, torsoY + 7, 6, trim())        // 腰の黄ベルト

    /// 正面の脚（両脚）。legY = 腰下の行。lift = 各脚の上げ量 (左, 右)。
    /// 足元が y=29 に着くよう、上げていない脚は必ず y=29 まで伸ばす。
    def legsDown(legY: Int32, liftL: Int32, liftR: Int32): Canvas =
        let footL = 29 - liftL;
        let footR = 29 - liftR;
        empty()
            |> overlay(vlineTo(13, legY, footL, suitDark()))    // 左脚（ズボン影）
            |> overlay(vlineTo(14, legY, footL, suit()))
            |> overlay(vlineTo(17, legY, footR, suit()))        // 右脚
            |> overlay(vlineTo(18, legY, footR, suitDark()))
            |> hline(13, footL, 2, trim())             // 足先（黄のブーツ先）
            |> hline(17, footR, 2, trim())

    /// 背面の脚（正面と同じ骨格・影の向きだけ反転）。
    def legsUp(legY: Int32, liftL: Int32, liftR: Int32): Canvas =
        let footL = 29 - liftL;
        let footR = 29 - liftR;
        empty()
            |> overlay(vlineTo(13, legY, footL, suit()))
            |> overlay(vlineTo(14, legY, footL, suitDark()))
            |> overlay(vlineTo(17, legY, footR, suitDark()))
            |> overlay(vlineTo(18, legY, footR, suit()))
            |> hline(13, footL, 2, trim())
            |> hline(17, footR, 2, trim())

    /// 横向きの脚（左向き・前脚と後脚）。frontFoot/backFoot = 各足の接地 y。
    /// stride = 前後の開き（前脚を左 x、後脚を右 x に置く）。
    def legsSide(legY: Int32, frontFoot: Int32, backFoot: Int32, stride: Int32): Canvas =
        empty()
            |> overlay(vlineTo(14 - stride, legY, frontFoot, suit()))      // 前脚
            |> hline(13 - stride, frontFoot, 3, trim())           // 前足先
            |> overlay(vlineTo(16 + stride, legY, backFoot, suitDark()))   // 後脚（影色）
            |> hline(15 + stride, backFoot, 3, suitDark())        // 後足先（影側）

    /// (x, y0) から (x, y1) まで縦線（y1 を含む・上下どちらでも）。
    def vlineTo(x: Int32, y0: Int32, y1: Int32, c: Color): Canvas =
        let lo = Int32.min(y0, y1);
        let hi = Int32.max(y0, y1);
        vline(x, lo, hi - lo + 1, c, empty())

    // ════════════════════════════════════════════════════════════
    //  腕・武器パーツ（短剣は常時見える主役）
    // ════════════════════════════════════════════════════════════

    /// 2px 幅の腕（肩 (sx,sy) から手 (hx,hy) へ）。肌色 + 袖の紫。
    /// 上半分を袖（紫）、手側を肌にして「腕」が読めるようにする。
    def armLimb(sx: Int32, sy: Int32, hx: Int32, hy: Int32): Canvas =
        line(sx, sy, hx, hy, suit(), empty())
            |> line(sx + 1, sy, hx + 1, hy, suitDark())    // 2px 幅
            |> dot(hx, hy, skin())                          // 手（肌）
            |> dot(hx + 1, hy, skin())

    /// 短剣（手 (hx,hy) から角度 dir に伸びる 3px 刃 + 黄の柄）。
    /// dir: 0=右, 1=右上, 2=上, 3=左上, 4=左, 5=左下, 6=下, 7=右下。
    def dagger(hx: Int32, hy: Int32, dir: Int32): Canvas =
        let (dx, dy) = dirVec(dir);
        let tipX = hx + dx * 4;
        let tipY = hy + dy * 4;
        empty()
            |> dot(hx, hy, trim())                          // 黄の柄頭
            |> line(hx + dx, hy + dy, tipX, tipY, blade())  // 刃
            |> dot(tipX, tipY, flash())                     // 切っ先ハイライト

    /// 8 方向の単位ベクトル。
    def dirVec(dir: Int32): (Int32, Int32) = match Int32.remainder(dir, 8) {
        case 0 => (1, 0)
        case 1 => (1, -1)
        case 2 => (0, -1)
        case 3 => (-1, -1)
        case 4 => (-1, 0)
        case 5 => (-1, 1)
        case 6 => (0, 1)
        case _ => (1, 1)
    }

    /// 腰の投げナイフ束（3 本・銀の小刀）。正面/横で位置を渡す。
    def knifeBelt(bx: Int32, by: Int32): Canvas =
        empty()
            |> vline(bx, by, 2, blade())
            |> vline(bx + 2, by, 2, blade())
            |> vline(bx + 4, by, 2, blade())
            |> hline(bx, by, 5, trim())                     // 黄の留め紐

    /// 飛ぶナイフ（明色の直線・散らさず 2px 幅）。tail→tip を結ぶ。
    def thrownKnife(tx: Int32, ty: Int32, ttx: Int32, tty: Int32): Canvas =
        line(tx, ty, ttx, tty, blade(), empty())
            |> line(tx, ty + 1, ttx, tty + 1, flash())      // 明色の尾を 1px 添える
            |> dot(ttx, tty, flash())                        // 切っ先

    // ════════════════════════════════════════════════════════════
    //  Idle — 落ち着きなく重心が揺れる。短剣をくるくる回す気配。
    // ════════════════════════════════════════════════════════════

    /// 呼吸の上下: f0,f2=標準, f1=1px 沈む, f3=1px 伸びる。
    def breath(frame: Int32): Int32 = match frame {
        case 1 => 1
        case 3 => -1
        case _ => 0
    }

    /// くるくる回す短剣の向き（Idle 各コマで変わる）。
    def spinDir(frame: Int32): Int32 = match frame {
        case 0 => 2      // 上
        case 1 => 1      // 右上
        case 2 => 0      // 右
        case _ => 3      // 左上
    }

    def idleDown(frame: Int32): Canvas =
        let b = breath(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        headDown(topY)
            |> overlay(torsoDown(torsoY))
            |> overlay(knifeBelt(11, torsoY + 6))                    // 腰の投げナイフ
            |> overlay(armLimb(12, torsoY + 1, 10, torsoY + 4))      // 左腕（腰に添える）
            |> overlay(armLimb(19, torsoY + 1, 21, torsoY + 3))      // 右腕（短剣を回す）
            |> overlay(dagger(21, torsoY + 3, spinDir(frame)))       // 回る短剣
            |> overlay(legsDown(19 + b, 0, 0))

    def idleUp(frame: Int32): Canvas =
        let b = breath(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        headUp(topY)
            |> overlay(torsoUp(torsoY))
            |> overlay(armLimb(12, torsoY + 1, 10, torsoY + 4))
            |> overlay(armLimb(19, torsoY + 1, 21, torsoY + 3))
            |> overlay(dagger(21, torsoY + 3, spinDir(frame)))
            |> overlay(legsUp(19 + b, 0, 0))

    def idleSide(frame: Int32): Canvas =
        let b = breath(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        headSide(topY)
            |> overlay(torsoSide(torsoY))
            |> overlay(knifeBelt(11, torsoY + 6))
            |> overlay(armLimb(13, torsoY + 1, 11, torsoY + 3))      // 前腕（短剣を回す）
            |> overlay(dagger(11, torsoY + 3, spinSideDir(frame)))
            |> overlay(legsSide(19 + b, 29, 29, 1))

    /// 横向きで短剣を回す向き（左向きなので左〜上寄り）。
    def spinSideDir(frame: Int32): Int32 = match frame {
        case 0 => 2      // 上
        case 1 => 3      // 左上
        case 2 => 4      // 左
        case _ => 3      // 左上
    }

    // ════════════════════════════════════════════════════════════
    //  Walk — つま先で弾む軽快な歩き。片足は必ず y=29 に着く。
    // ════════════════════════════════════════════════════════════

    /// 弾みの上下: 通過コマ(f1,f3)で体が 1px 浮く。
    def bounce(frame: Int32): Int32 = match frame {
        case 1 => -1
        case 3 => -1
        case _ => 0
    }

    /// 正面歩き。lift = (左脚上げ, 右脚上げ)。接地脚は必ず 0。
    def walkStep(frame: Int32): (Int32, Int32) = match frame {
        case 0 => (0, 2)    // 右足を上げて前へ（左が接地）
        case 1 => (0, 0)    // 通過（両足接地・体は浮く）
        case 2 => (2, 0)    // 左足を上げて前へ（右が接地）
        case _ => (0, 0)    // 通過
    }

    def walkDown(frame: Int32): Canvas =
        let b = bounce(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        let (lL, lR) = walkStep(frame);
        // 腕振り: 脚と逆位相で前後に振る
        let swing = armSwing(frame);
        headDown(topY)
            |> overlay(torsoDown(torsoY))
            |> overlay(knifeBelt(11, torsoY + 6))
            |> overlay(armLimb(12, torsoY + 1, 10 - swing, torsoY + 4))
            |> overlay(armLimb(19, torsoY + 1, 21 + swing, torsoY + 4))
            |> overlay(dagger(21 + swing, torsoY + 4, if (swing > 0) 7 else 5))  // 短剣は下向き気味
            |> overlay(legsDown(19 + b, lL, lR))

    def walkUp(frame: Int32): Canvas =
        let b = bounce(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        let (lL, lR) = walkStep(frame);
        let swing = armSwing(frame);
        headUp(topY)
            |> overlay(torsoUp(torsoY))
            |> overlay(armLimb(12, torsoY + 1, 10 - swing, torsoY + 4))
            |> overlay(armLimb(19, torsoY + 1, 21 + swing, torsoY + 4))
            |> overlay(dagger(21 + swing, torsoY + 4, if (swing > 0) 7 else 5))
            |> overlay(legsUp(19 + b, lL, lR))

    /// 腕振りの前後量（+ = 開く, - = 閉じる）。歩き 4 コマ。
    def armSwing(frame: Int32): Int32 = match frame {
        case 0 => 1
        case 1 => 0
        case 2 => -1
        case _ => 0
    }

    /// 横向き歩きの前後脚の接地 y と開き。左向き = 前は左。
    /// f0 と f2 は左右非対称（lint: WalkSide f0 非対称）。
    def walkSideStep(frame: Int32): (Int32, Int32, Int32) = match frame {
        case 0 => (29, 27, 3)   // 前足接地・後足を上げて開く（大きく前へ）
        case 1 => (29, 29, 1)   // 通過（両足そろい・狭い）
        case 2 => (27, 29, 3)   // 後足接地・前足を上げて開く
        case _ => (29, 29, 1)   // 通過
    }

    def walkSide(frame: Int32): Canvas =
        let b = bounce(frame);
        let topY = 3 + b;
        let torsoY = 11 + b;
        let (frontF, backF, stride) = walkSideStep(frame);
        let swing = armSwing(frame);
        headSide(topY)
            |> overlay(torsoSide(torsoY))
            |> overlay(knifeBelt(11, torsoY + 6))
            |> overlay(legsSide(19 + b, frontF, backF, stride))
            // 前腕を前後に振り、短剣を握ったまま
            |> overlay(armLimb(13, torsoY + 1, 11 - swing, torsoY + 4))
            |> overlay(dagger(11 - swing, torsoY + 4, if (swing > 0) 5 else 4))

    // ════════════════════════════════════════════════════════════
    //  Attack — 小さく踏み込む→投げナイフ→短剣の一閃→見得。
    //  6 コマ: 0構え 1踏み込み(沈む) 2振りかぶり 3ナイフ発射 4短剣一閃 5見得。
    // ════════════════════════════════════════════════════════════

    /// 踏み込みで体が沈む量（f1 で 2px しゃがむ）。
    def lunge(frame: Int32): Int32 = match frame {
        case 1 => 2
        case 2 => 1
        case _ => 0
    }

    def attackDown(frame: Int32): Canvas =
        let s = lunge(frame);
        let topY = 3 + s;
        let torsoY = 11 + s;
        // 脚: f1 でしゃがむ（膝を曲げる = 上げでなく体全体を沈める・接地維持）
        let base =
            headDown(topY)
                |> overlay(torsoDown(torsoY))
                |> overlay(legsDown(19 + s, 0, 0));
        match frame {
            case 0 =>                                        // 構え（ナイフを抜く）
                base
                    |> overlay(armLimb(19, torsoY + 1, 22, torsoY + 2))
                    |> overlay(dagger(22, torsoY + 2, 1))
                    |> overlay(knifeBelt(11, torsoY + 6))
            case 1 =>                                        // 踏み込み（腕を引く）
                base
                    |> overlay(armLimb(12, torsoY + 1, 9, torsoY - 1))   // 左手を後ろへ振り上げ
                    |> overlay(thrownKnifeSpin(9, torsoY - 1))
                    |> overlay(armLimb(19, torsoY + 1, 22, torsoY + 3))
                    |> overlay(dagger(22, torsoY + 3, 7))
            case 2 =>                                        // 振りかぶり
                base
                    |> overlay(armLimb(12, torsoY + 1, 8, torsoY - 2))
                    |> overlay(thrownKnifeSpin(8, torsoY - 2))
                    |> overlay(armLimb(19, torsoY + 1, 23, torsoY))
                    |> overlay(dagger(23, torsoY, 1))
            case 3 =>                                        // ナイフ発射（手前=下へ飛ぶ）
                base
                    |> overlay(armLimb(12, torsoY + 1, 13, torsoY + 5))   // 投げ切った左手
                    |> overlay(thrownKnife(14, torsoY + 8, 15, 30))       // 下へ直進
                    |> overlay(thrownKnife(16, torsoY + 8, 17, 30))       // 2 本目の尾
                    |> overlay(armLimb(19, torsoY + 1, 24, torsoY + 2))
                    |> overlay(dagger(24, torsoY + 2, 0))
            case 4 =>                                        // 短剣の一閃（右の大弧）
                base
                    |> overlay(armLimb(19, torsoY + 1, 24, torsoY + 5))
                    |> overlay(dagger(24, torsoY + 5, 7))
                    |> overlay(slashArc(16, torsoY + 4, 8, -60, 40))      // 明色の弧
            case _ =>                                        // 見得（決めポーズ）
                base
                    |> overlay(armLimb(19, torsoY + 1, 23, torsoY - 2))   // 短剣を高く掲げる
                    |> overlay(dagger(23, torsoY - 2, 2))
                    |> overlay(armLimb(12, torsoY + 1, 9, torsoY + 3))    // 左手は流し
        }

    def attackUp(frame: Int32): Canvas =
        let s = lunge(frame);
        let topY = 3 + s;
        let torsoY = 11 + s;
        let base =
            headUp(topY)
                |> overlay(torsoUp(torsoY))
                |> overlay(legsUp(19 + s, 0, 0));
        match frame {
            case 0 =>
                base
                    |> overlay(armLimb(19, torsoY + 1, 22, torsoY + 2))
                    |> overlay(dagger(22, torsoY + 2, 1))
                    |> overlay(knifeBelt(11, torsoY + 6))
            case 1 =>
                base
                    |> overlay(armLimb(19, torsoY + 1, 22, torsoY + 3))
                    |> overlay(dagger(22, torsoY + 3, 1))
            case 2 =>                                        // 振りかぶり（上方へ）
                base
                    |> overlay(armLimb(19, torsoY + 1, 23, torsoY - 2))
                    |> overlay(dagger(23, torsoY - 2, 2))
            case 3 =>                                        // ナイフ発射（奥=上へ飛ぶ）
                base
                    |> overlay(armLimb(19, torsoY + 1, 21, torsoY - 3))
                    |> overlay(thrownKnife(17, torsoY - 4, 16, 1))        // 上へ直進
                    |> overlay(thrownKnife(15, torsoY - 4, 14, 1))
            case 4 =>                                        // 短剣の一閃（上の弧）
                base
                    |> overlay(armLimb(19, torsoY + 1, 23, torsoY - 1))
                    |> overlay(dagger(23, torsoY - 1, 2))
                    |> overlay(slashArc(16, torsoY, 8, 30, 150))
            case _ =>                                        // 見得
                base
                    |> overlay(armLimb(19, torsoY + 1, 23, torsoY - 3))
                    |> overlay(dagger(23, torsoY - 3, 2))
        }

    def attackSide(frame: Int32): Canvas =
        let s = lunge(frame);
        let topY = 3 + s;
        let torsoY = 11 + s;
        // 踏み込みで前脚を大きく開く
        let stride = match frame { case 1 => 3 case 2 => 2 case _ => 1 };
        let base =
            headSide(topY)
                |> overlay(torsoSide(torsoY))
                |> overlay(legsSide(19 + s, 29, 29, stride));
        match frame {
            case 0 =>
                base
                    |> overlay(armLimb(13, torsoY + 1, 11, torsoY + 2))
                    |> overlay(dagger(11, torsoY + 2, 3))
                    |> overlay(knifeBelt(14, torsoY + 6))
            case 1 =>                                        // 踏み込み（腕を後ろへ引く）
                base
                    |> overlay(armLimb(15, torsoY + 1, 19, torsoY))
                    |> overlay(dagger(19, torsoY, 0))
            case 2 =>                                        // 振りかぶり
                base
                    |> overlay(armLimb(15, torsoY + 1, 20, torsoY - 1))
                    |> overlay(thrownKnifeSpin(20, torsoY - 1))
                    |> overlay(dagger(11, torsoY + 2, 3))
            case 3 =>                                        // ナイフ発射（左＝前方へ飛ぶ）
                base
                    |> overlay(armLimb(13, torsoY + 1, 9, torsoY))
                    |> overlay(thrownKnife(8, torsoY, 1, torsoY - 1))     // 左へ直進
                    |> overlay(thrownKnife(8, torsoY + 2, 1, torsoY + 1))
            case 4 =>                                        // 短剣の一閃（前方の弧）
                base
                    |> overlay(armLimb(13, torsoY + 1, 8, torsoY + 2))
                    |> overlay(dagger(8, torsoY + 2, 4))
                    |> overlay(slashArc(11, torsoY + 3, 8, 120, 240))
            case _ =>                                        // 見得
                base
                    |> overlay(armLimb(13, torsoY + 1, 9, torsoY - 3))
                    |> overlay(dagger(9, torsoY - 3, 3))
        }

    /// 回転するナイフ（投げる前の残像・小さな十字）。
    def thrownKnifeSpin(cx: Int32, cy: Int32): Canvas =
        empty()
            |> dot(cx, cy, blade())
            |> dot(cx - 1, cy, blade())
            |> dot(cx + 1, cy, blade())
            |> dot(cx, cy - 1, flash())
            |> dot(cx, cy + 1, blade())

    /// 短剣の斬撃軌跡（明色の連続弧・2px 幅で厚く）。
    def slashArc(cx: Int32, cy: Int32, r: Int32, a0: Int32, a1: Int32): Canvas =
        arc(cx, cy, r, a0, a1, flash(), empty())
            |> overlay(arc(cx, cy, r - 1, a0, a1, blade(), empty()))    // 内側 1px で厚み

    // ════════════════════════════════════════════════════════════
    //  UseItem — 薬瓶を掲げる→明色フラッシュ→使う の 3 拍（4 コマ）。
    // ════════════════════════════════════════════════════════════

    /// 小瓶（手 (hx,hy) の上に置く・黄の中身 + 銀の口）。
    def vial(hx: Int32, hy: Int32): Canvas =
        empty()
            |> dot(hx, hy - 1, blade())            // 口
            |> vline(hx, hy, 2, trim())            // 黄の中身
            |> dot(hx - 1, hy + 1, suit())         // 瓶の縁

    def useItemDown(frame: Int32): Canvas =
        let topY = 3;
        let torsoY = 11;
        let base =
            headDown(topY)
                |> overlay(torsoDown(torsoY))
                |> overlay(knifeBelt(11, torsoY + 6))
                |> overlay(dagger(21, torsoY + 3, 1))              // 短剣は右手に握ったまま
                |> overlay(armLimb(19, torsoY + 1, 21, torsoY + 3))
                |> overlay(legsDown(19, 0, 0));
        match frame {
            case 0 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY + 4)) |> overlay(vial(11, torsoY + 4))
            case 1 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY - 1)) |> overlay(vial(11, torsoY - 1))  // 掲げる
            case 2 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY - 1)) |> overlay(useFlash(11, torsoY - 1)) // 白フラッシュ
            case _ => base |> overlay(armLimb(12, torsoY + 1, 13, topY + 5)) |> overlay(vial(13, topY + 5))       // 口へ運ぶ
        }

    def useItemUp(frame: Int32): Canvas =
        let topY = 3;
        let torsoY = 11;
        let base =
            headUp(topY)
                |> overlay(torsoUp(torsoY))
                |> overlay(dagger(21, torsoY + 3, 1))
                |> overlay(armLimb(19, torsoY + 1, 21, torsoY + 3))
                |> overlay(legsUp(19, 0, 0));
        match frame {
            case 0 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY + 4)) |> overlay(vial(11, torsoY + 4))
            case 1 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY - 1)) |> overlay(vial(11, torsoY - 1))
            case 2 => base |> overlay(armLimb(12, torsoY + 1, 11, torsoY - 1)) |> overlay(useFlash(11, torsoY - 1))
            case _ => base |> overlay(armLimb(12, torsoY + 1, 12, topY + 4)) |> overlay(vial(12, topY + 4))
        }

    def useItemSide(frame: Int32): Canvas =
        let topY = 3;
        let torsoY = 11;
        let base =
            headSide(topY)
                |> overlay(torsoSide(torsoY))
                |> overlay(knifeBelt(14, torsoY + 6))
                |> overlay(legsSide(19, 29, 29, 1));
        match frame {
            case 0 => base |> overlay(armLimb(13, torsoY + 1, 11, torsoY + 4)) |> overlay(vial(11, torsoY + 4))
            case 1 => base |> overlay(armLimb(13, torsoY + 1, 10, torsoY - 1)) |> overlay(vial(10, torsoY - 1))
            case 2 => base |> overlay(armLimb(13, torsoY + 1, 10, torsoY - 1)) |> overlay(useFlash(10, torsoY - 1))
            case _ => base |> overlay(armLimb(13, torsoY + 1, 11, topY + 5)) |> overlay(vial(11, topY + 5))
        }

    /// アイテム発動の明色フラッシュ（中心から放射する小さな星）。
    def useFlash(cx: Int32, cy: Int32): Canvas =
        empty()
            |> dot(cx, cy, flash())
            |> dot(cx - 2, cy, flash())
            |> dot(cx + 2, cy, flash())
            |> dot(cx, cy - 2, flash())
            |> dot(cx, cy + 2, flash())
            |> dot(cx - 1, cy - 1, trim())
            |> dot(cx + 1, cy - 1, trim())
            |> dot(cx - 1, cy + 1, trim())
            |> dot(cx + 1, cy + 1, trim())

    // ════════════════════════════════════════════════════════════
    //  Damage — 白フラッシュ + 大げさにのけぞる芝居。
    //  3 コマ: 0=全身白+ノックバック 1=のけぞり深く 2=戻りかけ。
    // ════════════════════════════════════════════════════════════

    /// キャンバス全体を白 1 色に塗り替える（シルエット・フラッシュ用）。
    def whiteOut(cv: Canvas): Canvas =
        Map.map(_ -> flash(), cv)

    def damageDown(frame: Int32): Canvas =
        // 芝居のベース = のけぞった idle 姿勢
        let recoil = damagePose(RogueStage.Clip.IdleDown);
        match frame {
            case 0 => whiteOut(shift(0, 1, recoil))        // 全身白・手前(下)へ 1px + のけぞり
            case 1 => shift(0, 1, tiltBack(recoil, -2))    // 深くのけぞる（上体を後傾）
            case _ => tiltBack(recoil, -1)                 // 戻りかけ
        }

    def damageUp(frame: Int32): Canvas =
        let recoil = damagePose(RogueStage.Clip.IdleUp);
        match frame {
            case 0 => whiteOut(shift(0, -1, recoil))       // 全身白・奥(上)へ 1px
            case 1 => shift(0, -1, tiltBack(recoil, -2))
            case _ => tiltBack(recoil, -1)
        }

    def damageSide(frame: Int32): Canvas =
        let recoil = damagePose(RogueStage.Clip.IdleSide);
        match frame {
            case 0 => whiteOut(shift(2, 0, recoil))        // 全身白・横(右=後方)へ 2px
            case 1 => shift(2, 0, tiltBack(recoil, -2))
            case _ => shift(1, 0, tiltBack(recoil, -1))
        }

    /// 被弾ポーズの元絵（idle f0 を使う）。
    def damagePose(clip: RogueStage.Clip): Canvas = draw(clip, 0)

    /// 上体を後ろへ傾ける（y < 14 の部分だけ dx 平行移動して「のけぞり」）。
    def tiltBack(cv: Canvas, dx: Int32): Canvas =
        Map.foldLeftWithKey((acc, k, c) -> {
            let (x, y) = k;
            if (y < 14)
                PixelCanvas.dot(x + dx, y, c, acc)     // 頭・肩を後傾
            else
                PixelCanvas.dot(x, y, c, acc)
        }, empty(), cv)

    // ════════════════════════════════════════════════════════════
    //  Death — 膝どまりの大芝居（正面・6 コマ）。倒れ伏さない。
    //  0,1 よろめき → 2,3 膝から崩れ → 4,5 膝立ちのまま前傾がくり。
    //  一回転しかけて崩れ、ナイフを落とす。
    // ════════════════════════════════════════════════════════════

    def death(frame: Int32): Canvas = match frame {
        case 0 => deathStagger(2)      // よろめき（右へ傾ぐ・つま先立ち）
        case 1 => deathStagger(-3)     // 反対へ大きくよろめく（回りかけ）
        case 2 => deathCrumble(0)      // 膝から崩れる（沈み始め）
        case 3 => deathCrumble(1)      // 片膝が地面に着く
        case _ => deathKneel(frame - 4) // 膝立ち前傾がくり（0,1）
    }

    /// よろめき: 立位のまま上体を lean だけ傾ける。足は接地維持。
    def deathStagger(lean: Int32): Canvas =
        let topY = 4;
        let torsoY = 12;
        // 上体を lean、頭をさらに傾ける
        let head = shift(lean, 0, headDown(topY));
        let torso = shift(lean / 2, 0, torsoDown(torsoY));
        head
            |> overlay(torso)
            |> overlay(armLimb(19, torsoY + 1, 22 + lean, torsoY + 5))   // 腕がだらり
            |> overlay(dagger(22 + lean, torsoY + 5, 6))                 // 短剣を下向きに
            |> overlay(legsDown(19, 0, 0))

    /// 崩れ: 上体が沈み、両膝が曲がる。step0=沈み始め, step1=片膝接地。
    def deathCrumble(step: Int32): Canvas =
        let sink = 3 + step * 3;                 // 上体の沈み込み
        let topY = 4 + sink;
        let torsoY = 12 + sink;
        // 膝: 太ももを短く折り、膝下(すね)を地面へ。膝が y=29 付近に来る。
        let legs =
            empty()
                |> overlay(vlineTo(13, torsoY + 6, 26 + step, suitDark()))   // 左太もも
                |> overlay(vlineTo(14, torsoY + 6, 26 + step, suit()))
                |> overlay(vlineTo(17, torsoY + 6, 26 + step, suit()))       // 右太もも
                |> overlay(vlineTo(18, torsoY + 6, 26 + step, suitDark()))
                |> hline(12, 27 + step, 3, suit())                  // 左すね（前に折れる）
                |> hline(17, 27 + step, 3, suit())                  // 右すね
                |> hline(11, 29, 4, trim())                         // 足先（接地）
                |> hline(17, 29, 4, trim());
        headDown(topY)
            |> overlay(torsoDown(torsoY))
            |> overlay(legs)
            |> overlay(armLimb(19, torsoY + 1, 23, torsoY + 6))         // 腕を投げ出す
            // ナイフを取り落とす（宙〜地面へ）
            |> overlay(fallingKnife(step))

    /// 膝立ち前傾がくり: 膝を地面に着けたまま上体が前へガクッと落ちる。
    /// step0=前傾, step1=さらに深く前傾（最終コマ）。
    def deathKneel(step: Int32): Canvas =
        let bow = step * 2;                       // 前傾の深さ
        let torsoY = 16;
        // 膝立ち: もも(y=22..)から膝(y=27..29)まで繋げ、腰から上を積む。
        let legs =
            empty()
                |> hline(12, 29, 3, trim())                        // 左膝・すね接地
                |> hline(17, 29, 3, trim())                        // 右膝・すね接地
                |> vline(13, 20, 8, suitDark())                    // 左もも（腰から膝へ）
                |> vline(14, 20, 8, suit())
                |> vline(17, 20, 8, suit())
                |> vline(18, 20, 8, suitDark())
                |> hline(12, 28, 8, suitDark());                   // 膝の接地帯（影）
        // 上体を前傾（頭を前=下 かつ 少し右へガクッ）
        let head = shift(bow, bow, headDown(8));
        let torso = shift(bow / 2, bow, torsoDown(torsoY - 4));
        legs
            |> overlay(torso)
            |> overlay(head)
            |> overlay(armLimb(19, torsoY - 3, 22 + bow, torsoY + bow))  // 腕が力なく垂れる
            // 落としたナイフが足元に転がっている
            |> overlay(droppedKnife())

    /// 取り落とすナイフ（崩れ中に宙を舞う）。step で落下位置が下がる。
    def fallingKnife(step: Int32): Canvas =
        let ky = 14 + step * 8;
        empty()
            |> dot(24, ky, blade())
            |> dot(25, ky, blade())
            |> dot(24, ky - 1, flash())
            |> dot(23, ky, trim())                 // 黄の柄

    /// 地面に転がった短剣（足元・水平）。
    def droppedKnife(): Canvas =
        empty()
            |> hline(21, 30, 4, blade())
            |> dot(25, 30, flash())                // 切っ先
            |> dot(20, 30, trim())                 // 黄の柄頭
}
