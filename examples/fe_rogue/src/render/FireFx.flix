/// FireFx — 魔法の炎が着弾して燃え上がる一発演出（閃光 → 炎の舌が立ち上る → 火の粉）。
///
/// どの粒もどこにも保存されない: 絵ぜんぶが (見た目の指定 Spec, 発生指定 Burst, 着弾からの
/// 経過秒 t) の純粋な導出で、spawn も update も消去も要らない。描きたいフレームで `quads` を
/// 呼んで polygon 列に混ぜるだけ。`seed` に発生ごとの通し番号を渡すと、撃つたびに炎の表情が
/// 変わる（同じ seed なら同じ絵なので、巻き戻し・リプレイでも揺れない）。
///
/// 見た目は Spec のプリセットから選ぶ: standard（焚き火型）/ pillar（火柱）/ flare（爆炎）/
/// smolder（残り火）/ arcane（蒼炎）/ droplet（雫）/ fireball（火の玉）/ sidestream（横流れ）/
/// vortex（渦巻き）/ sparkler（線香花火）。
mod FireFx {

    /// 舌のシルエットの形。Kite = 上に尖った菱形（焚き火の舌）/ Drop = 上の尖り 1 頂点＋
    /// 下半分が半円の雫（ろうそく・鬼火の柔らかさ）。
    pub enum TongueShape with Eq {
        case Kite
        case Drop
    }

    /// 発生指定。
    /// center = 着弾のワールド座標（セル中心を想定）
    /// seed   = 発生ごとの通し番号（撃つたびの表情替え。同じ値なら同じ絵）
    /// scale  = 大きさ倍率（1.0 で 1 マス 16px を覆う想定）
    pub type alias Burst = {center = Vec2.Vec2, seed = Int32, scale = Float64}

    /// 炎の見た目の指定（プリセット 1 個 = このレコード 1 個）。長さ・px・速さはすべて
    /// scale = 1.0 のときの値で、Burst の scale が一括で掛かる。
    /// duration       = 演出全体の長さ（秒）。これより外の t では quads は空
    /// flashLife      = 閃光の寿命（秒）。0 なら閃光なし
    /// flashGrow      = 閃光が消えるまでに広がる半幅（px）
    /// flashColor     = 閃光の色
    /// flameCount     = 炎の舌の枚数
    /// delaySpan      = 各舌の点火のずれ幅（秒）。小さいほど一斉に燃え上がる
    /// lifeMin/Span   = 舌 1 枚の寿命（秒）: [min, min+span] から自分の値を引く
    /// spreadHalf     = 根元の横広がりの半幅（px）
    /// baseDrop       = 根元の縦位置（px）: セル中心からの下がり幅
    /// riseMin/Span   = 立ち上る速さ（px/秒）
    /// outSpeed       = 全方位へ弾く速さ（px/秒の目安）。0 なら真上型。爆発型は減速
    ///                  しながら outSpeed × 寿命 の距離まで届く
    /// halfMin/Span   = 舌 1 枚の最盛期の半幅（px）
    /// topReachMin    = 舌の縦横比: 上へ [min, min+0.8] × 半幅だけ尖る
    /// rampR/G/B      = 冷め具合 u (0..1) → 色成分の折れ線（Curve.pieces で読む）
    /// sparkCount     = 火の粉の粒数
    /// sparkLaunchMin/Span = 火の粉を上へ弾く初速（px/秒）
    /// sparkColor     = 火の粉の色
    /// tongue         = 舌のシルエット（Kite=菱形 / Drop=雫）
    /// driftX         = 舌の横ドリフト（px/秒）。風に流される。0 で無効
    /// leanBias       = 舌の一定の傾き（ラジアン）。揺れの傾きに加算。0 で直立基調
    /// swirl          = 渦の角速度（ラジアン/秒）。舌が中心を公転しながら立ち上る。0 で無効
    /// swirlRadius    = 渦の初期半径（px）。寿命で 0 へ縮み螺旋になる。0 で無効
    /// ballCount      = 火の玉の外殻ブロブ数（脈動する大玉の重ね枚数）。0 でレイヤーなし
    /// ballRadius     = 火の玉ブロブの基準半径（px）
    /// coreCount      = 火の玉の中心核の同心円の層数（白熱感）。0 でレイヤーなし
    /// coreRadius     = 中心核の外周半径（px）
    /// coreColor      = 中心核の色（白熱）
    /// sparkLifeScale = 火の粉の寿命倍率（1.0 標準。線香花火は長寿命の弧）
    /// sparkStreakLen = 火の粉を速度方向へ伸ばす streak の半長（px）。0 で丸い点
    /// sparkFlickerRate = 火の粉の高周波ちらつきレート（ラジアン/秒）。0 でちらつきなし
    pub type alias Spec = {
        duration = Float64,
        flashLife = Float64, flashGrow = Float64, flashColor = Color,
        flameCount = Int32, delaySpan = Float64, lifeMin = Float64, lifeSpan = Float64,
        spreadHalf = Float64, baseDrop = Float64,
        riseMin = Float64, riseSpan = Float64, outSpeed = Float64,
        halfMin = Float64, halfSpan = Float64, topReachMin = Float64,
        rampR = List[(Float64, Float64)], rampG = List[(Float64, Float64)], rampB = List[(Float64, Float64)],
        sparkCount = Int32, sparkLaunchMin = Float64, sparkLaunchSpan = Float64, sparkColor = Color,
        tongue = TongueShape,
        driftX = Float64, leanBias = Float64,
        swirl = Float64, swirlRadius = Float64,
        ballCount = Int32, ballRadius = Float64,
        coreCount = Int32, coreRadius = Float64, coreColor = Color,
        sparkLifeScale = Float64, sparkStreakLen = Float64, sparkFlickerRate = Float64
    }

    // ════════════════════════════════════════════════════════
    // プリセット
    // ════════════════════════════════════════════════════════

    /// 焚き火型（標準）: セルの足元から黄 → 橙 → 赤の舌がバランスよく燃え上がる。
    pub def standard(): Spec = {
        duration = 0.65,
        flashLife = 0.1, flashGrow = 6.5, flashColor = {r = 1.0f32, g = 0.95f32, b = 0.75f32},
        flameCount = 24, delaySpan = 0.22, lifeMin = 0.22, lifeSpan = 0.18,
        spreadHalf = 5.5, baseDrop = 5.0,
        riseMin = 14.0, riseSpan = 12.0, outSpeed = 0.0,
        halfMin = 1.3, halfSpan = 0.9, topReachMin = 2.6,
        rampR = (0.0, 1.0) :: (0.55, 1.0) :: (1.0, 0.45) :: Nil,
        rampG = (0.0, 0.95) :: (0.3, 0.55) :: (0.7, 0.22) :: (1.0, 0.07) :: Nil,
        rampB = (0.0, 0.6) :: (0.25, 0.12) :: (1.0, 0.02) :: Nil,
        sparkCount = 8, sparkLaunchMin = 30.0, sparkLaunchSpan = 35.0,
        sparkColor = {r = 1.0f32, g = 0.8f32, b = 0.4f32},
        // 新テイスト用の中立値: どれも「効果なし」なので、この値を継ぐ既存プリセットの絵は変わらない。
        tongue = TongueShape.Kite,
        driftX = 0.0, leanBias = 0.0,
        swirl = 0.0, swirlRadius = 0.0,
        ballCount = 0, ballRadius = 0.0,
        coreCount = 0, coreRadius = 0.0, coreColor = {r = 1.0f32, g = 0.95f32, b = 0.8f32},
        sparkLifeScale = 1.0, sparkStreakLen = 0.0, sparkFlickerRate = 0.0
    }

    /// 火柱: 細くまとまった白熱の舌が、勢いよく高く噴き上がる（standard との差分のみ）。
    pub def pillar(): Spec = {
        duration = 0.7,
        flashLife = 0.08, flashGrow = 4.0,
        flameCount = 26, delaySpan = 0.3, lifeMin = 0.2, lifeSpan = 0.15,
        spreadHalf = 3.0, baseDrop = 6.0,
        riseMin = 34.0, riseSpan = 16.0,
        halfMin = 1.1, halfSpan = 0.7, topReachMin = 3.4,
        rampR = (0.0, 1.0) :: (0.8, 1.0) :: (1.0, 0.8) :: Nil,
        rampG = (0.0, 1.0) :: (0.5, 0.8) :: (1.0, 0.35) :: Nil,
        rampB = (0.0, 0.85) :: (0.35, 0.35) :: (1.0, 0.05) :: Nil,
        sparkCount = 10, sparkLaunchMin = 55.0, sparkLaunchSpan = 40.0,
        sparkColor = {r = 1.0f32, g = 0.9f32, b = 0.55f32}
        | standard()
    }

    /// 爆炎: セル中心から全方位へ一斉に弾ける、短く激しい爆発（standard との差分のみ）。
    /// 閃光も大きい。
    pub def flare(): Spec = {
        duration = 0.5,
        flashLife = 0.12, flashGrow = 10.0,
        flameCount = 28, delaySpan = 0.08, lifeMin = 0.18, lifeSpan = 0.14,
        spreadHalf = 2.0, baseDrop = 0.0,
        riseMin = 6.0, riseSpan = 6.0, outSpeed = 40.0,
        halfMin = 1.2, halfSpan = 0.8, topReachMin = 2.4,
        rampR = (0.0, 1.0) :: (1.0, 0.5) :: Nil,
        rampG = (0.0, 0.95) :: (0.25, 0.6) :: (0.6, 0.25) :: (1.0, 0.05) :: Nil,
        rampB = (0.0, 0.7) :: (0.2, 0.15) :: (1.0, 0.02) :: Nil,
        sparkCount = 12, sparkLaunchMin = 40.0, sparkLaunchSpan = 40.0
        | standard()
    }

    /// 残り火: 低く広く、深紅の舌がゆっくりくすぶり続ける（standard との差分のみ）。
    /// 閃光なし・火の粉わずか。
    pub def smolder(): Spec = {
        duration = 0.85,
        flashLife = 0.0, flashGrow = 0.0,
        flameCount = 20, delaySpan = 0.45, lifeMin = 0.3, lifeSpan = 0.25,
        spreadHalf = 6.0,
        riseMin = 8.0, riseSpan = 6.0,
        halfMin = 1.2, halfSpan = 0.8, topReachMin = 2.2,
        rampR = (0.0, 0.95) :: (0.5, 0.8) :: (1.0, 0.3) :: Nil,
        rampG = (0.0, 0.45) :: (0.4, 0.2) :: (1.0, 0.03) :: Nil,
        rampB = (0.0, 0.15) :: (1.0, 0.02) :: Nil,
        sparkCount = 3, sparkLaunchMin = 20.0, sparkLaunchSpan = 20.0,
        sparkColor = {r = 1.0f32, g = 0.5f32, b = 0.25f32}
        | standard()
    }

    /// 蒼炎: 青白く燃える魔法の火（standard との差分のみ）。白 → 水色 → 青 → 菫色へ冷める。
    pub def arcane(): Spec = {
        flashColor = {r = 0.85f32, g = 0.95f32, b = 1.0f32},
        delaySpan = 0.2, lifeMin = 0.24,
        spreadHalf = 5.0,
        riseMin = 18.0, riseSpan = 14.0,
        halfMin = 1.2, halfSpan = 0.8, topReachMin = 2.8,
        rampR = (0.0, 0.75) :: (0.4, 0.45) :: (1.0, 0.25) :: Nil,
        rampG = (0.0, 0.9) :: (0.3, 0.55) :: (1.0, 0.1) :: Nil,
        rampB = (0.0, 1.0) :: (0.6, 1.0) :: (1.0, 0.5) :: Nil,
        sparkCount = 9, sparkLaunchMin = 35.0, sparkLaunchSpan = 40.0,
        sparkColor = {r = 0.75f32, g = 0.9f32, b = 1.0f32}
        | standard()
    }

    /// 雫型: 丸底の柔らかな舌がゆらりと立ち上る、ろうそく・鬼火のあかり（standard との差分のみ）。
    /// 舌のシルエットを Drop（上の尖り 1 頂点＋下半円）にし、尖りを抑えて丸く広く取る。
    pub def droplet(): Spec = {
        duration = 0.7,
        tongue = TongueShape.Drop,
        flashLife = 0.08, flashGrow = 4.0, flashColor = {r = 1.0f32, g = 0.9f32, b = 0.6f32},
        flameCount = 18, delaySpan = 0.28, lifeMin = 0.3, lifeSpan = 0.2,
        spreadHalf = 3.5, baseDrop = 4.0,
        riseMin = 10.0, riseSpan = 8.0,
        halfMin = 1.6, halfSpan = 1.0, topReachMin = 1.4,
        rampR = (0.0, 1.0) :: (0.6, 1.0) :: (1.0, 0.5) :: Nil,
        rampG = (0.0, 0.9) :: (0.35, 0.55) :: (1.0, 0.15) :: Nil,
        rampB = (0.0, 0.55) :: (0.3, 0.2) :: (1.0, 0.05) :: Nil,
        sparkCount = 4, sparkLaunchMin = 18.0, sparkLaunchSpan = 18.0,
        sparkColor = {r = 1.0f32, g = 0.85f32, b = 0.5f32}
        | standard()
    }

    /// 火の玉: 脈動する大玉＋白熱の核（2 層）に、縁を舐める舌少数と火の粉が絡む
    /// （standard との差分のみ）。ball/core レイヤーを有効にし、舌は根元を広く散らして縁に置く。
    pub def fireball(): Spec = {
        duration = 0.6,
        flashLife = 0.1, flashGrow = 8.0, flashColor = {r = 1.0f32, g = 0.9f32, b = 0.65f32},
        flameCount = 10, delaySpan = 0.12, lifeMin = 0.22, lifeSpan = 0.16,
        spreadHalf = 6.0, baseDrop = 0.0,
        riseMin = 10.0, riseSpan = 10.0,
        halfMin = 1.2, halfSpan = 0.8, topReachMin = 2.6,
        ballCount = 5, ballRadius = 7.0,
        coreCount = 2, coreRadius = 4.0, coreColor = {r = 1.0f32, g = 0.96f32, b = 0.82f32},
        rampR = (0.0, 1.0) :: (0.7, 1.0) :: (1.0, 0.6) :: Nil,
        rampG = (0.0, 0.9) :: (0.4, 0.55) :: (1.0, 0.15) :: Nil,
        rampB = (0.0, 0.55) :: (0.25, 0.15) :: (1.0, 0.03) :: Nil,
        sparkCount = 12, sparkLaunchMin = 35.0, sparkLaunchSpan = 40.0,
        sparkColor = {r = 1.0f32, g = 0.85f32, b = 0.5f32}
        | standard()
    }

    /// 横流れ: 風に吹かれて右へ流れ、強く傾いて燃える炎（standard との差分のみ）。
    /// driftX で舌を横へ運び、leanBias で一定の傾きを与える。
    pub def sidestream(): Spec = {
        duration = 0.7,
        flameCount = 24, delaySpan = 0.25, lifeMin = 0.26, lifeSpan = 0.2,
        spreadHalf = 4.0, baseDrop = 4.0,
        riseMin = 16.0, riseSpan = 12.0,
        driftX = 45.0, leanBias = 0.5,
        halfMin = 1.3, halfSpan = 0.9, topReachMin = 2.8,
        sparkCount = 8, sparkLaunchMin = 30.0, sparkLaunchSpan = 35.0
        | standard()
    }

    /// 渦巻き: 舌が中心を公転しながら立ち上り、半径が寿命で縮んで螺旋を描く
    /// （standard との差分のみ）。根元の横広がりは絞り、swirl の周回を主にする。
    pub def vortex(): Spec = {
        duration = 0.75,
        flameCount = 26, delaySpan = 0.3, lifeMin = 0.3, lifeSpan = 0.22,
        spreadHalf = 1.5, baseDrop = 3.0,
        riseMin = 14.0, riseSpan = 10.0,
        swirl = 9.0, swirlRadius = 6.0,
        halfMin = 1.0, halfSpan = 0.7, topReachMin = 2.6,
        sparkCount = 8, sparkLaunchMin = 30.0, sparkLaunchSpan = 35.0
        | standard()
    }

    /// 線香花火: 舌はほぼ出さず、速度方向に伸びる細い streak の火の粉が主役
    /// （standard との差分のみ）。長寿命の重力弧＋高周波ちらつきで儚くまたたく。
    pub def sparkler(): Spec = {
        duration = 0.9,
        flashLife = 0.06, flashGrow = 3.0, flashColor = {r = 1.0f32, g = 0.95f32, b = 0.7f32},
        flameCount = 4, delaySpan = 0.1, lifeMin = 0.12, lifeSpan = 0.08,
        spreadHalf = 2.0, baseDrop = 0.0,
        riseMin = 8.0, riseSpan = 6.0,
        halfMin = 0.8, halfSpan = 0.4, topReachMin = 2.0,
        sparkCount = 24, sparkLaunchMin = 45.0, sparkLaunchSpan = 45.0,
        sparkColor = {r = 1.0f32, g = 0.95f32, b = 0.7f32},
        sparkLifeScale = 2.0, sparkStreakLen = 3.5, sparkFlickerRate = 42.0
        | standard()
    }

    // ════════════════════════════════════════════════════════
    // 導出（共通の骨格）
    // ════════════════════════════════════════════════════════

    /// ダメージポップアップ(100)より奥・ユニットより前面（ExplosionFx と同じ層）。
    def zFire(): Int32 = 90

    def tau(): Float64 = 6.283185307179586

    /// 生存窓: 発生から delay 秒後に生まれ、life 秒だけ生きる。着弾から t 秒目がこの窓の
    /// 外なら None、内なら進み具合 u（0..1）と発生からの経過秒 tl を draw に渡して呼ぶ。
    /// flamePiece / sparkPiece 共通の「点火判定 → 進み具合の算出」の定型をここに集約する。
    def living(delay: Float64, life: Float64, t: Float64, draw: (Float64, Float64) -> a): Option[a] =
        let tl = t - delay;
        if (tl < 0.0 or tl >= life)
            None
        else
            Some(draw(tl / life, tl))

    /// rand チャンネル k から [min, min+span) の値を引く（詠唱の定型）。
    def ranged(rand: Int32 -> Float64, k: Int32, min: Float64, span: Float64): Float64 =
        min + span * rand(k)

    /// 着弾から t 秒目の炎の絵（polygon 列）。演出の時間外では空。
    /// レイヤーは奥から: 閃光 → 火の玉外殻 → 火の玉核 → 炎の舌 → 火の粉。ball/core は
    /// count = 0 の既存プリセットでは空を返すので、並びに足しても絵は変わらない。
    pub def quads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        if (t < 0.0 or t >= spec#duration)
            Nil
        else
            List.append(flashQuads(spec, burst, t),
                List.append(ballQuads(spec, burst, t),
                    List.append(coreQuads(spec, burst, t),
                        List.append(flameQuads(spec, burst, t), sparkQuads(spec, burst, t)))))

    /// 上に尖った菱形（炎の舌のシルエット）。中心から上へ topReach・下へ dropReach・
    /// 横へ halfW を取り、lean ラジアンだけ傾ける（lean = 0 で直立）。
    def kite(shape: {center = Vec2.Vec2, halfW = Float64, topReach = Float64, dropReach = Float64},
             lean: Float64): List[Vec2.Vec2] =
        let across = {x = RenderUtil.cosF(lean), y = RenderUtil.sinF(lean)};   // 傾き後の横軸
        let down = {x = -across#y, y = across#x};                              // 傾き後の縦軸（下向き +）
        let at = (sx, sy) -> Vec2.add(shape#center, Vec2.add(Vec2.mul(across, sx), Vec2.mul(down, sy)));
        at(0.0, -(shape#topReach)) :: at(shape#halfW, 0.0) ::
        at(0.0, shape#dropReach) :: at(-(shape#halfW), 0.0) :: Nil

    /// 雫のシルエット: 上に尖り 1 頂点、下半分は半円。上へ topReach 尖り、下と横は
    /// halfW・dropReach の半楕円の縁を dropRimSteps 等分でなぞる（apex + 縁の凸多角形）。
    /// kite と同じく lean ラジアンだけ傾ける。
    def drop(shape: {center = Vec2.Vec2, halfW = Float64, topReach = Float64, dropReach = Float64},
             lean: Float64): List[Vec2.Vec2] =
        let across = {x = RenderUtil.cosF(lean), y = RenderUtil.sinF(lean)};
        let down = {x = -across#y, y = across#x};
        let at = (sx, sy) -> Vec2.add(shape#center, Vec2.add(Vec2.mul(across, sx), Vec2.mul(down, sy)));
        let pi = tau() / 2.0;
        let rim = List.map(k -> {
            let th = pi * Int32.toFloat64(k) / Int32.toFloat64(dropRimSteps());   // 0（右肩）→ π（左肩）
            at(shape#halfW * RenderUtil.cosF(th), shape#dropReach * RenderUtil.sinF(th))
        }, List.range(0, dropRimSteps() + 1));
        at(0.0, -(shape#topReach)) :: rim

    /// 縁のなめらかさ: 下半円をこの数だけ等分して 1 段増やす（apex 込みで頂点は +2）。
    def dropRimSteps(): Int32 = 5

    /// 舌のシルエットを Spec の形指定で選ぶ。
    def tonguePoly(shape: TongueShape,
                   dims: {center = Vec2.Vec2, halfW = Float64, topReach = Float64, dropReach = Float64},
                   lean: Float64): List[Vec2.Vec2] =
        match shape {
            case TongueShape.Kite => kite(dims, lean)
            case TongueShape.Drop => drop(dims, lean)
        }

    /// 中心 `center`・半径 `radius` の正 `n` 角形（円近似）を `angle0` から反時計に取った頂点。
    /// 火の玉の外殻ブロブと中心核に使う。
    def disk(center: Vec2.Vec2, radius: Float64, n: Int32, angle0: Float64): List[Vec2.Vec2] =
        List.map(i -> {
            let a = angle0 + tau() * Int32.toFloat64(i) / Int32.toFloat64(n);
            Vec2.add(center, {x = radius * RenderUtil.cosF(a), y = radius * RenderUtil.sinF(a)})
        }, List.range(0, n))

    // ── 閃光: 着弾の瞬間に弾ける菱形 ──

    /// 閃光の出始めの半幅（px）。
    def flashHalfStart(): Float64 = 2.5

    /// 着弾の瞬間だけ出る菱形の閃光。広がりながら薄れて消える。flashLife = 0 なら出ない。
    def flashQuads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        if (t >= spec#flashLife)
            Nil
        else {
            let u = t / spec#flashLife;
            let half = (flashHalfStart() + spec#flashGrow * u) * burst#scale;
            { vertices = kite({center = burst#center, halfW = half, topReach = half, dropReach = half}, 0.0),
              color = spec#flashColor,
              alpha = Float64.truncateToFloat32(0.9 * (1.0 - u)),
              zIndex = zFire() + 2, clip = None, blend = DrawCmd.BlendMode.Normal } :: Nil
        }

    // ── 炎の舌: 根元から点火し、揺れながら立ち上り、ramp の色に冷めて消える ──

    // rand チャンネル（0〜9）: 炎の舌はこの範囲だけを使う（火の粉のチャンネルと相乗りしない）。
    def chFlameDelay(): Int32 = 0
    def chFlameLife(): Int32 = 1
    def chFlameBaseXA(): Int32 = 2
    def chFlameBaseXB(): Int32 = 3
    def chFlameRise(): Int32 = 4
    def chFlameSwaySpan(): Int32 = 5
    def chFlameSwayRate(): Int32 = 6
    def chFlamePhase(): Int32 = 7
    def chFlameHalfW(): Int32 = 8
    def chFlameTopReach(): Int32 = 9
    // 全方位への飛び（爆発型）専用チャンネル。火の粉側（10〜15）の先の 16・17 を使う。
    def chFlameOutAngle(): Int32 = 16
    def chFlameOutDist(): Int32 = 17

    // 横揺れの半幅（px）とレート（ラジアン/秒）。傾きも同じ波で決める（揺れる向きに舌が倒れる）。
    def flameSwayMin(): Float64 = 0.8
    def flameSwaySpan(): Float64 = 1.2
    def flameSwayRateMin(): Float64 = 7.0
    def flameSwayRateSpan(): Float64 = 4.0
    /// 揺れに合わせて倒れる最大の傾き（ラジアン）。
    def flameLeanMax(): Float64 = 0.3
    /// 舌の縦横比の個体差幅: 上への尖りは [topReachMin, topReachMin + 0.8] × 半幅。
    def flameTopReachSpan(): Float64 = 0.8
    /// 下への締まり: 0.9 × 半幅。
    def flameDropRatio(): Float64 = 0.9

    /// 生きている舌だけを polygon にする（点火前・燃え尽きは何も出さない）。
    def flameQuads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        Fx.deriveSeeded({seed = burst#seed, count = spec#flameCount}, t,
            (_, rand, tt) -> flamePiece(spec, burst, rand, tt))
            |> List.filterMap(piece -> piece)

    /// 舌 1 枚、着弾から t 秒目。点火が rand でずれ、根元から小さく生まれて膨らみ、
    /// 揺れながら立ち上って（outSpeed があれば全方位へ弾けて）縮み消える。
    /// 色と不透明度は寿命の進み u だけから決まる。
    def flamePiece(spec: Spec, burst: Burst, rand: Int32 -> Float64, t: Float64):
            Option[GameEngine.PolygonRenderCmd] =
        let delay = spec#delaySpan * rand(chFlameDelay());
        let life = ranged(rand, chFlameLife(), spec#lifeMin, spec#lifeSpan);
        living(delay, life, t, (u, tl) -> {
            let baseX = (rand(chFlameBaseXA()) + rand(chFlameBaseXB()) - 1.0) * spec#spreadHalf * burst#scale;
            let rise = ranged(rand, chFlameRise(), spec#riseMin, spec#riseSpan) * burst#scale;
            let phase = tau() * rand(chFlamePhase());
            // 全方位へ弾く飛び（爆発型のみ）。向きと届く割合は自分専用のチャンネルから引き、
            // 勢いよく飛び出して減速しながら最大 outSpeed × 寿命 の距離まで届く。
            // 割合を粒ごとに散らすことで、輪でなく円盤状に埋まる（中央が空洞にならない）。
            let outAngle = tau() * rand(chFlameOutAngle());
            let outDist = spec#outSpeed * life * burst#scale * ranged(rand, chFlameOutDist(), 0.25, 0.75)
                * Curve.pieces((0.0, 0.0) :: (0.35, 0.7) :: (1.0, 1.0) :: Nil, u);
            let outX = outDist * RenderUtil.cosF(outAngle);
            let outY = outDist * RenderUtil.sinF(outAngle) * 0.7;
            // 揺れの波（-1..1）。位置ずらしと傾きを同じ波から取り、舌が倒れながら揺れる。
            let wave = Curve.sine(1.0, ranged(rand, chFlameSwayRate(), flameSwayRateMin(), flameSwayRateSpan()), phase, tl);
            let sway = ranged(rand, chFlameSwaySpan(), flameSwayMin(), flameSwaySpan()) * burst#scale * wave;
            // 風の横流れ（sidestream）。driftX = 0 なら効かない。
            let drift = spec#driftX * burst#scale * tl;
            // 渦の公転（vortex）。中心を角度 spin+位相で回り、半径は寿命で 0 へ縮んで螺旋を描く。
            // swirlRadius = 0 なら半径 0 でずれず、効かない。
            let swAngle = Curve.spin(spec#swirl, tl) + phase;
            let swR = spec#swirlRadius * burst#scale * (1.0 - u);
            let swX = swR * RenderUtil.cosF(swAngle);
            let swY = swR * RenderUtil.sinF(swAngle);
            // 大きさの包絡: 生まれ（小）→ すぐ最盛期 → 燃え尽きへ縮む。
            let swell = Curve.pieces((0.0, 0.25) :: (0.12, 1.0) :: (1.0, 0.1) :: Nil, u);
            let halfW = ranged(rand, chFlameHalfW(), spec#halfMin, spec#halfSpan) * burst#scale * swell;
            let topReach = halfW * ranged(rand, chFlameTopReach(), spec#topReachMin, flameTopReachSpan());
            { vertices = tonguePoly(spec#tongue,
                  {center = {x = burst#center#x + baseX + sway + outX + drift + swX,
                             y = burst#center#y + spec#baseDrop * burst#scale - rise * tl + outY + swY},
                   halfW = halfW, topReach = topReach, dropReach = halfW * flameDropRatio()},
                  flameLeanMax() * wave + spec#leanBias),
              color = flameColor(spec, u),
              alpha = flameAlpha(u),
              zIndex = zFire(), clip = None, blend = DrawCmd.BlendMode.Normal }
        })

    /// 冷め具合 u（0 = 点火, 1 = 燃え尽き）→ 色。Spec の折れ線を成分ごとに読む。
    def flameColor(spec: Spec, u: Float64): Color =
        { r = Float64.truncateToFloat32(Curve.pieces(spec#rampR, u)),
          g = Float64.truncateToFloat32(Curve.pieces(spec#rampG, u)),
          b = Float64.truncateToFloat32(Curve.pieces(spec#rampB, u)) }

    /// 冷め具合 u → 不透明度。点火直後にすっと現れ、色が暗くなり切る前に消え終わる
    /// （u = 0.9 で透明。暗色の舌が根元に沈んで見えるのを防ぐ）。
    def flameAlpha(u: Float64): Float32 =
        Float64.truncateToFloat32(Curve.pieces((0.0, 0.0) :: (0.07, 0.95) :: (0.5, 0.85) :: (0.9, 0.0) :: Nil, u))

    // ── 火の玉（任意レイヤー）: 脈動する大玉ブロブの重なりと、中心の白熱核 ──
    // ballCount / coreCount が 0 のプリセットでは空を返すので、既存の絵に影響しない。

    // rand チャンネル（火の玉の外殻ブロブ専用）。舌・火の粉とは別 seed を引くので採番は 0 起点で衝突しない。
    def chBallPhase(): Int32 = 0
    def chBallOffX(): Int32 = 1
    def chBallOffY(): Int32 = 2
    def chBallHue(): Int32 = 3

    /// 外殻ブロブの seed オフセット（舌・火の粉と別系列の乱数にするため）。
    def ballSeedShift(): Int32 = 1000
    /// 外殻ブロブ・中心核の円近似の頂点数。
    def ballVerts(): Int32 = 12
    def coreVerts(): Int32 = 10
    /// 外殻ブロブの脈動レート（ラジアン/秒）と振幅（半径比）。粒位相でばらけて表面が波打つ。
    def ballPulseRate(): Float64 = 6.0
    def ballPulseAmp(): Float64 = 0.18
    /// 外殻ブロブが立ち上る速さ（px/秒）。玉がわずかに上へ流れる。
    def ballRise(): Float64 = 10.0

    /// 火の玉レイヤーの時間包絡（点火→保持→減衰）。t / duration で読む。
    def ballEnvelope(spec: Spec, t: Float64): Float64 =
        Curve.pieces((0.0, 0.0) :: (0.1, 1.0) :: (0.65, 1.0) :: (1.0, 0.0) :: Nil, t / spec#duration)

    /// 脈動する大玉ブロブの重なり。ballCount = 0 なら出ない。
    def ballQuads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        if (spec#ballCount <= 0)
            Nil
        else {
            let env = ballEnvelope(spec, t);
            Fx.deriveSeeded({seed = burst#seed + ballSeedShift(), count = spec#ballCount}, t, (_, rand, tt) -> {
                let phase = tau() * rand(chBallPhase());
                let pulse = 1.0 + ballPulseAmp() * Curve.sine(1.0, ballPulseRate(), phase, tt);
                let radius = spec#ballRadius * burst#scale * env * pulse;
                let offX = (rand(chBallOffX()) - 0.5) * spec#ballRadius * 0.5 * burst#scale;
                let offY = (rand(chBallOffY()) - 0.5) * spec#ballRadius * 0.5 * burst#scale - ballRise() * burst#scale * tt;
                ({ vertices = disk({x = burst#center#x + offX, y = burst#center#y + offY}, radius, ballVerts(), phase),
                   color = flameColor(spec, 0.12 + 0.3 * rand(chBallHue())),
                   alpha = Float64.truncateToFloat32(0.7 * env),
                   zIndex = zFire(), clip = None, blend = DrawCmd.BlendMode.Normal }: GameEngine.PolygonRenderCmd)
            })
        }

    /// 中心の白熱核（同心円 coreCount 層。内側ほど小さく明るく＝白熱感）。coreCount = 0 なら出ない。
    def coreQuads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        if (spec#coreCount <= 0)
            Nil
        else {
            let env = ballEnvelope(spec, t);
            let n = spec#coreCount;
            List.map(j -> {
                let f = Int32.toFloat64(j) / Int32.toFloat64(n);        // 0 = 外層, 1 に近いほど内層
                let radius = spec#coreRadius * burst#scale * env * (1.0 - 0.55 * f);
                ({ vertices = disk(burst#center, radius, coreVerts(), 0.0),
                   color = spec#coreColor,
                   alpha = Float64.truncateToFloat32((0.55 + 0.4 * f) * env),
                   zIndex = zFire() + 2, clip = None, blend = DrawCmd.BlendMode.Normal }: GameEngine.PolygonRenderCmd)
            }, List.range(0, n))
        }

    // ── 火の粉: 着弾直後に放り上げられ、重力で弧を描きながら燃え尽きる小さな粒 ──
    // 炎の舌とチャンネル 10 以降を使い分け、同じ seed でも舌と歩調が揃わないようにする。

    // rand チャンネル（10〜15）: 火の粉専用。
    def chSparkDelay(): Int32 = 10
    def chSparkLife(): Int32 = 11
    def chSparkKick(): Int32 = 12
    def chSparkLaunch(): Int32 = 13
    def chSparkHalf(): Int32 = 14
    def chSparkSpin(): Int32 = 15

    /// 飛び出しのずれ幅（秒）。ほぼ着弾と同時に散る。
    def sparkDelaySpan(): Float64 = 0.06
    // 粒の寿命（秒）。
    def sparkLifeMin(): Float64 = 0.25
    def sparkLifeSpan(): Float64 = 0.2
    /// 横へ弾く初速の半幅（px/秒）。左右どちらへも飛ぶ。
    def sparkKickHalf(): Float64 = 30.0
    /// 重力（px/秒²）。放り上げられた粒が弧を描いて戻る。
    def sparkGravity(): Float64 = 170.0
    // 粒の半幅（px）と回転レート（ラジアン/秒）。炎より二回り小さい点に見せる。
    def sparkHalfMin(): Float64 = 0.3
    def sparkHalfSpan(): Float64 = 0.3
    def sparkSpinMin(): Float64 = 8.0
    def sparkSpinSpan(): Float64 = 6.0

    /// 生きている火の粉だけを polygon にする。
    def sparkQuads(spec: Spec, burst: Burst, t: Float64): List[GameEngine.PolygonRenderCmd] =
        Fx.deriveSeeded({seed = burst#seed, count = spec#sparkCount}, t,
            (_, rand, tt) -> sparkPiece(spec, burst, rand, tt))
            |> List.filterMap(piece -> piece)

    /// 火の粉 1 粒、着弾から t 秒目。初速と重力だけの放物線（位置はどこにも保存しない）。
    def sparkPiece(spec: Spec, burst: Burst, rand: Int32 -> Float64, t: Float64):
            Option[GameEngine.PolygonRenderCmd] =
        let delay = sparkDelaySpan() * rand(chSparkDelay());
        // sparkLifeScale = 1.0 なら従来どおり。線香花火は倍率で長寿命の弧にする。
        let life = ranged(rand, chSparkLife(), sparkLifeMin(), sparkLifeSpan()) * spec#sparkLifeScale;
        living(delay, life, t, (u, tl) -> {
            let kick = (rand(chSparkKick()) - 0.5) * 2.0 * sparkKickHalf() * burst#scale;
            let launch = ranged(rand, chSparkLaunch(), spec#sparkLaunchMin, spec#sparkLaunchSpan) * burst#scale;
            let half = ranged(rand, chSparkHalf(), sparkHalfMin(), sparkHalfSpan()) * burst#scale;
            let pos = {x = burst#center#x + kick * tl,
                       y = burst#center#y - launch * tl + 0.5 * sparkGravity() * burst#scale * tl * tl};
            // 形: streakLen = 0 なら従来どおり回転する小片。> 0 なら速度方向へ伸びる細い streak
            //     （速度ベクトル = 位置の時間微分を正規化して軸に取る）。
            let verts =
                if (spec#sparkStreakLen <= 0.0)
                    Quad.rotated(pos, half, half, Curve.spin(sparkSpinMin() + sparkSpinSpan() * rand(chSparkSpin()), tl))
                else {
                    let vel = {x = kick, y = -launch + sparkGravity() * burst#scale * tl};
                    Quad.orientedByAxis(pos, Vec2.normalized(vel), half + spec#sparkStreakLen * burst#scale, half * 0.4)
                };
            // ちらつき: flickerRate = 0 なら乗数 1.0（従来どおり）。> 0 なら高周波の |sine| で alpha を変調。
            let fade = Curve.pieces((0.0, 1.0) :: (0.7, 1.0) :: (1.0, 0.0) :: Nil, u);
            let flick =
                if (spec#sparkFlickerRate <= 0.0) 1.0
                else 0.55 + 0.45 * Float64.abs(Curve.sine(1.0, spec#sparkFlickerRate, tau() * rand(chSparkSpin()), tl));
            { vertices = verts,
              color = spec#sparkColor,
              alpha = Float64.truncateToFloat32(fade * flick),
              zIndex = zFire() + 1, clip = None, blend = DrawCmd.BlendMode.Normal }
        })
}
