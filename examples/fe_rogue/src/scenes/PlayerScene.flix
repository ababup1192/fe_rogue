/// PlayerScene — 複数プレイヤー（Marker2D + 子 Sprite2D）の集まり
///
/// FE 風 SRPG の「3 人パーティ」を表現する。EnemyScene と同じ流儀で、
/// 各プレイヤーをトップレベルの "Player_<id>" ノードとして並べて管理する。
///
/// ノード構造（プレイヤー 1 体あたり）:
///   Player_<id> (Marker2D, NodeTag.Player(Data))
///     └─ Sprite (Sprite2D, character_sheet)
///
/// Camera は CameraScene が独立した最上位ノードとして管理し、毎フレーム
/// 「選択中プレイヤー」の位置に追従させる（PlayerScene 自身は Camera を持たない）。
///
/// ターン進行:
///   - PlayerCursor で Z 押下 → カーソル位置の **アクティブな** プレイヤーを選択
///     （`SelectedPlayer.State.put(Some(id))` ＋ `PlayerMoving` へ遷移）
///   - PlayerMoving で WASD → 選択中プレイヤーが移動
///   - PlayerAttack で Z（敵に） / X（スキップ） → 選択中プレイヤーを `waited = true`
///   - 全員 waited なら敵ターン、まだ残っていれば PlayerCursor で次セレクトへ
///
/// `waited = true` のプレイヤーは:
///   - 灰色 modulate で表示される
///   - PlayerCursor で選択不可（Z で反応しない）
///
/// 移動は moveTo(id, target) で論理位置（gridPos）を即更新し、
/// 見た目は engine 層の `Tween` モジュールに委ねる。**壁・他駒の判定は
/// 呼び出し側（Board / MoveRangeScene）が moveTo を呼ぶ前に済ませている前提**。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態。
    /// id: 0..N-1 の連番（N は `pools.party` の長さ）。"Player_<id>" ノード名と一致する。
    /// gridPos: 盤面上の駒の論理位置。moveTo で即座に更新される。
    /// moveTiles: 1 ターンに移動できるマス数（FE の「移動力」相当）。`resource` から初期値を継承。
    /// hp: 残り体力。0 になるとゲームオーバー。`resource#hp` が初期値。
    /// waited: 行動済みフラグ。true なら灰色表示・選択不可。
    /// attackTargetId: 体当たり攻撃モーション中なら Some(被攻撃者 id)。
    ///   `attack_lunge` アニメーションの method 発火 / finished 時に GameManager が
    ///   この値を読んでダメージ適用 / commit を行う。アニメ完了で None に戻す。
    /// resource: スポーン時のユニット定義テンプレート（UnitResource）。
    ///   ゲームオーバー時の復元（`respawnFromInitial`）で同じユニット種別で再生するために保持。
    /// weapons: 装備中の武器インベントリ。空になるとそのプレイヤーは攻撃できない。
    ///   攻撃時は `selectedWeaponIdx` で指定された武器が使われ、耐久度が 1 減り、
    ///   0 になったら weapons から取り除かれる（武器が壊れた）。
    /// selectedWeaponIdx: 武器選択ウィンドウで選ばれた武器の index（weapons リスト上）。
    ///   PlayerMoving + Z で WeaponSelect フェーズに入り、ウィンドウで選ばれた瞬間にセット、
    ///   PlayerAttack で実際に Z 押下したときに consume されてクリアされる。
    pub type alias Data = {
        id                 = Int32,
        gridPos            = {x = Int32, y = Int32},
        moveTiles          = Int32,
        hp                 = Int32,
        waited             = Bool,
        attackTargetId     = Option[Int32],
        resource           = UnitCatalog.UnitResource,
        weapons            = List[UnitCatalog.WeaponResource],
        selectedWeaponIdx  = Option[Int32]
    }

    /// スポーン時の中間表現。`add` で配置するセルの id/gridPos に加え、
    /// どのユニット定義（UnitResource）でセットアップするかも持つ。
    /// 初期 spawn のスナップショット（ゲームオーバー時の復元用）にも使う。
    /// `weapons` は初期インベントリ（壊れる前の固定リスト）で、respawn 時にこの値で復元する。
    pub type alias Spawn = {
        id       = Int32,
        gridPos  = {x = Int32, y = Int32},
        resource = UnitCatalog.UnitResource,
        weapons  = List[UnitCatalog.WeaponResource]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える。
    def tileSize(): Float64 = 16.0

    /// プレイヤー Sprite の zIndex（Player は前面に立つ）。EnemyScene と同じ 10。
    def spriteZIndex(): Int32 = 10

    /// 1 マス分のスライド時間（≈ 0.133 秒）
    def slideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 120)

    /// `waited = true` 時の sprite modulate（薄い灰色）。
    /// CanvasItem.setModulate で sprite の RGB を乗算する。
    def waitedColor(): Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32}

    /// `waited = false` 時の sprite modulate（白 = 元色）。
    def activeColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// "Player_2" のようなノード名（World の直接の子）。
    pub def playerName(id: Int32): String = "Player_${id}"

    /// Player_<id> の NodePath。Y-sort root の World 配下にぶら下げるため
    /// "World/Player_<id>" の 2 段構造。Tween / GlobalPosition 等の API はこの helper
    /// 経由で呼ぶこと（直書きしない）
    pub def playerPath(id: Int32): NodePath =
        List.append(MapScene.worldPath(), playerName(id) :: Nil)

    /// Player_<id> の子 Sprite ノードへのパス。modulate 変更や将来の alpha tween に使う。
    pub def spritePath(id: Int32): NodePath =
        List.append(playerPath(id), "Sprite" :: Nil)

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene が登録済みの scene にプレイヤー全員（`players` プールの全員）を追加する。
    /// 0 番目は MapScene が記録した spawnGrid に、残りはその近傍の床セルに配置する。
    /// 各プレイヤーには `players` プールのリスト順で `UnitResource` を、
    /// `playerWeapons` プールの同 index から `WeaponResource` を割り当てる
    /// （1 プレイヤー = 1 武器）。プールの長さ不一致は起動時の typo として即 panic する。
    pub def add(catalog: UnitCatalog.UnitCatalog, scene: Scene[NodeTag]): Scene[NodeTag] =
        let party        = UnitCatalog.pool("players", catalog);
        let weapons      = UnitCatalog.weaponPool("playerWeapons", catalog);
        let n            = List.length(party);
        if (List.length(weapons) != n)
            bug!("PlayerScene.add: playerWeapons length (${List.length(weapons)}) != players length (${n})")
        else {
            let spawnGrid = MapScene.getSpawnGrid(scene);
            let layer     = MapScene.getMapLayer(scene);
            let cells     = pickPlayerSpawns(spawnGrid, n, layer);
            // cells が n に満たない場合（極端に狭い anchor）は重複セルを許容して埋める
            let padded    = padCells(cells, spawnGrid, n);
            let spawns: List[Spawn] = padded
                |> List.mapWithIndex(id -> c ->
                    let res = match List.nth(id, party) {
                        case Some(r) => r
                        case None    => bug!("PlayerScene.add: party index ${id} out of range")
                    };
                    let weapon = match List.nth(id, weapons) {
                        case Some(w) => w
                        case None    => bug!("PlayerScene.add: weapons index ${id} out of range")
                    };
                    ({id = id, gridPos = c, resource = res, weapons = weapon :: Nil}: Spawn));
            List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), scene, spawns)
        }

    /// spawnGrid を中心に N 個の床セルを近い順で選ぶ。`isFloor` で篩い、
    /// 候補不足の場合は呼び出し側が `padCells` で埋める。
    def pickPlayerSpawns(origin: {x = Int32, y = Int32}, n: Int32,
                          layer: TileMapLayer): List[{x = Int32, y = Int32}] =
        let offsets =
                  ({x =  0, y =  0}: {x = Int32, y = Int32})
            ::    ({x =  1, y =  0}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  0}: {x = Int32, y = Int32})
            ::    ({x =  0, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  0, y = -1}: {x = Int32, y = Int32})
            ::    ({x =  1, y =  1}: {x = Int32, y = Int32})
            ::    ({x = -1, y =  1}: {x = Int32, y = Int32})
            ::    ({x =  1, y = -1}: {x = Int32, y = Int32})
            ::    ({x = -1, y = -1}: {x = Int32, y = Int32})
            ::    Nil;
        offsets
            |> List.map(o -> ({x = origin#x + o#x, y = origin#y + o#y}: {x = Int32, y = Int32}))
            |> List.filter(c -> TileMapLayer.isFloor(c, layer))
            |> dedupCells
            |> List.take(n)

    /// `cells` が n 個に満たない場合、不足分を spawnGrid で埋める。
    /// 配置不能なほど狭い部屋への保険（実運用では candidate がほぼ充足する想定）。
    def padCells(cells: List[{x = Int32, y = Int32}], fallback: {x = Int32, y = Int32},
                  n: Int32): List[{x = Int32, y = Int32}] =
        let len = List.length(cells);
        if (len >= n) List.take(n, cells)
        else
            let padding = List.repeat(n - len, fallback);
            List.append(cells, padding)

    /// セル一覧から重複を取り除く（順序保持・先勝ち）
    def dedupCells(cells: List[{x = Int32, y = Int32}]): List[{x = Int32, y = Int32}] =
        List.foldLeft((acc, c) ->
            if (List.exists(p -> p#x == c#x and p#y == c#y, acc)) acc
            else List.append(acc, c :: Nil),
            (Nil: List[{x = Int32, y = Int32}]), cells)

    /// プレイヤー 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    /// ステータス・テクスチャ・フレームは `sp#resource`（UnitResource）から取る。
    def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        let pos: Vec2.Vec2 = {
            x = Int32.toFloat64(sp#gridPos#x) * s + s / 2.0,
            y = Int32.toFloat64(sp#gridPos#y) * s + s / 2.0
        };
        let marker = Marker2D.make(pos);
        let res    = sp#resource;
        let data: Data = {
            id                = sp#id,
            gridPos           = sp#gridPos,
            moveTiles         = res#moveTiles,
            hp                = res#hp,
            waited            = false,
            attackTargetId    = None,
            resource          = res,
            weapons           = sp#weapons,
            selectedWeaponIdx = None
        };
        let sprite = Sprite2D.make(res#sprite#texture, Vec2.zero(), Vec2.one())
                        |> Sprite2D.setHframes(res#sprite#hframes)
                        |> Sprite2D.setVframes(res#sprite#vframes)
                        |> Sprite2D.setFrame(res#sprite#frame)
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addChildAt(MapScene.worldPath(), playerName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))
            |> Scene.addChildAt(playerPath(sp#id), "Sprite",
                                 EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) ロジック — 移動
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（Board）が済ませている前提**。
    /// gridPos を即更新し、見た目は Tween に委ねる。
    pub def moveTo(id: Int32, map: MapSnapshot, target: {x = Int32, y = Int32},
                    marker: Marker2D, data: Data,
                    scene: Scene[NodeTag]): (Marker2D, Data)
                    \ Tween.Scheduler =
        let targetWorld = map#gridToWorld(target);
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        Tween.tweenPosition(playerPath(id), startWorld, targetWorld, slideDuration());
        (marker, {gridPos = target | data})

    /// 指定 id のプレイヤーが現在 tween 中（次の入力を受け付けない状態）か。
    pub def isMoving(id: Int32): Bool \ Tween.Scheduler =
        Tween.Scheduler.isActive(playerPath(id))

    /// 指定 id のプレイヤーを `target` グリッドへ Tween で移動させ、scene の Data も
    /// 同時に更新する。`moveTo` は (Marker2D, Data) を返す形だが、こちらは
    /// physicsProcess の外（AutoMove など）から id だけで呼べるように scene を直接編集する。
    /// `EnemyScene.moveTo` と同じインターフェース。**歩行可否は呼び出し側が確認済み前提**。
    pub def moveToById(id: Int32, target: {x = Int32, y = Int32},
                        map: MapSnapshot,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let startWorld  = Scene.globalPositionAt(playerPath(id), scene);
        let targetWorld = map#gridToWorld(target);
        Tween.tweenPosition(playerPath(id), startWorld, targetWorld, slideDuration());
        mapPlayer(id, d -> {gridPos = target | d}, scene)

    /// 指定 id のプレイヤーを `target` グリッドに **瞬間移動** で戻す。
    /// 進行中の Tween があればキャンセルし、Marker2D の world 位置と Data#gridPos を
    /// 同時に target に揃える。PlayerMoving 中のキャンセルで「選択時の位置」に戻すのに使う。
    pub def snapTo(id: Int32, target: {x = Int32, y = Int32},
                    scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let s = tileSize();
        let world: Vec2.Vec2 = {
            x = Int32.toFloat64(target#x) * s + s / 2.0,
            y = Int32.toFloat64(target#y) * s + s / 2.0
        };
        Tween.Scheduler.cancel(playerPath(id));
        scene
            |> Scene.setGlobalPositionAt(playerPath(id), world)
            |> mapPlayer(id, d -> {gridPos = target | d})

    /// 毎フレーム engine から呼ばれる。**選択中プレイヤーのみ** 動かす。
    /// Game.flix の Node[NodeTag] redef からは PlayerMoving フェーズで
    /// 「id == SelectedPlayer.State.get()」のノードに対してだけ dispatch される。
    pub def physicsProcess(_delta: Duration.Duration,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                if (isMoving(data#id)) (node, scene)
                else
                    let board = BoardQuery.board();
                    let allowed = c -> MoveRangeScene.isInRange(c, scene);
                    // 自分以外の味方セル一覧（停止できない＝通過扱い）
                    let allyCells = getAll(scene)
                        |> List.filter(d -> d#id != data#id)
                        |> List.map(d -> d#gridPos);
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- stepThroughAllies(board, data#gridPos, dir, allowed, allyCells)
                    ) yield {
                        let (newMarker, newData) =
                            moveTo(data#id, board#map, target, marker, data, scene);
                        (EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                         scene)
                    };
                    Option.getWithDefault((node, scene), movement)
            case _ => (node, scene)
        }

    /// 1 ステップ移動の解決。dir 方向に 1 マス進み、その先が味方セルなら自動的に
    /// 「次の停止可能セル」まで滑らせる。これにより味方の上に視覚的に重ならず、
    /// かつ味方を「1 マス分の通行コストで通過」できる挙動になる。
    /// 進めない（壁 / 範囲外 / 敵）場合は None。連続して味方が並んでいるケースでは
    /// 通り抜けて最初の停止可能セルに着く。
    def stepThroughAllies(board: Board, source: {x = Int32, y = Int32},
                            dir: {x = Int32, y = Int32},
                            allowed: {x = Int32, y = Int32} -> Bool,
                            allyCells: List[{x = Int32, y = Int32}]):
                           Option[{x = Int32, y = Int32}] =
        match Board.tryMoveWithRange(board, source, dir, allowed) {
            case None         => None
            case Some(target) =>
                if (isAllyCell(target, allyCells))
                    stepThroughAllies(board, target, dir, allowed, allyCells)
                else Some(target)
        }

    /// 指定セルが「他の味方」のセルに一致するか。
    def isAllyCell(cell: {x = Int32, y = Int32},
                    allyCells: List[{x = Int32, y = Int32}]): Bool =
        List.exists(p -> p#x == cell#x and p#y == cell#y, allyCells)

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右）
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None

    // ────────────────────────────────────────────────────────
    // (E) 状態クエリ・更新
    // ────────────────────────────────────────────────────────

    /// scene に登録されている全プレイヤーの Data を id 昇順で返す。
    pub def getAll(scene: Scene[NodeTag]): List[Data] =
        Scene.preorderPaths(scene)
            |> List.filterMap(path -> match Scene.getState(path, scene) {
                case Some(NodeTag.Player(d)) => Some(d)
                case _                       => None
            })
            |> List.sortBy(d -> d#id)

    /// id を持つプレイヤーの Data を取り出す。未登録なら None。
    pub def get(id: Int32, scene: Scene[NodeTag]): Option[Data] =
        match Scene.getState(playerPath(id), scene) {
            case Some(NodeTag.Player(d)) => Some(d)
            case _                       => None
        }

    /// id を持つプレイヤーの Data を `f` で更新する。Marker2D 位置は触らない。
    pub def mapPlayer(id: Int32, f: Data -> Data,
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(d)) =>
                EngineNode.Marker2DWithState(marker, NodeTag.Player(f(d)))
            case other => other
        }, scene)

    /// 指定セル上の全プレイヤー（waited 含む）の id を返す。
    /// 敵が攻撃する隣接プレイヤーの判定など、waited 含めて見たいときに使う。
    pub def findIdAt(coord: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Option[Int32] =
        getAll(scene)
            |> List.findMap(d ->
                if (d#gridPos#x == coord#x and d#gridPos#y == coord#y) Some(d#id)
                else None)

    /// アクティブなプレイヤーが 1 人でも残っていれば true。
    /// 「全員行動済みなら敵ターンへ」の判定に使う。
    pub def anyActive(scene: Scene[NodeTag]): Bool =
        List.exists(d -> not d#waited, getAll(scene))

    /// プレイヤーを「行動済み」にして sprite を灰色 modulate にする。
    /// PlayerAttack 確定 / スキップ時に呼ばれる。
    pub def setWaited(id: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> mapPlayer(id, d -> {waited = true | d})
            |> setSpriteModulate(id, waitedColor())

    /// 全プレイヤーの waited をクリアし、sprite を白に戻す。
    /// 敵ターン終了後に呼ぶ（次の味方ターン開始）。
    pub def clearAllWaited(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) ->
            sc
                |> mapPlayer(id, d -> {waited = false | d})
                |> setSpriteModulate(id, activeColor()),
            scene, ids)

    /// 指定 id の子 Sprite の modulate を変える内部ヘルパー。
    def setSpriteModulate(id: Int32, color: Color,
                           scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(spritePath(id),
            n -> EngineNode.mapSprite2D(s -> CanvasItem.setModulate(color, s), n),
            scene)

    // ────────────────────────────────────────────────────────
    // (F) ゲームオーバー時のリセット
    // ────────────────────────────────────────────────────────

    /// 現在の全プレイヤーの spawn 情報（id / gridPos / resource / weapons）を抽出する。
    /// `Game.start` で初回 build 直後に呼んで保存する。
    /// 攻撃前に取られる前提でインベントリは無破損の初期値。respawn ではこの値で復元される。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                ({id = d#id, gridPos = d#gridPos, resource = d#resource, weapons = d#weapons}: Spawn))

    /// 既存のプレイヤーを全て scene から取り除き、`spawns` から再構築する。
    /// HP / waited / gridPos を初期値で生成する。
    pub def respawnFromInitial(spawns: List[Spawn],
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        let cleared = List.foldLeft((sc, d) ->
            Scene.removeAt(playerPath(d#id), sc), scene, getAll(scene));
        List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), cleared, spawns)

    // ────────────────────────────────────────────────────────
    // (G) 個別 getter（呼び出し側の便宜）
    // ────────────────────────────────────────────────────────

    pub def getGridPos(id: Int32, scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        match get(id, scene) {
            case Some(d) => d#gridPos
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def getMoveTiles(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => d#moveTiles
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def getHp(id: Int32, scene: Scene[NodeTag]): Int32 =
        match get(id, scene) {
            case Some(d) => d#hp
            case None    => bug!("PlayerScene: player ${id} not found")
        }

    pub def isWaited(id: Int32, scene: Scene[NodeTag]): Bool =
        match get(id, scene) {
            case Some(d) => d#waited
            case None    => false
        }

    /// 指定 id のプレイヤーの武器インベントリを返す。武器が 1 つも無ければ Nil。
    pub def getWeapons(id: Int32, scene: Scene[NodeTag]): List[UnitCatalog.WeaponResource] =
        match get(id, scene) {
            case Some(d) => d#weapons
            case None    => Nil
        }

    /// 指定 id のプレイヤーが攻撃可能か（武器を 1 本以上持っているか）。
    pub def canAttack(id: Int32, scene: Scene[NodeTag]): Bool =
        not List.isEmpty(getWeapons(id, scene))

    /// 武器選択ウィンドウで選ばれた武器 index を Data#selectedWeaponIdx にセットする。
    /// WeaponSelect フェーズの onItemConfirmed から呼ばれる。
    pub def setSelectedWeaponIdx(playerId: Int32, idx: Int32,
                                   scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedWeaponIdx = Some(idx) | d}, scene)

    /// 選択中武器 index をクリアする（攻撃完了後の後始末）。
    pub def clearSelectedWeaponIdx(playerId: Int32,
                                    scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedWeaponIdx = None | d}, scene)

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// `confirmAttackWithWeapon` がこの値を読んで実際の攻撃モーションを開始する。
    pub def setAttackTargetId(playerId: Int32, targetEnemyId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = Some(targetEnemyId) | d}, scene)

    /// `attackTargetId` をクリアする（武器選択をキャンセルしたとき等）。
    pub def clearAttackTargetId(playerId: Int32,
                                  scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    // ────────────────────────────────────────────────────────
    // (H) 体当たり攻撃モーション — AnimationPlayer ベース
    // ────────────────────────────────────────────────────────

    /// 体当たりの片道（origin → target）所要時間。Forward + Returning の合計が
    /// アニメ全長になる。視認性を保つため移動 (16/120) より速めに設定する。
    def attackPhaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒 / 片道

    /// `attack_lunge` アニメーション。
    /// - position track: origin → target → origin の 3 keyframe
    /// - method "attack:hit": 中点（target に重なる瞬間）で発火 → ダメージ適用 + SE 再生
    /// - finished: 攻撃モーション終了 → GameManager が waited 確定 / 次状態へ
    ///
    /// `targetPath` は攻撃側マーカー（PlayerScene なら `playerPath(id)`）。
    /// アニメ全長は 2 phase 分で、method "attack:hit" は phase 1 つぶん経過した時点
    /// （正規化 t = 0.5）で発火する。
    pub def attackLungeAnimation(targetPath: NodePath,
                                  originGrid: {x = Int32, y = Int32},
                                  targetGrid: {x = Int32, y = Int32}):
                                 AnimationPlayer.Animation =
        let phase    = attackPhaseDuration();
        let total    = Duration.add(phase, phase);
        let originW  = cellCenter(originGrid);
        let targetW  = cellCenter(targetGrid);
        let posKeys: List[AnimationPlayer.PosKey] =
            ({time = 0.0, pos = originW}: AnimationPlayer.PosKey) ::
            ({time = 0.5, pos = targetW}: AnimationPlayer.PosKey) ::
            ({time = 1.0, pos = originW}: AnimationPlayer.PosKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetPath,
            prop   = AnimationPlayer.Property.Position(posKeys)
        };
        let methodHit: AnimationPlayer.MethodKey = {
            time = phase,
            name = AnimEvent.tagToString(AnimEvent.Tag.AttackHit)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.AttackLunge),
            length  = total,
            tracks  = track :: Nil,
            methods = methodHit :: Nil
        }

    /// プレイヤー id の体当たり攻撃モーションを開始する。
    /// AnimationPlayer に `attack_lunge` を登録し、`attackTargetId = Some(targetEnemyId)` を
    /// 立てるだけ。中点で `attack:hit` メソッド、終端で finished が GameManager に届き、
    /// それぞれダメージ適用と waited 確定が行われる。
    /// インベントリが空（`weapons = Nil`）のプレイヤーは攻撃に到達してはいけない設計で、
    /// 防御的に no-op する（呼び出し側 = PlayerAttackRangeScene/TurnRules で禁止される）。
    pub def startAttack(id: Int32, targetEnemyId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                if (List.isEmpty(d#weapons)) scene
                else {
                    AnimationPlayer.play(playerPath(id),
                        attackLungeAnimation(playerPath(id), d#gridPos, targetGrid));
                    mapPlayer(id, dd -> {attackTargetId = Some(targetEnemyId) | dd}, scene)
                }
        }

    /// グリッド座標 → セル中心ワールド座標（add 内部の式と同じ）
    def cellCenter(c: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        {x = Int32.toFloat64(c#x) * s + s / 2.0,
         y = Int32.toFloat64(c#y) * s + s / 2.0}

    /// scene 内に攻撃モーション中のプレイヤーが居れば true。
    /// stepEnemyTurn 等の「敵の行動を進めて良いか」のガードに使う将来用の保険。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    /// `attack:hit` メソッド発火時に GameManager から呼ばれるダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵に 1 ダメージ + SE + ログを出す。
    /// HP <= 0 なら EnemyScene.startDeathAnimation を発火する（death_blink 開始）。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameLogger.GameLogger} =
        match get(playerId, scene) {
            case None    => scene
            case Some(d) =>
                match d#attackTargetId {
                    case None         => scene
                    case Some(enemyId) =>
                        AudioStreamPlayer.play("damage");
                        applyDamageToEnemy(playerId, d, enemyId, scene)
                }
        }

    /// `attack_lunge` finished 時に GameManager から呼ばれる。
    /// `attackTargetId` をクリアする。waited 確定 / 次フェーズへの遷移は GameManager の
    /// `commitWaitedAndAdvance` が担当する。
    pub def clearAttackTarget(playerId: Int32,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {attackTargetId = None | d}, scene)

    /// World 直下の `Player_<id>` 形式の NodePath から id を取り出す。
    /// それ以外なら None。AnimationPlayer の event 振り分けに使う
    pub def idFromPath(path: NodePath): Option[Int32] =
        match path {
            case world :: name :: Nil if world == MapScene.worldName() =>
                if (String.startsWith({prefix = "Player_"}, name))
                    String.dropLeft(7, name) |> Int32.fromString
                else None
            case _ => None
        }

    /// 敵 id にダメージを与える。攻撃力は `力(unit#attack) + 選択中武器の攻撃力` で、
    /// `Combat.attackDamage(総合攻撃力, 防御者#defense)` から素ダメージを得て
    /// `Combat.damage` で HP 減算 + 死亡判定。HP <= 0 で死亡演出を開始する。
    /// 使用武器は `player#selectedWeaponIdx`（WeaponMenuScene が事前にセット）の指す
    /// `weapons[idx]`。攻撃成立後にその武器の `durability` を 1 減らし、0 になったら
    /// インベントリから取り除き「P{N} の {武器名} がこわれた」ログを出す。
    /// `selectedWeaponIdx` は最後にクリアする。
    /// ログはスペック準拠で「P{N} → 敵{M} に Xダメージ」 / 撃破時「P{N} → 敵{M} を撃破」。
    /// 命中ロールは v1 では行わず常に命中（hit% は forecast でプレビュー表示するための値）。
    /// インベントリ空 / index 範囲外 / 敵不在ならば防御的に no-op。
    def applyDamageToEnemy(playerId: Int32, player: Data, enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameLogger.GameLogger} =
        // selectedWeaponIdx が None なら 0（先頭）をデフォルトとして扱う
        let idx = Option.getWithDefault(0, player#selectedWeaponIdx);
        match (List.nth(idx, player#weapons), EnemyScene.get(enemyId, scene)) {
            case (None, _)        => scene
            case (_, None)        => scene
            case (Some(weapon), Some(enemy)) =>
                let totalAttack = player#resource#attack + weapon#attack;
                let dmg    = Combat.attackDamage(totalAttack, enemy#resource#defense);
                let result = Combat.damage(hp = enemy#hp, amount = dmg);
                let afterDamage =
                    if (result#isDead) {
                        GameLogger.playerLog("P${playerId} → 敵${enemyId} を撃破");
                        EnemyScene.startDeathAnimation(enemyId, scene)
                    } else {
                        GameLogger.playerLog("P${playerId} → 敵${enemyId} に ${dmg}ダメージ");
                        EnemyScene.mapEnemy(enemyId,
                            enemyData -> {hp = result#newHp | enemyData}, scene)
                    };
                let consumed = Weapon.consume(weapon);
                let newWeapons = match consumed {
                    case Some(updated) =>
                        // 同じ index の要素だけ更新後の値に差し替える
                        List.mapWithIndex(i -> w -> if (i == idx) updated else w, player#weapons)
                    case None =>
                        // 壊れた → index 位置の要素を取り除く
                        List.mapWithIndex(i -> w -> (i, w), player#weapons)
                            |> List.filter(pair -> let (i, _) = pair; i != idx)
                            |> List.map(pair -> let (_, w) = pair; w)
                };
                if (Option.isEmpty(consumed))
                    GameLogger.playerLog("P${playerId} の ${weapon#name} がこわれた")
                else ();
                mapPlayer(playerId,
                    d -> {weapons = newWeapons, selectedWeaponIdx = None | d}, afterDamage)
        }
}
