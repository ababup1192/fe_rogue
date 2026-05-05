/// 複数の LDTK モジュール（部屋・通路）を 1 枚の TileMapLayer にマージする。
///
/// 設計方針: 「配置決定」と「合成」を分離する。
///   - 配置（どの ldtkPath を どの offsetGrid に置くか）は呼び出し側が決める。
///   - どの Door セルを開ける（壁→床）かも呼び出し側がワールド座標で指定する。
///   - 本モジュールは与えられた仕様を素直にマージするだけで、ランダム性や
///     方向判定のような決定ロジックは持たない。これにより将来 DungeonPlanner が
///     上に乗っかってランダムダンジョンを作る際にも、API は変えずに済む。
///
/// マージ手順:
///   1. 各モジュールを LDTKLoader.loadLevelRaw で読み込む（GPU アップロードなし）。
///   2. tiles の px と collisionCells を offsetGrid * tileSize / offsetGrid だけずらす。
///   3. 全モジュールの結果を結合する。
///   4. openDoors（ワールド座標）に該当する collisionCells と TileData を取り除く。
///      これで Door 位置の壁が床になる。openDoors に含まれない Door は壁のまま残る。
///   5. Overlap 配置で同じセルに重複する壁を 1 つに dedup する。
///   6. GPU インスタンスを構築し、initTileBuffer を 1 回だけ呼んで TileMapLayer を返す。
mod DungeonComposer {

    /// 1 モジュール（LDTK ファイル）の配置仕様。
    /// offsetGrid はグリッド単位の左上配置位置（例: {x = 8, y = 0} なら 8 セル右にずらす）。
    pub type alias ModuleSpec = {
        ldtkPath   = String,
        offsetGrid = Vec2.Vec2i
    }

    /// 配置済みモジュール群を 1 枚の TileMapLayer にマージする。
    /// openDoors にはワールド座標（オフセット適用後）のセルを渡す。
    /// 該当セルは壁から床に書き換えられる。
    /// 全モジュールは同一 textureName のタイルセットを使う前提（混ぜたい場合は別途設計が必要）。
    pub def compose(textureName: String,
                     modules: List[ModuleSpec],
                     openDoors: List[Vec2.Vec2i]): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        match modules {
            case Nil => bug!("DungeonComposer: modules must not be empty")
            case _   => composeNonEmpty(textureName, modules, openDoors)
        }

    /// modules が非空であることを前提にした本体。tileSet を最初のモジュールから採用する。
    def composeNonEmpty(textureName: String,
                         modules: List[ModuleSpec],
                         openDoors: List[Vec2.Vec2i]): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        // 1. すべてのモジュールをロードして offsetGrid 分平行移動する
        let placed = List.map(spec -> loadAndOffset(textureName, spec), modules);

        // tileSet と tileSize は全モジュール共通の前提（最初のモジュールから採用）。
        // modules 非空は呼び出し側 compose で保証済み。
        let firstRaw = match List.head(placed) {
            case Some(r) => r
            case None    => bug!("DungeonComposer: composeNonEmpty received empty placed list")
        };
        let tileSet  = firstRaw#tileSet;
        let tileSize = firstRaw#tileSize;

        // 2. 全モジュールの tiles / collisionCells を結合
        let mergedTiles      = List.flatMap(p -> p#tiles, placed);
        let mergedCollisions = List.flatMap(p -> p#collisionCells, placed);

        // 3. openDoors（ワールド座標）に該当する壁を取り除く
        let doorCellsF: List[Vec2.Vec2] = List.map(c -> Vec2.fromI(c), openDoors);
        let doorPxs:    List[Vec2.Vec2] = List.map(c -> Vec2.mul(Vec2.fromI(c), tileSize),
                                                    openDoors);

        let openedCollisions =
            List.filter(cell -> not (doorCellsF |> List.exists(d -> vec2Eq(d, cell))),
                        mergedCollisions);
        let openedTiles =
            List.filter(tile -> not (doorPxs |> List.exists(p -> vec2Eq(p, tile#px))),
                        mergedTiles);

        // 4. dedup（Overlap 領域で同じセルに壁が二重に入るのを防ぐ）
        let dedupedCollisions = dedupVec2(openedCollisions);
        let dedupedTiles      = dedupTiles(openedTiles);

        // 5. 全体の grid サイズ（モジュール bounding box）
        let mergedGridSize = boundingBoxGridSize(modules, placed);

        // 6. GPU インスタンスを 1 回だけアップロード
        let instances = LDTKLoader.buildTileInstances(dedupedTiles, tileSet, tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);

        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = dedupedTiles,
            collisionCells = dedupedCollisions,
            gridSize       = mergedGridSize
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount)

    /// 1 モジュールをロードして offsetGrid 分だけタイル / 衝突セルを平行移動する。
    /// 戻り値は offset 適用済みの LDTKLevelRaw。
    def loadAndOffset(textureName: String, spec: ModuleSpec): LDTKLoader.LDTKLevelRaw
            \ { GameEngine.Game, Fs.FileRead } =
        let raw = LDTKLoader.loadLevelRaw(LDTKLoader.simpleConfig({
            path = spec#ldtkPath,
            textureName = textureName
        }));
        let tileSize  = raw#tileSize;
        let offsetPx  = Vec2.mul(Vec2.fromI(spec#offsetGrid), tileSize);
        let offsetCell: Vec2.Vec2 = Vec2.fromI(spec#offsetGrid);

        let shiftedTiles = List.map(tile -> {
            { px = Vec2.add(tile#px, offsetPx) | tile }
        }, raw#tiles);
        let shiftedCollisions = List.map(cell -> Vec2.add(cell, offsetCell),
                                          raw#collisionCells);

        {
            tiles          = shiftedTiles,
            collisionCells = shiftedCollisions,
            doors          = raw#doors,        // 平行移動は openDoors 解決の責務外
            tileSet        = raw#tileSet,
            gridSize       = raw#gridSize,
            tileSize       = tileSize
        }

    /// マージ後の grid 寸法（モジュール群の bounding box の右下端）。
    /// モジュール i の右下端 = offsetGrid_i + gridSize_i。これらの max を取る。
    def boundingBoxGridSize(modules: List[ModuleSpec],
                              placed: List[LDTKLoader.LDTKLevelRaw]): Vec2.Vec2i =
        List.zip(modules, placed)
            |> List.foldLeft(acc -> entry -> {
                let (spec, raw) = entry;
                let rightBottom: Vec2.Vec2i = Vec2.addI(spec#offsetGrid, raw#gridSize);
                {x = Int32.max(acc#x, rightBottom#x),
                 y = Int32.max(acc#y, rightBottom#y)}
            }, Vec2.zeroI())

    // ────────────────────────────────────────────────────────
    // 等値比較 / dedup ヘルパー
    // ────────────────────────────────────────────────────────

    /// Vec2 同士の値同値（Float64 == 比較）。
    /// オフセットは整数 * tileSize なので浮動小数点誤差は出ない前提。
    def vec2Eq(a: Vec2.Vec2, b: Vec2.Vec2): Bool =
        a#x == b#x and a#y == b#y

    /// Vec2 リストから重複セルを除去する（Overlap 配置の同位置壁を 1 つにまとめる）。
    def dedupVec2(cells: List[Vec2.Vec2]): List[Vec2.Vec2] =
        List.foldLeft(acc -> cell -> {
            if (List.exists(c -> vec2Eq(c, cell), acc)) acc
            else cell :: acc
        }, Nil, cells)
            |> List.reverse

    /// TileData リストから「同 px・同 src・同 flip」の重複を除去する。
    /// 重複 TileData が GPU インスタンスとして 2 回描かれるのを防ぐ。
    def dedupTiles(tiles: List[TileData]): List[TileData] =
        List.foldLeft(acc -> tile -> {
            if (List.exists(t -> tileDataEq(t, tile), acc)) acc
            else tile :: acc
        }, Nil, tiles)
            |> List.reverse

    /// TileData の見た目が同じかどうか（alpha は描画微差なので比較対象外）。
    def tileDataEq(a: TileData, b: TileData): Bool =
        vec2Eq(a#px, b#px) and
        a#srcX == b#srcX and a#srcY == b#srcY and
        a#flipH == b#flipH and a#flipV == b#flipV
}
