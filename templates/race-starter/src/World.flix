// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 見下ろしのレース。コースは下へ流れ（前進）、自機の車は画面の下寄りにいる。←→ で左右に寄せ、
// 道（路面）からはみ出すと減速する。前方にライバル 2 台がいて、追い抜くと順位（rank）が上がり
// 得点が入る。前進した距離が 1 周（lapLength）に達すると lap が増え、totalLaps 周でゴール = WIN。
// 手触りと収支の数値（前進速度・ハンドルの効き・ライバル速度・周回数・得点）は RulesDoc、
// 色は ThemeDoc、コースの形（路面 vs 草）は CourseDoc — World は「規則」だけに集中する。
//
// ── 毎フレームの流れ ──
//   入力（Controls.step）→ 状態更新（World.step: 前進・ハンドル・はみ出し減速・ライバル前進・
//   追い抜き判定・周回/ゴール判定）→ 描画（View.frame）。
//   Main の App.game の update 行がこの順（Controls.step |> ActiveDocs.step）。
//
// ── 場面の移り変わり（Phase）──
//
//   Title ──Space/Enter──▶ Racing ──totalLaps 周を走破──▶ Finish ──Space/Enter──▶ Title
//
// 遷移を起こす関数の doc には [遷移: X→Y] を付けてある（探すときの目印）。
//
// Doc が壊れていても止まらない（fail-open）: 読めない → 既定値で起動、一部が欠け → その欄だけ既定。
mod World {

    /// いま画面が何をしているか。
    ///   Title  … 開始待ち（遊び方を出している）。
    ///   Racing … 走っている（ふつうの状態）。
    ///   Finish … totalLaps 周を走り切ってゴールした（WIN。Space/Enter で最初へ）。
    pub enum Phase with Eq, ToString {
        case Title
        case Racing
        case Finish
    }

    /// ライバル 1 台。
    ///   progress … そのライバルが走った距離（px。自機の distance と同じ物差し）。
    ///   laneX    … 画面上の左右位置（px。固定レーンを素直に走る）。
    ///   speed    … 前進の速さ（px/秒。Doc 由来）。
    ///   passed   … 自機がこのライバルを既に抜いたか（二重加点を防ぐ掛け金）。
    pub type alias Rival = { progress = Float64, laneX = Float64, speed = Float64, passed = Bool }

    /// ゲームの状態。自機の横位置と前進距離、周回、ライバル、収支を持つ。
    ///   playerX  … 自機の左右位置（px。y は画面下部に固定で View と対）。
    ///   distance … 自機が走った総距離（px）。lapLength ごとに 1 周進む物差し。
    ///   lap      … 走り終えた周回数（0 始まり。totalLaps に達したらゴール）。
    ///   speed    … いまの前進速度（px/秒。はみ出すと offRoadSlow を掛けて落ちる。演出と HUD 用）。
    ///   rank     … いまの順位（1 = 先頭）。ライバルより前にいるほど小さい。
    ///   rivals   … ライバル 2 台。
    ///   score    … 得点（追い抜き + ゴールボーナス）。
    pub type alias World = {
        rules = RulesDoc.Doc,
        theme = ThemeDoc.Doc,
        course = CourseDoc.Doc,
        phase = Phase,
        playerX = Float64,
        distance = Float64,
        lap = Int32,
        speed = Float64,
        rank = Int32,
        rivals = List[Rival],
        score = Int32,
        passFlash = Float64,
        activeDocsWritten = String
    }

    // ── 画面の寸法とレイアウト（project.json の design 240×360 と対。View も同じ値を使う） ──

    pub def designW(): Float64 = 240.0
    pub def designH(): Float64 = 360.0

    /// 自機の車の中心の y（画面の下寄りに固定）。ライバルはこれより上（前方）に見える。
    pub def playerY(): Float64 = 300.0

    /// 車 1 台の見た目・当たりの 1 辺（px）。ライバルとの近さ判定にも使う。
    pub def carSize(): Float64 = 18.0

    /// 自機が左右に出られる範囲（画面の縁に少し余白を残す）。草には出られるが画面外へは出ない。
    def marginX(): Float64 = 10.0

    /// コース 1 段（格子の 1 行）が距離いくつ分か（px）。距離 → 行番号の割り算の分母。
    /// 見た目のスクロール量（View）とも対にする（マジックナンバーを 2 か所に置かない）。
    pub def rowPitch(): Float64 = 40.0

    /// 起動時と bake が同じ形で読む Doc の束。
    pub type alias Docs = { rules = RulesDoc.Doc, theme = ThemeDoc.Doc, course = CourseDoc.Doc }

    /// ゲーム開始時の状態。Title 画面から始まる（まだ走っていない）。
    pub def initial(docs: Docs): World =
        { rules = docs#rules, theme = docs#theme, course = docs#course,
          phase = Phase.Title, playerX = designW() / 2.0, distance = 0.0,
          lap = 0, speed = 0.0, rank = startRank(docs#rules), rivals = initialRivals(docs#rules),
          score = 0, passFlash = 0.0, activeDocsWritten = "" }

    /// ライバル 2 台の初期配置。少し前方（progress を持たせて）に置き、左右の別レーンへ振る。
    /// 速さは Doc（rivalSpeedA / rivalSpeedB）。抜かれる前は passed = false。
    def initialRivals(rules: RulesDoc.Doc): List[Rival] =
        { progress = 120.0, laneX = designW() * 0.36, speed = rules#rivalSpeedA, passed = false }
            :: { progress = 200.0, laneX = designW() * 0.62, speed = rules#rivalSpeedB, passed = false }
            :: Nil

    /// 開始時の順位。自機は最後尾から出る（ライバルは全員前にいる）。
    def startRank(rules: RulesDoc.Doc): Int32 =
        List.length(initialRivals(rules)) + 1

    /// 遊び始め（Title → Racing）。距離・周回・収支を初期化し、ライバルを前方へ置き直す。[遷移: Title→Racing]
    pub def startGame(w: World): World =
        { phase = Phase.Racing, playerX = designW() / 2.0, distance = 0.0,
          lap = 0, speed = w#rules#forwardSpeed, rank = startRank(w#rules),
          rivals = initialRivals(w#rules), score = 0, passFlash = 0.0 | w }

    // ══════════════════════════════════════════════════════
    // 毎フレームの更新（前進・ハンドル・はみ出し・ライバル・追い抜き・周回）
    // ══════════════════════════════════════════════════════

    /// 毎フレームの拍。phase ごとに分岐する。
    ///   Racing 以外（Title/Finish）… 何もしない（入力は Controls が拾う）。
    ///   Racing … ハンドル → 前進（はみ出し減速込み）→ ライバル前進 → 追い抜き → 周回/ゴール。
    /// dir = 左右入力（-1/0/+1。Controls が渡す）。
    pub def step(dir: Float64, dt: Float64, w: World): World =
        match w#phase {
            case Phase.Racing => tickRacing(dir, dt, w)
            case _            => w
        }

    /// Racing の 1 拍。「進める部品」を順に pipe でつなぐ（読み下すと 1 フレームの物語になる）。
    def tickRacing(dir: Float64, dt: Float64, w: World): World =
        w
            |> steer(dir, dt)
            |> advance(dt)
            |> moveRivals(dt)
            |> resolvePasses
            |> tickFlash(dt)
            |> checkLaps

    /// ハンドル: ←→ で自機を左右へ寄せる。画面の縁（marginX）で止める（画面外へは出ない）。
    /// 草にははみ出せる（減速するのは advance 側の役目）。
    def steer(dir: Float64, dt: Float64, w: World): World =
        let nx = w#playerX + dir * w#rules#steerSpeed * dt;
        { playerX = clampF(marginX(), designW() - marginX(), nx) | w }

    /// 前進: 前進速度ぶん distance を伸ばす。ただし自機の足元が草（道の外）なら
    /// offRoadSlow を掛けて遅くする（はみ出し減速 = ルール）。
    def advance(dt: Float64, w: World): World =
        let base = w#rules#forwardSpeed;
        let sp = if (onRoad(w)) base else base * w#rules#offRoadSlow;
        { distance = w#distance + sp * dt, speed = sp | w }

    /// ライバルを前へ進める（各自の speed で distance を伸ばす。横移動や AI は持たない = 素直）。
    def moveRivals(dt: Float64, w: World): World =
        let moved = w#rivals |> List.map(r -> { progress = r#progress + r#speed * dt | r });
        { rivals = moved | w }

    // ══════════════════════════════════════════════════════
    // はみ出し判定（自機の足元が路面か草か）
    // ══════════════════════════════════════════════════════

    /// 自機の足元（いまの距離の行・playerX の列）が路面か。草なら false（= 減速）。
    /// 距離 → 行、playerX → 列 に写して CourseDoc に「そのマスは路面か」を尋ねるだけ。
    pub def onRoad(w: World): Bool =
        let row = CourseDoc.rowAt(roadRowAt(w#distance), w#course);
        CourseDoc.isRoadCell(row, colOf(w#playerX, w))

    /// いまの距離が何行目か（0 始まり。周回は CourseDoc.rowAt が余りで巻き戻す）。
    pub def roadRowAt(distance: Float64): Int32 =
        Float64.floor(distance / rowPitch()) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    /// 画面上の x を格子の列番号へ写す（0 始まり）。画面幅を colCount で等分する。
    def colOf(x: Float64, w: World): Int32 =
        let cols = CourseDoc.colCount(w#course);
        let cellW = designW() / Int32.toFloat64(cols);
        Float64.floor(x / cellW) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    // ══════════════════════════════════════════════════════
    // 追い抜き（自機の distance がライバルの progress を越えたら 1 台抜いた）
    // ══════════════════════════════════════════════════════

    /// 追い抜きを解く: まだ抜いていないライバルのうち、自機の distance が追い越したものを
    /// 「抜いた（passed = true）」に変え、抜いたぶんだけ scorePerPass を足し、順位を取り直す。
    /// passed の掛け金で「1 台につき 1 回だけ加点」を素直に守る（総当たりでなく状態で持つ）。
    def resolvePasses(w: World): World =
        let justPassed = r -> not r#passed and w#distance >= r#progress;
        let updated = w#rivals |> List.map(r -> if (justPassed(r)) { passed = true | r } else r);
        let passes = w#rivals |> List.count(justPassed);
        // 抜いた瞬間だけ閃光タイマーを満タンにする（演出。View が glowAt で焚く。ルールには絡まない）。
        let flash = if (passes > 0) flashDuration() else w#passFlash;
        { rivals = updated, score = w#score + passes * w#rules#scorePerPass,
          rank = rankOf({ rivals = updated | w }), passFlash = flash | w }

    /// 追い抜きの閃光が見えている長さ（秒）。View も減衰の分母にこの値を使う（マジックナンバーを 2 か所に置かない）。
    pub def flashDuration(): Float64 = 0.35

    /// 閃光タイマーを減らす（演出の時間管理。0 で消える）。
    def tickFlash(dt: Float64, w: World): World =
        { passFlash = Float64.max(0.0, w#passFlash - dt) | w }

    /// いまの順位（1 = 先頭）。自機より前にいる（progress が distance より大きい）ライバルの数 + 1。
    pub def rankOf(w: World): Int32 =
        1 + (w#rivals |> List.count(r -> r#progress > w#distance))

    // ══════════════════════════════════════════════════════
    // 周回とゴール
    // ══════════════════════════════════════════════════════

    /// 走った距離から「走り終えた周回数」を更新し、totalLaps 周に達したらゴール = WIN。
    /// lap は distance / lapLength の整数部（何周ぶん走ったか）。[遷移: Racing→Finish]
    def checkLaps(w: World): World =
        let lapsDone = Float64.floor(w#distance / w#rules#lapLength)
            |> Float64.tryToInt32 |> Option.getWithDefault(0);
        if (lapsDone >= w#rules#totalLaps)
            // ゴール。ボーナスは 1 回だけ足す（Finish に入る瞬間のみ通る）。
            { phase = Phase.Finish, lap = w#rules#totalLaps,
              score = w#score + w#rules#finishBonus | w }
        else
            { lap = lapsDone | w }

    // ══════════════════════════════════════════════════════
    // 場面の仕切り直し（Title へ戻る）
    // ══════════════════════════════════════════════════════

    /// Finish から最初（Title）へ戻る。[遷移: Finish→Title]
    pub def toTitle(w: World): World =
        initial({ rules = w#rules, theme = w#theme, course = w#course })

    /// Space/Enter の意味は場面で変わる: Title/Finish では仕切り直し、走行中は無し（ハンドルは別入力）。
    pub def confirm(w: World): World =
        match w#phase {
            case Phase.Title  => startGame(w)
            case Phase.Finish => toTitle(w)
            case Phase.Racing => w
        }

    pub def isRacing(w: World): Bool = w#phase == Phase.Racing

    // ══════════════════════════════════════════════════════
    // Doc の差し替え（保存即反映）と 表示中の名乗り
    // ══════════════════════════════════════════════════════

    pub def withRules(rules: RulesDoc.Doc, w: World): World = { rules = rules | w }
    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }
    pub def withCourse(course: CourseDoc.Doc, w: World): World = { course = course | w }

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。Studio の「表示中」バッジの材料。
    pub def activeDocs(_w: World): List[(String, List[String])] =
        ("rules", RulesDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("course", CourseDoc.path() :: Nil) :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
