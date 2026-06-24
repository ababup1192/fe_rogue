// Breakout — ノードタグ定義・trait instance・シーン構築・ゲームループ
//
// 足場段階（Step 0）:
//   - シーンはまだ空（Scene.empty()）。壁・パドル・ボール・ブロックは IDE 上で配置していく。
//   - NodeTag / Node instance は最小。ノードを置き始めたら役割タグと dispatch を足す。
//   - gameLoop は process → render の固定パイプラインのみ。物理・入力・衝突は配置後に追加する。

// ========================================================================
// ノードタグ
// ========================================================================

/// 各ノードに付与する識別タグ（Scene[NodeTag] の型パラメータ）。
/// 配置を進めるにつれ Wall / Paddle / Ball / Block などの役割タグを足していく。
pub enum NodeTag with Eq, ToString {
    case NoTag
}

// ========================================================================
// Node 実装（各シーンの process にディスパッチするだけ）
// ========================================================================

instance Node[NodeTag] {
    type Aef = {}
    type ProcessAef = {}
    // 足場段階ではライフサイクル処理なし。配置後に redef process などを足す。
}

// ========================================================================
// mod Game
// ========================================================================

mod Game {

    // ── 画面サイズ（project.json と一致させる） ──

    pub def designWi(): Int32 = 320
    pub def designHi(): Int32 = 240

    // ── シーン構築 ──
    // 足場段階では空。IDE で作ったシーンを SceneLoader.loadScene で繋ぐようになったら
    // ここをパイプで組み立てる。

    pub def buildScene(): Scene[NodeTag] = Scene.empty()

    // ── start / gameLoop ──

    pub def start(_fontAtlas: FontAtlas):
                  Unit \ GameEngine.Game =
        gameLoop(buildScene())

    /// gameLoop は engine のパイプラインを順に呼ぶだけ。
    def gameLoop(scene: Scene[NodeTag]): Unit \ {GameEngine.Game} =
        if (GameEngine.Game.shouldClose()) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updated = scene
                |> GameEngine.process(delta = dt, paused = false);
            GameEngine.render(updated);
            gameLoop(updated)
        }
}
