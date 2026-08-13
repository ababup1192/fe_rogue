// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 台本（文章・分岐・結末）は StoryDoc の rows、進め方と「疑うと灯りが消える」規則はここ。
// 表紙（Title）→ 物語（Story）→ 結末の節を読み終えたら表紙へ戻る。プレイヤーは死なない。
//
// 場面の移り変わり（Phase と、Story の中の台本の流れ）:
//
//     Title ──決定(advance/begin)──▶ Story
//                                      │  節の beats を順に読む(advance)
//                                      ▼
//                                  ask あり ──選ぶ(pick)──▶ goto の節へ(enter)
//                                  ask なし ──▶ next の節へ / next 空なら結末
//                                                              │
//     Title ◀──────結末を読み終えた・台本が切れた(toTitle)──────┘
//
// 遷移を起こす関数の doc には [遷移: X→Y] を付けてある（探すときの目印）。
//
// Doc が壊れていても止まらない（fail-open の 3 段階）:
//   読めない → 既定値で起動（Controls.loadDocs / *Doc.defaults）
//   一部が欠け → その欄だけ既定値（fromJson が欄ごとに拾う）
//   型が違う   → その欄は既定値のまま（行き先の節が無ければ表紙へ倒れる 等）
// だからプレイヤーの前でクラッシュしない。台本の編集ミスは既定へ落ちて読みは続く。
mod World {

    /// いま画面が何をしているか。Title = 表紙（決定で物語がはじまる）、Story = 台本を読んでいる。
    pub enum Phase with Eq, ToString {
        case Title
        case Story
    }

    /// 起動時に読む Doc の束（Main と SceneRender が同じ形で組む）。
    pub type alias Docs = {
        story = StoryDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc
    }

    /// ゲームの状態。section / idx = 台本上の現在地、kit = ダイアログと選択肢、
    /// cursor = 選択肢のカーソル位置、lightsOut = 消えた灯りの数（疑うたびに増える）、
    /// t = 起動からの積み上げ秒（雨・炎の揺らぎ・埃が見る。読んでいる間も部屋を止めない）。
    pub type alias World = {
        phase = Phase,
        story = StoryDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        t = Float64,
        section = String,
        idx = Int32,
        kit = NovelKit.Kit,
        cursor = Int32,
        lightsOut = Int32,
        ui = UiStore.UiWorld,
        docError = Option[String],
        activeDocsWritten = String
    }

    // ── 盤の寸法（design 480×300 の中の定数。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 300.0

    pub def spritePath(): String = "assets/novel.sprite.json"

    /// ゲーム開始時の状態。表紙から始まり、灯りは全部ついている。
    pub def initial(docs: Docs, ui: UiStore.UiWorld): World =
        { phase = Phase.Title,
          story = docs#story, kind = docs#kind, theme = docs#theme, sprites = docs#sprites,
          t = 0.0, section = docs#story#start, idx = 0,
          kit = NovelKit.closed(), cursor = 0, lightsOut = 0,
          ui = ui, docError = None, activeDocsWritten = "" }

    /// いまついている灯りの数（消えた分を引いた残り。負にはならない）。
    pub def lampsLit(w: World): Int32 =
        Int32.max(0, w#story#lamps - w#lightsOut)

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。
    /// Studio の「表示中」バッジの材料（ActiveDocs.step が debug/ に名乗る）。
    /// 表紙も部屋と額縁と台本の題を描くので story / theme / sprite は常に表示中。
    /// ダイアログ（ui）と手触り（kind: 文字送り・暗さ）は本文に入ってから —
    /// 全部を常時 active にしない（バッジの意味が死ぬ）。
    pub def activeDocs(w: World): List[(String, List[String])] =
        let base = ("story", StoryDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("sprite", spritePath() :: Nil)
            :: Nil;
        match w#phase {
            case Phase.Title => base
            case Phase.Story => List.append(base,
                   ("ui", NovelKit.uiPaths())
                :: ("kind", KindDoc.path() :: Nil)
                :: Nil)
        }

    // ── 進行の規則 ──

    /// 表紙から物語をはじめる。灯りは全部つき直る（新しい夜）。[遷移: Title→Story]
    def begin(w: World): World =
        enter(w#story#start, 0, { phase = Phase.Story, lightsOut = 0 | w })

    /// 表紙へ戻る（結末を読み終えた・台本が切れた）。部屋の暗さはそのまま残り、
    /// 次に begin したとき灯り直す。[遷移: Story→Title]
    def toTitle(w: World): World =
        { phase = Phase.Title, kit = NovelKit.closed() | w }

    /// 台本の (section, idx) のビートをキットに乗せる。ビートを読み終えた節は
    /// ask（分岐）→ next（次の節）→ どちらも無ければ結末 = 表紙へ、の順に出口を選ぶ。
    /// [遷移: 節→次のビート / 次の節 / 結末(Story→Title)]
    /// fuel は空の節が連なる壊れた台本でも必ず止まるための上限。
    pub def enter(sectionId: String, idx: Int32, w: World): World =
        enterFuel(8, sectionId, idx, w)

    def enterFuel(fuel: Int32, sectionId: String, idx: Int32, w: World): World =
        if (fuel <= 0) toTitle(w)
        else match StoryDoc.sectionOf(sectionId, w#story) {
            case None => toTitle(w)
            case Some(section) =>
                match List.nth(idx, section#beats) {
                    case Some(beat) =>
                        { section = sectionId, idx = idx,
                          kit = NovelKit.say(beat#speaker, beat#text) | w }
                    case None => leave(fuel, sectionId, idx, section, w)
                }
        }

    /// ビートを読み終えた節の出口。
    def leave(fuel: Int32, sectionId: String, idx: Int32, section: StoryDoc.Section, w: World): World =
        match section#ask {
            case Some(ask) =>
                { section = sectionId, idx = idx, cursor = 0,
                  kit = NovelKit.ask(ask#speaker, ask#text, entriesOf(ask#options)) | w }
            case None =>
                if (section#next == "") toTitle(w)
                else enterFuel(fuel - 1, section#next, 0, w)
        }

    /// 選択肢の rows を UI のスロット項目へ（クリックの意味は meta: novel/choice/N）。
    def entriesOf(options: List[StoryDoc.Choice]): List[UiSlots.Entry] =
        options |> List.zipWithIndex |> List.map(pair -> {
            let (i, choice) = pair;
            ({ text = choice#label, meta = Some("${NovelKit.choicePrefix()}${i}") }: UiSlots.Entry)
        })

    /// 決定 1 回分。表紙では物語をはじめ［遷移: Title→Story］、文字送り中なら全文へ、
    /// 読み終えていれば次のビートへ（Story のまま enter で進む）。
    /// 選択肢待ちは動かない（pick だけが進める）。
    pub def advance(w: World): World =
        match w#phase {
            case Phase.Title => begin(w)
            case Phase.Story =>
                if (NovelKit.isAsking(w#kit)) w
                else if (not UiDialog.lineDone(w#kit#dialog))
                    { kit = NovelKit.advance(w#kit) | w }
                else enter(w#section, w#idx + 1, w)
        }

    /// 選択肢カーソルを delta ぶん動かす（端で反対側へ回り込む）。
    pub def moveCursor(delta: Int32, w: World): World =
        let count = UiMenu.count(NovelKit.choicesPath(), w#ui);
        { cursor = UiMenu.moveCursor(delta, count, w#cursor) | w }

    /// 選択肢 i を選ぶ: 「疑う」選択（suspect）なら館の灯りをひとつ消してから、
    /// 行き先の節の先頭へ。[遷移: 分岐→goto の節]
    pub def pick(i: Int32, w: World): World =
        match currentOptions(w) |> List.nth(i) {
            case None => w
            case Some(choice) => enter(choice#goto, 0, dimIf(choice#suspect, w))
        }

    /// 疑ったときだけ灯りをひとつ消す（台本の lamps より多くは消えない）。
    def dimIf(suspect: Bool, w: World): World =
        if (suspect)
            { lightsOut = Int32.min(w#story#lamps, w#lightsOut + 1) | w }
        else w

    def currentOptions(w: World): List[StoryDoc.Choice] =
        StoryDoc.sectionOf(w#section, w#story)
            |> Option.flatMap(section -> section#ask)
            |> Option.map(ask -> ask#options)
            |> Option.getWithDefault(Nil)

    /// 毎フレーム: 文字送りを進め、キットの状態を UI へ刻む（表紙ではダイアログは閉じている）。
    /// 毎フレーム: 文字送りを進め、時計を進める。時計は場面を問わず進む —
    /// 読んでいる間も表紙でも、雨は降り炎は揺れる（動かない絵は止まって見える）。
    pub def step(dt: Float64, w: World): World =
        let kit = NovelKit.step(cps = w#kind#cps, dt, w#kit);
        { kit = kit, ui = NovelKit.apply(kit, w#ui), t = w#t + dt | w }

    // ── Doc の差し替え（保存即反映） ──

    /// 台本の差し替え。物語の途中なら現在地を読み直す（編集がその場で画面に出る）。
    /// 現在地の節が消えていたら表紙へ倒れる（fail-open）。
    pub def withStory(story: StoryDoc.Doc, w: World): World =
        let w1 = { story = story | w };
        match w1#phase {
            case Phase.Title => w1
            case Phase.Story => enter(w1#section, w1#idx, w1)
        }

    pub def withKind(kind: KindDoc.Doc, w: World): World = { kind = kind | w }

    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }

    pub def withSprites(sprites: PxSpriteDoc.Doc, w: World): World = { sprites = sprites | w }

    /// F1 リロード: ui.json を読み直す。失敗した分は元の表示のまま残し、
    /// エラー文字列を画面に出す（直して F1 で消える）。
    pub def reloadUi(w: World): World \ Fs.FileRead =
        let (ui2, errs) = UiSpec.reloadAllWithReport(w#ui);
        let msgs = errs |> List.map(entry -> { let (rootName, msg) = entry; "${rootName}: ${msg}" });
        { ui = ui2,
          docError = if (List.isEmpty(msgs)) None else Some(String.intercalate(" / ", msgs))
          | w }
}
