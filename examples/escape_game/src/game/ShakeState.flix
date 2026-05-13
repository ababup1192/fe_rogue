/// `<<shake <sec>>>` 命令で発火する画面ゆれの残り時間／強度を保持する。
///
/// 設計意図:
///   - 状態は `Game.ShakeState.Access` effect 経由で読み書きする。`Game.start` の
///     handler が region 内 Ref に閉じ込めて注入し、ゲーム本体は Ref を知らない
///   - Yarn 側は同期コマンドとして「セット → submitCommandDone」だけ。
///     実際の表示効果は毎フレームの `tickAndApply` が WorldScene のレイヤ位置に
///     ランダムオフセットを書き込んで実現する
///   - 期限切れ時はオフセットを (0, 0) に戻して終了
mod Game.ShakeState {
    use Duration.Duration

    /// shake の現在状態。`remaining` が 0 でない間アクティブ。
    /// `intensity` は最大オフセット（design px）。
    pub type alias Snapshot = { remaining = Duration, intensity = Float64 }

    /// shake 状態の読み書き。実体（region 内 Ref）は `Game.start` で handler 注入する。
    pub eff Access {
        def get(): Snapshot
        def put(target: Snapshot): Unit
    }

    /// `Editor.withState(rc)` と同じ流儀の handler 注入。
    /// `shakeRef` は内部 closure に閉じ込められ、呼び出し側からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Access) + r =
        thunk -> {
            let shakeRef: Ref[Snapshot, r] = Ref.fresh(rc, emptySnapshot());
            run thunk() with handler Access {
                def get(k)    = k(Ref.get(shakeRef))
                def put(s, k) = { Ref.put(s, shakeRef); k() }
            }
        }

    /// アクティブでない初期状態。handler 初期化用に純粋値で返す。
    def emptySnapshot(): Snapshot =
        ({remaining = Duration.zero(), intensity = 0.0}: Snapshot)

    /// 新しい shake を開始する。既存の shake は上書き（より強い揺れに置き換え）。
    /// `intensity` は最大オフセットの絶対値（design px 単位、典型値は 2〜6 px）。
    pub def start(duration: Duration, intensity: Float64): Unit \ Access =
        Access.put(({remaining = duration, intensity = intensity}: Snapshot))

    /// 現在 shake 中なら true。
    pub def isActive(): Bool \ Access =
        not Duration.isExpired(Access.get()#remaining)

    /// 1 フレーム進める：
    ///   - アクティブなら remaining を delta だけ減らし、ランダムオフセットを WorldScene に注入
    ///   - 期限切れになったタイミングでオフセットを (0, 0) にリセット
    ///   - 元から非アクティブなら何もしない（毎フレーム no-op オフセット書き込みは避ける）
    pub def tickAndApply(delta: Duration, scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Access, Math.Random} =
        let current = Access.get();
        if (Duration.isExpired(current#remaining)) scene
        else {
            let nextRemaining = Duration.subClampedToZero(current#remaining, delta);
            Access.put(({remaining = nextRemaining, intensity = current#intensity}: Snapshot));
            if (Duration.isExpired(nextRemaining)) {
                // 期限切れ: オフセットを (0, 0) に戻して終了
                WorldScene.setShakeOffset({x = 0.0, y = 0.0}, scene)
            } else {
                // ランダムに ±intensity の範囲でオフセット
                let dx = RandomUtil.randomRange(-current#intensity, current#intensity);
                let dy = RandomUtil.randomRange(-current#intensity, current#intensity);
                WorldScene.setShakeOffset({x = dx, y = dy}, scene)
            }
        }
}
