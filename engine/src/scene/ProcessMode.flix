/// ノードのポーズ制御モード。
/// ゲームがポーズ状態のとき、各ノードを更新するかどうかを決定する。
///
/// 使用例:
///   - 敵・プレイヤー → Pausable（ポーズで止まる）
///   - ポーズメニュー UI → WhenPaused（ポーズ中だけ動く）
///   - BGM コントローラー → Always（常に動作）
///   - 一時無効化したいノード → Disabled
pub enum ProcessMode with Eq, Order, ToString {
    case Pausable       // ポーズ中は停止、通常時は動作（デフォルト）
    case WhenPaused     // ポーズ中のみ動作（ポーズメニュー等）
    case Always         // ポーズに関係なく常に動作
    case Disabled       // 常に停止（一時的な無効化に使う）
}

pub mod ProcessMode {
    /// paused 状態と mode の組み合わせから、ノードの process を実行すべきか判定する。
    /// Scene.processAll から各ノードごとに呼ばれる。
    pub def shouldProcess(paused: Bool, mode: ProcessMode): Bool =
        match mode {
            case ProcessMode.Disabled   => false
            case ProcessMode.Always     => true
            case ProcessMode.Pausable   => not paused
            case ProcessMode.WhenPaused => paused
        }
}
