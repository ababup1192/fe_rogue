/// CustomEffects — fe_rogue 固有のカスタム effect 集約
///
/// 複数 Scene を跨ぐ操作だが、Scene 内では emit するだけで完結したいケースを
/// effect として宣言する。実体 (handler) は `Game.start` で 1 か所に注入される。
///
/// engine-guide スキルの規約: handler は **1〜3 行で Scene の関数を呼ぶだけ**。
/// 条件判定・計算は emit 元の Scene が済ませる。
mod CustomEffects {

    /// ゲームオーバー時のフルリビルドを要求する。
    /// emit 元 (PlayerScene.removeDeadAndCheckGameOver) は「全員脱落」を検知したら
    /// `request(scene)` を呼び、新 scene を受け取る。
    /// handler は `GameManager.buildPlayingScene(catalog)` で起動時と同じ
    /// フルリビルドを行い、state 4 種 (EnemyTurn.Queue / TurnPhase / SelectedPlayer /
    /// InitialSpawns) を一斉に書き換える。
    /// `Math.Random` / `Fs.FileRead` / `IO` が必要なので start でしか handler 注入できない。
    pub eff GameOverRequest {
        def request(scene: Scene[NodeTag]): Scene[NodeTag]
    }
}
