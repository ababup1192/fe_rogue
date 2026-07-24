// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 育成シミュ。発表会までの毎日、いくつかの行動から 1 つを ↑↓ で選び Space/Enter で決める。
// 選んだ行動でパラメータ（たいりょく・きあい・わざ）が Plan の伸び幅ぶん育ち、
// そのあと確率でイベント（数値の増減）が起きる。決めるたびに日が進み、日数（Doc）を使い切ると
// 発表会（Result）で合計値からランク（結末）が決まる。プレイヤーは死なない・詰まない。
//
// 手触りと収支の数値（日数・確率・上限・乱数の種）は RulesDoc、色は ThemeDoc、
// 行動・イベント・結末の一覧と文言は PlanDoc — World は「規則」だけに集中する。
//
// ── 毎フレームの流れ ──
//   ターン制なので毎フレーム進むのは演出タイマー（reveal の残り時間）だけ。
//   状態が本当に進むのは入力のとき: 入力（Controls.step）→ 選ぶ/決める（moveCursor / confirm）
//   → 描画（View.frame）。Main の App.game の update 行がこの順（Controls.step |> ActiveDocs.step）。
//
// ── 場面の移り変わり（Phase）──
//
//   Title ──Space/Enter──▶ Day(選択) ──決定──▶ Reveal(伸び+イベントを見せる)
//                             ▲                        │ Space/Enter
//                             │  まだ日が残っている ────┘
//                             │
//                             └── 日数を使い切った ──▶ Result(結末) ──Space/Enter──▶ Title
//
// 遷移を起こす関数の doc には [遷移: X→Y] を付けてある（探すときの目印）。
//
// Doc が壊れていても止まらない（fail-open）: 読めない → 既定値で起動、一部が欠け → その欄だけ既定。
mod World {

    /// いま画面が何をしているか。
    ///   Title  … 開始待ち（題と遊び方を出している）。
    ///   Day    … 今日の行動をメニューから選んでいる（↑↓ で選び Space/Enter で決定）。
    ///   Reveal … 選んだ行動の伸びと（起きたら）イベントを見せている（Space/Enter で次の日へ）。
    ///   Result … 発表会。育った合計値で決まった結末を出している（Space/Enter で最初へ）。
    pub enum Phase with Eq, ToString {
        case Title
        case Day
        case Reveal
        case Result
    }

    /// 起動時と bake が同じ形で読む Doc の束。
    pub type alias Docs = { rules = RulesDoc.Doc, theme = ThemeDoc.Doc, plan = PlanDoc.Doc }

    /// ゲームの状態。育ち具合と、いまが何日目か、メニューのカーソル、直前の見せ物を持つ。
    ///   stats     … いまのパラメータ（たいりょく・きあい・わざ）。行動とイベントで育つ。
    ///   day       … いま何日目か（0 始まり。dayCount に届いたら発表会）。
    ///   cursor    … メニューでいま選んでいる行動の番号（0 始まり）。
    ///   lastGain  … 直前の行動で伸びた分（Reveal のポップ表示に使う）。
    ///   lastEvent … 直前に起きたイベント（無ければ None）。Reveal で文を出す。
    ///   rng       … イベント抽選の決定的な乱数の状態（seed から始まり毎回進む）。
    pub type alias World = {
        rules = RulesDoc.Doc,
        theme = ThemeDoc.Doc,
        plan = PlanDoc.Doc,
        phase = Phase,
        stats = PlanDoc.Stats,
        day = Int32,
        cursor = Int32,
        lastGain = PlanDoc.Stats,
        lastEvent = Option[PlanDoc.Event],
        rng = Int64,
        activeDocsWritten = String
    }

    // ── 画面の寸法（project.json の design 320×360 と対。View も同じ値を使う）──

    pub def designW(): Float64 = 320.0
    pub def designH(): Float64 = 360.0

    /// ゲーム開始時の状態。Title 画面から始まる（まだ育っていない・1 日目の前）。
    pub def initial(docs: Docs): World =
        { rules = docs#rules, theme = docs#theme, plan = docs#plan,
          phase = Phase.Title, stats = PlanDoc.zeroStats(), day = 0, cursor = 0,
          lastGain = PlanDoc.zeroStats(), lastEvent = None,
          rng = seedRng(docs#rules), activeDocsWritten = "" }

    // ══════════════════════════════════════════════════════
    // 決定的な乱数（イベント抽選だけに使う。seed から始まり毎回進む LCG）
    // ══════════════════════════════════════════════════════

    /// 乱数の初期状態。Doc の seed から作る（同じ seed なら毎回同じ運びになる = 決定的）。
    def seedRng(rules: RulesDoc.Doc): Int64 =
        Int32.toInt64(rules#seed) + 1i64

    /// LCG を 1 歩進めて 0.0..1.0 の値と次の状態を返す（数値レシピの定番 = 黒箱に一言）。
    /// これは「線形合同法」という素朴な擬似乱数。演出の乱れではなくルール（イベント抽選）に使うので、
    /// World の rng に状態を持たせて再現できるようにしている。
    def nextRand(state: Int64): (Float64, Int64) =
        let next = state * 6364136223846793005i64 + 1442695040888963407i64;
        let hi = Int64.rightShift(Int64.abs(next), 33);      // 上位ビットだけ使う（下位は質が悪い）
        (Int64.toFloat64(Int64.modulo(hi, 1000000i64)) / 1000000.0, next)

    // ══════════════════════════════════════════════════════
    // 進行の規則（選ぶ → 決める → 育つ → イベント → 日が進む → 発表会）
    // ══════════════════════════════════════════════════════

    /// 遊び始め（Title → Day）。育ちを 0 に戻し、1 日目のメニューへ。乱数も種から引き直す。[遷移: Title→Day]
    pub def startGame(w: World): World =
        { phase = Phase.Day, stats = PlanDoc.zeroStats(), day = 0, cursor = 0,
          lastGain = PlanDoc.zeroStats(), lastEvent = None, rng = seedRng(w#rules) | w }

    /// メニューのカーソルを delta ぶん動かす（端で反対側へ回り込む）。Day 以外では動かない。
    /// 端の回り込みはエンジンの UiMenu.moveCursor（選択メニュー共通の作法・engine docs/module-index.md）
    /// に任せる — 自前で剰余を書かない。
    pub def moveCursor(delta: Int32, w: World): World =
        match w#phase {
            case Phase.Day =>
                { cursor = UiMenu.moveCursor(delta, PlanDoc.actionCount(w#plan), w#cursor) | w }
            case _ => w
        }

    /// Space/Enter の「決定」。意味は場面で変わる（Day では行動を決める・それ以外は場面送り）。
    pub def confirm(w: World): World =
        match w#phase {
            case Phase.Title  => startGame(w)
            case Phase.Day    => chooseAction(w)
            case Phase.Reveal => afterReveal(w)
            case Phase.Result => toTitle(w)
        }

    /// いま選んでいる行動を決める: パラメータを伸ばし、確率でイベントを起こし、Reveal を見せる。
    /// [遷移: Day→Reveal]
    def chooseAction(w: World): World =
        let action = PlanDoc.actionAt(w#cursor, w#plan);
        let grown = capStats(PlanDoc.addStats(w#stats, action#gain), w);   // 行動の伸び（上限で頭打ち）
        let (event, rng1) = rollEvent(w);                                  // 確率でイベントを引く
        let afterEvent = match event {
            case Some(ev) => capStats(PlanDoc.addStats(grown, ev#delta), w)
            case None     => grown
        };
        { phase = Phase.Reveal, stats = afterEvent, lastGain = action#gain,
          lastEvent = event, rng = rng1 | w }

    /// Reveal を読み終えた: まだ日が残っていれば次の日のメニューへ、使い切ったら発表会へ。
    /// day は「決めた回数」= 進んだ日数。dayCount 回決めたら発表会。[遷移: Reveal→Day / Reveal→Result]
    def afterReveal(w: World): World =
        let nextDay = w#day + 1;
        if (nextDay >= w#rules#dayCount)
            { phase = Phase.Result, day = nextDay | w }
        else
            { phase = Phase.Day, day = nextDay, cursor = 0 | w }

    /// 各パラメータを 0..statCap に収める（マイナスにも上限超えにもしない）。
    def capStats(s: PlanDoc.Stats, w: World): PlanDoc.Stats =
        let cap = w#rules#statCap;
        { power = clampI(0, cap, s#power),
          spirit = clampI(0, cap, s#spirit),
          skill = clampI(0, cap, s#skill) }

    // ── イベントの抽選（確率は eventChance、どれが出るかは weight の重み付き） ──

    /// 確率でイベントを 1 つ引く。まず eventChance で「起きるか」を決め、起きるなら
    /// weight（出やすさ）で重み付き抽選する。乱数は決定的（rng を返して次へ引き継ぐ）。
    def rollEvent(w: World): (Option[PlanDoc.Event], Int64) =
        let (r0, rng1) = nextRand(w#rng);
        if (r0 >= w#rules#eventChance)
            (None, rng1)                                     // 起きなかった
        else {
            let (r1, rng2) = nextRand(rng1);
            (pickWeighted(r1, w#plan#events), rng2)
        }

    /// weight の重み付き抽選: 全 weight の合計に r（0..1）を掛けた位置に落ちる行を選ぶ。
    /// weight が 0 の行は選ばれない。合計が 0（全部 0・空）なら None（イベント無し）。
    def pickWeighted(r: Float64, events: List[PlanDoc.Event]): Option[PlanDoc.Event] =
        let totalW = events |> List.map(e -> Int32.max(0, e#weight)) |> List.foldLeft((a, b) -> a + b, 0);
        if (totalW <= 0) None
        else {
            let target = r * Int32.toFloat64(totalW);        // 0..totalW の位置
            walkWeighted(target, 0.0, events)
        }

    /// 重みの帯を左から積んでいき、target を越えた行で止まる（重み付き抽選の心臓）。
    def walkWeighted(target: Float64, acc: Float64, events: List[PlanDoc.Event]): Option[PlanDoc.Event] =
        match events {
            case Nil          => None
            case ev :: rest =>
                let acc1 = acc + Int32.toFloat64(Int32.max(0, ev#weight));
                if (target < acc1) Some(ev) else walkWeighted(target, acc1, rest)
        }

    // ── 発表会（結末は合計値のしきい値で決まる。しきい値は Doc）──

    /// いまの育ちに見合う結末。合計値（3 パラメータの和）を PlanDoc.endingFor に渡すだけ。
    pub def ending(w: World): PlanDoc.Ending =
        PlanDoc.endingFor(PlanDoc.total(w#stats), w#plan)

    /// 発表会からタイトルへ戻る（必ず仕切り直せる）。[遷移: Result→Title]
    pub def toTitle(w: World): World =
        initial({ rules = w#rules, theme = w#theme, plan = w#plan })

    // ── 場面の問い合わせ（View / Controls が使う小物）──

    /// 発表会までの残り日数（Title/Day 用の表示に使う）。
    pub def daysLeft(w: World): Int32 =
        Int32.max(0, w#rules#dayCount - w#day)

    // ══════════════════════════════════════════════════════
    // Doc の差し替え（保存即反映）と 表示中の名乗り
    // ══════════════════════════════════════════════════════

    pub def withRules(rules: RulesDoc.Doc, w: World): World = { rules = rules | w }
    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }
    pub def withPlan(plan: PlanDoc.Doc, w: World): World = { plan = plan | w }

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。Studio の「表示中」バッジの材料。
    pub def activeDocs(_w: World): List[(String, List[String])] =
        ("rules", RulesDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("plan", PlanDoc.path() :: Nil) :: Nil

    def clampI(lo: Int32, hi: Int32, v: Int32): Int32 =
        Int32.max(lo, Int32.min(hi, v))
}
