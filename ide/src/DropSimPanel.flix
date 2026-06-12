// DropSimPanel — floors の Property Panel 末尾に「ドロップ試算」セクションを足す UI 層。
//
// ResourcePanel.rebuildPropertyPanel から appendSection が呼ばれ、選択中の record が
// floors の sub-entry のときだけ TitledPane（試行回数 N の Spinner + 実行ボタン + 結果 TextArea）
// を 1 個 children に積む。固有ルール（0.33・2段抽選・anchor 除外）は DropSimCore に閉じ、
// ここは「JSON を渡して結果文字列を表示する」配線に徹する。
//
// 実行は同期（FX スレッド内）。`Math.Random.runWithIO` で実機と同じ乱数源を discharge する。
// chests.json は floors.json と同じ resources/ ディレクトリから読む。
mod DropSimPanel {
    import java.lang.Integer
    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Button
    import javafx.scene.control.Label
    import javafx.scene.control.Spinner
    import javafx.scene.control.TextArea
    import javafx.scene.control.TitledPane
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.event.ActionEvent
    import javafx.event.EventHandler

    /// floors の sub-entry を表示中なら「ドロップ試算」セクションを children 末尾に積む。
    /// それ以外のリソースでは何もしない（汎用 Property Panel を汚さない）。
    pub def appendSection(children: ObservableList[Node], state: IdeState.IdeState,
                           record: Util.Json.Json, basePath: List[String],
                           refOptions: Map[String, List[String]]): Unit \ IO =
        if (List.head(basePath) != Some("floors")) ()
        else {
            let floorId = List.reverse(basePath) |> List.head |> Option.getWithDefault("?");
            let inner = new VBox(6.0);
            let kids = inner.getChildren();

            let row = new HBox(6.0);
            let label = new Label("試行回数 N:");
            // 値は実行時に getValue で読むので listener は付けない（直接構築）。
            let nSpinner: Spinner[Integer] = new Spinner(1i32, 100000i32, 1000i32);
            nSpinner.setEditable(true);
            nSpinner.setPrefWidth(90.0);
            let runBtn = new Button("試算 ▶");

            let resultArea = new TextArea("「試算 ▶」で N 回シミュレーションして結果を表示します");
            resultArea.setEditable(false);
            resultArea.setWrapText(false);
            resultArea.setPrefRowCount(18);
            discard resultArea.getStyleClass().add("dropsim-output");

            runBtn.setOnAction(new EventHandler[ActionEvent] {
                def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                    let n = nSpinner.getValue().intValue();
                    let chestsJson = loadChestsJson(state);
                    let nameMap = loadLabelMap(state);
                    let result = run {
                        DropSimCore.simulate(record, chestsJson, n, 3)
                    } with Math.Random.runWithIO;
                    let labelOf = id -> friendlyLabel(nameMap, refOptions, id);
                    let text = DropSimCore.formatResult(floorId, result, labelOf);
                    resultArea.setText(text)
                }
            });

            // コントロール行を組む
            let labelNode: Node = checked_cast(label);
            let spinnerNode: Node = checked_cast(nSpinner);
            let btnNode: Node = checked_cast(runBtn);
            let rowKids = row.getChildren();
            discard rowKids.add(labelNode);
            discard rowKids.add(spinnerNode);
            discard rowKids.add(btnNode);

            let rowNode: Node = checked_cast(row);
            let areaNode: Node = checked_cast(resultArea);
            discard kids.add(rowNode);
            discard kids.add(areaNode);

            // TitledPane（既定展開）で囲んで Property Panel 末尾に積む
            let innerNode: Node = checked_cast(inner);
            let pane = new TitledPane();
            pane.setText("ドロップ試算");
            pane.setExpanded(true);
            pane.setContent(innerNode);
            let paneNode: Node = checked_cast(pane);
            discard children.add(paneNode)
        }

    /// id → 人間向け表示。カタログの表示名（"てつのやり" 等）に種別を添える（例 "てつのやり(武器)"）。
    /// 名前が引けなければ id をそのまま使う（編集途中の不整合 JSON でも壊れない）。
    def friendlyLabel(nameMap: Map[String, String], refOptions: Map[String, List[String]], id: String): String =
        let nm = Map.get(id, nameMap) |> Option.getWithDefault(id);
        let cat = categoryOf(refOptions, id);
        if (cat == "") nm else "${nm}(${cat})"

    /// id がどのカタログ由来か（refOptions の containerKey 一覧から先勝ちで判定）。
    /// 解決順は ItemScene.lookupItem と同じ weapons→staves→consumables→rings。未解決は ""。
    def categoryOf(refOptions: Map[String, List[String]], id: String): String =
        let inCat = key -> Map.get(key, refOptions) |> Option.getWithDefault(Nil) |> List.exists(x -> x == id);
        if (inCat("weapons")) "武器"
        else if (inCat("staves")) "杖"
        else if (inCat("consumables")) "消耗品"
        else if (inCat("rings")) "指輪"
        else ""

    /// weapons/staves/consumables/rings の "name" と chests の "label" を 1 つの id→表示名 Map に集約。
    /// floors.json と同じ resources/ から読む。失敗したカタログは単に欠落（id 表示にフォールバック）。
    def loadLabelMap(state: IdeState.IdeState): Map[String, String] \ IO =
        match ResourceState.getSelectedDataPath(state#resource) {
            case None             => Map.empty()
            case Some(floorsPath) =>
                let dir = parentDir(floorsPath);
                let weapons = DropSimCore.idLabels(readResourceJson(dir, "weapons.json"), "weapons", "name");
                let staves  = DropSimCore.idLabels(readResourceJson(dir, "staves.json"), "staves", "name");
                let cons    = DropSimCore.idLabels(readResourceJson(dir, "consumables.json"), "consumables", "name");
                let rings   = DropSimCore.idLabels(readResourceJson(dir, "rings.json"), "rings", "name");
                let chests  = DropSimCore.idLabels(readResourceJson(dir, "chests.json"), "chests", "label");
                // 先勝ち（weapons→staves→consumables→rings）。Map.union は左優先。
                Map.union(weapons, Map.union(staves, Map.union(cons, Map.union(rings, chests))))
        }

    def readResourceJson(dir: String, name: String): Option[Util.Json.Json] \ IO =
        run { loadJsonFile("${dir}/${name}") } with Fs.FileRead.runWithIO

    /// floors.json と同じ resources/ から chests.json を読む。未選択 / 失敗は None
    /// （宝箱シミュレーションはスキップされる）。
    def loadChestsJson(state: IdeState.IdeState): Option[Util.Json.Json] \ IO =
        match ResourceState.getSelectedDataPath(state#resource) {
            case None             => None
            case Some(floorsPath) =>
                let chestsPath = "${parentDir(floorsPath)}/chests.json";
                run { loadJsonFile(chestsPath) } with Fs.FileRead.runWithIO
        }

    /// JSON ファイルを読んで Json にパース（ResourcePanel.loadJson と同じ流儀）。失敗は None。
    def loadJsonFile(path: String): Option[Util.Json.Json] \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(s -> JsonCompat.parse(String.trim(s)))

    /// パス末尾の `/<segment>` を 1 段落とす（区切りが無ければそのまま）。
    def parentDir(path: String): String =
        parentDirRec(path, String.length(path) - 1)

    def parentDirRec(path: String, idx: Int32): String =
        if (idx < 0) path
        else if (String.charAt(idx, path) == '/') path.substring(0, idx)
        else parentDirRec(path, idx - 1)
}
