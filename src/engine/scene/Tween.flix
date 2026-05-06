/// Tween — Godot 4 流儀の補間アニメーション
///
/// Godot 4 の `Tween` (RefCounted、Node ではない) と同じ立ち位置：
///   - Node ではなく engine モジュール
///   - SceneTree が裏で advance（本実装では `tickAll` を gameLoop が 1 行で呼ぶ）
///   - target Node にバウンドされ、Node 削除で auto-stop
///   - 完了で auto-free（リストから自動除去）
///   - 同パス再登録は古い tween を置換（再利用不可）
///
/// 使い方:
///   `Game.start` で `with Tween.withScheduler(rc)` を 1 行注入し、
///   `gameLoop` の物理パイプライン末尾で `|> Tween.tickAll(dt)` を呼ぶ。
///   ゲームロジック側は `Tween.tweenPosition(...)` / `Tween.tweenAlpha(...)` で
///   tween をスケジュールするだけ。advance 等の internal は見えない。

mod Tween {

    /// 補間対象プロパティ。start と target を両方内包する形にして、
    /// Position / Alpha どちらも同じ Entry シェイプで扱えるようにする。
    /// 将来 Scale / Rotation / Color に拡張する場合もここにバリアントを追加する。
    pub enum Kind {
        /// (start world 座標, target world 座標)
        case Position(Vec2.Vec2, Vec2.Vec2)
        /// (start alpha, target alpha) — Sprite2D の alpha を補間する
        case Alpha(Float32, Float32)
    }

    /// 1 つのアクティブ tween。
    /// `elapsed` は開始からの経過時間、`duration` は完了までの目標時間。
    /// 進度は `Duration.ratio(elapsed, duration)` で 0.0..1.0 に丸められる。
    pub type alias Entry = {
        path     = NodePath,
        kind     = Kind,
        elapsed  = Duration.Duration,
        duration = Duration.Duration
    }

    /// `tickAll` が `consumeUpdates` から受け取り、scene に書き戻す中間表現。
    /// 値の種類は Kind と 1-to-1。
    pub enum UpdateValue {
        case PosVal(Vec2.Vec2)
        case AlphaVal(Float32)
    }

    pub type alias Update = {
        path  = NodePath,
        value = UpdateValue
    }

    /// effect op は Flix 上 1 引数なので Entry 1 つで scheduling する。
    /// user-facing は下の `tweenPosition` / `tweenAlpha` 関数（複数引数の便宜 wrapper）。
    /// `consumeUpdates` は `tickAll` だけが呼ぶ engine 内部用。
    pub eff Scheduler {
        /// 既存同パスを置換しつつ entry を登録
        def schedule(entry: Entry): Unit
        /// 進行中の tween があるか
        def isActive(targetPath: NodePath): Bool
        /// 進行中の tween をキャンセル
        def cancel(targetPath: NodePath): Unit
        /// engine 内部用: 全 entry を delta 進め、完了したものを除去して
        /// 「scene に書き戻すべき更新一覧」を返す
        def consumeUpdates(delta: Duration.Duration): List[Update]
    }

    /// Godot の `tween.tween_property(self, "position", to, duration)` 同等の便宜関数。
    /// `targetPath` のノードを `startPos` から `to` へ `duration` かけて lerp する。
    /// 同パスへの再登録は古い tween を置換。
    pub def tweenPosition(targetPath: NodePath, startPos: Vec2.Vec2,
                          to: Vec2.Vec2, duration: Duration.Duration): Unit \ Scheduler =
        Scheduler.schedule({
            path     = targetPath,
            kind     = Kind.Position(startPos, to),
            elapsed  = Duration.zero(),
            duration = duration
        })

    /// Sprite2D の alpha を `from` → `to` に `duration` かけて補間する。
    /// 対象 path は **Sprite2D ノード**を指すこと（Marker2D 親ではなく子の Sprite）。
    /// 同パスへの再登録は古い tween を置換。
    pub def tweenAlpha(targetPath: NodePath, fromAlpha: Float32,
                       toAlpha: Float32, duration: Duration.Duration): Unit \ Scheduler =
        Scheduler.schedule({
            path     = targetPath,
            kind     = Kind.Alpha(fromAlpha, toAlpha),
            elapsed  = Duration.zero(),
            duration = duration
        })

    /// `Editor.withState(rc)` と同じ流儀の handler 注入。
    /// `tweensRef` は内部 closure に閉じ込められ、`Game.flix` からは見えない。
    /// 戻り値型は polymorphic なので、テスト等で結果を直接取り出せる。
    pub def withScheduler(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Scheduler) + r =
        thunk -> {
            let tweensRef: Ref[List[Entry], r] = Ref.fresh(rc, Nil);
            run {
                thunk()
            } with handler Scheduler {
                def schedule(entry, k) = {
                    // 同パスの旧 tween を置き換え（Godot 4 流儀）
                    let filtered = Ref.get(tweensRef)
                        |> List.filter(e -> e#path != entry#path);
                    Ref.put(entry :: filtered, tweensRef);
                    k()
                }
                def isActive(targetPath, k) =
                    k(Ref.get(tweensRef) |> List.exists(e -> e#path == targetPath))
                def cancel(targetPath, k) = {
                    Ref.put(Ref.get(tweensRef)
                        |> List.filter(e -> e#path != targetPath), tweensRef);
                    k()
                }
                def consumeUpdates(delta, k) = {
                    let entries = Ref.get(tweensRef);
                    let (stillRunning, updates) = List.foldLeft((acc, e) -> {
                        let (running, ups) = acc;
                        let nextElapsed = Duration.add(e#elapsed, delta);
                        let t = Duration.ratio(nextElapsed, e#duration);
                        let value = match e#kind {
                            case Kind.Position(start, target) =>
                                UpdateValue.PosVal(Vec2.lerp(start, target, t))
                            case Kind.Alpha(start, target) =>
                                let s = Float32.toFloat64(start);
                                let g = Float32.toFloat64(target);
                                let v = s + (g - s) * t;
                                // Float64 → Float32: alpha は 0..1 範囲内なので
                                // tryToFloat32 は常に Some を返す。Java interop で
                                // 直接 narrow しても良いが、stdlib API を使うほうが安全。
                                let v32 = Float64.tryToFloat32(v)
                                    |> Option.getWithDefault(target);
                                UpdateValue.AlphaVal(v32)
                        };
                        let update: Update = {
                            path  = e#path,
                            value = value
                        };
                        if (t >= 1.0)
                            // 完了 → リストから除外、updates には含めて最終位置を反映
                            (running, update :: ups)
                        else
                            // 進行中 → elapsed を更新してリストに残す
                            ({elapsed = nextElapsed | e} :: running, update :: ups)
                    }, (Nil, Nil), entries);
                    Ref.put(stillRunning, tweensRef);
                    k(updates)
                }
            }
        }

    /// gameLoop が 1 行で呼ぶ per-frame advance。
    /// target Node が scene から消えていれば tween を auto-stop する（Godot の Node バインド相当）。
    pub def tickAll(delta: Duration.Duration, scene: Scene[s]): Scene[s] \ Scheduler =
        let updates = Scheduler.consumeUpdates(delta);
        List.foldLeft((sc, u) ->
            match Scene.getEngineNode(u#path, sc) {
                case None =>
                    // auto-stop: target Node が消えたので残った tween entry を破棄
                    Scheduler.cancel(u#path);
                    sc
                case Some(_) =>
                    match u#value {
                        case UpdateValue.PosVal(v) =>
                            Scene.setGlobalPositionAt(u#path, v, sc)
                        case UpdateValue.AlphaVal(a) =>
                            Scene.mapEngineNode(u#path,
                                n -> EngineNode.mapSprite2D(s -> Sprite2D.setAlpha(a, s), n),
                                sc)
                    }
            },
            scene, updates)
}
