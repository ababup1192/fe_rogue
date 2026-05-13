/// `<<bgm play <name>>>` で再生中の BGM 名と、`<<bgm fade <sec>>>` で進行中の
/// 音量フェードを保持する。
///
/// 設計意図:
///   - 状態は `Game.AudioFader.Access` effect 経由で読み書きする。実体（region 内
///     Ref）は `Game.start` の handler が握り、ゲーム本体は Ref を知らない
///   - BGM は同時に 1 つだけ流れる前提（story.yarn の用例どおり）。`currentBgm`
///     が現在鳴っている論理名を保持する
///   - フェードは進行中のものが 1 つだけ。`fade` が `Some` のときに `tick` が
///     毎フレーム音量を補間して `setVolume` を発火する
///   - フェード完了で `stopAudio` を呼んで音を止め、`fade = None` に戻す
///   - `bgm play` は新しい音を流す際にフェードをキャンセルし、音量を 1.0 に
///     リセットする（前回の fade-out で 0 になった gain が残るのを防ぐ）
mod Game.AudioFader {
    use Duration.Duration

    /// 進行中フェード 1 件の状態。`elapsed` を `delta` ずつ進めて、
    /// `t = elapsed / duration` で `startVolume` → `endVolume` を線形補間する。
    pub type alias FadeProgress = {
        soundName = String,
        startVolume = Float32,
        endVolume = Float32,
        elapsed = Duration,
        duration = Duration
    }

    /// 現在の BGM 名と、進行中フェード（あれば）。
    pub type alias Snapshot = {
        currentBgm = Option[String],
        fade = Option[FadeProgress]
    }

    /// AudioFader 状態の読み書き。実体は `Game.start` の handler が region 内 Ref で持つ。
    pub eff Access {
        def get(): Snapshot
        def put(target: Snapshot): Unit
    }

    /// `Editor.withState(rc)` と同じ流儀の handler 注入。
    /// `faderRef` は内部 closure に閉じ込められ、呼び出し側からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Access) + r =
        thunk -> {
            let faderRef: Ref[Snapshot, r] = Ref.fresh(rc, emptySnapshot());
            run thunk() with handler Access {
                def get(k)    = k(Ref.get(faderRef))
                def put(s, k) = { Ref.put(s, faderRef); k() }
            }
        }

    /// BGM 未再生・フェードなしの初期状態。handler 初期化用に純粋値で返す。
    def emptySnapshot(): Snapshot =
        ({currentBgm = None, fade = None}: Snapshot)

    /// `bgm play <name>` から呼び出す。
    /// 別 BGM が鳴っていれば停止し、進行中フェードをキャンセル、currentBgm を上書き、
    /// 新しい BGM の音量を 1.0 にリセットする。
    /// 実際の `playAudio` 呼び出し（先頭から再生）は呼び出し側 (CommandRouter) の責務。
    /// ※ 同名 BGM の再指定の場合は stopAudio を呼ばない（CommandRouter 側で
    ///   playAudio が alSourceStop+Play して頭出しするので二度手間）
    pub def setBgm(name: String): Unit \ {Access, GameEngine.Audio} =
        let current = Access.get();
        match current#currentBgm {
            case Some(prev) if prev != name => GameEngine.Audio.stopAudio(prev)
            case _                          => ()
        };
        Access.put(({currentBgm = Some(name), fade = None}: Snapshot));
        GameEngine.Audio.setVolume(name, 1.0f32)

    /// `bgm fade <sec>` から呼び出す。currentBgm を 1.0 → 0.0 にフェードする。
    /// currentBgm が無ければ no-op（鳴っていない BGM はフェードのしようがない）。
    pub def fadeOutCurrent(duration: Duration): Unit \ Access =
        let current = Access.get();
        match current#currentBgm {
            case None => ()
            case Some(name) =>
                let progress: FadeProgress = {
                    soundName = name,
                    startVolume = 1.0f32,
                    endVolume = 0.0f32,
                    elapsed = Duration.zero(),
                    duration = duration
                };
                Access.put(({fade = Some(progress) | current}: Snapshot))
        }

    /// 1 フレーム進める：
    ///   - `fade = None` なら no-op
    ///   - 進行中なら elapsed を delta ぶん進めて、線形補間した音量を `setVolume`
    ///   - 完了タイミングで `stopAudio` を発火し、`fade = None` に戻す
    ///   - 完了時は `currentBgm` も `None` にする（フェードアウトしきった音は
    ///     「鳴っていない」扱い：次に `bgm play` が来るまで何も流さない）
    pub def tick(delta: Duration): Unit \ {Access, GameEngine.Audio} =
        let current = Access.get();
        match current#fade {
            case None => ()
            case Some(progress) =>
                let nextElapsed = Duration.add(progress#elapsed, delta);
                let t = Duration.ratio(nextElapsed, progress#duration);
                if (t >= 1.0) {
                    GameEngine.Audio.setVolume(progress#soundName, progress#endVolume);
                    GameEngine.Audio.stopAudio(progress#soundName);
                    Access.put(({currentBgm = None, fade = None}: Snapshot))
                } else {
                    let s = Float32.toFloat64(progress#startVolume);
                    let e = Float32.toFloat64(progress#endVolume);
                    let v = s + (e - s) * t;
                    let v32 = Float64.tryToFloat32(v)
                        |> Option.getWithDefault(progress#endVolume);
                    GameEngine.Audio.setVolume(progress#soundName, v32);
                    let updatedProgress = {elapsed = nextElapsed | progress};
                    Access.put(({fade = Some(updatedProgress) | current}: Snapshot))
                }
        }
}
