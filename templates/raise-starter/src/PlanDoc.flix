// PlanDoc — raise.plan.json（育成の中身の表: 行動・イベント・結末・パラメータ名）の宣言層。
// 「毎日えらべる行動」「ときどき起きるイベント」「発表会の結末」を全部 rows（表）で持つ。
// 行を足せば選択肢や結末が増える。プレイヤーの目に入る文言（行動名・イベント文・結末文）は
// すべてここ（コードに直書きしない）。伸ばす・抽選する・結末を選ぶの規則はコード（World）側。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
//
// パラメータは 3 つ固定（power/spirit/skill）。行動もイベントもこの 3 つの増減を持つので、
// 「3 つの数の組」を Stats という 1 つの型に名付けて共有する（伸びも現在値も同じ形）。
mod PlanDoc {
    use Util.Json.Json

    /// 3 パラメータの組。行動の伸び幅・イベントの増減・現在の育ち具合、どれもこの形。
    ///   power  … たいりょく    spirit … きあい    skill … わざ
    pub type alias Stats = { power = Int32, spirit = Int32, skill = Int32 }

    pub def zeroStats(): Stats = { power = 0, spirit = 0, skill = 0 }

    /// 2 つの Stats を足す（現在値 + 伸び / 現在値 + イベントの増減）。
    pub def addStats(a: Stats, b: Stats): Stats =
        { power = a#power + b#power, spirit = a#spirit + b#spirit, skill = a#skill + b#skill }

    /// 3 パラメータの合計（結末のしきい値と比べる値）。
    pub def total(s: Stats): Int32 = s#power + s#spirit + s#skill

    /// パラメータ 1 つの名前。id はコードが参照する（いまは表示用に label だけ使う）。
    pub type alias Stat = { id = String, label = String }

    /// 毎日えらべる行動。label = 画面に出す名前、note = 一言説明、gain = 3 パラメータの伸び幅。
    pub type alias Action = { label = String, note = String, gain = Stats }

    /// ときどき起きるイベント。text = 起きたとき出す文、delta = 3 パラメータの増減（マイナス可）、
    /// weight = 出やすさの重み（大きいほど選ばれやすい）。
    pub type alias Event = { label = String, text = String, delta = Stats, weight = Int32 }

    /// 発表会の結末。text = 結果の文、threshold = この結末になる合計値の下限。
    pub type alias Ending = { label = String, text = String, threshold = Int32 }

    /// 育成の中身の全体。title / subtitle = 表紙の文言。
    pub type alias Doc = {
        version = Int32,
        title = String,
        subtitle = String,
        stats = List[Stat],
        actions = List[Action],
        events = List[Event],
        endings = List[Ending]
    }

    pub def path(): String = "assets/raise.plan.json"

    /// コード側の既定値。表が読めなくても「読んで学べる最小の育成」でゲームは必ず起動する。
    pub def defaults(): Doc =
        { version = 1,
          title = "そだてゲーム",
          subtitle = "発表会まで、毎日ひとつえらぶ",
          stats =
              { id = "power",  label = "たいりょく" }
           :: { id = "spirit", label = "きあい" }
           :: { id = "skill",  label = "わざ" }
           :: Nil,
          actions =
              { label = "れんしゅう", note = "わざが大きく伸びる",             gain = { power = 2, spirit = 1, skill = 6 } }
           :: { label = "きんとれ",   note = "たいりょくが大きく伸びる",       gain = { power = 6, spirit = 1, skill = 1 } }
           :: { label = "やすむ",     note = "きあいが戻る（ほかは伸びない）", gain = { power = 0, spirit = 7, skill = 0 } }
           :: { label = "しあい",     note = "全部そこそこ伸びる",             gain = { power = 3, spirit = 2, skill = 3 } }
           :: Nil,
          events =
              { label = "ちょうし good", text = "きょうは のっている！",       delta = { power = 3, spirit = 5, skill = 3 }, weight = 3 }
           :: { label = "ねぶそく",      text = "ねぶそくで きあいが さがった", delta = { power = 0, spirit = -6, skill = 0 }, weight = 2 }
           :: { label = "ひらめき",      text = "こつを つかんだ！",           delta = { power = 0, spirit = 2, skill = 6 }, weight = 2 }
           :: Nil,
          endings =
              { label = "きん", text = "かんぺきな はっぴょうかい！",       threshold = 150 }
           :: { label = "ぎん", text = "よく そだった。おおきな はくしゅ",   threshold = 90 }
           :: { label = "どう", text = "むずかしかった。また あした",       threshold = 0 }
           :: Nil }

    // ── 表を引く小物（範囲外・空は fail-open で素直に倒す） ──

    /// えらべる行動の数（メニューの行数）。
    pub def actionCount(doc: Doc): Int32 = List.length(doc#actions)

    /// n 番目（0 始まり）の行動。範囲外は「伸びない行動」に倒す（詰まない）。
    pub def actionAt(n: Int32, doc: Doc): Action =
        List.nth(n, doc#actions)
            |> Option.getWithDefault({ label = "", note = "", gain = zeroStats() })

    /// n 番目のパラメータの名前（棒のラベル）。範囲外は空文字（View がその棒を描かないだけ）。
    pub def statLabel(n: Int32, doc: Doc): String =
        List.nth(n, doc#stats) |> Option.map(s -> s#label) |> Option.getWithDefault("")

    /// 合計値 total に見合う結末を選ぶ。threshold を「大きい順」に見て最初に届いたものを返す。
    /// どれにも届かなければ（endings が空なら）「また あした」の既定へ倒す（詰まない）。
    pub def endingFor(total: Int32, doc: Doc): Ending =
        doc#endings
            |> List.sortBy(e -> -e#threshold)                 // 大きいしきい値から見る
            |> List.find(e -> total >= e#threshold)
            |> Option.getWithDefault({ label = "", text = "また あした", threshold = 0 })

    // ══════════════════════════════════════════════════════
    // JSON 読み（fail-open。rows は「オブジェクトの配列」を 1 行ずつ拾う）
    // ══════════════════════════════════════════════════════

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          title = JsonCodec.stringOr("title", d#title, root),
          subtitle = JsonCodec.stringOr("subtitle", d#subtitle, root),
          stats = rowsOr(d#stats, "stats", statFromJson, root),
          actions = rowsOr(d#actions, "actions", actionFromJson, root),
          events = rowsOr(d#events, "events", eventFromJson, root),
          endings = rowsOr(d#endings, "endings", endingFromJson, root) }

    /// 「オブジェクトの配列」を 1 行ずつ拾う。形が違う・行が壊れているときは既定へ倒す。
    def rowsOr(fallback: List[a], key: String, rowOf: Json -> Option[a], obj: Map[String, Json]): List[a] =
        Map.get(key, obj)
            |> Option.flatMap(JsonCodec.decodeList(rowOf))
            |> Option.getWithDefault(fallback)

    /// 1 行から 3 パラメータの組を拾う（欠けたパラメータは 0）。行動の伸びもイベントの増減も同じ。
    def statsFromRow(obj: Map[String, Json]): Stats =
        { power = JsonCodec.intOr("power", 0, obj),
          spirit = JsonCodec.intOr("spirit", 0, obj),
          skill = JsonCodec.intOr("skill", 0, obj) }

    def statFromJson(json: Json): Option[Stat] =
        JsonCodec.expectObject(json) |> Option.map(obj ->
            { id = JsonCodec.stringOr("id", "", obj),
              label = JsonCodec.stringOr("label", "", obj) })

    def actionFromJson(json: Json): Option[Action] =
        JsonCodec.expectObject(json) |> Option.map(obj ->
            { label = JsonCodec.stringOr("label", "", obj),
              note = JsonCodec.stringOr("note", "", obj),
              gain = statsFromRow(obj) })

    def eventFromJson(json: Json): Option[Event] =
        JsonCodec.expectObject(json) |> Option.map(obj ->
            { label = JsonCodec.stringOr("label", "", obj),
              text = JsonCodec.stringOr("text", "", obj),
              delta = statsFromRow(obj),
              weight = JsonCodec.intOr("weight", 0, obj) })

    def endingFromJson(json: Json): Option[Ending] =
        JsonCodec.expectObject(json) |> Option.map(obj ->
            { label = JsonCodec.stringOr("label", "", obj),
              text = JsonCodec.stringOr("text", "", obj),
              threshold = JsonCodec.intOr("threshold", 0, obj) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
