// KnightB — 深紅のマントを纏うフルプレートの老騎士。両手持ちの大剣が常に主役。
// 重量感の演出方針:
//   - 歩行は上下動より「左右の踏みしめ」(体の横ずれ + 接地コマで沈み込み)
//   - 攻撃は担ぎ上げ → 溜め2コマ → 一気の振り下ろし + 地面に衝撃の星
//   - Death は正面向きの見せ場: 大剣が先に手を離れて地に刺さり、膝から崩れて膝立ちのまま果てる
mod KnightB {

    type alias Cv = PixelCanvas.Canvas

    pub def name(): String = "KNIGHT B 深紅の老大剣騎士"

    // v3 契約: 16 クリップ全て方向別に本作画。Side 系は左向きで描く(右向きは実行時 hflip)。
    pub def draw(clip: RogueStage.Clip, frame: Int32): PixelCanvas.Canvas =
        match clip {
            case RogueStage.Clip.IdleDown    => idle(wrapF(4, frame))
            case RogueStage.Clip.IdleUp      => idleUp(wrapF(4, frame))
            case RogueStage.Clip.IdleSide    => idleSide(wrapF(4, frame))
            case RogueStage.Clip.WalkDown    => walkDown(wrapF(4, frame))
            case RogueStage.Clip.WalkUp      => walkUp(wrapF(4, frame))
            case RogueStage.Clip.WalkSide    => walkSide(wrapF(4, frame))
            case RogueStage.Clip.AttackDown  => attackDown(clampF(6, frame))
            case RogueStage.Clip.AttackUp    => attackUp(clampF(6, frame))
            case RogueStage.Clip.AttackSide  => attack(clampF(6, frame))
            case RogueStage.Clip.UseItemDown => useItemDown(clampF(4, frame))
            case RogueStage.Clip.UseItemUp   => useItemUp(clampF(4, frame))
            case RogueStage.Clip.UseItemSide => useItem(clampF(4, frame))
            case RogueStage.Clip.DamageDown  => damageDown(clampF(3, frame))
            case RogueStage.Clip.DamageUp    => damageUp(clampF(3, frame))
            case RogueStage.Clip.DamageSide  => damage(clampF(3, frame))
            case RogueStage.Clip.Death       => death(clampF(6, frame))
        }

    // ── コマ番号の安全化: ループするクリップは周回で巻き込み、単発は端で止める ──

    def wrapF(n: Int32, f: Int32): Int32 =
        let m = Int32.remainder(f, n);
        if (m < 0) m + n else m

    def clampF(n: Int32, f: Int32): Int32 =
        Int32.max(0, Int32.min(f, n - 1))

    // ── 色 (RoguePalette のみ): 鋼2階調 + 深紅 + 金2階調 + 刃ハイライト ──

    def steel(): Color = RoguePalette.silver()    // 鎧の明部
    def steelD(): Color = RoguePalette.gray()     // 鎧の暗部
    def iron(): Color = RoguePalette.darkGray()   // ベルト・バイザーの影
    def crimson(): Color = RoguePalette.red()     // マント
    def crimsonD(): Color = RoguePalette.plum()   // マントの皺(赤の1段暗い色)
    def goldB(): Color = RoguePalette.yellow()    // 金装飾の明部
    def goldD(): Color = RoguePalette.mustard()   // 金装飾の暗部(裾の縁飾り)
    def edge(): Color = RoguePalette.paleBlue()   // 刃のハイライト
    def hilt(): Color = RoguePalette.darkBrown()  // 柄巻き
    def flash(): Color = RoguePalette.white()     // 被弾フラッシュ・斬撃・星

    // ── 汎用小物 ──

    // 条件付きでだけ 1 手順を適用する(まばたき的な差分に使う)。
    def when(b: Bool, f: Cv -> Cv, cv: Cv): Cv = if (b) f(cv) else cv

    // 全ピクセルを白に飛ばす(被弾フラッシュ)。
    def whiteOut(cv: Cv): Cv = Map.map(_ -> flash(), cv)

    // 白い十字の星(衝撃表現)。
    def starAt(x: Int32, y: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.dot(x, y, flash())
           |> PixelCanvas.dot(x - 1, y, flash())
           |> PixelCanvas.dot(x + 1, y, flash())
           |> PixelCanvas.dot(x, y - 1, flash())
           |> PixelCanvas.dot(x, y + 1, flash())

    // ══════════════ 正面向きの部品 (Idle / WalkDown / Death) ══════════════

    // 兜: 赤い羽根飾り + 銀の兜 + 暗いバイザーのスリット。
    def frontHelmet(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.dot(15 + dx, 3 + dy, crimson())
           |> PixelCanvas.dot(16 + dx, 3 + dy, crimson())
           |> PixelCanvas.hline(14 + dx, 4 + dy, 3, crimson())
           |> PixelCanvas.hline(13 + dx, 5 + dy, 6, steel())
           |> PixelCanvas.rectFill(12 + dx, 6 + dy, 8, 3, steel())
           |> PixelCanvas.hline(13 + dx, 7 + dy, 6, iron())
           |> PixelCanvas.hline(13 + dx, 9 + dy, 6, steelD())

    // 胴: 大きな肩当て(金鋲) + 胸甲(金の紋) + 腹甲 + ベルト(金バックル)。
    def frontTorso(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.hline(10 + dx, 10 + dy, 12, steel())
           |> PixelCanvas.dot(10 + dx, 10 + dy, goldB())
           |> PixelCanvas.dot(21 + dx, 10 + dy, goldB())
           |> PixelCanvas.hline(9 + dx, 11 + dy, 3, steelD())
           |> PixelCanvas.hline(12 + dx, 11 + dy, 8, steel())
           |> PixelCanvas.hline(20 + dx, 11 + dy, 3, steelD())
           |> PixelCanvas.hline(9 + dx, 12 + dy, 2, steelD())
           |> PixelCanvas.hline(11 + dx, 12 + dy, 10, steel())
           |> PixelCanvas.hline(21 + dx, 12 + dy, 2, steelD())
           |> PixelCanvas.rectFill(12 + dx, 13 + dy, 8, 3, steel())
           |> PixelCanvas.dot(15 + dx, 14 + dy, goldB())
           |> PixelCanvas.dot(16 + dx, 14 + dy, goldB())
           |> PixelCanvas.rectFill(12 + dx, 16 + dy, 8, 3, steelD())
           |> PixelCanvas.hline(12 + dx, 19 + dy, 8, iron())
           |> PixelCanvas.dot(15 + dx, 19 + dy, goldB())
           |> PixelCanvas.dot(16 + dx, 19 + dy, goldB())

    // マント: 体の両脇に垂れる深紅、裾に金の縁飾り。flick で裾が 1px はためく。
    def frontMantle(dx: Int32, dy: Int32, flickL: Bool, flickR: Bool, cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(10 + dx, 13 + dy, 2, 8, crimson())
           |> PixelCanvas.hline(10 + dx, 21 + dy, 2, goldD())
           |> PixelCanvas.rectFill(20 + dx, 13 + dy, 2, 8, crimson())
           |> PixelCanvas.hline(20 + dx, 21 + dy, 2, goldD())
           |> when(flickL, PixelCanvas.dot(9 + dx, 20 + dy, crimson()))
           |> when(flickR, PixelCanvas.dot(22 + dx, 20 + dy, crimson()))

    // 直立の両脚(膝当ての銀ライン + 靴)。足の底は y=29。
    def frontLegsStand(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 20, 3, 8, steelD())
           |> PixelCanvas.hline(12, 23, 3, steel())
           |> PixelCanvas.rectFill(17, 20, 3, 8, steelD())
           |> PixelCanvas.hline(17, 23, 3, steel())
           |> PixelCanvas.hline(11, 28, 4, steel())
           |> PixelCanvas.hline(11, 29, 4, steelD())
           |> PixelCanvas.hline(17, 28, 4, steel())
           |> PixelCanvas.hline(17, 29, 4, steelD())

    // 歩き: 左足を大きく踏み出し、右足は浮かせて引き付ける。
    def frontLegsStepL(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(10, 20, 3, 8, steelD())
           |> PixelCanvas.hline(10, 23, 3, steel())
           |> PixelCanvas.hline(9, 28, 4, steel())
           |> PixelCanvas.hline(9, 29, 4, steelD())
           |> PixelCanvas.rectFill(17, 21, 3, 6, steelD())
           |> PixelCanvas.hline(17, 27, 4, steel())
           |> PixelCanvas.hline(17, 28, 4, steelD())

    // 歩き: 右足を大きく踏み出し、左足は浮かせて引き付ける。
    def frontLegsStepR(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(19, 20, 3, 8, steelD())
           |> PixelCanvas.hline(19, 23, 3, steel())
           |> PixelCanvas.hline(19, 28, 4, steel())
           |> PixelCanvas.hline(19, 29, 4, steelD())
           |> PixelCanvas.rectFill(12, 21, 3, 6, steelD())
           |> PixelCanvas.hline(11, 27, 4, steel())
           |> PixelCanvas.hline(11, 28, 4, steelD())

    // 歩き: 両足が体の下に揃う接地コマ(体は 1px 沈む)。
    def frontLegsContact(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 21, 3, 7, steelD())
           |> PixelCanvas.hline(12, 24, 3, steel())
           |> PixelCanvas.rectFill(17, 21, 3, 7, steelD())
           |> PixelCanvas.hline(17, 24, 3, steel())
           |> PixelCanvas.hline(11, 28, 4, steel())
           |> PixelCanvas.hline(11, 29, 4, steelD())
           |> PixelCanvas.hline(17, 28, 4, steel())
           |> PixelCanvas.hline(17, 29, 4, steelD())

    // 待機用の大剣: 切っ先を地に突き立てた 3px 幅の刃(中央がハイライトの峰)。
    def plantedSword(cv: Cv): Cv =
        cv |> PixelCanvas.vline(5, 14, 14, steel())
           |> PixelCanvas.vline(6, 14, 14, edge())
           |> PixelCanvas.vline(7, 14, 14, steel())
           |> PixelCanvas.dot(6, 28, steel())
           |> PixelCanvas.hline(3, 13, 7, goldB())
           |> PixelCanvas.dot(6, 11, hilt())
           |> PixelCanvas.dot(6, 12, hilt())
           |> PixelCanvas.dot(5, 10, goldB())
           |> PixelCanvas.dot(6, 10, goldB())

    // 待機の両腕: 左腕は柄頭に添え、右腕は体側に垂れる(呼吸 dy に追従)。
    def idleArms(dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.hline(5, 9 + dy, 3, steel())
           |> PixelCanvas.dot(8, 10 + dy, steelD())
           |> PixelCanvas.dot(9, 10 + dy, steelD())
           |> PixelCanvas.dot(9, 11 + dy, steelD())
           |> PixelCanvas.vline(21, 13 + dy, 4, steelD())
           |> PixelCanvas.vline(22, 13 + dy, 3, steelD())
           |> PixelCanvas.dot(21, 17 + dy, steel())
           |> PixelCanvas.dot(22, 16 + dy, steel())

    // Idle: 突き立てた大剣に手を添えて重く呼吸する。f1/f3 は肩が 1px 沈み、
    // f2/f3 でマントの裾が交互にはためく(4コマ全て差分あり)。
    def idle(f: Int32): Cv =
        let dy = if (f == 1 or f == 3) 1 else 0;
        PixelCanvas.empty()
            |> frontLegsStand
            |> frontMantle(0, dy, f == 2, f == 3)
            |> frontTorso(0, dy)
            |> frontHelmet(0, dy)
            |> plantedSword
            |> idleArms(dy)

    // 背面立ちの足元(裾の下の脚 + 靴)。Up 系クリップ共通。
    def upFeetStand(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 25, 3, 3, steelD())
           |> PixelCanvas.rectFill(17, 25, 3, 3, steelD())
           |> PixelCanvas.hline(12, 28, 3, steel())
           |> PixelCanvas.hline(12, 29, 3, steelD())
           |> PixelCanvas.hline(17, 28, 3, steel())
           |> PixelCanvas.hline(17, 29, 3, steelD())

    // マントの皺: 布の中に走る暗色の縦筋 2 本 + 肩口の折り目 1 点。
    // 体の揺れ (dx,dy) に追従して動くので、大きな赤い面が布として読める。
    def backMantleWrinkles(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.vline(12 + dx, 14 + dy, 7, crimsonD())
           |> PixelCanvas.vline(18 + dx, 15 + dy, 6, crimsonD())
           |> PixelCanvas.dot(15 + dx, 13 + dy, crimsonD())

    // IdleUp: 背面の呼吸。肩とマント上端が f1/f3 で 1px 沈み、裾が f2/f3 で交互に揺れる。
    def idleUp(f: Int32): Cv =
        let dy = if (f == 1 or f == 3) 1 else 0;
        PixelCanvas.empty()
            |> upFeetStand
            |> backUpper(0, dy, 0)
            |> backMantleWrinkles(0, dy)
            |> swordOnShoulderUp(0, dy)
            |> when(f == 2, PixelCanvas.dot(8, 22, crimson()))
            |> when(f == 3, PixelCanvas.dot(23, 22 + dy, crimson()))

    // 横向き待機用の大剣: 体の前(左)で切っ先を地に突き立てる。
    def sidePlantedSword(cv: Cv): Cv =
        cv |> PixelCanvas.vline(6, 14, 14, steel())
           |> PixelCanvas.vline(7, 14, 14, edge())
           |> PixelCanvas.dot(6, 28, steel())
           |> PixelCanvas.hline(4, 13, 6, goldB())
           |> PixelCanvas.dot(6, 11, hilt())
           |> PixelCanvas.dot(6, 12, hilt())
           |> PixelCanvas.dot(5, 10, goldB())
           |> PixelCanvas.dot(6, 10, goldB())

    // IdleSide: 地に突いた大剣に手前の腕を預けて重く呼吸する(左向き)。
    // 剣は地面に固定したまま、体と腕だけが dy で上下する。
    def idleSide(f: Int32): Cv =
        let dy = if (f == 1 or f == 3) 1 else 0;
        PixelCanvas.empty()
            |> sideLegsStand
            |> sideMantle(0, dy, f == 2 or f == 3)
            |> sideTorso(0, dy)
            |> sideHelmet(0, dy)
            |> sidePlantedSword
            |> PixelCanvas.dot(11, 11 + dy, steelD())
            |> PixelCanvas.dot(10, 11 + dy, steelD())
            |> PixelCanvas.dot(9, 10 + dy, steelD())
            |> PixelCanvas.dot(8, 10 + dy, steel())
            |> PixelCanvas.dot(7, 10 + dy, steel())

    // 正面歩行用の大剣: 右肩に担ぎ、刃が頭上へ斜めに突き出る。
    def swordOnShoulderDown(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.line(20 + dx, 10 + dy, 26 + dx, 3 + dy, steel())
           |> PixelCanvas.line(21 + dx, 10 + dy, 27 + dx, 3 + dy, steel())
           |> PixelCanvas.line(20 + dx, 9 + dy, 26 + dx, 2 + dy, edge())
           |> PixelCanvas.dot(19 + dx, 11 + dy, goldB())
           |> PixelCanvas.dot(20 + dx, 11 + dy, goldB())
           |> PixelCanvas.dot(18 + dx, 12 + dy, hilt())
           |> PixelCanvas.dot(17 + dx, 13 + dy, steel())
           |> PixelCanvas.dot(18 + dx, 13 + dy, steel())

    // 正面歩行の左腕振り(右腕は柄を握って固定)。
    def walkDownArm(f: Int32, dx: Int32, dy: Int32, cv: Cv): Cv =
        if (f == 0)
            cv |> PixelCanvas.vline(9 + dx, 13 + dy, 4, steelD())
               |> PixelCanvas.dot(9 + dx, 17 + dy, steel())
        else if (f == 1)
            cv |> PixelCanvas.vline(10 + dx, 13 + dy, 3, steelD())
               |> PixelCanvas.dot(10 + dx, 16 + dy, steel())
        else if (f == 2)
            cv |> PixelCanvas.dot(10 + dx, 13 + dy, steelD())
               |> PixelCanvas.dot(10 + dx, 14 + dy, steelD())
               |> PixelCanvas.dot(11 + dx, 15 + dy, steelD())
               |> PixelCanvas.dot(11 + dx, 16 + dy, steel())
        else
            cv |> PixelCanvas.vline(9 + dx, 14 + dy, 3, steelD())
               |> PixelCanvas.dot(9 + dx, 17 + dy, steel())

    // WalkDown: 一歩ごとに体が左右へ 1px 揺れ(踏みしめ)、接地コマで 1px 沈む。
    def walkDown(f: Int32): Cv =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let dy = if (f == 1 or f == 3) 1 else 0;
        let legs = if (f == 0) frontLegsStepL else if (f == 2) frontLegsStepR else frontLegsContact;
        PixelCanvas.empty()
            |> legs
            |> frontMantle(sway, dy, f == 1, f == 3)
            |> frontTorso(sway, dy)
            |> frontHelmet(sway, dy)
            |> swordOnShoulderDown(sway, dy)
            |> walkDownArm(f, sway, dy)

    // 背面歩行用の大剣: 背中側から見ると左肩越しに刃が覗く。
    def swordOnShoulderUp(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.line(11 + dx, 10 + dy, 5 + dx, 3 + dy, steel())
           |> PixelCanvas.line(12 + dx, 10 + dy, 6 + dx, 3 + dy, steel())
           |> PixelCanvas.line(11 + dx, 9 + dy, 5 + dx, 2 + dy, edge())
           |> PixelCanvas.dot(12 + dx, 11 + dy, goldB())
           |> PixelCanvas.dot(13 + dx, 11 + dy, goldB())

    // 背面: 兜の後頭部(スリット無し・金の帯) + 深紅のマントが背中を覆う。
    def backUpper(dx: Int32, dy: Int32, hemDx: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.dot(15 + dx, 3 + dy, crimson())
           |> PixelCanvas.dot(16 + dx, 3 + dy, crimson())
           |> PixelCanvas.hline(14 + dx, 4 + dy, 3, crimson())
           |> PixelCanvas.hline(13 + dx, 5 + dy, 6, steel())
           |> PixelCanvas.rectFill(12 + dx, 6 + dy, 8, 3, steel())
           |> PixelCanvas.hline(13 + dx, 7 + dy, 6, goldD())
           |> PixelCanvas.hline(13 + dx, 9 + dy, 6, steelD())
           |> PixelCanvas.hline(10 + dx, 10 + dy, 12, steel())
           |> PixelCanvas.dot(10 + dx, 10 + dy, goldB())
           |> PixelCanvas.dot(21 + dx, 10 + dy, goldB())
           |> PixelCanvas.hline(9 + dx, 11 + dy, 14, steelD())
           |> PixelCanvas.rectFill(9 + dx, 12 + dy, 14, 12, crimson())
           |> PixelCanvas.vline(9 + dx, 12 + dy, 12, goldD())
           |> PixelCanvas.vline(22 + dx, 12 + dy, 12, goldD())
           |> PixelCanvas.hline(9 + dx + hemDx, 24 + dy, 14, goldD())

    // WalkUp: マントの裾が歩調に合わせて左右に流れ、裾の下で靴が交互に出る。
    // 皺の縦筋(crimsonD)が体の揺れに追従し、裾の輪郭は 4 コマとも違う形にして
    // 大きな赤い四角に見えないようにする。
    def walkUp(f: Int32): Cv =
        let sway = if (f == 0) -1 else if (f == 2) 1 else 0;
        let dy = if (f == 1 or f == 3) 1 else 0;
        let hemDx = if (f == 0) -1 else if (f == 2) 1 else 0;
        let hemFlutter =
            if (f == 0)
                (cv -> cv |> PixelCanvas.dot(9, 25, crimson())
                          |> PixelCanvas.dot(10, 25, crimson())
                          |> PixelCanvas.hline(9, 26, 2, goldD()))
            else if (f == 1)
                (cv -> cv |> PixelCanvas.dot(20, 26, crimson())
                          |> PixelCanvas.dot(20, 27, goldD()))
            else if (f == 2)
                (cv -> cv |> PixelCanvas.dot(21, 25, crimson())
                          |> PixelCanvas.dot(22, 25, crimson())
                          |> PixelCanvas.hline(21, 26, 2, goldD()))
            else
                (cv -> cv |> PixelCanvas.dot(11, 26, crimson())
                          |> PixelCanvas.dot(11, 27, goldD()));
        let feet =
            if (f == 0)
                (cv -> cv |> PixelCanvas.hline(12, 28, 3, steel())
                          |> PixelCanvas.hline(12, 29, 3, steelD())
                          |> PixelCanvas.hline(17, 27, 3, steel())
                          |> PixelCanvas.hline(17, 28, 3, steelD()))
            else if (f == 2)
                (cv -> cv |> PixelCanvas.hline(17, 28, 3, steel())
                          |> PixelCanvas.hline(17, 29, 3, steelD())
                          |> PixelCanvas.hline(12, 27, 3, steel())
                          |> PixelCanvas.hline(12, 28, 3, steelD()))
            else
                (cv -> cv |> PixelCanvas.hline(12, 28, 3, steel())
                          |> PixelCanvas.hline(12, 29, 3, steelD())
                          |> PixelCanvas.hline(17, 28, 3, steel())
                          |> PixelCanvas.hline(17, 29, 3, steelD()));
        PixelCanvas.empty()
            |> PixelCanvas.rectFill(12, 25, 3, 3, steelD())
            |> PixelCanvas.rectFill(17, 25, 3, 3, steelD())
            |> feet
            |> backUpper(sway, dy, hemDx)
            |> backMantleWrinkles(sway, dy)
            |> hemFlutter
            |> swordOnShoulderUp(sway, dy)
            |> when(f == 3, PixelCanvas.dot(23, 20 + dy, crimson()))
            |> when(f == 1, PixelCanvas.dot(8, 20 + dy, crimson()))

    // ══════════════ 横向き(左向き)の部品 (WalkSide / Attack / UseItem / Damage) ══════════════

    // 兜(横): バイザーが左を向き、羽根飾りは後方(右)へ流れる。
    def sideHelmet(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.dot(17 + dx, 3 + dy, crimson())
           |> PixelCanvas.dot(18 + dx, 3 + dy, crimson())
           |> PixelCanvas.hline(16 + dx, 4 + dy, 3, crimson())
           |> PixelCanvas.hline(12 + dx, 5 + dy, 6, steel())
           |> PixelCanvas.rectFill(11 + dx, 6 + dy, 8, 3, steel())
           |> PixelCanvas.dot(11 + dx, 7 + dy, iron())
           |> PixelCanvas.dot(12 + dx, 7 + dy, iron())
           |> PixelCanvas.hline(12 + dx, 9 + dy, 6, steelD())

    // 胴(横): 前傾気味の胸甲と大きな肩当て。
    def sideTorso(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.hline(12 + dx, 10 + dy, 5, steel())
           |> PixelCanvas.dot(12 + dx, 10 + dy, goldB())
           |> PixelCanvas.rectFill(12 + dx, 11 + dy, 5, 2, steel())
           |> PixelCanvas.rectFill(11 + dx, 12 + dy, 6, 4, steel())
           |> PixelCanvas.rectFill(11 + dx, 16 + dy, 6, 3, steelD())
           |> PixelCanvas.hline(11 + dx, 19 + dy, 6, iron())
           |> PixelCanvas.dot(12 + dx, 19 + dy, goldB())
           |> PixelCanvas.hline(12 + dx, 20 + dy, 5, steelD())

    // マント(横): 背中側(右)へ垂れ、sway で後方へ大きく流れる。
    def sideMantle(dx: Int32, dy: Int32, sway: Bool, cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(17 + dx, 11 + dy, 3, 10, crimson())
           |> PixelCanvas.vline(20 + dx, 15 + dy, 6, crimson())
           |> PixelCanvas.hline(17 + dx, 21 + dy, 4, goldD())
           |> when(sway, PixelCanvas.vline(21 + dx, 17 + dy, 4, crimson()))
           |> when(sway, PixelCanvas.dot(21 + dx, 21 + dy, goldD()))

    // 肩担ぎの大剣(横): 刃は後方上へ 2px 幅 + 峰のハイライト。
    def sideSwordShoulder(dx: Int32, dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.line(15 + dx, 10 + dy, 22 + dx, 4 + dy, steel())
           |> PixelCanvas.line(16 + dx, 10 + dy, 23 + dx, 4 + dy, steel())
           |> PixelCanvas.line(15 + dx, 9 + dy, 22 + dx, 3 + dy, edge())
           |> PixelCanvas.dot(14 + dx, 10 + dy, goldB())
           |> PixelCanvas.dot(14 + dx, 11 + dy, goldB())
           |> PixelCanvas.dot(13 + dx, 11 + dy, hilt())
           |> PixelCanvas.dot(12 + dx, 12 + dy, hilt())
           |> PixelCanvas.dot(11 + dx, 12 + dy, steelD())

    // 横歩き: 大股の踏み込みコマ(左足前・後ろ足は蹴り出し)。
    def sideLegsStride0(cv: Cv): Cv =
        cv |> PixelCanvas.line(13, 20, 11, 23, steelD())
           |> PixelCanvas.line(14, 20, 12, 23, steelD())
           |> PixelCanvas.vline(10, 24, 4, steelD())
           |> PixelCanvas.vline(11, 24, 4, steelD())
           |> PixelCanvas.dot(11, 23, steel())
           |> PixelCanvas.dot(12, 23, steel())
           |> PixelCanvas.hline(9, 28, 3, steel())
           |> PixelCanvas.hline(9, 29, 3, steelD())
           |> PixelCanvas.line(15, 20, 17, 23, steelD())
           |> PixelCanvas.line(16, 20, 18, 23, steelD())
           |> PixelCanvas.vline(17, 24, 4, steelD())
           |> PixelCanvas.vline(18, 24, 4, steelD())
           |> PixelCanvas.dot(17, 23, steel())
           |> PixelCanvas.dot(18, 23, steel())
           |> PixelCanvas.hline(17, 28, 3, steel())
           |> PixelCanvas.hline(17, 29, 3, steelD())

    // 横歩き: すれ違いコマ(軸足は体の下、逆足は浮いて前へ)。
    def sideLegsPass1(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 21, 2, 7, steelD())
           |> PixelCanvas.hline(11, 28, 3, steel())
           |> PixelCanvas.hline(11, 29, 3, steelD())
           |> PixelCanvas.rectFill(15, 21, 2, 5, steelD())
           |> PixelCanvas.hline(15, 26, 3, steel())
           |> PixelCanvas.hline(15, 27, 3, steelD())

    // 横歩き: 逆足の踏み込みコマ(f0 より歩幅を詰め、足の位置も変える)。
    def sideLegsStride2(cv: Cv): Cv =
        cv |> PixelCanvas.line(14, 20, 12, 23, steelD())
           |> PixelCanvas.line(15, 20, 13, 23, steelD())
           |> PixelCanvas.vline(11, 24, 4, steelD())
           |> PixelCanvas.vline(12, 24, 4, steelD())
           |> PixelCanvas.dot(12, 23, steel())
           |> PixelCanvas.dot(13, 23, steel())
           |> PixelCanvas.hline(10, 28, 3, steel())
           |> PixelCanvas.hline(10, 29, 3, steelD())
           |> PixelCanvas.line(14, 20, 16, 23, steelD())
           |> PixelCanvas.line(15, 20, 17, 23, steelD())
           |> PixelCanvas.vline(16, 24, 4, steelD())
           |> PixelCanvas.vline(17, 24, 4, steelD())
           |> PixelCanvas.dot(16, 23, steel())
           |> PixelCanvas.dot(17, 23, steel())
           |> PixelCanvas.hline(16, 28, 3, steel())
           |> PixelCanvas.hline(16, 29, 3, steelD())

    // 横歩き: すれ違いコマ2(逆足を高く畳む)。
    def sideLegsPass3(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(13, 21, 2, 7, steelD())
           |> PixelCanvas.hline(12, 28, 3, steel())
           |> PixelCanvas.hline(12, 29, 3, steelD())
           |> PixelCanvas.rectFill(16, 21, 2, 4, steelD())
           |> PixelCanvas.hline(16, 25, 3, steel())
           |> PixelCanvas.hline(16, 26, 3, steelD())

    // 横歩きの手前側の腕振り(奥の手は柄を握って固定)。
    def sideArm(f: Int32, dy: Int32, cv: Cv): Cv =
        if (f == 0)
            cv |> PixelCanvas.dot(11, 13 + dy, steelD())
               |> PixelCanvas.dot(12, 13 + dy, steelD())
               |> PixelCanvas.dot(10, 14 + dy, steelD())
               |> PixelCanvas.dot(11, 14 + dy, steelD())
               |> PixelCanvas.dot(9, 15 + dy, steel())
               |> PixelCanvas.dot(10, 15 + dy, steel())
        else if (f == 2)
            cv |> PixelCanvas.dot(14, 13 + dy, steelD())
               |> PixelCanvas.dot(15, 13 + dy, steelD())
               |> PixelCanvas.dot(15, 14 + dy, steelD())
               |> PixelCanvas.dot(16, 14 + dy, steelD())
               |> PixelCanvas.dot(16, 15 + dy, steel())
               |> PixelCanvas.dot(17, 15 + dy, steel())
        else if (f == 1)
            cv |> PixelCanvas.vline(12, 13 + dy, 3, steelD())
               |> PixelCanvas.vline(13, 13 + dy, 3, steelD())
               |> PixelCanvas.dot(12, 16 + dy, steel())
               |> PixelCanvas.dot(13, 16 + dy, steel())
        else
            cv |> PixelCanvas.vline(12, 14 + dy, 2, steelD())
               |> PixelCanvas.vline(13, 14 + dy, 2, steelD())
               |> PixelCanvas.dot(12, 16 + dy, steel())
               |> PixelCanvas.dot(13, 16 + dy, steel())

    // WalkSide: 大股ストライド2種 + すれ違い2種。すれ違いで体が 1px 浮き、
    // 踏み込みでマントが後方へ流れる。左向き作画(f0 は左右非対称)。
    def walkSide(f: Int32): Cv =
        let dy = if (f == 1 or f == 3) -1 else 0;
        let legs =
            if (f == 0) sideLegsStride0
            else if (f == 1) sideLegsPass1
            else if (f == 2) sideLegsStride2
            else sideLegsPass3;
        PixelCanvas.empty()
            |> legs
            |> sideMantle(0, dy, f == 0 or f == 2)
            |> sideTorso(0, dy)
            |> sideHelmet(0, dy)
            |> sideSwordShoulder(0, dy)
            |> sideArm(f, dy)

    // 攻撃用の踏ん張り脚(広いスタンス)。
    def attackLegsBrace(cv: Cv): Cv =
        cv |> PixelCanvas.line(13, 20, 10, 23, steelD())
           |> PixelCanvas.line(14, 20, 11, 23, steelD())
           |> PixelCanvas.vline(9, 24, 4, steelD())
           |> PixelCanvas.vline(10, 24, 4, steelD())
           |> PixelCanvas.dot(10, 23, steel())
           |> PixelCanvas.dot(11, 23, steel())
           |> PixelCanvas.hline(8, 28, 3, steel())
           |> PixelCanvas.hline(8, 29, 3, steelD())
           |> PixelCanvas.line(15, 20, 18, 23, steelD())
           |> PixelCanvas.line(16, 20, 19, 23, steelD())
           |> PixelCanvas.vline(18, 24, 4, steelD())
           |> PixelCanvas.vline(19, 24, 4, steelD())
           |> PixelCanvas.dot(18, 23, steel())
           |> PixelCanvas.dot(19, 23, steel())
           |> PixelCanvas.hline(18, 28, 3, steel())
           |> PixelCanvas.hline(18, 29, 3, steelD())

    // 振り下ろし後の深い踏み込み脚(前足は深く曲げ、後ろ足は伸び切る)。
    def attackLegsLunge(cv: Cv): Cv =
        cv |> PixelCanvas.line(12, 20, 8, 23, steelD())
           |> PixelCanvas.line(13, 20, 9, 23, steelD())
           |> PixelCanvas.vline(7, 24, 4, steelD())
           |> PixelCanvas.vline(8, 24, 4, steelD())
           |> PixelCanvas.dot(8, 23, steel())
           |> PixelCanvas.dot(9, 23, steel())
           |> PixelCanvas.hline(6, 28, 3, steel())
           |> PixelCanvas.hline(6, 29, 3, steelD())
           |> PixelCanvas.line(15, 20, 20, 26, steelD())
           |> PixelCanvas.line(16, 20, 21, 26, steelD())
           |> PixelCanvas.hline(19, 27, 3, steel())
           |> PixelCanvas.hline(20, 28, 2, steelD())

    // Attack: 担ぎ上げ(f0) → 高々と構える(f1) → 沈み込む溜め・切っ先が光る(f2)
    // → 弧の斬撃(f3) → 地面に着弾・衝撃の星(f4) → 残心(f5)。
    def attack(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty()
                |> attackLegsBrace
                |> sideMantle(1, 0, false)
                |> sideTorso(1, 0)
                |> sideHelmet(1, 0)
                |> PixelCanvas.line(16, 11, 23, 6, steel())
                |> PixelCanvas.line(17, 11, 24, 6, steel())
                |> PixelCanvas.line(16, 10, 23, 5, edge())
                |> PixelCanvas.dot(15, 11, goldB())
                |> PixelCanvas.dot(15, 12, goldB())
                |> PixelCanvas.dot(13, 12, steel())
                |> PixelCanvas.dot(14, 12, steel())
        else if (f == 1)
            PixelCanvas.empty()
                |> attackLegsBrace
                |> sideMantle(1, 0, true)
                |> sideTorso(2, 0)
                |> sideHelmet(2, 0)
                |> PixelCanvas.line(16, 9, 19, 2, steel())
                |> PixelCanvas.line(17, 9, 20, 2, steel())
                |> PixelCanvas.line(15, 9, 18, 2, edge())
                |> PixelCanvas.dot(15, 9, goldB())
                |> PixelCanvas.dot(16, 10, goldB())
                |> PixelCanvas.dot(13, 11, steelD())
                |> PixelCanvas.dot(14, 11, steelD())
                |> PixelCanvas.dot(14, 10, steel())
                |> PixelCanvas.dot(15, 10, steel())
        else if (f == 2)
            PixelCanvas.empty()
                |> attackLegsBrace
                |> sideMantle(1, 1, true)
                |> sideTorso(2, 1)
                |> sideHelmet(2, 1)
                |> PixelCanvas.line(16, 10, 22, 4, steel())
                |> PixelCanvas.line(17, 10, 23, 4, steel())
                |> PixelCanvas.line(16, 9, 22, 3, edge())
                |> PixelCanvas.dot(15, 10, goldB())
                |> PixelCanvas.dot(16, 11, goldB())
                |> PixelCanvas.dot(13, 12, steelD())
                |> PixelCanvas.dot(14, 12, steelD())
                |> PixelCanvas.dot(14, 11, steel())
                |> PixelCanvas.dot(15, 11, steel())
                |> PixelCanvas.dot(23, 3, flash())
        else if (f == 3)
            PixelCanvas.empty()
                |> PixelCanvas.line(16, 2, 10, 3, edge())
                |> PixelCanvas.line(10, 3, 5, 6, edge())
                |> PixelCanvas.line(5, 6, 3, 10, edge())
                |> PixelCanvas.line(16, 3, 10, 4, flash())
                |> PixelCanvas.line(10, 4, 5, 7, flash())
                |> PixelCanvas.line(5, 7, 3, 11, flash())
                |> PixelCanvas.line(16, 4, 10, 5, edge())
                |> PixelCanvas.line(10, 5, 5, 8, edge())
                |> PixelCanvas.line(5, 8, 3, 12, edge())
                |> attackLegsLunge
                |> sideMantle(0, 0, true)
                |> sideTorso(-2, 0)
                |> sideHelmet(-2, 0)
                |> PixelCanvas.line(7, 11, 2, 4, steel())
                |> PixelCanvas.line(8, 11, 3, 4, steel())
                |> PixelCanvas.line(7, 10, 2, 3, edge())
                |> PixelCanvas.dot(10, 11, goldB())
                |> PixelCanvas.dot(7, 13, goldB())
                |> PixelCanvas.dot(10, 12, steelD())
                |> PixelCanvas.dot(11, 12, steelD())
                |> PixelCanvas.dot(8, 12, steel())
                |> PixelCanvas.dot(9, 12, steel())
        else if (f == 4)
            PixelCanvas.empty()
                |> PixelCanvas.line(3, 7, 1, 14, edge())
                |> PixelCanvas.line(1, 14, 2, 20, edge())
                |> PixelCanvas.line(4, 7, 2, 14, flash())
                |> PixelCanvas.line(2, 14, 3, 20, flash())
                |> attackLegsLunge
                |> sideMantle(0, 1, true)
                |> sideTorso(-2, 1)
                |> sideHelmet(-2, 1)
                |> PixelCanvas.line(7, 15, 3, 25, steel())
                |> PixelCanvas.line(8, 15, 4, 25, steel())
                |> PixelCanvas.line(6, 14, 2, 24, edge())
                |> PixelCanvas.dot(10, 15, goldB())
                |> PixelCanvas.dot(7, 13, goldB())
                |> PixelCanvas.dot(10, 13, steelD())
                |> PixelCanvas.dot(11, 13, steelD())
                |> PixelCanvas.dot(8, 14, steel())
                |> PixelCanvas.dot(9, 14, steel())
                |> starAt(3, 27)
                |> PixelCanvas.dot(1, 24, goldB())
                |> PixelCanvas.dot(6, 27, goldB())
                |> PixelCanvas.dot(2, 28, goldB())
                |> PixelCanvas.dot(9, 28, steelD())
                |> PixelCanvas.dot(11, 28, steelD())
        else
            PixelCanvas.empty()
                |> attackLegsLunge
                |> sideMantle(0, 0, false)
                |> sideTorso(-2, 0)
                |> sideHelmet(-2, 0)
                |> PixelCanvas.line(7, 14, 3, 24, steel())
                |> PixelCanvas.line(8, 14, 4, 24, steel())
                |> PixelCanvas.line(6, 13, 2, 23, edge())
                |> PixelCanvas.dot(10, 14, goldB())
                |> PixelCanvas.dot(7, 12, goldB())
                |> PixelCanvas.dot(10, 12, steelD())
                |> PixelCanvas.dot(11, 12, steelD())
                |> PixelCanvas.dot(8, 13, steel())
                |> PixelCanvas.dot(9, 13, steel())
                |> PixelCanvas.dot(2, 26, goldB())
                |> PixelCanvas.dot(4, 28, steelD())
                |> PixelCanvas.dot(7, 28, steelD())

    // 頭上へ垂直に立てた大剣(正面)と、柄を握る両腕。
    def swordOverheadDown(dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.vline(17, 2 + dy, 7, edge())
           |> PixelCanvas.vline(18, 2 + dy, 7, steel())
           |> PixelCanvas.vline(19, 2 + dy, 7, steel())
           |> PixelCanvas.hline(16, 9 + dy, 5, goldB())
           |> PixelCanvas.dot(18, 10 + dy, hilt())
           |> PixelCanvas.dot(18, 11 + dy, hilt())
           |> PixelCanvas.dot(18, 12 + dy, goldB())
           |> PixelCanvas.dot(12, 12 + dy, steelD())
           |> PixelCanvas.dot(14, 11 + dy, steelD())
           |> PixelCanvas.dot(16, 11 + dy, steelD())
           |> PixelCanvas.dot(17, 10 + dy, steel())
           |> PixelCanvas.dot(19, 11 + dy, steel())

    // 眼前の地面に突き立った大剣(振り下ろしの着弾後)。体より後に重ねて描き、
    // 刃が手前にあることを示す。峰のハイライト列(edge)が鎧の上でも刃を読ませる。
    def swordPlantedFront(cv: Cv): Cv =
        cv |> PixelCanvas.vline(19, 15, 12, edge())
           |> PixelCanvas.vline(20, 15, 12, steel())
           |> PixelCanvas.vline(21, 15, 12, steel())
           |> PixelCanvas.dot(20, 27, steel())
           |> PixelCanvas.hline(18, 14, 5, goldB())
           |> PixelCanvas.dot(20, 12, hilt())
           |> PixelCanvas.dot(20, 13, hilt())
           |> PixelCanvas.dot(20, 11, goldB())
           |> PixelCanvas.dot(17, 12, steelD())
           |> PixelCanvas.dot(18, 13, steelD())
           |> PixelCanvas.dot(19, 13, steel())
           |> PixelCanvas.dot(21, 13, steel())

    // AttackDown: 担ぎ(f0) → 頭上へ立てる(f1) → 沈み込む溜め・切っ先が光る(f2)
    // → 体の右を大弧が走る振り下ろし(f3) → 眼前の地面へ着弾・衝撃の星(f4) → 残心(f5)。
    def attackDown(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty()
                |> frontLegsStand
                |> frontMantle(0, 0, false, false)
                |> frontTorso(0, 0)
                |> frontHelmet(0, 0)
                |> swordOnShoulderDown(0, 0)
                |> PixelCanvas.dot(11, 13, steelD())
                |> PixelCanvas.dot(12, 14, steelD())
                |> PixelCanvas.dot(13, 14, steel())
        else if (f == 1)
            PixelCanvas.empty()
                |> frontLegsStand
                |> frontMantle(0, 0, true, true)
                |> frontTorso(0, 0)
                |> frontHelmet(0, 0)
                |> swordOverheadDown(0)
        else if (f == 2)
            PixelCanvas.empty()
                |> frontLegsContact
                |> frontMantle(0, 1, true, true)
                |> frontTorso(0, 1)
                |> frontHelmet(0, 1)
                |> swordOverheadDown(1)
                |> PixelCanvas.dot(18, 2, flash())
                |> PixelCanvas.dot(20, 3, flash())
        else if (f == 3)
            PixelCanvas.empty()
                |> PixelCanvas.arc(16, 13, 12, -75, 60, edge())
                |> PixelCanvas.arc(16, 13, 11, -70, 55, flash())
                |> PixelCanvas.arc(16, 13, 10, -65, 50, edge())
                |> frontLegsContact
                |> frontMantle(-1, 1, true, false)
                |> frontTorso(-1, 1)
                |> frontHelmet(-1, 2)
                |> PixelCanvas.line(19, 14, 25, 24, steel())
                |> PixelCanvas.line(20, 14, 26, 24, steel())
                |> PixelCanvas.line(18, 15, 24, 25, edge())
                |> PixelCanvas.dot(18, 13, goldB())
                |> PixelCanvas.dot(19, 13, goldB())
                |> PixelCanvas.dot(17, 12, hilt())
                |> PixelCanvas.dot(16, 12, steel())
                |> PixelCanvas.dot(17, 13, steel())
                |> PixelCanvas.dot(14, 12, steelD())
                |> PixelCanvas.dot(15, 12, steelD())
        else if (f == 4)
            PixelCanvas.empty()
                |> frontLegsContact
                |> frontMantle(0, 1, true, true)
                |> frontTorso(0, 1)
                |> frontHelmet(0, 2)
                |> swordPlantedFront
                |> starAt(24, 26)
                |> PixelCanvas.dot(16, 27, flash())
                |> PixelCanvas.dot(14, 28, steelD())
                |> PixelCanvas.dot(25, 28, steelD())
        else
            PixelCanvas.empty()
                |> frontLegsContact
                |> frontMantle(0, 1, false, false)
                |> frontTorso(0, 1)
                |> frontHelmet(0, 1)
                |> swordPlantedFront

    // 頭上へ立てた大剣(背面・頭の左脇に見える)。
    def swordOverheadUp(dy: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.vline(10, 2 + dy, 7, edge())
           |> PixelCanvas.vline(11, 2 + dy, 7, steel())
           |> PixelCanvas.vline(12, 2 + dy, 7, steel())
           |> PixelCanvas.hline(9, 9 + dy, 5, goldB())
           |> PixelCanvas.dot(11, 10 + dy, steel())
           |> PixelCanvas.dot(12, 10 + dy, steel())

    // AttackUp: 肩の剣を頭上へ立て(f0-f1) → 沈む溜め(f2) → 肩越しの弧で奥へ振り抜く(f3)
    // → 奥の地面へ着弾(f4・刃は頭の上に峰だけ覗き、星が弾ける) → 残心(f5)。
    // 背面は腕がマントに隠れるので、剣の位置と頭越しの弧で振りを語る。
    def attackUp(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 0, 0)
                |> backMantleWrinkles(0, 0)
                |> swordOnShoulderUp(0, 0)
                |> PixelCanvas.dot(13, 12, steel())
                |> PixelCanvas.dot(14, 12, steel())
        else if (f == 1)
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 0, 0)
                |> backMantleWrinkles(0, 0)
                |> swordOverheadUp(0)
        else if (f == 2)
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 1, 0)
                |> backMantleWrinkles(0, 1)
                |> swordOverheadUp(1)
                |> PixelCanvas.dot(11, 2, flash())
        else if (f == 3)
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 0, 0)
                |> backMantleWrinkles(0, 0)
                |> PixelCanvas.arc(15, 9, 8, 20, 160, edge())
                |> PixelCanvas.arc(15, 9, 7, 30, 150, flash())
                |> PixelCanvas.vline(15, 2, 3, steel())
                |> PixelCanvas.vline(16, 2, 3, steel())
                |> PixelCanvas.dot(14, 2, edge())
                |> PixelCanvas.dot(13, 9, steel())
                |> PixelCanvas.dot(18, 9, steel())
        else if (f == 4)
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 1, 0)
                |> backMantleWrinkles(0, 1)
                |> PixelCanvas.dot(8, 21, crimson())
                |> PixelCanvas.dot(23, 21, crimson())
                |> PixelCanvas.vline(15, 3, 2, steel())
                |> PixelCanvas.vline(16, 3, 2, steel())
                |> starAt(16, 1)
                |> PixelCanvas.dot(13, 10, steel())
                |> PixelCanvas.dot(18, 10, steel())
        else
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 0, 0)
                |> backMantleWrinkles(0, 0)
                |> swordOnShoulderUp(1, 0)
                |> PixelCanvas.dot(14, 12, steel())
                |> PixelCanvas.dot(15, 12, steel())

    // UseItem 用: 大剣を背後(右)の地面に突き立てて両手を空ける。
    def plantedSwordBehind(cv: Cv): Cv =
        cv |> PixelCanvas.vline(23, 13, 14, steel())
           |> PixelCanvas.vline(24, 13, 14, edge())
           |> PixelCanvas.vline(25, 13, 14, steel())
           |> PixelCanvas.dot(24, 27, steel())
           |> PixelCanvas.hline(22, 12, 5, goldB())
           |> PixelCanvas.dot(24, 10, hilt())
           |> PixelCanvas.dot(24, 11, hilt())
           |> PixelCanvas.dot(23, 9, goldB())
           |> PixelCanvas.dot(24, 9, goldB())

    // 横向きの直立脚。
    def sideLegsStand(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 20, 2, 8, steelD())
           |> PixelCanvas.dot(12, 23, steel())
           |> PixelCanvas.dot(13, 23, steel())
           |> PixelCanvas.hline(10, 28, 3, steel())
           |> PixelCanvas.hline(10, 29, 3, steelD())
           |> PixelCanvas.rectFill(15, 20, 2, 8, steelD())
           |> PixelCanvas.dot(15, 23, steel())
           |> PixelCanvas.dot(16, 23, steel())
           |> PixelCanvas.hline(15, 28, 3, steel())
           |> PixelCanvas.hline(15, 29, 3, steelD())

    // 金の小瓶(2×2 の金 + 明部の照り)。
    def flaskAt(x: Int32, y: Int32, cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(x, y, 2, 2, goldD())
           |> PixelCanvas.dot(x + 1, y, goldB())

    // UseItem: 腰の小瓶へ手を伸ばす(f0) → 頭上へ掲げる(f1) → 白金のフラッシュ(f2)
    // → 兜へ傾けて呷る(f3)。大剣は背後に突き立てて常時見せる。
    def useItem(f: Int32): Cv =
        let base = PixelCanvas.empty()
            |> plantedSwordBehind
            |> sideLegsStand
            |> sideMantle(0, 0, false)
            |> sideTorso(0, 0);
        if (f == 0)
            base
                |> sideHelmet(0, 0)
                |> PixelCanvas.dot(11, 13, steelD())
                |> PixelCanvas.dot(11, 14, steelD())
                |> PixelCanvas.dot(10, 15, steelD())
                |> PixelCanvas.dot(10, 16, steel())
                |> PixelCanvas.dot(11, 16, steel())
                |> flaskAt(8, 15)
        else if (f == 1)
            base
                |> sideHelmet(0, 0)
                |> PixelCanvas.dot(12, 11, steelD())
                |> PixelCanvas.dot(13, 11, steelD())
                |> PixelCanvas.dot(11, 10, steelD())
                |> PixelCanvas.dot(12, 10, steelD())
                |> PixelCanvas.dot(11, 9, steelD())
                |> PixelCanvas.dot(10, 8, steel())
                |> PixelCanvas.dot(11, 8, steel())
                |> flaskAt(10, 5)
        else if (f == 2)
            base
                |> sideHelmet(0, 0)
                |> PixelCanvas.dot(12, 11, steelD())
                |> PixelCanvas.dot(13, 11, steelD())
                |> PixelCanvas.dot(11, 10, steelD())
                |> PixelCanvas.dot(12, 10, steelD())
                |> PixelCanvas.dot(11, 9, steelD())
                |> PixelCanvas.dot(10, 8, steel())
                |> PixelCanvas.dot(11, 8, steel())
                |> PixelCanvas.rectFill(10, 5, 2, 2, flash())
                |> PixelCanvas.dot(11, 2, flash())
                |> PixelCanvas.dot(7, 3, flash())
                |> PixelCanvas.dot(15, 3, flash())
                |> PixelCanvas.dot(6, 6, flash())
                |> PixelCanvas.dot(16, 6, flash())
                |> PixelCanvas.dot(9, 1, goldB())
                |> PixelCanvas.dot(13, 1, goldB())
                |> PixelCanvas.dot(5, 4, goldB())
                |> PixelCanvas.dot(17, 4, goldB())
        else
            base
                |> sideHelmet(1, -1)
                |> PixelCanvas.dot(11, 10, steelD())
                |> PixelCanvas.dot(11, 11, steelD())
                |> PixelCanvas.dot(12, 12, steelD())
                |> PixelCanvas.dot(10, 9, steel())
                |> PixelCanvas.dot(11, 9, steel())
                |> flaskAt(9, 7)
                |> PixelCanvas.dot(7, 4, goldB())

    // UseItemDown: 大剣は正面待機と同じく地に突き、左手は柄頭に置いたまま
    // 右手だけで小瓶を扱う。バイザーを跳ね上げて呷るが、開口部は影(iron)のままで
    // 顔は最後まで見せない。
    def useItemDown(f: Int32): Cv =
        let base = PixelCanvas.empty()
            |> frontLegsStand
            |> frontMantle(0, 0, false, false)
            |> frontTorso(0, 0)
            |> plantedSword
            |> PixelCanvas.hline(5, 9, 3, steel())
            |> PixelCanvas.dot(8, 10, steelD())
            |> PixelCanvas.dot(9, 10, steelD())
            |> PixelCanvas.dot(9, 11, steelD());
        if (f == 0)
            base
                |> frontHelmet(0, 0)
                |> PixelCanvas.vline(21, 13, 3, steelD())
                |> PixelCanvas.dot(21, 16, steel())
                |> PixelCanvas.dot(20, 17, steel())
                |> flaskAt(19, 17)
        else if (f == 1)
            base
                |> frontHelmet(0, 0)
                |> PixelCanvas.hline(13, 7, 6, steel())
                |> PixelCanvas.hline(14, 8, 4, iron())
                |> PixelCanvas.dot(20, 13, steelD())
                |> PixelCanvas.dot(21, 12, steelD())
                |> PixelCanvas.dot(21, 11, steel())
                |> flaskAt(20, 10)
        else if (f == 2)
            base
                |> frontHelmet(0, -1)
                |> PixelCanvas.hline(13, 6, 6, steel())
                |> PixelCanvas.hline(14, 7, 4, iron())
                |> PixelCanvas.dot(20, 11, steelD())
                |> PixelCanvas.dot(19, 10, steelD())
                |> PixelCanvas.dot(19, 9, steel())
                |> flaskAt(17, 6)
                |> PixelCanvas.dot(19, 5, flash())
        else
            base
                |> frontHelmet(0, 0)
                |> PixelCanvas.hline(13, 7, 6, steel())
                |> PixelCanvas.hline(14, 8, 4, iron())
                |> PixelCanvas.vline(21, 13, 3, steelD())
                |> PixelCanvas.dot(21, 16, steel())
                |> PixelCanvas.dot(13, 3, crimson())
                |> flaskAt(20, 15)

    // UseItemUp: 背面の一服。腕はマントに隠れるので、脇から出る右肘と
    // 頭の横に覗く小瓶の位置だけで飲む動きを語る。
    def useItemUp(f: Int32): Cv =
        let base = PixelCanvas.empty()
            |> upFeetStand
            |> backUpper(0, 0, 0)
            |> backMantleWrinkles(0, 0)
            |> swordOnShoulderUp(0, 0);
        if (f == 0)
            base
                |> PixelCanvas.dot(22, 15, steelD())
                |> PixelCanvas.dot(23, 15, steelD())
                |> PixelCanvas.dot(23, 16, steel())
        else if (f == 1)
            base
                |> PixelCanvas.dot(22, 12, steelD())
                |> PixelCanvas.dot(23, 12, steelD())
                |> PixelCanvas.dot(23, 11, steel())
                |> flaskAt(21, 8)
        else if (f == 2)
            base
                |> PixelCanvas.dot(22, 10, steelD())
                |> PixelCanvas.dot(22, 9, steelD())
                |> PixelCanvas.dot(21, 8, steel())
                |> flaskAt(19, 5)
                |> PixelCanvas.dot(17, 2, crimson())
                |> PixelCanvas.dot(21, 4, flash())
        else
            base
                |> PixelCanvas.dot(22, 14, steelD())
                |> PixelCanvas.dot(23, 14, steelD())
                |> PixelCanvas.dot(23, 15, steel())

    // Damage の芯: 巨体がのけぞり、大剣を持つ腕が後方へ跳ね上がる。
    def damageCore(cv: Cv): Cv =
        cv |> attackLegsBrace
           |> sideMantle(0, 0, true)
           |> sideTorso(1, 0)
           |> sideHelmet(2, 0)
           |> PixelCanvas.line(17, 9, 23, 3, steel())
           |> PixelCanvas.line(18, 9, 24, 3, steel())
           |> PixelCanvas.line(17, 8, 23, 2, edge())
           |> PixelCanvas.dot(16, 9, goldB())
           |> PixelCanvas.dot(17, 10, goldB())
           |> PixelCanvas.dot(14, 11, steelD())
           |> PixelCanvas.dot(15, 11, steelD())
           |> PixelCanvas.dot(15, 10, steel())
           |> PixelCanvas.dot(16, 10, steel())

    // Damage: f0=全身白フラッシュ + 2px ノックバック → f1=のけぞり + 3px + 衝撃星
    // → f2=頭を落として構え直す(2px)。巨体なので移動は小さく、光で衝撃を語る。
    def damage(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty() |> damageCore |> whiteOut |> PixelCanvas.shift(2, 0)
        else if (f == 1)
            PixelCanvas.empty()
                |> damageCore
                |> PixelCanvas.shift(3, 0)
                |> starAt(8, 13)
                |> PixelCanvas.dot(6, 15, flash())
        else
            PixelCanvas.empty()
                |> attackLegsBrace
                |> sideMantle(0, 0, false)
                |> sideTorso(0, 0)
                |> sideHelmet(1, 1)
                |> PixelCanvas.line(15, 11, 22, 6, steel())
                |> PixelCanvas.line(16, 11, 23, 6, steel())
                |> PixelCanvas.line(15, 10, 22, 5, edge())
                |> PixelCanvas.dot(14, 11, goldB())
                |> PixelCanvas.dot(14, 12, goldB())
                |> PixelCanvas.dot(13, 12, steel())
                |> PixelCanvas.dot(14, 13, steel())
                |> PixelCanvas.shift(2, 0)

    // DamageDown の芯: 頭がのけぞり、担いだ大剣が跳ね、左腕が跳ね上がる。
    def damageDownCore(cv: Cv): Cv =
        cv |> frontLegsStand
           |> frontMantle(0, 0, true, true)
           |> frontTorso(0, 0)
           |> frontHelmet(0, -1)
           |> swordOnShoulderDown(1, 1)
           |> PixelCanvas.dot(10, 13, steelD())
           |> PixelCanvas.dot(9, 12, steelD())
           |> PixelCanvas.dot(8, 12, steel())

    // DamageDown: f0=全身白フラッシュ + 2px ノックバック → f1=のけぞり + 3px + 衝撃星
    // → f2=頭を落として構え直す(1px)。横 Damage と対で、光と小さな移動で衝撃を語る。
    def damageDown(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty() |> damageDownCore |> whiteOut |> PixelCanvas.shift(-2, 0)
        else if (f == 1)
            PixelCanvas.empty()
                |> damageDownCore
                |> PixelCanvas.shift(-3, 0)
                |> starAt(4, 13)
                |> PixelCanvas.dot(2, 16, flash())
        else
            PixelCanvas.empty()
                |> frontLegsStand
                |> frontMantle(0, 0, false, false)
                |> frontTorso(0, 0)
                |> frontHelmet(0, 1)
                |> swordOnShoulderDown(0, 0)
                |> PixelCanvas.dot(11, 13, steelD())
                |> PixelCanvas.dot(11, 14, steelD())
                |> PixelCanvas.dot(11, 15, steel())
                |> PixelCanvas.shift(-1, 0)

    // DamageUp の芯: 肩の大剣が跳ね上がり、右肘がマントの外へ跳ねる。
    def damageUpCore(cv: Cv): Cv =
        cv |> upFeetStand
           |> backUpper(0, 0, 1)
           |> backMantleWrinkles(0, 0)
           |> swordOnShoulderUp(-1, -1)
           |> PixelCanvas.dot(23, 13, steelD())
           |> PixelCanvas.dot(24, 12, steelD())
           |> PixelCanvas.dot(24, 11, steel())

    // DamageUp: 背中(マント)に衝撃の星が走る。移動方向は DamageDown と逆にして
    // 前後どちらの被弾かを見分けやすくする。
    def damageUp(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty() |> damageUpCore |> whiteOut |> PixelCanvas.shift(2, 0)
        else if (f == 1)
            PixelCanvas.empty()
                |> damageUpCore
                |> PixelCanvas.shift(3, 0)
                |> starAt(19, 15)
                |> PixelCanvas.dot(22, 18, flash())
        else
            PixelCanvas.empty()
                |> upFeetStand
                |> backUpper(0, 1, 0)
                |> backMantleWrinkles(0, 1)
                |> swordOnShoulderUp(0, 1)
                |> PixelCanvas.shift(1, 0)

    // ══════════════ Death (正面向きの見せ場) ══════════════

    // 手を離れた大剣: 切っ先を支点に左へ傾き、地に刺さって止まっている。
    // f2 以降ずっとこの姿で残り、「主より先に戦いを終えた剣」を見せ続ける。
    def stuckSword(cv: Cv): Cv =
        cv |> PixelCanvas.line(6, 27, 2, 16, steel())
           |> PixelCanvas.line(7, 27, 3, 16, edge())
           |> PixelCanvas.line(8, 27, 4, 16, steel())
           |> PixelCanvas.hline(1, 15, 5, goldB())
           |> PixelCanvas.dot(2, 13, hilt())
           |> PixelCanvas.dot(2, 14, hilt())
           |> PixelCanvas.dot(1, 12, goldB())
           |> PixelCanvas.dot(6, 28, steel())

    // 膝立ちの脚: 太ももは立ったまま、膝から下が地に着く(足の裏は見せない)。
    def kneelLegs(cv: Cv): Cv =
        cv |> PixelCanvas.rectFill(12, 25, 3, 4, steelD())
           |> PixelCanvas.hline(12, 26, 3, steel())
           |> PixelCanvas.rectFill(17, 25, 3, 4, steelD())
           |> PixelCanvas.hline(17, 26, 3, steel())
           |> PixelCanvas.hline(12, 29, 3, steelD())
           |> PixelCanvas.hline(17, 29, 3, steelD())

    // Death: よろめき(f0-f1・支えの大剣が手を離れて地に刺さる) → 膝から崩れ(f2-f3)
    // → 膝立ちのまま前傾してがくりと果てる(f4-f5)。倒れ伏さず、最終コマも
    // 膝立ちの立面シルエットのまま終わる(この後は共通の Skeleton に差し替わる)。
    def death(f: Int32): Cv =
        if (f == 0)
            PixelCanvas.empty()
                |> frontLegsStand
                |> frontMantle(1, 0, false, true)
                |> frontTorso(1, 0)
                |> frontHelmet(2, 0)
                |> plantedSword
                |> PixelCanvas.vline(9, 12, 4, steelD())
                |> PixelCanvas.dot(9, 16, steel())
                |> PixelCanvas.vline(22, 13, 4, steelD())
                |> PixelCanvas.dot(22, 17, steel())
        else if (f == 1)
            PixelCanvas.empty()
                |> frontLegsStand
                |> frontMantle(-1, 1, true, false)
                |> frontTorso(-1, 1)
                |> frontHelmet(-2, 2)
                |> PixelCanvas.line(6, 27, 3, 15, steel())
                |> PixelCanvas.line(7, 27, 4, 15, edge())
                |> PixelCanvas.line(8, 27, 5, 15, steel())
                |> PixelCanvas.hline(2, 14, 5, goldB())
                |> PixelCanvas.dot(3, 12, hilt())
                |> PixelCanvas.dot(3, 13, hilt())
                |> PixelCanvas.dot(2, 11, goldB())
                |> PixelCanvas.dot(8, 14, steelD())
                |> PixelCanvas.dot(9, 14, steelD())
                |> PixelCanvas.dot(8, 13, steel())
                |> PixelCanvas.vline(21, 14, 4, steelD())
                |> PixelCanvas.dot(21, 18, steel())
        else if (f == 2)
            PixelCanvas.empty()
                |> stuckSword
                |> PixelCanvas.dot(4, 28, steelD())
                |> PixelCanvas.dot(10, 28, steelD())
                |> PixelCanvas.rectFill(12, 23, 3, 5, steelD())
                |> PixelCanvas.hline(12, 25, 3, steel())
                |> PixelCanvas.rectFill(17, 23, 3, 5, steelD())
                |> PixelCanvas.hline(17, 25, 3, steel())
                |> PixelCanvas.hline(11, 28, 4, steel())
                |> PixelCanvas.hline(11, 29, 4, steelD())
                |> PixelCanvas.hline(17, 28, 4, steel())
                |> PixelCanvas.hline(17, 29, 4, steelD())
                |> frontMantle(0, 3, false, false)
                |> frontTorso(0, 3)
                |> frontHelmet(-1, 4)
                |> PixelCanvas.dot(10, 17, steelD())
                |> PixelCanvas.dot(9, 18, steelD())
                |> PixelCanvas.dot(9, 19, steel())
                |> PixelCanvas.dot(21, 17, steelD())
                |> PixelCanvas.dot(22, 18, steelD())
                |> PixelCanvas.dot(22, 19, steel())
        else if (f == 3)
            PixelCanvas.empty()
                |> stuckSword
                |> kneelLegs
                |> frontMantle(0, 5, true, true)
                |> frontTorso(0, 5)
                |> frontHelmet(0, 6)
                |> PixelCanvas.dot(9, 28, steelD())
                |> PixelCanvas.dot(23, 28, steelD())
                |> PixelCanvas.vline(10, 17, 4, steelD())
                |> PixelCanvas.dot(10, 21, steel())
                |> PixelCanvas.vline(21, 17, 4, steelD())
                |> PixelCanvas.dot(21, 21, steel())
        else if (f == 4)
            PixelCanvas.empty()
                |> stuckSword
                |> kneelLegs
                |> frontMantle(0, 5, false, true)
                |> frontTorso(0, 5)
                |> frontHelmet(-1, 8)
                |> PixelCanvas.vline(10, 18, 4, steelD())
                |> PixelCanvas.dot(10, 22, steel())
                |> PixelCanvas.vline(21, 18, 4, steelD())
                |> PixelCanvas.dot(21, 22, steel())
        else
            PixelCanvas.empty()
                |> stuckSword
                |> kneelLegs
                |> frontMantle(0, 6, true, false)
                |> frontTorso(0, 6)
                |> frontHelmet(-1, 10)
                |> PixelCanvas.vline(10, 19, 4, steelD())
                |> PixelCanvas.dot(10, 23, steel())
                |> PixelCanvas.vline(21, 19, 4, steelD())
                |> PixelCanvas.dot(21, 23, steel())
}
