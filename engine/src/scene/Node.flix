/// シーンツリーに並ぶノード共通のふるまい（初期化・毎フレーム更新・物理更新）を定めるトレイト。
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

    /// `ready` / `physicsProcess` で発生するエフェクト集合。
    /// 物理ステップは衝突・移動の小さな世界に閉じることが多いので、`Aef` は狭く保ち、
    /// `process` で広い世界 (AnimationPlayer signal の受信など) に触れる場合は
    /// 別途 `ProcessAef` で広い集合を宣言する。物理更新と毎フレーム更新が
    /// それぞれ独立に別のエフェクトを起こせるよう、集合を分けている。
    type Aef: Eff

    /// `process` で発生するエフェクト集合。`ProcessAef = Aef` (Aef と同集合) が
    /// デフォルト想定だが、associated type のデフォルト値で他 type を参照する記法が
    /// サポートされないため、各 instance で明示的に書く必要がある。
    type ProcessAef: Eff

    // ── ライフサイクル ──

    /// ノードがシーンツリーに追加された後、最初に一度だけ呼ばれる初期化コールバック
    pub def ready(node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.Aef[s] =
            checked_ecast((node, scene))

    /// 毎フレーム呼ばれる更新コールバック
    /// delta: 前フレームからの経過時間
    pub def process(_delta: Duration.Duration, node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.ProcessAef[s] =
            checked_ecast((node, scene))

    /// 物理ステップ中に呼ばれる更新コールバック。
    /// PhysicsStep.step の重力・積分の **前** に呼ばれる。
    /// 力の適用・速度の変更など、物理演算に影響する処理をここに書く。
    pub def physicsProcess(_delta: Duration.Duration, node: EngineNode[s], _path: NodePath, scene: Scene[s]): (EngineNode[s], Scene[s]) \ Node.Aef[s] =
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
