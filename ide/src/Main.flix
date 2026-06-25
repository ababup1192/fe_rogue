// ide/src/Main.flix — Step C.3: IDE シェル + Open Project + scene 切替
//
// 起動時はプロジェクト未ロード状態 (グレー canvas + 空の Scenes リスト)。
// File → Open Project... でディレクトリを選ぶと project.json を読み、
// **/*.scene.json を列挙して左パネルの Scenes リストに表示する。
// リスト項目をクリックすると現セッション内で scene が切替えられる。
//
// 動作確認:
//   cd ide && ./bin/flix run
// 期待:
//   - 起動: ダークグレー canvas、Scenes リスト空、Inspector プレースホルダ
//   - File → Open Project... → examples/flappy_bird を選ぶと Scenes リストに
//     BirdScene/MenuScene/... が並ぶ。クリックで該当 scene が表示される。

def main(): Unit \ {IO, Chan, NonDet} =
    run {
        let state = IdeState.newState();
        run {
            sessionLoop(state, None)
        } with handler IdeGui.Gui {
            // JavaFX 実装に dispatch。state を closure capture して該当 widget を更新する
            def populateProjectTree(k) = {
                JavaFXIdeUI.schedulePopulateTree(state);
                k(())
            }
            def setTitle(title, k) = {
                JavaFXIdeUI.scheduleSetTitle(state, title);
                k(())
            }
            def setLoadingProgress(label, frac, k) = {
                JavaFXIdeUI.scheduleSetLoadingProgress(state, label, frac);
                k(())
            }
            def hideLoading(k) = {
                JavaFXIdeUI.scheduleHideLoading(state);
                k(())
            }
        }
    } with Fs.Glob.runWithIO
      with Fs.FileRead.runWithIO
      with Fs.FileWrite.runWithIO
      with Fs.ModificationTime.runWithFileTime
      with Fs.FileTime.runWithIO

/// 1 セッションを走らせる。Open Project でディレクトリが選ばれていれば
/// 再帰的に新 project で立て直す。
def sessionLoop(state: IdeState.IdeState, projectPath: Option[String]):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Fs.ModificationTime, Chan, NonDet, IdeGui.Gui} =
    let config = match projectPath {
        case Some(path) =>
            println("[Main] Loading project: ${path}");
            match ProjectLoader.loadProject(path) {
                case Ok(proj) =>
                    // 表示用相対パスでアルファベット順ソート。先頭シーンを起動時に自動オープンする
                    let sceneFiles = ProjectLoader.findSceneFiles(path)
                        |> List.map(rel -> (joinPath(path, rel), rel))
                        |> List.sortBy(p -> snd(p));
                    IdeState.setSceneFiles(state, sceneFiles);
                    // 起動時に先頭シーンを自動でロードする。pendingSceneRef にセットしておけば
                    // ideLoop の最初のフレームで loadPendingSceneOrKeep がロードする。
                    match List.head(sceneFiles) {
                        case Some((abs, _rel)) => Array.put(Some(abs), 0, state#pendingSceneRef)
                        case None              => ()
                    };
                    let textureNames = proj#config#textureManifest |> List.map(e -> e#name);
                    IdeState.setTextureNames(state, textureNames);
                    // texture 名 → 絶対パス。Resource preview の Image 読込で使う。
                    let texturePathMap = proj#config#textureManifest
                        |> List.map(e -> (e#name, e#path))
                        |> List.toMap;
                    IdeState.setTexturePathMap(state, texturePathMap);
                    // sound manifest の論理名一覧。AudioStreamPlayer.stream の dropdown 候補。
                    let soundNames = proj#config#soundManifest |> List.map(e -> e#name);
                    IdeState.setSoundNames(state, soundNames);
                    // resources/ 配下の Resource ファイルを列挙して ResourceState に登録。
                    let resources = ResourceDiscovery.discover(path);
                    println("[Main] Discovered ${List.length(resources)} resource(s) in ${path}/resources");
                    ResourceState.setDiscovered(state#resource, resources);
                    // assets/maps/*.map.json を列挙して MapEditorState に登録 (S8)。
                    let mapFiles = MapEditorPanel.findMapFiles(path);
                    println("[Main] Discovered ${List.length(mapFiles)} map(s) in ${path}/assets/maps");
                    MapEditorState.setLevelFiles(state#mapEditor, mapFiles);
                    // tileset PNG を Image としてキャッシュ (S13 で Canvas に切り抜き描画)
                    MapEditorPanel.loadTilesetImages(state);
                    IdeState.setCurrentProjectRoot(state, Some(path));
                    decorateTitle(proj#config, path)
                case Err(msg) =>
                    // project.json が無い / パース失敗。クラッシュさせず empty state へ。
                    println("[Main] Open Project failed: ${msg}");
                    IdeState.setSceneFiles(state, Nil);
                    IdeState.setTextureNames(state, Nil);
                    IdeState.setTexturePathMap(state, Map.empty());
                    IdeState.setSoundNames(state, Nil);
                    ResourceState.setDiscovered(state#resource, Nil);
                    MapEditorState.setLevelFiles(state#mapEditor, Nil);
                    IdeState.setCurrentProjectRoot(state, None);
                    emptyConfig()
            }
        case None =>
            println("[Main] Starting IDE with no project");
            IdeState.setSceneFiles(state, Nil);
            IdeState.setTextureNames(state, Nil);
            IdeState.setTexturePathMap(state, Map.empty());
            IdeState.setSoundNames(state, Nil);
            ResourceState.setDiscovered(state#resource, Nil);
            MapEditorState.setLevelFiles(state#mapEditor, Nil);
            IdeState.setCurrentProjectRoot(state, None);
            emptyConfig()
    };
    let customize = (stage, imageView) -> JavaFXIdeUI.customize(state, stage, imageView);
    // Label2D を含むシーンを開けるよう、project の fontManifest の先頭フォント名を
    // SceneLoader.loadSceneWithFont に渡せるよう保持する。フォント未定義のプロジェクトでは
    // loadScene にフォールバックする (Label2D が含まれれば bug! になるが project 側の責務)。
    let fontName = List.head(config#fontManifest) |> Option.map(f -> f#name);
    // editor の SceneJsonIndex を作るためのプロジェクトルート。プロジェクト未ロードのときは
    // cwd を指す "." を渡し、scene.json が見つからない索引で editor は無害に空回りする
    let projectRoot = projectPath |> Option.getWithDefault(".");
    run {
        ideLoop(state, fontName, projectRoot)
    } with JavaFXLayer.withJavaFX(config, state#runtime#pendingConfig, customize);
    // Phase 1: JavaFX runtime は Runtime.halt(0) で落としているため
    // ここに到達することは事実上無い (再 open は Phase 2 以降で対応)
    match IdeState.takePendingProject(state) {
        case Some(newPath) =>
            println("[Main] Reloading with new project: ${newPath}");
            sessionLoop(state, Some(newPath))
        case None =>
            println("[Main] User closed window. Exiting.")
    }

/// shouldClose まで毎フレーム描画する。`pendingSceneRef` がセットされていれば
/// その scene をロードして以降の描画対象を差し替える。
/// `fontName` が Some(name) なら Label2D を含むシーンも loadSceneWithFont で開ける。
/// `projectRoot` は editor が現プロジェクトの src/scenes を読むための基準ディレクトリ。
def ideLoop(state: IdeState.IdeState, fontName: Option[String], projectRoot: String):
        Unit \ {IO, GameEngine.Game, GameEngine.Audio, Fs.FileRead, Fs.FileWrite, Fs.Glob,
                Fs.ModificationTime, Chan, NonDet, IdeGui.Gui} =
    region rc {
        run {
            // IDE は常に editor ON で動かす。F1 トグル不要で preview クリック・
            // ドラッグが即座に効く。tree クリックで selected を直接書き換える
            // フローも初回からそのまま動く
            let initial = Editor.EditorState.get();
            Editor.EditorState.put({on = true | initial});
            renderLoop(state, fontName, Scene.empty())
        } with Editor.withStateAt(rc, projectRoot)
    }

def renderLoop(state: IdeState.IdeState, fontName: Option[String], currentScene: Scene[Unit]):
        Unit \ {IO, GameEngine.Game, GameEngine.Audio, Fs.FileRead, Fs.FileWrite, Fs.Glob, Fs.ModificationTime,
                Chan, NonDet, Editor.EditorState, EditHistory.Rewind, IdeGui.Gui} =
    if (GameEngine.Game.shouldClose()) ()
    else {
        // Phase 2: File → Open Project... で積まれた project を消費して in-place 再ロード。
        // Phase 3 で GL リソース再 init を AWT EDT に委譲済み
        let (newFontName, baseScene) = match IdeState.takePendingProject(state) {
            case None       => (fontName, currentScene)
            case Some(path) => reloadProject(state, fontName, path)
        };
        // File → New Scene... で積まれた新規シーン生成要求を消費する。
        // .scene.json 生成 → sceneFiles 再列挙 → rootJsonIndex 更新 → pendingSceneRef 予約。
        // 以降の sceneChanged 経路が TreeView 反映と auto-load/選択を担う
        consumePendingNewScene(state);
        // Scenes ツリーのコンテキストメニューで積まれた Delete / Rename を適用する
        consumePendingSceneOp(state);
        // Add Child Node で積まれた子ノード追加を適用する
        consumePendingAddChild(state);
        // Project Settings で積まれた design 解像度変更を適用する (project.json 更新 → 再ロード)
        consumePendingProjectSettings(state);
        // Deferred auto-load: AWT EDT が config swap を完了 (runtime#pendingConfig == None)
        // したフレームで初めて先頭シーンを pendingSceneRef に積む。font/texture が揃った
        // 後にロードされるので getFontAtlas が安全に解決できる
        if (Array.get(0, state#wantsAutoLoadFirstSceneRef)
            and Option.isEmpty(Array.get(0, state#runtime#pendingConfig))) {
            match List.head(Array.get(0, state#sceneFilesRef)) {
                case Some((abs, rel)) => {
                    println("[Main] Auto-loading first scene: ${rel}");
                    IdeGui.Gui.setLoadingProgress("シーンを読み込み中...", 0.95f64);
                    Array.put(Some(abs), 0, state#pendingSceneRef)
                }
                // シーンが 1 つも無いプロジェクト (新規/空。breakout 等) は auto-load
                // する先頭シーンが無いので、ここで overlay を畳まないと「初期化中」のまま
                // 止まって見える。File → New Scene でシーンを作れる状態にして待機する
                case None => {
                    println("[Main] Project has no scenes; ready for New Scene");
                    if (Array.get(0, state#loadingActiveRef)) {
                        Array.put(false, 0, state#loadingActiveRef);
                        IdeGui.Gui.hideLoading()
                    } else ()
                }
            };
            Array.put(false, 0, state#wantsAutoLoadFirstSceneRef)
        } else ();
        let sceneChanged = match Array.get(0, state#pendingSceneRef) {
            case Some(_) => true
            case None    => false
        };
        let nextScene = loadPendingSceneOrKeep(state, newFontName, baseScene);
        // ロード中フラグが立っており、今フレームで scene が切り替わったなら、
        // 先頭 scene が描画される直前まで来た → overlay を消す
        if (sceneChanged and Array.get(0, state#loadingActiveRef)) {
            Array.put(false, 0, state#loadingActiveRef);
            IdeGui.Gui.hideLoading()
        } else ();
        // Scene が切り替わったら SceneTree を rebuild して FX 側 TreeView に反映
        if (sceneChanged) {
            let tree = NodeInspector.buildSceneTree(nextScene);
            Array.put(tree, 0, state#runtime#sceneTree);
            IdeGui.Gui.populateProjectTree();
            // シーンメモ TextArea を新しい scene.json の description で更新
            ScenePanel.refreshSceneDescription(state)
        } else ();
        // FX 側から積まれた node 選択要求を消費して Editor#selected に反映
        consumePendingNodeSelection(state);
        // Editor の真の選択状態を status bar に出すため、毎フレーム書き出す。
        // 複数選択時は件数表示（rebuild 鍵が集合変化で変わるよう Inspector 側にも効く）。
        let editorSels = Editor.EditorState.get()#selections;
        let editorSelText = match editorSels {
            case Nil          => "-"
            case sel :: Nil   => "${sel#nodePath}"
            case _            => "${List.length(editorSels)} nodes"
        };
        Array.put(editorSelText, 0, state#runtime#editorSelDisplay);
        // editor がマウス入力を取り込み、選択 / ドラッグ / リサイズ / Undo まで処理して
        // 必要に応じて scene を更新する
        let toolMode = Array.get(0, state#toolModeRef);
        let zoomCmd = Array.get(0, state#zoomCommandRef);
        Array.put(0i32, 0, state#zoomCommandRef);
        // グリッドスナップ: ON なら間隔、OFF なら 0.0（=従来の 1px 丸め）を Editor へ渡す
        let snapStep = if (Array.get(0, state#snapEnabledRef)) Array.get(0, state#snapStepRef) else 0.0;
        // handleInput 前後で選択集合の差分を見る。consume(tree由来) は既に反映済みなので、
        // ここで変われば「キャンバス由来」。その時だけ tree へ反映するフラグを立てる
        // （tree クリックと毎フレーム sync の競合を断つ）。
        let selSigBefore = selectionsSig(Editor.EditorState.get()#selections);
        let edited = Editor.handleInput(
            {toolMode = toolMode, zoomCommand = zoomCmd, snapStep = snapStep}, nextScene);
        let selSigAfter = selectionsSig(Editor.EditorState.get()#selections);
        if (selSigAfter != selSigBefore) Array.put(true, 0, state#runtime#treeNeedsSync) else ();
        // Delete / Backspace キーで選択ノードを削除（テキスト入力中は TextField が消費するため発火しない）
        handleDeleteKey(state);
        // エディタ自由カメラ (pan/zoom) を投影へ渡す。これで描画は design-px のまま見た目だけ拡大縮小・移動。
        let editorView = Editor.currentEditorView();
        GameEngine.Game.setEditorView(editorView#panX, editorView#panY, editorView#zoom);
        // 現在ズーム倍率を HUD 表示用に公開する (FX 側 AnimationTimer が読む)
        Array.put(editorView#zoom, 0, state#zoomDisplayRef);
        // Inspector の pending edits (schema 駆動 widget が積んだ commit) を消費し、
        // SceneSerializer 経由で JSON 書き戻し。HotReload watcher が次フレームで scene を再 load
        consumeInspectorEdits(state);
        // Inspector の Play/Stop ボタンが積んだ音声コマンドを GameEngine.Audio で消化する
        consumePendingAudioCommand(state);
        // editor がドラッグ確定で JSON を書き戻すと HotReload watcher が発火する
        refreshTreeOnReload(state);
        // Inspector schema + currentValues snapshot を生成し、ScenePanel AnimationTimer に渡す
        snapshotInspectorState(state, edited);
        let preview = composePreview(edited);
        GameEngine.renderWith(Editor.currentViewTransform(), editor = true, preview);
        renderLoop(state, newFontName, edited)
    }

    /// 選択 node から schema (継承階層 sections) / snapshot / world position を計算して
    /// state#inspector に書く。ScenePanel が rebuildInspector でこの schema を読み、
    /// AnimationTimer が currentValues を読んで widget を更新する
    def snapshotInspectorState(state: IdeState.IdeState, scene: Scene[Unit]):
            Unit \ {IO, Editor.EditorState} =
        let selections = Editor.EditorState.get()#selections;
        Array.put(selections, 0, state#inspector#currentSelections);
        match selections {
            case Nil => clearInspectorSnapshot(state)
            case primary :: _ => {
                let wp = Scene.globalPositionAt(primary#nodePath, scene);
                Array.put(Some((wp#x, wp#y)), 0, state#inspector#worldPos);
                Array.put(Some(primary), 0, state#inspector#currentSelection);
                match Scene.getEngineNode(primary#nodePath, scene) {
                    case None => {
                        Array.put((Nil: List[NodeInspector.FieldSection]), 0,
                                  state#inspector#schema);
                        Array.put((Map.empty(): Map[String, Util.Json.Json]), 0,
                                  state#inspector#currentValues)
                    }
                    case Some(primaryNode) => {
                        // 全選択ノードの engine node（存在するものだけ）
                        let nodes = List.filterMap(s -> Scene.getEngineNode(s#nodePath, scene),
                                                   selections);
                        let baseSections = NodeInspector.sectionsFor(primaryNode);
                        let sceneJson = Array.get(0, state#runtime#currentSceneJson);
                        let layoutSections =
                            NodeInspector.extraLayoutSectionsFor(sceneJson, primary#nodePath);
                        let propsSections =
                            NodeInspector.propertiesSectionFor(sceneJson, primary#nodePath);
                        let rawSections = List.append(propsSections,
                                                    List.append(baseSections, layoutSections));
                        // 複数選択時は「全ノードで snapshot が Some を返す共通フィールド」だけに絞る
                        let sections = if (List.length(nodes) > 1)
                                           filterCommonSections(rawSections, nodes)
                                       else rawSections;
                        Array.put(sections, 0, state#inspector#schema);
                        // 各フィールドの値: 全ノードで一致ならその値、不一致なら mixed＝map から省略
                        let foldFields = (acc, section) -> {
                            let fields = List.append(section#common, section#advanced);
                            List.foldLeft((acc2, fd) ->
                                match uniformFieldValue(fd, nodes) {
                                    case Some(j) => Map.insert(fd#name, j, acc2)
                                    case None    => acc2
                                }, acc, fields)
                        };
                        let snapshot = List.foldLeft(foldFields,
                            (Map.empty(): Map[String, Util.Json.Json]), sections);
                        Array.put(snapshot, 0, state#inspector#currentValues)
                    }
                }
            }
        }

    /// 選択なし時に Inspector スナップショットを空にする
    def clearInspectorSnapshot(state: IdeState.IdeState): Unit \ IO = {
        Array.put((Nil: List[NodeInspector.FieldSection]), 0, state#inspector#schema);
        Array.put((None: Option[Editor.Selection]), 0, state#inspector#currentSelection);
        Array.put((Map.empty(): Map[String, Util.Json.Json]), 0,
                  state#inspector#currentValues);
        Array.put(None, 0, state#inspector#worldPos)
    }

    /// FieldDef を「全ノードで snapshot が Some を返す」もの（＝全ノード共通プロパティ）だけ残す。
    def filterCommonSections(sections: List[NodeInspector.FieldSection],
                             nodes: List[EngineNode[Unit]]): List[NodeInspector.FieldSection] =
        let keep = fd -> List.forAll(n -> not Option.isEmpty(fd#snapshot(n)), nodes);
        List.map(sec -> {typeName = sec#typeName,
                         common = List.filter(keep, sec#common),
                         advanced = List.filter(keep, sec#advanced)}, sections)
            |> List.filter(sec -> not (List.isEmpty(sec#common) and List.isEmpty(sec#advanced)))

    /// 全ノードで snapshot 値が一致すればその値、欠落 or 不一致なら None（= mixed）。
    def uniformFieldValue(fd: NodeInspector.FieldDef,
                          nodes: List[EngineNode[Unit]]): Option[Util.Json.Json] =
        let vals = List.map(n -> fd#snapshot(n), nodes);
        if (List.forAll(v -> not Option.isEmpty(v), vals)) {
            let strs = List.map(v -> "${v}", vals);
            match strs {
                case Nil      => None
                case s0 :: rest =>
                    if (List.forAll(s -> s == s0, rest)) List.head(vals) |> Option.flatMap(x -> x)
                    else None
            }
        } else None

/// Open Project... 経由で積まれた project を消費して in-place 再ロードする。
/// 戻り値: (新しい fontName, 描画リセット用の空 Scene)
/// 戻り値後に pendingSceneRef に先頭シーンを積んでおき、同フレームの loadPendingSceneOrKeep
/// で実シーンへ差し替わる
def reloadProject(state: IdeState.IdeState, oldFontName: Option[String], path: String):
        (Option[String], Scene[Unit]) \ {IO, Fs.FileRead, Fs.Glob, Fs.ModificationTime,
                                          Chan, NonDet, Editor.EditorState, IdeGui.Gui} =
    println("[Main] Reloading project: ${path}");
    // ロード中フラグを立てる。renderLoop が先頭シーン描画完了時に hideLoading を呼ぶ
    Array.put(true, 0, state#loadingActiveRef);
    IdeGui.Gui.setLoadingProgress("プロジェクトを読み込み中...", 0.05f64);
    match ProjectLoader.loadProject(path) {
        case Ok(proj) => {
            let sceneFiles = ProjectLoader.findSceneFiles(path)
                |> List.map(rel -> (joinPath(path, rel), rel))
                |> List.sortBy(p -> snd(p));
            IdeState.setSceneFiles(state, sceneFiles);
            IdeGui.Gui.setLoadingProgress("シーンを検索中...", 0.25f64);
            let textureNames = proj#config#textureManifest |> List.map(e -> e#name);
            IdeState.setTextureNames(state, textureNames);
            let texturePathMap = proj#config#textureManifest
                |> List.map(e -> (e#name, e#path))
                |> List.toMap;
            IdeState.setTexturePathMap(state, texturePathMap);
            let soundNames = proj#config#soundManifest |> List.map(e -> e#name);
            IdeState.setSoundNames(state, soundNames);
            let resources = ResourceDiscovery.discover(path);
            ResourceState.setDiscovered(state#resource, resources);
            // S8: assets/maps/*.map.json を列挙して Maps タブ用に登録
            let mapFiles = MapEditorPanel.findMapFiles(path);
            MapEditorState.setLevelFiles(state#mapEditor, mapFiles);
            // S13: tileset PNG を Image としてキャッシュ
            MapEditorPanel.loadTilesetImages(state);
            IdeState.setCurrentProjectRoot(state, Some(path));
            IdeState.setCurrentDesign(state, proj#config#designWidth, proj#config#designHeight);
            IdeGui.Gui.setLoadingProgress("リソースを検索中...", 0.50f64);
            let newFontName = List.head(proj#config#fontManifest) |> Option.map(f -> f#name);
            // Editor の scene.json 索引を新プロジェクトのものに差し替える。
            // これをしないと EditableNode.collectAll が空 → clicks が hit しない
            let newIndex = SceneJsonIndex.loadAt(path);
            let curEditor = Editor.EditorState.get();
            Editor.EditorState.put({rootJsonIndex = newIndex | curEditor});
            // 新 project の src/scenes を監視する HotReload watcher を起動する。
            // Editor 本体の watcher は IDE 起動時 cwd 基準で固定なので機能しない。
            // 起動した watcher は spawn したリレーループで flag に変換し、renderLoop が
            // pendingSceneRef に積み直す。古い watcher は recv blocked のまま放置される
            // (Open Project は稀なので leak は許容)
            let reloadRx = HotReload.startWatcherAt(path + "/src/scenes");
            let flagRef = state#runtime#reloadFlag;
            spawn { reloadRelay(reloadRx, flagRef) } @ Static;
            // GL リソースの再 init を AWT EDT (paintGL) に依頼。clearColor/designSize/
            // texture/font/projection/audio が新 config の値に切り替わる
            Array.put(Some(proj#config), 0, state#runtime#pendingConfig);
            IdeGui.Gui.setLoadingProgress("GL リソースを初期化中...", 0.75f64);
            // 先頭シーンの auto-load は swap 完了後に renderLoop が遅延実行する。
            // 即座に pendingSceneRef を積むと、まだ古い fontAtlasesArr で getFontAtlas
            // が呼ばれ bug! になるため、希望だけ立てて実体は次フレーム以降に委譲
            Array.put(true, 0, state#wantsAutoLoadFirstSceneRef);
            // GUI 側で TreeView を再構築 + Title 更新 (実装は handler 経由で JavaFXIdeUI に dispatch)
            IdeGui.Gui.populateProjectTree();
            IdeGui.Gui.setTitle("flix_game_engine IDE — ${proj#config#title} (${path})");
            (newFontName, Scene.empty())
        }
        case Err(msg) => {
            println("[Main] Open Project failed: ${msg}");
            Array.put(false, 0, state#loadingActiveRef);
            IdeGui.Gui.hideLoading();
            (oldFontName, Scene.empty())
        }
    }

/// pendingSceneRef を消費して新シーンを読むか、変更が無ければ現シーンをそのまま返す。
/// fontName が指定されているシーンは loadSceneWithFont で Label2D 対応で読み込む。
///
/// 注: AudioStreamPlayer ノードの `applyAudioAttach` は呼ばない (= IDE preview では
/// BGM は鳴らない)。Audio effect を renderLoop に伝播させると IDE 全体のロードが
/// 著しく遅くなったため、Inspector での編集 → JSON 書き戻しは効くが、preview
/// での音再生は **ゲーム本体 (`flix run`) でのみ** 確認する運用にする。
def loadPendingSceneOrKeep(state: IdeState.IdeState, fontName: Option[String],
                            currentScene: Scene[Unit]):
        Scene[Unit] \ {IO, GameEngine.Game, Fs.FileRead} =
    match IdeState.takePendingScene(state) {
        case None => currentScene
        case Some(path) =>
            println("[Main] Loading scene: ${path}");
            // ステータスバー / Inspector の参照用に現シーンパスを記録
            Array.put(Some(path), 0, state#currentScenePathRef);
            // Inspector の Container/Layout サポート用に scene JSON もパースしてキャッシュ
            let readResult = run {
                Fs.ReadFile.read(path)
            } with Fs.ReadFile.runWithFileRead;
            let jsonOpt = Result.toOption(readResult)
                |> Option.flatMap(s -> JsonCompat.parse(String.trim(s)));
            Array.put(jsonOpt, 0, state#runtime#currentSceneJson);
            match fontName {
                case Some(name) =>
                    let atlas = GameEngine.Game.getFontAtlas(name);
                    SceneLoader.loadSceneWithFont(path, atlas, SceneLoader.constTagParser(()), Scene.empty())
                case None =>
                    SceneLoader.loadScene(path, SceneLoader.constTagParser(()), Scene.empty())
            }
    }

/// プレビュー描画の合成。editor の選択枠 + ハンドル + コリジョン形状を重ねる
def composePreview(scene: Scene[Unit]):
        Scene[Unit] \ {GameEngine.Game, Editor.EditorState} =
    // デザイン解像度（ゲーム画面）の枠を最初に敷き、その上にエディタ overlay を重ねる。
    // これで「黒い領域のどこが実ゲーム画面か」が一目で分かり、その枠内に配置できる。
    // 灰色ワークスペース上に、ゲーム画面枠(藍)＋原点の赤X/緑Y線を重ねる (Godot の Viewport/Origin)。
    // editor の pan/zoom transform を枠/軸/オーバーレイ全てに共有してパン・ズームに追従させる。
    let vp = GameEngine.Game.getViewportRect();
    let view = Editor.currentEditorView();
    let zoom = view#zoom;
    let framed = Overlay.addDesignFrame(vp#size, zoom, (), scene);
    // スナップ ON 時は吸着の区切り単位で白いグリッドを敷く（OFF=0.0 なら addSnapGrid が無描画）。
    // 画面左上の design 座標 = editor pan。そこから見える範囲を覆う（画面外も）。
    let visibleTopLeft = {x = view#panX, y = view#panY};
    let withGrid = Overlay.addSnapGrid(visibleTopLeft, Editor.currentSnapStep(), zoom, (), framed);
    let withOrigin = Overlay.addOriginLines(vp#size, zoom, (), withGrid);
    Editor.applyOverlay((), withOrigin)

/// Inspector schema widget が積んだ pending edits をすべて消費して書き戻す。
/// 各 PendingEdit は SceneSerializer 呼出までを closure に閉じ込めているので、
/// ここでは run() を呼ぶだけ。HotReload watcher が拾って次フレームで scene 再 load。
def consumeInspectorEdits(state: IdeState.IdeState):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite} = {
    let edits = Array.get(0, state#inspector#pendingEdits);
    Array.put((Nil: List[NodeInspector.PendingEdit]), 0, state#inspector#pendingEdits);
    List.forEach(e -> e#perform(), edits)
}

/// Inspector の Play/Stop ボタン click handler が積んだ音声コマンドを 1 件取り出して
/// GameEngine.Audio handler に流す。JavaFX EDT は effect スコープ外なので、
/// ボタンは Ref に書くだけ → ここで effect 経由で OpenAL に届ける、という橋渡し。
/// Play 時は Inspector で編集された volume / loop も合わせて反映する。
def consumePendingAudioCommand(state: IdeState.IdeState):
        Unit \ {IO, GameEngine.Audio} =
    match IdeState.takeAudioCommand(state) {
        case None => ()
        case Some(IdeState.AudioCommand.Play(name, vol, loop)) =>
            AudioStreamPlayer.setVolume(name, vol);
            AudioStreamPlayer.setLooping(name, loop);
            AudioStreamPlayer.play(name)
        case Some(IdeState.AudioCommand.Stop(name)) => AudioStreamPlayer.stop(name)
    }

/// File → New Scene... で積まれた (name, rootType) を消費して .scene.json を生成する。
/// main thread でのみ呼ぶ (Fs.* と Editor.EditorState handler がここにしか無い)。
/// 生成後は sceneFiles 再列挙 + rootJsonIndex 更新 + pendingSceneRef 予約まで行い、
/// renderLoop の sceneChanged 経路が TreeView 反映と auto-load を担う。
def consumePendingNewScene(state: IdeState.IdeState):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState} =
    match IdeState.takePendingNewScene(state) {
        case None                   => ()
        case Some((name, rootType)) =>
            match IdeState.getCurrentProjectRoot(state) {
                case None       => println("[Main] New Scene: プロジェクト未ロード")
                case Some(root) => createNewSceneFile(state, root, name, rootType)
            }
    }

def createNewSceneFile(state: IdeState.IdeState, root: String, name: String, rootType: String):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState} =
    let scenePath = joinPath(root, "src/scenes/${name}.scene.json");
    if (pathExists(scenePath))
        println("[Main] New Scene: 既に存在します: ${name}.scene.json")
    else
        match writeSceneFile(scenePath, newSceneJson(name, rootType)) {
            case Err(msg) => println("[Main] New Scene 保存失敗: ${msg}")
            case Ok(_)    => registerNewScene(state, root, scenePath, rootType)
        }

/// 生成済みファイルを scene 一覧・editor 索引・auto-load 予約に反映する。
def registerNewScene(state: IdeState.IdeState, root: String, scenePath: String, rootType: String):
        Unit \ {IO, Fs.FileRead, Fs.Glob, Editor.EditorState} = {
    println("[Main] New Scene created: ${scenePath} (root=${rootType})");
    refreshSceneListAndIndex(state, root);
    // 生成したシーンを次フレームで auto-load + 選択
    Array.put(Some(scenePath), 0, state#pendingSceneRef)
}

/// src/scenes を再列挙して TreeView 用 Ref を更新し、editor の click-hit 索引も差し替える。
/// New Scene / Delete / Rename いずれの後にも呼ぶ共通リフレッシュ。
def refreshSceneListAndIndex(state: IdeState.IdeState, root: String):
        Unit \ {IO, Fs.FileRead, Fs.Glob, Editor.EditorState} = {
    let sceneFiles = ProjectLoader.findSceneFiles(root)
        |> List.map(rel -> (joinPath(root, rel), rel))
        |> List.sortBy(p -> snd(p));
    IdeState.setSceneFiles(state, sceneFiles);
    let newIndex = SceneJsonIndex.loadAt(root);
    let curEditor = Editor.EditorState.get();
    Editor.EditorState.put({rootJsonIndex = newIndex | curEditor})
}

/// Project Settings で積まれた design 解像度変更を適用する。
/// project.json の designWidth/Height を書き換え、プロジェクトを再ロードして config swap を起こす
/// (既存の reloadProject 経路を再利用 → design サイズ・projection・ビューポートが live 反映)。
def consumePendingProjectSettings(state: IdeState.IdeState):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite} =
    match IdeState.takePendingProjectSettings(state) {
        case None => ()
        case Some((w, h)) =>
            match IdeState.getCurrentProjectRoot(state) {
                case None       => println("[Main] Project Settings: プロジェクト未ロード")
                case Some(root) =>
                    let jsonPath = joinPath(root, "project.json");
                    match setProjectDesignSize(jsonPath, w, h) {
                        case Err(msg) => println("[Main] Project Settings 保存失敗: ${msg}")
                        case Ok(_)    => {
                            println("[Main] Project design size -> ${w}x${h}; reloading project");
                            Array.put(Some(root), 0, state#pendingProjectRef)
                        }
                    }
            }
    }

/// project.json の designWidth / designHeight を書き換える。キー順・スタイルは保持。
def setProjectDesignSize(jsonPath: String, w: Int32, h: Int32):
        Result[String, Unit] \ {Fs.FileRead, Fs.FileWrite} =
    let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
    let parsed = readResult
        |> Result.mapErr(e -> "read failed: ${e}")
        |> Result.flatMap(t -> JsonOrdered.parse(String.trim(t)));
    match parsed {
        case Err(msg) => Err(msg)
        case Ok(json) =>
            let updated = setTopLevelNumber("designHeight", h,
                            setTopLevelNumber("designWidth", w, json));
            let pretty = JsonOrdered.writePretty(2, updated);
            let writeResult = run { Fs.WriteFile.write({str = pretty}, jsonPath) }
                with Fs.WriteFile.runWithFileWrite;
            writeResult |> Result.mapErr(e -> "write failed: ${e}") |> Result.map(_ -> ())
    }

/// ルート OObject の top-level 数値キーを差し替える (存在するキーのみ。順序は保持)。
def setTopLevelNumber(key: String, value: Int32, json: JsonOrdered.OrderedJson):
        JsonOrdered.OrderedJson =
    match json {
        case JsonOrdered.OrderedJson.OObject(entries, style) =>
            let newEntries = List.map(e -> {
                let (k, v) = e;
                if (k == key)
                    (k, JsonOrdered.OrderedJson.ONumber(Int32.toString(value)))
                else (k, v)
            }, entries);
            JsonOrdered.OrderedJson.OObject(newEntries, style)
        case other => other
    }

/// Add Child Node で積まれた子ノード追加を main thread で適用する。
/// 追加後はそのシーンを再ロード予約 → sceneChanged 経路で preview と TreeView に反映。
def consumePendingAddChild(state: IdeState.IdeState):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, EditHistory.Rewind} =
    match IdeState.takePendingAddChild(state) {
        case None => ()
        case Some((abs, parentPath, childType)) =>
            match SceneSerializer.addChild(abs, parentPath, childType) {
                case Ok(childName) => {
                    println("[Main] Add child: ${childType} as '${childName}' under ${parentPath}");
                    // 追加ノードも Undo 可能に（Cmd+Z で removeChild）
                    EditHistory.Rewind.save(EditHistory.Entry.AddedNodeEntry({
                        jsonPath = abs,
                        nodePath = List.append(parentPath, childName :: Nil)}));
                    Array.put(Some(abs), 0, state#pendingSceneRef)
                }
                case Err(msg) => println("[Main] Add child failed: ${msg}")
            }
    }

/// Delete / Backspace 押下で、選択中ノード（非ルート）を削除キューに積む。
/// テキスト入力中は TextField がキーを消費して scene まで届かないので、ここは発火しない。
/// 削除すると選択が解除されるため、キー長押しでも 1 回だけ削除される（連打防止のフラグ不要）。
def handleDeleteKey(state: IdeState.IdeState): Unit \ {IO, GameEngine.Game, Editor.EditorState} =
    let pressed = GameEngine.Game.isKeyPressed(GameEngine.Key.Delete)
               or GameEngine.Game.isKeyPressed(GameEngine.Key.Backspace);
    if (not pressed) ()
    else match Editor.EditorState.get()#selections {
        case Nil          => ()
        case primary :: _ =>
            // 全選択ノードのうち非ルート（jsonNodePath 長 >= 2）を一括削除キューへ。
            let paths = Editor.EditorState.get()#selections
                |> List.filter(s -> List.length(s#jsonNodePath) >= 2)
                |> List.map(s -> s#jsonNodePath);
            if (List.isEmpty(paths)) ()
            else Array.put(Some(IdeState.SceneOp.DeleteNodes(primary#jsonPath, paths)),
                           0, state#pendingSceneOpRef)
    }

/// Scenes ツリーのコンテキストメニューで積まれた削除/改名を main thread で適用する。
def consumePendingSceneOp(state: IdeState.IdeState):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState,
                EditHistory.Rewind, IdeGui.Gui} =
    match IdeState.takePendingSceneOp(state) {
        case None     => ()
        case Some(op) =>
            match IdeState.getCurrentProjectRoot(state) {
                case None       => println("[Main] SceneOp: プロジェクト未ロード")
                case Some(root) => applySceneOp(state, root, op)
            }
    }

def applySceneOp(state: IdeState.IdeState, root: String, op: IdeState.SceneOp):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState,
                EditHistory.Rewind, IdeGui.Gui} =
    match op {
        case IdeState.SceneOp.DeleteScene(abs)       => deleteSceneFile(state, root, abs)
        case IdeState.SceneOp.RenameScene(abs, name) => renameSceneFile(state, root, abs, name)
        case IdeState.SceneOp.DeleteNode(abs, np)    => deleteNodeFromScene(state, abs, np)
        case IdeState.SceneOp.DeleteNodes(abs, nps)  => deleteNodesFromScene(state, abs, nps)
        case IdeState.SceneOp.DuplicateNode(abs, np) => duplicateNodeInScene(state, abs, np)
    }

/// ノード複製: 同じ親に clone を挿入。追加分は AddedNodeEntry で Undo（Cmd+Z で除去）。
def duplicateNodeInScene(state: IdeState.IdeState, abs: String, nodePath: List[String]):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, EditHistory.Rewind} =
    match SceneSerializer.duplicateNode(abs, nodePath) {
        case Err(msg)  => println("[Main] Duplicate node failed: ${msg}")
        case Ok(info)  => {
            EditHistory.Rewind.save(EditHistory.Entry.AddedNodeEntry({
                jsonPath = abs, nodePath = info#newNodePath}));
            println("[Main] Node duplicated: ${nodePath} -> '${info#newName}'");
            Array.put(Some(abs), 0, state#pendingSceneRef)
        }
    }

/// ノード削除: 親 children から除去→Undo 用に断片を保存→選択クリア→再 load。
/// 構造復元(Undo)は EditHistory の RemoveSubtreeEntry に断片を積んでおき、
/// Cmd+Z で SceneSerializer.insertSubtree により同位置へ戻す。
def deleteNodeFromScene(state: IdeState.IdeState, abs: String, nodePath: List[String]):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Editor.EditorState, EditHistory.Rewind} =
    match SceneSerializer.removeChild(abs, nodePath) {
        case Err(msg)  => println("[Main] Delete node failed: ${msg}")
        case Ok(info)  => {
            EditHistory.Rewind.save(EditHistory.Entry.RemoveSubtreeEntry({
                jsonPath = abs, parentPath = info#parentPath,
                index = info#index, fragment = info#fragment}));
            println("[Main] Node deleted: ${nodePath}");
            // 選択を解除（削除済みノードへの stale 参照を避ける。reload race 対策）
            let st = Editor.EditorState.get();
            Editor.EditorState.put({selected = None, dragOrigin = None, nodeOrigin = None,
                                    resizeOrigin = None, rotateOrigin = None | st});
            // 再 load してツリー/ビューポートを更新（addChild と同じ経路）
            Array.put(Some(abs), 0, state#pendingSceneRef)
        }
    }

/// 複数ノード削除: 各ノードを順に removeChild し、Undo 用断片を積む。
/// 親と子孫が同時選択されていると親削除で子孫も消えるため、子孫側は Err になるが握りつぶす。
def deleteNodesFromScene(state: IdeState.IdeState, abs: String, paths: List[List[String]]):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Editor.EditorState, EditHistory.Rewind} =
    let savedAny = List.foldLeft((acc, np) ->
        match SceneSerializer.removeChild(abs, np) {
            case Err(msg) => { println("[Main] Delete node skipped (${np}): ${msg}"); acc }
            case Ok(info) => {
                EditHistory.Rewind.save(EditHistory.Entry.RemoveSubtreeEntry({
                    jsonPath = abs, parentPath = info#parentPath,
                    index = info#index, fragment = info#fragment}));
                println("[Main] Node deleted: ${np}");
                true
            }
        }, false, paths);
    if (savedAny) {
        // 選択を解除（削除済みノードへの stale 参照を避ける）して再 load。
        let st = Editor.EditorState.get();
        Editor.EditorState.put({selected = None, selections = Nil, dragOrigin = None,
                                nodeOrigin = None, resizeOrigin = None, rotateOrigin = None | st});
        Array.put(Some(abs), 0, state#pendingSceneRef)
    } else ()

def deleteSceneFile(state: IdeState.IdeState, root: String, abs: String):
        Unit \ {IO, Fs.FileRead, Fs.Glob, Editor.EditorState, IdeGui.Gui} =
    if (not SceneFileOps.delete(abs))
        println("[Main] Delete 失敗: ${abs}")
    else {
        println("[Main] Scene deleted: ${abs}");
        let wasCurrent = IdeState.getCurrentScenePath(state) == Some(abs);
        refreshSceneListAndIndex(state, root);
        // 削除したのが現在表示中のシーンなら、残りの先頭シーンへ切替 (無ければ表示クリア)
        if (wasCurrent) {
            match List.head(Array.get(0, state#sceneFilesRef)) {
                case Some((nextAbs, _)) => Array.put(Some(nextAbs), 0, state#pendingSceneRef)
                case None               => Array.put((None: Option[String]), 0, state#currentScenePathRef)
            }
        } else ();
        // 非現在シーン削除では sceneChanged が立たないのでツリーを明示更新
        IdeGui.Gui.populateProjectTree()
    }

def renameSceneFile(state: IdeState.IdeState, root: String, abs: String, newName: String):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState, IdeGui.Gui} =
    let newAbs = joinPath(root, "src/scenes/${newName}.scene.json");
    if (pathExists(newAbs))
        println("[Main] Rename: 既に存在します: ${newName}.scene.json")
    else
        match readFileContent(abs) {
            case None          => println("[Main] Rename: 読み込み失敗 ${abs}")
            case Some(content) => writeRenamedScene(state, root, abs, newAbs, content, newName)
        }

def writeRenamedScene(state: IdeState.IdeState, root: String, abs: String, newAbs: String,
                      content: String, newName: String):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Editor.EditorState, IdeGui.Gui} =
    match writeSceneFile(newAbs, renameRootInJson(content, newName)) {
        case Err(msg) => println("[Main] Rename 保存失敗: ${msg}")
        case Ok(_)    => {
            discard SceneFileOps.delete(abs);
            println("[Main] Scene renamed: ${abs} -> ${newAbs}");
            let wasCurrent = IdeState.getCurrentScenePath(state) == Some(abs);
            refreshSceneListAndIndex(state, root);
            if (wasCurrent) Array.put(Some(newAbs), 0, state#pendingSceneRef) else ();
            IdeGui.Gui.populateProjectTree()
        }
    }

def readFileContent(path: String): Option[String] \ Fs.FileRead =
    run {
        match Fs.ReadFile.read(path) {
            case Ok(content) => Some(content)
            case Err(_)      => None
        }
    } with Fs.ReadFile.runWithFileRead

/// シーン JSON のルート "name" を newName に差し替える。パース不能ならそのまま。
def renameRootInJson(content: String, newName: String): String =
    match JsonCompat.parse(String.trim(content)) {
        case None       => content
        case Some(json) =>
            let updated = JsonOps.setAtKeyPath(json, "name" :: Nil,
                Util.Json.Json.JString(newName));
            Util.Json.toPrettyString(2i32, updated)
    }

def pathExists(path: String): Bool \ Fs.FileRead =
    run {
        match Fs.ReadFile.read(path) {
            case Ok(_)  => true
            case Err(_) => false
        }
    } with Fs.ReadFile.runWithFileRead

def writeSceneFile(path: String, content: String): Result[String, Unit] \ Fs.FileWrite =
    let result = run {
        Fs.WriteFile.write({str = content}, path)
    } with Fs.WriteFile.runWithFileWrite;
    match result {
        case Ok(_)      => Ok(())
        case Err(error) => Err("write failed: ${error}")
    }

/// 新規シーンの最小 .scene.json を組み立てる。ルート型ごとに必須フィールドだけ埋める
/// (Marker2D: pos / CanvasLayer: layer)。子ノードは IDE の Add Child Node で足していく。
def newSceneJson(name: String, rootType: String): String =
    match rootType {
        case "CanvasLayer" =>
            "{\n  \"type\": \"CanvasLayer\",\n  \"name\": \"${name}\",\n  \"layer\": 0\n}\n"
        case _ =>
            "{\n  \"type\": \"Marker2D\",\n  \"name\": \"${name}\",\n  \"pos\": [0, 0]\n}\n"
    }

/// 選択集合の同一性シグネチャ（jsonPath + nodePath を連結）。差分検出に使う。
def selectionsSig(sels: List[Editor.Selection]): String =
    List.map(s -> "${s#jsonPath}|${s#nodePath}", sels) |> String.intercalate(";")

/// SceneTree からの node 選択要求 (FX EDT が積む) を消費して Editor#selected に反映
def consumePendingNodeSelection(state: IdeState.IdeState):
        Unit \ {IO, Editor.EditorState} =
    match Array.get(0, state#runtime#pendingNodeSelection) {
        case None       => ()
        case Some(sels) => {
            Array.put((None: Option[List[Editor.Selection]]), 0, state#runtime#pendingNodeSelection);
            let cur = Editor.EditorState.get();
            // 先頭を primary（キャンバス操作/オーバーレイ主対象）、全体を selections に。
            Editor.EditorState.put({selected = List.head(sels), selections = sels | cur})
        }
    }

/// HotReload reloadRelay が立てた flag を消費して、現シーンを再読込予約する。
/// reloadRelay (Open Project ごとに spawn) が channel recv 経由で flag を true にする
def refreshTreeOnReload(state: IdeState.IdeState):
        Unit \ {IO, Editor.EditorState} =
    let _ = Editor.pollRawReload(); // Editor 本体の channel も空読みして leak を防ぐ
    if (Array.get(0, state#runtime#reloadFlag)) {
        Array.put(false, 0, state#runtime#reloadFlag);
        match IdeState.getCurrentScenePath(state) {
            case Some(path) => Array.put(Some(path), 0, state#pendingSceneRef)
            case None       => ()
        }
    } else ()

/// HotReload watcher が送ってくる Unit シグナルを `state#runtime#reloadFlag = true` に
/// 変換するリレーループ。Open Project ごとに spawn する。
/// `state` から refs だけ取り出して持つので、project 切替後も自分の rx と flag に対して
/// 動き続ける (前 project の relay は rx が二度と発火しないので idle のまま leak する)
def reloadRelay(rx: Receiver[Unit], flagRef: Array[Bool, Static]):
        Unit \ {Chan, NonDet, IO} =
    select {
        case _ <- recv(rx) => Array.put(true, 0, flagRef)
    };
    reloadRelay(rx, flagRef)

def decorateTitle(config: GameEngine.EngineConfig, path: String): GameEngine.EngineConfig =
    { title = "flix_game_engine IDE — ${config#title} (${path})" | config }

def emptyConfig(): GameEngine.EngineConfig =
    {
        designWidth     = 800,
        designHeight    = 600,
        windowWidth     = 800,
        windowHeight    = 600,
        title           = "flix_game_engine IDE — No project loaded",
        textureManifest = Nil,
        fontManifest    = Nil,
        soundManifest   = Nil,
        clearColor      = {r = 0.13f32, g = 0.13f32, b = 0.13f32},
        maxDeltaTime    = 0.05
    }

def joinPath(dir: String, rel: String): String =
    if (String.endsWith({suffix = "/"}, dir))
        "${dir}${rel}"
    else
        "${dir}/${rel}"

/// シーンファイルの物理削除だけを担う小さなラッパ。Main.flix は mod 無しのフラット
/// ファイルなので、Java import を局所化するためにここだけ mod に閉じる。
mod SceneFileOps {
    import java.io.File
    /// path のファイルを削除する。存在して削除できたら true。
    pub def delete(path: String): Bool \ IO = {
        let f = new File(path);
        if (f.exists()) f.delete() else false
    }
}
