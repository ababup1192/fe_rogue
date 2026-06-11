/// MapSnapshot — 盤面の地形を表す純粋データ型と、その上の純粋クエリ層。
///
/// 地形は純粋データ（wallCells / placements / mapGlobal）で持ち、床判定・座標変換・モジュール
/// 逆引きはここの純関数（isWall/isFloor/mapToLocal/gridToWorld/moduleOfCell）で計算する。
/// scene を一切読まないため、game 層（Board / EnemyAI 等）がここに依存できる（盤面ロジック→View の逆流を防ぐ）。
/// 本物の TileMapLayer からの射影（snapshotOf）と scene ノード操作は view 層の `MapScene` 側に置く。
///
/// 型エイリアス `MapSnapshot` は root 定義（bare 参照のまま全 Scene が使う）。
pub type alias MapSnapshot = {
    tileSize    = Float64,
    usedRect    = { position = {x = Int32, y = Int32}, size = {x = Int32, y = Int32} },
    // 壁セル（グリッド座標）。範囲外は wallCells に含まれない＝非壁（engine と同義）。
    // tuple は Order を持つので Set 化でき、床判定が Set.memberOf になる。
    wallCells   = Set[(Int32, Int32)],
    // gridToWorld 用の Map ノード global position（加算オフセット）。
    mapGlobal   = {x = Float64, y = Float64},
    // moduleOfCell の素。MapScene.Data#placements と同一構造（既に純粋）。
    placements  = List[{idx = Int32,
                        offset = {x = Int32, y = Int32},
                        gridSize = {x = Int32, y = Int32},
                        floorBoundsMin = {x = Int32, y = Int32},
                        floorBoundsMaxEx = {x = Int32, y = Int32},
                        interiorCells = List[{x = Int32, y = Int32}]}]
}

mod MapSnapshot {

    /// マップのセル幅（ピクセル）。n-format ダンジョン (`tileset_dungeon_green`, 26px) に合わせる。
    /// グリッド ⇄ ピクセル変換が必要な全 Scene が参照する唯一の情報源。
    pub def tileSize(): Float64 = 26.0

    /// グリッド座標 → セル中心ピクセル座標。`tileSize` で求めた正方形セルの中央点を返す。
    /// Marker2D / Sprite2D を「マスのど真ん中」に置きたい全 Scene が共通で使う。
    pub def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// セルが壁か。範囲外セルは wallCells に含まれない＝非壁（engine getCellSourceId と同義）。
    pub def isWall(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        Set.memberOf((c#x, c#y), m#wallCells)

    /// 範囲内 かつ 壁でない＝床（engine TileMapLayer.isFloor と同義）。
    pub def isFloor(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        inBounds(c, m) and not isWall(c, m)

    /// usedRect 内か。getUsedRect は position=(0,0) 固定なので 0..size で判定（engine isInBounds と同義）。
    def inBounds(c: {x = Int32, y = Int32}, m: MapSnapshot): Bool =
        let sz = m#usedRect#size;
        c#x >= 0 and c#x < sz#x and c#y >= 0 and c#y < sz#y

    /// グリッド座標 → セル中心ローカル座標（cellCenter と同式・tileSize はデータから）。
    pub def mapToLocal(c: {x = Int32, y = Int32}, m: MapSnapshot): {x = Float64, y = Float64} =
        let s = m#tileSize;
        let v = Vec2i.toVec2(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// グリッド座標 → world 座標（Map global 加算済み。呼び出し側が MapScene の位置を知らずに済む）。
    pub def gridToWorld(c: {x = Int32, y = Int32}, m: MapSnapshot): {x = Float64, y = Float64} =
        Vec2.add(m#mapGlobal, mapToLocal(c, m))

    /// セル → 包含モジュール idx。`moduleOfCellIn` を placements データに当てる。
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
