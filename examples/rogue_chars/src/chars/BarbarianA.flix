// BarbarianA — 上半身裸の大男。日焼けした筋肉・毛皮の腰巻・両刃の大斧。
// スキンヘッドに頭皮の戦傷（赤い刻み）が個性。動きのテーマは「質量」:
// 深い胸呼吸(2px)・肩を揺らすのしのし歩き・大上段からの叩き割り・地響きの死。
mod BarbarianA {

    use PixelCanvas.{Canvas, dot, hline, vline, rectFill, line, shift}

    pub def name(): String = "BARBARIAN A 質量で叩き割る禿頭の大斧使い"

    // ── 色（肌2階調+毛皮+鋼2階調+傷）──
    def sk(): Color = RoguePalette.tan()        // 日焼け肌・明
    def skD(): Color = RoguePalette.brown()     // 肌の影
    def fur(): Color = RoguePalette.darkBrown() // 毛皮・ブーツ
    def wood(): Color = RoguePalette.brown()    // 斧の柄（肌影と同色を兼用し6色に収める）
    def steel(): Color = RoguePalette.silver()  // 斧の刃
    def steelHi(): Color = RoguePalette.paleBlue() // 刃のハイライト
    def scarC(): Color = RoguePalette.red()     // 頭皮の戦傷
    def eyeC(): Color = RoguePalette.plum()     // 目

    // ── frame の丸め（負数も安全に 0..n-1 へ）──
    def wrapFrame(frame: Int32, n: Int32): Int32 =
        let r = Int32.remainder(frame, n);
        if (r < 0) r + n else r

    // 被弾フラッシュ用: 全ドットを白に置き換える
    def whiten(cv: Canvas): Canvas = Map.map(_ -> RoguePalette.white(), cv)

    // ── 斧（共通部品）──

    // 両刃の斧頭。中心 (cx,cy) の左右に刃が張り出す。幅3px+外縁1pxハイライト。
    def axeHead(cx: Int32, cy: Int32, cv: Canvas): Canvas =
        cv |> hline(cx - 2, cy - 2, 2, steel()) |> hline(cx + 1, cy - 2, 2, steel())
           |> hline(cx - 3, cy - 1, 3, steel()) |> hline(cx + 1, cy - 1, 3, steel())
           |> hline(cx - 3, cy,     3, steel()) |> hline(cx + 1, cy,     3, steel())
           |> hline(cx - 2, cy + 1, 2, steel()) |> hline(cx + 1, cy + 1, 2, steel())
           |> vline(cx - 3, cy - 1, 2, steelHi()) |> vline(cx + 3, cy - 1, 2, steelHi())

    // 直立持ちの斧。柄は x=hx の縦線、斧頭は柄の上部。
    def axeUpright(hx: Int32, top: Int32, bot: Int32, cv: Canvas): Canvas =
        cv |> vline(hx, top, bot - top + 1, wood())
           |> dot(hx, bot, fur())
           |> axeHead(hx, top + 3)

    // 地面に転がった斧（Death 用）。柄が横倒し・斧頭は右端。
    def axeGround(cv: Canvas): Canvas =
        cv |> hline(20, 27, 6, wood())
           |> hline(26, 25, 2, steel())
           |> hline(26, 26, 3, steel())
           |> hline(25, 27, 4, steel())
           |> hline(26, 28, 3, steel())
           |> hline(26, 29, 2, steel())
           |> vline(28, 26, 3, steelHi())

    // ── 正面パーツ ──

    // 正面の脚1本（幅3px）。lift 分だけ足が地面から浮く。下3行は毛皮ブーツ。
    def legFront(x: Int32, lift: Int32, cv: Canvas): Canvas =
        cv |> rectFill(x, 22, 3, 5 - lift, sk())
           |> rectFill(x, 27 - lift, 3, 3, fur())

    // 毛皮の腰巻（ベルト+房飾り）。腰は揺れない固定位置。
    def loinclothFront(cv: Canvas): Canvas =
        cv |> rectFill(11, 18, 10, 4, fur())
           |> hline(11, 18, 10, wood())
           |> dot(13, 20, wood()) |> dot(17, 21, wood()) |> dot(19, 20, wood())

    // 正面の胴。b=呼吸/上下動(負で持ち上がる・胴の底は y=17 固定)、s=肩の左右揺れ。
    // wide=true で胸郭が1px 張り出す（深呼吸の頂点）。
    def torsoFront(b: Int32, s: Int32, wide: Bool, cv: Canvas): Canvas =
        let c1 = cv |> hline(10 + s, 10 + b, 12, sk())
                    |> rectFill(11 + s, 11 + b, 10, 7 - b, sk())
                    |> vline(11 + s, 11 + b, 7 - b, skD())
                    |> hline(13 + s, 13 + b, 2, skD()) |> hline(17 + s, 13 + b, 2, skD())
                    |> dot(15 + s, 15 + b, skD()) |> dot(16 + s, 16, skD());
        if (wide)
            c1 |> vline(10 + s, 12 + b, 3, sk()) |> vline(21 + s, 12 + b, 3, sk())
        else
            c1

    // 正面の頭。スキンヘッド+頭皮の戦傷（赤の斜め3px）+眉影と顎影。
    def headFront(b: Int32, s: Int32, cv: Canvas): Canvas =
        cv |> rectFill(13 + s, 4 + b, 6, 6, sk())
           |> dot(14 + s, 5 + b, scarC()) |> dot(15 + s, 4 + b, scarC()) |> dot(16 + s, 4 + b, scarC())
           |> dot(14 + s, 6 + b, skD()) |> dot(17 + s, 6 + b, skD())
           |> dot(14 + s, 7 + b, eyeC()) |> dot(17 + s, 7 + b, eyeC())
           |> dot(13 + s, 8 + b, skD()) |> dot(18 + s, 8 + b, skD())
           |> hline(14 + s, 9 + b, 4, skD())

    // 正面・左腕（画面左）。だらりと下げた基本形。
    def leftArmIdle(b: Int32, s: Int32, cv: Canvas): Canvas =
        cv |> rectFill(9 + s, 11 + b, 2, 6, sk())
           |> hline(9 + s, 17 + b, 2, skD())

    // 正面・右腕+直立斧+握り拳。斧は常に見える主役。
    def rightArmAxe(b: Int32, s: Int32, cv: Canvas): Canvas =
        cv |> rectFill(21 + s, 11 + b, 2, 4, sk())
           |> dot(22 + s, 15 + b, sk())
           |> axeUpright(23 + s, 6 + b, 20 + b)
           |> dot(22 + s, 15 + b, sk()) |> dot(23 + s, 15 + b, sk()) |> dot(23 + s, 16 + b, sk())

    // 正面の素体（脚→腰巻→胴→頭）。腕と斧は呼び側が足す。
    def frontCore(b: Int32, s: Int32, lLift: Int32, rLift: Int32, wide: Bool, cv: Canvas): Canvas =
        cv |> legFront(12, lLift)
           |> legFront(17, rLift)
           |> loinclothFront
           |> torsoFront(b, s, wide)
           |> headFront(b, s)

    // 正面フル（Idle/WalkDown 共用）
    def frontBase(b: Int32, s: Int32, lLift: Int32, rLift: Int32, wide: Bool): Canvas =
        PixelCanvas.empty()
            |> frontCore(b, s, lLift, rLift, wide)
            |> leftArmIdle(b, s)
            |> rightArmAxe(b, s)

    // ── Idle: 胸全体の深い呼吸（上半身が 0→-1→-2→-1 と持ち上がり、頂点で胸郭が張る）──
    def idle(f: Int32): Canvas = match f {
        case 0 => frontBase(0, 0, 0, 0, false)
        case 1 => frontBase(-1, 0, 0, 0, false)
        case 2 => frontBase(-2, 0, 0, 0, true)
        case _ => frontBase(-1, 0, 0, 0, false)
    }

    // ── WalkDown: のしのし歩き。足踏み2px+体の上下動1px+肩の左右揺れ1px ──
    def walkDown(f: Int32): Canvas = match f {
        case 0 => frontBase(0, -1, 2, 0, false)   // 左足を上げ肩は左へ
        case 1 => frontBase(-1, 0, 1, 1, false)   // 通過姿勢・体が浮く
        case 2 => frontBase(0, 1, 0, 2, false)    // 右足を上げ肩は右へ
        case _ => frontBase(-1, 0, 0, 0, false)   // 両足接地で沈み込み
    }

    // ── 背面パーツ（WalkUp 用）──

    // 背面の頭。顔なし・後頭部にも戦傷が見える・うなじ影。
    def headBack(b: Int32, s: Int32, cv: Canvas): Canvas =
        cv |> rectFill(13 + s, 4 + b, 6, 6, sk())
           |> dot(15 + s, 4 + b, scarC()) |> dot(16 + s, 5 + b, scarC())
           |> hline(14 + s, 9 + b, 4, skD())

    // 背面の胴。胸筋の代わりに背骨の縦影と肩甲骨。
    def torsoBack(b: Int32, s: Int32, cv: Canvas): Canvas =
        cv |> hline(10 + s, 10 + b, 12, sk())
           |> rectFill(11 + s, 11 + b, 10, 7 - b, sk())
           |> vline(20 + s, 11 + b, 7 - b, skD())
           |> vline(16 + s, 11 + b, 5, skD())
           |> dot(13 + s, 12 + b, skD()) |> dot(18 + s, 12 + b, skD())

    // 背面フル。右手の斧は背面では画面左側に映る（鏡映）。
    def backBase(b: Int32, s: Int32, lLift: Int32, rLift: Int32): Canvas =
        PixelCanvas.empty()
            |> legFront(12, lLift)
            |> legFront(17, rLift)
            |> loinclothFront
            |> torsoBack(b, s)
            |> headBack(b, s)
            |> rectFill(21 + s, 11 + b, 2, 6, sk())
            |> hline(21 + s, 17 + b, 2, skD())
            |> rectFill(9 + s, 11 + b, 2, 4, sk())
            |> axeUpright(8 + s, 6 + b, 20 + b)
            |> dot(8 + s, 15 + b, sk()) |> dot(9 + s, 15 + b, sk()) |> dot(8 + s, 16 + b, sk())

    // ── WalkUp: 背面ののしのし歩き（WalkDown と同じ振り付け）──
    def walkUp(f: Int32): Canvas = match f {
        case 0 => backBase(0, -1, 2, 0)
        case 1 => backBase(-1, 0, 1, 1)
        case 2 => backBase(0, 1, 0, 2)
        case _ => backBase(-1, 0, 0, 0)
    }

    // ── 横向きパーツ（左向き作画）──

    // 横向きの脚1本。腰 (hipX, 22) から足 (footX, 26) へ斜めに伸ばし、下3行はブーツ。
    def legSideAt(hipX: Int32, footX: Int32, c: Color, cv: Canvas): Canvas =
        cv |> line(hipX, 22, footX, 26, c)
           |> line(hipX + 1, 22, footX + 1, 26, c)
           |> rectFill(footX, 27, 2, 3, fur())

    // 横向きの胴+頭+奥腕。dxT=胴の前後傾き、dxH=頭の前後傾き（前=負）。
    def sideTrunk(b: Int32, dxT: Int32, dxH: Int32, cv: Canvas): Canvas =
        cv |> rectFill(13 + dxT, 11 + b, 6, 7 - b, sk())
           |> vline(18 + dxT, 11 + b, 7 - b, skD())
           |> dot(12 + dxT, 12 + b, sk()) |> dot(12 + dxT, 13 + b, sk())
           |> rectFill(12 + dxH, 4 + b, 6, 6, sk())
           |> dot(14 + dxH, 4 + b, scarC()) |> dot(15 + dxH, 5 + b, scarC())
           |> dot(13 + dxH, 7 + b, eyeC())
           |> dot(12 + dxH, 8 + b, skD())
           |> hline(13 + dxH, 9 + b, 4, skD())
           |> rectFill(17 + dxT, 11 + b, 2, 4, skD())

    // 横向きの腰巻。
    def loinclothSide(cv: Canvas): Canvas =
        cv |> rectFill(13, 18, 6, 4, fur())
           |> hline(13, 18, 6, wood())
           |> dot(15, 20, wood()) |> dot(17, 21, wood())

    // 横向きフル。奥脚は影色・手前脚は明色で前後を描き分ける。
    // 斧は体の前（画面左）に直立で構え、刃の後列は頭の陰に隠れる（斧→頭の順に描く）。
    def sideBase(b: Int32, dxH: Int32, nearFootX: Int32, farFootX: Int32): Canvas =
        PixelCanvas.empty()
            |> legSideAt(16, farFootX, skD())
            |> legSideAt(14, nearFootX, sk())
            |> loinclothSide
            |> axeUpright(9, 5 + b, 20 + b)
            |> sideTrunk(b, 0, dxH)
            |> line(14, 11 + b, 10, 14 + b, sk())
            |> line(15, 12 + b, 11, 15 + b, sk())
            |> dot(9, 15 + b, sk()) |> dot(10, 15 + b, sk())

    // ── WalkSide: 歩幅の大きい踏み込み（足の前後差 最大7px）+ 上下動1px ──
    def walkSide(f: Int32): Canvas = match f {
        case 0 => sideBase(0, 0, 11, 18)    // 手前脚が前・奥脚が後ろ
        case 1 => sideBase(-1, 0, 14, 16)   // 通過姿勢・体が浮く
        case 2 => sideBase(0, 0, 18, 11)    // 脚が入れ替わる
        case _ => sideBase(-1, 0, 16, 13)   // もう一つの通過姿勢
    }

    // ── Attack 用の小道具 ──

    // 衝撃の星（黄の十字+白芯）
    def starAt(cx: Int32, cy: Int32, cv: Canvas): Canvas =
        cv |> dot(cx, cy - 1, RoguePalette.yellow()) |> dot(cx - 1, cy, RoguePalette.yellow())
           |> dot(cx + 1, cy, RoguePalette.yellow()) |> dot(cx, cy + 1, RoguePalette.yellow())
           |> dot(cx, cy, RoguePalette.white())

    // 頭上から地面まで振り抜いた斬撃の軌跡（外周=淡青2px+内側=白芯で幅2〜3px）
    def slashArc(cv: Canvas): Canvas =
        cv |> dot(15, 2, steelHi()) |> dot(12, 3, steelHi()) |> dot(9, 4, steelHi())
           |> dot(6, 6, steelHi()) |> dot(4, 9, steelHi()) |> dot(3, 12, steelHi())
           |> dot(2, 16, steelHi()) |> dot(2, 20, steelHi())
           |> dot(16, 3, steelHi()) |> dot(13, 4, steelHi()) |> dot(10, 5, steelHi())
           |> dot(7, 7, steelHi()) |> dot(5, 10, steelHi()) |> dot(4, 13, steelHi())
           |> dot(3, 17, steelHi()) |> dot(3, 21, steelHi())
           |> dot(14, 3, RoguePalette.white()) |> dot(11, 4, RoguePalette.white())
           |> dot(8, 5, RoguePalette.white()) |> dot(5, 8, RoguePalette.white())
           |> dot(3, 13, RoguePalette.white()) |> dot(2, 18, RoguePalette.white())

    // ── Attack: 引き溜め→大上段→振り下ろし→着弾（軌跡）→衝撃（星+土煙）→戻し ──
    def attack(f: Int32): Canvas = match f {
        case 0 =>
            // 引き溜め: 体を後ろに傾け、斧を背中側の低い位置へ引く
            PixelCanvas.empty()
                |> legSideAt(16, 18, skD()) |> legSideAt(14, 11, sk())
                |> line(12, 16, 20, 9, wood()) |> line(13, 16, 21, 9, wood())
                |> axeHead(21, 5)
                |> loinclothSide
                |> sideTrunk(1, 1, 2)
                |> line(15, 13, 13, 16, sk()) |> line(16, 13, 14, 16, sk())
                |> dot(12, 16, sk()) |> dot(13, 16, sk())
        case 1 =>
            // 大上段: 体は沈んで力を溜め、斧が頭より高く掲げられる
            PixelCanvas.empty()
                |> legSideAt(16, 17, skD()) |> legSideAt(14, 12, sk())
                |> loinclothSide
                |> sideTrunk(1, 1, 2)
                |> axeHead(14, 4)
                |> vline(14, 6, 4, wood())
                |> line(18, 12, 16, 9, skD())
                |> line(13, 12, 14, 9, sk()) |> line(14, 12, 15, 9, sk())
                |> dot(13, 9, sk()) |> dot(14, 9, sk()) |> dot(15, 8, sk())
        case 2 =>
            // 振り下ろし中: 前傾が始まり、斧が前方高くへ。軌跡が出始める
            PixelCanvas.empty()
                |> legSideAt(14, 10, sk()) |> legSideAt(16, 18, skD())
                |> loinclothSide
                |> sideTrunk(0, -1, -2)
                |> line(6, 9, 12, 13, wood()) |> line(7, 9, 13, 13, wood())
                |> axeHead(5, 7)
                |> line(13, 11, 11, 12, sk()) |> line(14, 12, 12, 13, sk())
                |> dot(11, 12, sk()) |> dot(12, 13, sk())
                |> dot(13, 2, steelHi()) |> dot(11, 3, steelHi()) |> dot(9, 4, steelHi())
                |> dot(12, 2, RoguePalette.white()) |> dot(10, 3, RoguePalette.white())
        case 3 =>
            // 着弾: 全身が前へ折れ、斧が地面へ。頭上から地面までの大きな軌跡
            PixelCanvas.empty()
                |> legSideAt(14, 10, sk()) |> legSideAt(16, 18, skD())
                |> loinclothSide
                |> sideTrunk(1, -2, -3)
                |> line(5, 24, 11, 15, wood()) |> line(6, 24, 12, 16, wood())
                |> axeHead(4, 26)
                |> line(12, 12, 11, 14, sk()) |> line(13, 13, 12, 15, sk())
                |> dot(11, 15, sk()) |> dot(12, 16, sk())
                |> slashArc
        case 4 =>
            // 衝撃: 軌跡は消え、着弾点に星2つ+土煙が立つ
            PixelCanvas.empty()
                |> legSideAt(14, 10, sk()) |> legSideAt(16, 18, skD())
                |> loinclothSide
                |> sideTrunk(0, -2, -3)
                |> line(5, 24, 11, 15, wood()) |> line(6, 24, 12, 16, wood())
                |> axeHead(4, 26)
                |> line(12, 11, 11, 13, sk()) |> line(13, 12, 12, 14, sk())
                |> dot(11, 15, sk()) |> dot(12, 16, sk())
                |> starAt(3, 21) |> starAt(9, 23)
                |> dot(2, 28, RoguePalette.gray()) |> dot(5, 29, RoguePalette.gray())
                |> dot(8, 28, RoguePalette.gray()) |> dot(10, 29, RoguePalette.darkGray())
                |> dot(4, 28, RoguePalette.darkGray())
        case _ =>
            // 戻し: 斧を引き上げ、土煙の名残だけが残る
            PixelCanvas.empty()
                |> legSideAt(14, 11, sk()) |> legSideAt(16, 18, skD())
                |> loinclothSide
                |> sideTrunk(0, -1, -1)
                |> line(7, 16, 13, 15, wood()) |> line(7, 17, 13, 16, wood())
                |> axeHead(6, 14)
                |> line(13, 11, 12, 13, sk()) |> line(14, 12, 13, 14, sk())
                |> dot(12, 15, sk()) |> dot(13, 16, sk())
                |> dot(4, 29, RoguePalette.darkGray()) |> dot(7, 28, RoguePalette.darkGray())
    }

    // 小瓶（薬）。2×3 の赤い瓶+左上に光沢。
    def flaskAt(x: Int32, y: Int32, cv: Canvas): Canvas =
        cv |> rectFill(x, y, 2, 3, RoguePalette.salmon())
           |> dot(x, y, steelHi())

    // ── UseItem: 胸元の薬→頭上へ掲げ→白いフラッシュ→呷る ──
    def useItem(f: Int32): Canvas =
        let base = PixelCanvas.empty()
            |> frontCore(0, 0, 0, 0, false)
            |> rightArmAxe(0, 0);
        match f {
            case 0 =>
                // 胸元に構える
                base |> rectFill(9, 11, 2, 3, sk()) |> dot(10, 14, sk())
                     |> flaskAt(8, 12)
            case 1 =>
                // 頭上へ掲げる
                base |> vline(9, 7, 5, sk()) |> vline(10, 7, 5, sk())
                     |> flaskAt(9, 4)
            case 2 =>
                // フラッシュ: 瓶が白く光り、黄の光が飛ぶ
                base |> vline(9, 7, 5, sk()) |> vline(10, 7, 5, sk())
                     |> rectFill(9, 4, 2, 3, RoguePalette.white())
                     |> dot(9, 2, RoguePalette.yellow()) |> dot(12, 4, RoguePalette.yellow())
                     |> dot(6, 4, RoguePalette.yellow()) |> dot(7, 2, RoguePalette.yellow())
                     |> dot(12, 7, RoguePalette.yellow()) |> dot(6, 7, RoguePalette.white())
            case _ =>
                // 呷る: 瓶が口元へ、顎が上がる
                base |> line(9, 11, 11, 8, sk()) |> line(10, 11, 12, 8, sk())
                     |> flaskAt(12, 6)
                     |> dot(14, 9, sk()) |> dot(15, 9, sk())
        }

    // ── Damage: 白シルエット+ノックバック2px → のけぞり3px → 立て直し ──
    def damage(f: Int32): Canvas = match f {
        case 0 => whiten(shift(2, 0, sideBase(0, 0, 13, 17)))
        case 1 => shift(3, 0, sideBase(1, 2, 12, 18))
                      |> dot(8, 11, RoguePalette.white()) |> dot(7, 14, RoguePalette.white())
        case _ => shift(1, 0, sideBase(1, 0, 13, 17))
    }

    // ── Death 用パーツ ──

    // 膝立ちポーズ。hy=頭の上端、ty=肩の行。bow=true で顔を伏せ後頭部を見せる。
    def kneelPose(hy: Int32, ty: Int32, bow: Bool, cv: Canvas): Canvas =
        let c1 = cv |> hline(10, ty, 12, sk())
                    |> rectFill(11, ty + 1, 10, 22 - ty, sk())
                    |> vline(11, ty + 1, 22 - ty, skD())
                    |> rectFill(11, 22, 10, 3, fur())
                    |> hline(11, 22, 10, wood())
                    |> rectFill(11, 25, 3, 3, sk()) |> rectFill(10, 28, 3, 2, fur())
                    |> rectFill(17, 25, 3, 3, sk()) |> rectFill(18, 28, 3, 2, fur())
                    |> rectFill(9, ty + 1, 2, 6, sk())
                    |> rectFill(21, ty + 1, 2, 6, sk());
        if (bow)
            c1 |> rectFill(12, hy, 6, 6, sk())
               |> hline(13, hy + 5, 4, skD())
               |> dot(13, hy + 1, scarC()) |> dot(14, hy, scarC()) |> dot(15, hy, scarC())
        else
            c1 |> rectFill(13, hy, 6, 6, sk())
               |> dot(14, hy + 1, scarC()) |> dot(15, hy, scarC()) |> dot(16, hy, scarC())
               |> dot(14, hy + 3, eyeC()) |> dot(17, hy + 3, eyeC())
               |> hline(14, hy + 5, 4, skD())

    // うつ伏せの遺体。dy で浮かせてバウンドを作る。spread=true で腕脚が大の字。
    def corpse(dy: Int32, spread: Bool, cv: Canvas): Canvas =
        let c1 = cv |> rectFill(12, 26 + dy, 8, 2, sk())
                    |> hline(12, 28 + dy, 8, fur());
        let c2 = if (spread)
            c1 |> hline(6, 27 + dy, 6, sk()) |> dot(6, 27 + dy, skD())
               |> hline(20, 27 + dy, 4, sk()) |> dot(23, 27 + dy, skD())
               |> hline(10, 29 + dy, 4, sk()) |> hline(18, 29 + dy, 4, sk())
               |> hline(8, 29 + dy, 2, fur()) |> hline(22, 29 + dy, 2, fur())
        else
            c1 |> hline(9, 27 + dy, 3, sk()) |> hline(20, 27 + dy, 3, sk())
               |> hline(12, 29 + dy, 3, sk()) |> hline(17, 29 + dy, 3, sk())
               |> dot(11, 29 + dy, fur()) |> dot(20, 29 + dy, fur());
        c2 |> rectFill(14, 23 + dy, 4, 3, sk())
           |> hline(14, 25 + dy, 4, skD())
           |> dot(15, 23 + dy, scarC()) |> dot(16, 24 + dy, scarC())

    // ── Death: よろめき→斧を取り落とす→膝→伏せ→地響きの落下(星+土煙)→バウンド→静止 ──
    // 正面（カメラ向き）で見せる。落ちた斧は f1 以降ずっと足元右に転がったまま。
    def death(f: Int32): Canvas = match f {
        case 0 =>
            // よろめき: 体が右へ傾ぎ、握った斧も傾く
            PixelCanvas.empty()
                |> frontCore(0, 1, 0, 0, false)
                |> leftArmIdle(0, 1)
                |> rectFill(22, 11, 2, 4, sk())
                |> line(23, 9, 25, 19, wood())
                |> axeHead(23, 7)
                |> dot(23, 15, sk()) |> dot(24, 15, sk())
        case 1 =>
            // 斧を取り落とし、両腕を横に泳がせてバランスを失う
            PixelCanvas.empty()
                |> axeGround
                |> frontCore(0, -1, 0, 0, false)
                |> rectFill(6, 12, 4, 2, sk())
                |> rectFill(20, 12, 4, 2, sk())
        case 2 =>
            // 膝から崩れる
            PixelCanvas.empty() |> axeGround |> kneelPose(8, 14, false)
        case 3 =>
            // さらに沈み、顔を伏せる
            PixelCanvas.empty() |> axeGround |> kneelPose(11, 16, true)
        case 4 =>
            // 前のめりに倒れ込み、地響き: 星+土煙が舞う
            PixelCanvas.empty()
                |> axeGround
                |> corpse(0, false)
                |> starAt(6, 24)
                |> dot(7, 27, RoguePalette.gray()) |> dot(5, 29, RoguePalette.gray())
                |> dot(9, 25, RoguePalette.gray()) |> dot(3, 28, RoguePalette.gray())
                |> dot(4, 27, RoguePalette.darkGray()) |> dot(10, 29, RoguePalette.darkGray())
        case 5 =>
            // 衝撃で体が2px 跳ね上がる（バウンド）
            PixelCanvas.empty()
                |> axeGround
                |> corpse(-2, false)
                |> dot(8, 29, RoguePalette.gray()) |> dot(22, 29, RoguePalette.gray())
        case 6 =>
            // 大の字に落ち着く。土煙の名残
            PixelCanvas.empty()
                |> axeGround
                |> corpse(0, true)
                |> dot(7, 28, RoguePalette.darkGray()) |> dot(4, 29, RoguePalette.darkGray())
        case _ =>
            // 静止した遺体。傍らに斧
            PixelCanvas.empty() |> axeGround |> corpse(0, true)
    }

    // ── 入口: クリップと frame からキャンバスを返す ──
    // v3 契約の暫定マイグレーション: 方向別（Down/Up/Side）は当面同じ絵を返す。
    // 方向ごとの本作画は次の改稿ラウンドで行う。
    pub def draw(clip: RogueStage.Clip, frame: Int32): PixelCanvas.Canvas =
        let f = wrapFrame(frame, RogueStage.frameCount(clip));
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
}
