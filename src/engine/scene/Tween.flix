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
///   ゲームロジック側は `Tween.tweenPosition(targetPath, start, to, duration)` で
///   tween をスケジュールするだけ。advance 等の internal は見えない。

mod Tween {

    /// 補間対象プロパティ。将来 Scale / Rotation / Color に拡張
    pub enum Kind {
        case Position(Vec2.Vec2)   // 目標 world 座標
    }

    /// 1 つのアクティブ tween。`startPos` は登録時にキャプチャしたロック値
    pub type alias Entry = {
        path     = NodePath,
        kind     = Kind,
        startPos = Vec2.Vec2,
        elapsed  = Float64,
        duration = Float64
    }

    /// `tickAll` が `consumeUpdates` から受け取り、scene に書き戻す中間表現
    pub type alias Update = {
        path         = NodePath,
        kind         = Kind,
        currentValue = Vec2.Vec2
    }

    /// effect op は Flix 上 1 引数なので Entry 1 つで scheduling する。
    /// user-facing は下の `tweenPosition` 関数（複数引数の便宜 wrapper）。
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
        def consumeUpdates(delta: Float64): List[Update]
    }

    /// Godot の `tween.tween_property(self, "position", to, duration)` 同等の便宜関数。
    /// `targetPath` のノードを `startPos` から `to` へ `duration` 秒かけて lerp する。
    /// 同パスへの再登録は古い tween を置換。
    pub def tweenPosition(targetPath: NodePath, startPos: Vec2.Vec2,
                          to: Vec2.Vec2, duration: Float64): Unit \ Scheduler =
        Scheduler.schedule({
            path     = targetPath,
            kind     = Kind.Position(to),
            startPos = startPos,
            elapsed  = 0.0,
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
                        let nextElapsed = e#elapsed + delta;
                        let t = Float64.min(1.0, nextElapsed / e#duration);
                        let cur = match e#kind {
                            case Kind.Position(target) => Vec2.lerp(e#startPos, target, t)
                        };
                        let update: Update = {
                            path         = e#path,
                            kind         = e#kind,
                            currentValue = cur
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
    pub def tickAll(delta: Float64, scene: Scene[s]): Scene[s] \ Scheduler =
        let updates = Scheduler.consumeUpdates(delta);
        List.foldLeft((sc, u) ->
            match Scene.getEngineNode(u#path, sc) {
                case None =>
                    // auto-stop: target Node が消えたので残った tween entry を破棄
                    Scheduler.cancel(u#path);
                    sc
                case Some(_) =>
                    match u#kind {
                        case Kind.Position(_) =>
                            Scene.setGlobalPositionAt(u#path, u#currentValue, sc)
                    }
            },
            scene, updates)
}
