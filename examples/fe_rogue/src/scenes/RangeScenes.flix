/// RangeScenes — マップ上のタイル群を半透明で可視化する Scene 群
///
/// 共通の Marker2D + Tile_<idx> Sprite2D 構造の描画責務は `RangeOverlay` mod に
/// 切り出してある。各 range mod は「セル計算」と「色・α 定数」と
/// 「NodeTag variant の構築」だけが固有で、残りは RangeOverlay にぶら下げる。
///
/// ノード構造 (どの mod も同型):
///   <name> (Marker2D, NodeTag.XxxRange(...))
///     ├─ Tile_0 (Sprite2D, alpha=A, modulate=Color)
///     ├─ Tile_1 ...
///     └─ ...
///
/// 親 Marker2D は world (0,0) に置く。MapScene の TileMapLayer も (0,0) なので、
/// 子 Sprite2D は `セル中心 = grid * tileSize + tileSize/2` を直接 position に
/// すればマップと同じ座標系でぴったり重なる。

/// 範囲表示 Scene が共有する描画プリミティブ。
/// NodeTag variant の構築 / セル計算は呼び出し側 (各 range mod) の責任で、
/// この mod は「親 Marker2D + Tile_<idx> ハッチ Panel 列を描く」ことだけを担う。
///
/// 各セルは塗り（半透明）＋45° 斜線ハッチ＋枠線＋角丸の Panel で描く
/// （Godot StyleBoxFlat + 斜線シェーダ相当。画像テクスチャは使わない）。
/// 呼び出し側は「色相 color」と「強調度 alpha」だけ渡し、塗り/縞/枠の
/// 不透明度と縞色/枠色は本 mod が color から派生させる（CSS の
/// repeating-linear-gradient + border デザインを 26px タイルへ縮小したもの）。
mod RangeOverlay {

    /// 全 range scene 共通の zIndex。tilemap (= 0) より上、Player Sprite (= 10) より下。
    def tileZIndex(): Int32 = 1

    /// セル枠から内側に詰める余白 px（CSS の inset 相当。隣マスとの隙間になる）。
    def inset(): Float64 = 2.0

    /// 縞 1 本の幅 px と周期 px（CSS の 7px/14px を 26px タイルへ縮小）。
    def stripeWidth(): Float64 = 3.0
    def stripePeriod(): Float64 = 6.0

    /// 色相を白方向へ `t` だけ寄せて明るくする（縞・枠用の明色を作る）。
    def lighten(c: Color, t: Float32): Color =
        {r = c#r + (1.0f32 - c#r) * t,
         g = c#g + (1.0f32 - c#g) * t,
         b = c#b + (1.0f32 - c#b) * t}

    /// 親 Marker2D を origin (0,0) にぶら下げる。`tag` は呼び出し側が
    /// `NodeTag.MoveRange(data)` 等の variant を構築して渡す。
    pub def attachParent(name: String, tag: NodeTag, scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addNode(name,
            EngineNode.Marker2DWithState(parent, tag),
            scene)

    /// `cells` を順に列挙してハッチ Panel を `Tile_<idx>` として子追加する。
    /// セル中心 (`MapSnapshot.cellCenter`) を基準に inset ぶん詰めた角丸 Panel を置く。
    /// `alpha` は範囲の強調度で、塗り/縞/枠の不透明度をまとめて増減させる。
    pub def renderTiles(parentName: String,
                         cells: List[{x = Int32, y = Int32}],
                         color: Color, alpha: Float32,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        let indexed = List.zipWithIndex(cells);
        let side = MapSnapshot.tileSize() - inset() * 2.0;
        let size: Vec2.Vec2 = {x = side, y = side};
        let half = side / 2.0;
        // 塗りは淡く、縞は中明色を濃いめ、枠は明色をくっきり（CSS の重み付けを踏襲）。
        let stripeColor = lighten(color, 0.5f32);
        let borderColor = lighten(color, 0.2f32);
        List.foldLeft(acc -> entry -> {
            let (idx, cell) = entry;
            let center = MapSnapshot.cellCenter(cell);
            let topLeft: Vec2.Vec2 = {x = center#x - half, y = center#y - half};
            // 縞以外（塗り）はほぼ透過させて床を見せ、色は斜線と枠で表現する。
            let panel = Panel.make(size, color)
                            |> Node2D.setPosition(topLeft)
                            |> Panel.setBackgroundAlpha(alpha * 0.08f32)
                            |> Panel.setBorderColor(borderColor)
                            |> Panel.setBorderAlpha(alpha)
                            |> Panel.setBorderWidth(1)
                            |> Panel.setCornerRadius(2.0)
                            |> Panel.setStripe(stripeColor, alpha * 0.65f32, stripeWidth(), stripePeriod())
                            |> CanvasItem.setZIndex(tileZIndex());
            Scene.addChild(parentName,
                "Tile_${idx}",
                EngineNode.PanelWithState(panel, NodeTag.NoTag),
                acc)
        }, scene, indexed)
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
///   - 範囲は `MoveRangeScene.isInRange` 経由で `PlayerScene.physicsProcess` から
///     参照され、移動先の許可判定に使われる (範囲外のマスへは踏み込めない)。
mod MoveRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `reachable` は BFS で到達可能と判定されたセル一覧 (origin を含む)。
    pub type alias Data = {
        reachable = List[{x = Int32, y = Int32}]
    }

    def name(): String = "MoveRange"
    pub def moveRangePath(): NodePath = name() :: Nil

    /// 移動範囲を識別する青系 modulate。Floor 装飾レイヤーの上で
    /// 移動可能マスとして識別しやすいように青寄りに着色する。
    def color(): Color = {r = 0.3f32, g = 0.5f32, b = 1.0f32}

    /// 移動可能マスをはっきり認識させるため完全不透明にする。
    /// 半透明にすると青が薄れて床と区別しにくくなる。
    def alpha(): Float32 = 1.0f32

    /// MapScene + PlayerScene が登録済みのシーンに MoveRange ノードと各セルの Sprite2D
    /// 子を追加する。**選択中プレイヤー** の位置を origin に `Board.reachableForUnit`
    /// で範囲を求める。未選択 (PlayerCursor / EnemyTurn 等) なら何も描画しない。
    /// `add` は `buildPlayingScene` の初回構築でも呼ばれる (`sceneRef` 更新前) ため、
    /// PartyQuery effect は使わず scene 引数を直接読む。`refresh` 経由のランタイム呼び出しでも
    /// 渡される scene は常に最新なので問題ない。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None     => scene
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case None    => scene
                    case Some(_) => buildFor(id, scene)
                }
        }

    /// 指定 id を起点に MoveRange を組み立てる本体 (既存ノードは事前に取り除いてから呼ぶ)。
    /// **通行不可**: 壁 / 敵駒。
    /// **味方駒は通過可能** (1 マスとしてカウント)。「味方は素通り、ただし停止はできない」
    /// 表現。`Board.reachableForUnit` で到達範囲を出し、`stoppableForUnit` で味方マス
    /// (自分 + 他味方) を除いたものを青マスとして描画する。AutoMove も同じプリミティブで
    /// 動くため、ここで仕様が一致していれば自動で挙動が揃う。
    def buildFor(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let board     = BoardSnapshot.fromScene(scene);
        let origin    = PlayerScene.getGridPos(id, scene);
        let steps     = PlayerScene.getMoveTiles(id, scene);
        let cells     = Board.reachableForUnit(board, origin, steps);
        let drawCells = Board.stoppableForUnit(board, origin, steps);
        scene
            |> RangeOverlay.attachParent(name(), NodeTag.MoveRange({reachable = cells}))
            |> RangeOverlay.renderTiles(name(), drawCells, color(), alpha())

    /// 既存の MoveRange ノードを丸ごと取り除いて `add` で組み直す。
    pub def refresh(scene: Scene[NodeTag]): Scene[NodeTag]
            \ SelectedPlayer.State =
        Scene.removeAt(moveRangePath(), scene) |> add

    /// 表示中の MoveRange ノードがあれば取り除く。なければ何もしない。
    /// PlayerAttack フェーズ移行時など、青マスを一時的に消したいときに使う
    /// (`EnemyRangeScene.clear` と対称)。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(moveRangePath(), scene)

    /// 指定セルが「現在のターンで踏める」範囲内にあるか。
    /// `MoveRange` ノードが未登録なら false を返す (ゲーム初期化前のフォールバック)。
    pub def isInRange(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#reachable)
            case _ => false
        }

    /// 現在範囲のセル一覧 (テスト・デバッグ用 + MoveAttackRangeScene が読む)。
    /// 未登録なら空リスト。
    pub def reachable(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(moveRangePath(), scene) {
            case Some(NodeTag.MoveRange(data)) => data#reachable
            case _ => Nil
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

    /// 親 Marker2D に紐づくデータ。reachable と重複しない「赤マスだけ」のセル一覧。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    def name(): String = "MoveAttackRange"
    pub def rangePath(): NodePath = name() :: Nil

    /// PlayerAttackRangeScene / EnemyRangeScene と同じ赤系 modulate。
    def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// 青マス (MoveRange = 1.0) より透かすことで、移動範囲より外側の脅威範囲を
    /// 視覚的に奥の層として見せ、「動けるマス」と「そこから攻撃が届くマス」を階層化する。
    def alpha(): Float32 = 0.5f32

    /// 既存ノードを取り除いて再構築する。`MoveRangeScene` の青マスが既に build 済みの
    /// 前提で、その reachable を読み取って差集合を作る。
    pub def refresh(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
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
                                else
                                    cleared
                                        |> RangeOverlay.attachParent(name(), NodeTag.MoveAttackRange({cells = cells}))
                                        |> RangeOverlay.renderTiles(name(), cells, color(), alpha())
                        }
                }
        }

    /// 表示中の MoveAttackRange ノードがあれば取り除く。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(rangePath(), scene)

    /// テスト・デバッグ用: 現在の脅威セル一覧。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.MoveAttackRange(data)) => data#cells
            case _ => Nil
        }
}

/// EnemyRangeScene — カーソルが敵に乗っているとき、その敵の移動範囲を赤色で可視化する
///
/// `MoveRangeScene` のミラー実装で、起点が「Player」ではなく「ホバー中の敵」になり、
/// 色が「青」ではなく「赤」になる。FE 風の「敵情報を見ながらターン計画を立てる」フローを
/// 提供するための情報表示専用シーン。
///
/// **ライフサイクル**:
///   - Cursor がフレーム間で乗っている敵 id が変わったとき、`refreshFor(id, scene)` で
///     既存ノードを破棄して新規構築する
///   - Cursor が敵以外に移ったとき、`clear(scene)` でノードを丸ごと取り除く
///   - 敵ターン開始時 / フェーズ切替で見せたくない場面でも `clear` を呼んで消す
///
/// `MoveRangeScene` のような「常設」運用は取らず、必要なときだけ scene に存在する。
mod EnemyRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `enemyId` は今表示している対象敵。`reachable` は BFS で到達可能と判定された
    /// セル一覧 (origin = 敵セルを含む)。
    pub type alias Data = {
        enemyId   = Int32,
        reachable = List[{x = Int32, y = Int32}]
    }

    def name(): String = "EnemyRange"
    pub def enemyRangePath(): NodePath = name() :: Nil

    /// 白系 modulate。敵の「移動範囲」を表す。攻撃到達範囲(EnemyAttackRange=赤)と
    /// 色で区別するため移動範囲は白にしている。
    def color(): Color = UITheme.white()

    /// 情報表示なので少し透かして駒や床を見やすくする。
    def alpha(): Float32 = 0.7f32

    /// 既存の EnemyRange ノードがあれば取り除き、`enemyId` の敵に対応する範囲で
    /// 構築し直す。敵が居なければ何もしない (`clear` 相当の保険)。
    /// 壁のみ通れない。味方マスや他敵マスも「想定移動範囲」として表示する
    /// (プレイヤーは「もし誰も居なければここまで来られる」を読む)。
    pub def refreshFor(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ EnemyData.RosterQuery =
        match EnemyData.RosterQuery.get(enemyId) {
            case None       => clear(scene)
            case Some(data) =>
                let cleared = clear(scene);
                let layer   = MapScene.getMapLayer(cleared);
                let cells = Board.reachableCells(
                    c -> TileMapLayer.isFloor(c, layer),
                    data#gridPos,
                    data#moveTiles);
                cleared
                    |> RangeOverlay.attachParent(name(),
                        NodeTag.EnemyRange({enemyId = enemyId, reachable = cells}))
                    |> RangeOverlay.renderTiles(name(), cells, color(), alpha())
        }

    /// 表示中の EnemyRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(enemyRangePath(), scene)

    /// 現在表示している敵 id (出ていなければ None)。
    pub def currentEnemyId(scene: Scene[NodeTag]): Option[Int32] =
        match Scene.getState(enemyRangePath(), scene) {
            case Some(NodeTag.EnemyRange(data)) => Some(data#enemyId)
            case _                              => None
        }

    /// 現在の reachable セル一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def reachable(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(enemyRangePath(), scene) {
            case Some(NodeTag.EnemyRange(data)) => data#reachable
            case _                              => Nil
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

    /// 親 Marker2D に紐づくデータ。
    /// `enemyId` は今表示している対象敵。`cells` は移動到達セルと重複しない「赤マスだけ」。
    pub type alias Data = {
        enemyId = Int32,
        cells   = List[{x = Int32, y = Int32}]
    }

    def name(): String = "EnemyAttackRange"
    pub def rangePath(): NodePath = name() :: Nil

    /// 赤系 modulate。EnemyRange(移動範囲=白) と区別する「攻撃到達」の色。
    def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// 移動範囲(白, alpha=0.7) と区別するため少し透かす。
    def alpha(): Float32 = 0.5f32

    /// 既存ノードを取り除き、`enemyId` の敵の脅威範囲で構築し直す。
    /// `EnemyRangeScene` が直前に build した敵移動到達セルを読み、武器射程で広げて差集合を作る。
    /// 敵が居ない / 武器なし / 脅威セルが空なら何も描かない。
    /// 「敵が居て武器を持つ」の 2 段の Option は forM で 1 段に畳み、空セル判定は
    /// `renderThreat` に寄せてネストを浅く保つ。
    pub def refreshFor(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ EnemyData.RosterQuery =
        let cleared = clear(scene);
        let built = forM (
            data <- EnemyData.RosterQuery.get(enemyId);
            w    <- data#weapon
        ) yield renderThreat(enemyId, threatCells(w, cleared), cleared);
        Option.getWithDefault(cleared, built)

    /// 敵移動到達セル (EnemyRangeScene.reachable) を武器射程で広げた脅威セル。
    def threatCells(weapon: UnitCatalog.WeaponResource,
                     scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        let reachable = EnemyRangeScene.reachable(scene);
        Board.computeThreatCells(reachable, Int32.max(1, weapon#range#min), weapon#range#max)

    /// 脅威セルが空でなければ EnemyAttackRange ノードを敷く。空なら scene をそのまま返す。
    def renderThreat(enemyId: Int32, cells: List[{x = Int32, y = Int32}],
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        if (List.isEmpty(cells)) scene
        else scene
            |> RangeOverlay.attachParent(name(),
                NodeTag.EnemyAttackRange({enemyId = enemyId, cells = cells}))
            |> RangeOverlay.renderTiles(name(), cells, color(), alpha())

    /// 表示中の EnemyAttackRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(rangePath(), scene)

    /// 現在の脅威セル一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.EnemyAttackRange(data)) => data#cells
            case _                                    => Nil
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
///   - `PlayerAttack` を抜ける (敵ターンへ移行) ときは `clear(scene)` で取り除く
mod PlayerAttackRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `cells` は赤く描画されている射程内セル一覧 (origin = 味方セルは含まない)。
    /// `isInRange` の判定に使う (カーソル clamp の述語)。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    def name(): String = "PlayerAttackRange"
    pub def attackRangePath(): NodePath = name() :: Nil

    /// 赤系 modulate。EnemyRangeScene / MoveAttackRangeScene と同色。
    def color(): Color = {r = 1.0f32, g = 0.3f32, b = 0.3f32}

    /// EnemyRangeScene と同じく少し透かして駒や床を見やすくする。
    def alpha(): Float32 = 0.7f32

    /// 既存の PlayerAttackRange ノードがあれば取り除き、**選択中プレイヤー** の現在位置
    /// origin に対して **インベントリ全武器の射程の和集合** で赤マスを敷き直す。
    /// 攻撃中はどの武器に持ち替えても届く敵にカーソルを乗せられるように、装備中(先頭)だけ
    /// でなく全武器の射程を合わせて表示する (重複セルは除去)。
    /// 未選択時は cleared を返す (赤マス表示なし)。
    /// 選択中プレイヤーの武器が壊れている (`weapons = Nil`) 場合は cells を空にして
    /// 親ノードだけ追加する。これにより PlayerAttack フェーズに入ってもカーソルが
    /// 敵に乗らず、Z 押下で AttackHit が発火しない (X でスキップして抜ける)。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        let cleared = clear(scene);
        match SelectedPlayer.State.get()#id {
            case None     => cleared
            case Some(id) =>
                match PlayerScene.get(id, cleared) {
                    case None    => cleared
                    case Some(d) =>
                        let layer = MapScene.getMapLayer(cleared);
                        let cells = unionWeaponCells(d#gridPos, d#weapons, layer);
                        cleared
                            |> RangeOverlay.attachParent(name(),
                                NodeTag.PlayerAttackRange({cells = cells}))
                            |> RangeOverlay.renderTiles(name(), cells, color(), alpha())
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

    /// 表示中の PlayerAttackRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(attackRangePath(), scene)

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

    /// 指定セルが現在の射程内 (赤マス上) にあるか。
    /// 範囲が表示されていない (= フェーズが PlayerAttack ではない) 場合は false。
    pub def isInRange(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) =>
                List.exists(c -> c#x == cell#x and c#y == cell#y, data#cells)
            case _ => false
        }

    /// 現在の射程内セル一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(attackRangePath(), scene) {
            case Some(NodeTag.PlayerAttackRange(data)) => data#cells
            case _ => Nil
        }

    /// 赤マス内に居る「生きている敵」の Data リストを reading order (y 昇順 → x 昇順)
    /// で返す。`PlayerAttack` フェーズでカーソルを敵間でサイクルさせる用。
    /// 死亡演出中 (`isDying`) と HP 0 以下の敵は除外する。
    pub def targetsInRange(scene: Scene[NodeTag]):
            List[EnemyScene.Data] \ EnemyData.RosterQuery =
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
/// `cells` API は他の Range scene と同じく「現在敷かれているセル一覧」を返す。
/// CursorScene の移動制限述語と TurnRules の Confirm 判定で使う。
///
/// **ライフサイクル**:
///   - `PhaseTransitions.enterTradeTargetSelect` で `show(scene)` を呼んで描く
///   - 別フェーズに抜けるとき (PhaseTransitions の他の enter* / 完了時) は `clear` を呼ぶ
mod TradeRangeScene {

    /// 親 Marker2D に紐づくデータ。
    /// `cells` は交換可能な相手候補のグリッド位置一覧 (= 選択中味方の上下左右に居る他味方)。
    /// カーソル移動制限と Confirm 時の相手判定に使う。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    def name(): String = "TradeRange"
    pub def rangePath(): NodePath = name() :: Nil

    /// 緑系 modulate。MoveRange (青) / PlayerAttackRange (赤) と区別する。
    def color(): Color = {r = 0.3f32, g = 1.0f32, b = 0.3f32}

    /// 他の情報表示 Range (EnemyRange / PlayerAttackRange) と透過度を揃えることで
    /// 各種ハイライトの視覚的重みを統一し、特定レイヤーだけが浮きあがるのを防ぐ。
    def alpha(): Float32 = 0.7f32

    /// 既存の TradeRange ノードがあれば取り除き、`SelectedPlayer.State` から
    /// 選択中味方の隣接味方マスを計算して緑マスを描き直す。
    /// 選択中味方なし / 居ない / 隣接味方ゼロのいずれでも安全に何も描かない。
    pub def show(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
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

    /// 指定セル群に親 Marker2D + 緑色 Sprite2D を貼り付ける純粋部分。
    def paintCells(allyCells: List[{x = Int32, y = Int32}],
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> RangeOverlay.attachParent(name(),
                NodeTag.TradeRange({cells = allyCells}))
            |> RangeOverlay.renderTiles(name(), allyCells, color(), alpha())

    /// 表示中の TradeRange ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(rangePath(), scene)

    /// 現在敷かれている緑マス一覧。カーソル移動制限と Confirm 時の対象判定に使う。
    /// 未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.TradeRange(data)) => data#cells
            case _                              => Nil
        }
}

/// DangerZoneScene — Shift トグルで「全(可視)敵に攻撃される可能性があるマス」を紫で可視化する。
///
/// 各敵について「移動到達セル ∪ そこから武器射程で届くセル」を求め、全敵ぶんを統合した
/// 危険範囲（= どこかの敵に攻撃されうるマス）を紫マスで描く。FE の敵射程一括表示(危険範囲)相当。
/// 表示状態は「ノードの有無」で表す（在れば ON）。Shift で `toggle` を呼んで出し入れする。
///
/// **ライフサイクル**:
///   - `Game.flix` の onKeyPressed が LeftShift のエッジで `toggle` を呼ぶ（PlayerCursor / PlayerMoving）。
///   - 敵が動くと内容が古くなるので、`PhaseTransitions.enterEnemyTurn` で `clear` する。
mod DangerZoneScene {

    /// 親 Marker2D に紐づくデータ。統合済みの危険マス一覧。
    pub type alias Data = {
        cells = List[{x = Int32, y = Int32}]
    }

    def name(): String = "DangerZone"
    pub def rangePath(): NodePath = name() :: Nil

    /// 紫系 modulate。移動(青/白)・攻撃(赤)・交換(緑)と区別する危険範囲色。
    def color(): Color = {r = 0.6f32, g = 0.3f32, b = 0.9f32}

    /// 下のマップ・駒が見える程度に透かす。
    def alpha(): Float32 = 0.5f32

    /// 現在表示中か（= DangerZone ノードが在るか）。Shift トグルの状態に使う。
    pub def isShown(scene: Scene[NodeTag]): Bool =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.DangerZone(_)) => true
            case _                           => false
        }

    /// Shift トグル: 表示中なら消す、非表示なら全敵の危険範囲を組んで紫で描く。
    pub def toggle(scene: Scene[NodeTag]): Scene[NodeTag] =
        if (isShown(scene)) clear(scene) else show(scene)

    /// 全可視敵の危険マス（移動到達 ∪ 攻撃到達）を統合して紫で描く。空なら何もしない。
    /// `EnemyScene.getAll` は scene ツリーを走査するだけで外部 effect を発火しないため、
    /// `EnemyData.RosterQuery` を使わずに呼び出せる (Flix では pure 関数でも
    /// 内部で scene を読むことは許容されている)。
    def show(scene: Scene[NodeTag]): Scene[NodeTag] =
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
        let cells = EnemyScene.getAll(cleared)
            |> List.filter(e -> EnemyScene.isVisible(e#id, cleared))
            |> List.foldLeft((acc, e) -> List.append(acc, dangerOf(e)), Nil)
            |> Board.dedupCells;
        if (List.isEmpty(cells)) cleared
        else
            cleared
                |> RangeOverlay.attachParent(name(), NodeTag.DangerZone({cells = cells}))
                |> RangeOverlay.renderTiles(name(), cells, color(), alpha())

    /// 表示中の DangerZone ノードがあれば取り除く。なければ何もしない。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(rangePath(), scene)

    /// 現在の危険マス一覧 (テスト・デバッグ用)。未登録なら空リスト。
    pub def cells(scene: Scene[NodeTag]): List[{x = Int32, y = Int32}] =
        match Scene.getState(rangePath(), scene) {
            case Some(NodeTag.DangerZone(data)) => data#cells
            case _                              => Nil
        }
}
