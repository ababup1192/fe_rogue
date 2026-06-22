///
/// Shape Survivors — hello world
///
/// 第一弾ゲーム「図形だけで作るオートシューター」の最小起動雛形。
/// まだゲームロジックは無い。ウィンドウを開き、背景の上に
///   - 自機を表す円（Arc2D を塗りつぶした円盤）
///   - タイトル文字（Label2D / SDF フォント）
/// を静止表示するだけ。これは設計 §3 の「図形 + 文字で見た目が成立するか」と、
/// MVU 的に `Scene` を毎フレーム描けるかの最小確認を兼ねる。
///
/// 設計の全体像は同じディレクトリの DESIGN.md を参照。
///
mod Game {

    /// このゲームのノード識別タグ。hello world では中身の状態を持たないので NoTag だけ。
    /// 本実装で自機・敵・弾などの状態を埋めるときにここを増やす。
    pub enum NodeTag with Eq {
        case NoTag
    }

    /// 設計解像度（project.json の designWidth/Height と一致させる）
    def designWi(): Int32 = 480
    def designHi(): Int32 = 270

    /// 起動エントリ。Main.flix から呼ばれる。
    /// hello world ではフェーズもカスタム effect も無く、描画ループを回すだけなので
    /// 必要な能力は GameEngine.Game（描画・入力・終了判定）だけで済む。
    pub def start(fontAtlas: FontAtlas): Unit \ GameEngine.Game =
        gameLoop(buildScene(fontAtlas))

    /// 表示するシーンを 1 度だけ組み立てる。
    /// Scene は不変な値なので、ここで作ったツリーをそのまま毎フレーム描く。
    def buildScene(fontAtlas: FontAtlas): Scene[NodeTag] =
        // 背景（design 解像度いっぱいの矩形）。一番奥に置く。
        let bg =
            ColorRect.make(
                {x = Int32.toFloat64(designWi()), y = Int32.toFloat64(designHi())},
                {r = 0.07f32, g = 0.08f32, b = 0.12f32}
            ) |> CanvasItem.setZIndex(-100);

        // 自機 = 塗りつぶした円盤（width = radius で内半径 0 = 中身まで塗る）。画面中央。
        let playerRadius = 12.0;
        let player =
            Arc2D.make(playerRadius, playerRadius, 0.0, Arc2D.tau(),
                       {r = 0.45f32, g = 0.85f32, b = 1.0f32})
            |> Node2D.setPosition({x = 240.0, y = 150.0});

        // タイトル文字（SDF フォント）。上部に表示。
        let title =
            Label2D.make("Shape Survivors", fontAtlas, 28.0)
            |> Node2D.setPosition({x = 120.0, y = 36.0});

        Scene.empty()
            |> Scene.addNode("background", EngineNode.ColorRectWithState(bg, NodeTag.NoTag))
            |> Scene.addNode("player", EngineNode.Arc2DWithState(player, NodeTag.NoTag))
            |> Scene.addNode("title", EngineNode.Label2DWithState(title, NodeTag.NoTag))

    /// メインループ：終了判定 → 描画 → 末尾再帰。
    /// hello world なので更新（process / handleInput）は無く、同じシーンを描き続ける。
    def gameLoop(scene: Scene[NodeTag]): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape))
            ()
        else {
            GameEngine.render(scene);
            gameLoop(scene)
        }
}
