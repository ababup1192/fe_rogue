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

        // 2. modules の順に collisionCells を「先勝ち」でマージする
        //    （同じセルに既に collision があれば後続を捨てる）。
        //    タイルは auto-tile で完全再生成するためここではマージ不要。
        let mergedCollisions =
            List.foldLeft(acc -> raw -> {
                let newCells = List.filter(
                    cell -> not List.exists(c -> vec2Eq(c, cell), acc),
                    raw#collisionCells);
                List.append(acc, newCells)
            }, Nil, placed);

        // 3. openDoors（ワールド座標）に該当する壁を取り除く
        let doorCellsF: List[Vec2.Vec2] = List.map(c -> Vec2.fromI(c), openDoors);
        let openedCollisions =
            List.filter(cell -> not (doorCellsF |> List.exists(d -> vec2Eq(d, cell))),
                        mergedCollisions);

        // 4. 全体の grid サイズ（モジュール bounding box）
        let mergedGridSize = boundingBoxGridSize(modules, placed);

        // 5. void-fill: どのモジュールの content にもカバーされていない in-bounds セルを
        //    強制的に collision に追加する（描画タイルは無し ＝ 真っ黒）。
        //    pathway の bbox 内空セルや、隣接するモジュール間の隙間を player から不可侵にする。
        let coveredRects = contentRectsOf(placed);
        let voidWalls = collectVoidCells(mergedGridSize, coveredRects);
        let withVoid = List.append(openedCollisions, voidWalls);

        // 6. auto-tile: マージ後の merged intGrid に LDTK の auto-rule を再適用して
        //    タイルを再生成する。各モジュールが独立に焼いた壁スプライトを破棄し、
        //    境界の neighborhood に応じた一貫したタイル並びにする。
        //    intGrid 上は void セルも壁(=1)扱い（OOB 値と同じ）として周縁の判定を正しく
        //    保つが、出力タイルは「いずれかのモジュールが content として持つ cell」だけに
        //    限定する（void 領域に巨大な wall-fill ブロックが出来るのを防ぐ）。
        let ruleSet = LDTKRules.loadRules("title_map/FE.ldtk");
        let intGrid = buildIntGridFn(withVoid);
        let tex = textureSize(tileSet);
        let allAutoTiles = LDTKRules.applyRules(ruleSet, intGrid, mergedGridSize, tex);
        // content rect を 1 cell 外側に拡張した範囲を「描画対象」とする。
        // これでモジュール周縁の void wall（外周フレーム）が描画される一方、
        // 2 cell 以上離れた deep void は黒のまま残る。
        let paddedRects = List.map(expandRect, coveredRects);
        let autoTiles = List.filter(tile -> {
            let cellX = Float64.tryToInt32(tile#px#x / tileSize) |> Option.getWithDefault(0i32);
            let cellY = Float64.tryToInt32(tile#px#y / tileSize) |> Option.getWithDefault(0i32);
            anyContains(paddedRects, ({x = cellX, y = cellY}: Vec2.Vec2i))
        }, allAutoTiles);

        // 7. GPU インスタンスを 1 回だけアップロード
        let instances = LDTKLoader.buildTileInstances(autoTiles, tileSet, tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);

        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = autoTiles,
            collisionCells = withVoid,
            gridSize       = mergedGridSize
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount)

    /// merged collisionCells から `(x, y) -> 1 if wall else 0` の関数を作る。
    /// この関数は範囲外を呼び出されないことを前提（範囲外処理は LDTKRules が行う）。
    def buildIntGridFn(collisions: List[Vec2.Vec2]): (Int32, Int32) -> Int32 =
        (x, y) -> {
            let cx = Int32.toFloat64(x);
            let cy = Int32.toFloat64(y);
            if (List.exists(c -> c#x == cx and c#y == cy, collisions)) 1i32
            else 0i32
        }

    /// TileSet から atlas のピクセル寸法を取り出す。
    def textureSize(tileSet: TileSet): { width = Float64, height = Float64 } =
        { width  = tileSet#atlasSource#texWidth,
          height = tileSet#atlasSource#texHeight }

    /// 各モジュールの「content bbox」（= 衝突セルのワールド座標 bbox）一覧を返す。
    /// 衝突セルが空なモジュールは bbox が空なので除外（影響しない）。
    /// 戻り値の rect は (minInclusive, maxExclusive) のペア。
    def contentRectsOf(placed: List[LDTKLoader.LDTKLevelRaw]): List[(Vec2.Vec2i, Vec2.Vec2i)] =
        List.filterMap(raw -> {
            match raw#collisionCells {
                case Nil => None
                case head :: rest =>
                    let initMin: Vec2.Vec2i = vec2ToI(head);
                    let initMax: Vec2.Vec2i = ({x = initMin#x + 1, y = initMin#y + 1}: Vec2.Vec2i);
                    let (mn, mx) = List.foldLeft(acc -> cell -> {
                        let (curMin, curMax) = acc;
                        let ci = vec2ToI(cell);
                        let newMin: Vec2.Vec2i =
                            {x = Int32.min(curMin#x, ci#x),
                             y = Int32.min(curMin#y, ci#y)};
                        let newMax: Vec2.Vec2i =
                            {x = Int32.max(curMax#x, ci#x + 1),
                             y = Int32.max(curMax#y, ci#y + 1)};
                        (newMin, newMax)
                    }, (initMin, initMax), rest);
                    Some((mn, mx))
            }
        }, placed)

    /// gridSize 内の全セルを走査し、どの coveredRect にも入っていないものを返す。
    def collectVoidCells(gridSize: Vec2.Vec2i,
                          coveredRects: List[(Vec2.Vec2i, Vec2.Vec2i)]): List[Vec2.Vec2] =
        let xs = List.range(0, gridSize#x);
        let ys = List.range(0, gridSize#y);
        List.flatMap(y ->
            List.filterMap(x -> {
                let ci: Vec2.Vec2i = {x = x, y = y};
                if (anyContains(coveredRects, ci)) None
                else Some(({x = Int32.toFloat64(x), y = Int32.toFloat64(y)}: Vec2.Vec2))
            }, xs),
            ys)

    /// 指定セルがいずれかの rect (minInclusive..maxExclusive) に含まれるか。
    def anyContains(rects: List[(Vec2.Vec2i, Vec2.Vec2i)], cell: Vec2.Vec2i): Bool =
        List.exists(r -> {
            let (mn, mx) = r;
            cell#x >= mn#x and cell#x < mx#x and
            cell#y >= mn#y and cell#y < mx#y
        }, rects)

    /// rect を上下左右に 1 cell 拡張する。
    /// auto-tile 描画対象の判定で「content の外周 1 cell 分」を含めるために使う。
    def expandRect(r: (Vec2.Vec2i, Vec2.Vec2i)): (Vec2.Vec2i, Vec2.Vec2i) =
        let (mn, mx) = r;
        (({x = mn#x - 1, y = mn#y - 1}: Vec2.Vec2i),
         ({x = mx#x + 1, y = mx#y + 1}: Vec2.Vec2i))

    /// Vec2 (Float64) → Vec2i (Int32) 変換（座標は整数 cell として保存されている前提）。
    def vec2ToI(v: Vec2.Vec2): Vec2.Vec2i =
        {x = Float64.tryToInt32(v#x) |> Option.getWithDefault(0i32),
         y = Float64.tryToInt32(v#y) |> Option.getWithDefault(0i32)}

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

    /// 配置済み 1 モジュールのワールド bbox。
    /// `idx` は `modulePaths` 上の 0-base index（先勝ち優先度と一致）。
    /// `offset` は正規化後の offsetGrid。`gridSize` は LDTK の元寸法。
    /// 「セル → モジュール index」逆引きや、敵スポーン候補セルの列挙に使う。
    pub type alias ModulePlacement = {
        idx      = Int32,
        offset   = Vec2.Vec2i,
        gridSize = Vec2.Vec2i
    }

    /// 高レベル API の戻り値。
    /// - `anchorOffset` は modulePaths[0] の正規化後 offsetGrid。
    /// - `spawnGrid` は anchor 内で「壁でない」と保証されたセルのワールド座標。
    ///   anchor 部屋の中心に最も近い床セルを採用する。
    ///   PlayerScene 等のスポーン位置に使うことで、(5,5) が壁の LDTK でも安全。
    /// - `moduleSpecs` は配置決定後の (path, offsetGrid) リスト。
    ///   別レイヤー（Floor 等）を同じ配置で重ねて描画する際に使う。
    /// - `placements` は配置済み全モジュールのワールド bbox（offset + gridSize）。
    ///   moduleSpecs と同じ idx 順で並ぶ。
    pub type alias ComposeResult = {
        layer        = TileMapLayer,
        anchorOffset = Vec2.Vec2i,
        spawnGrid    = Vec2.Vec2i,
        moduleSpecs  = List[ModuleSpec],
        placements   = List[ModulePlacement]
    }

    /// 連結グラフから offsetGrid と openDoors を自動導出して compose を呼ぶ。
    /// modulePaths[0] をアンカー（offset (0,0)）として固定し、connections を
    /// BFS で辿って各モジュールの offsetGrid を決定する。
    /// その後、すべての offset の最小値が (0,0) になるよう正規化する
    /// （Top / Left 方向の連結で発生する負 offset を非負領域に収める）。
    /// modulePaths の順序はそのまま compose に伝わる ＝ 「先勝ち dedup」の優先度。
    /// 部屋を先・通路を後ろに置くと、Overlap 領域で部屋スプライトが残る。
    pub def composeFromConnections(textureName: String,
                                    modulePaths: List[String],
                                    connections: List[Connection]): ComposeResult
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
            // 3. BFS で各モジュールの offsetGrid を算出（anchor (0,0) 基準）
            let rawOffsets = bfsOffsets(connections);
            // 4. 孤立モジュール検査（アンカーから到達不能なら bug!）
            let _ = List.forEach(i ->
                match Map.get(i, rawOffsets) {
                    case Some(_) => ()
                    case None    => bug!("DungeonComposer: module ${i} is not connected to anchor (modulePaths[0])")
                },
                List.range(0, n));
            // 5. 正規化: 全 offsets の min を (0,0) に揃えるよう一律シフト
            let minOff   = computeMinOffset(rawOffsets);
            let shift    = Vec2.subI(Vec2.zeroI(), minOff);
            let offsets  = shiftOffsets(rawOffsets, shift);
            let anchorOffset = lookupOffset(0, offsets);
            // 6. anchor 内の床セル（壁でないセル）でセンターに最近のものを spawnGrid とする
            let anchorRaw = match List.head(raws) {
                case Some(r) => r
                case None    => bug!("DungeonComposer: raws is empty")
            };
            let spawnGrid = findSpawnInAnchor(anchorRaw, anchorOffset);
            // 7. openDoors を構築（正規化後 offsets で）
            let openDoors = List.map(c -> {
                let off = lookupOffset(c#a#moduleIndex, offsets);
                Vec2.addI(off, c#a#grid)
            }, connections);
            // 8. ModuleSpec リストを modulePaths 順に組み立てる
            let modules = buildModuleSpecs(modulePaths, offsets);
            // 8'. ModulePlacement リスト（offset + gridSize）を idx 順に組み立てる
            let placements = buildPlacements(raws, offsets);
            // 9. 既存 compose に委譲
            let layer = compose(textureName, modules, openDoors);
            { layer = layer, anchorOffset = anchorOffset, spawnGrid = spawnGrid,
              moduleSpecs = modules, placements = placements }

    /// anchor のローカル collisionCells を見て「壁でない」セルのうち
    /// グリッド中心に最も近いものを返す。戻り値はワールド座標（anchorOffset 加算済み）。
    /// 床セルが 1 つも無ければ bug!（部屋なら通常あり得ない）。
    def findSpawnInAnchor(anchorRaw: LDTKLoader.LDTKLevelRaw,
                           anchorOffset: Vec2.Vec2i): Vec2.Vec2i =
        let gridSize = anchorRaw#gridSize;
        let cx = gridSize#x / 2;
        let cy = gridSize#y / 2;
        let center: Vec2.Vec2i = {x = cx, y = cy};
        let walls = anchorRaw#collisionCells;
        // 「local cell が壁か」: collisionCells は Float64 だが整数値を保持しているので == で比較
        let isLocalWall = c -> List.exists(w ->
            Float64.tryToInt32(w#x) == Some(c#x) and
            Float64.tryToInt32(w#y) == Some(c#y), walls);
        // 全セルを列挙（行優先）
        let allCells: List[Vec2.Vec2i] =
            List.range(0, gridSize#y) |> List.flatMap(y ->
                List.range(0, gridSize#x) |> List.map(x -> ({x = x, y = y}: Vec2.Vec2i)));
        // 壁でないセルだけ残し、中心に最近のものを選ぶ
        let nonWalls = List.filter(c -> not isLocalWall(c), allCells);
        match nonWalls {
            case Nil => bug!("DungeonComposer: anchor has no floor cell")
            case head :: rest =>
                let distSq = c -> {
                    let d = Vec2.subI(c, center);
                    d#x * d#x + d#y * d#y
                };
                let best = List.foldLeft(acc -> c ->
                    if (distSq(c) < distSq(acc)) c else acc, head, rest);
                Vec2.addI(anchorOffset, best)
        }

    /// offsets の値の min(x, y) を求める。各次元の最小は別々のモジュールから来ても良い。
    def computeMinOffset(offsets: Map[Int32, Vec2.Vec2i]): Vec2.Vec2i =
        Map.foldLeft(acc -> off -> {
            {x = Int32.min(acc#x, off#x), y = Int32.min(acc#y, off#y)}
        }, ({x = 0i32, y = 0i32}: Vec2.Vec2i), offsets)

    /// 全 offsets に shift を加える（要素を Vec2.addI(shift, off) に置換）。
    def shiftOffsets(offsets: Map[Int32, Vec2.Vec2i], shift: Vec2.Vec2i): Map[Int32, Vec2.Vec2i] =
        Map.map(off -> Vec2.addI(shift, off), offsets)

    /// offsets から特定モジュールの offset を取り出す。未配置なら bug!。
    def lookupOffset(i: Int32, offsets: Map[Int32, Vec2.Vec2i]): Vec2.Vec2i =
        match Map.get(i, offsets) {
            case Some(o) => o
            case None    => bug!("DungeonComposer: no offset computed for module ${i}")
        }

    /// raws と offsets を組み合わせて ModulePlacement リストにする（idx 順）。
    /// raws は modulePaths と同じ並びで loadLevelRaw 済み前提。
    def buildPlacements(raws: List[LDTKLoader.LDTKLevelRaw],
                         offsets: Map[Int32, Vec2.Vec2i]): List[ModulePlacement] =
        let (_, reversed) = List.foldLeft(acc -> raw -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let p: ModulePlacement = { idx = i, offset = off, gridSize = raw#gridSize };
            (i + 1, p :: list)
        }, (0, Nil), raws);
        List.reverse(reversed)

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

    /// 反対側の辺を返す（Right ↔ Left, Top ↔ Bottom）。通路の両端の連結に使う。
    pub def oppositeSide(side: DoorSide): DoorSide = match side {
        case DoorSide.Left   => DoorSide.Right
        case DoorSide.Right  => DoorSide.Left
        case DoorSide.Top    => DoorSide.Bottom
        case DoorSide.Bottom => DoorSide.Top
    }

    /// 左右辺かどうか。横通路（Pathway_1）と縦通路（Pathway_2）の選択に使う。
    pub def isHorizontalSide(side: DoorSide): Bool = match side {
        case DoorSide.Left  => true
        case DoorSide.Right => true
        case _              => false
    }

    /// 4 辺の全列挙。生成器が「空き辺」を走査するときに使う。
    pub def allSides(): List[DoorSide] =
        DoorSide.Left :: DoorSide.Right :: DoorSide.Top :: DoorSide.Bottom :: Nil

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
                                        sideConnections: List[SideConnection]): ComposeResult
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

    /// Generator 等の外部利用向けに公開した版。Doors 空なら None。
    pub def doorBySide(side: DoorSide, doors: List[Vec2.Vec2i]): Option[Vec2.Vec2i] =
        match doors {
            case Nil => None
            case head :: rest =>
                let pick = match side {
                    case DoorSide.Left   => (a, b) -> if (b#x < a#x) b else a
                    case DoorSide.Right  => (a, b) -> if (b#x > a#x) b else a
                    case DoorSide.Top    => (a, b) -> if (b#y < a#y) b else a
                    case DoorSide.Bottom => (a, b) -> if (b#y > a#y) b else a
                };
                Some(List.foldLeft(acc -> d -> pick(acc, d), head, rest))
        }

    // ════════════════════════════════════════════════════════
    // 装飾レイヤー（Floor 等）の合成
    // ════════════════════════════════════════════════════════

    /// 装飾レイヤー（Floor など）を Walls と同じ ModuleSpec 配置で 1 枚にマージする。
    /// auto-rule の再適用や collision 抽出は行わない（autoLayerTiles を offset して連結するだけ）。
    /// `layerIdentifier` には LDTK 上のレイヤー名（例: "Floor"）を渡す。
    /// 同一 px に複数モジュールのタイルが重なった場合は「先勝ち」で先頭モジュールを残す。
    pub def composeDecorationLayer(textureName: String,
                                    moduleSpecs: List[ModuleSpec],
                                    layerIdentifier: String): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        match moduleSpecs {
            case Nil => bug!("DungeonComposer: composeDecorationLayer received empty moduleSpecs")
            case _   =>
                let placed = List.map(spec ->
                    loadAndOffsetLayer(textureName, spec, layerIdentifier),
                    moduleSpecs);
                let firstRaw = match List.head(placed) {
                    case Some(r) => r
                    case None    => bug!("DungeonComposer: placed is empty")
                };
                let tileSet  = firstRaw#tileSet;
                let tileSize = firstRaw#tileSize;
                // 「先勝ち」で px が衝突するタイルは捨てる
                let mergedTiles =
                    List.foldLeft(acc -> raw -> {
                        let newTiles = List.filter(
                            t -> not List.exists(a -> vec2Eq(a#px, t#px), acc),
                            raw#tiles);
                        List.append(acc, newTiles)
                    }, Nil, placed);
                let mergedGridSize = boundingBoxGridSizeFromLayers(moduleSpecs, placed);
                let instances = LDTKLoader.buildTileInstances(mergedTiles, tileSet, tileSize);
                let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
                TileMapLayer.make({
                    tileSet        = tileSet,
                    tiles          = mergedTiles,
                    collisionCells = Nil,           // 装飾レイヤーは衝突を持たない
                    gridSize       = mergedGridSize
                }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount)
        }

    /// 1 モジュールの装飾レイヤーをロードし、offsetGrid 分だけタイルを平行移動する。
    def loadAndOffsetLayer(textureName: String, spec: ModuleSpec,
                            layerIdentifier: String): LDTKLoader.LDTKLayerRaw
            \ { GameEngine.Game, Fs.FileRead } =
        let raw = LDTKLoader.loadLayerByIdentifier(LDTKLoader.simpleConfig({
            path        = spec#ldtkPath,
            textureName = textureName
        }), layerIdentifier);
        let offsetPx = Vec2.mul(Vec2.fromI(spec#offsetGrid), raw#tileSize);
        let shiftedTiles = List.map(tile -> {
            { px = Vec2.add(tile#px, offsetPx) | tile }
        }, raw#tiles);
        { tiles    = shiftedTiles,
          tileSet  = raw#tileSet,
          gridSize = raw#gridSize,
          tileSize = raw#tileSize }

    /// LDTKLayerRaw 版の bounding box 計算（Walls 用と同じロジック）。
    def boundingBoxGridSizeFromLayers(modules: List[ModuleSpec],
                                       placed: List[LDTKLoader.LDTKLayerRaw]): Vec2.Vec2i =
        List.zip(modules, placed)
            |> List.foldLeft(acc -> entry -> {
                let (spec, raw) = entry;
                let rightBottom: Vec2.Vec2i = Vec2.addI(spec#offsetGrid, raw#gridSize);
                {x = Int32.max(acc#x, rightBottom#x),
                 y = Int32.max(acc#y, rightBottom#y)}
            }, Vec2.zeroI())
}
