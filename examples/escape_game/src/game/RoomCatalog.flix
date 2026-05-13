/// 部屋メタデータの静的テーブル。
///
/// 設計意図:
///   - 部屋ごとの「背景テクスチャ名」と「初期ホットスポット状態 (locked/visible)」だけを
///     ここで管理する。ホットスポットの座標・サイズは `RoomScene.scene.json` に外出し
///     してエディタ (F1) で位置調整 → save → hot reload の経路に乗せる
///   - `RoomState.enter(id, hotspots)` を呼ぶときに渡す **初期 hotspot 状態テーブル** は
///     `initialHotspots(roomId)` で生成する
mod Game.RoomCatalog {
    use Game.RoomState.{RoomId, HotspotId, HotspotState, HotspotTable}

    /// 背景テクスチャ名（`bg_<name>` の `<name>` 部分）。
    pub type alias BgTexture = String

    /// ホットスポットの初期状態定義 (id と locked/visible のみ)。
    /// 座標・サイズは scene.json で持つ。
    pub type alias HotspotDef = {
        id                = HotspotId,
        initiallyLocked   = Bool,
        initiallyVisible  = Bool
    }

    /// 部屋 1 つの静的定義。
    pub type alias RoomDef = {
        id        = RoomId,
        bgTexture = BgTexture,
        hotspots  = List[HotspotDef]
    }

    /// 全部屋の id 一覧。`<<room enter <id>>>` のバリデーション用。
    pub def allRoomIds(): List[RoomId] =
        List.map(room -> room#id, allRooms())

    /// 全部屋の定義列。
    pub def allRooms(): List[RoomDef] =
        demoRoom() :: Nil

    /// id から部屋定義を引く。
    pub def find(roomId: RoomId): Option[RoomDef] =
        List.find(room -> room#id == roomId, allRooms())

    /// 部屋入場時に `RoomState.enter` に渡す初期 hotspot テーブルを作る。
    /// 未登録の roomId は空 Map を返す（`RoomState` 側で未登録 id への操作は no-op）。
    pub def initialHotspots(roomId: RoomId): HotspotTable =
        find(roomId)
            |> Option.map(room -> hotspotTableOf(room#hotspots))
            |> Option.getWithDefault(Map.empty())

    /// HotspotDef の List を初期 HotspotTable に畳み込む。
    def hotspotTableOf(defs: List[HotspotDef]): HotspotTable =
        List.foldLeft((acc, hs: HotspotDef) ->
            Map.insert(
                hs#id,
                ({locked = hs#initiallyLocked, visible = hs#initiallyVisible}: HotspotState),
                acc),
            Map.empty(),
            defs)

    // ════════════════════════════════════════════════════════════════════════
    // 静的データ
    // ════════════════════════════════════════════════════════════════════════

    /// デモ部屋 1。引き出し / 額縁 / 金庫 / ドア の 4 ホットスポット。
    /// - drawer : 金庫を示唆するヒントメモが入っている
    /// - painting: 壁の額縁。金庫の合言葉となる記号並びが書かれている
    /// - safe   : 3 記号錠つき金庫。開錠すると鍵が出る (`initiallyLocked = true`)
    /// - door   : 出口。鍵で開ける
    /// 座標・サイズは `RoomScene.scene.json` で定義。エディタで調整可。
    def demoRoom(): RoomDef = {
        id        = "demo_room",
        bgTexture = "demo_room",
        hotspots  =
            ({id = "drawer",
              initiallyLocked  = false,
              initiallyVisible = true}: HotspotDef) ::
            ({id = "painting",
              initiallyLocked  = false,
              initiallyVisible = true}: HotspotDef) ::
            ({id = "safe",
              initiallyLocked  = true,
              initiallyVisible = true}: HotspotDef) ::
            ({id = "door",
              initiallyLocked  = true,
              initiallyVisible = true}: HotspotDef) ::
            Nil
    }
}
