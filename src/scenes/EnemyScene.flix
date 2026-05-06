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
    pub type alias Data = {
        id            = Int32,
        gridPos       = Vec2.Vec2i,
        alerted       = Bool,
        homeModuleIdx = Int32,
        moveTiles     = Int32
    }

    /// スポーン時の中間表現。`add` 内のループで部屋ごとに積み上げ、最後に Marker2D へ展開する。
    type alias Spawn = {
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

    /// 1 マス分のスライド時間（秒）。Player と同じ感覚で見えるよう揃える。
    def slideDuration(): Float64 = 16.0 / 120.0

    /// "Enemy_3" のようなトップレベルノード名。
    pub def enemyName(id: Int32): String = "Enemy_${id}"

    /// "Enemy_3" 1 つだけの NodePath（敵はトップレベルに並べる）。
    pub def enemyPath(id: Int32): NodePath = enemyName(id) :: Nil

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
        let playerPos   = PlayerScene.getGridPos(scene);
        // anchor (idx = 0) を除いた部屋だけを対象にする
        let rooms = List.filter(p ->
            p#idx >= 1 and p#idx < roomCount, placements);
        // 部屋を順に走査し、(nextId, takenCells, spawns) を畳み込む。
        // pickCellsInRoom が `Math.Random` を持つので畳み込み全体も `Math.Random`。
        let initial: (Int32, List[Vec2.Vec2i], List[Spawn]) =
            (0, playerPos :: Nil, Nil);
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
            id            = sp#id,
            gridPos       = sp#gridPos,
            alerted       = false,
            homeModuleIdx = sp#moduleIdx,
            moveTiles     = defaultMoveTiles()
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
}
