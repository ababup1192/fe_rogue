// DropSimCore — フロアのドロップ抽選を「何度も回して」集計する純ロジック。
//
// IDE は fe_rogue とは別 Flix パッケージで `FloorCatalog`/`ItemScene`/`ChestScene` を
// import できないため、実機のドロップ仕様をここに写経して再現する（出典行は各関数のコメント）。
// 乱数は実機と同じ `Math.Random.randomFloat64()` を使う（seed parity は狙わない＝
// 「同分布・同アルゴリズム」を保証する。DropSimPanel が `Math.Random.runWithIO` で discharge する）。
//
// 忠実に再現するもの:
//   - 床落ち: 対象部屋 = idx 1..roomCount-1（anchor=idx0 除外, ItemScene.add L122-123）。
//             各部屋 `randomCountInRange(itemsPerRoom)` 個、各個 `pickWeighted(items)`（L130/L234-240）。
//   - 宝箱  : `willSpawn = chests非空 and randomFloat64()<0.33`（ChestScene L58-59）。
//             chests 非空なら `count=randomCountInRange(chestsPerFloor)` を常に評価（L60, 引数評価）。
//             当たれば count 回 `pickWeighted(chests)`→種別, `pickWeighted(contents[種別])`→中身（L115-118）。
//   - 抽選  : `pickWeighted` は total=Σpercent（合計≠100 の相対重み・正規化しない, FloorCatalog L132-150）、
//             `randomCountInRange` は min..max inclusive 均等・max<min→min（L158-167）。
//
// 再現しないもの（理由つき）:
//   - 床/宝箱の空きセル抽選と枯渇打ち切り。floors.json は部屋の床セル geometry を持たないため
//     セル容量は不明 → 個数は「要求(demand)個数」を主値にする。id 分布には影響しない。
mod DropSimCore {

    /// 重み付きエントリ 1 件（floors.json / chests.json の `{id, percent}`）。
    pub type alias Entry = { id = String, percent = Int32 }

    /// 個数範囲（itemsPerRoom / chestsPerFloor の `{min, max}`）。
    pub type alias Range = { min = Int32, max = Int32 }

    /// パース済みフロア設定（シミュレーションの入力）。
    pub type alias Floor = {
        items          = List[Entry],
        itemsPerRoom   = Range,
        targetRooms    = Int32,            // roomCount - 1（anchor 除外、0 未満は 0）
        chests         = List[Entry],
        chestsPerFloor = Range
    }

    /// 1 回（1 フロア生成分）のドロップ結果。
    pub type alias RunResult = {
        floorCount   = Int32,
        floorDrops   = List[String],            // 床落ち id（出現順）
        chestSpawned = Bool,
        chestDrops   = List[(String, String)]   // (宝箱種別, 中身 id)
    }

    /// N 回回した集計結果。
    pub type alias SimResult = {
        n               = Int32,
        targetRooms     = Int32,
        itemsPerRoom    = Range,
        chestsPerFloor  = Range,
        samples         = List[RunResult],
        floorCountHist  = Map[Int32, Int32],            // 1回あたり床ドロップ総数 → 回数
        floorTotal      = Int32,                        // 全ドロップ総数（頻度の分母）
        floorFreq       = Map[String, Int32],           // 床落ち id → 出現回数
        itemsEntries    = List[Entry],                  // 理論%用（id → percent）
        itemsSum        = Int32,                        // 理論%の分母（Σpercent）
        chestHits       = Int32,                        // 宝箱が出た回数（0.33 当たり）
        chestKinds      = List[Entry],                  // floor#chests（種別の重み）
        chestKindFreq   = Map[String, Int32],           // 種別 → 出現回数
        chestContents   = Map[String, List[Entry]],     // 種別 → 中身プール（理論%用）
        chestContentFreq = Map[String, Map[String, Int32]]  // 種別 → (中身 id → 回数)
    }

    // ─── JSON パース（IDE の Util.Json.Json から） ──────────────────────

    def asObj(j: Util.Json.Json): Option[Map[String, Util.Json.Json]] =
        match j {
            case Util.Json.Json.JObject(m) => Some(m)
            case _                         => None
        }

    def asStr(j: Util.Json.Json): Option[String] =
        match j {
            case Util.Json.Json.JString(s) => Some(s)
            case _                         => None
        }

    /// JObject{id, percent} を 1 件の Entry に。型不一致は None。
    def parseEntry(x: Util.Json.Json): Option[Entry] =
        match asObj(x) {
            case None => None
            case Some(m) =>
                let idO = Map.get("id", m) |> Option.flatMap(asStr);
                let pO  = Map.get("percent", m) |> Option.flatMap(NodeInspector.jsonToInt);
                match (idO, pO) {
                    case (Some(id), Some(p)) => Some(({id = id, percent = p}: Entry))
                    case _                   => None
                }
        }

    /// `[{id, percent}]` 形の JArray を Entry リストへ。型不一致の要素は捨てる。
    pub def parseEntries(jo: Option[Util.Json.Json]): List[Entry] =
        match jo {
            case Some(Util.Json.Json.JArray(xs)) => List.filterMap(parseEntry, Vector.toList(xs))
            case _                               => Nil
        }

    /// `{min, max}` を Range へ。欠落は 0。
    def parseRange(jo: Option[Util.Json.Json]): Range =
        match jo |> Option.flatMap(asObj) {
            case Some(m) =>
                let mn = Map.get("min", m) |> Option.flatMap(NodeInspector.jsonToInt) |> Option.getWithDefault(0);
                let mx = Map.get("max", m) |> Option.flatMap(NodeInspector.jsonToInt) |> Option.getWithDefault(0);
                {min = mn, max = mx}
            case None => {min = 0, max = 0}
        }

    /// フロア record JSON から Floor を取り出す。`generation.roomCount` 欠落は 1。
    pub def parseFloor(record: Util.Json.Json): Floor =
        match asObj(record) {
            case None => {items = Nil, itemsPerRoom = {min = 0, max = 0}, targetRooms = 0,
                          chests = Nil, chestsPerFloor = {min = 0, max = 0}}
            case Some(m) =>
                let roomCount = Map.get("generation", m)
                    |> Option.flatMap(asObj)
                    |> Option.flatMap(g -> Map.get("roomCount", g))
                    |> Option.flatMap(NodeInspector.jsonToInt)
                    |> Option.getWithDefault(1);
                let target = if (roomCount - 1 < 0) 0 else roomCount - 1;
                {
                    items          = parseEntries(Map.get("items", m)),
                    itemsPerRoom   = parseRange(Map.get("itemsPerRoom", m)),
                    targetRooms    = target,
                    chests         = parseEntries(Map.get("chests", m)),
                    chestsPerFloor = parseRange(Map.get("chestsPerFloor", m))
                }
        }

    /// chests.json（`{"chests": {種別: {"contents": [...]}}}`）から 種別→中身プール を作る。
    pub def parseChestContents(jo: Option[Util.Json.Json]): Map[String, List[Entry]] =
        match jo |> Option.flatMap(asObj) |> Option.flatMap(top -> Map.get("chests", top)) |> Option.flatMap(asObj) {
            case None => Map.empty()
            case Some(cm) =>
                List.foldLeft((acc, p) -> {
                    let (kind, j) = p;
                    let contents = parseEntries(asObj(j) |> Option.flatMap(km -> Map.get("contents", km)));
                    Map.insert(kind, contents, acc)
                }, Map.empty(), Map.toList(cm))
        }

    /// カタログ JSON（`{containerKey: {id: {field: "表示名", ...}}}`）から id→表示名 を作る。
    /// weapons/staves/consumables/rings は field="name"、chests は field="label" を使う。
    pub def idLabels(jsonOpt: Option[Util.Json.Json], containerKey: String, field: String): Map[String, String] =
        match jsonOpt |> Option.flatMap(asObj) |> Option.flatMap(top -> Map.get(containerKey, top)) |> Option.flatMap(asObj) {
            case None     => Map.empty()
            case Some(cm) =>
                List.foldLeft((acc, p) -> {
                    let (id, j) = p;
                    match asObj(j) |> Option.flatMap(em -> Map.get(field, em)) |> Option.flatMap(asStr) {
                        case Some(nm) => Map.insert(id, nm, acc)
                        case None     => acc
                    }
                }, Map.empty(), Map.toList(cm))
        }

    // ─── 抽選（FloorCatalog の写経） ────────────────────────────────────

    def sumPercent(entries: List[Entry]): Int32 =
        List.foldLeft((acc, e) -> acc + e#percent, 0i32, entries)

    /// FloorCatalog.pickWeighted L132-150 と同一。total=Σpercent（正規化しない）、total<=0→None。
    pub def pickWeighted(entries: List[Entry]): Option[String] \ Math.Random =
        let total = sumPercent(entries);
        if (total <= 0i32) None
        else {
            let r = Math.Random.randomFloat64() * Int32.toFloat64(total);
            pickWeightedRec(r, 0.0, entries)
        }

    def pickWeightedRec(r: Float64, acc: Float64, entries: List[Entry]): Option[String] =
        match entries {
            case Nil      => None
            case e :: rest =>
                let next = acc + Int32.toFloat64(e#percent);
                if (r < next) Some(e#id)
                else pickWeightedRec(r, next, rest)
        }

    /// FloorCatalog.randomCountInRange L158-167 と同一。min..max inclusive 均等、max<min→min。
    pub def randomCountInRange(range: Range): Int32 \ Math.Random =
        let lo = range#min;
        let hi = range#max;
        if (hi < lo) lo
        else {
            let span = hi - lo + 1i32;
            let r = Math.Random.randomFloat64();
            let idx = Float64.truncateToInt32(Float64.floor(r * Int32.toFloat64(span)));
            lo + idx
        }

    // ─── 1 回シミュレート ───────────────────────────────────────────────

    def floorDrops(rooms: Int32, range: Range, items: List[Entry], acc: List[String]):
            List[String] \ Math.Random =
        if (rooms <= 0) acc
        else {
            let n = randomCountInRange(range);
            let withRoom = pickItems(n, items, acc);
            floorDrops(rooms - 1, range, items, withRoom)
        }

    def pickItems(n: Int32, items: List[Entry], acc: List[String]): List[String] \ Math.Random =
        if (n <= 0) acc
        else match pickWeighted(items) {
            case Some(id) => pickItems(n - 1, items, id :: acc)
            case None     => pickItems(n - 1, items, acc)   // items 空 / Σ<=0 → 何も出ない
        }

    def chestDrops(count: Int32, chests: List[Entry], contents: Map[String, List[Entry]],
                    acc: List[(String, String)]): List[(String, String)] \ Math.Random =
        if (count <= 0) acc
        else match pickWeighted(chests) {
            case None       => acc   // chests Σ<=0
            case Some(kind) =>
                let pool = Map.get(kind, contents) |> Option.getWithDefault(Nil);
                match pickWeighted(pool) {
                    case Some(cid) => chestDrops(count - 1, chests, contents, (kind, cid) :: acc)
                    case None      => chestDrops(count - 1, chests, contents, acc)
                }
        }

    def simulateOnce(floor: Floor, contents: Map[String, List[Entry]]): RunResult \ Math.Random =
        let fDrops = floorDrops(floor#targetRooms, floor#itemsPerRoom, floor#items, Nil) |> List.reverse;
        // ChestScene.add の評価順を踏襲: chests 非空でのみ 0.33 を引き、count は常に引く。
        let willSpawn = (not List.isEmpty(floor#chests)) and Math.Random.randomFloat64() < 0.33;
        let count = randomCountInRange(floor#chestsPerFloor);
        let (spawned, cDrops) =
            if (willSpawn and count > 0)
                (true, chestDrops(count, floor#chests, contents, Nil) |> List.reverse)
            else (false, Nil);
        {floorCount = List.length(fDrops), floorDrops = fDrops, chestSpawned = spawned, chestDrops = cDrops}

    // ─── N 回集計 ────────────────────────────────────────────────────────

    type alias Acc = {
        samples          = List[RunResult],
        floorCountHist   = Map[Int32, Int32],
        floorTotal       = Int32,
        floorFreq        = Map[String, Int32],
        chestHits        = Int32,
        chestKindFreq    = Map[String, Int32],
        chestContentFreq = Map[String, Map[String, Int32]]
    }

    def bump(k: a, m: Map[a, Int32]): Map[a, Int32] with Order[a] =
        Map.insert(k, (Map.get(k, m) |> Option.getWithDefault(0)) + 1, m)

    def accumulate(acc: Acc, idx: Int32, sampleCount: Int32, rr: RunResult): Acc =
        let samples1 = if (idx < sampleCount) List.append(acc#samples, rr :: Nil) else acc#samples;
        let hist1 = bump(rr#floorCount, acc#floorCountHist);
        let total1 = acc#floorTotal + rr#floorCount;
        let freq1 = List.foldLeft((mp, id) -> bump(id, mp), acc#floorFreq, rr#floorDrops);
        let hits1 = if (rr#chestSpawned) acc#chestHits + 1 else acc#chestHits;
        let kindFreq1 = List.foldLeft((mp, kc) -> bump(fst(kc), mp), acc#chestKindFreq, rr#chestDrops);
        let contentFreq1 = List.foldLeft((mp, kc) -> {
            let (kind, cid) = kc;
            let inner = Map.get(kind, mp) |> Option.getWithDefault(Map.empty());
            Map.insert(kind, bump(cid, inner), mp)
        }, acc#chestContentFreq, rr#chestDrops);
        {samples = samples1, floorCountHist = hist1, floorTotal = total1, floorFreq = freq1,
         chestHits = hits1, chestKindFreq = kindFreq1, chestContentFreq = contentFreq1}

    def loop(idx: Int32, n: Int32, sampleCount: Int32, floor: Floor,
              contents: Map[String, List[Entry]], acc: Acc): Acc \ Math.Random =
        if (idx >= n) acc
        else {
            let rr = simulateOnce(floor, contents);
            loop(idx + 1, n, sampleCount, floor, contents, accumulate(acc, idx, sampleCount, rr))
        }

    /// フロア record と chests.json を N 回シミュレートして集計する。
    pub def simulate(record: Util.Json.Json, chestsJson: Option[Util.Json.Json],
                      n: Int32, sampleCount: Int32): SimResult \ Math.Random =
        let floor = parseFloor(record);
        let contents = parseChestContents(chestsJson);
        let empty: Acc = {samples = Nil, floorCountHist = Map.empty(), floorTotal = 0,
                          floorFreq = Map.empty(), chestHits = 0, chestKindFreq = Map.empty(),
                          chestContentFreq = Map.empty()};
        let acc = loop(0, n, sampleCount, floor, contents, empty);
        // floor#chests が参照する種別の中身プールだけ残す（理論%表示用）。
        let usedContents = List.foldLeft((mp, e) ->
            Map.insert(e#id, Map.get(e#id, contents) |> Option.getWithDefault(Nil), mp),
            Map.empty(), floor#chests);
        {
            n = n, targetRooms = floor#targetRooms, itemsPerRoom = floor#itemsPerRoom,
            chestsPerFloor = floor#chestsPerFloor, samples = acc#samples,
            floorCountHist = acc#floorCountHist, floorTotal = acc#floorTotal, floorFreq = acc#floorFreq,
            itemsEntries = floor#items, itemsSum = sumPercent(floor#items),
            chestHits = acc#chestHits, chestKinds = floor#chests, chestKindFreq = acc#chestKindFreq,
            chestContents = usedContents, chestContentFreq = acc#chestContentFreq
        }

    // ─── 結果の整形（純粋・テスト可能） ──────────────────────────────────

    def fmt1(x: Float64): String =
        let tenths = Float64.floor(x * 10.0 + 0.5) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let whole = tenths / 10;
        let frac = tenths - whole * 10;
        "${whole}.${frac}"

    def pct(part: Int32, whole: Int32): Float64 =
        if (whole <= 0) 0.0 else 100.0 * Int32.toFloat64(part) / Int32.toFloat64(whole)

    def bar(p: Float64, width: Int32): String =
        let cells = Float64.floor(p * Int32.toFloat64(width) / 100.0) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let c = if (cells < 0) 0 else if (cells > width) width else cells;
        String.repeat(c, "█")

    /// percent 降順に並べた entries（理論%の表示順）。
    def sortByPercentDesc(entries: List[Entry]): List[Entry] =
        List.sortBy(e -> 0i32 - e#percent, entries)

    /// 出現回数降順に並べた (key, count)。
    def sortByCountDesc(m: Map[String, Int32]): List[(String, Int32)] =
        Map.toList(m) |> List.sortBy(p -> 0i32 - snd(p))

    def rangeStr(r: Range): String = "${r#min}..${r#max}"

    def expectedCount(r: Range): Float64 =
        if (r#max < r#min) Int32.toFloat64(r#min)
        else (Int32.toFloat64(r#min) + Int32.toFloat64(r#max)) / 2.0

    /// 集計結果を等幅テキストに整形する。`labelOf` は id → 人間向け表示（例 "てつのやり(武器)"、
    /// 未解決なら id そのもの）。床アイテム・宝箱種別・中身すべてこの表示名で出す。
    pub def formatResult(floorId: String, r: SimResult, labelOf: String -> String): String =
        let lines =
            List.append(headerLines(floorId, r, labelOf),
                List.append(sampleLines(r, labelOf),
                    List.append(floorAggLines(r, labelOf), chestAggLines(r, labelOf))));
        String.intercalate("\n", lines)

    def headerLines(floorId: String, r: SimResult, labelOf: String -> String): List[String] =
        let floorExp = Int32.toFloat64(r#targetRooms) * expectedCount(r#itemsPerRoom);
        "=== ドロップ試算: ${floorId} ===  N=${r#n}" ::
        "床: 対象部屋=${r#targetRooms} (roomCount-anchor) / itemsPerRoom=${rangeStr(r#itemsPerRoom)} / items Σpercent=${r#itemsSum}(相対重み)" ::
        "    期待床ドロップ数 = ${r#targetRooms} × ${fmt1(expectedCount(r#itemsPerRoom))} = ${fmt1(floorExp)}（要求個数。実機はセル数で打ち切られうる）" ::
        "宝箱: chests=${chestKindsLabel(r, labelOf)} / 出現率0.33 / chestsPerFloor=${rangeStr(r#chestsPerFloor)}" ::
        "注: 個数はdemand(要求)。セル枯渇による打ち切りは未モデル化（通常セルは潤沢で近似良好）。出現率は実配置率ではない。" ::
        Nil

    def chestKindsLabel(r: SimResult, labelOf: String -> String): String =
        if (List.isEmpty(r#chestKinds)) "なし"
        else r#chestKinds |> List.map(e -> "${labelOf(e#id)}:${e#percent}") |> String.intercalate(",")

    def sampleLines(r: SimResult, labelOf: String -> String): List[String] =
        let header = "" :: "── サンプル(最初の${List.length(r#samples)}回) ──" :: Nil;
        List.append(header, sampleLinesRec(r#samples, 0, labelOf))

    def sampleLinesRec(samples: List[RunResult], i: Int32, labelOf: String -> String): List[String] =
        match samples {
            case Nil         => Nil
            case rr :: rest => sampleLine(i, rr, labelOf) :: sampleLinesRec(rest, i + 1, labelOf)
        }

    def sampleLine(i: Int32, rr: RunResult, labelOf: String -> String): String =
        let floorStr =
            if (List.isEmpty(rr#floorDrops)) "なし"
            else tallyList(rr#floorDrops) |> List.map(p -> "${labelOf(fst(p))}×${snd(p)}") |> String.intercalate(", ");
        let chestStr =
            if (not rr#chestSpawned) "なし(0.33外れ)"
            else if (List.isEmpty(rr#chestDrops)) "出現(中身なし)"
            else rr#chestDrops |> List.map(kc -> "[${labelOf(fst(kc))}] ${labelOf(snd(kc))}") |> String.intercalate(", ");
        "[${i + 1}] 床(計${rr#floorCount}): ${floorStr}   宝箱: ${chestStr}"

    /// id リストを出現順を保ったまま (id, 個数) に畳む。
    def tallyList(ids: List[String]): List[(String, Int32)] =
        List.foldLeft((acc, id) ->
            if (List.exists(p -> fst(p) == id, acc))
                List.map(p -> if (fst(p) == id) (fst(p), snd(p) + 1) else p, acc)
            else List.append(acc, (id, 1) :: Nil),
            Nil, ids)

    def floorAggLines(r: SimResult, labelOf: String -> String): List[String] =
        let avg = if (r#n <= 0) 0.0 else Int32.toFloat64(r#floorTotal) / Int32.toFloat64(r#n);
        let histHeader = "" :: "── N=${r#n} 集計 ──" :: "[床 個数分布]  平均=${fmt1(avg)}/回" :: Nil;
        let histRows = Map.toList(r#floorCountHist)
            |> List.sortBy(p -> fst(p))
            |> List.map(p -> {
                let (cnt, occ) = p;
                "  ${padInt(cnt, 3)}個 ${bar(pct(occ, r#n), 20)} ${occ} (${fmt1(pct(occ, r#n))}%)"
            });
        let freqHeader = "[床アイテム別頻度]  実測% / 理論%(percent/${r#itemsSum})" :: Nil;
        let freqRows = sortByPercentDesc(r#itemsEntries) |> List.map(e -> {
            let observed = Map.get(e#id, r#floorFreq) |> Option.getWithDefault(0);
            let obsPct = "${fmt1(pct(observed, r#floorTotal))}%";
            "  ${padStr(labelOf(e#id), 26)} ${padStr(obsPct, 7)} / ${fmt1(pct(e#percent, r#itemsSum))}%(${e#percent})"
        });
        List.append(histHeader, List.append(histRows, List.append(freqHeader, freqRows)))

    def chestAggLines(r: SimResult, labelOf: String -> String): List[String] =
        if (List.isEmpty(r#chestKinds)) Nil
        else {
            let hitHeader = "" :: "[宝箱]  出現 ${r#chestHits}/${r#n} (${fmt1(pct(r#chestHits, r#n))}% ≈ 0.33)" :: Nil;
            let kindTotal = List.foldLeft((a, p) -> a + snd(p), 0, Map.toList(r#chestKindFreq));
            let kindRows =
                if (List.length(r#chestKinds) <= 1) Nil
                else "  種別内訳:" :: (sortByCountDesc(r#chestKindFreq) |> List.map(p ->
                    "    ${labelOf(fst(p))} ${snd(p)} (${fmt1(pct(snd(p), kindTotal))}%)"));
            // 種別ごとの中身頻度（出た宝箱内の割合 / 理論=percent/Σcontents）。
            let contentBlocks = r#chestKinds |> List.flatMap(ke -> {
                let kind = ke#id;
                let pool = Map.get(kind, r#chestContents) |> Option.getWithDefault(Nil);
                let poolSum = List.foldLeft((a, e) -> a + e#percent, 0, pool);
                let inner = Map.get(kind, r#chestContentFreq) |> Option.getWithDefault(Map.empty());
                let innerTotal = List.foldLeft((a, p) -> a + snd(p), 0, Map.toList(inner));
                let rows = sortByPercentDesc(pool) |> List.map(e -> {
                    let obs = Map.get(e#id, inner) |> Option.getWithDefault(0);
                    let obsPct = "${fmt1(pct(obs, innerTotal))}%";
                    "    ${padStr(labelOf(e#id), 24)} ${padStr(obsPct, 7)} / ${fmt1(pct(e#percent, poolSum))}%"
                });
                "  [${labelOf(kind)}] 中身頻度 実測/理論(percent/${poolSum})" :: rows
            });
            List.append(hitHeader, List.append(kindRows, contentBlocks))
        }

    // 右詰め・左詰めの簡易パディング（等幅表示の桁そろえ）。
    def spaces(n: Int32): String = String.repeat(n, " ")

    def padInt(v: Int32, width: Int32): String =
        let s = "${v}";
        let pad = width - String.length(s);
        if (pad <= 0) s else "${spaces(pad)}${s}"

    def padStr(s: String, width: Int32): String =
        let pad = width - String.length(s);
        if (pad <= 0) s else "${s}${spaces(pad)}"
}
