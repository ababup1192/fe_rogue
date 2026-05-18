// IdeGui — IDE シェル側の GUI 操作を抽象化する algebraic effect。
//
// Main の業務ロジック (reloadProject 等) は `IdeGui.Gui.X` を呼び、framework 名 (JavaFXIdeUI) を
// 直接参照しない。実装は handler 側で差し替え可能で、SwingIdeUI / WebIdeUI 等への
// 移植は handler の置き換えだけで済む。
//
// 設計方針:
//   - Engine 由来の effect (`GameEngine.Game` / `GameEngine.Audio`) と同じレイヤに位置付ける
//   - 呼び出しは fire-and-forget (戻り値は Unit)。FX thread への dispatch は handler 内で行う
//   - 業務上の意味で命名 (populateProjectTree / setTitle)。FX widget は handler 実装の詳細

mod IdeGui {
    /// IDE シェルへの GUI 命令。実装側は state を closure capture して該当 widget を更新する
    pub eff Gui {
        /// 現プロジェクトの scene 一覧と resource 一覧を view に反映する。
        /// reloadProject が project 切替後に呼ぶ
        def populateProjectTree(): Unit
        /// メインウィンドウのタイトルバー文字列を更新する
        def setTitle(title: String): Unit
    }
}
