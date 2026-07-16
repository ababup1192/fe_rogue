// GameUi — UI ページ（assets/Hud.ui.json）の読み込みと毎フレームの投影。
// 見た目（文言の配置・色・字の大きさ）はすべて ui.json 側にあり、コードは bind の文言だけ流し込む。

mod GameUi {

    def pagePaths(): List[String] = "assets/Hud.ui.json" :: Nil

    /// 全ページの Spec を 1 つの UiWorld へ生成する。壊れた・存在しないファイルは
    /// そのページを抜いたまま進む（実験はそれでも動く）。
    pub def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        pagePaths() |> List.foldLeft((ui, path) -> spawnPage(path, ui), UiStore.empty())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, spawned)) => spawned
            case Result.Err(_)           => ui
        }

    /// 毎フレームの投影: bind キーへ今の表示文字列を流し込む。
    pub def projectUi(world: World.World): World.World =
        { ui = UiBinding.apply(key -> bindText(key, world), world#ui) | world }

    /// bind key → いまの表示文字列。ui.json 側の "bind" 宣言と対になる表。
    /// fullscreen/cursor はタイトルバーごと消えるフルスクリーン時でも statusLine の代わりに
    /// 画面内で読めるようにするための表示（起動確認をウィンドウ内だけで完結させる）。
    def bindText(key: String, world: World.World): Option[String] = match key {
        case "kindLabel"      => Some(World.transitionLabel(world))
        case "fullscreenFlag" => Some("fullscreen=${World.onOff(world#fullscreen)}")
        case "cursorFlag"     => Some("cursor=${World.onOff(world#cursorVisible)}")
        case _                => None
    }
}
