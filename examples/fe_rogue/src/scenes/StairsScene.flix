/// StairsScene — フロアの「次の階へ降りる階段」マーカー
///
/// 各フロアに 1 つだけ、床のランダムなセルに配置される。味方がそのセルに乗ると
/// 行動メニューに「かいだん」が出て、選ぶとその味方はマップから退場し次フロアへ進む。
///
/// ノード構造（Cursor と並列のトップレベル）:
///   Stairs (Marker2D, NodeTag.Stairs(Data))
///     └─ Sprite (Sprite2D, stairs.png)
///
/// 設計:
///   - 親 Marker2D に配置セルと placed フラグを持たせる
///   - 配置するまでは親 Marker2D を invisible にする（add 直後）
///   - `placeRandom` で床セルを 1 つ選び、`isAt` で「そのセルに階段があるか」を答える
mod StairsScene {

    /// `gridPos`: 階段を置いたグリッド座標（placed = false のときは未使用）
    /// `placed`: 階段が配置済みか。false の間は描画されず、`isAt` も常に false を返す
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        placed  = Bool
    }

    def name(): String = "Stairs"
    pub def stairsPath(): NodePath = name() :: Nil

    /// AssetPath.resolve は cwd を基点に解決するため、プロジェクトルートから実行が前提。
    def scenePath(): String = AssetPath.resolve("src/scenes/StairsScene.scene.json")

    /// MapScene 登録済みの scene に階段ノードを追加する（初期は未配置 = 非表示）。
    /// レイアウト（Marker2D + 子 Sprite2D, テクスチャ, scale, zIndex, 初期不可視）は
    /// `StairsScene.scene.json` に閉じ込めてあり、ロード後にゲーム状態 (`Data`) を
    /// `Scene.setState` で後付け注入する分業。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let initialData: Data = {gridPos = {x = 0, y = 0}, placed = false};
        SceneLoader.loadScene(scenePath(),
                               SceneLoader.constTagParser(NodeTag.NoTag),
                               scene)
            |> Scene.setState(stairsPath(), NodeTag.Stairs(initialData))

    /// 床セルからランダムに 1 つ選んで階段を配置する。
    /// 候補は「部屋の内部床セル かつ 駒（味方・敵）に占有されていない かつ 床アイテムが無い」セル。
    /// 部屋は anchor（プレイヤー初期配置, idx=0）を除いた idx 1..roomCount を対象にする
    /// （= 階段はスタート部屋以外に出す）。各部屋の `interiorCells`（decorTiles の world 座標）を
    /// そのまま使うので、door セル（通路の出入口）や通路の床は最初から候補に入らず、
    /// 階段が「通路にある」状態にならない。
    /// 候補が 1 つも無い極端なマップでは何もしない（階段は非表示のまま）。
    /// プレイヤー・敵・アイテム配置が済んだ後（= buildPlayingScene の末尾）に呼ぶ。
    pub def placeRandom(scene: Scene[NodeTag]): Scene[NodeTag] \ {Math.Random, World.Command} =
        let placements = MapScene.getPlacements(scene);
        let roomCount  = MapScene.getRoomCount(scene);
        let occupied   = List.append(
            PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
            EnemyScene.getAll(scene)  |> List.map(d -> d#gridPos));
        // anchor (idx=0) を除いた部屋だけを候補に（idx >= 1 かつ idx < roomCount = 部屋）
        let rooms = List.filter(p -> p#idx >= 1 and p#idx < roomCount, placements);
        let candidates = rooms
            |> List.flatMap(p -> p#interiorCells)
            |> List.filter(cell ->
                not isOccupied(cell, occupied)
                and Option.isEmpty(ItemScene.findAt(cell, scene)));
        match RandomUtil.pick(candidates) {
            case Some(cell) => placeAt(cell, scene)
            case None       => scene
        }

    def isOccupied(cell: {x = Int32, y = Int32},
                    occupied: List[{x = Int32, y = Int32}]): Bool =
        List.exists(o -> o#x == cell#x and o#y == cell#y, occupied)

    /// `target` セルに階段を配置する。scene ノード（位置更新 + 可視化 + Data）を書き、
    /// あわせて `Cmd.SetStairs(Some(cell))` を emit して World を権威に更新する（P3-a）。
    /// `placeRandom` の内部実装。テストからも床セルを固定して配置確認に使う。
    /// scene ノードは描画/フォグの view として残す（`renderSubtrees`/`applyFog` が読む）。gameplay の階段位置読みは
    /// `World.stairsPosOf` に flip 済み。
    pub def placeAt(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        let world = MapSnapshot.cellCenter(target);
        World.Command.emit(World.Cmd.SetStairs(Some(target)));
        scene
            |> Scene.setGlobalPositionAt(stairsPath(), world)
            |> mapStairs((marker, _) ->
                (CanvasItem.setVisible(true, marker),
                 ({gridPos = target, placed = true}: Data)))

    /// 指定セルに（配置済みの）階段があるか。ActionMenuScene が「かいだん」コマンドの
    /// 出現条件として使う。
    pub def isAt(gridPos: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(stairsPath(), scene) {
            case Some(NodeTag.Stairs(data)) =>
                data#placed
                and data#gridPos#x == gridPos#x
                and data#gridPos#y == gridPos#y
            case _ => false
        }

    /// placed = false（未配置）のときは座標として意味のある値を持たないため None を返す。
    pub def getPos(scene: Scene[NodeTag]): Option[{x = Int32, y = Int32}] =
        match Scene.getState(stairsPath(), scene) {
            case Some(NodeTag.Stairs(data)) =>
                if (data#placed) Some(data#gridPos) else None
            case _ => None
        }

    /// `Scene.mapEngineNode` のパターンマッチにより、Stairs 以外のノードは `other => other` で
    /// 素通しされるため、他ノードへの副作用なく安全に呼べる。
    def mapStairs(f: (Marker2D, Data) -> (Marker2D, Data),
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(stairsPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Stairs(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Stairs(newData))
            case other => other
        }, scene)

    /// フォグ適用: 配置済み(placed) かつ 現在地が lit のときだけ階段を表示する。
    /// 位置・placed・gridPos は素通し（`placeAt` と責務分離）。`FogScene` から毎フレーム呼ばれる。
    pub def applyFog(isLit: {x = Int32, y = Int32} -> Bool,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        mapStairs((marker, data) ->
            (CanvasItem.setVisible(data#placed and isLit(data#gridPos), marker), data),
            scene)

}
