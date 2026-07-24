// Course — 累積距離を、画面上の道路の中心と幅へ写す純粋な変換。
// World の路面判定と View の道路描画は、必ずこのモジュールの同じ Sample を使う。
mod Course {

    /// 道路を調べる位置。距離と画面幅をレコードに束ね、同じ Float64 の取り違えを防ぐ。
    pub type alias SampleInput = {
        totalProgress = Float64,
        screenWidth = Float64
    }

    /// ある距離における道路の断面。
    ///   centerX     … 画面上の道路中央。
    ///   width       … 画面上の道路幅。
    ///   lapProgress … 一周内で進んだ距離。
    ///   rowIndex    … 元になった rows の行番号。
    pub type alias Sample = {
        centerX = Float64,
        width = Float64,
        lapProgress = Float64,
        rowIndex = Int32
    }

    /// 車体が道路内か調べるための横方向の占有範囲。
    pub type alias Footprint = {
        centerX = Float64,
        halfWidth = Float64
    }

    /// rows の 1 行が表す進行距離。表示の細かさと一周の長さを一つの値にそろえる。
    pub def rowDistance(): Float64 = 42.0

    /// 一周を、見た目と走り方が変わる6区間に分ける。
    pub def sectorCount(): Int32 = 6

    /// コース一周の距離。rows を増減すると自動で追随する。
    pub def lapLength(course: CourseDoc.Doc): Float64 =
        Int32.toFloat64(List.length(course#rows)) * rowDistance()

    /// 累積距離に対応する道路断面を返す。
    /// 隣り合う rows の中心と幅を補間するため、文字格子でもカーブが段差にならない。
    pub def sample(input: SampleInput, course: CourseDoc.Doc): Sample =
        let safeLapLength = Float64.max(rowDistance(), lapLength(course));
        let completedLaps = Float64.floor(input#totalProgress / safeLapLength);
        let lapProgress = input#totalProgress - completedLaps * safeLapLength;
        let rowPosition = lapProgress / rowDistance();
        let rowIndex = floorToInt(rowPosition);
        let fraction = rowPosition - Int32.toFloat64(rowIndex);
        let current = spanAt(rowIndex, course);
        let next = spanAt(rowIndex + 1, course);
        { centerX = lerp(current#centerRatio, next#centerRatio, fraction) * input#screenWidth,
          width = lerp(current#widthRatio, next#widthRatio, fraction) * input#screenWidth,
          lapProgress = lapProgress,
          rowIndex = rowIndex }

    /// 車体の左右端が両方とも路面内に収まっているか。
    pub def contains(footprint: Footprint, sample: Sample): Bool =
        let roadLeft = sample#centerX - sample#width / 2.0;
        let roadRight = sample#centerX + sample#width / 2.0;
        footprint#centerX - footprint#halfWidth >= roadLeft
            and footprint#centerX + footprint#halfWidth <= roadRight

    /// 道路中央から laneOffset（-1..1）ぶん左右へ寄せた位置。
    /// ライバルの判定と描画で同じ式を共有し、カーブ上の位置をずらさない。
    pub def laneCenter(laneOffset: Float64, sample: Sample): Float64 =
        sample#centerX + laneOffset * sample#width * 0.34

    /// 一周を6区間に分けた現在区間（0..5）。ネオンゲートとHUDが同じ境界を使う。
    pub def sectorIndex(totalProgress: Float64, course: CourseDoc.Doc): Int32 =
        let length = Float64.max(rowDistance(), lapLength(course));
        let lapProgress = sample({ totalProgress = totalProgress, screenWidth = 1.0 }, course)#lapProgress;
        let sectorLength = length / Int32.toFloat64(sectorCount());
        Int32.min(sectorCount() - 1, floorToInt(lapProgress / sectorLength))

    /// `=` を含む断面か調べる。配置は Doc、加速する規則は World に残す。
    pub def isBoostStrip(totalProgress: Float64, course: CourseDoc.Doc): Bool =
        let rowIndex = sample(
            { totalProgress = totalProgress, screenWidth = 1.0 },
            course)#rowIndex;
        wrappedRowAt(rowIndex, course)
            |> String.toList
            |> List.exists(character -> character == '=')

    /// `^` を含む断面か調べる。配置は Doc、飛ぶ規則は World に残す。
    pub def isJumpRamp(totalProgress: Float64, course: CourseDoc.Doc): Bool =
        let rowIndex = sample(
            { totalProgress = totalProgress, screenWidth = 1.0 },
            course)#rowIndex;
        wrappedRowAt(rowIndex, course)
            |> String.toList
            |> List.exists(character -> character == '^')

    /// 一拍の移動区間に `^` の行が含まれるか。最高速で短い台をまたいでも拾う。
    pub def crossedJumpRamp(
        path: { fromProgress = Float64, toProgress = Float64 },
        course: CourseDoc.Doc
    ): Bool =
        let firstRow = floorToInt(path#fromProgress / rowDistance());
        let lastRow = floorToInt(path#toProgress / rowDistance());
        let firstCrossedRow = firstRow + 1;
        if (lastRow < firstCrossedRow)
            false
        else
            List.range(firstCrossedRow, lastRow + 1)
                |> List.exists(rowIndex ->
                    wrappedRowAt(rowIndex, course)
                        |> String.toList
                        |> List.exists(character -> character == '^'))

    /// 現在行に左右壁の記号があるか。開いた路肩と反発区間を分ける。
    pub def hasWalls(totalProgress: Float64, course: CourseDoc.Doc): Bool =
        let rowIndex = sample(
            { totalProgress = totalProgress, screenWidth = 1.0 },
            course)#rowIndex;
        wrappedRowAt(rowIndex, course)
            |> String.toList
            |> List.exists(character -> character == '[' or character == ']')

    type alias Span = {
        centerRatio = Float64,
        widthRatio = Float64
    }

    def spanAt(rowIndex: Int32, course: CourseDoc.Doc): Span =
        let row = wrappedRowAt(rowIndex, course);
        let columns = String.toList(row)
            |> List.zipWithIndex
            |> List.filter(entry -> {
                let (_, character) = entry;
                character == '#' or character == '=' or character == '^'
            })
            |> List.map(fst);
        let columnCount = Int32.max(1, String.length(row));
        match (List.head(columns), List.reverse(columns) |> List.head) {
            case (Some(firstColumn), Some(lastColumn)) =>
                let widthColumns = lastColumn - firstColumn + 1;
                { centerRatio = (Int32.toFloat64(firstColumn) + Int32.toFloat64(widthColumns) / 2.0)
                        / Int32.toFloat64(columnCount),
                  widthRatio = Int32.toFloat64(widthColumns) / Int32.toFloat64(columnCount) }
            case _ =>
                // 道路記号が無い行でも白画面やゼロ幅にせず、中央の安全な道へ倒す。
                { centerRatio = 0.5, widthRatio = 0.35 }
        }

    def wrappedRowAt(rowIndex: Int32, course: CourseDoc.Doc): String =
        let rowCount = List.length(course#rows);
        if (rowCount <= 0) ""
        else {
            let wrapped = Int32.modulo(Int32.modulo(rowIndex, rowCount) + rowCount, rowCount);
            List.nth(wrapped, course#rows) |> Option.getWithDefault("")
        }

    def floorToInt(value: Float64): Int32 =
        Float64.floor(value) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    def lerp(startValue: Float64, endValue: Float64, amount: Float64): Float64 =
        startValue + (endValue - startValue) * amount
}
