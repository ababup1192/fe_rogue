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
    /// `moveTiles` は 1 ターンに進めるマス数（FE の「移動力」相当）。
    /// EnemyAI が BFS パスからこの値ぶんだけ進めて 1 マスずつ Tween する。
    /// `hp` は残り体力。0 になると `isDying = true` がセットされ、`death_blink`
    /// アニメーションが再生される。アニメ終了で GameManager がノードを scene から削除する。
    /// `isDying = true` の敵は `EnemyTurn.Queue` / `findIdAt` などから除外され、行動しない。
    pub type alias Data = {
        id             = Int32,
        gridPos        = Vec2.Vec2i,
        alerted        = Bool,
        homeModuleIdx  = Int32,
        moveTiles      = Int32,
        hp             = Int32,
        isDying        = Bool,
        attackTargetId = Option[Int32]
    }

    /// スポーン時の中間表現。`add` 内のループで部屋ごとに積み上げ、最後に Marker2D へ展開する。
    /// `respawnFromInitial` で「ゲームオーバー時に同じ位置に敵を出し直す」のにも使うため pub。
    pub type alias Spawn = {
        id        = Int32,
        gridPos   = Vec2.Vec2i,
        moduleIdx = Int32
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// 敵スプライトのテクスチャ（Main.flix の textureManifest と整合）
    def textureName(): String = "character_sheet"

    /// `character_sheet_grid_16.png` のグリッド分割（5 列 × 2 行）。
    /// PlayerScene.scene.json と同じ値で、上段一番右 = frame index 4。
    def hframes(): Int32 = 5
    def vframes(): Int32 = 2
    def spriteFrame(): Int32 = 4

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える。
    def tileSize(): Float64 = 16.0

    /// プレイヤーと同じ高さで前面に立つ。MoveRange (1) より上。
    def spriteZIndex(): Int32 = 10

    /// 1 部屋あたりのスポーン上限（実数は 0..maxPerRoom inclusive のランダム）。
    def maxPerRoom(): Int32 = 2

    /// 敵初期の移動力（マス）。`Data#moveTiles` の初期値として使う。
    pub def defaultMoveTiles(): Int32 = 3

    /// 敵初期 HP。スポーン時とリセット時の `Data#hp` 初期値。
    pub def defaultHp(): Int32 = 3

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

    /// "Enemy_3" のようなトップレベルノード名。
    pub def enemyName(id: Int32): String = "Enemy_${id}"

    /// "Enemy_3" 1 つだけの NodePath（敵はトップレベルに並べる）。
    pub def enemyPath(id: Int32): NodePath = enemyName(id) :: Nil

    /// 敵 id の子 Sprite ノードへのパス。alpha 補間 (Tween.tweenAlpha) のターゲットに使う。
    pub def spritePath(id: Int32): NodePath = enemyName(id) :: "Sprite" :: Nil

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene が登録済みの scene に敵を追加する。
    /// 各部屋について 0..maxPerRoom 体のスポーン位置を決め、それぞれを
    /// Marker2D + 子 Sprite2D として登録する。`Math.Random` を使うのでこの effect が必要。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random} =
        let layer       = MapScene.getMapLayer(scene);
        let placements  = MapScene.getPlacements(scene);
        let roomCount   = MapScene.getRoomCount(scene);
        // パーティ全員のセルを taken に入れて避ける（敵が味方の上にスポーンしないように）
        let playerCells = PlayerScene.getAll(scene) |> List.map(d -> d#gridPos);
        // anchor (idx = 0) を除いた部屋だけを対象にする
        let rooms = List.filter(p ->
            p#idx >= 1 and p#idx < roomCount, placements);
        // 部屋を順に走査し、(nextId, takenCells, spawns) を畳み込む。
        // pickCellsInRoom が `Math.Random` を持つので畳み込み全体も `Math.Random`。
        let initial: (Int32, List[Vec2.Vec2i], List[Spawn]) =
            (0, playerCells, Nil);
        let (_, _, accSpawns) = List.foldLeft(state -> p ->
            spawnInRoom(layer, p, randomCountUpTo(maxPerRoom()), state),
            initial, rooms);
        // accSpawns は逆順（cons で積んだ）なので reverse して id 昇順に揃える
        let spawns = List.reverse(accSpawns);
        List.foldLeft(acc -> sp -> addOneEnemy(sp, acc), scene, spawns)

    /// 0 以上 max 以下のランダム整数を返す（max + 1 通り）。
    /// `Math.Random.randomFloat64` は [0.0, 1.0) なので
    /// `floor(r * (max + 1))` で {0, 1, ..., max} に均等射影できる。
    def randomCountUpTo(max: Int32): Int32 \ Math.Random =
        let r = Math.Random.randomFloat64();
        let n = Int32.toFloat64(max + 1);
        Float64.truncateToInt32(Float64.floor(r * n))

    /// 部屋 1 つから `count` 個のスポーンセルを選んで state に積む。
    /// state = (次に振る id, スポーン済みセル累積, spawn list 累積)。
    /// 候補不足のときは取れる分だけ積んで打ち切る。
    def spawnInRoom(layer: TileMapLayer,
                     p: DungeonComposer.ModulePlacement,
                     count: Int32,
                     state: (Int32, List[Vec2.Vec2i], List[Spawn])):
                    (Int32, List[Vec2.Vec2i], List[Spawn]) \ Math.Random =
        if (count <= 0) state
        else
            let (nextId, taken, list) = state;
            let candidates = floorCellsInRoom(layer, p)
                              |> List.filter(c -> not isTaken(c, taken));
            match RandomUtil.pick(candidates) {
                case None       => state   // 候補ゼロで打ち切り
                case Some(cell) =>
                    let entry: Spawn = { id = nextId, gridPos = cell, moduleIdx = p#idx };
                    spawnInRoom(layer, p, count - 1,
                                 (nextId + 1, cell :: taken, entry :: list))
            }

    /// 部屋の bbox（offset + gridSize）に含まれる床セルを列挙する。
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[Vec2.Vec2i] =
        let minX = p#offset#x;
        let minY = p#offset#y;
        let maxX = p#offset#x + p#gridSize#x;
        let maxY = p#offset#y + p#gridSize#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        List.flatMap(y ->
            List.filter(c -> TileMapLayer.isFloor(c, layer),
                List.map(x -> ({x = x, y = y}: Vec2.Vec2i), xs)),
            ys)

    def isTaken(c: Vec2.Vec2i, taken: List[Vec2.Vec2i]): Bool =
        List.exists(t -> t#x == c#x and t#y == c#y, taken)

    /// 1 体ぶんの Marker2D + 子 Sprite2D を scene に追加する。
    def addOneEnemy(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        let pos: Vec2.Vec2 = {
            x = Int32.toFloat64(sp#gridPos#x) * s + s / 2.0,
            y = Int32.toFloat64(sp#gridPos#y) * s + s / 2.0
        };
        let marker = Marker2D.make(pos);
        let data: Data = {
            id             = sp#id,
            gridPos        = sp#gridPos,
            alerted        = false,
            homeModuleIdx  = sp#moduleIdx,
            moveTiles      = defaultMoveTiles(),
            hp             = defaultHp(),
            isDying        = false,
            attackTargetId = None
        };
        let sprite = Sprite2D.make(textureName(), Vec2.zero(), Vec2.one())
                        |> Sprite2D.setHframes(hframes())
                        |> Sprite2D.setVframes(vframes())
                        |> Sprite2D.setFrame(spriteFrame())
                        |> CanvasItem.setZIndex(spriteZIndex());
        scene
            |> Scene.addNode(enemyName(sp#id),
                              EngineNode.Marker2DWithState(marker, NodeTag.Enemy(data)))
            |> Scene.addChild(enemyName(sp#id), "Sprite",
                               EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

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
    pub def moveTo(id: Int32, target: Vec2.Vec2i,
                    map: MapSnapshot,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        let startWorld  = Scene.globalPositionAt(enemyPath(id), scene);
        let targetWorld = map#gridToWorld(target);
        Tween.tweenPosition(enemyPath(id), startWorld, targetWorld, slideDuration());
        mapEnemy(id, d -> {gridPos = target | d}, scene)

    /// 指定セルに居る（生きている）敵の id を返す。死亡演出中の敵は対象外。
    /// PlayerAttack フェーズで「カーソルが赤マス上の敵に乗っているか」の判定に使う。
    pub def findIdAt(coord: Vec2.Vec2i, scene: Scene[NodeTag]): Option[Int32] =
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

    /// `Enemy_<id>` 形式の NodePath から id を取り出す。それ以外なら None。
    /// AnimationPlayer の finished イベントを scene 別に振り分けるために使う。
    pub def idFromPath(path: NodePath): Option[Int32] =
        match path {
            case name :: Nil =>
                if (String.startsWith({prefix = "Enemy_"}, name))
                    String.dropLeft(6, name) |> Int32.fromString
                else None
            case _ => None
        }

    // ────────────────────────────────────────────────────────
    // (F) 初期 spawn のスナップショットと再配置（ゲームオーバー時のリセット）
    // ────────────────────────────────────────────────────────

    /// 現在 scene に居る全敵の `Spawn` 情報（id / gridPos / homeModuleIdx）を抽出する。
    /// `Game.start` で初回 buildPlayingScene 直後に呼んで保存し、ゲームオーバー時に
    /// `respawnFromInitial` で再配置する。
    pub def snapshotSpawns(scene: Scene[NodeTag]): List[Spawn] =
        getAll(scene)
            |> List.map(d ->
                ({id = d#id, gridPos = d#gridPos, moduleIdx = d#homeModuleIdx}: Spawn))

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
    pub def startAttack(id: Int32, targetPlayerId: Int32,
                         targetGrid: Vec2.Vec2i,
                         scene: Scene[NodeTag]): Scene[NodeTag]
            \ AnimationPlayer.Scheduler =
        match get(id, scene) {
            case None    => scene
            case Some(d) =>
                AnimationPlayer.play(enemyPath(id),
                    PlayerScene.attackLungeAnimation(enemyPath(id),
                                                       d#gridPos, targetGrid));
                mapEnemy(id, dd -> {attackTargetId = Some(targetPlayerId) | dd}, scene)
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
            {GameEngine.Audio, GameLogger.GameLogger} =
        match get(enemyId, scene) {
            case None    => (scene, Nil)
            case Some(d) =>
                match d#attackTargetId {
                    case None             => (scene, Nil)
                    case Some(targetPlayerId) =>
                        AudioStreamPlayer.play("damage");
                        applyDamageToPlayer(enemyId, targetPlayerId, scene)
                }
        }

    /// `attack_lunge` finished 時に呼ばれる。`attackTargetId` をクリアする。
    pub def clearAttackTarget(enemyId: Int32,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        mapEnemy(enemyId, d -> {attackTargetId = None | d}, scene)

    /// プレイヤー targetId に 1 ダメージ。HP=0 なら killedIds に追加して返す
    /// （呼び出し側 GameManager が handlePlayerDeath を発火する）。
    /// HP の減算と死亡判定は `Combat.damage` に集約してある。
    def applyDamageToPlayer(enemyId: Int32, targetId: Int32,
                             scene: Scene[NodeTag]):
            (Scene[NodeTag], List[Int32]) \ GameLogger.GameLogger =
        match PlayerScene.get(targetId, scene) {
            case None    => (scene, Nil)
            case Some(player) =>
                let result = Combat.damage(hp = player#hp, amount = 1);
                GameLogger.enemyLog(
                    "敵${enemyId}が味方${targetId}を攻撃 残りHP${result#newHp}");
                let damaged = PlayerScene.mapPlayer(targetId,
                    playerData -> {hp = result#newHp | playerData}, scene);
                if (result#isDead) (damaged, targetId :: Nil)
                else (damaged, Nil)
        }
}
