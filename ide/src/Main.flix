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

def main(): Unit \ IO =
    run {
        run {
            let state = IdeUI.newState();
            sessionLoop(state, None)
        } with Fs.Glob.runWithIO
    } with Fs.FileRead.runWithIO

/// 1 セッションを走らせる。Open Project でディレクトリが選ばれていれば
/// 再帰的に新 project で立て直す。
def sessionLoop(state: IdeUI.IdeState, projectPath: Option[String]): Unit \ {IO, Fs.FileRead, Fs.Glob} =
    let config = match projectPath {
        case Some(path) =>
            println("[Main] Loading project: ${path}");
            match ProjectLoader.loadProject(path) {
                case Ok(proj) =>
                    let sceneFiles = ProjectLoader.findSceneFiles(path)
                        |> List.map(rel -> (joinPath(path, rel), rel));
                    IdeUI.setSceneFiles(state, sceneFiles);
                    let textureNames = proj#config#textureManifest |> List.map(e -> e#name);
                    IdeUI.setTextureNames(state, textureNames);
                    decorateTitle(proj#config, path)
                case Err(msg) =>
                    // project.json が無い / パース失敗。クラッシュさせず empty state へ。
                    println("[Main] Open Project failed: ${msg}");
                    IdeUI.setSceneFiles(state, Nil);
                    IdeUI.setTextureNames(state, Nil);
                    emptyConfig()
            }
        case None =>
            println("[Main] Starting IDE with no project");
            IdeUI.setSceneFiles(state, Nil);
            IdeUI.setTextureNames(state, Nil);
            emptyConfig()
    };
    let customize = (frame, canvas) -> IdeUI.customize(state, frame, canvas);
    // Label2D を含むシーンを開けるよう、project の fontManifest の先頭フォント名を
    // SceneLoader.loadSceneWithFont に渡せるよう保持する。フォント未定義のプロジェクトでは
    // loadScene にフォールバックする (Label2D が含まれれば bug! になるが project 側の責務)。
    let fontName = List.head(config#fontManifest) |> Option.map(f -> f#name);
    run {
        ideLoop(state, fontName)
    } with SwingLayer.withSwing(config, customize);
    match IdeUI.takePendingProject(state) {
        case Some(newPath) =>
            println("[Main] Reloading with new project: ${newPath}");
            sessionLoop(state, Some(newPath))
        case None =>
            println("[Main] User closed window. Exiting.")
    }

/// shouldClose まで毎フレーム描画する。`pendingSceneRef` がセットされていれば
/// その scene をロードして以降の描画対象を差し替える。
/// `fontName` が Some(name) なら Label2D を含むシーンも loadSceneWithFont で開ける。
def ideLoop(state: IdeUI.IdeState, fontName: Option[String]): Unit \ {IO, GameEngine.Game, Fs.FileRead} =
    renderLoop(state, fontName, Scene.empty())

def renderLoop(state: IdeUI.IdeState, fontName: Option[String], currentScene: Scene[Unit]): Unit \ {IO, GameEngine.Game, Fs.FileRead} =
    if (GameEngine.Game.shouldClose()) ()
    else {
        let nextScene = match IdeUI.takePendingScene(state) {
            case Some(path) =>
                println("[Main] Loading scene: ${path}");
                match fontName {
                    case Some(name) =>
                        let atlas = GameEngine.Game.getFontAtlas(name);
                        SceneLoader.loadSceneWithFont(path, atlas, SceneLoader.constTagParser(()), Scene.empty())
                    case None =>
                        SceneLoader.loadScene(path, SceneLoader.constTagParser(()), Scene.empty())
                }
            case None => currentScene
        };
        // editor の Overlay.addCollisionShapes を再利用して、Area2D / Body2D 系の
        // collision shape を「薄青のアウトライン」で可視化する。プレビュー用の合成は
        // 都度行い、保存対象の nextScene 本体には混入させない
        let preview = Overlay.addCollisionShapes(
            Camera2D.identityTransform(), (), nextScene);
        GameEngine.render(preview);
        renderLoop(state, fontName, nextScene)
    }

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
