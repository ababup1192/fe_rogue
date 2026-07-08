/// RoomLayout — 素朴な部屋 `DungeonComposer.ModulePlacement` を組む純ユーティリティ
///
/// Scene / effect 非依存のダンジョン配置ヘルパー群。
/// 単一部屋（`singleRoom`）/ 左右 2 部屋（`twoRoom`）の placements 構築と、
/// 任意 placement の中心セル算出（`moduleCenter`）。production（単一床レイアウト）と
/// テスト・map-test・診断（部屋を素早く組む共通構築点）の両方が使う。faction/sim 非依存。
mod RoomLayout {

    /// テスト・map-test・診断で全床の素朴な部屋を素早く組むための共通構築点。
    pub def placement(idx: Int32, ox: Int32, oy: Int32, w: Int32, h: Int32):
            DungeonComposer.ModulePlacement =
        {
            idx              = idx,
            offset           = ({x = ox, y = oy}: {x = Int32, y = Int32}),
            gridSize         = ({x = w,  y = h }: {x = Int32, y = Int32}),
            floorBoundsMin   = ({x = 0,  y = 0 }: {x = Int32, y = Int32}),
            floorBoundsMaxEx = ({x = w,  y = h }: {x = Int32, y = Int32}),
            interiorCells    = (Nil: List[{x = Int32, y = Int32}])
        }

    /// 全床 w×h を単一モジュール(idx=0)に割る placements。
    pub def singleRoom(w: Int32, h: Int32): List[DungeonComposer.ModulePlacement] =
        placement(0, 0, 0, w, h) :: Nil

    /// floorBounds を左右に分割した 2 モジュール（idx0 / idx1）の placements。
    /// 検知テスト（同じ部屋にいるか）で moduleOfCell を 2 部屋にしたいときに使う。
    pub def twoRoom(w: Int32, h: Int32): List[DungeonComposer.ModulePlacement] =
        let half = w / 2;
        ({idx = 0, offset = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          gridSize = ({x = w, y = h}: {x = Int32, y = Int32}),
          floorBoundsMin = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          floorBoundsMaxEx = ({x = half, y = h}: {x = Int32, y = Int32}),
          interiorCells = (Nil: List[{x = Int32, y = Int32}])}: DungeonComposer.ModulePlacement) ::
        ({idx = 1, offset = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          gridSize = ({x = w, y = h}: {x = Int32, y = Int32}),
          floorBoundsMin = ({x = half, y = 0}: {x = Int32, y = Int32}),
          floorBoundsMaxEx = ({x = w, y = h}: {x = Int32, y = Int32}),
          interiorCells = (Nil: List[{x = Int32, y = Int32}])}: DungeonComposer.ModulePlacement) :: Nil

    /// 発見演出で「部屋の中心にカメラを寄せる」ために使う。
    /// floorBounds の bbox 計算を `moduleOfCellIn` と一致させることで、境界判定との一貫性を保つ。
    pub def moduleCenter(idx: Int32,
                          placements: List[DungeonComposer.ModulePlacement]):
            Option[{x = Int32, y = Int32}] =
        List.findMap(p ->
            if (p#idx == idx) {
                let minX = p#offset#x + p#floorBoundsMin#x;
                let minY = p#offset#y + p#floorBoundsMin#y;
                let maxX = p#offset#x + p#floorBoundsMaxEx#x;
                let maxY = p#offset#y + p#floorBoundsMaxEx#y;
                Some(({x = (minX + maxX - 1) / 2,
                       y = (minY + maxY - 1) / 2}: {x = Int32, y = Int32}))
            } else None,
            placements)

}
