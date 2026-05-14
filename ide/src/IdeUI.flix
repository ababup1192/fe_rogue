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

    /// IDE のグローバル状態。EDT 上の UI イベントが Refs に書き、
    /// メインループ (Main.flix) と renderLoop が読む。
    ///   pendingProjectRef:    File → Open Project... で選ばれたディレクトリ。Main の reload で消費。
    ///   pendingSceneRef:      scene リストで選ばれた scene の絶対パス。renderLoop が毎フレーム消費。
    ///   sceneFilesRef:        現プロジェクトの (絶対パス, 表示用相対パス) のペアリスト。
    ///   sceneTreeModelRef:    左パネル JTree の TreeModel。シーン選択時に root を差し替える。
    ///   nodeJsonMapRef:       tree ノードの identityHashCode → 対応する JsonElement。
    ///                         Tree 選択時に Inspector が JSON プロパティを引くのに使う。
    ///   inspectorContentRef:  Inspector 本体の JPanel (BoxLayout)。ノード選択ごとに
    ///                         removeAll → 再構築する。
    pub type alias IdeState = {
        pendingProjectRef   = Array[Option[String], Static],
        pendingSceneRef     = Array[Option[String], Static],
        sceneFilesRef       = Array[List[(String, String)], Static],
        loadingSplashRef    = Array[Option[JFrame], Static],
        sceneTreeModelRef   = Array[Option[DefaultTreeModel], Static],
        nodeJsonMapRef      = Array[Map[Int32, Json.JsonElement], Static],
        inspectorContentRef = Array[Option[JPanel], Static]
    }

    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef   = Array#{(None: Option[String])} @ Static,
            pendingSceneRef     = Array#{(None: Option[String])} @ Static,
            sceneFilesRef       = Array#{(Nil: List[(String, String)])} @ Static,
            loadingSplashRef    = Array#{(None: Option[JFrame])} @ Static,
            sceneTreeModelRef   = Array#{(None: Option[DefaultTreeModel])} @ Static,
            nodeJsonMapRef      = Array#{(Map.empty(): Map[Int32, Json.JsonElement])} @ Static,
            inspectorContentRef = Array#{(None: Option[JPanel])} @ Static
        }

    pub def takePendingProject(state: IdeState): Option[String] \ IO =
        let p = Array.get(0, state#pendingProjectRef);
        Array.put(None, 0, state#pendingProjectRef);
        p

    pub def takePendingScene(state: IdeState): Option[String] \ IO =
        let p = Array.get(0, state#pendingSceneRef);
        Array.put(None, 0, state#pendingSceneRef);
        p

    pub def setSceneFiles(state: IdeState, files: List[(String, String)]): Unit \ IO =
        Array.put(files, 0, state#sceneFilesRef)

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

        // 選択ノードに対応する JsonElement を nodeJsonMap から引いて Inspector を更新する。
        // 取得は identityHashCode(node) ベース。シーン再読込で map がリセットされるため、
        // 古いノードに対する取得は自然と None になる。
        tree.addTreeSelectionListener(new TreeSelectionListener {
            def valueChanged(_this: TreeSelectionListener, _e: TreeSelectionEvent): Unit \ IO = {
                let selected = tree.getLastSelectedPathComponent();
                if (Object.isNull(selected)) ()
                else {
                    let id = System.identityHashCode(selected);
                    match Map.get(id, Array.get(0, state#nodeJsonMapRef)) {
                        case Some(json) => updateInspector(state, json)
                        case None       => ()
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
    /// JsonObject の場合は "type" と "name" を取り出してラベルにし、"children" 配列を再帰展開する。
    /// JsonArray の場合は合成ルートの下に各要素の subtree を並べる。
    /// それ以外の形は "<invalid>" ノードに落とす（IDE 全体をクラッシュさせないため）。
    /// 同時に nodeJsonMap に identityHashCode(node) → elem を登録し、Tree 選択時に
    /// Inspector が JsonElement を引けるようにする。
    def jsonToTreeNode(elem: Json.JsonElement, state: IdeState): DefaultMutableTreeNode \ IO =
        let label = match elem {
            case JsonObject(map) =>
                let nodeType = match Map.get("type", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "Node"
                };
                let nodeName = match Map.get("name", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "<unnamed>"
                };
                "[${nodeType}] ${nodeName}"
            case JsonArray(_) => "<root array>"
            case _            => "<invalid>"
        };
        let node = new DefaultMutableTreeNode(label);
        let id = System.identityHashCode(node);
        Array.put(Map.insert(id, elem, Array.get(0, state#nodeJsonMapRef)), 0, state#nodeJsonMapRef);

        match elem {
            case JsonObject(map) =>
                match Map.get("children", map) {
                    case Some(JsonArray(children)) =>
                        Vector.toList(children) |> List.forEach(child -> {
                            let childNode = jsonToTreeNode(child, state);
                            node.add(childNode)
                        })
                    case _ => ()
                }
            case JsonArray(items) =>
                Vector.toList(items) |> List.forEach(child -> {
                    let childNode = jsonToTreeNode(child, state);
                    node.add(childNode)
                })
            case _ => ()
        };
        node

    /// 絶対パスから scene.json を読み、木を再構築して state#sceneTreeModelRef の root を差し替える。
    /// 同時に nodeJsonMap をリセットし、Inspector を placeholder に戻す。
    /// EDT の listener から呼ばれるため、Fs.FileRead エフェクトはこの関数内で discharge する
    /// （listener のシグネチャは `Unit \ IO` 固定）。
    /// 読み込み・パース失敗時はクラッシュさせず、エラーラベルのみのツリーを表示する。
    def populateSceneTree(state: IdeState, absPath: String): Unit \ IO =
        Array.put(Map.empty(), 0, state#nodeJsonMapRef);
        let readResult = run {
            Fs.ReadFile.read(absPath)
        } with Fs.ReadFile.runWithFileRead with Fs.FileRead.runWithIO;
        let newRoot = match readResult {
            case Err(e)   => new DefaultMutableTreeNode("(read error: ${e})")
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None      => new DefaultMutableTreeNode("(JSON parse failed)")
                    case Some(json) => jsonToTreeNode(json, state)
                }
        };
        match Array.get(0, state#sceneTreeModelRef) {
            case Some(model) => model.setRoot(newRoot)
            case None        => ()
        };
        resetInspectorPlaceholder(state)

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
                        Map.foldLeftWithKey((_acc, key, value) -> {
                            if (key == "children" or key == "type" or key == "name") ()
                            else {
                                let row = createPropertyRow(key, value);
                                content.add(row);
                                ()
                            }
                        }, (), propMap);
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

    /// 1 プロパティ行: 左にキー名ラベル、右にプロパティ型に応じた widget。
    def createPropertyRow(key: String, value: Json.JsonElement): JPanel \ IO =
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(new Color(40, 40, 40));
        row.setBorder(BorderFactory.createEmptyBorder(3, 10, 3, 10));
        row.setMaximumSize(new Dimension(9999, 28));
        row.setAlignmentX(0.0f32);

        let label = new JLabel(key);
        label.setForeground(new Color(180, 180, 180));
        label.setPreferredSize(new Dimension(96, 22));
        row.add(label, BorderLayout.WEST);

        row.add(createPropertyWidget(key, value), BorderLayout.CENTER);
        row

    /// プロパティ値の型 + キー名に基づいて適切な widget を返す。
    /// 編集はまだ wire していないが、見た目だけ Godot 風に揃える。
    ///   key=="alpha"/"opacity" + JsonNumber → JSlider(0..100)
    ///   JsonBool                              → JCheckBox
    ///   JsonString                            → JTextField
    ///   JsonNumber                            → JTextField (数値整形)
    ///   JsonArray [num, num]                  → X/Y 2 フィールド (Vec2)
    ///   JsonArray (それ以外)                   → サマリラベル
    ///   JsonObject                            → サマリラベル
    def createPropertyWidget(key: String, value: Json.JsonElement): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        if (isAlphaKey(key)) {
            match value {
                case JsonNumber(bd) => panel.add(createAlphaSlider(bd), BorderLayout.CENTER)
                case _              => panel.add(createReadOnlyLabel("(not a number)"), BorderLayout.CENTER)
            }
        } else {
            match value {
                case JsonBool(b)    => panel.add(createBoolCheck(b), BorderLayout.CENTER)
                case JsonString(s)  => panel.add(createTextInput(s), BorderLayout.CENTER)
                case JsonNumber(bd) => panel.add(createTextInput(formatBd(bd)), BorderLayout.CENTER)
                case JsonArray(items) =>
                    let elems = Vector.toList(items);
                    match elems {
                        case JsonNumber(bdX) :: JsonNumber(bdY) :: Nil =>
                            panel.add(createVec2Field(bdX, bdY), BorderLayout.CENTER)
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

    /// 0.0..1.0 の値を 0..100 の JSlider にし、横に現在値ラベルを並べる
    def createAlphaSlider(bd: BigDecimal): JPanel \ IO =
        let panel = new JPanel(new BorderLayout(6, 0));
        panel.setBackground(new Color(40, 40, 40));

        let alpha = bd.doubleValue();
        let raw = Float64.tryToInt32(alpha * 100.0) |> Option.getWithDefault(100i32);
        let clamped = if (raw < 0i32) 0i32 else if (raw > 100i32) 100i32 else raw;

        let slider = new JSlider(0, 100, clamped);
        slider.setBackground(new Color(40, 40, 40));
        slider.setForeground(Color.LIGHT_GRAY);
        panel.add(slider, BorderLayout.CENTER);

        let valLabel = new JLabel(formatBd(bd));
        valLabel.setForeground(new Color(180, 180, 180));
        valLabel.setPreferredSize(new Dimension(40, 22));
        panel.add(valLabel, BorderLayout.EAST);
        panel

    /// Bool プロパティ: ダーク背景のチェックボックス
    def createBoolCheck(b: Bool): JCheckBox \ IO =
        let cb = new JCheckBox();
        cb.setSelected(b);
        cb.setBackground(new Color(40, 40, 40));
        cb.setForeground(Color.LIGHT_GRAY);
        cb

    /// String/Number 共通の文字列入力フィールド
    def createTextInput(text: String): JTextField \ IO =
        let tf = new JTextField(text);
        tf.setBackground(new Color(50, 50, 50));
        tf.setForeground(Color.LIGHT_GRAY);
        tf.setCaretColor(Color.WHITE);
        tf.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(new Color(70, 70, 70), 1),
            BorderFactory.createEmptyBorder(2, 4, 2, 4)
        ));
        tf

    /// 編集 widget を出せない / 出す意味がない場合の薄い灰色ラベル
    def createReadOnlyLabel(text: String): JLabel \ IO =
        let lbl = new JLabel(text);
        lbl.setForeground(new Color(140, 140, 140));
        lbl

    /// Vec2 プロパティ (pos/scale/size 等): Godot 風に X (赤系) と Y (緑系) の 2 列。
    def createVec2Field(bdX: BigDecimal, bdY: BigDecimal): JPanel \ IO =
        let panel = new JPanel(new GridLayout(1, 2, 6, 0));
        panel.setBackground(new Color(40, 40, 40));
        panel.add(createAxisField("X", new Color(220, 110, 110), bdX));
        panel.add(createAxisField("Y", new Color(120, 200, 120), bdY));
        panel

    /// 1 軸ぶんの入力フィールド (ラベル + テキスト)
    def createAxisField(axisName: String, axisColor: Color, bd: BigDecimal): JPanel \ IO =
        let panel = new JPanel(new BorderLayout(4, 0));
        panel.setBackground(new Color(40, 40, 40));
        let lbl = new JLabel(axisName);
        lbl.setForeground(axisColor);
        lbl.setPreferredSize(new Dimension(14, 22));
        panel.add(lbl, BorderLayout.WEST);
        panel.add(createTextInput(formatBd(bd)), BorderLayout.CENTER);
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
