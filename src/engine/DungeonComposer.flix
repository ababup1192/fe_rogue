/// 複数の LDTK モジュール（部屋・通路）を 1 枚の TileMapLayer にマージする。
///
/// 設計方針: 「配置決定」と「合成」を分離する。
///   - 配置（どの ldtkPath を どの offsetGrid に置くか）は呼び出し側が決める。
///   - どの Door セルを開ける（壁→床）かも呼び出し側がワールド座標で指定する。
///   - 本モジュールは与えられた仕様を素直にマージするだけで、ランダム性や
///     方向判定のような決定ロジックは持たない。これにより将来 DungeonPlanner が
///     上に乗っかってランダムダンジョンを作る際にも、API は変えずに済む。
///
/// **3 段の API**
///   - 低レベル: `compose(textureName, modules, openDoors)` — 各モジュールの
///     offsetGrid と openDoors を呼び出し側が手で計算して渡す。
///   - 中レベル: `composeFromConnections(textureName, modulePaths, connections)` —
///     「Door A と Door B を重ねる」という連結グラフ（Door は grid 座標で指定）から
///     offsetGrid / openDoors を自動導出して内部で `compose` を呼ぶ。
///   - 高レベル: `composeFromSideConnections(textureName, modulePaths, sideConnections)` —
///     Door を `DoorSide` 列挙（Left/Right/Top/Bottom）で指定する。Composer が各モジュールの
///     `doors` 一覧から min-x/max-x/min-y/max-y で該当 Door の grid 座標を解決して
///     `composeFromConnections` に橋渡しする。MapScene などはこちらを使うのが最も簡潔。
///     ⚠️ 1 辺に複数 Door があるケース（幅 2 マスの通路など）は曖昧になるので、
///     その場合は中レベルの `composeFromConnections` を使うか拡張する。
///
/// **重要: モジュール順序が重なり優先度を決める**
///   modules の前に来たモジュールが同じ px / セルでの勝者になる。
///   後続モジュールは「既に塞がれていない」位置にだけタイル / 衝突を追加する。
///   部屋を先に渡し、通路を後ろに置くと、Overlap 領域で部屋の壁スプライトが
///   優先され、通路の corridor wall は重ならない位置にだけ追加される。
///
/// マージ手順:
///   1. 各モジュールを LDTKLoader.loadLevelRaw で読み込む（GPU アップロードなし）。
///   2. tiles の px と collisionCells を offsetGrid * tileSize / offsetGrid だけずらす。
///   3. modules の順に走査し、既に登録済みの px / セル位置に対する後続タイル / 衝突を捨てる。
///      モジュール内部の重複（同一 px に flip 違いを 2 枚重ねる演出など）は保持する。
///   4. openDoors（ワールド座標）に該当する collisionCells と TileData を取り除く。
///      これで Door 位置の壁が床になる。openDoors に含まれない Door は壁のまま残る。
///   5. GPU インスタンスを構築し、initTileBuffer を 1 回だけ呼んで TileMapLayer を返す。
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

        // 2. modules の順に「先勝ち」マージする。
        //    - 既に同じ px 位置にタイルを置いたモジュールがあれば、後続のそこにあるタイルは捨てる。
        //    - 既に同じセルに collision がある場合も、後続の collision は捨てる。
        //    モジュール内部の重複（同 px に flip 違いを 2 枚重ねる）は維持する。
        let (mergedTiles, mergedCollisions) =
            List.foldLeft(acc -> raw -> {
                let (accTiles, accCells) = acc;
                let usedPxs: List[Vec2.Vec2] = List.map(t -> t#px, accTiles);
                let newTiles = List.filter(
                    tile -> not List.exists(p -> vec2Eq(p, tile#px), usedPxs),
                    raw#tiles);
                let newCells = List.filter(
                    cell -> not List.exists(c -> vec2Eq(c, cell), accCells),
                    raw#collisionCells);
                (List.append(accTiles, newTiles), List.append(accCells, newCells))
            }, (Nil, Nil), placed);

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

        // 4. 全体の grid サイズ（モジュール bounding box）
        let mergedGridSize = boundingBoxGridSize(modules, placed);

        // 5. GPU インスタンスを 1 回だけアップロード
        let instances = LDTKLoader.buildTileInstances(openedTiles, tileSet, tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);

        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = openedTiles,
            collisionCells = openedCollisions,
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
    // 等値比較ヘルパー
    // ────────────────────────────────────────────────────────

    /// Vec2 同士の値同値（Float64 == 比較）。
    /// オフセットは整数 * tileSize なので浮動小数点誤差は出ない前提。
    def vec2Eq(a: Vec2.Vec2, b: Vec2.Vec2): Bool =
        a#x == b#x and a#y == b#y

    /// Vec2i 同士の値同値（Int32 == 比較）。
    def vec2EqI(a: Vec2.Vec2i, b: Vec2.Vec2i): Bool =
        a#x == b#x and a#y == b#y

    // ════════════════════════════════════════════════════════
    // 高レベル API: Connection グラフから offsetGrid / openDoors を自動導出
    // ════════════════════════════════════════════════════════

    /// あるモジュール内の特定の Door を指す参照。
    /// moduleIndex は composeFromConnections の modulePaths リスト上の 0-base index。
    /// grid はそのモジュールのローカル grid 座標（LDTK の __grid と同じ値）。
    pub type alias DoorRef = {
        moduleIndex = Int32,
        grid        = Vec2.Vec2i
    }

    /// 2 つの Door を「同じワールド座標に重ねる」連結指示。
    /// `a` と `b` のどちらが先に配置済みでもよい（BFS で順序非依存）。
    pub type alias Connection = {
        a = DoorRef,
        b = DoorRef
    }

    /// 連結グラフから offsetGrid と openDoors を自動導出して compose を呼ぶ。
    /// modulePaths[0] をアンカー（offset (0,0)）として固定し、connections を
    /// BFS で辿って各モジュールの offsetGrid を決定する。
    /// modulePaths の順序はそのまま compose に伝わる ＝ 「先勝ち dedup」の優先度。
    /// 部屋を先・通路を後ろに置くと、Overlap 領域で部屋スプライトが残る。
    pub def composeFromConnections(textureName: String,
                                    modulePaths: List[String],
                                    connections: List[Connection]): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        let n = List.length(modulePaths);
        if (n == 0) bug!("DungeonComposer: modulePaths must not be empty")
        else
            // 1. ロードして doors / gridSize を検査用に取得（compose 内でも再ロードする）。
            //    起動時 1 回の読み込みなのでコスト的には無視できる。
            let raws = List.map(path ->
                LDTKLoader.loadLevelRaw(LDTKLoader.simpleConfig({
                    path = path,
                    textureName = textureName
                })),
                modulePaths);
            // 2. 連結整合性の事前検査（早期 bug! で打ち間違いを検出）
            let _ = validateConnections(connections, raws, n);
            // 3. BFS で各モジュールの offsetGrid を算出
            let offsets = bfsOffsets(connections);
            // 4. 孤立モジュール検査（アンカーから到達不能なら bug!）
            let _ = List.forEach(i ->
                match Map.get(i, offsets) {
                    case Some(_) => ()
                    case None    => bug!("DungeonComposer: module ${i} is not connected to anchor (modulePaths[0])")
                },
                List.range(0, n));
            // 5. openDoors を構築（connection ごとに a 側の world 座標を集める）
            let openDoors = List.map(c -> {
                let off = lookupOffset(c#a#moduleIndex, offsets);
                Vec2.addI(off, c#a#grid)
            }, connections);
            // 6. ModuleSpec リストを modulePaths 順に組み立てる（順序＝優先度）
            let modules = buildModuleSpecs(modulePaths, offsets);
            // 7. 既存 compose に委譲
            compose(textureName, modules, openDoors)

    /// offsets から特定モジュールの offset を取り出す。未配置なら bug!。
    def lookupOffset(i: Int32, offsets: Map[Int32, Vec2.Vec2i]): Vec2.Vec2i =
        match Map.get(i, offsets) {
            case Some(o) => o
            case None    => bug!("DungeonComposer: no offset computed for module ${i}")
        }

    /// modulePaths を offsets と組み合わせて ModuleSpec リストにする（modulePaths 順を維持）。
    def buildModuleSpecs(modulePaths: List[String],
                          offsets: Map[Int32, Vec2.Vec2i]): List[ModuleSpec] =
        let (_, reversed) = List.foldLeft(acc -> path -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let spec: ModuleSpec = { ldtkPath = path, offsetGrid = off };
            (i + 1, spec :: list)
        }, (0, Nil), modulePaths);
        List.reverse(reversed)

    /// 全 connection の DoorRef を検査する。bug! しなければ Unit。
    def validateConnections(connections: List[Connection],
                             raws: List[LDTKLoader.LDTKLevelRaw],
                             n: Int32): Unit =
        List.forEach(c -> {
            let _ = validateDoorRef(c#a, raws, n);
            validateDoorRef(c#b, raws, n)
        }, connections)

    /// DoorRef が有効かを検査する: index が範囲内、grid が LDTK の doors リストに存在。
    def validateDoorRef(ref: DoorRef,
                         raws: List[LDTKLoader.LDTKLevelRaw],
                         n: Int32): Unit =
        if (ref#moduleIndex < 0 or ref#moduleIndex >= n)
            bug!("DungeonComposer: moduleIndex ${ref#moduleIndex} out of range [0, ${n})")
        else
            let raw = match List.nth(ref#moduleIndex, raws) {
                case Some(r) => r
                case None    => bug!("DungeonComposer: raws lookup failed for index ${ref#moduleIndex}")
            };
            let exists = List.exists(d -> vec2EqI(d, ref#grid), raw#doors);
            if (not exists)
                bug!("DungeonComposer: door (${ref#grid#x},${ref#grid#y}) not found in module ${ref#moduleIndex}")
            else
                ()

    /// connections を BFS で辿り、modulePaths[0] をアンカー (0,0) として
    /// 各モジュールの offsetGrid を Map[Int32, Vec2.Vec2i] にまとめる。
    /// 既配置モジュールに到達した際に offset が食い違ったら bug!。
    def bfsOffsets(connections: List[Connection]): Map[Int32, Vec2.Vec2i] =
        // 各 connection を双方向に展開: (src, gSrc, dst, gDst)
        let edges: List[(Int32, Vec2.Vec2i, Int32, Vec2.Vec2i)] =
            List.flatMap(c -> {
                (c#a#moduleIndex, c#a#grid, c#b#moduleIndex, c#b#grid) ::
                (c#b#moduleIndex, c#b#grid, c#a#moduleIndex, c#a#grid) ::
                Nil
            }, connections);
        let initialOffsets = Map.empty() |> Map.insert(0, Vec2.zeroI());
        bfsLoop(initialOffsets, 0 :: Nil, edges)

    def bfsLoop(offsets: Map[Int32, Vec2.Vec2i],
                 queue: List[Int32],
                 edges: List[(Int32, Vec2.Vec2i, Int32, Vec2.Vec2i)]): Map[Int32, Vec2.Vec2i] =
        match queue {
            case Nil => offsets
            case i :: rest =>
                let myOffset = lookupOffset(i, offsets);
                let (newOffsets, addedQueue) =
                    List.foldLeft(acc -> edge -> {
                        let (off, placedQueue) = acc;
                        let (src, gSrc, dst, gDst) = edge;
                        if (src != i) acc
                        else
                            // world(i.gSrc) = world(dst.gDst) を満たすには:
                            //   offsets[i] + gSrc = offsets[dst] + gDst
                            //   ∴ offsets[dst] = offsets[i] + gSrc - gDst
                            let expected = Vec2.subI(Vec2.addI(myOffset, gSrc), gDst);
                            match Map.get(dst, off) {
                                case None =>
                                    (Map.insert(dst, expected, off), dst :: placedQueue)
                                case Some(existing) =>
                                    if (vec2EqI(existing, expected)) acc
                                    else bug!("DungeonComposer: inconsistent offset for module ${dst}: expected (${expected#x},${expected#y}) but already placed at (${existing#x},${existing#y})")
                            }
                    }, (offsets, Nil), edges);
                bfsLoop(newOffsets, List.append(rest, addedQueue), edges)
        }

    // ════════════════════════════════════════════════════════
    // 高レベル API: Door を Side 列挙で指定する
    // ════════════════════════════════════════════════════════

    /// モジュールの 4 辺を表す列挙。
    /// Composer が `doors` 一覧の min-x / max-x / min-y / max-y からそれぞれ
    /// Left / Right / Top / Bottom の Door を解決する。
    pub enum DoorSide with Eq {
        case Left
        case Right
        case Top
        case Bottom
    }

    /// Side 指定で Door を参照する。grid 座標は `composeFromSideConnections` が
    /// 内部で解決する。
    pub type alias SideRef = {
        moduleIndex = Int32,
        side        = DoorSide
    }

    /// 2 つの SideRef の Door を「同じワールド座標に重ねる」連結指示。
    pub type alias SideConnection = {
        a = SideRef,
        b = SideRef
    }

    /// Side ベースで連結を指定する高レベル API。
    /// 各 SideRef を `(moduleIndex, grid)` の DoorRef に解決してから
    /// `composeFromConnections` に委譲する。
    /// 1 辺に Door が複数ある場合は最初に見つかったものを採用する仕様
    /// （現在の LDTK 構成では 1 辺 1 Door なので一意になる）。
    pub def composeFromSideConnections(textureName: String,
                                        modulePaths: List[String],
                                        sideConnections: List[SideConnection]): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        let n = List.length(modulePaths);
        if (n == 0) bug!("DungeonComposer: modulePaths must not be empty")
        else
            let raws = List.map(path ->
                LDTKLoader.loadLevelRaw(LDTKLoader.simpleConfig({
                    path = path,
                    textureName = textureName
                })),
                modulePaths);
            let connections = List.map(sc ->
                ({
                    a = resolveSideRef(sc#a, raws, n),
                    b = resolveSideRef(sc#b, raws, n)
                }: Connection),
                sideConnections);
            composeFromConnections(textureName, modulePaths, connections)

    /// SideRef を DoorRef に解決する。範囲外 / Doors 空ならば bug!。
    def resolveSideRef(ref: SideRef,
                        raws: List[LDTKLoader.LDTKLevelRaw],
                        n: Int32): DoorRef =
        if (ref#moduleIndex < 0 or ref#moduleIndex >= n)
            bug!("DungeonComposer: moduleIndex ${ref#moduleIndex} out of range [0, ${n})")
        else
            let raw = match List.nth(ref#moduleIndex, raws) {
                case Some(r) => r
                case None    => bug!("DungeonComposer: raws lookup failed for index ${ref#moduleIndex}")
            };
            let grid = pickDoorBySide(ref#side, raw#doors, ref#moduleIndex);
            { moduleIndex = ref#moduleIndex, grid = grid }

    /// Side に応じて min/max 比較で 1 つの Door grid 座標を選ぶ。
    /// Left / Right は x 軸、Top / Bottom は y 軸で min / max を取る。
    /// 同点（タイ）は出現順で先頭が勝つ（List.foldLeft の比較が strict less / greater のため）。
    def pickDoorBySide(side: DoorSide,
                        doors: List[Vec2.Vec2i],
                        moduleIndex: Int32): Vec2.Vec2i =
        match doors {
            case Nil => bug!("DungeonComposer: module ${moduleIndex} has no Doors")
            case head :: rest =>
                let pick = match side {
                    case DoorSide.Left   => (a, b) -> if (b#x < a#x) b else a
                    case DoorSide.Right  => (a, b) -> if (b#x > a#x) b else a
                    case DoorSide.Top    => (a, b) -> if (b#y < a#y) b else a
                    case DoorSide.Bottom => (a, b) -> if (b#y > a#y) b else a
                };
                List.foldLeft(acc -> d -> pick(acc, d), head, rest)
        }
}
