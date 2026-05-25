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

    /// ItemMenu で選択中のアイテムの種別と inventory 内 index。
    /// 武器と杖は別リストに格納されているため、どちらに属するかを ADT で区別する。
    pub enum ItemKind with Eq, ToString {
        case Weapon(Int32)   // weapons リスト上の index
        case Staff(Int32)    // staves リスト上の index
    }

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
    /// weapons: 装備中の武器インベントリ。先頭が「装備中」武器で、攻撃時に自動使用される。
    ///   `equipWeapon` で他の武器を先頭に持ってくると装備が切り替わる。
    ///   攻撃で耐久度が 1 減り、0 になったら weapons から取り除かれる（武器が壊れた）。
    /// staves: 杖のインベントリ。攻撃には使わず、ItemMenu の「使う」で発動する。
    ///   発動で耐久度が 1 減り、0 になったら staves から取り除かれる。
    /// selectedItem: ItemMenu で選択中のアイテム（武器 or 杖）。
    ///   一覧画面で選んだ瞬間にセット、サブメニュー（使う/装備/捨てる）で確定後にクリアされる。
    pub type alias Data = {
        id                 = Int32,
        gridPos            = {x = Int32, y = Int32},
        moveTiles          = Int32,
        hp                 = Int32,
        waited             = Bool,
        attackTargetId     = Option[Int32],
        resource           = UnitCatalog.UnitResource,
        weapons            = List[UnitCatalog.WeaponResource],
        staves             = List[Staff.StaffResource],
        selectedItem       = Option[ItemKind],
        // AutoMove 中にこの味方が当ターン何マス進んだか。
        // moveTiles に達したら `waited = true` にして次の味方に交代する。
        // プレイヤーターン開始時に 0 リセット。
        moveStepsTaken     = Int32
    }

    /// 味方パーティの「現フレーム状態」を Scene を介さずに読み取る effect。
    ///
    /// 非 driver / 非 data Scene (HUD / Camera / Menu / Overlay) は `PlayerScene` モジュールを
    /// 直接タイプせず、この effect 経由で味方データを得る。これにより一方向の依存グラフを
    /// 保ち、テストで handler を差し替えてスタブできる。
    ///
    /// 設計は `BoardQuery` (Board.flix:34) と同じ:
    ///   - 読み取り専用、Ref を持たない
    ///   - handler は Game.start で `Ref.get(sceneRef)` から最新 scene を読んで `PlayerScene.*`
    ///     をそのまま呼び返す inline handler
    ///   - 毎フレーム gameLoop が sceneRef を更新するため、各 op は最新値を返す
    ///
    /// driver Scene (AutoMoveScene / EnemyTurnDriverScene) と data Scene 同士の相互参照は
    /// orchestrator として現状の直接呼び出しを許容する (本 effect は経由しない)。
    pub eff PartyQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
        def getGridPos(id: Int32): {x = Int32, y = Int32}
        def getMoveTiles(id: Int32): Int32
    }

    /// スポーン時の中間表現。`add` で配置するセルの id/gridPos に加え、
    /// どのユニット定義（UnitResource）でセットアップするかも持つ。
    /// 初期 spawn のスナップショット（ゲームオーバー時の復元用）にも使う。
    /// `weapons` / `staves` は初期インベントリ（壊れる前の固定リスト）で、
    /// respawn 時にこの値で復元する。
    pub type alias Spawn = {
        id       = Int32,
        gridPos  = {x = Int32, y = Int32},
        resource = UnitCatalog.UnitResource,
        weapons  = List[UnitCatalog.WeaponResource],
        staves   = List[Staff.StaffResource]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

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
    /// 各プレイヤーには `players` プールのリスト順で `UnitResource` を割り当て、
    /// その `initialWeapon` id から weapons カタログを引いて `WeaponResource` を装備させる
    /// （1 プレイヤー = 1 武器）。`initialStaves` の各 id は `staffCatalog` から
    /// `StaffResource` を引いて初期インベントリに加える。未定義 id は起動時 typo として
    /// 即 panic する。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                  staffCatalog: Staff.StaffCatalog,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        let party        = UnitCatalog.pool("players", catalog);
        let n            = List.length(party);
        let spawnGrid    = MapScene.getSpawnGrid(scene);
        let layer        = MapScene.getMapLayer(scene);
        let cells        = pickPlayerSpawns(spawnGrid, n, layer);
        // cells が n に満たない場合（極端に狭い anchor）は重複セルを許容して埋める
        let padded       = padCells(cells, spawnGrid, n);
        let spawns: List[Spawn] = padded
            |> List.mapWithIndex(id -> c ->
                let res = match List.nth(id, party) {
                    case Some(r) => r
                    case None    => bug!("PlayerScene.add: party index ${id} out of range")
                };
                let weapon = UnitCatalog.lookupWeapon(res#initialWeapon, catalog);
                let staves = List.map(staffId -> Staff.lookup(staffId, staffCatalog),
                                       res#initialStaves);
                ({id = id, gridPos = c, resource = res,
                   weapons = weapon :: Nil, staves = staves}: Spawn));
        List.foldLeft((sc, sp) -> addOnePlayer(sp, sc), scene, spawns)

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
    /// pub: `PlayerScene.add` の party 追加ループから呼ばれる本体内部ロジック。
    /// テストでも catalog からの Spawn 構築 → addOnePlayer の本体経路を流用する。
    pub def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pos = MapScene.cellCenter(sp#gridPos);
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
            staves            = sp#staves,
            selectedItem      = None,
            moveStepsTaken    = 0
        };
        let sprite = Sprite2D.make(res#sprite#texture, res#sprite#offset, Vec2.one())
                        |> Sprite2D.setHframes(res#sprite#hframes)
                        |> Sprite2D.setVframes(res#sprite#vframes)
                        |> Sprite2D.setFrame(res#sprite#frame)
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addChildAt(MapScene.worldPath(), playerName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))
            |> Scene.addChildAt(playerPath(sp#id), "Sprite",
                                 EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> UnitHPBarScene.attach(playerPath(sp#id), res#hp, UnitHPBarScene.BarPosition.Above)

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
        let world = MapScene.cellCenter(target);
        Tween.Scheduler.cancel(playerPath(id));
        scene
            |> Scene.setGlobalPositionAt(playerPath(id), world)
            |> mapPlayer(id, d -> {gridPos = target | d})

    /// PlayerCursor + Z で味方マスを選択した瞬間の遷移: 選択中味方を SelectedPlayer に
    /// 記録し、PlayerMoving に進む。
    /// overlay (MoveRange / MoveAttackRange / EnemyRange) と Cursor の整理は
    /// `PhaseTransitions.enterPlayerMoving` が担当する (この関数は SelectedPlayer 更新だけ)。
    pub def beginSelection(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        SelectedPlayer.State.put({
            id     = Some(playerId),
            origin = Some(getGridPos(playerId, scene))
        });
        PhaseTransitions.enterPlayerMoving(scene)

    /// PlayerMoving + X: 選択駒を origin に瞬間移動で戻し、選択解除して PlayerCursor に戻す。
    /// 「キャンセル → 再選択の繰り返しで実質ターン制限なしの自由移動」を防ぐ FE 流。
    /// overlay / cursor の片付けは `PhaseTransitions.enterPlayerCursor` が担当。
    pub def cancelSelection(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PartyQuery} =
        let selection = SelectedPlayer.State.get();
        let restored = match (selection#id, selection#origin) {
            case (Some(id), Some(origin)) => snapTo(id, origin, scene)
            case _                         => scene
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        PhaseTransitions.enterPlayerCursor(restored)

    /// ActionMenu「こうげき」確定で呼ばれる: 攻撃ターゲット選択フェーズへ。
    /// overlay / cursor 整理は `PhaseTransitions.enterPlayerAttack` が担当。
    pub def enterAttackPhase(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PartyQuery, EnemyScene.RosterQuery} =
        PhaseTransitions.enterPlayerAttack(scene)

    /// 各 Player ノードの毎フレーム process。AnimationPlayer から自分宛 (`playerPath(id)`)
    /// の signal だけ pull し、attack:hit (中点) / attack_lunge (完了) に反応する。
    /// Game.flix の `Node[NodeTag] instance` の process redef から全 Player に dispatch
    /// される (per-node)。owner 完全一致なので他 Player の signal は取りこぼさない。
    /// 「Sceneのライフサイクルで処理が完結」する Godot 流の per-node signal モデル。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameEngine.Audio, GameEngine.Game,
                        GameLogger.GameLogger,
                        EnemyTurn.Queue, TurnPhase.State,
                        SelectedPlayer.State, Pacing.State} =
        match idFromPath(path) {
            case None           => (node, scene)
            case Some(playerId) =>
                let bundle = AnimationPlayer.Scheduler.drainSignals(playerPath(playerId));
                let afterMethods = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.AttackHit) => onAttackHit(playerId, sc)
                        case _                              => sc
                    },
                    scene, bundle#methods);
                let afterFinished = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.AttackLunge) => onAttackLungeDone(playerId, sc)
                        case _                                => sc
                    },
                    afterMethods, bundle#finished);
                // signal handler が scene 経由で self (Player ノード) を更新する可能性が
                // あるため、最新ノードを取り直して返す (古い node で打ち消されないように)
                match Scene.getEngineNode(path, afterFinished) {
                    case Some(latest) => (latest, afterFinished)
                    case None         => (node, afterFinished)
                }
        }

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
                    // 方向キー押下で 1 セルだけ進む。味方セルへ進入可能 (重なる)、
                    // ただし重なっている間は Z で行動決定できない (`Board.isOverlappingAlly`
                    // で `TurnRules` がブロック)。「味方を超えて自動スライド」する旧
                    // `stepThroughAllies` 挙動は廃止。
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- Board.tryMoveWithRange(board, data#gridPos, dir, allowed)
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

    /// 指定プレイヤーの上下左右 1 マスに居る他味方を返す（自分は含まない）。
    /// 「こうかん」コマンドや将来の隣接判定 (例: 助太刀) の出現条件として使う。
    /// 斜め (例: (4,4) と (5,5)) は含まない。waited フィルタはここではせず、
    /// 全味方を対象にする (waited 駒との交換可否は呼び出し側で判定)。
    pub def adjacentAllies(player: Data): List[Data] \ PartyQuery =
        PartyQuery.getAll()
            |> List.filter(other ->
                other#id != player#id
                and Weapon.manhattan(player#gridPos, other#gridPos) == 1)

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

    /// アクティブ（waited でない）味方のうち、id 最小のものを返す。誰も居なければ None。
    /// `commitWaitedAndAdvance` の直後にカーソルを次に動ける駒へ飛ばす用途で使う
    /// (`PartyQuery` 経由だとフレーム冒頭 snapshot を読むため stale)。
    pub def firstActive(scene: Scene[NodeTag]): Option[Data] =
        getAll(scene)
            |> List.filter(d -> not d#waited)
            |> List.sortBy(d -> d#id)
            |> List.head

    /// 敵攻撃で HP=0 になったプレイヤーを scene から取り除く。`killed` は
    /// `EnemyScene.applyAttackHit` が返した死亡 id のリスト (通常 1 要素)。
    /// 選択中プレイヤーが含まれていれば (反撃で死亡したケース) 選択も解除する。
    /// 全員脱落していれば `CustomEffects.GameOverRequest.request` を emit して、
    /// handler 側でマップ・配置をフルリビルドする。
    pub def removeDeadAndCheckGameOver(killed: List[Int32],
                                         scene: Scene[NodeTag]):
            Scene[NodeTag] \ {CustomEffects.GameOverRequest, SelectedPlayer.State} =
        if (List.isEmpty(killed)) scene
        else {
            let removed = List.foldLeft(
                (sc, id) -> Scene.removeAt(playerPath(id), sc),
                scene, killed);
            let selectedKilled = match SelectedPlayer.State.get()#id {
                case Some(id) => List.exists(k -> k == id, killed)
                case None     => false
            };
            if (selectedKilled)
                SelectedPlayer.State.put(SelectedPlayer.cleared())
            else ();
            if (List.isEmpty(getAll(removed)))
                CustomEffects.GameOverRequest.request(removed)
            else removed
        }

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

    /// AutoMove で消費した移動歩数を記録するための setter。
    pub def setMoveStepsTaken(id: Int32, steps: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(id, d -> {moveStepsTaken = steps | d}, scene)

    /// 全プレイヤーの moveStepsTaken を 0 にリセットする。
    /// プレイヤーターン開始時 / AutoMove キャンセル時に呼ぶ。
    pub def resetAllMoveStepsTaken(scene: Scene[NodeTag]): Scene[NodeTag] =
        let ids = getAll(scene) |> List.map(d -> d#id);
        List.foldLeft((sc, id) -> mapPlayer(id, d -> {moveStepsTaken = 0 | d}, sc),
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

    /// 現在の全プレイヤーの spawn 情報（id / gridPos / resource / weapons / staves）を抽出する。
    /// `Game.start` で初回 build 直後に呼んで保存する。
    /// 攻撃前に取られる前提でインベントリは無破損の初期値。respawn ではこの値で復元される。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                ({id = d#id, gridPos = d#gridPos, resource = d#resource,
                   weapons = d#weapons, staves = d#staves}: Spawn))

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

    /// 指定 id のプレイヤーの杖インベントリを返す（無ければ空）。
    pub def getStaves(id: Int32, scene: Scene[NodeTag]): List[Staff.StaffResource] =
        match get(id, scene) {
            case Some(d) => d#staves
            case None    => Nil
        }

    /// ItemMenu で選ばれたアイテム（武器 or 杖）の種別と index を Data#selectedItem にセットする。
    /// `ItemActionSelect` フェーズに進むときに ItemMenuScene から呼ばれる。
    pub def setSelectedItem(playerId: Int32, item: ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = Some(item) | d}, scene)

    /// 選択中アイテムをクリアする（サブメニュー確定後の後始末）。
    pub def clearSelectedItem(playerId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {selectedItem = None | d}, scene)

    /// 指定 idx の武器を装備（= weapons リストの先頭に移動）。
    /// 既に先頭なら何もしない。範囲外なら no-op。
    /// 「こうげき」は常に `weapons.head` を使うため、これで装備切り替えが反映される。
    pub def equipWeapon(playerId: Int32, idx: Int32,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {weapons = moveToHead(idx, d#weapons) | d}, scene)

    /// 指定 idx の武器をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropWeapon(playerId: Int32, idx: Int32,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {weapons = removeAt(idx, d#weapons) | d}, scene)

    /// 指定 idx の杖をインベントリから削除（捨てる）。範囲外なら no-op。
    pub def dropStaff(playerId: Int32, idx: Int32,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayer(playerId, d -> {staves = removeAt(idx, d#staves) | d}, scene)

    /// 2 プレイヤー間でインベントリのアイテム 1 個ずつを交換する純粋関数。
    ///   - 双方が実体アイテム持ちなら相互スワップ（ともに元の場所から消え、相手の末尾に追加）
    ///   - 相手が `None` (= 空スロット) のときは一方向 transfer
    ///     (自分のアイテムが消えて相手の対応リスト末尾に積まれる)
    /// 種別 (武器/杖) は元のままなので、武器 ↔ 杖の交換も自動的に両者の対応リストへ振り分けられる。
    /// `selfKind` が範囲外 / `selfId` が存在しない場合は防御的に no-op。
    /// 「こうかん」確定 (Phase 4) で TradeMenuScene から呼ばれる。
    ///
    /// 引数 (record-style):
    ///   - `selfId`      : 必ず実体アイテムを渡す側のプレイヤー id
    ///   - `selfKind`    : self 側で渡すアイテム種別 (Weapon idx / Staff idx)
    ///   - `partnerId`   : もう一方のプレイヤー id
    ///   - `partnerKind` : Some なら双方向 swap、None なら self 側からの片方向 transfer
    pub def swapItem(args: {selfId = Int32, selfKind = ItemKind,
                              partnerId = Int32,
                              partnerKind = Option[ItemKind]},
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        let selfId      = args#selfId;
        let selfKind    = args#selfKind;
        let partnerId   = args#partnerId;
        let partnerKind = args#partnerKind;
        // 1. 両者のアイテム実体を「現在の scene」から抜き出す (まだ削除はしない)
        let selfItemOpt = getInventoryItem(selfId, selfKind, scene);
        let partnerItemOpt = partnerKind
            |> Option.flatMap(pk -> getInventoryItem(partnerId, pk, scene));
        // 2. self 側に実体が無ければ no-op (selfKind = 空スロットは仕様外)
        selfItemOpt
            |> Option.map(selfItem -> scene
                |> removeInventoryItem(selfId, selfKind)
                |> removeOptInventoryItem(partnerId, partnerKind)
                |> addOptInventoryItem(selfId, partnerItemOpt)
                |> addInventoryItem(partnerId, selfItem))
            |> Option.getWithDefault(scene)

    /// 指定 player の (kind = Weapon(idx) | Staff(idx)) のアイテム実体を返す。
    /// player が居ない / index が範囲外なら None
    /// (getWeapons / getStaves が居ない player に対し Nil を返すので、その経由で None)。
    /// 戻り値は `ItemScene.GroundItemKind` を流用 (= 「インベントリ可能なアイテム値」)。
    def getInventoryItem(playerId: Int32, kind: ItemKind, scene: Scene[NodeTag]):
            Option[ItemScene.GroundItemKind] =
        match kind {
            case ItemKind.Weapon(idx) =>
                List.nth(idx, getWeapons(playerId, scene))
                    |> Option.map(w -> ItemScene.GroundItemKind.WeaponItem(w))
            case ItemKind.Staff(idx) =>
                List.nth(idx, getStaves(playerId, scene))
                    |> Option.map(s -> ItemScene.GroundItemKind.StaffItem(s))
        }

    /// 指定 player の `kind` のアイテムをインベントリから取り除く。
    /// `dropWeapon` / `dropStaff` のディスパッチ統合版。
    def removeInventoryItem(playerId: Int32, kind: ItemKind,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        match kind {
            case ItemKind.Weapon(idx) => dropWeapon(playerId, idx, scene)
            case ItemKind.Staff(idx)  => dropStaff(playerId, idx, scene)
        }

    /// `partnerKind = None` (= 空スロット相手) の場合は no-op、Some なら removeInventoryItem。
    def removeOptInventoryItem(playerId: Int32, kindOpt: Option[ItemKind],
                                 scene: Scene[NodeTag]): Scene[NodeTag] =
        kindOpt
            |> Option.map(k -> removeInventoryItem(playerId, k, scene))
            |> Option.getWithDefault(scene)

    /// 指定 player のインベントリに `item` を追加 (武器なら weapons 末尾、杖なら staves 末尾)。
    /// `ActionMenuScene.addPickedItem` と同じ追加ルール (ログを出さない版)。
    def addInventoryItem(playerId: Int32, item: ItemScene.GroundItemKind,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        match item {
            case ItemScene.GroundItemKind.WeaponItem(weapon) =>
                mapPlayer(playerId,
                    d -> {weapons = List.append(d#weapons, weapon :: Nil) | d}, scene)
            case ItemScene.GroundItemKind.StaffItem(staff)   =>
                mapPlayer(playerId,
                    d -> {staves = List.append(d#staves, staff :: Nil) | d}, scene)
        }

    /// `optItem = None` のときは no-op、Some なら addInventoryItem。
    def addOptInventoryItem(playerId: Int32, optItem: Option[ItemScene.GroundItemKind],
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        optItem
            |> Option.map(item -> addInventoryItem(playerId, item, scene))
            |> Option.getWithDefault(scene)

    /// List の `idx` 番目の要素を先頭に移動する。範囲外なら元のリストをそのまま返す。
    /// `[a, b, c, d]` の idx=2 を頭に → `[c, a, b, d]`。
    def moveToHead(idx: Int32, list: List[a]): List[a] =
        match List.nth(idx, list) {
            case None    => list
            case Some(x) => x :: removeAt(idx, list)
        }

    /// List から `idx` 番目の要素を取り除く。範囲外なら元のリストをそのまま返す。
    def removeAt(idx: Int32, list: List[a]): List[a] =
        List.zipWithIndex(list)
            |> List.filter(pair -> let (i, _) = pair; i != idx)
            |> List.map(pair -> let (_, x) = pair; x)

    /// 攻撃ターゲットの敵 id を Data#attackTargetId に記録する。
    /// 武器選択ウィンドウを開く前に GameManager から呼ばれ、ウィンドウ確定後の
    /// `WeaponMenuScene.onWeaponConfirmed` 経由でフェーズが AttackForecast に進み、
    /// `BattlePanelScene.confirm` がこの値を読んで実際の攻撃モーションを開始する。
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
        let originW  = MapScene.cellCenter(originGrid);
        let targetW  = MapScene.cellCenter(targetGrid);
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


    /// scene 内に攻撃モーション中のプレイヤーが居れば true。
    /// stepEnemyTurn 等の「敵の行動を進めて良いか」のガードに使う将来用の保険。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    /// `attack:hit` メソッド発火時に GameManager から呼ばれるダメージ適用。
    /// 当該 player の `attackTargetId` を読み、対応する敵に 1 ダメージ + SE + ログを出す。
    /// HP <= 0 なら EnemyScene.startDeathAnimation を発火する（death_blink 開始）。
    pub def applyAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game,
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

    /// PlayerAttack / WeaponSelect / ActionMenu「たいき」を抜けるときの共通処理:
    ///   1) 選択中駒を waited に (灰色 modulate)
    ///   2) 選択クリア
    ///   3) 残ったアクティブが居れば PlayerCursor に戻り、次セレクト準備
    ///      居なければ `EnemyTurnDriverScene.beginTurn` で敵ターン開始
    /// 複数 Scene 跨ぎなので「次フェーズ判定」をまとめてここに置く。
    /// ActionMenu / EnemyScene / BattlePanel / EnemyTurnDriverScene / TurnInputBridge から
    /// 呼ばれる。
    pub def commitWaitedAndAdvance(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        let withWaited = match SelectedPlayer.State.get()#id {
            case Some(id) => setWaited(id, scene)
            case None     => scene   // 防御的 (選択なしで Attack に入ることは想定外)
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        // 次の active 味方の gridPos をローカル `withWaited` から直接拾って渡す。
        // `enterPlayerCursor` 側の PartyQuery フォールバックは sceneRef (frame 冒頭の snapshot)
        // を読むので、たった今 setWaited した駒をまだ active として返してしまう。
        match firstActive(withWaited) {
            case Some(next) =>
                PhaseTransitions.enterPlayerCursorAt(next#gridPos, withWaited)
            case None       =>
                EnemyTurnDriverScene.beginTurn(withWaited)
        }

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理 (味方側)。
    /// 攻撃ダメージ適用本体は既存 `applyAttackHit` を呼ぶ。
    /// 名前は「event 受信」の semantics を明示するための薄ラッパ。
    pub def onAttackHit(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Audio,
                              GameEngine.Game, GameLogger.GameLogger} =
        applyAttackHit(playerId, scene)

    /// AnimationPlayer の `attack_lunge` finished イベント受信時の処理 (味方側)。
    /// 2 通りある:
    ///   - `PlayerAttackHold` (= 味方主攻撃の完了) → CounterAttackRules.decide で分岐:
    ///       Kill (敵瀕死) / Counter (敵反撃) / Commit (waited 確定)。
    ///   - `EnemyTurn` (= 敵攻撃に対する味方反撃の完了) → 単純に attackTargetId クリア。
    ///       次フレーム以降で EnemyTurnDriver が PlayerScene.anyAttacking が false に
    ///       なったのを見て次の step に進む。FE 風で「反撃の反撃」は実装しない。
    pub def onAttackLungeDone(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State, Pacing.State} =
        if (TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn)
            clearAttackTarget(playerId, scene)
        else match get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                let target = player#attackTargetId
                    |> Option.flatMap(eid -> EnemyScene.get(eid, scene));
                match CounterAttackRules.decide(player, target) {
                    case CounterAttackRules.Outcome.Kill =>
                        let cleared = clearAttackTarget(playerId, scene);
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        Pacing.State.hold(700 |> Duration.millis);
                        cleared
                    case CounterAttackRules.Outcome.Counter(enemyId) =>
                        let cleared = clearAttackTarget(playerId, scene);
                        match get(playerId, cleared) {
                            case None    => commitWaitedAndAdvance(cleared)
                            case Some(p) =>
                                GameLogger.enemyLog("敵${enemyId} の反撃");
                                EnemyScene.startAttack(enemyId, playerId, p#gridPos, cleared)
                        }
                    case CounterAttackRules.Outcome.Commit =>
                        let cleared = clearAttackTarget(playerId, scene);
                        commitWaitedAndAdvance(cleared)
                }
        }

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

    /// 敵 id にダメージを与える。攻撃力は `力(unit#attack) + 装備中武器の攻撃力` で、
    /// `Combat.attackDamage(総合攻撃力, 防御者#defense)` から素ダメージを得て
    /// `Combat.damage` で HP 減算 + 死亡判定。HP <= 0 で死亡演出を開始する。
    /// 装備中武器は `weapons.head`（= リストの先頭）。「装備」操作で先頭を入れ替えると
    /// 攻撃に使われる武器が切り替わる。攻撃成立後に耐久度を 1 減らし、0 になったら
    /// インベントリから取り除き「P{N} の {武器名} がこわれた」ログを出す。
    /// ログはスペック準拠で「P{N} → 敵{M} に Xダメージ」 / 撃破時「P{N} → 敵{M} を撃破」。
    /// 命中ロールは v1 では行わず常に命中（hit% は forecast でプレビュー表示するための値）。
    /// インベントリ空 / 敵不在ならば防御的に no-op。
    def applyDamageToEnemy(playerId: Int32, player: Data, enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, GameEngine.Game,
                               GameLogger.GameLogger} =
        // 常に先頭武器（= 装備中）を使う。空なら no-op。
        let idx = 0;
        match (List.nth(idx, player#weapons), EnemyScene.get(enemyId, scene)) {
            case (None, _)        => scene
            case (_, None)        => scene
            case (Some(weapon), Some(enemy)) =>
                let phys = UnitCatalog.isPhysical(weapon#weaponType);
                let totalAttack = Combat.attackStatFor(player#resource#attack,
                                                       player#resource#magicAttack,
                                                       weapon#attack, phys);
                let targetDef   = Combat.defenseStatFor(enemy#resource#defense,
                                                        enemy#resource#magicDefense,
                                                        phys);
                let dmg    = Combat.attackDamage(totalAttack, targetDef);
                let result = Combat.damage(hp = enemy#hp, amount = dmg);
                // 被弾位置（敵の頭上）にダメージ数字を浮かす。撃破時もこの 1 回は出す。
                let popupPos = MapScene.cellCenter(enemy#gridPos);
                let popupColor = DamagePopupScene.damageToEnemyColor();
                let withPopup = DamagePopupScene.emit(popupPos, dmg, popupColor, scene);
                let afterDamage =
                    if (result#isDead) {
                        GameLogger.playerLog("P${playerId} → 敵${enemyId} を撃破");
                        withPopup
                            |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
                            |> EnemyScene.startDeathAnimation(enemyId)
                    } else {
                        GameLogger.playerLog("P${playerId} → 敵${enemyId} に ${dmg}ダメージ");
                        withPopup
                            |> EnemyScene.mapEnemy(enemyId,
                                enemyData -> {hp = result#newHp | enemyData})
                            |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
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
                    d -> {weapons = newWeapons | d}, afterDamage)
        }

    // ────────────────────────────────────────────────────────
    // (I) 杖の発動 — direction → 直線レイキャスト → 効果適用 → ターン進行
    // ────────────────────────────────────────────────────────

    /// 杖を発動する。`StaffAim` フェーズで方向キーが押された瞬間に呼ばれる。
    ///   1. プレイヤーの `staves[staffIdx]` と `gridPos` / `magicAttack` を取り出す
    ///   2. `Board.rayCast` で射線上の最初の当たり対象を `RayHit` で得る
    ///   3. `staff#effect × hit` で効果を分岐適用（Heal / Blowback / Swap）
    ///   4. `Staff.consume` で耐久 -1、0 なら staves から除去 + 破損ログ
    ///   5. 選択中アイテムをクリア → `commitWaitedAndAdvance` で waited 確定し次ターンへ
    ///
    /// 杖は CounterAttackRules を経由しない（反撃なし）。
    /// 該当プレイヤー / 杖が見つからない場合は防御的に no-op。
    pub def applyStaffCast(playerId: Int32, staffIdx: Int32,
                             direction: Staff.Direction,
                             scene: Scene[NodeTag]):
            Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                BoardQuery, GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match get(playerId, scene) {
            case None         => scene
            case Some(player) =>
                match List.nth(staffIdx, player#staves) {
                    case None        => scene
                    case Some(staff) =>
                        let board = BoardQuery.board();
                        let dir   = Staff.toVec2i(direction);
                        // 杖は射程を持たない: 盤面外は壁扱いなので、十分大きい上限を渡せば
                        // 必ず壁または駒で止まる（無限射程と等価）。
                        let hit   = Board.rayCast(player#gridPos, dir, staffMaxRange(), board);
                        let afterEffect = applyStaffEffect(playerId, player, staff,
                                                            dir, hit, scene);
                        let afterConsume = consumeStaff(playerId, staffIdx, staff, afterEffect);
                        let cleared = clearSelectedItem(playerId, afterConsume);
                        commitWaitedAndAdvance(cleared)
                }
        }

    /// 杖の射程上限。盤面の最大寸法より大きければ実質「無限」として機能する。
    def staffMaxRange(): Int32 = 1000

    /// `staff#effect × hit` の組み合わせで効果を適用する。
    /// 9 通り（うち実意味のあるのは 6 通り）の分岐は table comment を参照。
    def applyStaffEffect(playerId: Int32, player: Data,
                          staff: Staff.StaffResource,
                          dir: {x = Int32, y = Int32},
                          hit: RayHit,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger} =
        match (staff#effect, hit) {
            case (Staff.StaffEffect.Heal, RayHit.HitPlayer(targetId, _)) =>
                applyHealToPlayer(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Heal, RayHit.HitEnemy(targetId, _)) =>
                applyHealToEnemy(playerId, player, targetId, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitPlayer(targetId, hitCell)) =>
                applyBlowbackToPlayer(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Blowback, RayHit.HitEnemy(targetId, hitCell)) =>
                applyBlowbackToEnemy(playerId, targetId, hitCell, dir, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitPlayer(otherId, otherCell)) =>
                applySwapWithPlayer(playerId, player#gridPos, otherId, otherCell, scene)
            case (Staff.StaffEffect.Swap, RayHit.HitEnemy(enemyId, enemyCell)) =>
                applySwapWithEnemy(playerId, player#gridPos, enemyId, enemyCell, scene)
            // 空振り系: 効果なし、ログだけ（実際の杖名を表示する）
            case (Staff.StaffEffect.Heal, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Blowback, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は届かなかった");
                scene
            case (Staff.StaffEffect.Swap, _) =>
                GameLogger.playerLog("P${playerId} の ${staff#name} は消えた");
                scene
        }

    /// ライブ × 味方: 対象味方の HP を「魔力 × 2」回復、HPBar 更新、ログ。
    def applyHealToPlayer(srcId: Int32, player: Data, targetId: Int32,
                           scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack * 2;
        match get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let result = Combat.heal(target#hp, target#resource#hp, amount);
                let healed = result#newHp - target#hp;
                GameLogger.playerLog("P${srcId} → P${targetId} を ${healed}回復");
                scene
                    |> mapPlayer(targetId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(playerPath(targetId), result#newHp)
        }

    /// ライブ × 敵: 敵の HP を「魔力 × 2」回復（敵にも効く仕様）。
    def applyHealToEnemy(srcId: Int32, player: Data, enemyId: Int32,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let amount = player#resource#magicAttack * 2;
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let result = Combat.heal(enemy#hp, enemy#resource#hp, amount);
                let healed = result#newHp - enemy#hp;
                GameLogger.playerLog("P${srcId} → 敵${enemyId} を ${healed}回復");
                scene
                    |> EnemyScene.mapEnemy(enemyId, d -> {hp = result#newHp | d})
                    |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), result#newHp)
        }

    /// ふきとばし × 味方: 1 ダメ → 死亡なら止まる、生存なら最終位置までスナップで移動。
    /// 仕様確認: MVP では「最終位置に瞬間移動 + ダメージ popup」で済ませる
    /// （1 マスずつ tween は engine の sequence 機能が要るため、後続タスクで強化）。
    def applyBlowbackToPlayer(srcId: Int32, targetId: Int32,
                                hitCell: {x = Int32, y = Int32},
                                dir: {x = Int32, y = Int32},
                                scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        match get(targetId, scene) {
            case None         => scene
            case Some(target) =>
                let dmgResult = Combat.damage(hp = target#hp, amount = 1);
                let withDamage = scene
                    |> mapPlayer(targetId, d -> {hp = dmgResult#newHp | d})
                    |> UnitHPBarScene.update(playerPath(targetId), dmgResult#newHp);
                GameLogger.playerLog(
                    "P${srcId} → P${targetId} を ふきとばし (1ダメージ)");
                if (dmgResult#isDead) withDamage
                else applyBlowbackMove(targetId, hitCell, dir, withDamage,
                                        cell -> snapTo(targetId, cell, withDamage))
        }

    /// ふきとばし × 敵: 1 ダメ → 死亡なら startDeathAnimation、生存なら最終位置に snapTo。
    def applyBlowbackToEnemy(srcId: Int32, enemyId: Int32,
                               hitCell: {x = Int32, y = Int32},
                               dir: {x = Int32, y = Int32},
                               scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                GameLogger.GameLogger} =
        match EnemyScene.get(enemyId, scene) {
            case None        => scene
            case Some(enemy) =>
                let dmgResult = Combat.damage(hp = enemy#hp, amount = 1);
                if (dmgResult#isDead) {
                    GameLogger.playerLog("P${srcId} → 敵${enemyId} を ふきとばし撃破");
                    scene
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), 0)
                        |> EnemyScene.startDeathAnimation(enemyId)
                } else {
                    let withDamage = scene
                        |> EnemyScene.mapEnemy(enemyId, d -> {hp = dmgResult#newHp | d})
                        |> UnitHPBarScene.update(EnemyScene.enemyPath(enemyId), dmgResult#newHp);
                    GameLogger.playerLog(
                        "P${srcId} → 敵${enemyId} を ふきとばし (1ダメージ)");
                    applyBlowbackMove(enemyId, hitCell, dir, withDamage,
                                       cell -> EnemyScene.snapTo(enemyId, cell, withDamage))
                }
        }

    /// 押される対象の最終位置を `Board.knockbackPath` で計算し、`moveFn` で動かす。
    /// 経路が空（押される先がない）なら何もしない。
    def applyBlowbackMove(_targetId: Int32,
                           hitCell: {x = Int32, y = Int32},
                           dir: {x = Int32, y = Int32},
                           scene: Scene[NodeTag],
                           moveFn: {x = Int32, y = Int32} -> Scene[NodeTag] \ Tween.Scheduler):
            Scene[NodeTag] \ Tween.Scheduler =
        let board: Board = BoardSnapshot.fromScene(scene);
        let path = Board.knockbackPath(hitCell, dir, board);
        match List.last(path) {
            case None       => scene
            case Some(last) => moveFn(last)
        }

    /// いれかえ × 味方: 自分と相手の gridPos を瞬間 swap する。
    def applySwapWithPlayer(srcId: Int32, srcCell: {x = Int32, y = Int32},
                              otherId: Int32, otherCell: {x = Int32, y = Int32},
                              scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と P${otherId} がいれかわった");
        scene
            |> snapTo(srcId, otherCell)
            |> snapTo(otherId, srcCell)

    /// いれかえ × 敵: 自分（Player）と敵を交換する。
    def applySwapWithEnemy(srcId: Int32, srcCell: {x = Int32, y = Int32},
                             enemyId: Int32, enemyCell: {x = Int32, y = Int32},
                             scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        GameLogger.playerLog("P${srcId} と 敵${enemyId} がいれかわった");
        scene
            |> snapTo(srcId, enemyCell)
            |> EnemyScene.snapTo(enemyId, srcCell)

    /// 杖の耐久を 1 減らし、0 なら staves から除去 + 破損ログ。
    def consumeStaff(playerId: Int32, staffIdx: Int32, staff: Staff.StaffResource,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        let consumed = Staff.consume(staff);
        let newStaves = match consumed {
            case Some(updated) =>
                // 同じ index の要素だけ更新後の値に差し替える
                let originalStaves = getStaves(playerId, scene);
                List.mapWithIndex(i -> s -> if (i == staffIdx) updated else s,
                                   originalStaves)
            case None =>
                // 壊れた → index 位置の要素を取り除く
                getStaves(playerId, scene) |> dropAt(staffIdx)
        };
        if (Option.isEmpty(consumed))
            GameLogger.playerLog("P${playerId} の ${staff#name} がこわれた")
        else ();
        mapPlayer(playerId, d -> {staves = newStaves | d}, scene)

    /// List から `idx` 番目を取り除く（範囲外なら元のリスト）。
    def dropAt(idx: Int32, list: List[a]): List[a] =
        List.zipWithIndex(list)
            |> List.filter(pair -> let (i, _) = pair; i != idx)
            |> List.map(pair -> let (_, x) = pair; x)
}
