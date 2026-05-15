// IdeUI — IDE のフレームレイアウトとメニュー処理。SwingLayer から呼ばれる
// `customizeFrame` コールバックを提供する。
//
// 役割:
//   - 大きめのウィンドウサイズ + BorderLayout
//     - frame.NORTH  = タブバー (Scenes / Resources モード切替)
//     - frame.WEST   = scene-tree (Scenes モード時のみ)
//     - frame.CENTER = centerEastSplit (canvas + Inspector/SceneFiles) または resourcesTab
//     - frame.SOUTH  = ステータスバー (Scenes モード時のみ)
//   - JMenuBar に File → Open Project... を追加
//   - File チューザでプロジェクトディレクトリを選ばせ、`pendingProjectRef` に保存
//     + WindowEvent.WINDOW_CLOSING を dispatch して SwingLayer.withSwing を抜けさせる
//   - 右下の scene ファイルリストをクリックすると `pendingSceneRef` を更新し、
//     同時に左の scene-tree も該当 JSON で再構築する
//
// タブ切替の実装方針:
//   AWTGLCanvas (heavyweight) を JTabbedPane や CardLayout に入れると、Mac の AWT で
//   lightweight 兄弟 component の paint と衝突して canvas 周辺に白い paint 漏れが出る。
//   そのため frame.NORTH に独自タブバーを置き、タブ切替時に frame レベルで
//   westPanel/centerEastSplit/southPanel と resourcesTab を物理的に入れ替える方式にしている。
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
    import javax.swing.JToggleButton
    import javax.swing.ButtonGroup
    import javax.swing.JCheckBox
    import javax.swing.JTextField
    import javax.swing.JTextArea
    import javax.swing.JComboBox
    import javax.swing.JSlider
    import javax.swing.JSpinner
    import javax.swing.SpinnerNumberModel
    import javax.swing.JColorChooser
    import javax.swing.SwingConstants
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
    import javax.swing.tree.TreePath
    import javax.swing.tree.TreeSelectionModel
    import java.awt.BorderLayout
    import java.awt.Color
    import java.awt.Dimension
    import java.awt.GridLayout
    import java.awt.FlowLayout
    import java.awt.Toolkit
    import java.awt.FileDialog
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import java.awt.event.WindowEvent
    import java.awt.event.FocusAdapter
    import java.awt.event.FocusEvent
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
        frame.getContentPane().setBackground(new Color(28, 28, 28));
        // ResourceEditorUI から JOptionPane の parent component として使えるよう、
        // メイン frame を ResourceState に登録しておく。
        ResourceState.setMainFrame(state#resource, frame);

        // Scenes モードの 3 component (frame.WEST/CENTER/SOUTH) と Resources tab を事前構築。
        // 旧 IDE と同じ frame 階層 (frame.CENTER.centerEastSplit.left.centerPanel に canvas) を
        // 保つことで heavyweight canvas のレイアウトを最も安定させる。
        let westPanel = buildSceneTreePanel(state);
        westPanel.setPreferredSize(new Dimension(300, 0));
        let centerEastSplit = buildCenterEastSplit(state, canvas);
        let southPanel = buildStatusBar();

        let resourcesTab = ResourceEditorUI.buildTab(state);

        // タブバー (frame.NORTH に常駐)
        let tabBar = buildTabBar(state, frame, canvas, westPanel, centerEastSplit, southPanel, resourcesTab);

        // 初期状態は Scenes モード
        frame.add(tabBar, BorderLayout.NORTH);
        frame.add(westPanel, BorderLayout.WEST);
        frame.add(centerEastSplit, BorderLayout.CENTER);
        frame.add(southPanel, BorderLayout.SOUTH);

        // メニューバー (frame レベル、タブと無関係)
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

    /// frame.NORTH に置くタブバー。Scenes / Resources の JToggleButton を持ち、
    /// 切替時に frame の WEST/CENTER/SOUTH と CENTER (resourcesTab) を入れ替える。
    /// 選択中のボタンは明るい背景で「前に出ている」ように見せる (タブっぽい UI)。
    def buildTabBar(state: IdeState, frame: JFrame, canvas: AWTGLCanvas,
                    westPanel: JPanel, centerEastSplit: JSplitPane, southPanel: JPanel,
                    resourcesTab: JPanel): JPanel \ IO =
        let _ = state;
        let tabBar = new JPanel(new FlowLayout(FlowLayout.LEFT, 4, 0));
        tabBar.setBackground(new Color(35, 35, 35));
        tabBar.setBorder(BorderFactory.createMatteBorder(0, 0, 1, 0, new Color(60, 60, 60)));

        let scenesBtn = new JToggleButton("Scenes", true);
        let resourcesBtn = new JToggleButton("Resources");
        let group = new ButtonGroup();
        group.add(scenesBtn);
        group.add(resourcesBtn);
        styleTabButton(scenesBtn, true);
        styleTabButton(resourcesBtn, false);
        tabBar.add(scenesBtn);
        tabBar.add(resourcesBtn);

        // 選択状態の変化に追随して見た目を更新。ButtonGroup により片方が selected になれば
        // もう片方は automatically deselect されるので、両方の stateChanged を聞く。
        let restyleBoth = () -> {
            styleTabButton(scenesBtn, scenesBtn.isSelected());
            styleTabButton(resourcesBtn, resourcesBtn.isSelected())
        };
        scenesBtn.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = restyleBoth()
        });
        resourcesBtn.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = restyleBoth()
        });

        scenesBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                let cp = frame.getContentPane();
                // Resources 側の lightweight component を完全に hide してから remove。
                // setVisible(false) を呼ばないと Mac AWT で widget が canvas の上に
                // 残ったまま見えることがある。
                resourcesTab.setVisible(false);
                cp.remove(resourcesTab);
                cp.add(westPanel, BorderLayout.WEST);
                cp.add(centerEastSplit, BorderLayout.CENTER);
                cp.add(southPanel, BorderLayout.SOUTH);
                canvas.setVisible(true);
                frame.revalidate();
                frame.repaint()
            }
        });
        resourcesBtn.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                // Mac の AWTGLCanvas は setVisible(false) だけでは native window が残り、
                // Resources の lightweight component を覆い隠す。サイズ 0 + 画面外座標で
                // 物理的に隠す (再度 Scenes に切替えた時に BorderLayout が再レイアウトで戻す)。
                canvas.setVisible(false);
                canvas.setBounds(-10000, -10000, 0, 0);
                let cp = frame.getContentPane();
                cp.remove(westPanel);
                cp.remove(centerEastSplit);
                cp.remove(southPanel);
                resourcesTab.setVisible(true);
                cp.add(resourcesTab, BorderLayout.CENTER);
                frame.revalidate();
                frame.repaint()
            }
        });
        tabBar

    /// タブ風 JToggleButton のスタイル。選択時は明るい背景で「前に出ている」ように、
    /// 非選択時はタブバーと一体化した暗い背景にする。Mac の Aqua LAF が setBackground を
    /// 無視しないよう setContentAreaFilled(true) と setOpaque(true) を設定する。
    def styleTabButton(btn: JToggleButton, isSelected: Bool): Unit \ IO =
        btn.setOpaque(true);
        btn.setContentAreaFilled(true);
        btn.setFocusPainted(false);
        btn.setBorderPainted(true);
        if (isSelected) {
            btn.setBackground(new Color(60, 60, 80));
            btn.setForeground(new Color(235, 235, 245));
            btn.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(2, 1, 0, 1, new Color(110, 130, 200)),
                BorderFactory.createEmptyBorder(4, 12, 4, 12)))
        } else {
            btn.setBackground(new Color(35, 35, 35));
            btn.setForeground(new Color(150, 150, 150));
            btn.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(1, 1, 1, 1, new Color(60, 60, 60)),
                BorderFactory.createEmptyBorder(3, 12, 3, 12)))
        }

    /// frame.SOUTH に置く 22px のステータスバー (現状は灰色の帯のみ、将来 dirty 表示やメッセージを出す)。
    def buildStatusBar(): JPanel \ IO =
        let panel = new JPanel();
        panel.setPreferredSize(new Dimension(0, 22));
        panel.setBackground(new Color(50, 50, 50));
        panel

    /// 中央列 (canvas を含む centerPanel) と東列 (Inspector + Scene Files) を
    /// 1 つの JSplitPane にまとめて返す。frame.CENTER に直接置かれる。
    def buildCenterEastSplit(state: IdeState, canvas: AWTGLCanvas): JSplitPane \ IO =
        // 中央: scene preview (canvas)
        let centerPanel = new JPanel(new BorderLayout());
        centerPanel.setBackground(new Color(20, 20, 20));
        centerPanel.setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));
        canvas.setBackground(new Color(20, 20, 20));
        centerPanel.add(canvas, BorderLayout.CENTER);
        centerPanel.setMinimumSize(new Dimension(400, 0));

        // 右: 上 = Inspector / 下 = Scene Files の縦分割
        let inspectorPanel = buildInspectorPanel(state);
        let scenesPanel = buildScenesPanel(state);

        let eastSplit = new JSplitPane(JSplitPane.VERTICAL_SPLIT, inspectorPanel, scenesPanel);
        eastSplit.setDividerLocation(400);
        eastSplit.setResizeWeight(0.5);
        eastSplit.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        eastSplit.setPreferredSize(new Dimension(300, 0));
        eastSplit.setMinimumSize(new Dimension(220, 0));
        eastSplit.setBackground(new Color(28, 28, 28));

        let centerEastSplit = new JSplitPane(JSplitPane.HORIZONTAL_SPLIT, centerPanel, eastSplit);
        centerEastSplit.setDividerLocation(1280 - 300 - 300 - 8);
        centerEastSplit.setResizeWeight(1.0);
        centerEastSplit.setContinuousLayout(true);
        centerEastSplit.setDividerSize(8);
        centerEastSplit.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
        centerEastSplit.setBackground(new Color(28, 28, 28));
        centerEastSplit

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
        Array.put(Some(tree), 0, state#sceneTreeRef);
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

    /// preview クリック等で `selectedNodePathRef` が editor 側から書き換わった直後に呼ぶ。
    /// JTree のハイライトを最新の選択に合わせ、Inspector を該当ノードで再構築する。
    /// JTree の TreeSelectionListener が再発火しないよう、setSelectionPath 中は
    /// `treeListenerMuteRef` を立てる
    pub def applySelectionToView(state: IdeState): Unit \ IO =
        match (Array.get(0, state#sceneTreeRef),
               Array.get(0, state#sceneTreeModelRef)) {
            case (Some(tree), Some(model)) =>
                let selected = Array.get(0, state#selectedNodePathRef);
                applyTreeSelection(state, tree, model, selected);
                applyInspectorSelection(state, selected)
            case _ => ()
        }

    /// JTree の見た目選択を `selected` に合わせる。listener loop を防ぐためミュート下で呼ぶ
    def applyTreeSelection(state: IdeState, tree: JTree, model: DefaultTreeModel,
                            selected: Option[List[Int32]]): Unit \ IO =
        match selected {
            case None =>
                IdeState.setTreeListenerMuted(state, true);
                tree.clearSelection();
                IdeState.setTreeListenerMuted(state, false)
            case Some(indices) =>
                match buildTreePath(model, indices) {
                    case None => ()
                    case Some(path) =>
                        IdeState.setTreeListenerMuted(state, true);
                        tree.setSelectionPath(path);
                        tree.scrollPathToVisible(path);
                        IdeState.setTreeListenerMuted(state, false)
                }
        }

    /// Inspector を現選択ノードの JSON 値で再構築する。未選択なら placeholder に戻す
    def applyInspectorSelection(state: IdeState, selected: Option[List[Int32]]): Unit \ IO =
        match selected {
            case None => resetInspectorPlaceholder(state)
            case Some(indices) =>
                match Array.get(0, state#currentSceneJsonRef) {
                    case None => ()
                    case Some(sceneRoot) =>
                        match JsonOps.getAtNodePath(sceneRoot, indices) {
                            case Some(json) => updateInspector(state, json)
                            case None       => ()
                        }
                }
        }

    /// `indices` (ルートからの子インデックス列) を JTree の TreePath に変換する。
    /// 途中のインデックスが child 範囲外なら None。
    /// Object 型を Flix の関数シグネチャに直接書くと stdlib の `Object` モジュールと
    /// 衝突するため、Ref を経由して型推論に任せる
    def buildTreePath(model: DefaultTreeModel, indices: List[Int32]):
            Option[TreePath] \ IO =
        let root = model.getRoot();
        if (Object.isNull(root)) None
        else
            region rc {
                let nodeRef = Ref.fresh(rc, root);
                let pathRef = Ref.fresh(rc, new TreePath(root));
                let failedRef = Ref.fresh(rc, false);
                List.forEach(idx -> {
                    if (Ref.get(failedRef)) ()
                    else {
                        let current = Ref.get(nodeRef);
                        let child = model.getChild(current, idx);
                        if (Object.isNull(child)) Ref.put(true, failedRef)
                        else {
                            Ref.put(child, nodeRef);
                            Ref.put(Ref.get(pathRef).pathByAddingChild(child), pathRef)
                        }
                    }
                }, indices);
                if (Ref.get(failedRef)) None
                else Some(Ref.get(pathRef))
            }

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
        // setRoot は JTree の expansion state をリセットするため、ルート以外の子は
        // 折り畳まれた状態になる。HotReload (Inspector commit / preview ドラッグ確定)
        // のたびに「以前展開していた所が閉じる」ので、再構築直後に全ノードを expand
        // し直して兄弟ノードが消えないようにする。
        match Array.get(0, state#sceneTreeRef) {
            case Some(tree) => expandAllRows(tree, 0i32)
            case None       => ()
        };
        resetInspectorPlaceholder(state)

    /// JTree の全行を展開する。expandRow は新たな子行を露出させ getRowCount を増やすため、
    /// 単純に index を進めながら現在の行数を毎回読み直して末尾まで降りる。
    def expandAllRows(tree: JTree, i: Int32): Unit \ IO =
        if (i >= tree.getRowCount()) ()
        else {
            tree.expandRow(i);
            expandAllRows(tree, i + 1i32)
        }

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
        // 縦スクロール時に末尾の行が viewport 下端ピッタリで詰まって見えないよう、
        // content 自体の下端に余白を入れる
        content.setBorder(BorderFactory.createEmptyBorder(0, 0, 16, 0));
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
                        renderTopLevelGroups(content, state, propMap);
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

    /// Inspector の先頭に出す「ノード名」ヘッダ。タイプ表示は直後のクラス見出し
    /// (`createClassHeaderRow`) と重複するためここには出さない。
    /// `nodeType` 引数はシグネチャ互換のため残しているが現状未使用
    def createInspectorHeader(_nodeType: String, nodeName: String): JPanel \ IO =
        let header = new JPanel(new BorderLayout());
        header.setBackground(new Color(55, 55, 60));
        header.setBorder(BorderFactory.createEmptyBorder(6, 10, 6, 10));
        header.setMaximumSize(new Dimension(9999, 26));
        header.setAlignmentX(0.0f32);

        let nameLabel = new JLabel(nodeName);
        nameLabel.setForeground(Color.WHITE);
        header.add(nameLabel, BorderLayout.WEST);
        header

    /// JsonObject を再帰的にレンダリングする（ネスト object 用）。
    /// 最上位は `renderTopLevelGroups` で Godot 風グループ表示を使うので、
    /// ここに来るのは主にネスト object (shape, spriteFrames 等) のレンダリング。
    /// `prefix` は選択ノード直下からのキー列。commit は `prefix ::: key :: Nil` で
    /// commitEdit に渡され、JsonOps.setAtNodePath で末端まで降りて差し替えられる。
    /// `indent` はインデントレベル (0 から増える)、行の左余白を増やすのに使う。
    /// 最上位 (prefix = Nil) では children/type/name は header で扱うので個別行は出さない。
    def renderObjectProperties(content: JPanel, state: IdeState, prefix: List[String],
                                obj: Map[String, Json.JsonElement], indent: Int32): Unit \ IO =
        Map.foldLeftWithKey((_acc, key, value) -> {
            if (List.isEmpty(prefix) and (key == "children" or key == "type" or key == "name")) ()
            else renderOneProperty(content, state, prefix, obj, key, value, indent)
        }, (), obj)

    /// 1 キー分のレンダリング。renderObjectProperties (alphabetical) からも
    /// renderTopLevelGroups (グループ順) からも同じロジックを使う。
    /// value の種類で widget 1 行 / セクション + 子再帰 / カラーピッカー等を切り替える
    def renderOneProperty(content: JPanel, state: IdeState, prefix: List[String],
                          obj: Map[String, Json.JsonElement],
                          key: String, value: Json.JsonElement, indent: Int32): Unit \ IO =
        let subPrefix = prefix ::: key :: Nil;
        let commit = newVal -> commitEdit(state, subPrefix, newVal);
        match value {
            case JsonObject(nested) =>
                if (key == "shape" and Map.memberOf("kind", nested)) {
                    content.add(createSectionRow(key, indent));
                    renderShapeObject(content, state, subPrefix, nested, indent + 1i32)
                } else if (isColorObject(nested)) {
                    let row = createPropertyRowWidget(key,
                        createColorPicker(nested, commit), indent);
                    content.add(row);
                    ()
                } else {
                    content.add(createSectionRow(key, indent));
                    renderObjectProperties(content, state, subPrefix, nested, indent + 1i32)
                }
            case JsonArray(items) =>
                let elems = Vector.toList(items);
                match elems {
                    case JsonNumber(_) :: JsonNumber(_) :: Nil =>
                        let row = createPropertyRow(state, key, value, obj, commit, indent);
                        content.add(row);
                        ()
                    case _ =>
                        content.add(createSectionRow("${key} (${List.length(elems)})", indent));
                        renderArrayProperties(content, state, subPrefix, elems, indent + 1i32)
                }
            case JsonString(s) if key == "text" => {
                // text は多行入力 (JTextArea)。行高 (28px) を上書きして JTextArea を見せる
                let row = createTallPropertyRow(key,
                    createMultilineStringInput(s, commit), indent, 80i32);
                content.add(row);
                ()
            }
            case _ => {
                let row = createPropertyRow(state, key, value, obj, commit, indent);
                content.add(row);
                ()
            }
        }

    /// 高さ可変なプロパティ行。ラベル + 高さ最大値を上書きできる widget を並べる。
    /// JTextArea を含む `text` 行のように、widget 自身が複数行を要求するケース用。
    /// widget は BorderLayout.CENTER に直接置き、横幅を行いっぱいに伸ばす
    def createTallPropertyRow(key: String, widget: JScrollPane, indent: Int32,
                               heightPx: Int32): JPanel \ IO =
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(new Color(40, 40, 40));
        row.setBorder(BorderFactory.createEmptyBorder(3, 10 + indent * 16i32, 3, 10));
        row.setMaximumSize(new Dimension(9999, heightPx));
        row.setAlignmentX(0.0f32);
        let label = new JLabel(key);
        label.setForeground(new Color(180, 180, 180));
        label.setPreferredSize(new Dimension(80, 22));
        row.add(label, BorderLayout.NORTH);
        row.add(widget, BorderLayout.CENTER);
        row

    /// 最上位 (選択ノード直下) のプロパティを Godot Inspector 風にグループ表示する。
    /// 表示順:
    ///   1. グループに属さない「ユーザ定義 / その他」キー (custom properties など) を先頭に直接出す
    ///   2. クラスグループを派生順 → ベース順に並べる
    ///   3. 先頭グループの className が nodeType と同じなら、Inspector ヘッダのタイプ表示と
    ///      重複するのでクラス見出しを省く
    /// `type`/`name`/`children` は Inspector ヘッダで扱うので個別行は出さない
    def renderTopLevelGroups(content: JPanel, state: IdeState,
                              obj: Map[String, Json.JsonElement]): Unit \ IO =
        let nodeType = match Map.get("type", obj) {
            case Some(JsonString(s)) => s
            case _                   => ""
        };
        let groups = inspectorGroupsFor(nodeType);
        let isHeaderKey = key -> key == "type" or key == "name" or key == "children";
        if (List.isEmpty(groups)) {
            // type 不明: グループ無しで alphabetical fallback
            renderObjectProperties(content, state, Nil, obj, 0i32)
        } else {
            // 1. グループに属さないキー (ユーザ定義 / 拡張 property) を最初に直接出す
            //    Godot でも script 公開 property は最上段に来る。
            //    `properties` キーは「ユーザ定義 property のラッパ」という暗黙の慣行に従い、
            //    section 化せず中身を最上位に展開する (commit 経路の subKeys には "properties" を積む)
            let groupedKeys = groups
                |> List.flatMap(g -> g#keys)
                |> List.toSet;
            let extraKeys = Map.keysOf(obj)
                |> Set.toList
                |> List.filter(k -> not isHeaderKey(k) and not Set.memberOf(k, groupedKeys));
            List.forEach(k -> match Map.get(k, obj) {
                case Some(JsonObject(inner)) =>
                    if (k == "properties")
                        renderObjectProperties(content, state, "properties" :: Nil, inner, 0i32)
                    else
                        renderOneProperty(content, state, Nil, obj, k, JsonObject(inner), 0i32)
                case Some(v) => renderOneProperty(content, state, Nil, obj, k, v, 0i32)
                case None    => ()
            }, extraKeys);
            // 2. クラスグループを順番に出す。タイプ重複の心配は無い (Inspector ヘッダは名前のみ)
            //    ので全てのグループに見出しを付ける
            List.forEach(group -> {
                let presentKeys = group#keys
                    |> List.filter(k -> Map.memberOf(k, obj));
                if (List.isEmpty(presentKeys)) ()
                else {
                    content.add(createClassHeaderRow(group#className));
                    List.forEach(k -> match Map.get(k, obj) {
                        case Some(v) => renderOneProperty(content, state, Nil, obj, k, v, 0i32)
                        case None    => ()
                    }, presentKeys)
                }
            }, groups)
        }

    /// Godot Inspector 風の「クラス名見出し」行。継承境界を示す。
    /// `createSectionRow` (ネスト object 用の薄い見出し) より背景が暗く文字を中央寄せにし、
    /// 「ここから別 class の property セット」だと視認しやすくする
    def createClassHeaderRow(className: String): JPanel \ IO =
        let row = new JPanel(new BorderLayout());
        row.setBackground(new Color(60, 60, 70));
        row.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(1, 0, 1, 0, new Color(35, 35, 40)),
            BorderFactory.createEmptyBorder(5, 10, 5, 10)
        ));
        row.setMaximumSize(new Dimension(9999, 28));
        row.setAlignmentX(0.0f32);
        let lbl = new JLabel(className);
        lbl.setForeground(new Color(220, 220, 230));
        lbl.setHorizontalAlignment(SwingConstants.CENTER);
        row.add(lbl, BorderLayout.CENTER);
        row

    /// ノード type ごとの Inspector プロパティグループ。Godot の継承ツリー表記に倣い、
    /// type-specific → 親クラス → 共通祖先 の順に並べる。
    /// 各グループは {className, keys}: keys は表示順のキー名リスト。
    /// 該当 type が無い場合は Nil を返し、呼び出し側で alphabetical にフォールバックする
    def inspectorGroupsFor(nodeType: String): List[{className = String, keys = List[String]}] =
        let node2d: {className = String, keys = List[String]} =
            {className = "Node2D",
             keys = "pos" :: "rotation" :: "scale" :: "skew" :: Nil};
        let canvasItem: {className = String, keys = List[String]} =
            {className = "CanvasItem",
             keys = "visible" :: "modulate" :: "alpha" :: "opacity" ::
                     "zIndex" :: "ySortEnabled" :: Nil};
        let collisionObject: {className = String, keys = List[String]} =
            {className = "CollisionObject2D",
             keys = "collisionLayer" :: "collisionMask" :: "tag" :: Nil};
        let baseButton: {className = String, keys = List[String]} =
            {className = "BaseButton",
             keys = "size" :: "centered" :: "disabled" :: Nil};
        match nodeType {
            case "AnimatedSprite2D" =>
                ({className = "AnimatedSprite2D",
                  keys = "spriteFrames" :: "animation" :: "autoplay" ::
                          "frame" :: "frameProgress" :: "speedScale" ::
                          "playing" :: Nil}: {className = String, keys = List[String]}) ::
                ({className = "Sprite2D",
                  keys = "centered" :: "offset" :: "flipH" :: "flipV" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "Sprite2D" =>
                ({className = "Sprite2D",
                  keys = "texture" :: "centered" :: "offset" ::
                          "flipH" :: "flipV" :: "region" ::
                          "hframes" :: "vframes" :: "frame" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "Label2D" =>
                ({className = "Label2D",
                  keys = "text" :: "fontSize" :: "fontName" ::
                          "horizontalAlignment" :: "verticalAlignment" ::
                          "centered" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "RichTextLabel" =>
                ({className = "RichTextLabel",
                  keys = "text" :: "size" :: "fontSize" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "ColorRect" =>
                ({className = "ColorRect",
                  keys = "size" :: "color" :: "alpha" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "TextureRect" =>
                ({className = "TextureRect",
                  keys = "texture" :: "size" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case "Button" =>
                ({className = "Button",
                  keys = "text" :: "fontSize" :: "fontName" :: "tag" :: Nil}: {className = String, keys = List[String]}) ::
                baseButton :: node2d :: canvasItem :: Nil
            case "TextureButton" =>
                ({className = "TextureButton",
                  keys = "textureNormal" :: "texturePressed" ::
                          "textureHover" :: "textureDisabled" :: Nil}: {className = String, keys = List[String]}) ::
                baseButton :: node2d :: canvasItem :: Nil
            case "Area2D" =>
                ({className = "Area2D",
                  keys = "monitoring" :: "monitorable" :: "priority" :: "shape" :: Nil}: {className = String, keys = List[String]}) ::
                collisionObject :: node2d :: canvasItem :: Nil
            case "RigidBody2D" =>
                ({className = "RigidBody2D",
                  keys = "mass" :: "gravityScale" :: "linearVelocity" ::
                          "angularVelocity" :: "friction" :: "restitution" ::
                          "shape" :: Nil}: {className = String, keys = List[String]}) ::
                collisionObject :: node2d :: canvasItem :: Nil
            case "StaticBody2D" =>
                ({className = "StaticBody2D",
                  keys = "shape" :: "friction" :: "restitution" :: Nil}: {className = String, keys = List[String]}) ::
                collisionObject :: node2d :: canvasItem :: Nil
            case "CharacterBody2D" =>
                ({className = "CharacterBody2D",
                  keys = "shape" :: "velocity" :: Nil}: {className = String, keys = List[String]}) ::
                collisionObject :: node2d :: canvasItem :: Nil
            case "CanvasLayer" =>
                ({className = "CanvasLayer",
                  keys = "layer" :: "pos" :: "scale" :: "rotation" :: "visible" :: Nil}: {className = String, keys = List[String]}) ::
                Nil
            case "Camera2D" =>
                ({className = "Camera2D",
                  keys = "zoom" :: "offset" :: "enabled" :: "isCurrent" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: Nil
            case "Marker2D" =>
                node2d :: canvasItem :: Nil
            case "TileMapLayer" =>
                ({className = "TileMapLayer",
                  keys = "tileSet" :: "tileSize" :: Nil}: {className = String, keys = List[String]}) ::
                node2d :: canvasItem :: Nil
            case _ => Nil
        }

    /// JsonArray を 1 要素ずつ「[i]」セクションに展開する。
    /// 要素が JsonObject なら renderObjectProperties で再帰、それ以外（プリミティブ）なら 1 行 widget。
    /// path は配列インデックスを文字列化して subKeys に積む（JsonOps.setAtKeyPath が
    /// JsonArray を受けて整数パースで降りる）
    def renderArrayProperties(content: JPanel, state: IdeState, prefix: List[String],
                               items: List[Json.JsonElement], indent: Int32): Unit \ IO =
        discard List.mapWithIndex((idx, item) -> {
            let subPrefix = prefix ::: Int32.toString(idx) :: Nil;
            let commit = newVal -> commitEdit(state, subPrefix, newVal);
            match item {
                case JsonObject(nested) =>
                    content.add(createSectionRow("[${idx}]", indent));
                    renderObjectProperties(content, state, subPrefix, nested, indent + 1i32)
                case _ =>
                    let row = createPropertyRow(state, "[${idx}]", item, Map.empty(), commit, indent);
                    content.add(row);
                    ()
            }
        }, items);
        ()

    /// JsonObject が「色」を表すか判定する。r/g/b 3 キーが揃っていれば色とみなす（a は任意）。
    /// scene.json の慣行は {"r": 1.0, "g": 0.5, "b": 0.0} の 0.0..1.0 浮動小数
    def isColorObject(m: Map[String, Json.JsonElement]): Bool =
        Map.memberOf("r", m) and Map.memberOf("g", m) and Map.memberOf("b", m)

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
        label.setPreferredSize(new Dimension(80, 22));
        row.add(label, BorderLayout.WEST);

        let widgetWrap = new JPanel(new FlowLayout(FlowLayout.LEFT, 0, 0));
        widgetWrap.setBackground(new Color(40, 40, 40));
        widgetWrap.add(createShapeKindCombo(currentKind, commit));
        row.add(widgetWrap, BorderLayout.CENTER);
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
        cb.setPreferredSize(new Dimension(150, 22));
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
    /// `siblingMap` は同じ親オブジェクトの全プロパティ。`animation` のように兄弟ノード
    /// （`spriteFrames`）を参照して選択肢を決める widget で使う。
    /// `indent` はネストの深さ。左余白に反映する。
    def createPropertyRow(state: IdeState, key: String, value: Json.JsonElement,
                          siblingMap: Map[String, Json.JsonElement],
                          commit: Json.JsonElement -> Unit \ IO,
                          indent: Int32): JPanel \ IO =
        createPropertyRowWidget(key,
            createPropertyWidget(state, key, value, siblingMap, commit), indent)

    /// キー名ラベル + 任意 widget の 1 行ラッパ。createPropertyRow と
    /// 「ラベル + 既製 widget」の両方から使う共通ガワ。
    /// widget は FlowLayout(LEFT) でくるんで「自身の preferredSize で左寄せ」する。
    /// BorderLayout.CENTER に直接置くと widget が行の残幅まで引き伸ばされ、Inspector 内で
    /// 大きく見えてしまうため
    def createPropertyRowWidget(key: String, widget: JPanel, indent: Int32): JPanel \ IO =
        let row = new JPanel(new BorderLayout(6, 0));
        row.setBackground(new Color(40, 40, 40));
        row.setBorder(BorderFactory.createEmptyBorder(3, 10 + indent * 16i32, 3, 10));
        row.setMaximumSize(new Dimension(9999, 28));
        row.setAlignmentX(0.0f32);

        let label = new JLabel(key);
        label.setForeground(new Color(180, 180, 180));
        label.setPreferredSize(new Dimension(80, 22));
        row.add(label, BorderLayout.WEST);

        let widgetWrap = new JPanel(new FlowLayout(FlowLayout.LEFT, 0, 0));
        widgetWrap.setBackground(new Color(40, 40, 40));
        widgetWrap.add(widget);
        row.add(widgetWrap, BorderLayout.CENTER);
        row

    /// プロパティ値の型 + キー名に基づいて適切な widget を返す。
    /// 優先順:
    ///   1. (key, value) で specialty 一致（bounded slider / enum dropdown / texture / animation など）
    ///   2. value の型ごと（Bool→Check, Number→Spinner, String→TextField,
    ///      Vec2→XY 2 フィールド, Color→Picker, それ以外→読取ラベル）
    /// `siblingMap` は animation/autoplay の選択肢を spriteFrames から拾うのに使う
    def createPropertyWidget(state: IdeState, key: String, value: Json.JsonElement,
                             siblingMap: Map[String, Json.JsonElement],
                             commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        // 1. 数値プロパティの specialty マッピング
        match (boundedSliderRange(key), value) {
            case (Some(range), JsonNumber(bd)) =>
                panel.add(createBoundedSlider(bd, range, commit), BorderLayout.CENTER)
            case _ => match (integerSpinnerSpec(key), value) {
                case (Some(spec), JsonNumber(bd)) =>
                    panel.add(createIntegerSpinner(bd, spec, commit), BorderLayout.CENTER)
                case _ => match (doubleSpinnerSpec(key), value) {
                    case (Some(spec), JsonNumber(bd)) =>
                        panel.add(createDoubleSpinner(bd, spec, commit), BorderLayout.CENTER)
                    case _ => match (enumOptionsFor(key, siblingMap), value) {
                        case (Some(opts), JsonString(s)) =>
                            panel.add(createEnumDropdown(s, opts, commit), BorderLayout.CENTER)
                        case _ =>
                            // 2. 値型による標準ディスパッチ
                            panel.add(defaultWidgetFor(state, key, value, commit), BorderLayout.CENTER)
                    }
                }
            }
        };
        panel

    /// specialty マッピングに該当しない値を、単純な型ベースで widget 化する
    def defaultWidgetFor(state: IdeState, key: String, value: Json.JsonElement,
                          commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        match value {
            case JsonBool(b)    => panel.add(createBoolCheck(b, commit), BorderLayout.CENTER)
            case JsonString(s)  =>
                if (isTextureKey(key)) {
                    let names = Array.get(0, state#textureNamesRef);
                    match names {
                        case Nil => panel.add(createStringInput(s, commit), BorderLayout.CENTER)
                        case _   => panel.add(createTextureSelector(s, names, commit), BorderLayout.CENTER)
                    }
                } else if (key == "text") {
                    // text フィールドは Label2D / RichTextLabel が改行を解釈するので多行で編集
                    panel.add(createMultilineStringInput(s, commit), BorderLayout.CENTER)
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
                if (isColorObject(m))
                    panel.add(createColorPicker(m, commit), BorderLayout.CENTER)
                else
                    panel.add(createReadOnlyLabel("[Object: ${Map.size(m)} keys]"), BorderLayout.CENTER)
            case _ =>
                panel.add(createReadOnlyLabel("(null)"), BorderLayout.CENTER)
        };
        panel

    /// テクスチャ名フィールドかどうか。TextureButton の state-specific キー
    /// (textureNormal / texturePressed / textureHover / textureDisabled) も
    /// プロジェクトのテクスチャ dropdown に流す
    def isTextureKey(key: String): Bool =
        key == "texture"
        or key == "textureNormal"
        or key == "texturePressed"
        or key == "textureHover"
        or key == "textureDisabled"

    /// bounded float（スライダーで操作するのが自然な値）の min/max/単位ラベル。
    /// alpha/opacity は 0..1 の透明度。speedScale は 0..3 で 1.0 が標準速度。
    /// frameProgress は AnimatedSprite2D の現フレーム進捗 0..1。
    /// rotation は GameEngine 内部表現がラジアンなので -π..π
    def boundedSliderRange(key: String):
            Option[{min = Float64, max = Float64, label = String}] =
        match key {
            case "alpha"         => Some({min = 0.0,  max = 1.0,  label = "%.2f"})
            case "opacity"       => Some({min = 0.0,  max = 1.0,  label = "%.2f"})
            case "speedScale"    => Some({min = 0.0,  max = 3.0,  label = "%.2fx"})
            case "frameProgress" => Some({min = 0.0,  max = 1.0,  label = "%.2f"})
            case "rotation"      => Some({min = -3.1415927, max = 3.1415927, label = "%.2frad"})
            case _               => None
        }

    /// 整数スピナーで扱うキーの (min, max, step) 仕様。範囲は素朴に幅広く取り、
    /// 「上下キーで 1 ずつ動く」だけが本質
    def integerSpinnerSpec(key: String):
            Option[{min = Int32, max = Int32, step = Int32}] =
        match key {
            case "zIndex" => Some({min = -1024i32, max = 1024i32, step = 1i32})
            case "layer"  => Some({min = 0i32,    max = 1024i32, step = 1i32})
            case "frame"  => Some({min = 0i32,    max = 9999i32, step = 1i32})
            case "fontSize" => Some({min = 1i32,  max = 256i32,  step = 1i32})
            case _ => None
        }

    /// 浮動小数スピナーで扱うキーの (min, max, step)。物理量・時間量など、
    /// スライダーほどレンジが固定でないがスピナーで微調整したい値
    def doubleSpinnerSpec(key: String):
            Option[{min = Float64, max = Float64, step = Float64}] =
        match key {
            case "speed"        => Some({min = 0.0, max = 1000.0, step = 0.5})
            case "duration"     => Some({min = 0.0, max = 1000.0, step = 0.1})
            case "gravityScale" => Some({min = 0.0, max = 100.0, step = 0.1})
            case "radius"       => Some({min = 0.0, max = 9999.0, step = 1.0})
            case "width"        => Some({min = 0.0, max = 9999.0, step = 1.0})
            case "height"       => Some({min = 0.0, max = 9999.0, step = 1.0})
            // HBox/VBox の子間隔
            case "separation"   => Some({min = 0.0, max = 999.0, step = 1.0})
            // MarginContainer の余白 (Label2D / RichTextLabel の margin にも流用)
            case "margin"       => Some({min = 0.0, max = 999.0, step = 1.0})
            case _ => None
        }

    /// String enum で扱うキーの選択肢。spriteFrames から動的に拾うものは
    /// siblingMap を参照する
    def enumOptionsFor(key: String, siblingMap: Map[String, Json.JsonElement]):
            Option[List[String]] =
        if (key == "animation" or key == "autoplay")
            match Map.get("spriteFrames", siblingMap) {
                case Some(JsonObject(framesMap)) =>
                    let names = Map.keysOf(framesMap) |> Set.toList;
                    if (List.isEmpty(names)) None else Some(names)
                case _ => None
            }
        else if (key == "horizontalAlignment")
            // engine の parseHorizontalAlignment (SceneLoader.flix:947) が受理する文字列に合わせる
            Some("left" :: "center" :: "right" :: "fill" :: Nil)
        else if (key == "verticalAlignment")
            // engine の parseVerticalAlignment (SceneLoader.flix:959) に合わせる
            Some("top" :: "center" :: "bottom" :: "fill" :: Nil)
        // Layout primitive (Panel / HBox / VBox / Margin / Center) は "type" を持たない
        // JsonObject。shape.kind は createShapeKindRow が先取りするのでここには来ない
        else if (key == "kind" and not Map.memberOf("type", siblingMap))
            // engine の Layout.buildByKind (Layout.flix:99-141) が受理する文字列
            Some("Panel" :: "HBoxContainer" :: "VBoxContainer" ::
                  "MarginContainer" :: "CenterContainer" :: Nil)
        // HBox/VBox の主軸方向 alignment。engine の MainAxisAlign に合わせる
        else if (key == "alignment" and not Map.memberOf("type", siblingMap))
            Some("Begin" :: "Center" :: "End" :: Nil)
        // HBox/VBox の交差軸方向 alignment。CrossAxisAlign は Stretch も持つ
        else if (key == "crossAxis" and not Map.memberOf("type", siblingMap))
            Some("Begin" :: "Center" :: "End" :: "Stretch" :: Nil)
        else None

    /// 連続値スライダー: 0..1000 の Int32 段階を min..max にマップする。
    /// drag 中は値ラベルだけ更新し、release (not isAdjusting) で commit する。
    /// 段階数を 1000 にして alpha (0..1) でも 0.001 刻みになる
    def createBoundedSlider(bd: BigDecimal,
                             range: {min = Float64, max = Float64, label = String},
                             commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let cur = bd.doubleValue();
        let span = range#max - range#min;
        let toTick = v -> Float64.tryToInt32(((v - range#min) / span) * 1000.0)
                          |> Option.getWithDefault(0i32);
        let clamp = t -> if (t < 0i32) 0i32 else if (t > 1000i32) 1000i32 else t;
        let tickToValue = t -> range#min + (Int32.toFloat64(t) / 1000.0) * span;

        let slider = new JSlider(0, 1000, clamp(toTick(cur)));
        slider.setBackground(new Color(40, 40, 40));
        slider.setForeground(Color.LIGHT_GRAY);
        slider.setPreferredSize(new Dimension(120, 22));

        let valLabel = new JLabel(formatBd(bd));
        valLabel.setForeground(new Color(180, 180, 180));
        valLabel.setPreferredSize(new Dimension(50, 22));

        slider.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = tickToValue(slider.getValue());
                let newBd = unsafe IO { BigDecimal.valueOf(v).stripTrailingZeros() };
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

    /// 整数スピナー: ↑↓ ボタン（および ↑↓ キー）で 1 ずつ動く。値変更で即 commit。
    def createIntegerSpinner(bd: BigDecimal,
                              spec: {min = Int32, max = Int32, step = Int32},
                              commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let cur = Float64.tryToInt32(bd.doubleValue()) |> Option.getWithDefault(0i32);
        let clamped = if (cur < spec#min) spec#min
                       else if (cur > spec#max) spec#max else cur;
        let model = new SpinnerNumberModel(clamped, spec#min, spec#max, spec#step);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(80, 22));
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().intValue();
                let newBd = unsafe IO { BigDecimal.valueOf(Int32.toFloat64(v)).stripTrailingZeros() };
                commit(JsonNumber(newBd))
            }
        });
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        panel.add(spinner, BorderLayout.CENTER);
        panel

    /// 浮動小数スピナー: ↑↓ で step ずつ動く。
    /// SpinnerNumberModel の Number は Double に丸める
    def createDoubleSpinner(bd: BigDecimal,
                             spec: {min = Float64, max = Float64, step = Float64},
                             commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let cur = bd.doubleValue();
        let clamped = if (cur < spec#min) spec#min
                       else if (cur > spec#max) spec#max else cur;
        let model = new SpinnerNumberModel(clamped, spec#min, spec#max, spec#step);
        let spinner = new JSpinner(model);
        spinner.setPreferredSize(new Dimension(90, 22));
        spinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = {
                let v = model.getNumber().doubleValue();
                let newBd = unsafe IO { BigDecimal.valueOf(v).stripTrailingZeros() };
                commit(JsonNumber(newBd))
            }
        });
        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        panel.add(spinner, BorderLayout.CENTER);
        panel

    /// 汎用 enum dropdown: 既存値が options に無ければ "<unknown>: ..." を先頭に置いて
    /// 状態を見せ、それが選ばれた場合は commit しない（誤入力された scene.json を壊さないため）。
    /// texture / shape kind の selector と同じ作法
    def createEnumDropdown(initial: String, options: List[String],
                            commit: Json.JsonElement -> Unit \ IO): JComboBox[String] \ IO =
        let unknown = not List.memberOf(initial, options);
        let missingLabel = "<unknown>: ${initial}";
        let items = if (unknown) missingLabel :: options else options;
        let cb: JComboBox[String] = new JComboBox();
        List.forEach(n -> { cb.addItem(n); () }, items);
        cb.setSelectedItem(if (unknown) missingLabel else initial);
        cb.setPreferredSize(new Dimension(150, 22));
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
                        if (name == initial) ()
                        else commit(JsonString(name))
                    case None => ()
                }
            }
        });
        cb

    /// カラーピッカー: 現在色のスウォッチを表示し、クリックで JColorChooser を開く。
    /// scene.json の color object は {"r": 0..1, "g": 0..1, "b": 0..1} 浮動小数なので、
    /// 0..255 の AWT 値とは内部で変換する。a は任意キーで、無ければ commit でも省く。
    def createColorPicker(m: Map[String, Json.JsonElement],
                           commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let getF = key -> match Map.get(key, m) {
            case Some(JsonNumber(bd)) => bd.doubleValue()
            case _ => 0.0
        };
        let r0 = getF("r"); let g0 = getF("g"); let b0 = getF("b");
        let hasAlpha = Map.memberOf("a", m);
        let toByte = f -> {
            let scaled = Float64.tryToInt32(f * 255.0) |> Option.getWithDefault(0i32);
            if (scaled < 0i32) 0i32 else if (scaled > 255i32) 255i32 else scaled
        };
        let initial = new Color(toByte(r0), toByte(g0), toByte(b0));

        let swatch = new JButton("");
        swatch.setBackground(initial);
        swatch.setOpaque(true);
        swatch.setBorder(BorderFactory.createLineBorder(new Color(70, 70, 70), 1));
        swatch.setPreferredSize(new Dimension(80, 22));
        swatch.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                let picked = JColorChooser.showDialog(swatch, "Pick color", swatch.getBackground());
                if (Object.isNull(picked)) ()
                else {
                    swatch.setBackground(picked);
                    let r = Int32.toFloat64(picked.getRed())   / 255.0;
                    let g = Int32.toFloat64(picked.getGreen()) / 255.0;
                    let b = Int32.toFloat64(picked.getBlue())  / 255.0;
                    let mkBd = v -> unsafe IO { BigDecimal.valueOf(v).stripTrailingZeros() };
                    let base: Map[String, Json.JsonElement] = Map#{
                        "r" => JsonNumber(mkBd(r)),
                        "g" => JsonNumber(mkBd(g)),
                        "b" => JsonNumber(mkBd(b))
                    };
                    let newMap = if (hasAlpha) {
                        let a = Int32.toFloat64(picked.getAlpha()) / 255.0;
                        Map.insert("a", JsonNumber(mkBd(a)), base)
                    } else base;
                    commit(JsonObject(newMap))
                }
            }
        });

        let panel = new JPanel(new BorderLayout());
        panel.setBackground(new Color(40, 40, 40));
        panel.add(swatch, BorderLayout.CENTER);
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
        tf.setColumns(10);
        styleTextInput(tf);
        tf.addActionListener(new ActionListener {
            def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO =
                commit(JsonString(tf.getText()))
        });
        tf

    /// 多行 String プロパティ (Label2D / RichTextLabel の `text` 等): JTextArea で
    /// 改行を編集可能にし、Focus 離脱で commit (JsonString)。
    /// Enter は通常の改行として扱う。長い行は単語境界で折り返す。
    /// JScrollPane で囲んでいるので Inspector スクロール内でも壊れない
    def createMultilineStringInput(initial: String,
                                    commit: Json.JsonElement -> Unit \ IO): JScrollPane \ IO =
        let ta = new JTextArea(initial, 3i32, 20i32);
        ta.setLineWrap(true);
        ta.setWrapStyleWord(true);
        ta.setBackground(new Color(50, 50, 50));
        ta.setForeground(Color.LIGHT_GRAY);
        ta.setCaretColor(Color.WHITE);
        ta.setBorder(BorderFactory.createEmptyBorder(2, 4, 2, 4));
        ta.addFocusListener(new FocusAdapter {
            def focusLost(_this: FocusAdapter, _e: FocusEvent): Unit \ IO =
                commit(JsonString(ta.getText()))
        });
        let scroll = new JScrollPane(ta);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(70, 70, 70), 1));
        scroll

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
        cb.setPreferredSize(new Dimension(150, 22));
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
        tf.setColumns(8);
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
    /// 各軸は JSpinner なので ↑↓ 矢印ボタン or ↑↓ キーで 1 ずつ動き、即 commit する。
    /// 直接編集も可（focus を抜けると model が更新され ChangeListener が発火）。
    /// SpinnerNumberModel への参照を直接保持しておくことで、commit で getModel() →
    /// SpinnerNumberModel への downcast を回避する
    def createVec2Field(bdX: BigDecimal, bdY: BigDecimal,
                        commit: Json.JsonElement -> Unit \ IO): JPanel \ IO =
        let xModel = new SpinnerNumberModel(bdX.doubleValue(), -99999.0, 99999.0, 1.0);
        let yModel = new SpinnerNumberModel(bdY.doubleValue(), -99999.0, 99999.0, 1.0);
        let xSpinner = new JSpinner(xModel);
        let ySpinner = new JSpinner(yModel);
        xSpinner.setPreferredSize(new Dimension(60, 22));
        ySpinner.setPreferredSize(new Dimension(60, 22));

        let commitVec2 = () -> {
            let xV = xModel.getNumber().doubleValue();
            let yV = yModel.getNumber().doubleValue();
            let newX = unsafe IO { BigDecimal.valueOf(xV).stripTrailingZeros() };
            let newY = unsafe IO { BigDecimal.valueOf(yV).stripTrailingZeros() };
            commit(JsonArray(Vector#{JsonNumber(newX), JsonNumber(newY)}))
        };
        xSpinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = commitVec2()
        });
        ySpinner.addChangeListener(new ChangeListener {
            def stateChanged(_this: ChangeListener, _e: ChangeEvent): Unit \ IO = commitVec2()
        });

        let panel = new JPanel(new GridLayout(1, 2, 6, 0));
        panel.setBackground(new Color(40, 40, 40));
        panel.add(wrapSpinnerAxis("X", new Color(220, 110, 110), xSpinner));
        panel.add(wrapSpinnerAxis("Y", new Color(120, 200, 120), ySpinner));
        panel

    /// 1 軸ぶんの「色付きラベル + JSpinner」ラッパ
    def wrapSpinnerAxis(axisName: String, axisColor: Color, spinner: JSpinner): JPanel \ IO =
        let panel = new JPanel(new BorderLayout(4, 0));
        panel.setBackground(new Color(40, 40, 40));
        let lbl = new JLabel(axisName);
        lbl.setForeground(axisColor);
        lbl.setPreferredSize(new Dimension(14, 22));
        panel.add(lbl, BorderLayout.WEST);
        panel.add(spinner, BorderLayout.CENTER);
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
