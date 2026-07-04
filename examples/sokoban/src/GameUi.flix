// GameUi — タイトルと CLEAR のページを、データとして宣言する。
// 見た目はすべて assets/*.ui.json に住む。起動時に両方のファイルが1つの
// UiWorld（engine_world の UI store）へ生成され、loop はそれを Worldline の隣で
// 単なる値として持ち運ぶ。毎フレーム projectUi が World の判定結果 —— どのペー
// ジを見せるか、クリアまでに何手かかったか —— をそこに刻み込み、UiRender がそれ
// をボックスとグリフに変換する。

mod GameUi {

    pub def titleUiPath(): String = "assets/Title.ui.json"
    pub def clearUiPath(): String = "assets/Clear.ui.json"

    /// UI キャンバス、design px 単位。
    pub def designSize(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// 両方のページ Spec を1つの UiWorld へ生成する。壊れた、あるいは存在しない
    /// ファイルはページなしへと縮退する —— 壊れたレベル文字列と同様、ゲームはそ
    /// れでも動く。
    pub def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        UiStore.empty() |> spawnPage(titleUiPath()) |> spawnPage(clearUiPath())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, spawned)) => spawned
            case Result.Err(_)           => ui
        }

    /// World を UI store に刻み込む: ページの可視性と手数。手数は誰のカウンター
    /// でもない —— loop から渡される Worldline.pastLength であり、履歴がすでに
    /// 手を数えていたのである。
    pub def projectUi(moves: Int32, w: Board.World, ui: UiStore.UiWorld): UiStore.UiWorld =
        let Board.World.World(b) = w;
        ui |> UiStore.setVisible("Title", b#screen == Board.Screen.Title)
           |> UiStore.setVisible("Clear", b#screen == Board.Screen.Playing and Board.won(w))
           |> UiStore.setText("Clear/panel/moves", "Moves: ${moves}")
}
