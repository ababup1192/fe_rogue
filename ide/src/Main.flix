// ide/src/Main.flix — Step C.1: SwingLayer.withSwing 経由で render_core 初期化
//
// 動作確認:
//   cd ide && ./bin/flix run
// 期待:
//   - JFrame タイトルが "flix_game_engine IDE — Step C.1"
//   - clearColor (青系) でクリアされた canvas
//   - stdout に [SwingLayer] initGL / Loading textures / Baking font atlases / render_core ready
//   - × クリックで終了
//
// 検証ポイント:
//   - SwingLayer.withSwing が GameEngine.Game / GameEngine.Audio handler を提供できる
//   - render_core の shader/texture/font 初期化が initGL コンテキスト下で動く
//   - paintGL から renderFrameMixed (sprites = [], tileMaps = []) が呼べる
//   - f() は shouldClose まで何もしないだけのループ

def main(): Unit \ IO =
    let config: GameEngine.EngineConfig = {
        designWidth     = 480,
        designHeight    = 720,
        windowWidth     = 480,
        windowHeight    = 720,
        title           = "flix_game_engine IDE — Step C.1",
        textureManifest = Nil,
        fontManifest    = Nil,
        soundManifest   = Nil,
        clearColor      = {r = 0.219608f32, g = 0.372549f32, b = 0.380392f32},
        maxDeltaTime    = 0.05
    };
    run {
        idleLoop()
    } with SwingLayer.withSwing(config)

// shouldClose になるまで何もせずに待つだけのループ。
// (実際のシーン描画は Step C.2 で追加)
def idleLoop(): Unit \ GameEngine.Game =
    if (GameEngine.Game.shouldClose()) ()
    else {
        // 何もコマンドを送らないと paintGL は clearColor のみ描画する
        GameEngine.Game.renderCommands(Nil, Nil);
        idleLoop()
    }
