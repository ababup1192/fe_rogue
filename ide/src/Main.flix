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
        sessionLoop(state, None)
    } with Fs.Glob.runWithIO
      with Fs.FileRead.runWithIO
      with Fs.FileWrite.runWithIO
      with Fs.ModificationTime.runWithFileTime
      with Fs.FileTime.runWithIO

/// 1 セッションを走らせる。Open Project でディレクトリが選ばれていれば
/// 再帰的に新 project で立て直す。
def sessionLoop(state: IdeState.IdeState, projectPath: Option[String]):
        Unit \ {IO, Fs.FileRead, Fs.FileWrite, Fs.Glob, Fs.ModificationTime, Chan, NonDet} =
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
                    // texture 名 → 絶対パス。SpritePreview が BufferedImage 読込で使う。
                    let texturePathMap = proj#config#textureManifest
                        |> List.map(e -> (e#name, e#path))
                        |> List.toMap;
                    IdeState.setTexturePathMap(state, texturePathMap);
                    // resources/ 配下の Resource ファイルを列挙して ResourceState に登録。
                    let resources = ResourceDiscovery.discover(path);
                    println("[Main] Discovered ${List.length(resources)} resource(s) in ${path}/resources");
                    ResourceState.setDiscovered(state#resource, resources);
                    decorateTitle(proj#config, path)
                case Err(msg) =>
                    // project.json が無い / パース失敗。クラッシュさせず empty state へ。
                    println("[Main] Open Project failed: ${msg}");
                    IdeState.setSceneFiles(state, Nil);
                    IdeState.setTextureNames(state, Nil);
                    IdeState.setTexturePathMap(state, Map.empty());
                    ResourceState.setDiscovered(state#resource, Nil);
                    emptyConfig()
            }
        case None =>
            println("[Main] Starting IDE with no project");
            IdeState.setSceneFiles(state, Nil);
            IdeState.setTextureNames(state, Nil);
            IdeState.setTexturePathMap(state, Map.empty());
            ResourceState.setDiscovered(state#resource, Nil);
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
    } with JavaFXLayer.withJavaFX(config, state#fxPendingConfigRef, customize);
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
        Unit \ {IO, GameEngine.Game, Fs.FileRead, Fs.FileWrite, Fs.Glob,
                Fs.ModificationTime, Chan, NonDet} =
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
        Unit \ {IO, GameEngine.Game, Fs.FileRead, Fs.FileWrite, Fs.Glob,
                Editor.EditorState, EditHistory.Rewind} =
    if (GameEngine.Game.shouldClose()) ()
    else {
        // Phase 2: File → Open Project... で積まれた project を消費して in-place 再ロード。
        // Phase 3 で GL リソース再 init を AWT EDT に委譲済み
        let (newFontName, baseScene) = match IdeState.takePendingProject(state) {
            case None       => (fontName, currentScene)
            case Some(path) => reloadProject(state, fontName, path)
        };
        // Deferred auto-load: AWT EDT が config swap を完了 (fxPendingConfigRef == None)
        // したフレームで初めて先頭シーンを pendingSceneRef に積む。font/texture が揃った
        // 後にロードされるので getFontAtlas が安全に解決できる
        if (Array.get(0, state#wantsAutoLoadFirstSceneRef)
            and Option.isEmpty(Array.get(0, state#fxPendingConfigRef))) {
            match List.head(Array.get(0, state#sceneFilesRef)) {
                case Some((abs, rel)) => {
                    println("[Main] Auto-loading first scene: ${rel}");
                    Array.put(Some(abs), 0, state#pendingSceneRef)
                }
                case None => ()
            };
            Array.put(false, 0, state#wantsAutoLoadFirstSceneRef)
        } else ();
        let nextScene = loadPendingSceneOrKeep(state, newFontName, baseScene);
        // Editor の真の選択状態を status bar に出すため、毎フレーム書き出す。
        // syncEditorSelectionToTree 経由の selectedNodePathRef は currentSceneJsonRef
        // が None だと変換できず常に "-" になるため、診断目的で直接 editor を覗く
        let editorSel = Editor.EditorState.get()#selected;
        let editorSelText = match editorSel {
            case None      => "-"
            case Some(sel) => "${sel#nodePath}"
        };
        Array.put(editorSelText, 0, state#fxEditorSelDisplayRef);
        // ユーザーが JTree でノードを選んだ場合は、editor 側の selected にも反映する
        // (preview に選択枠を出すため)。Editor.handleInput の前に呼ぶ
        SelectionBridge.applyTreeSelectionToEditor(state);
        // editor がマウス入力を取り込み、選択 / ドラッグ / リサイズ / Undo まで処理して
        // 必要に応じて scene を更新する。F1 で OFF にすると素通しで戻る。
        // 編集を確定したフレームでは Editor.handleInput が JSON 書き戻しまで行う
        let edited = Editor.handleInput(nextScene);
        // preview 上でユーザーがクリックして選択が変わったケースを IdeState 側に同期する。
        // 変化があった場合は IdeUI.applySelectionToView で JTree と Inspector も更新する
        // (Phase 1-2 では JTree は無いので no-op になる)
        if (SelectionBridge.syncEditorSelectionToTree(state))
            IdeUI.applySelectionToView(state)
        else ();
        // editor がドラッグ確定で JSON を書き戻すと HotReload watcher が発火する。
        // 検知したら現シーンの JTree / Inspector を再構築して最新値を表示する
        refreshTreeOnReload(state);
        let preview = composePreview(edited);
        GameEngine.render(preview);
        renderLoop(state, newFontName, edited)
    }

/// Open Project... 経由で積まれた project を消費して in-place 再ロードする。
/// 戻り値: (新しい fontName, 描画リセット用の空 Scene)
/// 戻り値後に pendingSceneRef に先頭シーンを積んでおき、同フレームの loadPendingSceneOrKeep
/// で実シーンへ差し替わる
def reloadProject(state: IdeState.IdeState, oldFontName: Option[String], path: String):
        (Option[String], Scene[Unit]) \ {IO, Fs.FileRead, Fs.Glob, Editor.EditorState} =
    println("[Main] Reloading project: ${path}");
    match ProjectLoader.loadProject(path) {
        case Ok(proj) => {
            let sceneFiles = ProjectLoader.findSceneFiles(path)
                |> List.map(rel -> (joinPath(path, rel), rel))
                |> List.sortBy(p -> snd(p));
            IdeState.setSceneFiles(state, sceneFiles);
            let textureNames = proj#config#textureManifest |> List.map(e -> e#name);
            IdeState.setTextureNames(state, textureNames);
            let texturePathMap = proj#config#textureManifest
                |> List.map(e -> (e#name, e#path))
                |> List.toMap;
            IdeState.setTexturePathMap(state, texturePathMap);
            let resources = ResourceDiscovery.discover(path);
            ResourceState.setDiscovered(state#resource, resources);
            let newFontName = List.head(proj#config#fontManifest) |> Option.map(f -> f#name);
            // Editor の scene.json 索引を新プロジェクトのものに差し替える。
            // これをしないと EditableNode.collectAll が空 → clicks が hit しない
            let newIndex = SceneJsonIndex.loadAt(path);
            let curEditor = Editor.EditorState.get();
            Editor.EditorState.put({rootJsonIndex = newIndex | curEditor});
            // GL リソースの再 init を AWT EDT (paintGL) に依頼。clearColor/designSize/
            // texture/font/projection/audio が新 config の値に切り替わる
            Array.put(Some(proj#config), 0, state#fxPendingConfigRef);
            // 先頭シーンの auto-load は swap 完了後に renderLoop が遅延実行する。
            // 即座に pendingSceneRef を積むと、まだ古い fontAtlasesArr で getFontAtlas
            // が呼ばれ bug! になるため、希望だけ立てて実体は次フレーム以降に委譲
            Array.put(true, 0, state#wantsAutoLoadFirstSceneRef);
            // FX thread 側で TreeView を再構築 + Title 更新
            JavaFXIdeUI.schedulePopulateTree(state);
            JavaFXIdeUI.scheduleSetTitle(state,
                "flix_game_engine IDE — ${proj#config#title} (${path})");
            (newFontName, Scene.empty())
        }
        case Err(msg) => {
            println("[Main] Open Project failed: ${msg}");
            (oldFontName, Scene.empty())
        }
    }

/// pendingSceneRef を消費して新シーンを読むか、変更が無ければ現シーンをそのまま返す。
/// fontName が指定されているシーンは loadSceneWithFont で Label2D 対応で読み込む
def loadPendingSceneOrKeep(state: IdeState.IdeState, fontName: Option[String],
                            currentScene: Scene[Unit]):
        Scene[Unit] \ {IO, GameEngine.Game, Fs.FileRead} =
    match IdeState.takePendingScene(state) {
        case None => currentScene
        case Some(path) =>
            println("[Main] Loading scene: ${path}");
            // ステータスバー / Inspector の参照用に現シーンパスを記録
            Array.put(Some(path), 0, state#currentScenePathRef);
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
    Editor.applyOverlay((), scene)

/// Editor の HotReload watcher が発火したら、現シーンの JSON を再読込して
/// JTree と Inspector を最新値で再構築する。ドラッグ・リサイズ確定で editor が
/// JSON を書き戻すと、このパスを通って表示が即更新される。
///
/// IDE は editor 常時 ON で動かすため pollReload では握り潰されてしまう。
/// pollRawReload を使い、editor の on/off に関わらず JSON 変更を拾う。
///
/// populateSceneTree は選択をクリアして Inspector を placeholder に戻すので、
/// 直後に editor 側の選択を再同期 → applySelectionToView で同じノードを
/// 再選択し直し、Inspector に新しい座標・サイズを反映する。
def refreshTreeOnReload(state: IdeState.IdeState):
        Unit \ {IO, Editor.EditorState} =
    if (Editor.pollRawReload())
        match IdeState.getCurrentScenePath(state) {
            case Some(path) =>
                IdeUI.populateSceneTree(state, path);
                discard SelectionBridge.syncEditorSelectionToTree(state);
                IdeUI.applySelectionToView(state)
            case None => ()
        }
    else ()

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
