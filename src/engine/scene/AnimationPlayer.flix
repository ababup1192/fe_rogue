/// AnimationPlayer — Godot 4 流儀のキーフレームベースアニメーション
///
/// Tween との違い:
///   - Tween は「A → B」を 1 行で書く一発補間。動的に target を計算するムーブ用途
///   - AnimationPlayer は「複数 keyframe / メソッドトラック / 完了通知」を持つ
///     宣言的アニメーション。攻撃モーションや死亡演出など、開始～完了～副作用が
///     1 つのまとまりとして名前を持って再利用される用途
///
/// データモデル:
///   - `Animation`: 名前付きの再生定義。`tracks`（プロパティ補間）と `methods`
///     （特定時刻に発火するイベント名）を束ねる
///   - `Track`: 補間先 NodePath + 補間種別（Position / Alpha）を keyframe 列で保持
///   - `Playback`: 再生インスタンス。`owner` NodePath をキーに「同 owner で 1 つ」
///     を保証する（Godot の AnimationPlayer は Node 1 つに 1 つ）
///
/// 副作用フロー:
///   - `play(target, anim)` で再生スケジュール
///   - `tickAll(dt, scene)` を gameLoop が毎フレーム呼び、scene にプロパティ更新を反映
///   - メソッド発火 / 完了は drain queue にバッファされ、`drainEvents()` で取り出す
///   - 呼び出し側（GameManager）が drainEvents の結果を見てゲームロジックを進める
///
/// 使い方の典型:
///   `Game.start` で `with AnimationPlayer.withScheduler(rc)` を 1 行注入し、
///   `gameLoop` 末尾で `|> AnimationPlayer.tickAll(dt)` を呼ぶ。
///   ゲームロジック側は `AnimationPlayer.play(targetPath, anim)` で再生開始するだけ。

mod AnimationPlayer {

    // ════════════════════════════════════════════════════════
    // (A) アニメーション定義
    // ════════════════════════════════════════════════════════

    /// Position track の 1 keyframe。`time` は **正規化** された [0, 1] の時刻
    /// （anim.length に対する割合）。
    pub type alias PosKey = { time = Float64, pos = Vec2.Vec2 }

    /// Alpha track の 1 keyframe。`time` は正規化済み [0, 1]。
    pub type alias AlphaKey = { time = Float64, alpha = Float32 }

    /// 補間プロパティ種別。Tween と違い複数 keyframe を持てるのが特徴。
    /// 攻撃モーションの「origin → target → origin」は Position keys 3 個で表現できる。
    pub enum Property {
        case Position(List[PosKey])
        case Alpha(List[AlphaKey])
    }

    /// 1 つのプロパティトラック。`target` は補間先 NodePath、`prop` が補間内容。
    /// Position track のターゲットは Marker2D 等（global 位置を更新）、
    /// Alpha track のターゲットは Sprite2D（alpha を更新）。
    pub type alias Track = { target = NodePath, prop = Property }

    /// メソッドトラックの 1 イベント。`time` は anim 内の絶対時間。
    /// `name` はゲーム側で解釈する識別子（例: "attack:hit"）。
    pub type alias MethodKey = { time = Duration.Duration, name = String }

    /// 1 つのアニメーション定義（Godot Animation リソース相当）。
    /// 同じ Animation インスタンスを複数 owner で並列再生して良い（イミュータブル）。
    pub type alias Animation = {
        name    = String,
        length  = Duration.Duration,
        tracks  = List[Track],
        methods = List[MethodKey]
    }

    /// 再生中インスタンス。`owner` は同時再生の単位（典型的に被アニメーションノードの NodePath）。
    /// 同じ owner で `play` を呼ぶと旧 playback は破棄される（Godot AnimationPlayer の挙動）。
    /// `firedMethods` は重複発火を防ぐための「発火済みメソッド名」キャッシュ。
    pub type alias Playback = {
        owner        = NodePath,
        anim         = Animation,
        elapsed      = Duration.Duration,
        firedMethods = List[String]
    }

    // ════════════════════════════════════════════════════════
    // (B) Tick / Event の中間表現
    // ════════════════════════════════════════════════════════

    /// `consumeTick` から `tickAll` への中間値。フレーム時点でのプロパティ更新一覧。
    pub enum UpdateValue {
        case PosVal(Vec2.Vec2)
        case AlphaVal(Float32)
    }

    pub type alias PropertyUpdate = { target = NodePath, value = UpdateValue }
    pub type alias Tick = { propertyUpdates = List[PropertyUpdate] }

    /// メソッド発火 / 完了通知の 1 イベント。
    /// `name` は method イベントなら MethodKey#name、finished イベントなら anim.name。
    pub type alias Event = { owner = NodePath, name = String }

    /// `drainEvents` の戻り値。次に GameManager がディスパッチする 2 種類のイベント。
    pub type alias EventBundle = {
        methods  = List[Event],
        finished = List[Event]
    }

    // ════════════════════════════════════════════════════════
    // (C) Scheduler effect — handler が Ref に状態を閉じ込める
    // ════════════════════════════════════════════════════════

    pub eff Scheduler {
        /// `Playback` を登録する（既存同 owner は置換）。
        /// user-facing は下の `play` 関数を使うと便利。
        def schedule(playback: Playback): Unit
        /// 指定 owner の playback があるか
        def isPlaying(owner: NodePath): Bool
        /// 指定 owner の playback を即時停止する
        def stop(owner: NodePath): Unit
        /// 全 playback と未配送イベントを一括破棄する。
        /// 通常は `tickAll` の auto-stop で十分だが、ゲームオーバー等で
        /// 「次フレームを待たずに即時クリーンしたい」場合の保険として用意してある。
        def cancelAll(): Unit
        /// 現在再生中の全 playback の owner NodePath 一覧。
        /// `tickAll` の冒頭で「scene から消えた owner の playback を破棄する」auto-stop に使う。
        def activeOwners(): List[NodePath]
        /// engine 内部用: `tickAll` が呼ぶ。delta 進めて property 更新を返し、
        /// 完了 / メソッドイベントは内部 buffer に溜める。
        def consumeTick(delta: Duration.Duration): Tick
        /// 内部 buffer にたまった method / finished イベントを取り出してクリアする
        def drainEvents(): EventBundle
    }

    /// `play(targetPath, anim)` — Godot の `AnimationPlayer.play("name")` 同等の便宜関数。
    pub def play(target: NodePath, anim: Animation): Unit \ Scheduler =
        Scheduler.schedule({
            owner        = target,
            anim         = anim,
            elapsed      = Duration.zero(),
            firedMethods = Nil
        })

    // ════════════════════════════════════════════════════════
    // (D) 補間ヘルパ — keyframe 列から t (0..1) で値を引く
    // ════════════════════════════════════════════════════════

    /// keyframe 列を walk して t に対応する Position を線形補間する。
    /// 範囲外（t <= 先頭 / t >= 末尾）は端の値で clamp。
    /// 0 件なら fallback を返す。
    def lerpPos(t: Float64, keys: List[PosKey], fallback: Vec2.Vec2): Vec2.Vec2 =
        match keys {
            case Nil      => fallback
            case k :: Nil => k#pos
            case k1 :: k2 :: rest =>
                if (t <= k1#time) k1#pos
                else if (t >= k2#time) lerpPos(t, k2 :: rest, fallback)
                else
                    let span = k2#time - k1#time;
                    let local = if (span <= 0.0) 0.0 else (t - k1#time) / span;
                    Vec2.lerp(k1#pos, k2#pos, local)
        }

    /// keyframe 列から t に対応する Alpha (Float32) を線形補間する。
    def lerpAlpha(t: Float64, keys: List[AlphaKey], fallback: Float32): Float32 =
        match keys {
            case Nil      => fallback
            case k :: Nil => k#alpha
            case k1 :: k2 :: rest =>
                if (t <= k1#time) k1#alpha
                else if (t >= k2#time) lerpAlpha(t, k2 :: rest, fallback)
                else
                    let span = k2#time - k1#time;
                    let local = if (span <= 0.0) 0.0 else (t - k1#time) / span;
                    let s = Float32.toFloat64(k1#alpha);
                    let g = Float32.toFloat64(k2#alpha);
                    let v = s + (g - s) * local;
                    Float64.tryToFloat32(v) |> Option.getWithDefault(k2#alpha)
        }

    // ════════════════════════════════════════════════════════
    // (E) handler factory — 既存の `Tween.withScheduler` と同じ流儀
    // ════════════════════════════════════════════════════════

    /// `with AnimationPlayer.withScheduler(rc)` を Game.start の handler スタックに
    /// 1 行差すと、その下の thunk から `Scheduler` op が使える。内部 Ref は閉じ込められる。
    pub def withScheduler(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Scheduler) + r =
        thunk -> {
            let activeRef: Ref[List[Playback], r] = Ref.fresh(rc, Nil);
            let pendingRef: Ref[EventBundle, r] =
                Ref.fresh(rc, {methods = Nil, finished = Nil});
            run {
                thunk()
            } with handler Scheduler {
                def schedule(pb, k) = {
                    // 同 owner の旧 playback を破棄して新規を載せる
                    let filtered = Ref.get(activeRef)
                        |> List.filter(p -> p#owner != pb#owner);
                    Ref.put(pb :: filtered, activeRef);
                    k()
                }
                def stop(target, k) = {
                    Ref.put(Ref.get(activeRef)
                        |> List.filter(p -> p#owner != target), activeRef);
                    k()
                }
                def cancelAll(k) = {
                    Ref.put((Nil: List[Playback]), activeRef);
                    Ref.put(({methods = Nil, finished = Nil}: EventBundle), pendingRef);
                    k()
                }
                def isPlaying(target, k) =
                    k(Ref.get(activeRef) |> List.exists(p -> p#owner == target))
                def activeOwners(k) =
                    k(Ref.get(activeRef) |> List.map(p -> p#owner))
                def consumeTick(delta, k) = {
                    let pbs = Ref.get(activeRef);
                    let pending = Ref.get(pendingRef);
                    let folded = List.foldLeft(acc -> pb -> {
                        let (running, ups, methods, fins) = acc;
                        let nextElapsed = Duration.add(pb#elapsed, delta);
                        let lengthSec = Duration.toSeconds(pb#anim#length);
                        // 長さ 0 のアニメは即完了扱い（snag のような「タイマー専用」用途も
                        // 実際は length > 0 で使うが安全側に倒す）
                        let t = if (lengthSec <= 0.0) 1.0
                                else Float64.min(1.0,
                                    Duration.toSeconds(nextElapsed) / lengthSec);
                        // 各 track の現在値を property update に変換
                        let trackUpdates = pb#anim#tracks
                            |> List.map(track -> {
                                let value = match track#prop {
                                    case Property.Position(keys) =>
                                        UpdateValue.PosVal(lerpPos(t, keys, Vec2.zero()))
                                    case Property.Alpha(keys) =>
                                        UpdateValue.AlphaVal(lerpAlpha(t, keys, 1.0f32))
                                };
                                ({target = track#target, value = value}: PropertyUpdate)
                            });
                        // method 発火: time <= elapsed かつまだ未発火のものを拾う
                        let elapsedSec = Duration.toSeconds(nextElapsed);
                        let unfired = pb#anim#methods
                            |> List.filter(m ->
                                Duration.toSeconds(m#time) <= elapsedSec
                                and not (pb#firedMethods
                                         |> List.exists(n -> n == m#name)));
                        let firedNames = List.map(m -> m#name, unfired);
                        let methodEvents = unfired
                            |> List.map(m -> ({owner = pb#owner, name = m#name}: Event));
                        let finishedEvents =
                            if (t >= 1.0)
                                ({owner = pb#owner, name = pb#anim#name}: Event) :: Nil
                            else Nil;
                        if (t >= 1.0)
                            // 完了 → running から除外。プロパティ更新は最終値を 1 回反映する
                            (running,
                             List.append(ups, trackUpdates),
                             List.append(methods, methodEvents),
                             List.append(fins, finishedEvents))
                        else
                            // 進行中 → elapsed と firedMethods を更新して running に残す
                            ({elapsed      = nextElapsed,
                              firedMethods = List.append(pb#firedMethods, firedNames)
                              | pb} :: running,
                             List.append(ups, trackUpdates),
                             List.append(methods, methodEvents),
                             fins)
                    },
                    ((Nil: List[Playback]),
                     (Nil: List[PropertyUpdate]),
                     (Nil: List[Event]),
                     (Nil: List[Event])),
                    pbs);
                    let (stillRunning, propertyUpdates, newMethods, newFinished) = folded;
                    Ref.put(stillRunning, activeRef);
                    Ref.put(({
                        methods  = List.append(pending#methods, newMethods),
                        finished = List.append(pending#finished, newFinished)
                    }: EventBundle), pendingRef);
                    k(({propertyUpdates = propertyUpdates}: Tick))
                }
                def drainEvents(k) = {
                    let pending = Ref.get(pendingRef);
                    Ref.put(({methods = Nil, finished = Nil}: EventBundle), pendingRef);
                    k(pending)
                }
            }
        }

    // ════════════════════════════════════════════════════════
    // (F) per-frame advance — gameLoop が 1 行で呼ぶ
    // ════════════════════════════════════════════════════════

    /// `Tween.tickAll` と同じ立ち位置のフレームエントリ。
    /// 動作:
    ///   1. **auto-stop**: 再生中 playback の owner が scene 上に居なければ stop する。
    ///      ゲームオーバーリセット / ホットリロードでノードが破棄された後に
    ///      古い playback が次フレームで残骸となるのを防ぐ
    ///   2. プロパティ更新を scene に書き戻す
    ///   3. method / finished イベントは内部 buffer に溜まるので、呼び出し側
    ///      (GameManager) が `drainEvents` で取り出してゲームロジックを進める
    /// target ノードが scene から消えていれば、そのプロパティ更新は無視する
    /// （auto-stop で playback も同時に破棄されているはず）。
    pub def tickAll(delta: Duration.Duration, scene: Scene[s]): Scene[s] \ Scheduler =
        // 1. auto-stop: scene から消えた owner の playback を破棄
        let owners = Scheduler.activeOwners();
        List.forEach(o -> match Scene.getEngineNode(o, scene) {
            case None    => Scheduler.stop(o)
            case Some(_) => ()
        }, owners);
        // 2. tick 1 フレーム分: プロパティ更新は scene に書き戻し、
        //    method / finished は内部 buffer に溜める
        let tick = Scheduler.consumeTick(delta);
        List.foldLeft((sc, u) ->
            match Scene.getEngineNode(u#target, sc) {
                case None    => sc
                case Some(_) =>
                    match u#value {
                        case UpdateValue.PosVal(v) =>
                            Scene.setGlobalPositionAt(u#target, v, sc)
                        case UpdateValue.AlphaVal(a) =>
                            Scene.mapEngineNode(u#target,
                                n -> EngineNode.mapSprite2D(s -> Sprite2D.setAlpha(a, s), n),
                                sc)
                    }
            },
            scene, tick#propertyUpdates)
}
