// community-build 用のダミーアプリ。engine_core + render_core + engine を include し、
// window を構築するだけ。main は 1 つだけなので examples/ide のような複数 main 衝突が
// 起きない。community-build は `flix build`(コンパイルのみ) で実行はしないため、
// ヘッドレス環境でも GLFW window は実際には開かれない。
// (LwjglLayer.withLwjgl が GLFW window 生成 + render_core シェーダ/VAO 構築を行うので、
//  engine_core/render_core/engine の到達コードが型検査 + codegen まで通る。)
def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            designWidth = 170,
            designHeight = 128,
            windowWidth = 680,
            windowHeight = 512,
            title = "community-build smoke",
            textureManifest = Nil,
            fontManifest = Nil,
            soundManifest = Nil,
            clearColor = { r = 0.0f32, g = 0.0f32, b = 0.0f32 },
            maxDeltaTime = 0.1
        };
        LwjglLayer.withLwjgl(config, () -> ())
    }
