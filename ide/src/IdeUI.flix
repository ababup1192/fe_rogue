// IdeUI — IDE のフレームレイアウトとメニュー処理。SwingLayer から呼ばれる
// `customizeFrame` コールバックを提供する。
//
// 役割:
//   - 大きめのウィンドウサイズ + BorderLayout
//     (左 = scene-tree / 中央 = scene preview / 右 = JSplitPane(Inspector 上, Scene Files 下))
//   - JMenuBar に File → Open Project... を追加
//   - File チューザでプロジェクトディレクトリを選ばせ、`pendingProjectRef` に保存
//     + WindowEvent.WINDOW_CLOSING を dispatch して SwingLayer.withSwing を抜けさせる
//   - 右下の scene ファイルリストをクリックすると `pendingSceneRef` を更新し、
//     同時に左の scene-tree も該当 JSON で再構築する (window は閉じない、
//     現セッション内で scene を切替える)
//
// SwingLayer は UI 構造を知らない。IdeUI は IDE 固有の UI を集約する。

mod IdeUI {
    import javax.swing.JFrame
    import javax.swing.JMenuBar
    import javax.swing.JMenu
    import javax.swing.JMenuItem
    import javax.swing.JPanel
    import javax.swing.JLabel
    import javax.swing.JList
    import javax.swing.JButton
    import javax.swing.JProgressBar
    import javax.swing.JScrollPane
    import javax.swing.JTree
    import javax.swing.JSplitPane
    import javax.swing.JCheckBox
    import javax.swing.JTextField
    import javax.swing.JComboBox
    import javax.swing.JSlider
    import javax.swing.DefaultListModel
    import javax.swing.ListSelectionModel
    import javax.swing.JFileChooser
    import javax.swing.BoxLayout
    import javax.swing.BorderFactory
    import javax.swing.{Timer => SwingTimer}
    import javax.swing.UIManager
    import javax.swing.Box
    import javax.swing.event.ListSelectionListener
    import javax.swing.event.ListSelectionEvent
    import javax.swing.event.TreeSelectionListener
    import javax.swing.event.TreeSelectionEvent
    import javax.swing.event.ChangeListener
    import javax.swing.event.ChangeEvent
    import javax.swing.tree.DefaultMutableTreeNode
    import javax.swing.tree.DefaultTreeModel
    import javax.swing.tree.DefaultTreeCellRenderer
    import javax.swing.tree.TreeSelectionModel
    import java.awt.BorderLayout
    import java.awt.Color
    import java.awt.Dimension
    import java.awt.GridLayout
    import java.awt.Toolkit
    import java.awt.FileDialog
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import java.awt.event.WindowEvent
    import java.io.File
    import java.lang.System
    import java.math.BigDecimal
    import java.util.prefs.Preferences
    import org.lwjgl.opengl.awt.AWTGLCanvas

    use Json.JsonElement.{JsonObject, JsonArray, JsonString, JsonNumber, JsonBool}

    /// IdeState 本体は IdeState モジュールで定義される。再露出のための型エイリアス。
    pub type alias IdeState = IdeState.IdeState

    /// SwingLayer.withSwing に渡す customizeFrame コールバック本体。
    pub def customize(state: IdeState, frame: JFrame, canvas: AWTGLCanvas): Unit \ IO =
        // ウィンドウサイズ (IDE 想定: 1280x800)。極端な縮小で Metal が落ちるので最小も設定。
        frame.setSize(new Dimension(1280, 800));
        frame.setMinimumSize(new Dimension(800, 500));
        frame.setLayout(new BorderLayout());

        // 中央: scene preview。canvas を BorderLayout.CENTER に直接置いて
        // 利用可能スペース全部を使わせる。design/window アスペクト比のズレは
        // renderFrameMixed の calcViewport が letterbox/pillarbox で吸収する。
        let centerPanel = new JPanel(new BorderLayout());
        centerPanel.setBackground(new Color(20, 20, 20));
        centerPanel.setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));
        centerPanel.add(canvas, BorderLayout.CENTER);
        frame.add(centerPanel, BorderLayout.CENTER);

        // 左: scene-tree (現在選択中の scene のノード階層を JTree で表示)
        let westPanel = buildSceneTreePanel(state);
        westPanel.setPreferredSize(new Dimension(300, 0));
        frame.add(westPanel, BorderLayout.WEST);

        // 右: 上 = Inspector / 下 = Scene Files の縦分割
        let inspectorPanel = buildInspectorPanel(state);
        let scenesPanel = buildScenesPanel(state);

        let eastSplit = new JSplitPane(JSplitPane.VERTICAL_SPLIT, inspectorPanel, scenesPanel);
        eastSplit.setDividerLocation(400);
        eastSplit.setResizeWeight(0.5);
        eastSplit.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        eastSplit.setPreferredSize(new Dimension(300, 0));
        frame.add(eastSplit, BorderLayout.EAST);

        // 下: ステータスバー
        let southPanel = new JPanel();
        southPanel.setPreferredSize(new Dimension(0, 22));
        southPanel.setBackground(new Color(50, 50, 50));
        frame.add(southPanel, BorderLayout.SOUTH);

        // メニューバー
        frame.setJMenuBar(buildMenuBar(state, frame));

        // 前セッション残しの loading splash があれば、setVisible 後に EDT で dispose する。
        // customize() 自体は setVisible より前に呼ばれるため、すぐ dispose すると窓が
        // 一切ない時間ができる。Swing の Timer (EDT 上で発火) で 80ms 後に dispose を予約する。
        // (Runnable は run() メソッドが Flix の予約語と衝突するため Timer + ActionListener で代替)
        let timer = new SwingTimer(80, new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                match Array.get(0, state#loadingSplashRef) {
                    case Some(splash) =>
                        splash.dispose();
                        Array.put(None, 0, state#loadingSplashRef)
                    case None => ()
                }
            }
        });
        timer.setRepeats(false);
        timer.start()

    /// 右下パネル: 上段はヘッダラベル、下段は scene ファイル JList。
    def buildScenesPanel(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        let header = new JLabel("  Scene Files");
        header.setForeground(Color.LIGHT_GRAY);
        panel.add(header, BorderLayout.NORTH);

        // 現在の scene ファイルから ListModel を構築。
        // クリック後の reload で再構築されるが、これは初回 paint 用の初期内容。
        let listModel = new DefaultListModel();
        let files = Array.get(0, state#sceneFilesRef);
        List.forEach(pair -> {
            let (_abs, rel) = pair;
            listModel.addElement(rel);
            ()
        }, files);

        let list = new JList();
        list.setModel(listModel);
        list.setBackground(new Color(35, 35, 35));
        list.setForeground(Color.LIGHT_GRAY);
        list.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        list.addListSelectionListener(new ListSelectionListener {
            def valueChanged(_this: ListSelectionListener, e: ListSelectionEvent): Unit \ IO = {
                if (not e.getValueIsAdjusting()) {
                    let idx = list.getSelectedIndex();
                    if (idx >= 0) {
                        let current = Array.get(0, state#sceneFilesRef);
                        match List.nth(idx, current) {
                            case Some(pair) =>
                                let (abs, _rel) = pair;
                                println("[IdeUI] Scene selected: ${abs}");
                                Array.put(Some(abs), 0, state#pendingSceneRef);
                                populateSceneTree(state, abs)
                            case None => ()
                        }
                    } else ()
                } else ()
            }
        });

        let scroll = new JScrollPane(list);
        scroll.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        panel.add(scroll, BorderLayout.CENTER);
        panel

    /// 左パネル: 現在選択中のシーンのノード階層を JTree で表示する。
    /// 初期表示は "(no scene selected)" だけ。シーン選択で populateSceneTree が
    /// 呼ばれ、JSON の type/name/children を読んで木を組み立てる。
    /// TreeModel を state#sceneTreeModelRef に保存し、後で listener から差し替えできるようにする。
    def buildSceneTreePanel(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        let header = new JLabel("  Scene");
        header.setForeground(Color.LIGHT_GRAY);
        panel.add(header, BorderLayout.NORTH);

        let root = new DefaultMutableTreeNode("(no scene selected)");
        let model = new DefaultTreeModel(root);
        Array.put(Some(model), 0, state#sceneTreeModelRef);

        let tree = new JTree(model);
        tree.setRootVisible(true);
        tree.setShowsRootHandles(true);
        tree.getSelectionModel().setSelectionMode(TreeSelectionModel.SINGLE_TREE_SELECTION);
        tree.setBackground(new Color(35, 35, 35));
        tree.setForeground(Color.LIGHT_GRAY);

        // ダークテーマ化: デフォルトの DefaultTreeCellRenderer は非選択セルを白で塗るため、
        // 全行が「選択中」のように見える。各色を tree.setBackground と揃え、選択色だけ
        // 一般的なダークテーマの青に差し替える。
        let renderer = new DefaultTreeCellRenderer();
        renderer.setBackgroundNonSelectionColor(new Color(35, 35, 35));
        renderer.setBackgroundSelectionColor(new Color(55, 90, 140));
        renderer.setTextNonSelectionColor(Color.LIGHT_GRAY);
        renderer.setTextSelectionColor(Color.WHITE);
        renderer.setBorderSelectionColor(new Color(55, 90, 140));
        tree.setCellRenderer(renderer);

        // 選択ノードの子インデックス列を nodePathMap から引き、selectedNodePathRef に保存。
        // その path で currentSceneJson を歩いて「最新の」JsonElement を取り、Inspector に渡す。
        // commit 後に再選択された場合も、currentSceneJson は更新済みなので最新値が出る。
        tree.addTreeSelectionListener(new TreeSelectionListener {
            def valueChanged(_this: TreeSelectionListener, _e: TreeSelectionEvent): Unit \ IO = {
                // preview→tree 同期で setSelectionPath を呼んだ際は何もしない
                // (editor 選択 → tree ハイライト → listener → editor 再書き込みのループ防止)
                if (IdeState.isTreeListenerMuted(state)) ()
                else {
                    let selected = tree.getLastSelectedPathComponent();
                    if (Object.isNull(selected)) ()
                    else {
                        let id = System.identityHashCode(selected);
                        let pathOpt = Map.get(id, Array.get(0, state#nodePathMapRef));
                        Array.put(pathOpt, 0, state#selectedNodePathRef);
                        // pending として積むことで、次フレームの renderLoop が
                        // SelectionBridge.applyTreeSelectionToEditor 経由で editor に流す
                        IdeState.setPendingTreeSelection(state, pathOpt);
                        match (pathOpt, Array.get(0, state#currentSceneJsonRef)) {
                            case (Some(path), Some(sceneRoot)) =>
                                match JsonOps.getAtNodePath(sceneRoot, path) {
                                    case Some(json) => updateInspector(state, json)
                                    case None       => ()
                                }
                            case _ => ()
                        }
                    }
                }
            }
        });

        let scroll = new JScrollPane(tree);
        scroll.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        scroll.getViewport().setBackground(new Color(35, 35, 35));
        panel.add(scroll, BorderLayout.CENTER);
        panel

    /// JSON 要素を Swing の TreeNode に再帰変換する。
    /// ラベル整形・子インデックスの積み上げといった純粋ロジックは SceneTreeModel に任せ、
    /// ここでは TreeModelNode を walk して DefaultMutableTreeNode を組み立てる。
    /// 同時に nodePathMap (identityHashCode → ルートからの子インデックス列) を登録し、
    /// Tree 選択 / Inspector commit で参照できるようにする。
    def jsonToTreeNode(elem: Json.JsonElement, state: IdeState): DefaultMutableTreeNode \ IO =
        treeModelToSwing(SceneTreeModel.fromJson(elem), state)

    /// SceneTreeModel.TreeModelNode を Swing の DefaultMutableTreeNode に変換しつつ、
    /// 各 Swing ノードの identityHashCode を nodePath にマップ登録する。
    def treeModelToSwing(model: SceneTreeModel.TreeModelNode, state: IdeState): DefaultMutableTreeNode \ IO =
        let node = new DefaultMutableTreeNode(SceneTreeModel.labelOf(model));
        let id = System.identityHashCode(node);
        Array.put(Map.insert(id, SceneTreeModel.nodePathOf(model), Array.get(0, state#nodePathMapRef)),
                  0, state#nodePathMapRef);
        discard SceneTreeModel.childrenOf(model) |> List.map(child -> {
            let childNode = treeModelToSwing(child, state);
            node.add(childNode);
            ()
        });
        node

    /// 絶対パスから scene.json を読み、木を再構築して state#sceneTreeModelRef の root を差し替える。
    /// 同時に nodePathMap / currentSceneJson / currentScenePath / selectedNodePath を更新し、
    /// Inspector を placeholder に戻す。
    /// EDT の listener から呼ばれるため、Fs.FileRead エフェクトはこの関数内で discharge する
    /// （listener のシグネチャは `Unit \ IO` 固定）。
    /// 読み込み・パース失敗時はクラッシュさせず、エラーラベルのみのツリーを表示する。
    pub def populateSceneTree(state: IdeState, absPath: String): Unit \ IO =
        Array.put(Map.empty(), 0, state#nodePathMapRef);
        Array.put(None, 0, state#selectedNodePathRef);
        Array.put(Some(absPath), 0, state#currentScenePathRef);
        let readResult = run {
            Fs.ReadFile.read(absPath)
        } with Fs.ReadFile.runWithFileRead with Fs.FileRead.runWithIO;
        let (newRoot, parsedJson) = match readResult {
            case Err(e)   => (new DefaultMutableTreeNode("(read error: ${e})"), None)
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None       => (new DefaultMutableTreeNode("(JSON parse failed)"), None)
                    case Some(json) => (jsonToTreeNode(json, state), Some(json))
                }
        };
        Array.put(parsedJson, 0, state#currentSceneJsonRef);
        match Array.get(0, state#sceneTreeModelRef) {
            case Some(model) => model.setRoot(newRoot)
            case None        => ()
        };
        resetInspectorPlaceholder(state)

    // ========================================================================
    // 編集 (commit) — Inspector の widget 変更を JSON に反映し、ファイルに書き戻し、
    // pendingSceneRef をセットして canvas を即時 reload する。
    // ========================================================================

    /// 選択中ノードのプロパティ (sub-path で示される) を `newValue` で更新し、
    /// ファイルに書き戻して reload を予約する。`subKeys` はノード直下からのキー列
    /// (例: ["pos"] や ["properties", "jumpVelocity"])。
    /// 必要な state (current scene path/json/selected path) のいずれかが None なら何もしない。
    def commitEdit(state: IdeState, subKeys: List[String], newValue: Json.JsonElement): Unit \ IO =
        match (Array.get(0, state#currentSceneJsonRef),
               Array.get(0, state#currentScenePathRef),
               Array.get(0, state#selectedNodePathRef)) {
            case (Some(root), Some(path), Some(nodePath)) =>
                let newRoot = JsonOps.setAtNodePath({root = root, nodePath = nodePath,
                                                     subKeys = subKeys, newValue = newValue});
                match writeSceneJson(path, newRoot) {
                    case Ok(_) =>
                        Array.put(Some(newRoot), 0, state#currentSceneJsonRef);
                        // canvas に反映: 同じ path を pendingSceneRef にセットして renderLoop に拾わせる
                        Array.put(Some(path), 0, state#pendingSceneRef);
                        // 兄弟フィールドが変化するケース (shape kind 切替で width↔radius が
                        // 入れ替わるなど) に備えて Inspector も最新の JsonElement で再描画する。
                        // 個別 widget commit の単純更新でも再描画は無害（widget の値はそのまま）
                        match JsonOps.getAtNodePath(newRoot, nodePath) {
                            case Some(json) => updateInspector(state, json)
                            case None       => ()
                        }
                    case Err(msg) =>
                        println("[IdeUI] write failed: ${msg}")
                }
            case _ => ()
        }

    /// root JsonElement を pretty-print して `path` に書き出す。
    /// Fs.FileWrite を内部で discharge し、外側 effect は IO のみ。
    def writeSceneJson(path: String, root: Json.JsonElement): Result[String, Unit] \ IO =
        let pretty = Json.Write.toPrettyString(2, root);
        let result = run {
            Fs.WriteFile.write({str = pretty}, path)
        } with Fs.WriteFile.runWithFileWrite with Fs.FileWrite.runWithIO;
        match result {
            case Ok(_)      => Ok(())
            case Err(error) => Err("${error}")
        }

    // ========================================================================
    // Inspector パネル
    // ========================================================================

    /// 右上 Inspector パネル。BoxLayout(Y_AXIS) の content を JScrollPane に入れる。
    /// content の参照は state#inspectorContentRef に保存し、ノード選択ごとに
    /// removeAll → 再構築する。
    def buildInspectorPanel(state: IdeState): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));

        let header = new JLabel("  Inspector");
        header.setForeground(Color.LIGHT_GRAY);
        panel.add(header, BorderLayout.NORTH);

        let content = new JPanel();
        content.setLayout(new BoxLayout(content, BoxLayout.Y_AXIS));
        content.setBackground(new Color(40, 40, 40));
        Array.put(Some(content), 0, state#inspectorContentRef);
        resetInspectorPlaceholder(state);

        let scroll = new JScrollPane(content);
        scroll.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        scroll.getViewport().setBackground(new Color(40, 40, 40));
        panel.add(scroll, BorderLayout.CENTER);
        panel

    /// Inspector を「未選択」状態に戻す。シーン再読込・初期化で呼ぶ。
    def resetInspectorPlaceholder(state: IdeState): Unit \ IO =
        match Array.get(0, state#inspectorContentRef) {
            case None => ()
            case Some(content) =>
                content.removeAll();
                let placeholder = new JLabel("  (no node selected)");
                placeholder.setForeground(new Color(120, 120, 120));
                placeholder.setAlignmentX(0.0f32);
                content.add(placeholder);
                content.add(Box.createVerticalGlue());
                content.revalidate();
                content.repaint()
        }

    /// 指定 JSON ノードに対応する Inspector を再構築する。
    /// 先頭にタイプ＋名前のヘッダ、続けて他プロパティを Godot 風の行で並べる。
    /// children/type/name はヘッダで扱うので個別の行は出さない。
    def updateInspector(state: IdeState, json: Json.JsonElement): Unit \ IO =
        match Array.get(0, state#inspectorContentRef) {
            case None => ()
            case Some(content) =>
                content.removeAll();
                match json {
                    case JsonObject(propMap) =>
                        let nodeType = match Map.get("type", propMap) {
                            case Some(JsonString(s)) => s
                            case _                   => "Node"
                        };
                        let nodeName = match Map.get("name", propMap) {
                            case Some(JsonString(s)) => s
                            case _                   => "<unnamed>"
                        };
                        content.add(createInspectorHeader(nodeType, nodeName));
                        renderObjectProperties(content, state, Nil, propMap, 0i32);
                        discard content.add(Box.createVerticalGlue())
                    case _ =>
                        let lbl = new JLabel("  (not a node object)");
                        lbl.setForeground(new Color(120, 120, 120));
                        lbl.setAlignmentX(0.0f32);
                        content.add(lbl);
                        discard content.add(Box.createVerticalGlue())
                };
                content.revalidate();
                content.repaint()
        }

    /// Inspector の先頭に出す「ノード名 + タイプ」ヘッダ。Godot の Inspector top に倣う。
    def createInspectorHeader(nodeType: String, nodeName: String): JPanel \ IO =
        let header = new JPanel(new BorderLayout());
        header.setBackground(new Color(55, 55, 60));
        header.setBorder(BorderFactory.createEmptyBorder(6, 10, 6, 10));
        header.setMaximumSize(new Dimension(9999, 44));
        header.setAlignmentX(0.0f32);

        let nameLabel = new JLabel(nodeName);
        nameLabel.setForeground(Color.WHITE);
        header.add(nameLabel, BorderLayout.NORTH);

        let typeLabel = new JLabel(nodeType);
        typeLabel.setForeground(new Color(140, 180, 220));
        header.add(typeLabel, BorderLayout.SOUTH);
        header

    /// JsonObject を再帰的にレンダリングする。
    /// 各キーについて:
    ///   - 値が JsonObject なら「セクション見出し」行を出し、子をインデントして再帰
    ///   - "shape" キーで kind フィールドを持つ場合は専用エディタ (`renderShapeObject`) に委譲
    ///   - その他は通常の編集 widget 行を出す
    /// `prefix` は選択ノード直下からのキー列。commit は `prefix ::: key :: Nil` で
    /// commitEdit に渡され、JsonOps.setAtNodePath で末端まで降りて差し替えられる。
    /// `indent` はインデントレベル (0 から増える)、行の左余白を増やすのに使う。
    /// 最上位 (prefix = Nil) では children/type/name は header で扱うので個別行は出さない。
    def renderObjectProperties(content: JPanel, state: IdeState, prefix: List[String],
                                obj: Map[String, Json.JsonElement], indent: Int32): Unit \ IO =
        Map.foldLeftWithKey((_acc, key, value) -> {
            if (List.isEmpty(prefix) and (key == "children" or key == "type" or key == "name")) ()
            else {
                match value {
                    case JsonObject(nested) => {
                        content.add(createSectionRow(key, indent));
                        if (key == "shape" and Map.memberOf("kind", nested))
                            renderShapeObject(content, state, prefix ::: key :: Nil, nested, indent + 1i32)
                        else
                            renderObjectProperties(content, state, prefix ::: key :: Nil, nested, indent + 1i32)
                    }
                    case _ => {
                        let commit = newVal -> commitEdit(state, prefix ::: key :: Nil, newVal);
                        let row = createPropertyRow(state, key, value, commit, indent);
                        content.add(row);
                        ()
                    }
                }
            }
        }, (), obj)

    /// "shape" JsonObject 用の専用エディタ。
    ///
    /// 1. kind フィールドを JComboBox で表示し、変更時は **shape オブジェクト全体** を
    ///    新 kind のデフォルト値で置換する（width/height ↔ radius など兄弟フィールドが
    ///    一斉に切り替わる）。
    /// 2. kind 以外のフィールド（width/height/radius/vertical 等）は通常通り
    ///    `renderObjectProperties` で widget 化する。
    ///
    /// `prefix` は shape オブジェクト自身を指すパス（呼び出し側で末尾に "shape" を含める）
    def renderShapeObject(content: JPanel, state: IdeState, prefix: List[String],
                          shapeMap: Map[String, Json.JsonElement], indent: Int32): Unit \ IO =
        let currentKind = match Map.get("kind", shapeMap) {
            case Some(JsonString(s)) => s
            case _                   => "CircleShape2D"
        };
        let kindCommit = newKindStr ->
            commitEdit(state, prefix, JsonObject(defaultShapeFor(newKindStr)));
        content.add(createShapeKindRow(currentKind, kindCommit, indent));
        let rest = Map.remove("kind", shapeMap);
        renderObjectProperties(content, state, prefix, rest, indent)

    /// shape の "kind" 行 — 左にラベル、右に shape 種別を選ぶ JComboBox。
    def createShapeKindRow(currentKind: String, commit: String -> Unit \ IO,
                           indent: Int32): JPanel \ IO =
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(new Color(40, 40, 40));
        row.setBorder(BorderFactory.createEmptyBorder(3, 10 + indent * 16i32, 3, 10));
        row.setMaximumSize(new Dimension(9999, 28));
        row.setAlignmentX(0.0f32);

        let label = new JLabel("kind");
        label.setForeground(new Color(180, 180, 180));
        label.setPreferredSize(new Dimension(96, 22));
        row.add(label, BorderLayout.WEST);

        row.add(createShapeKindCombo(currentKind, commit), BorderLayout.CENTER);
        row

    /// shape 種別のドロップダウン本体。RectShape2D / CircleShape2D / CapsuleShape2D を提示。
    /// `currentKind` が未知の値なら一覧の先頭に挿入して選択状態にする
    /// （誤入力された scene.json を壊さないため）
    def createShapeKindCombo(currentKind: String, commit: String -> Unit \ IO):
                              JComboBox[String] \ IO =
        let options = "RectShape2D" :: "CircleShape2D" :: "CapsuleShape2D" :: Nil;
        let unknown = not List.memberOf(currentKind, options);
        let missingLabel = "<unknown>: ${currentKind}";
        let items = if (unknown) missingLabel :: options else options;
        let cb: JComboBox[String] = new JComboBox();
        List.forEach(n -> { cb.addItem(n); () }, items);
        cb.setSelectedItem(if (unknown) missingLabel else currentKind);
        cb.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                let idx = cb.getSelectedIndex();
                let chosen =
                    if (unknown) {
                        if (idx == 0) None
                        else List.nth(idx - 1, options)
                    } else List.nth(idx, options);
                match chosen {
                    case Some(name) =>
                        // 同じ kind を再選択しても、scene.json の他フィールドを
                        // 規定値で上書きする副作用は望ましくないのでスキップ
                        if (name == currentKind) ()
                        else commit(name)
                    case None => ()
                }
            }
        });
        cb

    /// 指定 kind に対応する shape JsonObject のデフォルト値を返す。
    /// kind 切替時に「兄弟フィールドが消える / 増える」のを賢く扱うため、
    /// 既存値は保持せず常に新規セットで上書きする
    def defaultShapeFor(kind: String): Map[String, Json.JsonElement] =
        match kind {
            case "RectShape2D" =>
                Map#{
                    "kind" => JsonString("RectShape2D"),
                    "width" => JsonNumber(unsafe IO { BigDecimal.valueOf(32.0).stripTrailingZeros() }),
                    "height" => JsonNumber(unsafe IO { BigDecimal.valueOf(32.0).stripTrailingZeros() })
                }
            case "CircleShape2D" =>
                Map#{
                    "kind" => JsonString("CircleShape2D"),
                    "radius" => JsonNumber(unsafe IO { BigDecimal.valueOf(16.0).stripTrailingZeros() })
                }
            case "CapsuleShape2D" =>
                Map#{
                    "kind" => JsonString("CapsuleShape2D"),
                    "radius" => JsonNumber(unsafe IO { BigDecimal.valueOf(16.0).stripTrailingZeros() }),
                    "height" => JsonNumber(unsafe IO { BigDecimal.valueOf(32.0).stripTrailingZeros() }),
                    "vertical" => JsonBool(true)
                }
            case _ => Map#{"kind" => JsonString(kind)}
        }

    /// 子プロパティを持つ Object 用のセクション見出し行 (Godot の category header 風)。
    /// 編集 widget は無く、ラベルだけ。下にインデントされた子 row が続く。
    def createSectionRow(name: String, indent: Int32): JPanel \ IO =
        let row = new JPanel(new BorderLayout());
        row.setBackground(new Color(50, 50, 55));
        row.setBorder(BorderFactory.createEmptyBorder(4, 10 + indent * 16i32, 4, 10));
        row.setMaximumSize(new Dimension(9999, 24));
        row.setAlignmentX(0.0f32);
        let lbl = new JLabel(name);
        lbl.setForeground(new Color(225, 225, 225));
        row.add(lbl, BorderLayout.WEST);
        row

    /// 1 プロパティ行: 左にキー名ラベル、右にプロパティ型に応じた widget。
    /// `commit` は widget が値変更を確定したときに「新しい JsonElement」を渡す callback。
    /// `indent` はネストの深さ。左余白に反映する。
    def createPropertyRow(state: IdeState, key: String, value: Json.JsonElement,
                          commit: Json.JsonElement -> Unit \ IO,
                          indent: Int32): JPanel \ IO =
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(new Color(40, 40, 40));
        row.setBorder(BorderFactory.createEmptyBorder(3, 10 + indent * 16i32, 3, 10));
        row.setMaximumSize(new Dimension(9999, 28));
        row.setAlignmentX(0.0f32);

        let label = new JLabel(key);
        label.setForeground(new Color(180, 180, 180));
        label.setPreferredSize(new Dimension(96, 22));
        row.add(label, BorderLayout.WEST);

        row.add(createPropertyWidget(state, key, value, commit), BorderLayout.CENTER);
        row

    /// プロパティ値の型 + キー名に基づいて適切な widget を返す。
    ///   key=="alpha"/"opacity" + JsonNumber → JSlider(0..100) — release 時に commit
    ///   key=="texture" + JsonString          → JComboBox (project.json の texture 名一覧)
    ///                                          名前リストが空のときは JTextField にフォールバック
    ///   JsonBool                              → JCheckBox — toggle で即 commit
    ///   JsonString                            → JTextField — Enter で commit (JsonString)
    ///   JsonNumber                            → JTextField — Enter で parse → commit (JsonNumber)
    ///   JsonArray [num, num]                  → X/Y 2 フィールド — どちらかの Enter で配列ごと commit
    ///   JsonArray (それ以外)                   → 編集不可サマリラベル
    ///   JsonObject                            → 編集不可サマリラベル
    def createPropertyWidget(state: IdeState, key: String, value: Json.JsonElement,
                             commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        if (isAlphaKey(key)) {
            match value {
                case JsonNumber(bd) => panel.add(createAlphaSlider(bd, commit), BorderLayout.CENTER)
                case _              => panel.add(createReadOnlyLabel("(not a number)"), BorderLayout.CENTER)
            }
        } else {
            match value {
                case JsonBool(b)    => panel.add(createBoolCheck(b, commit), BorderLayout.CENTER)
                case JsonString(s)  =>
                    if (key == "texture") {
                        let names = Array.get(0, state#textureNamesRef);
                        match names {
                            case Nil => panel.add(createStringInput(s, commit), BorderLayout.CENTER)
                            case _   => panel.add(createTextureSelector(s, names, commit), BorderLayout.CENTER)
                        }
                    } else
                        panel.add(createStringInput(s, commit), BorderLayout.CENTER)
                case JsonNumber(bd) => panel.add(createNumberInput(bd, commit), BorderLayout.CENTER)
                case JsonArray(items) =>
                    let elems = Vector.toList(items);
                    match elems {
                        case JsonNumber(bdX) :: JsonNumber(bdY) :: Nil =>
                            panel.add(createVec2Field(bdX, bdY, commit), BorderLayout.CENTER)
                        case _ =>
                            panel.add(createReadOnlyLabel("[Array: ${List.length(elems)} items]"), BorderLayout.CENTER)
                    }
                case JsonObject(m) =>
                    panel.add(createReadOnlyLabel("[Object: ${Map.size(m)} keys]"), BorderLayout.CENTER)
                case _ =>
                    panel.add(createReadOnlyLabel("(null)"), BorderLayout.CENTER)
            }
        };
        panel

    /// alpha/opacity 系キーを判定する
    def isAlphaKey(key: String): Bool =
        key == "alpha" or key == "opacity"

    /// 0.0..1.0 の値を 0..100 の JSlider にし、横に現在値ラベルを並べる。
    /// drag 中は label だけ更新し、release (not isAdjusting) で commit する。
    def createAlphaSlider(bd: BigDecimal, commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let alpha = bd.doubleValue();
        let raw = Float64.tryToInt32(alpha * 100.0) |> Option.getWithDefault(100i32);
        let clamped = if (raw < 0i32) 0i32 else if (raw > 100i32) 100i32 else raw;

        let slider = new JSlider(0, 100, clamped);
        slider.setBackground(new Color(40, 40, 40));
        slider.setForeground(Color.LIGHT_GRAY);

        let valLabel = new JLabel(formatBd(bd));
        valLabel.setForeground(new Color(180, 180, 180));
        valLabel.setPreferredSize(new Dimension(40, 22));

        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let cur = slider.getValue();
                let newAlpha = Int32.toFloat64(cur) / 100.0;
                let newBd = unsafe IO { BigDecimal.valueOf(newAlpha).stripTrailingZeros() };
                valLabel.setText(formatBd(newBd));
                if (not slider.getValueIsAdjusting()) commit(JsonNumber(newBd))
                else ()
            }
        });

        let panel = new JPanel(new BorderLayout(6, 0));
        panel.setBackground(new Color(40, 40, 40));
        panel.add(slider, BorderLayout.CENTER);
        panel.add(valLabel, BorderLayout.EAST);
        panel

    /// Bool プロパティ: ダーク背景のチェックボックス。toggle で即 commit。
    def createBoolCheck(b: Bool, commit: Json.JsonElement -> Unit \ IO): JCheckBox \ IO =
        let cb = new JCheckBox();
        cb.setSelected(b);
        cb.setBackground(new Color(40, 40, 40));
        cb.setForeground(Color.LIGHT_GRAY);
        cb.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                commit(JsonBool(cb.isSelected()))
        });
        cb

    /// String プロパティ: Enter で commit (JsonString)。
    def createStringInput(initial: String, commit: Json.JsonElement -> Unit \ IO): JTextField \ IO =
        let tf = new JTextField(initial);
        styleTextInput(tf);
        tf.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                commit(JsonString(tf.getText()))
        });
        tf

    /// texture フィールド用の dropdown。`names` は project.json で宣言された名前一覧。
    /// 既存値 `initial` が名前一覧に無い場合は先頭に "<missing>: initial" を入れて選択しておく
    /// (誤入力された scene.json を壊さないため + ユーザに状態を知らせるため)。
    /// 選択変更で commit(JsonString(name))。"<missing>: ..." を選び直すのは無意味なので
    /// その項目を選んだ場合は commit せず無視する。
    ///
    /// 色について: macOS Aqua L&F は JComboBox の閉じた状態 (button 部) をネイティブ描画し
    /// setBackground/setForeground を無視する。BasicComboBoxUI に切替えると selection color が
    /// macOS 紫を継承して逆に悪化したので、Aqua の見た目のままにしている。
    def createTextureSelector(initial: String, names: List[String],
                              commit: Json.JsonElement -> Unit \ IO): JComboBox[String] \ IO =
        let initialMissing = not List.memberOf(initial, names);
        let missingLabel = "<missing>: ${initial}";
        let items = if (initialMissing) missingLabel :: names else names;
        let cb: JComboBox[String] = new JComboBox();
        List.forEach(n -> { cb.addItem(n); () }, items);
        cb.setSelectedItem(if (initialMissing) missingLabel else initial);
        // JComboBox は同じ項目を再選択しても actionPerformed を発火しないので
        // 「現値と等しいか」のスキップは不要。素朴に index → 名前で commit する。
        cb.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                let idx = cb.getSelectedIndex();
                let chosen =
                    if (initialMissing) {
                        if (idx == 0) None             // <missing> を選び直しても意味は無い
                        else List.nth(idx - 1, names)
                    } else List.nth(idx, names);
                match chosen {
                    case Some(name) => commit(JsonString(name))
                    case None       => ()
                }
            }
        });
        cb

    /// Number プロパティ: Enter で parse → commit (JsonNumber)。parse 失敗時は無視。
    def createNumberInput(bd: BigDecimal, commit: Json.JsonElement -> Unit \ IO): JTextField \ IO =
        let tf = new JTextField(formatBd(bd));
        styleTextInput(tf);
        tf.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                match JsonOps.parseBigDecimal(tf.getText()) {
                    case Some(newBd) => commit(JsonNumber(newBd))
                    case None        => ()
                }
            }
        });
        tf

    /// 共通: ダークテーマ用の JTextField スタイル
    def styleTextInput(tf: JTextField): Unit \ IO =
        tf.setBackground(new Color(50, 50, 50));
        tf.setForeground(Color.LIGHT_GRAY);
        tf.setCaretColor(Color.WHITE);
        tf.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(new Color(70, 70, 70), 1),
            BorderFactory.createEmptyBorder(2, 4, 2, 4)
        ))

    /// 編集 widget を出せない / 出す意味がない場合の薄い灰色ラベル
    def createReadOnlyLabel(text: String): JLabel \ IO =
        let lbl = new JLabel(text);
        lbl.setForeground(new Color(140, 140, 140));
        lbl

    /// Vec2 プロパティ (pos/scale/size 等): Godot 風に X (赤系) と Y (緑系) の 2 列。
    /// どちらか片方の Enter で「両方のフィールドの現在値」を読んで配列ごと commit する。
    /// 片方が parse 失敗のときは何もしない。
    def createVec2Field(bdX: BigDecimal, bdY: BigDecimal,
                        commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let xField = new JTextField(formatBd(bdX));
        styleTextInput(xField);
        let yField = new JTextField(formatBd(bdY));
        styleTextInput(yField);

        let commitVec2 = () -> {
            match (JsonOps.parseBigDecimal(xField.getText()), JsonOps.parseBigDecimal(yField.getText())) {
                case (Some(newX), Some(newY)) =>
                    commit(JsonArray(Vector#{JsonNumber(newX), JsonNumber(newY)}))
                case _ => ()
            }
        };
        xField.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = commitVec2()
        });
        yField.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = commitVec2()
        });

        let panel = new JPanel(new GridLayout(1, 2, 6, 0));
        panel.setBackground(new Color(40, 40, 40));
        panel.add(wrapAxis("X", new Color(220, 110, 110), xField));
        panel.add(wrapAxis("Y", new Color(120, 200, 120), yField));
        panel

    /// 1 軸ぶんの「色付きラベル + テキストフィールド」ラッパ
    def wrapAxis(axisName: String, axisColor: Color, field: JTextField): JPanel \ IO =
        let panel = new JPanel(new BorderLayout(4, 0));
        panel.setBackground(new Color(40, 40, 40));
        let lbl = new JLabel(axisName);
        lbl.setForeground(axisColor);
        lbl.setPreferredSize(new Dimension(14, 22));
        panel.add(lbl, BorderLayout.WEST);
        panel.add(field, BorderLayout.CENTER);
        panel

    /// BigDecimal を見やすい文字列に。"2.8E+2" のような表記を避けるため toPlainString。
    def formatBd(bd: BigDecimal): String =
        bd.toPlainString()

    /// File メニューを構築する。
    /// Open Project... は JFileChooser でディレクトリを選ばせ、選択結果を
    /// `pendingProjectRef` に書き込んでから WindowEvent.WINDOW_CLOSING を dispatch する。
    /// 前回開いたパスを Preferences に記憶し、次回起動時の初期表示にも使う。
    def buildMenuBar(state: IdeState, frame: JFrame): JMenuBar \ IO =
        let menuBar = new JMenuBar();
        let fileMenu = new JMenu("File");

        let openItem = new JMenuItem("Open Project...");
        openItem.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                showOpenProjectChooser(state, frame)
        });
        fileMenu.add(openItem);

        menuBar.add(fileMenu);
        menuBar

    /// macOS ネイティブの NSOpenPanel をディレクトリ選択モードで開く。
    /// `apple.awt.fileDialogForDirectories=true` を直前にセットすると java.awt.FileDialog
    /// がディレクトリチューザとして振る舞い、VSCode などと同じサイドバー・←→ナビゲーション・
    /// 「開く」ボタンが使える。Swing の JFileChooser は L&F が古く UX が劣る。
    /// 起動時の初期ディレクトリは Preferences に保存した前回パスから復元する。
    def showOpenProjectChooser(state: IdeState, frame: JFrame): Unit \ IO =
        let prefs = Preferences.userRoot();

        // macOS 専用フラグ: AWT FileDialog をディレクトリチューザにする
        discard System.setProperty("apple.awt.fileDialogForDirectories", "true");

        let dialog = new FileDialog(frame, "Open Project", FileDialog.LOAD);

        // 前回開いたプロジェクトの親ディレクトリを初期表示に
        let lastDir = prefs.get("flix_ide_last_project_dir", "");
        if (not String.isEmpty(lastDir)) {
            let lastFile = new File(lastDir);
            if (lastFile.exists()) {
                let parent = lastFile.getParent();
                if (not Object.isNull(parent)) {
                    dialog.setDirectory(parent)
                } else ()
            } else ()
        } else ();

        dialog.setVisible(true);

        // ダイアログを閉じたらフラグを戻す (他の File I/O に影響しないように)
        discard System.setProperty("apple.awt.fileDialogForDirectories", "false");

        let dir = dialog.getDirectory();
        let file = dialog.getFile();
        if (Object.isNull(file)) {
            // キャンセル
            ()
        } else {
            // dir は末尾スラッシュ付き ("/Users/abab/Desktop/") なので単純連結
            let path = "${dir}${file}";
            println("[IdeUI] Open Project selected: ${path}");
            prefs.put("flix_ide_last_project_dir", path);
            Array.put(Some(path), 0, state#pendingProjectRef);
            showLoadingSplash(state, path);
            frame.dispatchEvent(new WindowEvent(frame, WindowEvent.WINDOW_CLOSING))
        }

    /// project ロード中に表示する小さい splash window を作って visible にする。
    /// state.loadingSplashRef に保存し、customize 側で dispose される。
    def showLoadingSplash(state: IdeState, path: String): Unit \ IO =
        let splash = new JFrame();
        splash.setUndecorated(true);
        splash.setSize(new Dimension(360, 110));

        // 画面中央に配置
        let screenSize = Toolkit.getDefaultToolkit().getScreenSize();
        let x = (screenSize.width - 360) / 2;
        let y = (screenSize.height - 110) / 2;
        splash.setLocation(x, y);

        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        panel.setBorder(BorderFactory.createEmptyBorder(16, 20, 16, 20));

        let titleLabel = new JLabel("Loading project...");
        titleLabel.setForeground(new Color(220, 220, 220));
        panel.add(titleLabel, BorderLayout.NORTH);

        let pathLabel = new JLabel(path);
        pathLabel.setForeground(new Color(160, 160, 160));
        panel.add(pathLabel, BorderLayout.CENTER);

        let progress = new JProgressBar();
        progress.setIndeterminate(true);
        panel.add(progress, BorderLayout.SOUTH);

        splash.add(panel);
        splash.setAlwaysOnTop(true);
        splash.setVisible(true);
        Array.put(Some(splash), 0, state#loadingSplashRef)
}
