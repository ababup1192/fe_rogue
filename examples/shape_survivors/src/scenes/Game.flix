///
/// Shape Survivors — 回1: 自機が動き、敵が湧いて追ってくる
///
/// MVU（Model-View-Update）で組む：
///   - World（Model）  : ゲームの状態を表す「ただの値」。可変変数は使わない。
///   - step  (Update)  : 入力と前フレームの World から「新しい World」を作る純粋関数。
///   - view  (View)    : World から描画用の Scene を組み立てる純粋関数。
///
/// 敵の大群は `List[Enemy]`。全員を毎フレーム追尾させるのは `List.map` 一発。
/// 乱数（スポーン位置）は副作用なので step には入れず、gameLoop（シェル）側に閉じ込める。
/// こうして step / view は「同じ入力なら必ず同じ結果」の純粋関数のままに保つ。
///
/// 設計の全体像は同じディレクトリの DESIGN.md を参照。
///
mod Game {

    /// ノード識別タグ。view が組む図形はどれも状態を持たないので、今は NoTag だけ。
    pub enum NodeTag with Eq {
        case NoTag
    }

    /// 敵 1 体。今は位置だけ。HP や種別はあとで増やす。
    type alias Enemy = {
        pos = Vec2.Vec2
    }

    /// ゲームの状態（Model）。
    type alias World = {
        player    = Vec2.Vec2,    // 自機の位置
        enemies   = List[Enemy],  // 敵の大群
        sinceSpawn = Float64      // 前回スポーンからの経過秒（スポーン間隔の判定用）
    }

    // --- 定数 ---

    def designWi(): Int32 = 480
    def designHi(): Int32 = 270

    def playerSpeed(): Float64 = 110.0  // 自機の移動速度（px/秒）
    def playerRadius(): Float64 = 12.0

    def enemySpeed(): Float64 = 55.0    // 敵の速度（自機より遅い＝引き撃ちで避けられる）
    def enemyRadius(): Float64 = 7.0

    def spawnInterval(): Float64 = 0.7  // 何秒ごとに 1 体湧くか
    def maxEnemies(): Int32 = 120       // 上限（まだ敵を倒せないので無制限に増えないよう蓋）

    /// 起動エントリ。初期 World から描画ループを始める。
    /// 乱数を使う（スポーン）ので effect に `Math.Random` が増える。
    pub def start(fontAtlas: FontAtlas): Unit \ {GameEngine.Game, Math.Random} =
        gameLoop(fontAtlas, initialWorld())

    /// ゲーム開始時の World。自機は中央、敵はまだいない。
    def initialWorld(): World =
        { player = {x = Int32.toFloat64(designWi()) / 2.0,
                    y = Int32.toFloat64(designHi()) / 2.0},
          enemies = Nil,
          sinceSpawn = 0.0 }

    // ============================================================
    //  シェル（副作用あり）：入力と乱数を読む
    // ============================================================

    /// 押されている方向キーを「方向ベクトル」として読む（effect: GameEngine.Game）。
    def readInputDirection(): Vec2.Vec2 \ GameEngine.Game =
        let xDir =
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.D) or
                 GameEngine.Game.isKeyPressed(GameEngine.Key.Right))  1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.A) or
                 GameEngine.Game.isKeyPressed(GameEngine.Key.Left))  -1.0 else 0.0);
        let yDir =
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.S) or
                 GameEngine.Game.isKeyPressed(GameEngine.Key.Down))   1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.W) or
                 GameEngine.Game.isKeyPressed(GameEngine.Key.Up))    -1.0 else 0.0);
        {x = xDir, y = yDir}

    /// 画面のどこかの端のランダムな点を返す（effect: Math.Random）。
    /// 「乱数を使う」ことが型 `\ Math.Random` に現れる ── 純粋な step との対比で読んでほしい。
    def randomEdgePosition(): Vec2.Vec2 \ Math.Random =
        let edge = Math.Random.randomFloat64();  // どの辺か（0..1）
        let t    = Math.Random.randomFloat64();  // 辺に沿った位置（0..1）
        let w = Int32.toFloat64(designWi());
        let h = Int32.toFloat64(designHi());
        if (edge < 0.25)      {x = t * w, y = 0.0}    // 上
        else if (edge < 0.5)  {x = t * w, y = h}      // 下
        else if (edge < 0.75) {x = 0.0,   y = t * h}  // 左
        else                  {x = w,     y = t * h}  // 右

    // ============================================================
    //  純粋なコア（effect なし）：step とその部品
    // ============================================================

    /// 純粋な更新関数。前フレームの world ＋ 入力方向 ＋ スポーン候補位置から
    /// 「新しい world」を作る。シグネチャに `\` が無い ＝ 副作用ゼロ。
    /// （スポーンするか否かの判定は純粋。ランダムな「位置」だけを外から受け取る）
    def step(dt: Float64, direction: Vec2.Vec2, spawnCandidate: Vec2.Vec2, world: World): World =
        let player  = movePlayer(dt, direction, world#player);
        let chased  = world#enemies |> List.map(enemy -> chaseEnemy(dt, player, enemy));
        let elapsed = world#sinceSpawn + dt;
        let (enemies, sinceSpawn) =
            if (elapsed >= spawnInterval() and List.length(chased) < maxEnemies())
                ({pos = spawnCandidate} :: chased, 0.0)  // 大群に 1 体追加（先頭に cons）
            else
                (chased, elapsed);
        { player = player, enemies = enemies, sinceSpawn = sinceSpawn }

    /// 自機を入力方向へ動かし、画面内に収める（純粋）。
    def movePlayer(dt: Float64, direction: Vec2.Vec2, position: Vec2.Vec2): Vec2.Vec2 =
        let velocity =
            if (Vec2.length(direction) > 0.0)
                Vec2.mul(Vec2.normalized(direction), playerSpeed() * dt)  // 斜めでも速さ一定
            else
                Vec2.zero();
        clampToScreen(Vec2.add(position, velocity))

    /// 敵 1 体を自機へ近づける（純粋）。List.map でこれを全敵に適用する。
    def chaseEnemy(dt: Float64, target: Vec2.Vec2, enemy: Enemy): Enemy =
        let toTarget = Vec2.sub(target, enemy#pos);
        let velocity =
            if (Vec2.length(toTarget) > 0.0)
                Vec2.mul(Vec2.normalized(toTarget), enemySpeed() * dt)
            else
                Vec2.zero();
        { pos = Vec2.add(enemy#pos, velocity) }

    /// 自機が画面の外に出ないよう、半径ぶん内側に収める（純粋）。
    def clampToScreen(position: Vec2.Vec2): Vec2.Vec2 =
        let radius = playerRadius();
        let maxX = Int32.toFloat64(designWi()) - radius;
        let maxY = Int32.toFloat64(designHi()) - radius;
        {x = Float64.max(radius, Float64.min(maxX, position#x)),
         y = Float64.max(radius, Float64.min(maxY, position#y))}

    // ============================================================
    //  View（純粋）：World → Scene
    // ============================================================

    /// 純粋な描画関数。World から表示する Scene を組み立てる（effect 無し）。
    def view(world: World, fontAtlas: FontAtlas): Scene[NodeTag] =
        let bg =
            ColorRect.make(
                {x = Int32.toFloat64(designWi()), y = Int32.toFloat64(designHi())},
                {r = 0.07f32, g = 0.08f32, b = 0.12f32}
            ) |> CanvasItem.setZIndex(-100);

        let player =
            Arc2D.make(playerRadius(), playerRadius(), 0.0, Arc2D.tau(),
                       {r = 0.45f32, g = 0.85f32, b = 1.0f32})
            |> Node2D.setPosition(world#player);

        let countLabel =
            Label2D.make("enemies: ${List.length(world#enemies)}", fontAtlas, 14.0)
            |> Node2D.setPosition({x = 10.0, y = 8.0});

        Scene.empty()
            |> Scene.addNode("background", EngineNode.ColorRectWithState(bg, NodeTag.NoTag))
            |> addEnemies(world#enemies)
            |> Scene.addNode("player", EngineNode.Arc2DWithState(player, NodeTag.NoTag))
            |> Scene.addNode("count", EngineNode.Label2DWithState(countLabel, NodeTag.NoTag))

    /// 敵の大群を Scene に追加する。foldLeft で「(連番, Scene)」を畳み込み、
    /// それぞれ "enemy0", "enemy1", ... という名前で円ノードを足す。
    def addEnemies(enemies: List[Enemy], scene: Scene[NodeTag]): Scene[NodeTag] =
        let (_, result) =
            List.foldLeft(
                (acc, enemy) -> {
                    let (index, sc) = acc;
                    (index + 1, Scene.addNode("enemy${index}", enemyNode(enemy), sc))
                },
                (0, scene),
                enemies);
        result

    /// 敵 1 体を表す円ノード。
    def enemyNode(enemy: Enemy): EngineNode[NodeTag] =
        let circle =
            Arc2D.make(enemyRadius(), enemyRadius(), 0.0, Arc2D.tau(),
                       {r = 1.0f32, g = 0.4f32, b = 0.35f32})
            |> Node2D.setPosition(enemy#pos);
        EngineNode.Arc2DWithState(circle, NodeTag.NoTag)

    // ============================================================
    //  メインループ：副作用を全てここに集約する
    // ============================================================

    /// 終了判定 → 入力・乱数（シェル） → 純粋更新 → 描画 → 末尾再帰。
    def gameLoop(fontAtlas: FontAtlas, world: World): Unit \ {GameEngine.Game, Math.Random} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape))
            ()
        else {
            let dt = Duration.toSeconds(GameEngine.Game.getDeltaTime());
            let direction = readInputDirection();       // 副作用：入力
            let spawnCandidate = randomEdgePosition();  // 副作用：乱数
            let nextWorld = step(dt, direction, spawnCandidate, world);  // 純粋
            GameEngine.render(view(nextWorld, fontAtlas));               // 副作用：描画
            gameLoop(fontAtlas, nextWorld)
        }
}
