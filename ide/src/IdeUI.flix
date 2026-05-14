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
    import javax.swing.tree.DefaultMutableTreeNode
    import javax.swing.tree.DefaultTreeModel
    import javax.swing.tree.DefaultTreeCellRenderer
    import javax.swing.tree.TreeSelectionModel
    import java.awt.BorderLayout
    import java.awt.Color
    import java.awt.Dimension
    import java.awt.Toolkit
    import java.awt.FileDialog
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import java.awt.event.WindowEvent
    import java.io.File
    import java.lang.System
    import java.util.prefs.Preferences
    import org.lwjgl.opengl.awt.AWTGLCanvas

    use Json.JsonElement.{JsonObject, JsonArray, JsonString}

    /// IDE のグローバル状態。EDT 上の UI イベントが Refs に書き、
    /// メインループ (Main.flix) と renderLoop が読む。
    ///   pendingProjectRef: File → Open Project... で選ばれたディレクトリ。Main の reload で消費。
    ///   pendingSceneRef:   scene リストで選ばれた scene の絶対パス。renderLoop が毎フレーム消費。
    ///   sceneFilesRef:     現プロジェクトの (絶対パス, 表示用相対パス) のペアリスト。
    ///   sceneTreeModelRef: 左パネル JTree の TreeModel。シーン選択時に root を差し替えて
    ///                      ノード階層 ([type] name) を表示する。
    pub type alias IdeState = {
        pendingProjectRef = Array[Option[String], Static],
        pendingSceneRef   = Array[Option[String], Static],
        sceneFilesRef     = Array[List[(String, String)], Static],
        loadingSplashRef  = Array[Option[JFrame], Static],
        sceneTreeModelRef = Array[Option[DefaultTreeModel], Static]
    }

    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef = Array#{(None: Option[String])} @ Static,
            pendingSceneRef   = Array#{(None: Option[String])} @ Static,
            sceneFilesRef     = Array#{(Nil: List[(String, String)])} @ Static,
            loadingSplashRef  = Array#{(None: Option[JFrame])} @ Static,
            sceneTreeModelRef = Array#{(None: Option[DefaultTreeModel])} @ Static
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
        let inspectorPanel = new JPanel(new BorderLayout());
        inspectorPanel.setBackground(new Color(40, 40, 40));
        let inspectorLabel = new JLabel("  Inspector");
        inspectorLabel.setForeground(Color.LIGHT_GRAY);
        inspectorPanel.add(inspectorLabel, BorderLayout.NORTH);

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

        let scroll = new JScrollPane(tree);
        scroll.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        scroll.getViewport().setBackground(new Color(35, 35, 35));
        panel.add(scroll, BorderLayout.CENTER);
        panel

    /// JSON 要素を Swing の TreeNode に再帰変換する。
    /// JsonObject の場合は "type" と "name" を取り出してラベルにし、"children" 配列を再帰展開する。
    /// JsonArray の場合は合成ルートの下に各要素の subtree を並べる。
    /// それ以外の形は "<invalid>" ノードに落とす（IDE 全体をクラッシュさせないため）。
    def jsonToTreeNode(elem: Json.JsonElement): DefaultMutableTreeNode \ IO =
        match elem {
            case JsonObject(map) =>
                let nodeType = match Map.get("type", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "Node"
                };
                let nodeName = match Map.get("name", map) {
                    case Some(JsonString(s)) => s
                    case _                   => "<unnamed>"
                };
                let parent = new DefaultMutableTreeNode("[${nodeType}] ${nodeName}");
                match Map.get("children", map) {
                    case Some(JsonArray(children)) =>
                        Vector.toList(children) |> List.forEach(child -> {
                            let childNode = jsonToTreeNode(child);
                            parent.add(childNode)
                        })
                    case _ => ()
                };
                parent
            case JsonArray(items) =>
                let parent = new DefaultMutableTreeNode("<root array>");
                Vector.toList(items) |> List.forEach(child -> {
                    let childNode = jsonToTreeNode(child);
                    parent.add(childNode)
                });
                parent
            case _ => new DefaultMutableTreeNode("<invalid>")
        }

    /// 絶対パスから scene.json を読み、木を再構築して state#sceneTreeModelRef の root を差し替える。
    /// EDT の listener から呼ばれるため、Fs.FileRead エフェクトはこの関数内で discharge する
    /// （listener のシグネチャは `Unit \ IO` 固定）。
    /// 読み込み・パース失敗時はクラッシュさせず、エラーラベルのみのツリーを表示する。
    def populateSceneTree(state: IdeState, absPath: String): Unit \ IO =
        let readResult = run {
            Fs.ReadFile.read(absPath)
        } with Fs.ReadFile.runWithFileRead with Fs.FileRead.runWithIO;
        let newRoot = match readResult {
            case Err(e)   => new DefaultMutableTreeNode("(read error: ${e})")
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None      => new DefaultMutableTreeNode("(JSON parse failed)")
                    case Some(json) => jsonToTreeNode(json)
                }
        };
        match Array.get(0, state#sceneTreeModelRef) {
            case Some(model) => model.setRoot(newRoot)
            case None        => ()
        }

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
