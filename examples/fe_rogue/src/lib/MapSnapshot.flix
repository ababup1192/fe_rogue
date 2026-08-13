/// MapSnapshot — 盤面の地形を表す純粋データ型と、その上の純粋クエリ層。
///
/// 地形は純粋データ（wallCells / placements / mapGlobal）で持ち、床判定・座標変換・モジュール
/// 逆引きはここの純関数（isWall/isFloor/mapToLocal/gridToWorld/moduleOfCell）で計算する。
/// scene を一切読まないため、game 層（Board / EnemyAI 等）がここに依存できる（盤面ロジック→View の逆流を防ぐ）。
/// 本物の TileLayer 値からの射影（snapshotOf）は build 側の `MapSetup` に置く。
///
/// モジュール内に入れると `MapSnapshot.MapSnapshot` と修飾が必要になるため、型エイリアスは root に定義する。
pub type alias MapSnapshot = {
    tileSize    = Float64,
    usedRect    = { position = {x = Int32, y = Int32}, size = {x = Int32, y = Int32} },
    // 壁セル（グリッド座標）。範囲外セルは登録しない約束で、isWall が非壁と判定できる。
    // tuple は Order を持つので Set 化でき、床判定が Set.memberOf になる。
    wallCells   = Set[(Int32, Int32)],
    // gridToWorld 用の Map ノード global position（加算オフセット）。
    mapGlobal   = {x = Float64, y = Float64},
    // スナップショット取得時に追加変換が不要なため、DungeonComposer の placements をそのまま保持する。
    placements  = List[{idx = Int32,
                        offset = {x = Int32, y = Int32},
                        gridSize = {x = Int32, y = Int32},
                        floorBoundsMin = {x = Int32, y = Int32},
                        floorBoundsMaxEx = {x = Int32, y = Int32},
                        interiorCells = List[{x = Int32, y = Int32}]}]
}

mod MapSnapshot {

    /// マップのセル幅（ピクセル）。使用タイルセットのグリッド解像度に固定された定数で、
    /// グリッド ⇄ ピクセル変換が必要な全モジュールが参照する source of truth。
    pub def tileSize(): Float64 = 26.0

    /// グリッド座標 → セル中心ピクセル座標。MapSnapshot を持たない呼び出し側が
    /// グローバル `tileSize()` だけで中央座標を得るために用意した軽量版。
    /// MapSnapshot を持つ場合は `mapToLocal` を使えばスナップショット固有の tileSize を参照できる。
    /// セル中心の芯は engine_world の `Grid.cellCenter` に委譲し（原点は持たない）、
    /// マップ原点の加算は `gridToWorld` 側の政策として残す。
    pub def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        Grid.cellCenter(tileSize(), (cell#x, cell#y))

    /// セルが壁か。範囲外セルは wallCells に登録されないため、壁として扱わない契約。
    pub def isWall(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        Set.memberOf((c#x, c#y), m#wallCells)

    /// 範囲内 かつ 壁でない＝床。両条件の積で定義することで、範囲外は壁・床どちらでもない扱いになる。
    pub def isFloor(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        inBounds(c, m) and not isWall(c, m)

    /// usedRect 内か。usedRect は position=(0,0) 基準で size のみ持つため、
    /// 判定は size のみで十分（position を加算しても 0 なので省略できる）。
    def inBounds(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        let sz = m#usedRect#size;
        c#x >= 0 and c#x < sz#x and c#y >= 0 and c#y < sz#y

    /// グリッド座標 → セル中心ローカル座標。スナップショット固有の tileSize を引数から取るため、
    /// 呼び出し側が MapSnapshot を保持していればグローバル定数に依存せず変換できる。
    /// セル中心の芯は `Grid.cellCenter` に委譲する（原点なし。原点加算は `gridToWorld`）。
    pub def mapToLocal(c: {x = Int32, y = Int32}, m: MapSnapshot): {x = Float64, y = Float64} =
        Grid.cellCenter(m#tileSize, (c#x, c#y))

    /// グリッド座標 → world 座標（Map global 加算済み。呼び出し側がマップ原点を知らずに済む）。
    pub def gridToWorld(c: {x = Int32, y = Int32}, m: MapSnapshot): {x = Float64, y = Float64} =
        Vec2.add(m#mapGlobal, mapToLocal(c, m))

    /// セル → 包含モジュール idx。placements を外部に公開せず MapSnapshot ごと渡せる便利 API として提供する。
    pub def moduleOfCell(c: {x = Int32, y = Int32}, m: MapSnapshot): Option[Int32] =
        moduleOfCellIn(c, m#placements)

    /// `placements` を「先勝ち（idx 昇順）」で走査し、`coord` を含む最初のモジュール idx を返す。
    /// modulePaths は「部屋を先・通路を後ろ」で並ぶため、部屋優先で逆引きできる。
    /// bbox は `floorBoundsMin/MaxEx` ベース（n-format で gridSize より厳しい実効床範囲）。
    pub def moduleOfCellIn(coord: {x = Int32, y = Int32},
                            placements: List[{idx = Int32,
                                              offset = {x = Int32, y = Int32},
                                              gridSize = {x = Int32, y = Int32},
                                              floorBoundsMin = {x = Int32, y = Int32},
                                              floorBoundsMaxEx = {x = Int32, y = Int32},
                                              interiorCells = List[{x = Int32, y = Int32}]}]): Option[Int32] =
        List.findMap(p -> {
            let minX = p#offset#x + p#floorBoundsMin#x;
            let minY = p#offset#y + p#floorBoundsMin#y;
            let maxX = p#offset#x + p#floorBoundsMaxEx#x;
            let maxY = p#offset#y + p#floorBoundsMaxEx#y;
            if (coord#x >= minX and coord#x < maxX
                and coord#y >= minY and coord#y < maxY) Some(p#idx)
            else None
        }, placements)
}
