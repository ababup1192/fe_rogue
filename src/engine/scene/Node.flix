/// シーンツリーの基本ノード（Godot Node 準拠）
/// see: https://docs.godotengine.org/en/stable/classes/class_node.html
///
/// ライフサイクル:
///   addNode → ready()
///     → [毎フレーム] process(delta)
///     → [物理ステップ] physicsProcess(delta) → 重力・積分
///
/// 全メソッドにデフォルト実装があり、必要なものだけオーバーライドすればよい。
/// 型パラメータ s はゲーム固有の状態を表す。
/// EngineNode[s] がエンジンノードとゲーム状態を一体で保持する。
///
/// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
/// 例: `type Aef = { Math.Random }` や `type Aef = {}` （純粋）
pub trait Node[s] {

    /// ライフサイクルコールバックで発生するエフェクト
    type Aef: Eff

    // ── ライフサイクル ──

    /// ノードがシーンツリーに追加された後、最初に一度だけ呼ばれる初期化コールバック
    pub def ready(node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.Aef[s] =
            checked_ecast((node, scene))

    /// 毎フレーム呼ばれる更新コールバック
    /// delta: 前フレームからの経過秒数（Float64）
    pub def process(_delta: Float64, node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.Aef[s] =
            checked_ecast((node, scene))

    /// 物理ステップ中に呼ばれる更新コールバック（Godot _physics_process 準拠）
    /// PhysicsStep.step の重力・積分の **前** に呼ばれる。
    /// 力の適用・速度の変更など、物理演算に影響する処理をここに書く。
    pub def physicsProcess(_delta: Float64, node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.Aef[s] =
            checked_ecast((node, scene))

    // ── タイムアウト検出 ──

    /// timeout イベントが保留中か
    pub def isTimedOut(_state: s): Bool = false

    /// timeout フラグをクリア
    pub def clearTimedOut(state: s): s = state

    // ── ポーズ制御 ──

    /// このノードの ProcessMode を返す（デフォルト: Pausable）
    /// Scene.processAll がポーズ中に呼ぶかどうかの判定に使われる
    pub def getProcessMode(_state: s): ProcessMode =
            ProcessMode.Pausable
}
