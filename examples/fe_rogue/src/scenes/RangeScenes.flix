/// RangeScenes — マップ上のタイル群を半透明で可視化する範囲オーバーレイ群
///
/// 7 種の範囲（移動 / 移動攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険）のセル集合は
/// `RangeOverlayState` resource が権威で保持する。各 range mod は「セル計算」と「色・α 定数」と
/// 「resource の自フィールドへの put/get」だけを持ち、描画は `RenderWorld.renderRangeOverlays` が
/// cells から直描きする（`RangeOverlay.tileDrawables` の 1 経路に集約）。
///
/// 各 mod は `Scene[NodeTag]` を引数・戻り値に取るが、これは gameLoop / PhaseTransitions の
/// pipeline に合わせるためで、scene ツリー自体は変更しない（範囲の状態は resource に書く）。
/// EnemyRange / PlayerAttackRange / DangerZone のセル計算は地形（`MapScene.getMapLayer`）を
/// 読むため scene 引数を使う。

/// 範囲表示が共有する描画プリミティブ。セル計算 / 色・α は呼び出し側（各 range mod）の責任で、
/// この mod は「セル群を 45° 斜線ハッチ Panel の box Drawable に落とす」ことだけを担う。
///
/// 各セルは塗り（半透明）＋45° 斜線ハッチ＋枠線＋角丸の Panel で描く
/// （Godot StyleBoxFlat + 斜線シェーダ相当。画像テクスチャは使わない）。
/// 呼び出し側は「色相 color」と「強調度 alpha」だけ渡し、塗り/縞/枠の
/// 不透明度と縞色/枠色は本 mod が color から派生させる（CSS の
/// repeating-linear-gradient + border デザインを 26px タイルへ縮小したもの）。
mod RangeOverlay {

    /// 全 range 共通の zIndex。tilemap (= 0) より上、Player Sprite (= 10) より下。
    def tileZIndex(): Int32 = 1

    /// セル枠から内側に詰める余白 px（CSS の inset 相当。隣マスとの隙間になる）。
    def inset(): Float64 = 2.0

    /// 縞 1 本の幅 px と周期 px。周期を詰めて斜線の本数を増やす（細かいハッチ）。
    def stripeWidth(): Float64 = 1.0
    def stripePeriod(): Float64 = 2.0

    /// 色相を白方向へ `t` だけ寄せて明るくする（縞・枠用の明色を作る）。
    def lighten(c: Color, t: Float32): Color =
        {r = c#r + (1.0f32 - c#r) * t,
         g = c#g + (1.0f32 - c#g) * t,
         b = c#b + (1.0f32 - c#b) * t}

    /// 1 セル分のハッチ Panel（サイズ＋塗り/縞/枠、位置なし）。塗りは淡く床を見せ、色は斜線と枠で表現する
    /// （CSS の重み付けを踏襲）。World 描画（`tileDrawables`）が 1 セルの見た目を組むために使う。
    pub def tilePanel(color: Color, alpha: Float32): Panel =
        let side = MapSnapshot.tileSize() - inset() * 2.0;
        Panel.make(({x = side, y = side}: Vec2.Vec2), color)
            |> Panel.setBackgroundAlpha(alpha * 0.08f32)
            |> Panel.setBorderColor(lighten(color, 0.2f32))
            |> Panel.setBorderAlpha(alpha)
            |> Panel.setBorderWidth(0.5)
            |> Panel.setCornerRadius(2.0)
            |> Panel.setStripe(lighten(color, 0.5f32), alpha * 0.65f32, stripeWidth(), stripePeriod())
            |> CanvasItem.setZIndex(tileZIndex())

    /// セル中心を基準に Panel を置く左上座標（世界座標）。`tileDrawables` が使う。
    def tileTopLeft(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let half = (MapSnapshot.tileSize() - inset() * 2.0) / 2.0;
        let center = MapSnapshot.cellCenter(cell);
        {x = center#x - half, y = center#y - half}

    /// `cells` を camera 適用済みのハッチ box Drawable にする（World render System 用）。`Panel.toDrawables`
    /// で `tilePanel` と同一 styling を Drawable 化し、位置は `tileTopLeft` を camera 変換、scale（=Panel サイズ）を
    /// zoom 倍する（`RenderWorld.unitDraw` のスケール処理と対称）。
    pub def tileDrawables(cells: List[{x = Int32, y = Int32}], color: Color, alpha: Float32,
                          transform: Camera2D.ViewTransform): List[GameEngine.Drawable] =
        let panel = tilePanel(color, alpha);
        List.flatMap(cell -> {
            let screenTopLeft = Camera2D.applyToWorldPos(transform, tileTopLeft(cell));
            Panel.toDrawables(panel, screenTopLeft)
                |> Render.applyCameraScale(transform)
        }, cells)

}

/// MoveRangeScene — プレイヤーの「今ターン移動可能なマス」を青で可視化する
///
/// FE 風のターン制移動を提供する。選択中プレイヤーの位置から `Board.reachableForUnit`
/// で範囲を求め、`Board.stoppableForUnit` で味方マスを除いた青マスを描画する。
///
/// **ターン遷移**:
///   - `add` を初回・リロード時に 1 回呼んで現在位置から範囲を構築する。
///   - `Game.flix` の InputHandler が決定キー (Z / Space / Enter) のエッジを拾い、
///     `refresh` を呼ぶと 範囲を消して新しい原点で再構築する。
///   - 範囲は `MoveRangeScene.isInRange` 経由で `PlayerMovementDriver` から
///     参照され、移動先の許可判定に使われる (範囲外のマスへは踏み込めない)。
mod MoveRangeScene {

    /// 範囲データ。
    /// `reachable` は BFS で到達可能と判定されたセル一覧 (origin を含む)＝`isInRange` 用。
    /// `drawCells` は実際に青く描くセル (stoppable＝味方マスを除いた停止可能マス)＝World 描画が読む。
    pub type alias Data = {
        reachable = List[{x = Int32, y = Int32}],
        drawCells = List[{x = Int32, y = Int32}]
    }

    /// 移動範囲を識別する青系 modulate。Floor 装飾レイヤーの上で
    /// 移動可能マスとして識別しやすいように青寄りに着色する。World 描画も同値を使うため pub。
    pub def color(): Color = {r = 0.3f32, g = 0.5f32, b = 1.0f32}

    /// 移動可能マスをはっきり認識させるため完全不透明にする。
    /// 半透明にすると青が薄れて床と区別しにくくなる。
    pub def alpha(): Float32 = 1.0f32

    /// **選択中プレイヤー** の位置を origin に `Board.reachableForUnit` で範囲を求め resource に書く。
    /// 未選択 (PlayerCursor / EnemyTurn 等) なら何もしない（既存範囲は `refresh` が先に clear する）。
    /// `add` は `buildPlayingScene` の初回構築でも呼ばれる (`sceneRef` 更新前) ため、
    /// PartyQuery effect は使わず scene 引数を直接読む。`refresh` 経由のランタイム呼び出しでも
    /// 渡される scene は常に最新なので問題ない。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {SelectedPlayer.State, World.WorldQuery, RangeOverlayState.State} =
        match SelectedPlayer.State.get()#id {
            case None     => scene
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case None    => scene
                    case Some(_) => buildFor(id, scene)
                }
        }

    /// このターンの移動範囲の原点を選ぶ純粋関数。`MovedFrom` ドラフト（ターン開始位置）が
    /// あればそれを、無ければ現在位置を使う。これにより `refresh`（= clear + add + buildFor）が
    /// **冪等**になり、移動→メニュー→キャンセルでの無限移動を防ぐ（初回選択では origin == current
    /// なので従来と一致。移動後に再 refresh されても範囲はターン開始位置に固定される）。
    pub def chooseMoveOrigin(id: Int32, currentPos: {x = Int32, y = Int32},
                              drafts: List[MoveDraft.DraftAction]): {x = Int32, y = Int32} =
        MoveDraft.originOf(id, drafts) |> Option.getWithDefault(currentPos)

    /// 指定 id を起点に MoveRange を組み立てて resource に書く。
    /// **通行不可**: 壁 / 敵駒。**味方駒は通過可能** (1 マスとしてカウント)。「味方は素通り、ただし停止はできない」
    /// 表現。`Board.reachableForUnit` で到達範囲を出し、`stoppableForUnit` で味方マス
    /// (自分 + 他味方) を除いたものを青マスとして描画する。AutoMove も同じプリミティブで
    /// 動くため、ここで仕様が一致していれば自動で挙動が揃う。
    /// 原点は **現在位置でなくターン開始位置**（`chooseMoveOrigin` 経由）に固定する。
    def buildFor(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {SelectedPlayer.State, World.WorldQuery, RangeOverlayState.State} =
        // 盤面 pieces・現在位置とも World 由来（scene gridPos twin は退役＝stale）。
        let w0        = World.WorldQuery.get();
        let board     = World.toBoard(w0, scene);
        let drafts    = SelectedPlayer.State.get()#drafts;
        let origin    = chooseMoveOrigin(id,
            World.posOf(World.EntityRef.Player(id), w0)
                |> Option.getWithDefault(PlayerScene.getGridPos(id, scene)), drafts);
        let steps     = PlayerScene.getMoveTiles(id, scene);
        let cells     = Board.reachableForUnit(board, origin, steps);
        let drawCells = Board.stoppableForUnit(board, origin, steps);
        RangeOverlayState.State.put(
            {moveRange = Some({reachable = cells, drawCells = drawCells}) | RangeOverlayState.State.get()});
        scene

    /// 既存の MoveRange を消してから `add` で組み直す（未選択なら消えたまま）。
    pub def refresh(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {SelectedPlayer.State, World.WorldQuery, RangeOverlayState.State} =
        clear(scene) |> add

    /// 表示中の MoveRange があれば消す。PlayerAttack フェーズ移行時など、青マスを一時的に
    /// 消したいときに使う (`EnemyRangeScene.clear` と対称)。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({moveRange = None | RangeOverlayState.State.get()});
        scene

    /// 指定セルが「現在のターンで踏める」範囲内にあるか。
    /// MoveRange が未登録なら false を返す (ゲーム初期化前のフォールバック)。
    pub def isInRange(cell: {x = Int32, y = Int32}, _scene: Scene[NodeTag]): Bool \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#moveRange {
            case Some(data) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#reachable)
            case None => false
        }

    /// 現在範囲のセル一覧 (テスト・デバッグ用 + MoveAttackRangeScene が読む)。未登録なら空リスト。
    pub def reachable(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#moveRange {
            case Some(data) => data#reachable
            case None => Nil
        }

    /// World 描画が読む「青く描くセル」(stoppable)。未登録なら空リスト。
    pub def drawCells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#moveRange {
            case Some(data) => data#drawCells
            case None => Nil
        }
}


/// MoveAttackRangeScene — 「移動先のいずれかから攻撃が届くセル」を赤マスで可視化する
///
/// 目的: 移動先を決める前に「ここに動けばあそこの敵を攻撃できる」「ここに動くと
/// この敵の射程に入る」が一目で分かるようにする。Fire Emblem 風の脅威範囲表示。
///
/// 描画ルール:
///   - 表示中: `PlayerMoving` / `ActionSelect` フェーズ
///   - セル集合 = ⋃ {reachable のセル c から武器射程 (`min..max` マンハッタン) で
///                 届くセル} − reachable 自身
///     (= 「移動マスとは別のところ」だけ赤で出す。重なるなら青を優先)
///   - 武器なし / 射程ゼロなら何も描かない
///   - 地形フィルタはかけない (壁・床問わず射程を一貫表示)
///
/// **ライフサイクル**:
///   - `MoveRangeScene.refresh` の直後に `MoveAttackRangeScene.refresh` を呼ぶ
///     (reachable に依存するので、青マスを組み立てた後でないとデータが取れない)
///   - `MoveRangeScene.clear` の直後に `MoveAttackRangeScene.clear` を呼ぶ
mod MoveAttackRangeScene {

    /// reachable と重複しない「赤マスだけ」のセル一覧。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    /// PlayerAttackRangeScene / EnemyRangeScene と同じ赤系 modulate。World 描画も同値を使うため pub。
    pub def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// 青マス (MoveRange = 1.0) より透かすことで、移動範囲より外側の脅威範囲を
    /// 視覚的に奥の層として見せ、「動けるマス」と「そこから攻撃が届くマス」を階層化する。
    pub def alpha(): Float32 = 0.5f32

    /// 既存を消して再構築する。`MoveRangeScene` の青マスが既に build 済みの
    /// 前提で、その reachable を resource から読んで差集合を作る。
    pub def refresh(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, RangeOverlayState.State} =
        let cleared = clear(scene);
        match SelectedPlayer.State.get()#id {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.get(id, cleared) {
                    case None         => cleared
                    case Some(player) =>
                        match PlayerData.equippedWeapon(player#weapons) {
                            case None    => cleared
                            case Some(w) =>
                                let reachable = MoveRangeScene.reachable(cleared);
                                let lo = Int32.max(1, w#range#min);
                                let hi = w#range#max;
                                let cells = Board.computeThreatCells(reachable, lo, hi);
                                if (List.isEmpty(cells)) cleared
                                else {
                                    RangeOverlayState.State.put(
                                        {moveAttackRange = Some({cells = cells}) | RangeOverlayState.State.get()});
                                    cleared
                                }
                        }
                }
        }

    /// 表示中の MoveAttackRange があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({moveAttackRange = None | RangeOverlayState.State.get()});
        scene

    /// テスト・デバッグ用: 現在の脅威セル一覧。未登録なら空リスト。World 描画セルもこれ。
    pub def cells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#moveAttackRange {
            case Some(data) => data#cells
            case None => Nil
        }
}


/// EnemyRangeScene — カーソルが敵に乗っているとき、その敵の移動範囲を白色で可視化する
///
/// `MoveRangeScene` のミラー実装で、起点が「Player」ではなく「ホバー中の敵」になり、
/// 色が「青」ではなく「白」になる。FE 風の「敵情報を見ながらターン計画を立てる」フローを
/// 提供するための情報表示専用。
///
/// **ライフサイクル**:
///   - Cursor がフレーム間で乗っている敵 id が変わったとき、`refreshFor(id, scene)` で
///     消して新規構築する
///   - Cursor が敵以外に移ったとき、`clear(scene)` で消す
///   - 敵ターン開始時 / フェーズ切替で見せたくない場面でも `clear` を呼んで消す
mod EnemyRangeScene {

    /// `enemyId` は今表示している対象敵。`reachable` は BFS で到達可能と判定された
    /// セル一覧 (origin = 敵セルを含む)。
    pub type alias Data = {
        enemyId   = Int32,
        reachable = List[{x = Int32, y = Int32}]
    }

    /// 白系 modulate。敵の「移動範囲」を表す。攻撃到達範囲(EnemyAttackRange=赤)と
    /// 色で区別するため移動範囲は白にしている。
    pub def color(): Color = UITheme.white()

    /// 情報表示なので少し透かして駒や床を見やすくする。
    pub def alpha(): Float32 = 0.7f32

    /// 既存を消し、`enemyId` の敵に対応する範囲で構築し直す。敵が居なければ何もしない (`clear` 相当の保険)。
    /// 壁のみ通れない。味方マスや他敵マスも「想定移動範囲」として表示する
    /// (プレイヤーは「もし誰も居なければここまで来られる」を読む)。
    pub def refreshFor(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EnemyData.RosterQuery, RangeOverlayState.State} =
        match EnemyData.RosterQuery.get(enemyId) {
            case None       => clear(scene)
            case Some(data) =>
                let cleared = clear(scene);
                let layer   = MapScene.getMapLayer(cleared);
                let cells = Board.reachableCells(
                    c -> TileMapLayer.isFloor(c, layer),
                    data#gridPos,
                    data#moveTiles);
                RangeOverlayState.State.put(
                    {enemyRange = Some({enemyId = enemyId, reachable = cells}) | RangeOverlayState.State.get()});
                cleared
        }

    /// 表示中の EnemyRange があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({enemyRange = None | RangeOverlayState.State.get()});
        scene

    /// 現在表示している敵 id (出ていなければ None)。
    pub def currentEnemyId(_scene: Scene[NodeTag]): Option[Int32] \ RangeOverlayState.State =
        RangeOverlayState.State.get()#enemyRange |> Option.map(data -> data#enemyId)

    /// 現在の reachable セル一覧 (テスト・デバッグ用 + EnemyAttackRangeScene が読む)。未登録なら空リスト。
    pub def reachable(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#enemyRange {
            case Some(data) => data#reachable
            case None       => Nil
        }
}


/// EnemyAttackRangeScene — カーソルが敵に乗っているとき、その敵の「攻撃到達範囲（脅威範囲）」を
/// 赤色で可視化する。`MoveAttackRangeScene`(プレイヤーの脅威範囲) の敵版ミラー。
///
/// 脅威範囲 = ⋃ {敵の移動到達セル c から武器射程 (min..max マンハッタン) で届くセル} − 移動到達セル。
/// 移動到達セル自身は `EnemyRangeScene`(白) が描くので、ここでは「移動の外側で攻撃が届くセル」だけを
/// 赤で出す。
///
/// **ライフサイクル**:
///   - `EnemyRangeScene.refreshFor` の直後に `refreshFor` を呼ぶ
///     (敵移動到達セルを `EnemyRangeScene.reachable` から読むため、白マス構築後でないとデータが無い)
///   - 敵から離れたとき / 該当フェーズを抜けるときは `clear`
mod EnemyAttackRangeScene {

    /// `enemyId` は今表示している対象敵。`cells` は移動到達セルと重複しない「赤マスだけ」。
    pub type alias Data = {
        enemyId = Int32,
        cells   = List[{x = Int32, y = Int32}]
    }

    /// 赤系 modulate。EnemyRange(移動範囲=白) と区別する「攻撃到達」の色。
    pub def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// 移動範囲(白, alpha=0.7) と区別するため少し透かす。
    pub def alpha(): Float32 = 0.5f32

    /// 既存を消し、`enemyId` の敵の脅威範囲で構築し直す。
    /// `EnemyRangeScene` が直前に build した敵移動到達セルを resource から読み、武器射程で広げて差集合を作る。
    /// 敵が居ない / 武器なし / 脅威セルが空なら何も描かない。
    /// 「敵が居て武器を持つ」の 2 段の Option は forM で 1 段に畳み、空セル判定は
    /// `renderThreat` に寄せてネストを浅く保つ。
    pub def refreshFor(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EnemyData.RosterQuery, RangeOverlayState.State} =
        let cleared = clear(scene);
        let built = forM (
            data <- EnemyData.RosterQuery.get(enemyId);
            w    <- data#weapon
        ) yield renderThreat(enemyId, threatCells(w, cleared), cleared);
        Option.getWithDefault(cleared, built)

    /// 敵移動到達セル (EnemyRangeScene.reachable) を武器射程で広げた脅威セル。
    def threatCells(weapon: UnitCatalog.WeaponResource,
                     scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        let reachable = EnemyRangeScene.reachable(scene);
        Board.computeThreatCells(reachable, Int32.max(1, weapon#range#min), weapon#range#max)

    /// 脅威セルが空でなければ EnemyAttackRange を resource に敷く。空なら scene をそのまま返す。
    def renderThreat(enemyId: Int32, cells: List[{x = Int32, y = Int32}],
                      scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        if (List.isEmpty(cells)) scene
        else {
            RangeOverlayState.State.put(
                {enemyAttackRange = Some({enemyId = enemyId, cells = cells}) | RangeOverlayState.State.get()});
            scene
        }

    /// 表示中の EnemyAttackRange があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({enemyAttackRange = None | RangeOverlayState.State.get()});
        scene

    /// 現在の脅威セル一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#enemyAttackRange {
            case Some(data) => data#cells
            case None       => Nil
        }
}


/// PlayerAttackRangeScene — 攻撃フェーズ中に味方の射程を赤色で可視化する
///
/// `EnemyRangeScene` のミラー実装で、起点が「ホバー中の敵」ではなく「味方」になる。
/// 射程は装備中武器の `WeaponResource#range` から取る。range = 1 なら隣接 4 マス、
/// range = 2 なら十字に 2 マスずつ伸びる (くんれんゆみ等の間接攻撃)。
///
/// **ライフサイクル**:
///   - `PlayerMoving + Z` で `PlayerAttack` フェーズに入るとき `show(scene)` を呼んで
///     味方の現在位置を origin に赤マスを描く
///   - `PlayerAttack` を抜ける (敵ターンへ移行) ときは `clear(scene)` で消す
mod PlayerAttackRangeScene {

    /// `cells` は赤く描画されている射程内セル一覧 (origin = 味方セルは含まない)。
    /// `targetsInRange` の判定に使う。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    /// 赤系 modulate。EnemyRangeScene / MoveAttackRangeScene と同色。
    pub def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// EnemyRangeScene と同じく少し透かして駒や床を見やすくする。
    pub def alpha(): Float32 = 0.7f32

    /// 既存を消し、**選択中プレイヤー** の現在位置 origin に対して **インベントリ全武器の射程の和集合** で
    /// 赤マスを敷き直す。攻撃中はどの武器に持ち替えても届く敵にカーソルを乗せられるように、装備中(先頭)だけ
    /// でなく全武器の射程を合わせて表示する (重複セルは除去)。
    /// 未選択時は cleared を返す (赤マス表示なし)。
    /// 選択中プレイヤーの武器が壊れている (`weapons = Nil`) 場合は cells を空にして
    /// 表示だけ有効にする。これにより PlayerAttack フェーズに入ってもカーソルが
    /// 敵に乗らず、Z 押下で AttackHit が発火しない (X でスキップして抜ける)。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, World.WorldQuery, RangeOverlayState.State} =
        let cleared = clear(scene);
        match SelectedPlayer.State.get()#id {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.getWithWorldPos(id, cleared) {
                    case None    => cleared
                    case Some(d) =>
                        let layer = MapScene.getMapLayer(cleared);
                        let cells = unionWeaponCells(d#gridPos, d#weapons, layer);
                        RangeOverlayState.State.put(
                            {playerAttackRange = Some({cells = cells}) | RangeOverlayState.State.get()});
                        cleared
                }
        }

    /// インベントリ全武器の射程セルの和集合 (重複除去)。武器ごとに `computeAttackCells` で
    /// 菱形セルを出し、(x, y) タプルで dedup してから record に戻す。武器なしなら空。
    def unionWeaponCells(origin: {x = Int32, y = Int32},
                          weapons: List[UnitCatalog.WeaponResource],
                          layer: TileMapLayer): List[{x = Int32, y = Int32}] =
        weapons
            |> List.flatMap(w -> computeAttackCells(origin, w#range, layer))
            |> List.map(c -> (c#x, c#y))
            |> List.toSet
            |> Set.toList
            |> List.map(p -> match p { case (x, y) => {x = x, y = y} })

    /// 表示中の PlayerAttackRange があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({playerAttackRange = None | RangeOverlayState.State.get()});
        scene

    /// `show` から切り出して `unionWeaponCells` でも再利用できるようにした純粋関数。
    /// テスト時は scene や effect なしで直接呼び出せる。
    /// origin から **マンハッタン距離** `range#min..range#max` (inclusive) にある全セルを
    /// 列挙する (= 菱形パターン)。斜め (1,1) もマンハッタン距離 2 として含まれる。
    /// 例:
    ///   `{min=1, max=1}` → 隣接 4 セル (剣・槍)
    ///   `{min=2, max=2}` → 距離 2 の 8 セル (弓: 上下左右 2 マス先 + 斜め 1 マス)
    ///   `{min=1, max=2}` → 距離 1〜2 の 12 セル (手槍・手斧)
    /// 地形フィルタはかけない: 壁・味方・床いずれの上にも赤マスを描いて「武器の届く範囲」
    /// を一貫表示する (実際に攻撃できるのは敵セルだけで、その判定は TurnRules 側)。
    /// `layer` 引数は将来の terrain-aware フィルタ用に残してある (現状 unused)。
    pub def computeAttackCells(origin: {x = Int32, y = Int32},
                                range: UnitCatalog.WeaponRange,
                                _layer: TileMapLayer): List[{x = Int32, y = Int32}] =
        let lo = Int32.max(1, range#min);
        let hi = range#max;
        Board.manhattanOffsets(lo, hi)
            |> List.map(o ->
                ({x = origin#x + o#x, y = origin#y + o#y}: {x = Int32, y = Int32}))

    /// 現在の射程内セル一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#playerAttackRange {
            case Some(data) => data#cells
            case None => Nil
        }

    /// 赤マス内に居る「生きている敵」の Data リストを reading order (y 昇順 → x 昇順)
    /// で返す。`PlayerAttack` フェーズでカーソルを敵間でサイクルさせる用。
    /// 死亡演出中 (`isDying`) と HP 0 以下の敵は除外する。
    pub def targetsInRange(scene: Scene[NodeTag]):
            List[EnemyScene.Data] \ {EnemyData.RosterQuery, RangeOverlayState.State} =
        let inRangeCells = cells(scene);
        EnemyData.RosterQuery.getAll()
            |> List.filter(d ->
                not d#isDying
                and d#hp > 0
                and List.exists(c ->
                    c#x == d#gridPos#x and c#y == d#gridPos#y,
                    inRangeCells))
            |> List.sortBy(d -> (d#gridPos#y, d#gridPos#x))
}


/// TradeRangeScene — 物交換の相手候補 (隣接味方マス) を緑色で可視化する
///
/// 「こうかん」確定で `TradeTargetSelect` フェーズに入ると、選択中プレイヤーの
/// 上下左右 1 マス内に居る他味方のマスを緑色で敷く。プレイヤーは赤マスと同じく
/// 緑マス上のみ移動できるカーソルで交換相手を選ぶ。
///
/// `cells` API は他の Range と同じく「現在敷かれているセル一覧」を返す。
/// CursorScene の移動制限述語と TurnRules の Confirm 判定で使う。
///
/// **ライフサイクル**:
///   - `PhaseTransitions.enterTradeTargetSelect` で `show(scene)` を呼んで描く
///   - 別フェーズに抜けるとき (PhaseTransitions の他の enter* / 完了時) は `clear` を呼ぶ
mod TradeRangeScene {

    /// `cells` は交換可能な相手候補のグリッド位置一覧 (= 選択中味方の上下左右に居る他味方)。
    /// カーソル移動制限と Confirm 時の相手判定に使う。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    /// 緑系 modulate。MoveRange (青) / PlayerAttackRange (赤) と区別する。
    pub def color(): Color = {r = 0.3f32, g = 1.0f32, b = 0.3f32}

    /// 他の情報表示 Range (EnemyRange / PlayerAttackRange) と透過度を揃えることで
    /// 各種ハイライトの視覚的重みを統一し、特定レイヤーだけが浮きあがるのを防ぐ。
    pub def alpha(): Float32 = 0.7f32

    /// 既存を消し、`SelectedPlayer.State` から選択中味方の隣接味方マスを計算して緑マスを描き直す。
    /// 選択中味方なし / 居ない / 隣接味方ゼロのいずれでも安全に何も描かない。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery, RangeOverlayState.State} =
        let cleared = clear(scene);
        adjacentAllyCells()
            |> Option.filter(allyCells -> not List.isEmpty(allyCells))
            |> Option.map(allyCells -> paintCells(allyCells, cleared))
            |> Option.getWithDefault(cleared)

    /// 選択中味方の隣接味方マスを返す。
    /// `None` と `Some(Nil)` を区別している理由: 上流の `show` は `Option.filter` で
    /// 空リストを弾くが、「選択中プレイヤー自体が居ない」場合も同じ分岐に落とすと
    /// デフォルト値の選択が曖昧になる。`None` は「計算不能」、`Some(Nil)` は
    /// 「隣接味方ゼロ(正常計算済み)」として意味を分けておくことで、
    /// 将来 None を別途ログ・fallback 処理したいときに判別できる。
    def adjacentAllyCells():
            Option[List[{x = Int32, y = Int32}]]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield PlayerScene.adjacentAllies(player) |> List.map(d -> d#gridPos)

    /// 指定セル群を resource の tradeRange に書く純粋部分。
    def paintCells(allyCells: List[{x = Int32, y = Int32}],
                    scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({tradeRange = Some({cells = allyCells}) | RangeOverlayState.State.get()});
        scene

    /// 表示中の TradeRange があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({tradeRange = None | RangeOverlayState.State.get()});
        scene

    /// 現在敷かれている緑マス一覧。カーソル移動制限と Confirm 時の対象判定に使う。
    /// 未登録なら空リスト。
    pub def cells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#tradeRange {
            case Some(data) => data#cells
            case None       => Nil
        }
}


/// DangerZoneScene — Shift トグルで「全(可視)敵に攻撃される可能性があるマス」を紫で可視化する。
///
/// 各敵について「移動到達セル ∪ そこから武器射程で届くセル」を求め、全敵ぶんを統合した
/// 危険範囲（= どこかの敵に攻撃されうるマス）を紫マスで描く。FE の敵射程一括表示(危険範囲)相当。
/// 表示状態は resource の Option の在/不在で表す（Some なら ON）。Shift で `toggle` を呼んで出し入れする。
///
/// **ライフサイクル**:
///   - `Game.flix` の onKeyPressed が LeftShift のエッジで `toggle` を呼ぶ（PlayerCursor / PlayerMoving）。
///   - 敵が動くと内容が古くなるので、`PhaseTransitions.enterEnemyTurn` で `clear` する。
mod DangerZoneScene {

    /// 統合済みの危険マス一覧。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    /// 紫系 modulate。移動(青/白)・攻撃(赤)・交換(緑)と区別する危険範囲色。
    pub def color(): Color = {r = 0.6f32, g = 0.3f32, b = 0.9f32}

    /// 下のマップ・駒が見える程度に透かす。
    pub def alpha(): Float32 = 0.5f32

    /// 現在表示中か（= dangerZone が Some か）。Shift トグルの状態に使う。
    pub def isShown(_scene: Scene[NodeTag]): Bool \ RangeOverlayState.State =
        Option.nonEmpty(RangeOverlayState.State.get()#dangerZone)

    /// Shift トグル: 表示中なら消す、非表示なら全敵の危険範囲を組んで紫で描く。
    pub def toggle(scene: Scene[NodeTag]): Scene[NodeTag] \ {World.WorldQuery, RangeOverlayState.State} =
        if (isShown(scene)) clear(scene) else show(scene)

    /// 全可視敵の危険マス（移動到達 ∪ 攻撃到達）を統合して紫で描く。空なら何もしない。
    /// `EnemyScene.getAll` は scene ツリーを走査するだけで外部 effect を発火しないため、
    /// `EnemyData.RosterQuery` を使わずに呼び出せる。
    def show(scene: Scene[NodeTag]): Scene[NodeTag] \ {World.WorldQuery, RangeOverlayState.State} =
        let cleared = clear(scene);
        let layer   = MapScene.getMapLayer(cleared);
        // 敵 1 体の危険マス: 移動到達セル + (武器があれば)そこから射程で届くセル。
        let dangerOf = e -> {
            let reachable = Board.reachableCells(
                c -> TileMapLayer.isFloor(c, layer), e#gridPos, e#moveTiles);
            match e#weapon {
                case None    => reachable
                case Some(w) =>
                    let lo = Int32.max(1, w#range#min);
                    let hi = w#range#max;
                    List.append(reachable, Board.computeThreatCells(reachable, lo, hi))
            }
        };
        // 位置は World 上書き Data（scene gridPos twin は退役）。
        let cells = EnemyScene.getAllWithWorldPos(cleared)
            |> List.filter(e -> EnemyScene.isVisible(e#id, cleared))
            |> List.foldLeft((acc, e) -> List.append(acc, dangerOf(e)), Nil)
            |> Board.dedupCells;
        if (List.isEmpty(cells)) cleared
        else {
            RangeOverlayState.State.put({dangerZone = Some({cells = cells}) | RangeOverlayState.State.get()});
            cleared
        }

    /// 表示中の DangerZone があれば消す。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] \ RangeOverlayState.State =
        RangeOverlayState.State.put({dangerZone = None | RangeOverlayState.State.get()});
        scene

    /// 現在の危険マス一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(_scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] \ RangeOverlayState.State =
        match RangeOverlayState.State.get()#dangerZone {
            case Some(data) => data#cells
            case None       => Nil
        }
}
