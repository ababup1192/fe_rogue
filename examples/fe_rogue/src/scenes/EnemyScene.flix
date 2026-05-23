/// EnemyScene — 敵キャラクター（Marker2D + 子 Sprite2D）の集まり
///
/// FE 風のターン制で味方を追跡してくる敵駒を表現する。プレイヤーと違って
/// 1 シーンに複数体が同時に存在するため、各敵をトップレベルの "Enemy_<id>"
/// ノードとして並べて管理する（PlayerScene が単一 Marker2D なのに対して、
/// EnemyScene は同じノード型を id 別に量産するイメージ）。
///
/// ノード構造（敵 1 体あたり）:
///   Enemy_<id> (Marker2D, NodeTag.Enemy(Data))
///     └─ Sprite (Sprite2D, frame=4 の `character_sheet` 上段一番右)
///
/// スポーン規則（Q1-B / Q2-B / anchor 除外）:
///   - 部屋（idx in [1, roomCount)）ごとに `Random` で 0..maxPerRoom 体スポーン。
///   - anchor 部屋（idx 0、プレイヤー初期位置）は除外。Q3-B との組み合わせで
///     起動瞬間に殴られないようにする。
///   - 通路（idx >= roomCount）は対象外。プレイヤーが通り抜けるだけの空間にする。
///   - 各敵は部屋の床セルから 1 つを選ぶ（プレイヤー位置・既存敵セルを避ける）。
///
/// Step 2 ではスポーン + 表示までで、AI / ターン進行は Step 3 で接続する。
mod EnemyScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 敵 1 体ぶんの状態。
    /// `alerted` はプレイヤーと同モジュールに入った瞬間 true になり、以降永続。
    /// `homeModuleIdx` はスポーンしたときの部屋 idx（検知判定の補助情報）。
    /// `moveTiles` は 1 ターンに進めるマス数（FE の「移動力」相当、`resource` から初期値継承）。
    /// EnemyAI が BFS パスからこの値ぶんだけ進めて 1 マスずつ Tween する。
    /// `hp` は残り体力。0 になると `isDying = true` がセットされ、`death_blink`
    /// アニメーションが再生される。アニメ終了で GameManager がノードを scene から削除する。
    /// `isDying = true` の敵は `EnemyTurn.Queue` / `findIdAt` などから除外され、行動しない。
    /// `resource` はスポーン時のユニット定義テンプレート（UnitResource）。
    /// ゲームオーバー時の `respawnFromInitial` で同じ敵種別で再生するために保持。
    /// `weapon` は装備中の武器。攻撃するたびに耐久度が 1 減り、0 で `None` になる
    /// （以降、その敵は EnemyAI 側で Attack を返さなくなる）。攻撃力は `resource#attack + weapon#attack`。
    pub type alias Data = {
        id             = Int32,
        gridPos        = {x = Int32, y = Int32},
        alerted        = Bool,
        homeModuleIdx  = Int32,
        moveTiles      = Int32,
        hp             = Int32,
        isDying        = Bool,
        attackTargetId = Option[Int32],
        resource       = UnitCatalog.UnitResource,
        weapon         = Option[UnitCatalog.WeaponResource]
    }

    /// スポーン時の中間表現。`add` 内のループで部屋ごとに積み上げ、最後に Marker2D へ展開する。
    /// `respawnFromInitial` で「ゲームオーバー時に同じ位置・同じ種別の敵を出し直す」のにも使うため pub。
    /// `weapon` は初期装備の固定値で、復元時にこの値が再び敵に持たされる。
    pub type alias Spawn = {
        id        = Int32,
        gridPos   = {x = Int32, y = Int32},
        moduleIdx = Int32,
        resource  = UnitCatalog.UnitResource,
        weapon    = UnitCatalog.WeaponResource
    }

    /// 敵駒の「現フレーム状態」を Scene を介さずに読み取る effect。
    ///
    /// 非 driver / 非 data Scene (HUD / Camera / Menu / Overlay) は `EnemyScene` モジュールを
    /// 直接タイプせず、この effect 経由で敵データを得る。`PlayerScene.Query` の敵版で、設計思想は同じ
    /// (BoardQuery / PlayerScene.Query 参照)。
    pub eff RosterQuery {
        def get(id: Int32): Option[Data]
        def getAll(): List[Data]
        def findIdAt(coord: {x = Int32, y = Int32}): Option[Int32]
        def anyAttacking(): Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// プレイヤーと同じ高さで前面に立つ。MoveRange (1) より上。
    def spriteZIndex(): Int32 = 10

    // per-room cap は引数で受け取る floor の `monstersPerRoom` を使う (resource 駆動)。
    // 旧 `maxPerRoom()` 定数は floor 駆動化で廃止

    /// 1 マス分のスライド時間。Player と同じ感覚で見えるよう揃える。
    def slideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 120)

    /// 死亡点滅アニメーションの全長。3 サイクル（半透明 → 不透明）× 2 フェーズ × 150ms。
    def deathBlinkLength(): Duration.Duration = 900 |> Duration.millis

    /// 死亡演出時の半透明 alpha 値（点滅の谷）。
    def dimAlpha(): Float32 = 0.3f32

    /// 通常時 / 点滅の山の alpha 値。
    def fullAlpha(): Float32 = 1.0f32

    /// `death_blink` アニメーション。1 → 0.3 → 1 → 0.3 → 1 → 0.3 → 1 を均等な 6 区間で
    /// 並べて 3 サイクルの点滅を表現する。target は子 Sprite ノードの alpha。
    /// アニメ完了時の `finished` イベント (owner=enemyPath, name="death_blink") を
    /// GameManager がディスパッチして bonus.ogg + Scene.removeAt を実行する。
    def deathBlinkAnimation(targetSprite: NodePath): AnimationPlayer.Animation =
        let alphaKeys: List[AnimationPlayer.AlphaKey] =
            ({time = 0.0,        alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 1.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 2.0 / 6.0,  alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 3.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 4.0 / 6.0,  alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            ({time = 5.0 / 6.0,  alpha = dimAlpha() }: AnimationPlayer.AlphaKey) ::
            ({time = 1.0,        alpha = fullAlpha()}: AnimationPlayer.AlphaKey) ::
            Nil;
        let track: AnimationPlayer.Track = {
            target = targetSprite,
            prop   = AnimationPlayer.Property.Alpha(alphaKeys)
        };
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.DeathBlink),
            length  = deathBlinkLength(),
            tracks  = track :: Nil,
            methods = Nil
        }

    /// "Enemy_3" のようなノード名（World の直接の子）。
    pub def enemyName(id: Int32): String = "Enemy_${id}"

    /// 敵 id の NodePath。Y-sort root の World 配下にぶら下げるため
    /// "World/Enemy_<id>" の 2 段構造
    pub def enemyPath(id: Int32): NodePath =
        List.append(MapScene.worldPath(), enemyName(id) :: Nil)

    /// 敵 id の子 Sprite ノードへのパス。alpha 補間 (Tween.tweenAlpha) のターゲットに使う。
    pub def spritePath(id: Int32): NodePath =
        List.append(enemyPath(id), "Sprite" :: Nil)

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene が登録済みの scene に敵を追加する。
    /// 各部屋について 0..`floor#monstersPerRoom` 体のスポーン位置を決め、
    /// それぞれに `floor#monsters` から percent 重みでランダム抽選した unit id を引いて
    /// UnitResource を割り当て、`initialWeapon` id から武器カタログを引いて装備させる。
    /// `Math.Random` を使うのでこの effect が必要。
    pub def add(catalog: UnitCatalog.UnitCatalog,
                 floor: FloorCatalog.FloorResource,
                 scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random} =
        let layer       = MapScene.getMapLayer(scene);
        let placements  = MapScene.getPlacements(scene);
        let roomCount   = MapScene.getRoomCount(scene);
        // パーティ全員のセルを taken に入れて避ける（敵が味方の上にスポーンしないように）
        let playerCells = PlayerScene.getAll(scene) |> List.map(d -> d#gridPos);
        // anchor (idx = 0) を除いた部屋だけを対象にする
        let rooms = List.filter(p ->
            p#idx >= 1 and p#idx < roomCount, placements);
        // 部屋を順に走査し、(nextId, takenCells, spawns) を畳み込む。
        // pickCellsInRoom と weighted 抽選が `Math.Random` を持つので畳み込み全体も `Math.Random`。
        let initial: (Int32, List[{x = Int32, y = Int32}], List[Spawn]) =
            (0, playerCells, Nil);
        let monsters = floor#monsters;
        let range = floor#monstersPerRoom;
        let (_, _, accSpawns) = List.foldLeft(state -> p ->
            spawnInRoom(layer, p, FloorCatalog.randomCountInRange(range),
                         monsters, catalog, state),
            initial, rooms);
        // accSpawns は逆順（cons で積んだ）なので reverse して id 昇順に揃える
        let spawns = List.reverse(accSpawns);
        List.foldLeft(acc -> sp -> addOneEnemy(sp, acc), scene, spawns)

    /// 部屋 1 つから `count` 個のスポーンセルを選んで state に積む。
    /// state = (次に振る id, スポーン済みセル累積, spawn list 累積)。
    /// 候補不足のときは取れる分だけ積んで打ち切る。
    /// 各セルにつき floor の `monsters` (percent 配列) から重み付き抽選した unit id を
    /// `catalog#units` で UnitResource に解決し、`initialWeapon` id から武器カタログを引いて装備させる。
    def spawnInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     monsters: List[FloorCatalog.SpawnEntry],
                     catalog: UnitCatalog.UnitCatalog,
                     state: (Int32, List[{x = Int32, y = Int32}], List[Spawn])):
                    (Int32, List[{x = Int32, y = Int32}], List[Spawn]) \ Math.Random =
        if (count <= 0) state
        else
            let (nextId, taken, list) = state;
            let candidates = floorCellsInRoom(layer, p)
                              |> List.filter(c -> not isTaken(c, taken));
            match RandomUtil.pick(candidates) {
                case None       => state   // 候補ゼロで打ち切り
                case Some(cell) =>
                    match FloorCatalog.pickWeighted(monsters) {
                        case None => state  // weight 配列が空 / 合計 0 → スキップ
                        case Some(id) =>
                            let res = match Map.get(id, UnitCatalog.unitsOf(catalog)) {
                                case Some(u) => u
                                case None    =>
                                    bug!("EnemyScene.spawnInRoom: unit id '${id}' not in catalog")
                            };
                            let weapon = UnitCatalog.lookupWeapon(res#initialWeapon, catalog);
                            let entry: Spawn = {
                                id = nextId, gridPos = cell, moduleIdx = p#idx,
                                resource = res, weapon = weapon
                            };
                            spawnInRoom(layer, p, count - 1, monsters, catalog,
                                         (nextId + 1, cell :: taken, entry :: list))
                    }
            }

    /// 部屋の bbox（offset + gridSize）に含まれる床セルを列挙する。
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        let minX = p#offset#x;
        let minY = p#offset#y;
        let maxX = p#offset#x + p#gridSize#x;
        let maxY = p#offset#y + p#gridSize#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> TileMapLayer.isFloor(c, layer),
                List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32}), xs)),
            ys)

    def isTaken(c: {x = Int32, y = Int32}, taken: List[{x = Int32, y = Int32}]): Bool =
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    /// 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    /// ステータス・テクスチャ・フレームは `sp#resource`（UnitResource）から取る。
    def addOneEnemy(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pos = MapScene.cellCenter(sp#gridPos);
        let marker = Marker2D.make(pos);
        let res    = sp#resource;
        let data: Data = {
            id             = sp#id,
            gridPos        = sp#gridPos,
            alerted        = false,
            homeModuleIdx  = sp#moduleIdx,
            moveTiles      = res#moveTiles,
            hp             = res#hp,
            isDying        = false,
            attackTargetId = None,
            resource       = res,
            weapon         = Some(sp#weapon)
        };
        let sprite = Sprite2D.make(res#sprite#texture, res#sprite#offset, Vec2.one())
                        |> Sprite2D.setHframes(res#sprite#hframes)
                        |> Sprite2D.setVframes(res#sprite#vframes)
                        |> Sprite2D.setFrame(res#sprite#frame)
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addChildAt(MapScene.worldPath(), enemyName(sp#id),
                                 EngineNode.Marker2DWithState(marker, NodeTag.Enemy(data)))
            |> Scene.addChildAt(enemyPath(sp#id), "Sprite",
                                 EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> UnitHPBarScene.attach(enemyPath(sp#id), res#hp, UnitHPBarScene.BarPosition.Below)

    // ────────────────────────────────────────────────────────
    // (D) クエリ
    // ────────────────────────────────────────────────────────

    /// scene 上に登録された全ての敵の Data を返す（preorder 走査順）。
    pub def getAll(scene: Scene[NodeTag]): List[Data] =
        Scene.preorderPaths(scene)
            |> List.filterMap(path -> match Scene.getState(path, scene) {
                case Some(NodeTag.Enemy(data)) => Some(data)
                case _                          => None
            })

    /// id を持つ敵の Data を取り出す。未登録なら None。
    pub def get(id: Int32, scene: Scene[NodeTag]): Option[Data] =
        match Scene.getState(enemyPath(id), scene) {
            case Some(NodeTag.Enemy(data)) => Some(data)
            case _                          => None
        }

    /// 敵 id の Data を `f` で更新する。Marker2D 自体には触れない。
    pub def mapEnemy(id: Int32, f: Data -> Data,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(enemyPath(id), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Enemy(data)) =>
                EngineNode.Marker2DWithState(marker, NodeTag.Enemy(f(data)))
            case other => other
        }, scene)

    /// 敵 id を `target` に移動させる。論理位置（gridPos）は即時更新し、
    /// 見た目の補間は Tween に委ねる（PlayerScene.moveTo と同じ機構）。
    /// 呼び出しごとに 1 マス分（隣接セル）の Tween を登録する前提。複数マス分の
    /// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ呼ぶことで実現する。
    /// **歩行可否（壁・他駒）の判定は呼び出し側（EnemyAI）が済ませている前提**で、
    /// EnemyScene 自身は衝突判定を持たない。
    pub def moveTo(id: Int32, target: {x = Int32, y = Int32},
                    map: MapSnapshot,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let startWorld  = Scene.globalPositionAt(enemyPath(id), scene);
        let targetWorld = map#gridToWorld(target);
        Tween.tweenPosition(enemyPath(id), startWorld, targetWorld, slideDuration());
        mapEnemy(id, d -> {gridPos = target | d}, scene)

    /// 指定セルに居る（生きている）敵の id を返す。死亡演出中の敵は対象外。
    /// PlayerAttack フェーズで「カーソルが赤マス上の敵に乗っているか」の判定に使う。
    pub def findIdAt(coord: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Option[Int32] =
        getAll(scene)
            |> List.findMap(d ->
                if (not d#isDying
                    and d#gridPos#x == coord#x
                    and d#gridPos#y == coord#y) Some(d#id)
                else None)

    // ────────────────────────────────────────────────────────
    // (E) 死亡演出 — death_blink アニメ → finished で Scene 削除
    // ────────────────────────────────────────────────────────

    /// 敵 id の HP を 0 にして死亡演出を開始する。
    /// `isDying = true` を立てて `death_blink` アニメーションを再生する。
    /// アニメ完了で GameManager が `completeDeath` を呼んでノード削除と bonus 再生を行う。
    pub def startDeathAnimation(id: Int32,
                                 scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        AnimationPlayer.play(enemyPath(id), deathBlinkAnimation(spritePath(id)));
        mapEnemy(id, d -> {hp = 0, isDying = true | d}, scene)

    /// `death_blink` 完了時に GameManager が呼ぶ後始末。
    /// bonus.ogg を再生し、ノードを scene から削除する（damage の後に bonus が鳴る順序保証）。
    pub def completeDeath(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Audio =
        AudioStreamPlayer.play("bonus");
        Scene.removeAt(enemyPath(id), scene)

    /// World 直下の `Enemy_<id>` 形式の NodePath から id を取り出す。
    /// それ以外なら None。AnimationPlayer の finished イベント振り分けに使う
    pub def idFromPath(path: NodePath): Option[Int32] =
        match path {
            case world :: name :: Nil if world == MapScene.worldName() =>
                if (String.startsWith({prefix = "Enemy_"}, name))
                    String.dropLeft(6, name) |> Int32.fromString
                else None
            case _ => None
        }

    // ────────────────────────────────────────────────────────
    // (F) 初期 spawn のスナップショットと再配置（ゲームオーバー時のリセット）
    // ────────────────────────────────────────────────────────

    /// 現在 scene に居る全敵の `Spawn` 情報（id / gridPos / homeModuleIdx / resource / weapon）を
    /// 抽出する。`Game.start` で初回 buildPlayingScene 直後に呼んで保存し、ゲームオーバー時に
    /// `respawnFromInitial` で同じ位置・同じ敵種別・同じ武器で再配置する。
    /// スナップショットは攻撃前に取られる前提で `weapon` は常に Some。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                let weapon = match d#weapon {
                    case Some(w) => w
                    case None    => bug!("EnemyScene.snapshotSpawns: weapon is None for 敵${d#id} (snapshot taken after weapon broke?)")
                };
                ({id = d#id, gridPos = d#gridPos, moduleIdx = d#homeModuleIdx, resource = d#resource, weapon = weapon}: Spawn))

    /// 既存の敵を全て scene から取り除き、`spawns` から再構築する。
    /// 各敵は `addOneEnemy` を使って HP・alerted・dying を初期値で生成する。
    pub def respawnFromInitial(spawns: List[Spawn],
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        let cleared = List.foldLeft((sc, d) -> Scene.removeAt(enemyPath(d#id), sc),
                                     scene, getAll(scene));
        List.foldLeft((sc, sp) -> addOneEnemy(sp, sc), cleared, spawns)

    // ────────────────────────────────────────────────────────
    // (G) 体当たり攻撃モーション — AnimationPlayer ベース
    // ────────────────────────────────────────────────────────

    /// 敵 id の体当たり攻撃モーションを開始する。
    /// `attack_lunge` アニメーションを再生し `attackTargetId = Some(targetPlayerId)` を立てる。
    /// 中点で `attack:hit` メソッド、終端で finished が GameManager に届き、
    /// それぞれダメージ適用・後始末（味方死亡なら handlePlayerDeath）が走る。
    /// 武器が壊れている（`weapon = None`）敵はそもそも EnemyAI が Attack を返さない設計で、
    /// ここに到達したら防御的に no-op する。
    pub def startAttack(id: Int32, targetPlayerId: Int32,
                         targetGrid: {x = Int32, y = Int32},
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                if (Option.isEmpty(d#weapon)) scene
                else {
                    AnimationPlayer.play(enemyPath(id),
                        PlayerScene.attackLungeAnimation(enemyPath(id),
                                                           d#gridPos, targetGrid));
                    mapEnemy(id, dd -> {attackTargetId = Some(targetPlayerId) | dd}, scene)
                }
        }

    /// scene 内に攻撃モーション中の敵が居れば true。stepEnemyTurn が次ステップに進んで
    /// 良いかの判定に使う（攻撃モーション中はキューを進めない）。
    pub def anyAttacking(scene: Scene[NodeTag]): Bool =
        List.exists(d -> Option.nonEmpty(d#attackTargetId), getAll(scene))

    /// `attack:hit` メソッド発火時に GameManager から呼ばれるダメージ適用。
    /// 戻り値は (新 scene, HP=0 になったプレイヤー id のリスト)。
    /// killedIds が空でないとき呼び出し側は handlePlayerDeath を発火する。
    pub def applyAttackHit(enemyId: Int32, scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \
            {GameEngine.Audio, GameEngine.Game, GameLogger.GameLogger} =
        match get(enemyId, scene) {
            case None    => (scene, Nil)
            case Some(d) =>
                match d#attackTargetId {
                    case None             => (scene, Nil)
                    case Some(targetPlayerId) =>
                        AudioStreamPlayer.play("damage");
                        applyDamageToPlayer(enemyId, d, targetPlayerId, scene)
                }
        }

    /// `attack_lunge` finished 時に呼ばれる。`attackTargetId` をクリアする。
    pub def clearAttackTarget(enemyId: Int32,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        mapEnemy(enemyId, d -> {attackTargetId = None | d}, scene)

    /// AnimationPlayer の `attack:hit` method イベント受信時の処理 (敵側)。
    /// 既存 `applyAttackHit` の killed リストを `PlayerScene.removeDeadAndCheckGameOver`
    /// に流し、全滅時は `CustomEffects.GameOverRequest` でフルリビルドさせる。
    pub def onAttackHit(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game,
                              GameLogger.GameLogger,
                              CustomEffects.GameOverRequest,
                              SelectedPlayer.State} =
        let (next, killed) = applyAttackHit(enemyId, scene);
        PlayerScene.removeDeadAndCheckGameOver(killed, next)

    /// AnimationPlayer の `death_blink` finished イベント受信時の処理。
    /// 死亡演出が終わったので scene から該当敵ノードを削除する (SE 込み)。
    pub def onDeathBlinkDone(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Audio =
        completeDeath(enemyId, scene)

    /// 各 Enemy ノードの毎フレーム process。AnimationPlayer から自分宛 (`enemyPath(id)`)
    /// の signal だけ pull し、attack:hit (中点) / death_blink (完了) / attack_lunge (反撃完了)
    /// に反応する。Game.flix の `Node[NodeTag] instance` の process redef から全 Enemy に
    /// dispatch される (per-node)。owner 完全一致なので他 Enemy の signal は取りこぼさない。
    /// 「Sceneのライフサイクルで処理が完結」する Godot 流の per-node signal モデル。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {AnimationPlayer.Scheduler, GameEngine.Audio, GameEngine.Game,
                        GameLogger.GameLogger,
                        CustomEffects.GameOverRequest,
                        Tween.Scheduler,
                        EnemyTurn.Queue, TurnPhase.State,
                        SelectedPlayer.State} =
        match idFromPath(path) {
            case None          => (node, scene)
            case Some(enemyId) =>
                let bundle = AnimationPlayer.Scheduler.drainSignals(enemyPath(enemyId));
                let afterMethods = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.AttackHit) => onAttackHit(enemyId, sc)
                        case _                              => sc
                    },
                    scene, bundle#methods);
                let afterFinished = List.foldLeft(
                    (sc, ev) -> match AnimEvent.parseTag(ev#name) {
                        case Some(AnimEvent.Tag.DeathBlink)  => onDeathBlinkDone(enemyId, sc)
                        case Some(AnimEvent.Tag.AttackLunge) => onCounterLungeDone(enemyId, sc)
                        case _                                => sc
                    },
                    afterMethods, bundle#finished);
                // signal handler が scene 経由で self (Enemy ノード) を更新する可能性が
                // あるため、最新ノードを取り直して返す (古い node で打ち消されないように)
                match Scene.getEngineNode(path, afterFinished) {
                    case Some(latest) => (latest, afterFinished)
                    case None         => (node, afterFinished)
                }
        }

    /// AnimationPlayer の `attack_lunge` finished イベント受信時の処理 (敵側 = 反撃完了)。
    /// `attackTargetId` をクリアした後、現フェーズが `PlayerAttackHold` (= 味方攻撃に対する
    /// 反撃の完了) なら commit、`EnemyTurn` (= 通常の敵ターン中の攻撃) なら何もしない。
    /// フェーズが `PlayerAttackHold` なのは `BattlePanelScene.confirm` が攻撃モーション
    /// 開始時にここへ遷移させているため (味方 attack_lunge → 反撃 attack_lunge の間ずっと Hold)。
    pub def onCounterLungeDone(enemyId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        let cleared = clearAttackTarget(enemyId, scene);
        if (TurnPhase.State.get() == TurnPhase.Phase.PlayerAttackHold)
            PlayerScene.commitWaitedAndAdvance(cleared)
        else cleared

    /// プレイヤー targetId にダメージを与える。攻撃力は `力(enemy#attack) + 武器の攻撃力` で、
    /// `Combat.attackDamage(総合攻撃力, 防御者#defense)` から素ダメージを得て
    /// `Combat.damage` で HP 減算 + 死亡判定。攻撃成立後は武器の `durability` を 1 減らし、
    /// 0 になったら `weapon = None` に切り替え、ログに「敵N の {武器名} がこわれた」を出す。
    /// ログはスペック準拠で「敵{N} → P{M} に Xダメージ」、撃破時「敵{N} → P{M} を撃破」。
    /// HP=0 なら killedIds に追加して返す（呼び出し側 GameManager が handlePlayerDeath を発火する）。
    /// 武器なし（None）でここに到達した場合は防御的に何もしない。
    def applyDamageToPlayer(enemyId: Int32, enemy: Data, targetId: Int32,
                             scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \ {GameEngine.Game, GameLogger.GameLogger} =
        match (enemy#weapon, PlayerScene.get(targetId, scene)) {
            case (None, _)        => (scene, Nil)
            case (_, None)        => (scene, Nil)
            case (Some(weapon), Some(player)) =>
                let phys = UnitCatalog.isPhysical(weapon#weaponType);
                let totalAttack = Combat.attackStatFor(enemy#resource#attack,
                                                       enemy#resource#magicAttack,
                                                       weapon#attack, phys);
                let targetDef   = Combat.defenseStatFor(player#resource#defense,
                                                        player#resource#magicDefense,
                                                        phys);
                let dmg    = Combat.attackDamage(totalAttack, targetDef);
                let result = Combat.damage(hp = player#hp, amount = dmg);
                if (result#isDead) {
                    GameLogger.enemyLog("敵${enemyId} → P${targetId} を撃破")
                } else {
                    GameLogger.enemyLog("敵${enemyId} → P${targetId} に ${dmg}ダメージ")
                };
                // 被弾位置（プレイヤーの頭上）にダメージ数字を浮かす。撃破時も出す。
                let popupPos = MapScene.cellCenter(player#gridPos);
                let popupColor = DamagePopupScene.damageToPlayerColor();
                let withPopup = DamagePopupScene.emit(popupPos, dmg, popupColor, scene);
                let damaged = withPopup
                    |> PlayerScene.mapPlayer(targetId,
                        playerData -> {hp = result#newHp | playerData})
                    |> UnitHPBarScene.update(PlayerScene.playerPath(targetId), result#newHp);
                let consumed = Weapon.consume(weapon);
                if (Option.isEmpty(consumed))
                    GameLogger.enemyLog("敵${enemyId} の ${weapon#name} がこわれた")
                else ();
                let withWeaponUpdate = mapEnemy(enemyId,
                    d -> {weapon = consumed | d}, damaged);
                if (result#isDead) (withWeaponUpdate, targetId :: Nil)
                else (withWeaponUpdate, Nil)
        }

    /// 指定 id の敵が現在装備している武器を返す。未装備（壊れた後）なら None。
    /// EnemyAI 等が「攻撃できるか」を判定するために使う。
    pub def getWeapon(id: Int32, scene: Scene[NodeTag]): Option[UnitCatalog.WeaponResource] =
        match get(id, scene) {
            case Some(d) => d#weapon
            case None    => None
        }
}
