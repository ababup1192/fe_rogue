/// 部屋プールと通路ファイルからランダムに連結ダンジョンを生成する。
///
/// 出力は `composeFromSideConnections` の入力（modulePaths + sideConnections）。
/// Composer 自体には触れず「グラフを作る」レイヤーとして独立する。
///
/// アルゴリズム（一様ランダム anchor / 部屋数減らして続行）:
///   1. 最初の部屋（プールからランダム選択）を index 0・offset (0,0) で配置。
///   2. roomCount - 1 回の追加ループ:
///      a. 既配置の部屋のうち、空き辺が 1 つ以上ある候補を抽出。
///      b. 候補から一様ランダムに anchor を選ぶ（一方向への片寄りを抑える）。
///      c. anchor の空き辺からランダムに 1 つ選ぶ。
///      d. 横辺なら横通路、縦辺なら縦通路を選び、新部屋もプールからランダム選択。
///      e. 通路と新部屋の offset を BFS と同じロジックで算出。
///      f. 新部屋の bbox が既配置の部屋と衝突しなければ commit。
///         衝突したら別の (anchor, side) で再試行（最大 N 回）。全部失敗したら早期終了。
///   3. 配置済みモジュールを「部屋優先」順序に並び替えた modulePaths と、
///      対応する sideConnections を Plan として返す。
mod DungeonGenerator {
    use DungeonComposer.{DoorSide, SideConnection, SideRef}

    /// 利用可能な部屋プール / 通路 / 目標部屋数の設定。
    pub type alias Config = {
        roomPaths       = List[String],   // 部屋 LDTK プール（複数可）
        horizontalPaths = List[String],   // 横通路 LDTK プール（複数可、空不可）
        verticalPaths   = List[String],   // 縦通路 LDTK プール（複数可、空不可）
        roomCount       = Int32           // 目標部屋数（>= 1）
    }

    /// composeFromSideConnections に渡す入力一式。
    /// `modulePaths` は「部屋を先・通路を後ろ」で並ぶため、
    /// `roomCount` で部屋と通路の境界を呼び出し側が判別できる。
    pub type alias Plan = {
        modulePaths     = List[String],
        sideConnections = List[SideConnection],
        roomCount       = Int32
    }

    /// LDTK ファイルから取り出した寸法と Door 一覧（生成中に何度も参照する）。
    type alias Meta = {
        gridSize = Vec2.Vec2i,
        doors    = List[Vec2.Vec2i]
    }

    /// 配置済み 1 モジュール。usedSides はそのモジュールで既に連結に使った辺。
    type alias Entry = {
        ldtkPath  = String,
        offset    = Vec2.Vec2i,
        gridSize  = Vec2.Vec2i,
        doors     = List[Vec2.Vec2i],
        isRoom    = Bool,
        usedSides = List[DoorSide]
    }

    /// 連結指示を「最終 modulePaths への index 解決前の生成中表現」で保持する。
    /// fromIdx / toIdx は `entries: Map[Int32, Entry]` のキー。
    type alias PendingConn = {
        fromIdx  = Int32,
        fromSide = DoorSide,
        toIdx    = Int32,
        toSide   = DoorSide
    }

    type alias State = {
        entries = Map[Int32, Entry],
        next    = Int32,
        conns   = List[PendingConn]
    }

    /// 1 回の (anchor, side) 試行で衝突したときの最大リトライ回数。
    def maxAttemptsPerRoom(): Int32 = 16

    // ════════════════════════════════════════════════════════
    // 公開 API
    // ════════════════════════════════════════════════════════

    /// ランダムにダンジョンを生成し、composeFromSideConnections に渡せる Plan を返す。
    pub def generate(textureName: String, config: Config): Plan
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        if (config#roomCount < 1) bug!("DungeonGenerator: roomCount must be >= 1")
        else
            // 1. 全 LDTK ファイルのメタデータを一度だけ読み込む（重複ロード回避）
            let allPaths = List.append(config#horizontalPaths,
                            List.append(config#verticalPaths, config#roomPaths));
            let metaMap = loadAllMetadata(textureName, allPaths);
            // 2. 最初の部屋を配置（offset (0,0), index 0）
            let firstPath = pickOrBug(config#roomPaths, "roomPaths must not be empty");
            let firstMeta = metaOf(firstPath, metaMap);
            let firstEntry: Entry = {
                ldtkPath  = firstPath,
                offset    = Vec2.zeroI(),
                gridSize  = firstMeta#gridSize,
                doors     = firstMeta#doors,
                isRoom    = true,
                usedSides = Nil
            };
            let initial: State = {
                entries = Map.empty() |> Map.insert(0, firstEntry),
                next    = 1,
                conns   = Nil
            };
            // 3. roomCount-1 回ループ
            let finalState = addRoomsLoop(initial, config#roomCount - 1, config, metaMap);
            // 4. 部屋数の実績をログ出力
            let placedRoomCount = countRooms(finalState);
            println("DungeonGenerator: placed ${placedRoomCount} rooms (target ${config#roomCount})");
            // 5. Plan に整形（部屋優先・index 再採番）
            buildPlan(finalState)

    // ════════════════════════════════════════════════════════
    // メタデータロード
    // ════════════════════════════════════════════════════════

    /// 重複を除いてからファイルを読み、path → Meta の Map を作る。
    def loadAllMetadata(textureName: String, paths: List[String]): Map[String, Meta]
            \ {GameEngine.Game, Fs.FileRead} =
        let unique = dedupStrings(paths);
        List.foldLeft(acc -> path -> {
            let raw = LDTKLoader.loadLevelRaw(LDTKLoader.simpleConfig({
                path = path,
                textureName = textureName
            }));
            let meta: Meta = { gridSize = raw#gridSize, doors = raw#doors };
            Map.insert(path, meta, acc)
        }, Map.empty(), unique)

    def dedupStrings(list: List[String]): List[String] =
        List.foldLeft(acc -> s -> {
            if (List.exists(x -> x == s, acc)) acc else s :: acc
        }, Nil, list) |> List.reverse

    def metaOf(path: String, map: Map[String, Meta]): Meta =
        match Map.get(path, map) {
            case Some(m) => m
            case None    => bug!("DungeonGenerator: no metadata for ${path}")
        }

    // ════════════════════════════════════════════════════════
    // 配置ループ
    // ════════════════════════════════════════════════════════

    /// 残り部屋数だけ追加を試みる。1 回でも失敗（候補ゼロ or 全リトライ失敗）したら打ち切り。
    def addRoomsLoop(state: State, remaining: Int32,
                      config: Config, metaMap: Map[String, Meta]): State \ Math.Random =
        if (remaining <= 0) state
        else
            match tryAddOne(state, config, metaMap) {
                case Some(newState) => addRoomsLoop(newState, remaining - 1, config, metaMap)
                case None           => state    // 早期終了
            }

    /// 1 部屋追加を試みる。anchor 候補を一様ランダムに選び、空き辺・通路・新部屋もランダム選択。
    /// 衝突したら試行を最大 maxAttemptsPerRoom 回繰り返す。
    def tryAddOne(state: State, config: Config, metaMap: Map[String, Meta]):
                  Option[State] \ Math.Random =
        let anchorIdxs = findAnchorCandidates(state);
        if (List.isEmpty(anchorIdxs)) None
        else
            tryAttempts(maxAttemptsPerRoom(), state, config, metaMap, anchorIdxs)

    def tryAttempts(remaining: Int32, state: State, config: Config,
                     metaMap: Map[String, Meta], anchorIdxs: List[Int32]):
                    Option[State] \ Math.Random =
        if (remaining <= 0) None
        else
            match tryOneAttempt(state, config, metaMap, anchorIdxs) {
                case Some(newState) => Some(newState)
                case None           => tryAttempts(remaining - 1, state, config, metaMap, anchorIdxs)
            }

    /// 1 試行: anchor / side / 新部屋・通路を選んで配置を試す。衝突したら None。
    def tryOneAttempt(state: State, config: Config,
                       metaMap: Map[String, Meta],
                       anchorIdxs: List[Int32]): Option[State] \ Math.Random =
        match RandomUtil.pick(anchorIdxs) {
            case None => None
            case Some(anchorIdx) =>
                let anchor = entryOf(anchorIdx, state);
                let freeSides = freeSidesOf(anchor);
                match RandomUtil.pick(freeSides) {
                    case None => None
                    case Some(anchorSide) =>
                        match RandomUtil.pick(config#roomPaths) {
                            case None => None
                            case Some(newRoomPath) =>
                                let pool = if (DungeonComposer.isHorizontalSide(anchorSide))
                                               config#horizontalPaths
                                           else
                                               config#verticalPaths;
                                match RandomUtil.pick(pool) {
                                    case None => None
                                    case Some(pathwayPath) =>
                                        tryPlacement(anchorIdx, anchorSide, newRoomPath,
                                                      pathwayPath, state, config, metaMap)
                                }
                        }
                }
        }

    /// 選択された (anchor, side, 新部屋) の組で実際に offset を計算し配置を確定する。
    /// 通路選択は side が横辺かどうかで決まる。プールから一様ランダムに 1 本選ぶ。
    def tryPlacement(anchorIdx: Int32, anchorSide: DoorSide, newRoomPath: String,
                      pathwayPath: String,
                      state: State, _config: Config,
                      metaMap: Map[String, Meta]): Option[State] =
        let anchor = entryOf(anchorIdx, state);
        let anchorDoor = match DungeonComposer.doorBySide(anchorSide, anchor#doors) {
            case Some(d) => d
            case None    => bug!("DungeonGenerator: anchor has no door on ${sideName(anchorSide)}")
        };
        let pathwayMeta = metaOf(pathwayPath, metaMap);
        let pathwaySide = DungeonComposer.oppositeSide(anchorSide);
        let pathwayDoorIn = match DungeonComposer.doorBySide(pathwaySide, pathwayMeta#doors) {
            case Some(d) => d
            case None    => bug!("DungeonGenerator: pathway ${pathwayPath} has no door on ${sideName(pathwaySide)}")
        };
        // pathway の世界座標 = anchor.offset + anchor.door
        let connectWorld = Vec2.addI(anchor#offset, anchorDoor);
        let pathwayOffset = Vec2.subI(connectWorld, pathwayDoorIn);
        // 通路の反対側 door = anchor と同じ side
        let pathwayDoorOut = match DungeonComposer.doorBySide(anchorSide, pathwayMeta#doors) {
            case Some(d) => d
            case None    => bug!("DungeonGenerator: pathway ${pathwayPath} has no door on ${sideName(anchorSide)}")
        };
        let outConnectWorld = Vec2.addI(pathwayOffset, pathwayDoorOut);
        // 新部屋の合うべき側 = anchor の反対 side
        let newRoomSide = DungeonComposer.oppositeSide(anchorSide);
        let newRoomMeta = metaOf(newRoomPath, metaMap);
        let newRoomDoor = match DungeonComposer.doorBySide(newRoomSide, newRoomMeta#doors) {
            case Some(d) => d
            case None    => bug!("DungeonGenerator: new room ${newRoomPath} has no door on ${sideName(newRoomSide)}")
        };
        let newRoomOffset = Vec2.subI(outConnectWorld, newRoomDoor);
        // 衝突検査: 新部屋 bbox が既配置の部屋と重ならないか
        if (collidesWithRooms(newRoomOffset, newRoomMeta#gridSize, state))
            None
        else {
            // commit: pathway と new room を追加し、anchor の usedSides を更新
            let pathwayEntry: Entry = {
                ldtkPath  = pathwayPath,
                offset    = pathwayOffset,
                gridSize  = pathwayMeta#gridSize,
                doors     = pathwayMeta#doors,
                isRoom    = false,
                usedSides = pathwaySide :: anchorSide :: Nil   // 通路は両端を使い切る
            };
            let newRoomEntry: Entry = {
                ldtkPath  = newRoomPath,
                offset    = newRoomOffset,
                gridSize  = newRoomMeta#gridSize,
                doors     = newRoomMeta#doors,
                isRoom    = true,
                usedSides = newRoomSide :: Nil
            };
            let pathwayIdx = state#next;
            let newRoomIdx = state#next + 1;
            let updatedAnchor: Entry = {
                usedSides = anchorSide :: anchor#usedSides
                | anchor
            };
            let entries1 = Map.insert(anchorIdx, updatedAnchor, state#entries);
            let entries2 = Map.insert(pathwayIdx, pathwayEntry, entries1);
            let entries3 = Map.insert(newRoomIdx, newRoomEntry, entries2);
            let conn1: PendingConn = { fromIdx = anchorIdx,  fromSide = anchorSide,
                                        toIdx   = pathwayIdx, toSide   = pathwaySide };
            let conn2: PendingConn = { fromIdx = pathwayIdx, fromSide = anchorSide,
                                        toIdx   = newRoomIdx, toSide   = newRoomSide };
            Some({
                entries = entries3,
                next    = state#next + 2,
                conns   = conn2 :: conn1 :: state#conns
            })
        }

    // ════════════════════════════════════════════════════════
    // ヘルパー: 候補抽出 / 衝突 / 整形
    // ════════════════════════════════════════════════════════

    /// 空き辺が 1 つ以上ある「部屋」の index を返す。通路は anchor にしない。
    def findAnchorCandidates(state: State): List[Int32] =
        Map.toList(state#entries)
        |> List.filter(kv -> {
            let (_, e) = kv;
            e#isRoom and List.length(e#usedSides) < 4
        })
        |> List.map(kv -> { let (k, _) = kv; k })

    def freeSidesOf(entry: Entry): List[DoorSide] =
        DungeonComposer.allSides()
        |> List.filter(s -> not List.exists(u -> u == s, entry#usedSides))

    def entryOf(idx: Int32, state: State): Entry =
        match Map.get(idx, state#entries) {
            case Some(e) => e
            case None    => bug!("DungeonGenerator: no entry at index ${idx}")
        }

    /// 新規 bbox が既配置の「部屋」と重なるかチェック。通路同士・通路と部屋の重複は許す
    /// （pathway パディングは空セルなので部屋優先 dedup で問題なし）。
    def collidesWithRooms(offset: Vec2.Vec2i, gridSize: Vec2.Vec2i, state: State): Bool =
        let aMinX = offset#x;
        let aMinY = offset#y;
        let aMaxX = offset#x + gridSize#x;
        let aMaxY = offset#y + gridSize#y;
        Map.toList(state#entries)
        |> List.exists(kv -> {
            let (_, e) = kv;
            if (not e#isRoom) false
            else
                let bMinX = e#offset#x;
                let bMinY = e#offset#y;
                let bMaxX = e#offset#x + e#gridSize#x;
                let bMaxY = e#offset#y + e#gridSize#y;
                // strict overlap: 接するだけは衝突しない
                aMinX < bMaxX and bMinX < aMaxX and aMinY < bMaxY and bMinY < aMaxY
        })

    def countRooms(state: State): Int32 =
        Map.toList(state#entries)
        |> List.count(kv -> { let (_, e) = kv; e#isRoom })

    /// 配置済み entries を「部屋を先・通路を後ろ」の modulePaths と
    /// それに対応する sideConnections に整形する。
    /// 旧 index → 新 index のマッピングを作って sideConnections を解決する。
    def buildPlan(state: State): Plan =
        let kvs = Map.toList(state#entries);
        // ソート: isRoom=true を先、isRoom=false を後ろ。同種は元の挿入順を維持。
        let rooms    = List.filter(kv -> { let (_, e) = kv; e#isRoom }, kvs);
        let pathways = List.filter(kv -> { let (_, e) = kv; not e#isRoom }, kvs);
        let ordered  = List.append(rooms, pathways);
        // 旧 index → 新 index の Map
        let (_, indexMap) = List.foldLeft(acc -> kv -> {
            let (newIdx, m) = acc;
            let (oldIdx, _) = kv;
            (newIdx + 1, Map.insert(oldIdx, newIdx, m))
        }, (0, Map.empty()), ordered);
        let modulePaths = List.map(kv -> { let (_, e) = kv; e#ldtkPath }, ordered);
        let sideConnections = List.map(c -> {
            let f = lookupRemap(c#fromIdx, indexMap);
            let t = lookupRemap(c#toIdx, indexMap);
            ({
                a = ({moduleIndex = f, side = c#fromSide}: SideRef),
                b = ({moduleIndex = t, side = c#toSide}:   SideRef)
            }: SideConnection)
        }, List.reverse(state#conns));   // 元の追加順に戻す（読みやすさのため）
        { modulePaths     = modulePaths,
          sideConnections = sideConnections,
          roomCount       = List.length(rooms) }

    def lookupRemap(oldIdx: Int32, m: Map[Int32, Int32]): Int32 =
        match Map.get(oldIdx, m) {
            case Some(n) => n
            case None    => bug!("DungeonGenerator: index remap failed for ${oldIdx}")
        }

    def pickOrBug(list: List[a], msg: String): a \ Math.Random =
        match RandomUtil.pick(list) {
            case Some(x) => x
            case None    => bug!("DungeonGenerator: ${msg}")
        }

    def sideName(side: DoorSide): String = match side {
        case DoorSide.Left   => "Left"
        case DoorSide.Right  => "Right"
        case DoorSide.Top    => "Top"
        case DoorSide.Bottom => "Bottom"
    }
}
