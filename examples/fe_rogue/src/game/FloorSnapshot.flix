/// FloorSnapshot — フロアの状態を「カタログ id ＋ 動的値」だけで表す純粋データ。
///
/// 全滅時の「そのフロアの最初から」復元と、将来の中断機能（JSON セーブ）が共有する土台。
/// resource 実体・GPU ハンドル・関数を一切含まないため、そのまま JSON 化（`Saveable`）でき、
/// `Scene.empty()` から決定論的に再構築できる（マップは `DungeonGenerator.Plan` を
/// `composeFromSideConnections` に渡して乱数なしで再現）。
///
/// 進入時スナップショット（リスタート用）では動的値は「進入時の値」（敵=full hp・default、
/// 味方=carry 反映後の HP/durability）。型は現在状態も表現できるので、中断保存では現在値を入れる。
mod FloorSnapshot {

    // 武器 / 杖 / 消費の持ち物は `{id = String, durability = Int32}`（id はカタログ id、durability は
    // 実行時の残り耐久）で表す。型エイリアスにすると別モジュールの推論で構造型と unify しない癖が出るため
    // 各所でインラインに展開して書く。

    /// 味方 1 体のスナップショット。`classId` は UnitCatalog のクラス id（resource は復元時に lookup）。
    /// 注: `facing` / `statuses` は**現在状態（中断保存）用に保持**するフィールドで、リスタート復元
    /// （進入時 = facing 既定 / statuses 空）では消費しない。中断ロード実装時に復元側で読む想定。
    pub type alias PlayerSnap = {
        id           = Int32,
        classId      = String,
        gridPos      = {x = Int32, y = Int32},
        hp           = Int32,
        level        = Int32,
        exp          = Int32,
        // 成長後の 6 ステータス（最大 HP 含む）。レベルアップは成長率乱数なので level から再計算できず、
        // 値を保存する（`PlayerScene.CarryData#stats` と同じ役割）。復元時 base resource に上書きする。
        stats        = LevelSystem.Stats,
        facing       = Staff.Direction,
        statuses     = List[StatusSystem.Status],
        weapons      = List[{id = String, durability = Int32}],
        staves       = List[{id = String, durability = Int32}],
        consumables  = List[{id = String, durability = Int32}],
        rings        = List[String],   // 指輪 id のリスト（先頭が装備候補）
        ringEquipped = Bool
    }

    /// 敵 1 体のスナップショット。`resourceId` は EnemyCatalog の id（resource は復元時に lookup）。
    /// `weapon` は装備中武器（id ＋ 残り耐久、壊れて無ければ None）。`ring` は装備指輪 id（多くは None）。
    /// 注: `hp` / `statuses` / `alerted` は**現在状態（中断保存）用**。リスタート復元は full HP・既定状態で
    /// 再配置するため消費しない（中断ロード実装時に復元側で読む想定）。
    pub type alias EnemySnap = {
        id         = Int32,
        resourceId = String,
        gridPos    = {x = Int32, y = Int32},
        hp         = Int32,
        moduleIdx  = Int32,
        weapon     = Option[{id = String, durability = Int32}],
        ring       = Option[String],
        statuses   = List[StatusSystem.Status],
        alerted    = Bool
    }

    /// 床に落ちているアイテム 1 個（種別 id ＋ セル座標）。
    pub type alias ItemSnap = { gridPos = {x = Int32, y = Int32}, itemKey = String }

    /// 宝箱 1 個（箱種別 id ＋ 中身アイテム id ＋ セル座標）。
    pub type alias ChestSnap = {
        gridPos   = {x = Int32, y = Int32},
        chestKey  = String,
        contentId = String
    }

    /// フロア全体のスナップショット。
    pub type alias T = {
        floorId  = String,
        mapPlan  = DungeonGenerator.Plan,
        players  = List[PlayerSnap],
        enemies  = List[EnemySnap],
        items    = List[ItemSnap],
        chests   = List[ChestSnap],
        stairs   = Option[{x = Int32, y = Int32}]
    }

    /// 進入時スナップショットの保持 effect（`InitialSpawns` と同じ handler 注入パターン）。
    /// 全滅時の「そのフロアの最初から」で読み出す。初期値 `None`（フロア進入で `put` される）。
    pub eff State {
        /// 保存済みスナップショットを返す（未保存なら `None`）。
        def get(): Option[T]
        /// 進入時スナップショットを上書き保存する。
        def put(snapshot: T): Unit
    }

    /// Ref を closure に閉じ込めた handler 注入。`Game.start` で 1 度巻く。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let snapshotRef: Ref[Option[T], r] = Ref.fresh(rc, None);
            run {
                thunk()
            } with handler State {
                def get(k)           = k(Ref.get(snapshotRef))
                def put(snapshot, k) = { Ref.put(Some(snapshot), snapshotRef); k() }
            }
        }
}
