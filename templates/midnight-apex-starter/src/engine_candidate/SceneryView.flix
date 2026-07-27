// SceneryView — 道路から独立した基板平原へ、JSONの回路模様を透視投影する。
mod SceneryView {

    /// 固定消失点の左右平面を使い、コースが曲がっても回路柄そのものは引きずらない。
    pub def draw(world: World.World, z: Int32): List[Render.PlacedItem] =
        let projection = Perspective.config(
            World.designWidth(), World.designHeight());
        let sampleAt = CourseProjection.sampler(
            World.designWidth(), world#course);
        Perspective.slices(visibleProgress(world), sampleAt, projection)
            |> consecutivePairs
            |> List.zipWithIndex
            |> List.filter(entry -> {
                let (index, pair) = entry;
                let (near, _) = pair;
                Int32.modulo(index, world#scenery#circuitStride) == 0
                    and near#y > projection#horizonY + 4.0
            })
            |> List.flatMap(entry -> {
                let (_, pair) = entry;
                pcbHalf(
                    -1.0, pair, world#scenery,
                    world#sprites, world#theme, z)
                ::: pcbHalf(
                    1.0, pair, world#scenery,
                    world#sprites, world#theme, z)
            })

    /// 自動生成の細線を地模様、文字格子を意図的な密集として重ねる。
    def pcbHalf(side: Float64,
                pair: (CourseProjection.Slice, CourseProjection.Slice),
                scenery: SceneryDoc.Doc,
                sprites: PxSpriteDoc.Doc,
                theme: ThemeDoc.Doc,
                z: Int32): List[Render.PlacedItem] =
        let (near, _far) = pair;
        let traceColor =
            if (side < 0.0)
                ThemeDoc.darken(theme#shoulder, scenery#circuitBrightness)
            else
                ThemeDoc.darken(theme#player, scenery#circuitBrightness);
        let branchColor =
            if (side < 0.0)
                ThemeDoc.darken(theme#lane, 0.52)
            else
                ThemeDoc.darken(theme#rivalB, 0.58);
        let weight = Float64.max(
            0.42, near#scale * scenery#circuitLineWidth);
        copperPatches(side, pair, scenery, theme, z)
        ::: authoredPattern(side, pair, scenery, sprites, theme, z + 1)
        ::: parallelTraces(
                side, pair, scenery,
                traceColor, branchColor, weight, z + 2)
        ::: branchBuses(
                side, pair, scenery, branchColor, weight, z + 2)
        ::: viaField(
                side, pair, scenery, traceColor, theme, z + 3)

    /// 多数の平行線を束にし、一本ずつの色と太さを少しずつ変える。
    def parallelTraces(side: Float64,
                       pair: (CourseProjection.Slice, CourseProjection.Slice),
                       scenery: SceneryDoc.Doc,
                       traceColor: Color,
                       branchColor: Color,
                       weight: Float64,
                       z: Int32): List[Render.PlacedItem] =
        let (near, far) = pair;
        List.range(0, scenery#circuitTraceCount)
            |> List.map(index -> {
                let ratio = traceRatio(index, scenery);
                let color =
                    if (Int32.modulo(index, 3) == 1)
                        branchColor
                    else if (Int32.modulo(index, 3) == 2)
                        ThemeDoc.darken(traceColor, 0.76)
                    else
                        traceColor;
                let lineWeight =
                    if (Int32.modulo(index, 4) == 0)
                        weight
                    else
                        Float64.max(0.36, weight * 0.62);
                Render.lineSeg(
                    { x = halfX(side, near, ratio), y = near#y },
                    { x = halfX(side, far, ratio), y = far#y },
                    lineWeight, color, z)
            })

    /// 横枝の長さを区間ごとに変え、規則正しい梯子に見えるのを避ける。
    def branchBuses(side: Float64,
                    pair: (CourseProjection.Slice, CourseProjection.Slice),
                    scenery: SceneryDoc.Doc,
                    color: Color,
                    weight: Float64,
                    z: Int32): List[Render.PlacedItem] =
        let (near, far) = pair;
        let third = Int32.max(1, scenery#circuitTraceCount / 3);
        List.range(0, scenery#circuitBranchCount)
            |> List.map(index -> {
                let t = Int32.toFloat64(index + 1)
                    / Int32.toFloat64(scenery#circuitBranchCount + 1);
                let startIndex = Int32.modulo(
                    near#meta#rowIndex + index * 2, third);
                let endIndex = scenery#circuitTraceCount - 1
                    - Int32.modulo(near#meta#rowIndex + index, third);
                let startRatio = traceRatio(startIndex, scenery);
                let endRatio = traceRatio(endIndex, scenery);
                let y = lerp(far#y, near#y, t);
                Render.lineSeg(
                    { x = lerp(
                          halfX(side, far, startRatio),
                          halfX(side, near, startRatio), t),
                      y = y },
                    { x = lerp(
                          halfX(side, far, endRatio),
                          halfX(side, near, endRatio), t),
                      y = y },
                    Float64.max(0.36, weight * 0.58),
                    color, z)
            })

    /// ビアを配線上へ散らし、外輪と暗い穴の二重円で平面の穴として見せる。
    def viaField(side: Float64,
                 pair: (CourseProjection.Slice, CourseProjection.Slice),
                 scenery: SceneryDoc.Doc,
                 color: Color,
                 theme: ThemeDoc.Doc,
                 z: Int32): List[Render.PlacedItem] =
        let (near, far) = pair;
        let phase = Int32.modulo(near#meta#rowIndex, 5);
        let t = 0.18 + Int32.toFloat64(phase) * 0.15;
        let radius = Float64.max(
            0.52,
            scenery#circuitViaSize
                * lerp(far#scale, near#scale, t));
        let y = lerp(far#y, near#y, t);
        List.range(0, scenery#circuitTraceCount)
            |> List.filter(index ->
                Int32.modulo(
                    index + near#meta#rowIndex,
                    scenery#circuitViaEvery) == 0)
            |> List.flatMap(index -> {
                let ratio = traceRatio(index, scenery);
                let x = lerp(
                    halfX(side, far, ratio),
                    halfX(side, near, ratio), t);
                Render.circleAt({ x = x, y = y }, radius, color, z)
                :: Render.circleAt(
                    { x = x, y = y },
                    Float64.max(0.26, radius * 0.40),
                    ThemeDoc.darken(theme#night, 0.72),
                    z + 1)
                :: Nil
            })

    /// JSON文字格子は左右別の設計図を使い、線束の密集・空白・大きな面を非対称にする。
    def authoredPattern(side: Float64,
                        pair: (CourseProjection.Slice, CourseProjection.Slice),
                        scenery: SceneryDoc.Doc,
                        sprites: PxSpriteDoc.Doc,
                        theme: ThemeDoc.Doc,
                        z: Int32): List[Render.PlacedItem] =
        let spriteName =
            if (side < 0.0) "circuit_left" else "circuit_right";
        match Map.get(spriteName, sprites#sprites) {
            case None => Nil
            case Some(sprite) => match Map.get("idle", sprite#frames) {
                case None => Nil
                case Some(rows) => {
                    let (near, _far) = pair;
                    let rowCount = List.length(rows);
                    if (rowCount == 0)
                        Nil
                    else {
                        let rowIndex = Int32.modulo(
                            near#meta#rowIndex + if (side < 0.0) 0 else 11,
                            rowCount);
                        let row = List.nth(rowIndex, rows)
                            |> Option.getWithDefault("");
                        let columns = patternWidth(rows);
                        String.toList(row)
                            |> List.zipWithIndex
                            |> List.filterMap(entry -> {
                                let (column, symbol) = entry;
                                Map.get(symbol, sprites#legend)
                                    |> Option.map(key -> (column, key))
                            })
                            |> List.flatMap(cell -> {
                                let (column, key) = cell;
                                patternCell(
                                    side, pair, scenery, theme,
                                    column, columns, key, z)
                            })
                    }
                }
            }
        }

    def patternCell(side: Float64,
                    pair: (CourseProjection.Slice, CourseProjection.Slice),
                    scenery: SceneryDoc.Doc,
                    theme: ThemeDoc.Doc,
                    column: Int32,
                    columns: Int32,
                    key: String,
                    z: Int32): List[Render.PlacedItem] =
        let (near, far) = pair;
        let safeColumns = Int32.max(1, columns);
        let startT = Int32.toFloat64(column)
            / Int32.toFloat64(safeColumns);
        let finishT = Int32.toFloat64(column + 1)
            / Int32.toFloat64(safeColumns);
        let centerT = (startT + finishT) / 2.0;
        let color = patternColor(side, key, theme);
        if (key == "circuitVia") {
            let center = {
                x = lerp(
                    halfX(side, far, centerT),
                    halfX(side, near, centerT), 0.5),
                y = lerp(far#y, near#y, 0.5)
            };
            let radius = Float64.max(
                0.52,
                scenery#circuitViaSize
                    * lerp(far#scale, near#scale, 0.5));
            Render.circleAt(center, radius, color, z)
            :: Render.circleAt(
                center,
                Float64.max(0.26, radius * 0.40),
                ThemeDoc.darken(theme#night, 0.72),
                z + 1)
            :: Nil
        } else {
            let vertices =
                { x = halfX(side, near, startT), y = near#y }
                :: { x = halfX(side, near, finishT), y = near#y }
                :: { x = halfX(side, far, finishT), y = far#y }
                :: { x = halfX(side, far, startT), y = far#y }
                :: Nil;
            { at = Vec2.zero(),
              item = Render.polygon(vertices, color, z) }
            :: Nil
        }

    /// 大きな銅箔面は頻度だけDocで調整し、配線の細さとの対比を作る。
    def copperPatches(side: Float64,
                      pair: (CourseProjection.Slice, CourseProjection.Slice),
                      scenery: SceneryDoc.Doc,
                      theme: ThemeDoc.Doc,
                      z: Int32): List[Render.PlacedItem] =
        let (near, far) = pair;
        let visible = Int32.modulo(
            near#meta#rowIndex + if (side < 0.0) 0 else 2,
            scenery#circuitPadEvery) == 0;
        if (not visible)
            Nil
        else {
            let phase = Int32.modulo(near#meta#rowIndex, 3);
            let start = 0.06 + Int32.toFloat64(phase) * 0.18;
            let finish = Float64.min(0.94, start + 0.20);
            let vertices =
                { x = halfX(side, near, start), y = near#y }
                :: { x = halfX(side, near, finish), y = near#y }
                :: { x = halfX(side, far, finish), y = far#y }
                :: { x = halfX(side, far, start), y = far#y }
                :: Nil;
            { at = Vec2.zero(),
              item = Render.polygon(
                  vertices,
                  ThemeDoc.darken(
                      if (side < 0.0) theme#shoulder else theme#player,
                      0.72),
                  z) }
            :: Nil
        }

    /// 回路模様の意味色キー → 実色。side は道のどちら側かで、色を左右で振り分ける。
    /// Studio 用の色票（Palette）も同じここを引くので、実色を決める場所が 2 つに割れない。
    pub def patternColor(side: Float64,
                         key: String,
                         theme: ThemeDoc.Doc): Color =
        if (key == "copperPlane")
            ThemeDoc.darken(
                if (side < 0.0) theme#shoulder else theme#player,
                0.70)
        else if (key == "circuitTraceDim")
            ThemeDoc.darken(theme#lane, 0.64)
        else if (key == "circuitVia")
            ThemeDoc.lighten(
                if (side < 0.0) theme#lane else theme#rivalB,
                0.14)
        else
            ThemeDoc.darken(
                if (side < 0.0) theme#shoulder else theme#player,
                0.38)

    /// ratio=0 は画面端側、1 は中央。道路中心を参照しないため平原は曲線から独立する。
    def halfX(side: Float64,
              slice: CourseProjection.Slice,
              ratio: Float64): Float64 =
        let outerT = if (side < 0.0) 0.0 else 1.0;
        fieldX(slice, lerp(outerT, 0.5, ratio))

    def fieldX(slice: CourseProjection.Slice, t: Float64): Float64 =
        World.designWidth() / 2.0
            + (t - 0.5) * World.designWidth() * slice#scale * 1.48

    def traceRatio(index: Int32, scenery: SceneryDoc.Doc): Float64 =
        let last = Int32.max(1, scenery#circuitTraceCount - 1);
        lerp(
            scenery#circuitOuterRatio,
            scenery#circuitInnerRatio,
            Int32.toFloat64(index) / Int32.toFloat64(last))

    def patternWidth(rows: List[String]): Int32 =
        rows
            |> List.foldLeft(
                (widest, row) -> Int32.max(widest, String.length(row)),
                1)

    def lerp(start: Float64, finish: Float64, t: Float64): Float64 =
        start + (finish - start) * t

    def consecutivePairs(slices: List[CourseProjection.Slice]):
            List[(CourseProjection.Slice, CourseProjection.Slice)] =
        match slices {
            case first :: second :: rest =>
                (first, second) :: consecutivePairs(second :: rest)
            case _ => Nil
        }

    /// 表紙はS字入口、走行中は現在位置を地面の流れにも共有する。
    def visibleProgress(world: World.World): Float64 =
        if (world#phase == World.Phase.Title)
            Course.rowDistance() * 8.5
        else
            world#totalProgress * world#scenery#circuitScrollMultiplier
}
