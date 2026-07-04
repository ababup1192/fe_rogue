// SnapshotSite — カタログ（エントリ列）を静的なマルチページ HTML サイトへ変換する汎用生成器。
//
// この生成器はゲームの内容を一切知らない。入力は「名前・説明・シナリオ・タグ・画像拡張子・
// 表示幅・（未生成時の案内）」だけを持つ構造的レコード（Item）で、それを次の 3 種類のページへ
// 射影する:
//   - index.html        : シナリオごとの代表サムネ + 件数 + 説明を並べたハブ（末尾にタグ目次）
//   - page_<sc>.html    : シナリオ別ギャラリー（← index パンくず + 前後シナリオへの導線つき）。
//                         ページ内は Item のデータだけから決まる 3 節に分かれる: ext が "gif" の
//                         項目は「操作フロー」、タグに "edge-case" を含む項目は「エッジケース」、
//                         それ以外は「基本状態」。シナリオ名や項目名を見て分岐することはない。
//   - tag_<tag>.html    : そのタグを持つ項目をシナリオ横断で集めたページ（← index パンくずのみ）。
// 画像ファイル名は `<name>.<ext>` で一意に導く（エントリ名がファイル名の正）。これが唯一の
// 「エントリ↔ファイル」規約で、それ以外にゲーム固有の知識を持たない。
//
// 依存は Flix 標準ライブラリ + Fs 効果 + java.io.File のみ。ゲーム固有の型を import しないため、
// そのまま engine 側の汎用パーツへ吸い出せる。品質要素（image-rendering: pixelated / Retina 前提の
// CSS 幅 / ダーク配色）は生成 HTML に組み込む。
mod SnapshotSite {
    import java.io.File

    /// サイト全体の設定。1 サイト 1 レコードで名前渡しする。
    pub type alias Config = {
        outDir   = String,  // 出力ディレクトリ（index.html / page_*.html / 画像が同居する）
        title    = String,  // ハブ見出し兼 <title>
        cssScale = Int32    // 画像 CSS 幅 = 実ピクセル幅 ÷ cssScale（Retina 2x で補間を消すなら 2）
    }

    /// カタログ 1 項目の表示情報（生成器が受け取る唯一の入力形）。
    pub type alias Item = {
        name         = String,         // ファイル basename・コピー用コード表記・img alt
        desc         = String,         // 1 行説明
        scenario     = String,         // 所属シナリオ（ページの束ね。表示順は宣言順）
        tags         = List[String],   // 分類タグ。tag_<tag>.html への横断リンクになる。"edge-case" は
                                        // シナリオページ内でエッジケース節に振り分けられる予約タグ
        ext          = String,         // 画像拡張子（"png" / "gif"）→ ファイル名 = name.ext
        pxWidth      = Int32,          // 画像の実ピクセル幅
        generateHint = Option[String], // Some かつ画像が未生成なら img の代わりにこの案内を出す
        lint         = LintBadge       // 幾何リンタの結果（構造データ。生成器はこれを見てバッジを描くだけ）
    }

    /// カード 1 枚に添える幾何リンタの結果（ゲーム非依存の構造データ）。
    /// `checked`: リンタを走らせたか（未検査＝GIF 等はバッジを出さない）。
    /// `findingCount`: 有効（非抑制）Finding 数。0 かつ検査済みなら ✓。
    /// `suppressedCount`: 抑制タグで意図的に許した Finding 数（別掲する）。
    /// `details`: 各 Finding の説明（折りたたみで見せる。有効・抑制の両方を含む）。
    pub type alias LintBadge = {
        checked         = Bool,
        findingCount    = Int32,
        suppressedCount = Int32,
        details         = List[String]
    }

    /// 未検査バッジ（GIF など lint を通していない項目の既定）。
    pub def noLint(): LintBadge = {checked = false, findingCount = 0, suppressedCount = 0, details = Nil}

    // ════════════════════════════════════════════════════════
    // 生成エントリポイント
    // ════════════════════════════════════════════════════════

    /// index.html（ハブ）・各 page_<scenario>.html・各 tag_<tag>.html を outDir に書き出す。
    /// シナリオはエントリの初出順に並べ、その順序がハブのカード順・前後導線の順序になる。
    /// タグも同じく初出順に列挙し、それぞれ横断ページを 1 枚ずつ生成する。
    pub def generate(config: Config, items: List[Item]): Unit \ IO + Fs.FileWrite =
        let scenarios = scenariosOf(items);
        let tags = tagsOf(items);
        writeFile("${config#outDir}/index.html", indexHtml(config, scenarios, tags, items));
        List.forEach(scenario ->
            writeFile("${config#outDir}/page_${scenario}.html", pageHtml(config, scenario, scenarios, items)),
            scenarios);
        List.forEach(tag ->
            writeFile("${config#outDir}/tag_${tag}.html", tagPageHtml(config, tag, items)),
            tags)

    /// エントリ列に現れるシナリオを初出順（重複なし）で返す。
    def scenariosOf(items: List[Item]): List[String] =
        List.foldLeft((acc, item) ->
            if (List.memberOf(item#scenario, acc)) acc else List.append(acc, item#scenario :: Nil),
            (Nil: List[String]), items)

    /// エントリ列に現れるタグを初出順（重複なし）で返す（シナリオをまたいで集約）。
    def tagsOf(items: List[Item]): List[String] =
        List.foldLeft((acc, item) ->
            List.foldLeft((acc2, tag) ->
                if (List.memberOf(tag, acc2)) acc2 else List.append(acc2, tag :: Nil),
                acc, item#tags),
            (Nil: List[String]), items)

    /// あるシナリオに属する項目を宣言順で返す。
    def itemsOf(scenario: String, items: List[Item]): List[Item] =
        List.filter(item -> item#scenario == scenario, items)

    /// あるタグを持つ項目をカタログ宣言順（シナリオ横断）で返す。
    def itemsWithTag(tag: String, items: List[Item]): List[Item] =
        List.filter(item -> List.memberOf(tag, item#tags), items)

    // ════════════════════════════════════════════════════════
    // ページ内節（Item のデータだけから決まる。シナリオ名は見ない）
    // ════════════════════════════════════════════════════════

    /// シナリオページ内の節。ext と tags という Item 自身の構造だけで決まるので、新しいゲーム機能を
    /// 足しても分岐を増やす必要がない。
    enum Section with Eq {
        case Basic     // 基本状態: 静止画で、エッジケースの印がないもの
        case EdgeCase  // エッジケース: タグに "edge-case" を含むもの
        case Flow      // 操作フロー: ext が "gif" のもの
    }

    /// 表示順（基本状態 → エッジケース → 操作フロー）。
    def sectionOrder(): List[Section] = Section.Basic :: Section.EdgeCase :: Section.Flow :: Nil

    /// 項目 1 個がどの節に属するか。ext/tags だけを見る（ゲーム固有の知識を持ち込まない）。
    def sectionOf(item: Item): Section =
        if (item#ext == "gif")
            Section.Flow
        else if (List.memberOf("edge-case", item#tags))
            Section.EdgeCase
        else
            Section.Basic

    /// 節の見出しラベル。
    def sectionLabel(section: Section): String = match section {
        case Section.Basic    => "基本状態"
        case Section.EdgeCase => "エッジケース"
        case Section.Flow     => "操作フロー"
    }

    // ════════════════════════════════════════════════════════
    // index.html（ハブ：シナリオカード一覧）
    // ════════════════════════════════════════════════════════

    /// 各シナリオを 1 枚のカードにする（代表サムネ＝そのシナリオの先頭項目・件数・説明）。末尾に
    /// タグ目次（tag_<tag>.html への横断リンク集）を添える。
    def indexHtml(config: Config, scenarios: List[String], tags: List[String], items: List[Item]): String \ IO =
        let cards = scenarios
            |> List.map(scenario -> scenarioCard(config, scenario, items))
            |> String.unlines;
        "<!doctype html><meta charset=\"utf-8\"><title>${config#title}</title>\n"
            + styleBlock()
            + "<h1>${config#title}</h1>\n"
            + "<p class=\"hint\">ゲーム機能ごとにページを分けています。カードを開くと基本状態/エッジケース/操作フローを"
            + "一覧できます。各ページの黄色いコード表記がスナップショット名（不具合報告はこの名前で・クリックでコピー）。</p>\n"
            + "<main class=\"hub\">\n${cards}\n</main>\n"
            + tagIndexHtml(tags)

    /// シナリオカード 1 枚。先頭項目を代表サムネにし、件数バッジと説明を添えて page へリンクする。
    def scenarioCard(config: Config, scenario: String, items: List[Item]): String \ IO =
        let inScenario = itemsOf(scenario, items);
        let count = List.length(inScenario);
        match List.head(inScenario) {
            case None        => ""
            case Some(first) =>
                let cssW = first#pxWidth / config#cssScale;
                "  <a class=\"scenario\" href=\"page_${scenario}.html\" style=\"width:${cssW}px\">"
                    + "<div class=\"scenario-head\"><span class=\"scenario-name\">${scenario}</span>"
                    + "<span class=\"count\">${count}</span></div>"
                    + thumbHtml(config, first)
                    + "<span class=\"desc\">${first#desc}</span></a>"
        }

    /// index 末尾のタグ目次。各タグを tag_<tag>.html へのリンクにするだけの薄い一覧（0 件なら空）。
    def tagIndexHtml(tags: List[String]): String =
        if (List.isEmpty(tags))
            ""
        else
            "<h2 class=\"section\">タグ</h2>\n<p class=\"tag-index\">"
                + (tags |> List.map(tagLinkHtml) |> String.intercalate(" "))
                + "</p>\n"

    // ════════════════════════════════════════════════════════
    // page_<scenario>.html（シナリオ別ギャラリー）
    // ════════════════════════════════════════════════════════

    /// 1 シナリオのギャラリー。パンくず（← index）＋前後シナリオ導線＋節ごと（基本状態/エッジケース/
    /// 操作フロー）に分けた項目カードを並べる。節の判定は sectionOf（Item の ext/tags のみ参照）。
    def pageHtml(config: Config, scenario: String, scenarios: List[String], items: List[Item]): String \ IO =
        let inScenario = itemsOf(scenario, items);
        let sections = sectionOrder()
            |> List.map(section -> sectionHtml(config, section, inScenario))
            |> List.filter(html -> html != "")
            |> String.unlines;
        "<!doctype html><meta charset=\"utf-8\"><title>${config#title} — ${scenario}</title>\n"
            + styleBlock()
            + "<nav class=\"crumbs\"><a href=\"index.html\">← index</a>"
            + neighborLinks(scenario, scenarios)
            + "</nav>\n"
            + "<h1>${scenario}</h1>\n"
            + "<p class=\"hint\">黄色のコード表記がスナップショット名（不具合報告はこの名前で）。クリックでコピー。"
            + "タグはクリックで機能横断ページへ。</p>\n"
            + sections

    /// 1 節ぶんの見出し + カード列。その節に属する項目がなければ何も出さない。
    def sectionHtml(config: Config, section: Section, items: List[Item]): String \ IO =
        let inSection = List.filter(item -> sectionOf(item) == section, items);
        if (List.isEmpty(inSection))
            ""
        else
            let cards = inSection |> List.map(item -> itemCard(config, false, item)) |> String.unlines;
            "<h2 class=\"section\">${sectionLabel(section)}</h2>\n<main>\n${cards}\n</main>\n"

    // ════════════════════════════════════════════════════════
    // tag_<tag>.html（タグ横断ページ）
    // ════════════════════════════════════════════════════════

    /// あるタグを持つ項目をシナリオ横断で 1 ページに並べる。各カードは自分の所属シナリオページへの
    /// リンクを添える（scenario リンクは showScenarioLink=true で itemCard に出させる）。
    def tagPageHtml(config: Config, tag: String, items: List[Item]): String \ IO =
        let matching = itemsWithTag(tag, items);
        let cards = matching |> List.map(item -> itemCard(config, true, item)) |> String.unlines;
        let count = List.length(matching);
        "<!doctype html><meta charset=\"utf-8\"><title>${config#title} — #${tag}</title>\n"
            + styleBlock()
            + "<nav class=\"crumbs\"><a href=\"index.html\">← index</a></nav>\n"
            + "<h1>#${tag}</h1>\n"
            + "<p class=\"hint\">タグ「${tag}」を持つ項目をゲーム機能横断で表示（${count} 件）。"
            + "カード内の「in ...」がその項目の所属ページ。</p>\n"
            + "<main>\n${cards}\n</main>\n"

    /// 前後シナリオへのリンク（端では出さない）。
    def neighborLinks(scenario: String, scenarios: List[String]): String =
        let indexed = List.zipWithIndex(scenarios);
        let idx = indexed |> List.findLeft(pair -> snd(pair) == scenario) |> Option.map(fst);
        match idx {
            case None    => ""
            case Some(i) =>
                let link = (label, target) -> match target {
                    case None    => ""
                    case Some(t) => " <a href=\"page_${t}.html\">${label} ${t}</a>"
                };
                link("◀", List.nth(i - 1, scenarios)) + link("▶", List.nth(i + 1, scenarios))
        }

    // ════════════════════════════════════════════════════════
    // 画像・カード断片
    // ════════════════════════════════════════════════════════

    /// 項目 1 個のカード（名前コード＝クリックでコピー ＋ 説明 ＋（任意で）所属シナリオへのリンク
    /// ＋ タグ（クリックでタグ横断ページへ） ＋ 画像/案内）。showScenarioLink はタグ横断ページなど
    /// 項目の所属が自明でない文脈で true にする（シナリオページ自身では冗長なので false）。
    def itemCard(config: Config, showScenarioLink: Bool, item: Item): String \ IO =
        let cssW = item#pxWidth / config#cssScale;
        let scenarioLink =
            if (showScenarioLink)
                " <a class=\"scenario-link\" href=\"page_${item#scenario}.html#${item#name}\">in ${item#scenario}</a>"
            else "";
        "  <figure id=\"${item#name}\" style=\"width:${cssW}px\"><figcaption>"
            + "<code onclick=\"navigator.clipboard&&navigator.clipboard.writeText('${item#name}')\" "
            + "title=\"クリックで名前をコピー\">${item#name}</code>" + scenarioLink
            + "<span class=\"desc\">${item#desc}</span>"
            + tagsHtml(item#tags)
            + lintHtml(item#lint)
            + "</figcaption>" + mediaHtml(config, item) + "</figure>"

    /// lint バッジ（✓ or ⚠件数）＋ ⚠ の詳細を折りたたみ表示。未検査なら何も出さない。
    def lintHtml(badge: LintBadge): String =
        if (not badge#checked)
            ""
        else if (badge#findingCount == 0 and badge#suppressedCount == 0)
            "<span class=\"lint ok\">✓ lint</span>"
        else {
            let suppText = if (badge#suppressedCount > 0) " <span class=\"lint sup\">抑制 ${badge#suppressedCount}</span>" else "";
            let head =
                if (badge#findingCount > 0)
                    "<span class=\"lint warn\">⚠ ${badge#findingCount}</span>${suppText}"
                else
                    "<span class=\"lint ok\">✓ lint</span>${suppText}";
            let items = badge#details |> List.map(d -> "<li>${d}</li>") |> String.unlines;
            "<details class=\"lint-detail\"><summary>${head}</summary><ul>${items}</ul></details>"
        }

    /// 本体画像。画像があれば img、無くて generateHint があればその案内、無ければ（生成後に出る）img。
    def mediaHtml(config: Config, item: Item): String \ IO =
        let file = "${item#name}.${item#ext}";
        if (fileExists("${config#outDir}/${file}"))
            "<img src=\"${file}\" alt=\"${item#name}\">"
        else match item#generateHint {
            case Some(hint) => "<p class=\"hint missing\">${hint}</p>"
            case None       => "<img src=\"${file}\" alt=\"${item#name}\">"
        }

    /// ハブの代表サムネ。未生成なら小さなプレースホルダを出す（案内文はページ側で見せる）。
    def thumbHtml(config: Config, item: Item): String \ IO =
        let file = "${item#name}.${item#ext}";
        if (fileExists("${config#outDir}/${file}"))
            "<img src=\"${file}\" alt=\"${item#name}\">"
        else "<div class=\"placeholder\">（未生成）</div>"

    /// タグ列（`#tag` を空白区切り・各タグは tag_<tag>.html へのリンク）。空なら何も出さない。
    def tagsHtml(tags: List[String]): String =
        if (List.isEmpty(tags)) ""
        else "<span class=\"tags\">" + (tags |> List.map(tagLinkHtml) |> String.intercalate(" ")) + "</span>"

    /// 1 タグぶんのリンク（`#tag` 表記で tag_<tag>.html を指す）。
    def tagLinkHtml(tag: String): String = "<a class=\"tag\" href=\"tag_${tag}.html\">#${tag}</a>"

    /// path のファイルが存在するか（generateHint / プレースホルダの分岐に使う）。
    def fileExists(path: String): Bool \ IO = (new File(path)).exists()

    /// index.html への書き出し（Fs.WriteFile を Fs.FileWrite として伝播させる）。
    def writeFile(path: String, content: String): Unit \ Fs.FileWrite =
        run { discard Fs.WriteFile.write({str = content}, path) } with Fs.WriteFile.runWithFileWrite

    // ════════════════════════════════════════════════════════
    // 共有スタイル（ダーク配色・ドット絵を補間なしで焼き付ける）
    // ════════════════════════════════════════════════════════

    /// index / page で共有する <style>。ドット絵は image-rendering: pixelated で補間しない。
    def styleBlock(): String =
        "<style>body{background:#1a1f2b;color:#cdd5e6;font-family:sans-serif;margin:16px}\n"
            + "a{color:#9cc0ff}h1{font-size:18px}\n"
            + "p.hint{font-size:12px;color:#8c99ad;margin:0 0 16px}\n"
            + "p.hint.missing{margin:6px 0 0}\n"
            + "nav.crumbs{font-size:13px;margin-bottom:8px;display:flex;gap:14px;flex-wrap:wrap}\n"
            + "main{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start}\n"
            + "figure{margin:0;background:#0d1220;border:1px solid #2a3445;border-radius:6px;padding:8px}\n"
            + "figcaption{margin-bottom:6px;display:flex;flex-direction:column;gap:3px}\n"
            + "figcaption code{font-size:14px;font-weight:700;color:#ffd479;background:#241c07;\n"
            + "  padding:2px 6px;border-radius:4px;align-self:flex-start;cursor:pointer;\n"
            + "  font-family:ui-monospace,Menlo,Consolas,monospace}\n"
            + "figcaption .desc{font-size:12px;color:#9cc0ff}\n"
            + ".tags{font-size:11px;color:#6f7d94;display:flex;gap:6px;flex-wrap:wrap}\n"
            + "a.tag{color:#6f7d94;text-decoration:none}a.tag:hover{color:#9cc0ff;text-decoration:underline}\n"
            + "a.scenario-link{font-size:11px;color:#6f7d94;align-self:flex-start}\n"
            + "img{display:block;image-rendering:pixelated;width:100%;height:auto;background:#000}\n"
            + ".placeholder{display:flex;align-items:center;justify-content:center;height:80px;\n"
            + "  color:#6f7d94;font-size:12px;background:#000;border:1px dashed #2a3445}\n"
            + "a.scenario{display:block;text-decoration:none;background:#0d1220;border:1px solid #2a3445;\n"
            + "  border-radius:6px;padding:8px}\n"
            + "a.scenario:hover{border-color:#4a6fb0}\n"
            + ".scenario-head{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px}\n"
            + ".scenario-name{font-size:14px;font-weight:700;color:#ffd479}\n"
            + ".count{font-size:12px;color:#8c99ad;background:#1a2332;border-radius:10px;padding:1px 8px}\n"
            + "a.scenario .desc{display:block;font-size:12px;color:#9cc0ff;margin-top:6px}\n"
            + "h2.section{font-size:13px;color:#8c99ad;margin:18px 0 8px;text-transform:uppercase;\n"
            + "  letter-spacing:.04em;border-bottom:1px solid #2a3445;padding-bottom:4px}\n"
            + "h2.section:first-of-type{margin-top:4px}\n"
            + "p.tag-index{display:flex;gap:10px;flex-wrap:wrap;font-size:12px}\n"
            + "span.lint{font-size:11px;border-radius:4px;padding:1px 6px;align-self:flex-start}\n"
            + "span.lint.ok{color:#7bd88f;background:#123020}\n"
            + "span.lint.warn{color:#ffce6b;background:#3a2a08}\n"
            + "span.lint.sup{color:#8c99ad;background:#1a2332}\n"
            + "details.lint-detail{align-self:flex-start}details.lint-detail summary{cursor:pointer;list-style:none}\n"
            + "details.lint-detail ul{margin:4px 0 0;padding-left:16px;font-size:11px;color:#c9a24a}\n"
            + "details.lint-detail li{margin:2px 0}\n"
            + "figure:target{border-color:#ffd479}</style>\n"
}
