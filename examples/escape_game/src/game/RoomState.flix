/// 現在の部屋 ID と、その部屋にあるホットスポットの状態（ロック / 表示）を保持する。
///
/// 設計意図:
///   - 状態は `Game.RoomState.Access` effect 経由で読み書きする。実体は region 内
///     `Ref[RoomId, r]` + `MutMap[HotspotId, HotspotState, r]` の組で、`Game.start` の
///     handler が握る（`Game.ShakeState` と同じ流儀）
///   - Yarn 側は副作用コマンド `<<room enter <id>>>` `<<hotspot lock/unlock/show/hide <id>>>`
///     で書き換え、ビルトイン `current_room()` `is_locked(id)` で問い合わせる
///   - ホットスポットの「定義」（座標・ヒット範囲・初期ロック）は `Game.RoomCatalog` が
///     静的に持つ。本モジュールはあくまで「現フレームの状態」だけを保つ
///   - 部屋切替時 (`enter`) は `MutMap.clear` + `MutMap.putAll` でテーブルを再構築する
///   - 外部に渡す `Snapshot` は immutable Map を含む値型で、save/load や view が
///     mutable を直接触らないように `MutMap.toMap` で 1 段コピーする
mod Game.RoomState {

    /// 部屋 id（`RoomCatalog` の id と一致する想定）。
    pub type alias RoomId = String

    /// ホットスポット id（`<<hotspot lock chest>>` の `chest` のような短い識別子）。
    pub type alias HotspotId = String

    /// 1 ホットスポット分の状態。
    pub type alias HotspotState = { locked = Bool, visible = Bool }

    /// ホットスポット状態テーブル（外部 API 用、immutable）。
    pub type alias HotspotTable = Map[HotspotId, HotspotState]

    /// 外部に渡す部屋状態の瞬時値。view / save 用の immutable コピー。
    /// `roomId` 空文字 `""` は「未入場」を表す。
    pub type alias Snapshot = {
        roomId   = RoomId,
        hotspots = HotspotTable
    }

    /// 部屋とホットスポットの状態操作。実体は `Game.start` の handler で
    /// region 内 mutable に閉じ込めて注入する。
    pub eff Access {
        /// 現在のスナップショットを取得する（`MutMap.toMap` で 1 段コピー）。
        def snapshot(): Snapshot

        /// 部屋を切り替える。`hotspots` は新しい部屋の初期状態（catalog から作る想定）。
        /// 既存テーブルは clear して、新しいエントリだけ残す。
        def enter(roomId: RoomId, hotspots: HotspotTable): Unit

        /// ホットスポットのロック状態を更新する。未登録の id は何もしない。
        def setLocked(hotspotId: HotspotId, locked: Bool): Unit

        /// ホットスポットの表示状態を更新する。未登録の id は何もしない。
        def setVisible(hotspotId: HotspotId, visible: Bool): Unit
    }

    /// `Game.ShakeState.withState` と同じ流儀の handler 注入。
    /// `roomIdRef` (Ref) と `hotspotsMap` (MutMap) は内部 closure に閉じ込められ、
    /// 呼び出し側からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Access) + r =
        thunk -> {
            let roomIdRef: Ref[RoomId, r] = Ref.fresh(rc, "");
            let hotspotsMap: MutMap[HotspotId, HotspotState, r] = MutMap.empty(rc);
            run thunk() with handler Access {
                def snapshot(k)              = k(snapshotOf(roomIdRef, hotspotsMap))
                def enter(id, hs, k)         = { enterMut(id, hs, roomIdRef, hotspotsMap); k() }
                def setLocked(id, locked, k) = { updateHotspot(id, s -> withLocked(locked, s), hotspotsMap); k() }
                def setVisible(id, vis, k)   = { updateHotspot(id, s -> withVisible(vis, s), hotspotsMap); k() }
            }
        }

    /// 内部 mutable 状態から immutable Snapshot を作る。
    /// `MutMap.toMap` で hotspots を 1 度コピーする。
    def snapshotOf(roomIdRef: Ref[RoomId, r],
                    hotspotsMap: MutMap[HotspotId, HotspotState, r]):
                    Snapshot \ r =
        ({roomId = Ref.get(roomIdRef), hotspots = MutMap.toMap(hotspotsMap)}: Snapshot)

    /// 部屋切替: roomId を上書きし、hotspots テーブルを clear した上で
    /// 新しいエントリを put し直す。
    def enterMut(roomId: RoomId, hotspots: HotspotTable,
                  roomIdRef: Ref[RoomId, r],
                  hotspotsMap: MutMap[HotspotId, HotspotState, r]): Unit \ r =
        Ref.put(roomId, roomIdRef);
        MutMap.clear(hotspotsMap);
        Map.forEach((id, state) -> MutMap.put(id, state, hotspotsMap), hotspots)

    /// 既存ホットスポット 1 件に変換 `f` を適用する。未登録 id は no-op。
    /// `setLocked` / `setVisible` の共通 boilerplate を 1 か所に集約する。
    def updateHotspot(hotspotId: HotspotId,
                       f: HotspotState -> HotspotState,
                       hotspotsMap: MutMap[HotspotId, HotspotState, r]): Unit \ r =
        match MutMap.get(hotspotId, hotspotsMap) {
            case None       => ()
            case Some(prev) => MutMap.put(hotspotId, f(prev), hotspotsMap)
        }

    /// `locked` を差し替えた新しい HotspotState を返す純粋関数。
    def withLocked(locked: Bool, prev: HotspotState): HotspotState =
        ({locked = locked, visible = prev#visible}: HotspotState)

    /// `visible` を差し替えた新しい HotspotState を返す純粋関数。
    def withVisible(visible: Bool, prev: HotspotState): HotspotState =
        ({locked = prev#locked, visible = visible}: HotspotState)

    // ════════════════════════════════════════════════════════════════════════
    // 公開ヘルパー（Snapshot を読む派生クエリ）
    // ════════════════════════════════════════════════════════════════════════

    /// 現在の部屋 id。未入場時は空文字 `""`。
    pub def currentRoom(): RoomId \ Access =
        Access.snapshot()#roomId

    /// 指定ホットスポットがロック中か。未登録は false（= 触れる前提）。
    pub def isLocked(hotspotId: HotspotId): Bool \ Access =
        Access.snapshot()#hotspots
            |> Map.get(hotspotId)
            |> Option.map(s -> s#locked)
            |> Option.getWithDefault(false)

    /// 指定ホットスポットが表示中か。未登録は false。
    pub def isVisible(hotspotId: HotspotId): Bool \ Access =
        Access.snapshot()#hotspots
            |> Map.get(hotspotId)
            |> Option.map(s -> s#visible)
            |> Option.getWithDefault(false)
}
