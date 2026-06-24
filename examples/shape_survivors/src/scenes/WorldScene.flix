///
/// Shape Survivors — WorldScene（群れ駆動ノード ＋ 描画）
///
/// `WorldDriver` ノード（Marker2D）が純粋 `Model.World` を 1 個丸ごと抱える。
///   - process    : 入力・乱数（副作用）を集めて純粋 Update.step を回し、新しい World を node に戻す。
///                  HP が尽きたら GamePhaseState.put(GameOver) を要求する（局面遷移は effect 経由）。
///   - syncVisual : World から描画用の図形ノード（自機・敵群・弾群）と HUD を毎フレーム作り直す（純粋）。
///
/// 「ロジックは純粋層（game/）、presentation はここ」という分離を保つ。process だけが副作用を持ち、
/// syncVisual は Scene を組み替えるだけの純粋関数。
///
mod WorldScene {

    /// 色（赤・緑・青、各 0.0〜1.0）。エンジンの色は Float32 なので f32 を付ける。
    /// 背景色は scene.json 側で宣言しているので、ここには群れ（自機・敵・弾）の色だけ。
    type alias Rgb = {r = Float32, g = Float32, b = Float32}

    def playerColor(): Rgb = {r = 0.45f32, g = 0.85f32, b = 1.0f32}
    def invulnColor(): Rgb = {r = 1.0f32,  g = 1.0f32,  b = 1.0f32}  // 無敵中
    def enemyColor(): Rgb  = {r = 1.0f32,  g = 0.4f32,  b = 0.35f32}  // Grunt
    def tankColor(): Rgb   = {r = 0.8f32,  g = 0.35f32, b = 0.95f32}  // Tank（固い敵）
    def slashColor(): Rgb  = {r = 0.7f32,  g = 0.9f32,  b = 1.0f32}   // 薙ぎの閃き（淡い青白）
    def slashAlpha(): Float32 = 0.28f32                               // 半透明＝チカつかない
    def gemColor(): Rgb    = {r = 0.4f32,  g = 1.0f32,  b = 0.55f32}

    // --- ノードのパス・グループ ---
    // 静的構造は StageScene.scene.json の CanvasLayer "stage" 配下にあり、
    // WorldDriver と群れの図形も同じ "stage" 配下に置いて描画レイヤを揃える。
    def stageName(): String = "stage"
    def worldPath(): NodePath = stageName() :: "world" :: Nil
    def hudPath(): NodePath = stageName() :: "hud" :: Nil
    def swarmGroup(): String = "swarm"  // 毎フレーム作り直す図形ノード群（一括削除用）

    def sceneJsonPath(): String = "src/scenes/StageScene.scene.json"

    // ============================================================
    //  構築：静的構造（scene.json）＋ WorldDriver ＋ 初期の群れ
    // ============================================================

    /// scene.json の "tag" 文字列を NodeTag に変換する。未知タグは NoTag に倒す。
    def parseNodeTag(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None        => Ok(NodeTag.NoTag)
            case Some("Hud") => Ok(NodeTag.Hud)
            case Some(_)     => Ok(NodeTag.NoTag)
        }

    /// プレイ用シーンを 1 から組む。
    /// 静的構造（背景・HUD）は scene.json から読み込み、群れの状態を抱える WorldDriver を
    /// stage 配下に追加し、syncVisual で初期の図形を展開する。
    pub def buildScene(fontAtlas: FontAtlas): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let worldMarker = Marker2D.make({x = 0.0, y = 0.0});
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, parseNodeTag, Scene.empty())
            |> Scene.addChild(stageName(), "world",
                EngineNode.Marker2DWithState(worldMarker, NodeTag.WorldDriver(Model.initialWorld())))
            |> syncVisual

    // UI（メニュー・オーバーレイ）の描画順。群れ（z=0）より十分前に出す。
    def uiPanelZ(): Int32 = 90
    def uiTextZ(): Int32 = 100

    /// UI 背面の暗いパネル。後ろの群れを隠して文字を読みやすくする。
    def uiPanel(pos: Vec2.Vec2, size: Vec2.Vec2): ColorRect =
        ColorRect.make(size, {r = 0.03f32, g = 0.03f32, b = 0.09f32})
        |> Node2D.setPosition(pos)
        |> CanvasItem.setZIndex(uiPanelZ())

    /// ゲームオーバーの結果オーバーレイ（中央付近に3行）を最前面に重ねる。
    pub def addGameOverOverlay(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let seconds = secondsOf(scene);
        let kills = killsOf(scene);
        let panel = uiPanel({x = 110.0, y = 78.0}, {x = 270.0, y = 116.0});
        let title =
            Label2D.make("GAME OVER", fontAtlas, 32.0)
            |> Node2D.setPosition({x = 150.0, y = 96.0}) |> CanvasItem.setZIndex(uiTextZ());
        let result =
            Label2D.make("time ${seconds}s   kills ${kills}", fontAtlas, 16.0)
            |> Node2D.setPosition({x = 156.0, y = 140.0}) |> CanvasItem.setZIndex(uiTextZ());
        let prompt =
            Label2D.make("press Enter to retry", fontAtlas, 14.0)
            |> Node2D.setPosition({x = 162.0, y = 168.0}) |> CanvasItem.setZIndex(uiTextZ());
        scene
            |> Scene.addChild(stageName(), "over_panel", EngineNode.ColorRectWithState(panel, NodeTag.NoTag))
            |> Scene.addChild(stageName(), "over_title", EngineNode.Label2DWithState(title, NodeTag.NoTag))
            |> Scene.addChild(stageName(), "over_result", EngineNode.Label2DWithState(result, NodeTag.NoTag))
            |> Scene.addChild(stageName(), "over_prompt", EngineNode.Label2DWithState(prompt, NodeTag.NoTag))

    // ============================================================
    //  レベルアップ3択メニュー（engine の ItemList / MenuHandler を使う）
    // ============================================================

    def levelUpGroup(): String = "levelupui"  // メニューのノード群（確定後に一括削除）

    /// レベルアップ時に呼ばれ、強化4種からランダム3つを ItemList として重ねる。
    /// 選択肢は ItemList ノードのタグ `LevelUpMenu(choices)` に持たせ、確定時に idx で引く。
    pub def addLevelUpMenu(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let choices = randomChoices(3);
        let items = choices |> List.map(kind ->
            { text = Upgrade.label(kind), disabled = false, metadata = None });
        let panel = uiPanel({x = 118.0, y = 62.0}, {x = 244.0, y = 98.0});
        let menu =
            ItemList.make(items, fontAtlas, 12.0, {x = 150.0, y = 60.0})
            |> ItemList.setFocused(true)
            |> Node2D.setPosition({x = 150.0, y = 98.0})
            |> CanvasItem.setZIndex(uiTextZ());
        let header =
            Label2D.make("LEVEL UP!  choose:", fontAtlas, 16.0)
            |> Node2D.setPosition({x = 150.0, y = 72.0})
            |> CanvasItem.setZIndex(uiTextZ());
        scene
            |> Scene.addChild(stageName(), "levelup_panel",
                EngineNode.ColorRectWithState(panel, NodeTag.NoTag))
            |> Scene.addToGroup(stageName() :: "levelup_panel" :: Nil, levelUpGroup())
            |> Scene.addChild(stageName(), "levelup_header",
                EngineNode.Label2DWithState(header, NodeTag.NoTag))
            |> Scene.addToGroup(stageName() :: "levelup_header" :: Nil, levelUpGroup())
            |> Scene.addChild(stageName(), "levelup_menu",
                EngineNode.ItemListWithState(menu, NodeTag.LevelUpMenu(choices)))
            |> Scene.addToGroup(stageName() :: "levelup_menu" :: Nil, levelUpGroup())

    /// 強化4種からランダムに n 個（重複なし）。各要素に乱数キーを付けて並べ替え、先頭 n 個を取る。
    def randomChoices(n: Int32): List[Upgrade.Kind] \ Math.Random =
        Upgrade.all()
            |> List.map(kind -> (Math.Random.randomFloat64(), kind))
            |> List.sortBy(pair -> { let (key, _) = pair; key })
            |> List.map(pair -> { let (_, kind) = pair; kind })
            |> List.take(n)

    /// メニューで idx 番を確定したときの処理（MenuHandler から委譲）。
    /// 選んだ強化を World に適用し、メニューを消して Playing に戻す。
    pub def applyChosenUpgrade(idx: Int32, choices: List[Upgrade.Kind],
                               scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        let kind = List.nth(idx, choices) |> Option.getWithDefault(Upgrade.Kind.FireRate);
        let upgraded = match Scene.getState(worldPath(), scene) {
            case Some(NodeTag.WorldDriver(world)) =>
                Scene.setState(worldPath(), NodeTag.WorldDriver(Upgrade.apply(kind, world)), scene)
            case _ => scene
        };
        GamePhaseState.put(GamePhase.Playing);
        Scene.removeGroup(levelUpGroup(), upgraded)

    // ============================================================
    //  process：副作用を集めて純粋 step を回す（trait Node から委譲される）
    // ============================================================

    /// WorldDriver ノードの process。入力・乱数を読み、Update.step（純粋）で世界を 1 フレーム進め、
    /// 新しい World を node 状態に戻す。HP が尽きたら GameOver を要求する。
    pub def process(delta: Duration.Duration, node: EngineNode[NodeTag],
                    _path: NodePath, scene: Scene[NodeTag]):
                   (EngineNode[NodeTag], Scene[NodeTag]) \ {GameEngine.Game, Math.Random, GamePhaseState} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.WorldDriver(world)) =>
                let dt = Duration.toSeconds(delta);
                let direction = readInputDirection();       // 副作用：入力
                let spawnCandidate = randomEdgePosition();  // 副作用：乱数（湧き位置）
                let spawnKind = randomEnemyKind();          // 副作用：乱数（敵の種類）
                let stepped = Update.step(dt, direction, spawnCandidate, spawnKind, world);  // 純粋
                let leveledUp = stepped#level > world#level;
                // 局面遷移は hp / level を見て effect で要求する（死亡を優先）。
                // LevelUp の選択肢は applyPhaseChange→addLevelUpMenu 側で乱数生成する。
                if (stepped#hp <= 0) GamePhaseState.put(GamePhase.GameOver)
                else if (leveledUp) GamePhaseState.put(GamePhase.LevelUp)
                else ();
                // LevelUp でポーズすると tickSlashes が止まり閃きが残るので、入る瞬間に消す。
                let newWorld = if (leveledUp) { slashes = Nil | stepped } else stepped;
                (EngineNode.Marker2DWithState(marker, NodeTag.WorldDriver(newWorld)), scene)
            case _ => (node, scene)
        }

    /// 押されている方向キーを「方向ベクトル」として読む（effect: GameEngine.Game）。
    /// 左右（上下）を同時に押すと +1 と -1 で打ち消し合い、0 になる。
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

    /// スポーンする敵の種類を確率で決める（effect: Math.Random）。
    def randomEnemyKind(): Model.EnemyKind \ Math.Random =
        if (Math.Random.randomFloat64() < Model.tankSpawnChance()) Model.EnemyKind.Tank
        else Model.EnemyKind.Grunt

    /// 画面のどこかの端のランダムな点を返す（effect: Math.Random）。
    def randomEdgePosition(): Vec2.Vec2 \ Math.Random =
        let edge = Math.Random.randomFloat64();
        let t    = Math.Random.randomFloat64();
        let w = Int32.toFloat64(Model.designWi());
        let h = Int32.toFloat64(Model.designHi());
        if (edge < 0.25)      {x = t * w, y = 0.0}    // 上
        else if (edge < 0.5)  {x = t * w, y = h}      // 下
        else if (edge < 0.75) {x = 0.0,   y = t * h}  // 左
        else                  {x = w,     y = t * h}  // 右

    // ============================================================
    //  syncVisual：World → 描画用の図形ノード（純粋）
    // ============================================================

    /// WorldDriver が抱える World を読み、群れ（自機・敵・弾）の図形ノードを毎フレーム作り直し、
    /// HUD のテキストを更新する。Scene を組み替えるだけの純粋関数（effect 無し）。
    pub def syncVisual(scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(worldPath(), scene) {
            case Some(NodeTag.WorldDriver(world)) =>
                scene
                    |> Scene.removeGroup(swarmGroup())  // 前フレームの図形を一括削除
                    |> addPlayer(world)
                    // 敵・弾は四角形（Polygon2D）で描く。円（Arc2D）は 1 個 32 ポリゴンだが
                    // 四角形は 1 ポリゴンなので、数百体でも描画コストが約 1/32 で済む。
                    |> addSquares("gem", Model.gemRadius(), gemColor(),
                                  List.map(g -> g#pos, world#gems))
                    // 敵は種類ごとに大きさ・色を変えて描く（Grunt=赤小, Tank=紫大）
                    |> addSquares("grunt", Model.enemyVisualRadiusFor(Model.EnemyKind.Grunt), enemyColor(),
                                  enemyPositionsOfKind(Model.EnemyKind.Grunt, world))
                    |> addSquares("tank", Model.enemyVisualRadiusFor(Model.EnemyKind.Tank), tankColor(),
                                  enemyPositionsOfKind(Model.EnemyKind.Tank, world))
                    |> addSlashes(world#slashes)  // 薙ぎの閃き（広い矩形）を敵の上に重ねる
                    |> updateHud(world)
            case _ => scene
        }

    /// 指定した種類の敵の位置だけを取り出す（描画を種類ごとに分けるため）。
    def enemyPositionsOfKind(kind: Model.EnemyKind, world: Model.World): List[Vec2.Vec2] =
        world#enemies |> List.filterMap(enemy ->
            if (enemy#kind == kind) Some(enemy#pos) else None)

    /// 自機（円）。無敵中は白く光らせる。群れグループに入れて毎フレーム作り直す。
    def addPlayer(world: Model.World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let color = if (world#invulnLeft > 0.0) invulnColor() else playerColor();
        addCircle("player", Model.playerRadius(), color, world#player, scene)

    /// 1 個の円ノードを stage 配下に、群れグループとして追加する。
    def addCircle(name: String, radius: Float64, color: Rgb,
                  pos: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        let circle =
            Arc2D.make(radius, radius, 0.0, Arc2D.tau(), color)
            |> Node2D.setPosition(pos);
        scene
            |> Scene.addChild(stageName(), name, EngineNode.Arc2DWithState(circle, NodeTag.NoTag))
            |> Scene.addToGroup(stageName() :: name :: Nil, swarmGroup())

    /// 中心まわりの正方形（半幅 half）の頂点。Polygon2D は局所座標の点列なので原点中心で作り、
    /// 位置は Node2D.setPosition で与える。
    def squarePoints(half: Float64): List[Vec2.Vec2] =
        {x = 0.0 - half, y = 0.0 - half} ::
        {x = half,       y = 0.0 - half} ::
        {x = half,       y = half} ::
        {x = 0.0 - half, y = half} :: Nil

    /// 1 個の四角ノードを stage 配下に、群れグループとして追加する（四角形＝1 ポリゴン）。
    def addSquare(name: String, half: Float64, color: Rgb,
                  pos: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        let square =
            Polygon2D.make(squarePoints(half), color)
            |> Node2D.setPosition(pos);
        scene
            |> Scene.addChild(stageName(), name, EngineNode.Polygon2DWithState(square, NodeTag.NoTag))
            |> Scene.addToGroup(stageName() :: name :: Nil, swarmGroup())

    /// 薙ぎの閃き群を、向いた側へ伸びる広い矩形（Polygon2D）として群れグループに足す。
    def addSlashes(slashes: List[Model.Slash], scene: Scene[NodeTag]): Scene[NodeTag] =
        let keyed = slashes |> List.mapWithIndex((index, slash) -> ("slash${index}", slash));
        keyed |> List.foldLeft((sc, keyAndSlash) -> {
            let (key, slash) = keyAndSlash;
            let poly =
                Polygon2D.make(slashPoints(slash#right), slashColor())
                |> Polygon2D.setAlpha(slashAlpha())
                |> Node2D.setPosition(slash#pos);
            sc
                |> Scene.addChild(stageName(), key, EngineNode.Polygon2DWithState(poly, NodeTag.NoTag))
                |> Scene.addToGroup(stageName() :: key :: Nil, swarmGroup())
        }, scene)

    /// 薙ぎ矩形の頂点（自機位置を原点とする局所座標）。enemyInWhip の判定範囲と一致させる。
    def slashPoints(right: Bool): List[Vec2.Vec2] =
        let h = Model.whipHalfHeight();
        let reach = Model.whipReach();
        let back = Model.whipBackMargin();
        if (right)
            {x = 0.0 - back, y = 0.0 - h} :: {x = reach,      y = 0.0 - h} ::
            {x = reach,      y = h}       :: {x = 0.0 - back, y = h}       :: Nil
        else
            {x = back,        y = 0.0 - h} :: {x = 0.0 - reach, y = 0.0 - h} ::
            {x = 0.0 - reach, y = h}       :: {x = back,        y = h}       :: Nil

    /// 位置のリストを、同じ大きさ・色の四角ノード群として群れグループに足す（"enemy0", "enemy1", ...）。
    def addSquares(prefix: String, half: Float64, color: Rgb,
                   positions: List[Vec2.Vec2], scene: Scene[NodeTag]): Scene[NodeTag] =
        let keyed = positions |> List.mapWithIndex((index, pos) -> ("${prefix}${index}", pos));
        keyed |> List.foldLeft((sc, keyAndPos) -> {
            let (key, pos) = keyAndPos;
            addSquare(key, half, color, pos, sc)
        }, scene)

    /// HUD ラベルのテキストだけ更新する（位置・フォントは buildScene で固定済み）。
    def updateHud(world: Model.World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let seconds = Float64.truncateToInt32(Float64.floor(world#elapsed));
        let text = "HP ${world#hp}/${world#maxHp}  Lv ${world#level}  "
            + "XP ${world#xp}/${Model.xpThreshold(world#level)}  kills ${world#kills}  ${seconds}s";
        Scene.mapEngineNode(hudPath(), EngineNode.mapLabel2D(Label2D.setText(text)), scene)

    // --- ゲームオーバー表示用に World からスコアを取り出す小道具 ---

    def worldOf(scene: Scene[NodeTag]): Option[Model.World] =
        match Scene.getState(worldPath(), scene) {
            case Some(NodeTag.WorldDriver(world)) => Some(world)
            case _ => None
        }

    def secondsOf(scene: Scene[NodeTag]): Int32 =
        worldOf(scene)
            |> Option.map(world -> Float64.truncateToInt32(Float64.floor(world#elapsed)))
            |> Option.getWithDefault(0)

    def killsOf(scene: Scene[NodeTag]): Int32 =
        worldOf(scene) |> Option.map(world -> world#kills) |> Option.getWithDefault(0)
}
