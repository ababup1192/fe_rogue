// Stage — StageDoc の rows(文字格子)を遊べる形に組む。すべて純粋。
//
// ── 文字の対応表(この表が正 — StageDoc の note と揃える)──
//   #  土(硬い)          X  石(硬い)          W  背後壁だけ(通れる)
//   =  一方通行床          ~  動く床(横往復)     !  消える床(点滅)
//   o  コイン              S  バネ                T  松明
//   c  チェックポイント    G  ゴール旗            P  開始位置
//   a  歩く敵              b  飛ぶ敵              z  撃つ敵
//   .  空
//
// 格子は不変(コインの取得などの進行は World が集合で覚える — rows は書き換えない)。
// 動く床・敵は「湧き場所」だけここが読み、動きは World / Enemies の仕事。
mod Stage {

    pub type alias Cell = { x = Int32, y = Int32 }

    /// 動く床 1 枚。cell は左端の休止位置、wTiles = 幅、横に ampTiles 往復する。
    pub type alias Platform = { cell = Cell, wTiles = Int32 }

    pub type alias Stage = {
        name = String,
        kind = String,               // outdoor / cave / tower(空気の選択)
        rows = Vector[Vector[Char]],
        width = Int32,
        height = Int32,
        start = Cell,
        coins = List[Cell],
        springs = List[Cell],
        torches = List[Cell],
        checkpoints = List[Cell],
        goal = Cell,
        platforms = List[Platform],
        walkers = List[Cell],
        flyers = List[Cell],
        shooters = List[Cell]
    }

    /// Spec(rows)から Stage を組む。行長の不揃いは短い方に合わせず、
    /// 格子外扱い(charAt が '.' を返す)で吸収する。
    pub def make(spec: StageDoc.Spec): Stage =
        let rows = spec#rows |> List.map(r -> String.toList(r) |> List.toVector) |> List.toVector;
        let height = Vector.length(rows);
        let width = rows |> Vector.foldLeft((acc, r) -> Int32.max(acc, Vector.length(r)), 0);
        let find = byChar(spec#rows);
        { name = spec#name, kind = spec#kind, rows = rows,
          width = width, height = height,
          start = List.head(find('P')) |> Option.getWithDefault({ x = 2, y = 2 }),
          coins = find('o'),
          springs = find('S'),
          torches = find('T'),
          checkpoints = find('c'),
          goal = List.head(find('G'))
              |> Option.getWithDefault({ x = width - 2, y = 2 }),
          platforms = platformsOf(find('~')),
          walkers = find('a'),
          flyers = find('b'),
          shooters = find('z') }

    /// 格子の 1 文字。外は '.'(空)— 落下死はステージ最下段より下で World が判定する。
    pub def charAt(st: Stage, x: Int32, y: Int32): Char =
        match Vector.nth(y, st#rows) {
            case Some(row) => Vector.nth(x, row) |> Option.getWithDefault('.')
            case None      => '.'
        }

    /// 全方向に硬いか。左右端の外も硬い(横に落ちない)。
    pub def solidAt(st: Stage, x: Int32, y: Int32): Bool =
        if (x < 0 or x >= st#width) true
        else {
            let ch = charAt(st, x, y);
            ch == '#' or ch == 'X'
        }

    /// 一方通行の床か(= のマス)。
    pub def oneWayAt(st: Stage, x: Int32, y: Int32): Bool =
        charAt(st, x, y) == '='

    /// 消える床のマスか(点滅の位相は World が時刻から決める)。
    pub def blinkAt(st: Stage, x: Int32, y: Int32): Bool =
        charAt(st, x, y) == '!'

    /// 背後壁を敷くマスか。cave の通れるマス(W と、ギミックが置かれた空洞)に敷く。
    pub def wallAt(st: Stage, x: Int32, y: Int32): Bool =
        if (st#kind != "cave" or solidAt(st, x, y)) false
        else {
            let ch = charAt(st, x, y);
            if (ch == '.') hasNeighborTunnel(st, x, y) else true
        }

    /// '.' でも周囲(自分含む 3×3)に W があれば洞窟の空洞とみなす —
    /// rows の W の塗り忘れで壁に穴が開かないための救済。
    def hasNeighborTunnel(st: Stage, x: Int32, y: Int32): Bool =
        List.range(-1, 2) |> List.exists(dy ->
            List.range(-1, 2) |> List.exists(dx ->
                charAt(st, x + dx, y + dy) == 'W'))

    /// マスの中心のワールド px。
    pub def centerOf(cell: Cell): Vec2.Vec2 =
        let ts = Physics.tileSize();
        { x = (Int32.toFloat64(cell#x) + 0.5) * ts,
          y = (Int32.toFloat64(cell#y) + 0.5) * ts }

    /// ステージ全体のワールド矩形(px)。カメラの見せる範囲。
    pub def worldRect(st: Stage): Rect2.Rect2 =
        let ts = Physics.tileSize();
        { position = { x = 0.0, y = 0.0 },
          size = { x = Int32.toFloat64(st#width) * ts,
                   y = Int32.toFloat64(st#height) * ts } }

    // ── 抽出 ──

    /// 文字 → その文字のマス(上の行から・行の中は左から)を引く関数。
    /// 格子を 1 度ほどいて振り分けるので、種類が増えても走査は 1 回のまま。
    def byChar(rows: List[String]): Char -> List[Cell] =
        let table = Grid.cellsOfRows(rows)
            |> List.foldLeft((acc, e) -> {
                let (cell, ch) = e;
                Map.insertWith((newL, oldL) -> newL ::: oldL, ch, cell :: Nil, acc)
            }, Map.empty())
            |> Map.map(List.reverse);
        ch -> Map.get(ch, table) |> Option.getWithDefault(Nil)

    /// 連続した '~' の水平の並びを 1 枚の動く床にまとめる(左端セル + 幅)。
    def platformsOf(tildes: List[Cell]): List[Platform] =
        let keys = tildes |> List.map(c -> (c#x, c#y));
        let isT = (x, y) -> List.memberOf((x, y), keys);
        tildes
            |> List.filter(c -> not isT(c#x - 1, c#y))   // 各並びの左端だけ
            |> List.map(c -> { cell = c, wTiles = runLength(isT, c#x, c#y, 0) })

    def runLength(isT: (Int32, Int32) -> Bool, x: Int32, y: Int32, acc: Int32): Int32 =
        if (isT(x + acc, y)) runLength(isT, x, y, acc + 1) else acc
}
