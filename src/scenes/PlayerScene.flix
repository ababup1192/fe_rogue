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
/// 呼び出し側（BoardLogic / MoveRangeScene）が moveTo を呼ぶ前に済ませている前提**。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態。
    /// id: 0..partySize-1 の連番。"Player_<id>" ノード名と一致する。
    /// gridPos: 盤面上の駒の論理位置。moveTo で即座に更新される。
    /// moveTiles: 1 ターンに移動できるマス数（FE の「移動力」相当）。
    /// hp: 残り体力。0 になるとゲームオーバー（同マップ初期化）。
    /// waited: 行動済みフラグ。true なら灰色表示・選択不可。
    /// attacking: 体当たり攻撃モーション中なら Some(...)。tickAttacks が状態を進める。
    pub type alias Data = {
        id        = Int32,
        gridPos   = Vec2.Vec2i,
        moveTiles = Int32,
        hp        = Int32,
        waited    = Bool,
        attacking = Option[AttackAnim.State]
    }

    /// スポーン時の中間表現。`add` で配置するセルの id/gridPos を持つ。
    /// 初期 spawn のスナップショット（ゲームオーバー時の復元用）にも使う。
    pub type alias Spawn = {
        id      = Int32,
        gridPos = Vec2.Vec2i
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// プレイヤースプライトのテクスチャ名（Main.flix の textureManifest と整合）
    def textureName(): String = "character_sheet"

    /// `character_sheet_grid_16.png` のグリッド分割（5 列 × 2 行）。
    def hframes(): Int32 = 5
    def vframes(): Int32 = 2

    /// 各プレイヤーの sprite frame。視覚的に区別できるよう id ごとに変える。
    /// (id 0 = frame 0, id 1 = frame 1, id 2 = frame 2)
    def spriteFrameFor(id: Int32): Int32 = id

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える。
    def tileSize(): Float64 = 16.0

    /// プレイヤー Sprite の zIndex（Player は前面に立つ）。EnemyScene と同じ 10。
    def spriteZIndex(): Int32 = 10

    /// 1 マス分のスライド時間（秒）
    def slideDuration(): Float64 = 16.0 / 120.0

    /// プレイヤー初期の移動力（マス）
    pub def defaultMoveTiles(): Int32 = 5

    /// プレイヤー初期 HP
    pub def defaultHp(): Int32 = 10

    /// パーティ人数。spawn と reset で参照する。
    pub def partySize(): Int32 = 3

    /// `waited = true` 時の sprite modulate（薄い灰色）。
    /// CanvasItem.setModulate で sprite の RGB を乗算する。
    def waitedColor(): Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32}

    /// `waited = false` 時の sprite modulate（白 = 元色）。
    def activeColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// "Player_2" のようなトップレベルノード名。
    pub def playerName(id: Int32): String = "Player_${id}"

    /// "Player_2" 1 つだけの NodePath。
    pub def playerPath(id: Int32): NodePath = playerName(id) :: Nil

    /// Player_<id> の子 Sprite ノードへのパス。modulate 変更や将来の alpha tween に使う。
    pub def spritePath(id: Int32): NodePath = playerName(id) :: "Sprite" :: Nil

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene が登録済みの scene にプレイヤー全員 (`partySize()` 名) を追加する。
    /// 0 番目は MapScene が記録した spawnGrid に、残りはその近傍の床セルに配置する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let spawnGrid = MapScene.getSpawnGrid(scene);
        let layer     = MapScene.getMapLayer(scene);
        let cells     = pickPlayerSpawns(spawnGrid, partySize(), layer);
        // cells が partySize に満たない場合（極端に狭い anchor）は重複セルを許容して埋める
        let padded    = padCells(cells, spawnGrid, partySize());
        let spawns: List[Spawn] = List.zip(List.range(0, partySize()), padded)
            |> List.map(t -> { let (id, c) = t; ({id = id, gridPos = c}: Spawn) });
        List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), scene, spawns)

    /// spawnGrid を中心に N 個の床セルを近い順で選ぶ。`isFloor` で篩い、
    /// 候補不足の場合は呼び出し側が `padCells` で埋める。
    def pickPlayerSpawns(origin: Vec2.Vec2i, n: Int32,
                          layer: TileMapLayer): List[Vec2.Vec2i] =
        let offsets =
                  ({x =  0, y =  0}: Vec2.Vec2i)
            ::    ({x =  1, y =  0}: Vec2.Vec2i)
            ::    ({x = -1, y =  0}: Vec2.Vec2i)
            ::    ({x =  0, y =  1}: Vec2.Vec2i)
            ::    ({x =  0, y = -1}: Vec2.Vec2i)
            ::    ({x =  1, y =  1}: Vec2.Vec2i)
            ::    ({x = -1, y =  1}: Vec2.Vec2i)
            ::    ({x =  1, y = -1}: Vec2.Vec2i)
            ::    ({x = -1, y = -1}: Vec2.Vec2i)
            ::    Nil;
        offsets
            |> List.map(o -> ({x = origin#x + o#x, y = origin#y + o#y}: Vec2.Vec2i))
            |> List.filter(c -> TileMapLayer.isFloor(c, layer))
            |> dedupCells
            |> List.take(n)

    /// `cells` が n 個に満たない場合、不足分を spawnGrid で埋める。
    /// 配置不能なほど狭い部屋への保険（実運用では candidate がほぼ充足する想定）。
    def padCells(cells: List[Vec2.Vec2i], fallback: Vec2.Vec2i,
                  n: Int32): List[Vec2.Vec2i] =
        let len = List.length(cells);
        if (len >= n) List.take(n, cells)
        else
            let padding = List.repeat(n - len, fallback);
            List.append(cells, padding)

    /// セル一覧から重複を取り除く（順序保持・先勝ち）
    def dedupCells(cells: List[Vec2.Vec2i]): List[Vec2.Vec2i] =
        List.foldLeft((acc, c) ->
            if (List.exists(p -> p#x == c#x and p#y == c#y, acc)) acc
            else List.append(acc, c :: Nil),
            (Nil: List[Vec2.Vec2i]), cells)

    /// プレイヤー 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        let pos: Vec2.Vec2 = {
            x = Int32.toFloat64(sp#gridPos#x) * s + s / 2.0,
            y = Int32.toFloat64(sp#gridPos#y) * s + s / 2.0
        };
        let marker = Marker2D.make(pos);
        let data: Data = {
            id        = sp#id,
            gridPos   = sp#gridPos,
            moveTiles = defaultMoveTiles(),
            hp        = defaultHp(),
            waited    = false,
            attacking = None
        };
        let sprite = Sprite2D.make(textureName(), Vec2.zero(), Vec2.one())
                        |> Sprite2D.setHframes(hframes())
                        |> Sprite2D.setVframes(vframes())
                        |> Sprite2D.setFrame(spriteFrameFor(sp#id))
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addNode(playerName(sp#id),
                              EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))
            |> Scene.addChild(playerName(sp#id), "Sprite",
                               EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) ロジック — 移動
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（BoardLogic）が済ませている前提**。
    /// gridPos を即更新し、見た目は Tween に委ねる。
    pub def moveTo(id: Int32, map: MapSnapshot, target: Vec2.Vec2i,
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

    /// 指定 id のプレイヤーを `target` グリッドに **瞬間移動** で戻す。
    /// 進行中の Tween があればキャンセルし、Marker2D の world 位置と Data#gridPos を
    /// 同時に target に揃える。PlayerMoving 中のキャンセルで「選択時の位置」に戻すのに使う。
    pub def snapTo(id: Int32, target: Vec2.Vec2i,
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
    pub def physicsProcess(_delta: Float64,
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
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- BoardLogic.tryMoveWithRange(board, data#gridPos,
                                                                dir, allowed)
                    ) yield {
                        let (newMarker, newData) =
                            moveTo(data#id, board#map, target, marker, data, scene);
                        (EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                         scene)
                    };
                    Option.getWithDefault((node, scene), movement)
            case _ => (node, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右）
    def readHeldDirection(): Option[Vec2.Vec2i] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2.upI())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2.downI())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2.leftI())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2.rightI())
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

    /// 指定セル上に居る **アクティブな（waited = false）** プレイヤーの id を返す。
    /// PlayerCursor で「カーソルが操作可能な味方の上にあるか」を判定するのに使う。
    pub def findActiveIdAt(coord: Vec2.Vec2i,
                            scene: Scene[NodeTag]): Option[Int32] =
        getAll(scene)
            |> List.findMap(d ->
                if (not d#waited
                    and d#gridPos#x == coord#x
                    and d#gridPos#y == coord#y) Some(d#id)
                else None)

    /// 指定セル上の全プレイヤー（waited 含む）の id を返す。
    /// 敵が攻撃する隣接プレイヤーの判定など、waited 含めて見たいときに使う。
    pub def findIdAt(coord: Vec2.Vec2i,
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

    /// 現在の全プレイヤーの spawn 情報（id / gridPos）を抽出する。
    /// `Game.start` で初回 build 直後に呼んで保存する。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d -> ({id = d#id, gridPos = d#gridPos}: Spawn))

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

    pub def getGridPos(id: Int32, scene: Scene[NodeTag]): Vec2.Vec2i =
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

    // ────────────────────────────────────────────────────────
    // (H) 体当たり攻撃モーション
    // ────────────────────────────────────────────────────────

    /// プレイヤー id の体当たり攻撃モーションを開始する。
    /// `targetGrid` は攻撃対象（敵）のグリッド位置、`targetEnemyId` はその id。
    /// Forward 用の Tween を登録し、`attacking = Some({Forward, ...})` を立てる。
    /// HP 適用 / damage.ogg 再生は **重なる瞬間（Forward 完了時）** に `tickAttacks`
    /// が行うのでここでは呼ばない。
    pub def startAttack(id: Int32, targetEnemyId: Int32,
                         targetGrid: Vec2.Vec2i,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                let originGrid = d#gridPos;
                let startWorld = cellCenter(originGrid);
                let endWorld   = cellCenter(targetGrid);
                Tween.tweenPosition(playerPath(id), startWorld, endWorld,
                                     AttackAnim.phaseDuration());
                let s: AttackAnim.State = {
                    phase     = AttackAnim.Phase.Forward,
                    targetId  = targetEnemyId,
                    targetPos = targetGrid,
                    originPos = originGrid
                };
                mapPlayer(id, dd -> {attacking = Some(s) | dd}, scene)
        }

    /// グリッド座標 → セル中心ワールド座標（add 内部の式と同じ）
    def cellCenter(c: Vec2.Vec2i): Vec2.Vec2 =
        let s = tileSize();
        {x = Int32.toFloat64(c#x) * s + s / 2.0,
         y = Int32.toFloat64(c#y) * s + s / 2.0}

    /// scene 内に **攻撃モーション中** のプレイヤーが居れば true。
    /// stepEnemyTurn 等の「敵の行動を進めて良いか」のガードに使う想定（プレイヤー攻撃は
    /// 普段プレイヤーターン中なので、この関数は将来の混在シナリオ用の保険）。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attacking), getAll(scene))

    /// プレイヤー攻撃モーションを毎フレーム進める。`gameLoop` が `Tween.tickAll` 直後に呼ぶ。
    /// 戻り値は (scene, completed) のタプルで、completed は「**Returning が完了した
    /// プレイヤー**」の id 一覧。呼び出し側 (Game.flix) はこれを受けて
    /// commitWaitedAndAdvance などを発火する。
    pub def tickAttacks(scene: Scene[NodeTag]): (Scene[NodeTag], List[Int32])
            \ {Tween.Scheduler, GameEngine.Audio, GameLogger.GameLogger} =
        let attackingIds = getAll(scene)
            |> List.filterMap(d -> match d#attacking {
                case Some(s) => Some((d#id, s))
                case None    => None
            });
        List.foldLeft((acc, entry) -> {
            let (sc, completed) = acc;
            let (id, s) = entry;
            if (Tween.Scheduler.isActive(playerPath(id))) (sc, completed)
            else
                let (next, doneId) = advanceAttack(id, s, sc);
                (next, List.append(completed, doneId))
        }, (scene, (Nil: List[Int32])), attackingIds)

    /// 1 体ぶんの攻撃モーションを 1 フェーズ進める内部関数。
    /// 戻り値は (新 scene, Returning 完了したなら [id] / それ以外 [])。
    def advanceAttack(id: Int32, s: AttackAnim.State,
                       scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32])
            \ {Tween.Scheduler, GameEngine.Audio, GameLogger.GameLogger} =
        match s#phase {
            case AttackAnim.Phase.Forward =>
                // 重なった瞬間: damage.ogg を鳴らし、対象敵に 1 ダメージを適用
                AudioStreamPlayer.play("damage");
                let targetId = s#targetId;
                let damaged = applyDamageToEnemy(targetId, scene);
                // Returning tween を開始（target → origin）
                let startWorld = cellCenter(s#targetPos);
                let endWorld   = cellCenter(s#originPos);
                Tween.tweenPosition(playerPath(id), startWorld, endWorld,
                                     AttackAnim.phaseDuration());
                let s2: AttackAnim.State = {phase = AttackAnim.Phase.Returning | s};
                let next = mapPlayer(id, d -> {attacking = Some(s2) | d}, damaged);
                (next, Nil)
            case AttackAnim.Phase.Returning =>
                // Returning 完了 → attacking をクリアして「完了 id」として返す
                let cleared = mapPlayer(id, d -> {attacking = None | d}, scene);
                (cleared, id :: Nil)
        }

    /// 敵 id にダメージ 1 を与える。HP <= 0 で死亡演出を開始（bonus は death animation
    /// 終了時に EnemyScene.tickDeaths が再生する）。
    /// ログは「敵N にダメージ 残りHPM」を重なりタイミングで残す。
    def applyDamageToEnemy(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        match EnemyScene.get(enemyId, scene) {
            case None    => scene
            case Some(e) =>
                let newHp = e#hp - 1;
                GameLogger.GameLogger.playerLog("敵${enemyId}にダメージ 残りHP${newHp}");
                if (newHp <= 0) EnemyScene.startDeathAnimation(enemyId, scene)
                else EnemyScene.mapEnemy(enemyId, d -> {hp = newHp | d}, scene)
        }
}
