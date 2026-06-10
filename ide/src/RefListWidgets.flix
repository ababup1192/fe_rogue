// RefListWidgets — PropertyWidgets から切り出した「RefList エディタ」クラスタ。
//
// 動的長の配列を編集する 2 系統の widget を提供する:
//   - RefPercentListT: `[{id: <ref>, percent: 0-100}]` (合計表示付き)
//   - KindedRefListT:  `[{kind, id}]` (kind ごとに id 候補を切替)
//
// いずれも (value, onCommit) を取り、Add/Remove/値変更を内部 Static 配列 state で
// 保持して JSON に書き戻す。コア側の生成ヘルパー
// (PropertyWidgets.makeStringComboBox / PropertyWidgets.makeIntSpinner) と
// 編集確定 callback 型 (PropertyWidgets.Commit) を共有する。
//
// buildFieldWidget からのディスパッチ対象は buildRefPercentListWidget /
// buildKindedRefListWidget の 2 つ (どちらも pub)。

mod RefListWidgets {
    import javafx.scene.Node
    import javafx.scene.control.Button
    import javafx.scene.control.Label
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.geometry.Pos
    import javafx.event.ActionEvent
    import javafx.event.EventHandler

    /// RefPercentListT widget: 動的長の `[{id: <ref>, percent: 0-100}]` 配列を編集する。
    /// 行ごとに ComboBox (ref dropdown) + Spinner (percent) + 削除ボタン、最下段に追加ボタン
    /// と合計表示。Add / Remove は VBox を再描画、value 変更は in-place で commit + 合計
    /// ラベル更新のみ (Spinner / ComboBox が壊れないように)
    pub def buildRefPercentListWidget(value: Option[Util.Json.Json],
                                        options: List[String],
                                        commit: PropertyWidgets.Commit): Node \ IO = {
        let initial = parseRefPercentRows(value);
        let rowsRef: Array[List[(String, Int32)], Static] = Array#{initial} @ Static;
        let sumLabelRef: Array[Option[Label], Static] = Array#{(None: Option[Label])} @ Static;
        let outer = new VBox(4.0);
        outer.getStyleClass().add("ref-percent-list");
        renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
        checked_cast(outer)
    }

    /// outer の子をクリアして再描画。Add/Remove のたびに呼ぶ
    def renderRefPercentList(outer: VBox,
                              rowsRef: Array[List[(String, Int32)], Static],
                              sumLabelRef: Array[Option[Label], Static],
                              options: List[String],
                              commit: PropertyWidgets.Commit): Unit \ IO = {
        let children = outer.getChildren();
        children.clear();
        let rows = Array.get(0, rowsRef);
        renderRefPercentListRows(0i32, rows, outer, rowsRef, sumLabelRef, options, commit);
        // 追加ボタン
        let addBtn = new Button("＋ 追加");
        addBtn.getStyleClass().add("catalog-btn");
        addBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, rowsRef);
                let firstOpt = List.head(options) |> Option.getWithDefault("");
                let newRows = List.append(cur, (firstOpt, 0i32) :: Nil);
                Array.put(newRows, 0, rowsRef);
                renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
                commitRefPercentRows(rowsRef, commit)
            }
        });
        let addNode: Node = checked_cast(addBtn);
        discard children.add(addNode);
        // 合計ラベル
        let sum = sumPercents(rows);
        let lbl = new Label(formatSumLabel(sum));
        lbl.getStyleClass().add("ref-percent-sum");
        Array.put(Some(lbl), 0, sumLabelRef);
        let lblNode: Node = checked_cast(lbl);
        discard children.add(lblNode)
    }

    /// 各行 (HBox) を VBox に append する。idx は再描画のたびに 0 から数え直し
    def renderRefPercentListRows(idx: Int32, remaining: List[(String, Int32)],
                                  outer: VBox,
                                  rowsRef: Array[List[(String, Int32)], Static],
                                  sumLabelRef: Array[Option[Label], Static],
                                  options: List[String],
                                  commit: PropertyWidgets.Commit): Unit \ IO =
        match remaining {
            case Nil => ()
            case (id, pct) :: rest => {
                let row = buildRefPercentRow(idx, id, pct, {
                    outer = outer, rowsRef = rowsRef, sumLabelRef = sumLabelRef,
                    options = options, commit = commit
                });
                let rowNode: Node = checked_cast(row);
                discard outer.getChildren().add(rowNode);
                renderRefPercentListRows(idx + 1i32, rest, outer, rowsRef, sumLabelRef,
                                          options, commit)
            }
        }

    /// renderRefPercentList 系で共有する文脈 (行に依らない参照)。
    /// idx/id/pct の行ごとに変わる値とは分けて束ねる。
    type alias RefPercentRowContext = {
        outer       = VBox,
        rowsRef     = Array[List[(String, Int32)], Static],
        sumLabelRef = Array[Option[Label], Static],
        options     = List[String],
        commit      = PropertyWidgets.Commit
    }

    /// 1 行ぶん: [ComboBox] [Spinner] % [✕]
    def buildRefPercentRow(idx: Int32, id: String, pct: Int32,
                            ctx: RefPercentRowContext): HBox \ IO = {
        let outer = ctx#outer;
        let rowsRef = ctx#rowsRef;
        let sumLabelRef = ctx#sumLabelRef;
        let options = ctx#options;
        let commit = ctx#commit;
        let row = new HBox(4.0);
        row.setAlignment(Pos.CENTER_LEFT);
        // ComboBox
        let combo = PropertyWidgets.makeStringComboBox(options, id, 140.0, newVal -> {
            let cur = Array.get(0, rowsRef);
            let curPct = nthPercent(idx, cur);
            Array.put(replaceRowAt(idx, (newVal, curPct), cur), 0, rowsRef);
            commitRefPercentRows(rowsRef, commit);
            updateSumLabel(rowsRef, sumLabelRef)
        });
        // Spinner (percent)
        let spinner = PropertyWidgets.makeIntSpinner({min = 0i32, max = 100i32}, pct, 80.0, v -> {
            let cur = Array.get(0, rowsRef);
            let curId = nthId(idx, cur);
            Array.put(replaceRowAt(idx, (curId, v), cur), 0, rowsRef);
            commitRefPercentRows(rowsRef, commit);
            updateSumLabel(rowsRef, sumLabelRef)
        });
        let pctLbl = new Label("%");
        // Remove ボタン
        let removeBtn = new Button("✕");
        removeBtn.getStyleClass().add("catalog-btn");
        removeBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, rowsRef);
                Array.put(removeRowAt(idx, cur), 0, rowsRef);
                renderRefPercentList(outer, rowsRef, sumLabelRef, options, commit);
                commitRefPercentRows(rowsRef, commit)
            }
        });
        let children = row.getChildren();
        let comboNode:  Node = checked_cast(combo);
        let spinNode:   Node = checked_cast(spinner);
        let pctLblNode: Node = checked_cast(pctLbl);
        let rmNode:     Node = checked_cast(removeBtn);
        discard children.add(comboNode);
        discard children.add(spinNode);
        discard children.add(pctLblNode);
        discard children.add(rmNode);
        row
    }

    /// JSON 値 (Option[JArray of JObject{id, percent}]) を [(id, percent)] にパース。
    /// 不正な要素はスキップ。値無しは空リスト
    def parseRefPercentRows(value: Option[Util.Json.Json]): List[(String, Int32)] =
        match value {
            case Some(Util.Json.Json.JArray(items)) =>
                Vector.toList(items)
                    |> List.filterMap(decodeRefPercentRow)
            case _ => Nil
        }

    def decodeRefPercentRow(elem: Util.Json.Json): Option[(String, Int32)] =
        match elem {
            case Util.Json.Json.JObject(m) =>
                let idOpt = Map.get("id", m) |> Option.flatMap(j -> match j {
                    case Util.Json.Json.JString(s) => Some(s)
                    case _ => None
                });
                let pctOpt = Map.get("percent", m) |> Option.flatMap(NodeInspector.jsonToInt);
                match (idOpt, pctOpt) {
                    case (Some(i), Some(p)) => Some((i, p))
                    case _                  => None
                }
            case _ => None
        }

    /// 内部 state を JSON に書き戻して commit
    def commitRefPercentRows(rowsRef: Array[List[(String, Int32)], Static],
                              commit: PropertyWidgets.Commit): Unit \ IO = {
        let rows = Array.get(0, rowsRef);
        let items = rows |> List.map(p -> {
            let (id, pct) = p;
            Util.Json.Json.JObject(Map#{
                "id"      => Util.Json.Json.JString(id),
                "percent" => NodeInspector.intToJson(pct)
            })
        });
        commit(Util.Json.Json.JArray(List.toVector(items)))
    }

    /// idx 番目の (id, pct) を newPair で置き換えた新リストを返す
    def replaceRowAt(idx: Int32, newPair: (String, Int32),
                      rows: List[(String, Int32)]): List[(String, Int32)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) newPair :: xs
                else x :: replaceRowAt(idx - 1i32, newPair, xs)
        }

    /// idx 番目を取り除いた新リストを返す
    def removeRowAt(idx: Int32, rows: List[(String, Int32)]): List[(String, Int32)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) xs
                else x :: removeRowAt(idx - 1i32, xs)
        }

    def nthPercent(idx: Int32, rows: List[(String, Int32)]): Int32 =
        match List.nth(idx, rows) {
            case Some((_, p)) => p
            case None         => 0i32
        }

    def nthId(idx: Int32, rows: List[(String, Int32)]): String =
        match List.nth(idx, rows) {
            case Some((i, _)) => i
            case None         => ""
        }

    def sumPercents(rows: List[(String, Int32)]): Int32 =
        List.foldLeft((acc, p) -> { let (_, v) = p; acc + v }, 0i32, rows)

    def formatSumLabel(sum: Int32): String =
        if (sum == 100i32) "合計: ${sum}% ✓"
        else "合計: ${sum}% ⚠"

    def updateSumLabel(rowsRef: Array[List[(String, Int32)], Static],
                        sumLabelRef: Array[Option[Label], Static]): Unit \ IO = {
        let sum = sumPercents(Array.get(0, rowsRef));
        match Array.get(0, sumLabelRef) {
            case Some(lbl) => lbl.setText(formatSumLabel(sum))
            case None      => ()
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // KindedRefListT widget — 動的長の `[{kind, id}]` 配列を編集する
    //
    // 各行は (kind ComboBox, id ComboBox, 削除ボタン) の組。
    // kind を変えると id ComboBox の候補が新しい kind に紐づく catalog の id 一覧に切替わる。
    // 下部に「＋ 追加」ボタン。
    // fe_rogue の `initialInventory`（武器・杖の混在リスト）等で使う想定。
    // ════════════════════════════════════════════════════════════════════════

    /// `KindedRefListT(kinds)` 用 widget。`refOptions[kindSpec.target]` で各 kind の id 候補を引く。
    pub def buildKindedRefListWidget(value: Option[Util.Json.Json],
                                       kinds: List[Resource.KindSpec],
                                       refOptions: Map[String, List[String]],
                                       commit: PropertyWidgets.Commit): Node \ IO = {
        let initial = parseKindedRows(value);
        let rowsRef: Array[List[(String, String)], Static] = Array#{initial} @ Static;
        let outer = new VBox(4.0);
        outer.getStyleClass().add("kinded-ref-list");
        renderKindedRefList(outer, rowsRef, kinds, refOptions, commit);
        checked_cast(outer)
    }

    /// JSON `[{"kind": "...", "id": "..."}, ...]` を `(kindId, id)` のリストに変換する。
    /// 不正な要素はスキップ。
    def parseKindedRows(value: Option[Util.Json.Json]): List[(String, String)] =
        match value {
            case Some(Util.Json.Json.JArray(arr)) =>
                List.filterMap(parseKindedRow, Vector.toList(arr))
            case _ => Nil
        }

    def parseKindedRow(elem: Util.Json.Json): Option[(String, String)] =
        match elem {
            case Util.Json.Json.JObject(m) =>
                let kindOpt = Map.get("kind", m) |> Option.flatMap(j -> match j {
                    case Util.Json.Json.JString(s) => Some(s)
                    case _ => None
                });
                let idOpt = Map.get("id", m) |> Option.flatMap(j -> match j {
                    case Util.Json.Json.JString(s) => Some(s)
                    case _ => None
                });
                match (kindOpt, idOpt) {
                    case (Some(k), Some(i)) => Some((k, i))
                    case _                  => None
                }
            case _ => None
        }

    /// 内部 state を JSON に書き戻して commit する
    def commitKindedRows(rowsRef: Array[List[(String, String)], Static],
                          commit: PropertyWidgets.Commit): Unit \ IO = {
        let rows = Array.get(0, rowsRef);
        let items = rows |> List.map(p -> {
            let (k, i) = p;
            Util.Json.Json.JObject(Map#{
                "kind" => Util.Json.Json.JString(k),
                "id"   => Util.Json.Json.JString(i)
            })
        });
        commit(Util.Json.Json.JArray(List.toVector(items)))
    }

    /// outer の子をクリアして再描画。Add/Remove/kind 切替 のたびに呼ぶ
    def renderKindedRefList(outer: VBox,
                              rowsRef: Array[List[(String, String)], Static],
                              kinds: List[Resource.KindSpec],
                              refOptions: Map[String, List[String]],
                              commit: PropertyWidgets.Commit): Unit \ IO = {
        let children = outer.getChildren();
        children.clear();
        let rows = Array.get(0, rowsRef);
        renderKindedRows(0i32, rows, outer, rowsRef, kinds, refOptions, commit);
        // 追加ボタン: 最初の kind を default にして、その catalog の先頭 id を採用
        let addBtn = new Button("＋ 追加");
        addBtn.getStyleClass().add("catalog-btn");
        addBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let defaultRow = defaultKindedRow(kinds, refOptions);
                let cur = Array.get(0, rowsRef);
                let newRows = List.append(cur, defaultRow :: Nil);
                Array.put(newRows, 0, rowsRef);
                renderKindedRefList(outer, rowsRef, kinds, refOptions, commit);
                commitKindedRows(rowsRef, commit)
            }
        });
        let addNode: Node = checked_cast(addBtn);
        discard children.add(addNode)
    }

    /// 各行を VBox に append する。idx は再描画のたびに 0 から数え直し
    def renderKindedRows(idx: Int32, remaining: List[(String, String)],
                          outer: VBox,
                          rowsRef: Array[List[(String, String)], Static],
                          kinds: List[Resource.KindSpec],
                          refOptions: Map[String, List[String]],
                          commit: PropertyWidgets.Commit): Unit \ IO =
        match remaining {
            case Nil => ()
            case (kindId, id) :: rest => {
                let row = buildKindedRow(idx, kindId, id, {
                    outer = outer, rowsRef = rowsRef, kinds = kinds,
                    refOptions = refOptions, commit = commit
                });
                let rowNode: Node = checked_cast(row);
                discard outer.getChildren().add(rowNode);
                renderKindedRows(idx + 1i32, rest, outer, rowsRef, kinds, refOptions, commit)
            }
        }

    /// renderKindedRefList 系で共有する文脈 (行に依らない参照)。
    /// idx/kindId/id の行ごとに変わる値とは分けて束ねる。
    type alias KindedRowContext = {
        outer      = VBox,
        rowsRef    = Array[List[(String, String)], Static],
        kinds      = List[Resource.KindSpec],
        refOptions = Map[String, List[String]],
        commit     = PropertyWidgets.Commit
    }

    /// 1 行: [kind ComboBox] [id ComboBox] [✕]
    def buildKindedRow(idx: Int32, kindId: String, id: String,
                        ctx: KindedRowContext): HBox \ IO = {
        let outer = ctx#outer;
        let rowsRef = ctx#rowsRef;
        let kinds = ctx#kinds;
        let refOptions = ctx#refOptions;
        let commit = ctx#commit;
        let row = new HBox(4.0);
        row.setAlignment(Pos.CENTER_LEFT);
        // kind ComboBox: 表示は label、内部状態は kindId
        // kind 変更時: 行の kindId を更新、id を新 kind の先頭に reset、再描画 + commit
        let kindLabels = List.map(k -> k#label, kinds);
        let kindCombo = PropertyWidgets.makeStringComboBox(kindLabels, labelOfKindId(kindId, kinds), 80.0, newLabel -> {
            let newKindId = kindIdOfLabel(newLabel, kinds);
            let firstId = firstIdForKind(newKindId, kinds, refOptions);
            let cur = Array.get(0, rowsRef);
            Array.put(replaceKindedRowAt(idx, (newKindId, firstId), cur), 0, rowsRef);
            renderKindedRefList(outer, rowsRef, kinds, refOptions, commit);
            commitKindedRows(rowsRef, commit)
        });
        // id ComboBox: 現 kind の catalog から候補を引く
        // id 変更時: 行の id だけ更新、commit
        let idCombo = PropertyWidgets.makeStringComboBox(idOptionsForKind(kindId, kinds, refOptions), id, 140.0, newId -> {
            let cur = Array.get(0, rowsRef);
            let curKind = nthKindId(idx, cur);
            Array.put(replaceKindedRowAt(idx, (curKind, newId), cur), 0, rowsRef);
            commitKindedRows(rowsRef, commit)
        });
        // 削除ボタン
        let removeBtn = new Button("✕");
        removeBtn.getStyleClass().add("catalog-btn");
        removeBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let cur = Array.get(0, rowsRef);
                Array.put(removeKindedRowAt(idx, cur), 0, rowsRef);
                renderKindedRefList(outer, rowsRef, kinds, refOptions, commit);
                commitKindedRows(rowsRef, commit)
            }
        });
        let children = row.getChildren();
        let kindComboNode: Node = checked_cast(kindCombo);
        let idComboNode: Node = checked_cast(idCombo);
        let removeBtnNode: Node = checked_cast(removeBtn);
        discard children.add(kindComboNode);
        discard children.add(idComboNode);
        discard children.add(removeBtnNode);
        row
    }

    /// kindId → label。未知 kindId は kindId 自体を返す（表示崩れ防止）。
    def labelOfKindId(kindId: String, kinds: List[Resource.KindSpec]): String =
        match List.find(k -> k#kindId == kindId, kinds) {
            case Some(k) => k#label
            case None    => kindId
        }

    /// label → kindId。未知 label は先頭 kind の kindId にフォールバック。
    def kindIdOfLabel(label: String, kinds: List[Resource.KindSpec]): String =
        match List.find(k -> k#label == label, kinds) {
            case Some(k) => k#kindId
            case None    => match List.head(kinds) {
                case Some(k) => k#kindId
                case None    => ""
            }
        }

    /// 指定 kindId の catalog から id 候補リストを引く。未定義なら空。
    def idOptionsForKind(kindId: String, kinds: List[Resource.KindSpec],
                          refOptions: Map[String, List[String]]): List[String] =
        match List.find(k -> k#kindId == kindId, kinds) {
            case Some(k) => Map.get(k#target, refOptions) |> Option.getWithDefault(Nil)
            case None    => Nil
        }

    /// 指定 kindId の catalog の先頭 id。空なら "".
    def firstIdForKind(kindId: String, kinds: List[Resource.KindSpec],
                        refOptions: Map[String, List[String]]): String =
        List.head(idOptionsForKind(kindId, kinds, refOptions)) |> Option.getWithDefault("")

    /// 「＋ 追加」のデフォルト行: 先頭 kind の先頭 id を採用
    def defaultKindedRow(kinds: List[Resource.KindSpec],
                          refOptions: Map[String, List[String]]): (String, String) =
        match List.head(kinds) {
            case Some(k) => (k#kindId, firstIdForKind(k#kindId, kinds, refOptions))
            case None    => ("", "")
        }

    /// idx 番目の (kindId, id) を newPair で置換した新リスト
    def replaceKindedRowAt(idx: Int32, newPair: (String, String),
                            rows: List[(String, String)]): List[(String, String)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) newPair :: xs
                else x :: replaceKindedRowAt(idx - 1i32, newPair, xs)
        }

    /// idx 番目を除いた新リスト
    def removeKindedRowAt(idx: Int32, rows: List[(String, String)]):
            List[(String, String)] =
        match rows {
            case Nil     => Nil
            case x :: xs =>
                if (idx == 0i32) xs
                else x :: removeKindedRowAt(idx - 1i32, xs)
        }

    def nthKindId(idx: Int32, rows: List[(String, String)]): String =
        match List.nth(idx, rows) {
            case Some((k, _)) => k
            case None         => ""
        }
}
