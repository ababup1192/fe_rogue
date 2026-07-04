// Board — sokoban 1セッションぶんの全状態と、グリッド上の純粋なルール。壁・ゴール・
// クレートはそれぞれ Store（グリッド座標の Set 1個）。ルールはグリッド上に住み、
// 絵（ロボットがどのセルから移動中に描かれるか、巻き戻し時計）も状態なので同じ
// レコードに同居し、View によってピクセルへ投影される。
//
// ここにあるものはすべて純粋で時間から自由: Board と Input が与えられれば、ルール
// が次の Board を言い当てる。dt による進行、履歴、loop は Sokoban に住み、描画は
// View に住む。

mod Board {

    // ── Input: このフレームのキー入力を素のデータとして ──
    // キーボードは World の外に住む。`enter` はレベルではなくエッジ: キーが押された
    // フレームだけ true なので、1回の押下はちょうど1ページだけをめくる。held か
    // pressed かは loop が判定し、ルールは判定結果だけを見る。
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool,
                             undo = Bool, enter = Bool, back = Bool, esc = Bool }

    /// 中立の入力: 何も押されていない状態。ルールがキーボードを黙らせたまま1フレー
    /// ムを走らせる必要がある場所（巻き戻し中、CLEAR のお祝い）で使う。
    pub def noKeys(): Input =
        { up = false, down = false, left = false, right = false,
          undo = false, enter = false, back = false, esc = false }

    // ── 絵の状態: Board のうち描画だけが読むフィールド ──
    // slide は描画位置の移動量: ホップ（あるいは巻き戻し）が確定すると、ロボットの
    // セルは即座に変わる —— 描画位置はそこから数分の1秒かけて古いセルから移動し、
    // どこまで来たか（t）はフレームをまたいで保持する必要があるので、他のすべてと
    // 同様 Board に住む。reverse は巻き戻しスライドの印: 仕組みは同じで、映像を逆
    // 再生しているだけ。
    pub type alias Slide = { fromCell = (Int32, Int32), pushing = Bool, reverse = Bool, t = Float64 }

    /// ロボットの頭上に浮かぶ巻き戻し時計。spin は巻き戻した手数を数え（1手ごとに
    /// 反時計回りに1回転、逆再生スライドと歩調を合わせる）、linger は巻き戻しが止
    /// まってからの経過時間 —— 時計はこの後まもなくフェードアウトする。
    pub type alias UndoFx = { spin = Float64, linger = Float64 }

    /// 巻き戻し時計が最後の巻き戻しからフェードアウトするまで生き延びる秒数。
    /// 経年変化（Sokoban）とフェード（View）の双方が使うので、ここに置く。
    pub def clockLinger(): Float64 = 0.4

    // ── Screen: フレームがどのページを見せているか ──
    // screen も他のすべてと同じ状態なので、純粋な tick がすべての遷移を所有する。
    // 各遷移は新しい履歴を始める —— 過去は「あるボードへの一回の挑戦」に属する。
    pub enum Screen with Eq {
        case Title
        case Playing
    }

    pub type alias Board = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32,
        facing = Dir4.Dir4,
        walkPhase = Float64,
        slide = Option[Slide],
        undoFx = Option[UndoFx],
        screen = Screen,
        level = Int32,
        clearElapsed = Float64
    }

    pub enum World {
        case World(Board)
    }

    // ── 出発点となるボードたち ──

    pub def initialWorld(): World = titleWorld()

    pub def levelCount(): Int32 = 2

    def levelText(n: Int32): String =
        if (n <= 1) Level.one() else Level.two()

    /// タイトルページも（レベル1の）ボードを一応持つ —— どの World も持っている
    /// —— が、フレームはそこでは決してそれを描かない。
    pub def titleWorld(): World = fromLevel(Screen.Title, 1)

    /// レベル n への新しい挑戦、プレイ開始可能な状態。
    pub def playingWorld(n: Int32): World = fromLevel(Screen.Playing, n)

    /// 同梱のレベル文字列はテストによってパース可能と保証されている。壊れた文字列
    /// は、起動を落とす代わりに何もない床へ縮退する。
    def fromLevel(screen: Screen, n: Int32): World =
        match Level.parse(levelText(n)) {
            case Result.Ok(p)  => toWorld(screen, n, p)
            case Result.Err(_) => toWorld(screen, n,
                                          { walls = Set.empty(), goals = Set.empty(),
                                            crates = Set.empty(), robot = (0, 0),
                                            cols = 1, rows = 1 })
        }

    def toWorld(screen: Screen, n: Int32, p: Level.Parsed): World =
        World.World({ walls = p#walls, goals = p#goals, crates = p#crates,
                      robot = p#robot, cols = p#cols, rows = p#rows,
                      facing = Dir4.Down, walkPhase = 0.0,
                      slide = None, undoFx = None,
                      screen = screen, level = n, clearElapsed = 0.0 })

    /// 勝利条件はどこにも保存されていない: Store から導出される。クレートが1つも
    /// ないボードはパズルにならないので、決してクリア扱いにはならない。
    pub def won(w: World): Bool =
        let World.World(b) = w;
        not Set.isEmpty(b#crates) and Set.isSubsetOf(b#crates, b#goals)

    // ── ルールブック: 押されたキー方向をボードに適用する ──

    /// 方向キーが押されていればホップを開始し、そうでなければ立ち止まったまま。
    pub def beginHop(input: Input, b: Board): Board =
        match pick(input#up, input#down, input#left, input#right) {
            case None    => b
            case Some(d) => move(d, b)
        }

    /// sokoban のルールブックすべて。行き先セルが判定を決める: 壁ならロボットは
    /// 止まる；クレートがあれば、その向こうのセルが空いている場合に限り一緒に動
    /// く；それ以外は何も動かず、ロボットは向きを変えるだけ。合法なホップはセル
    /// を即座に変え、絵がそれに追いつくためのスライドを開始する。
    def move(d: Dir4.Dir4, b: Board): Board =
        let target = Grid.neighbor(b#robot, d);
        let beyond = Grid.neighbor(target, d);
        let pushing = Set.memberOf(target, b#crates);
        let blocked = Set.memberOf(target, b#walls)
            or (pushing and (Set.memberOf(beyond, b#walls) or Set.memberOf(beyond, b#crates)));
        if (blocked)
            { facing = d | b }
        else
            { robot = target,
              crates = if (pushing) Set.insert(beyond, Set.remove(target, b#crates)) else b#crates,
              facing = d,
              slide = Some({ fromCell = b#robot, pushing = pushing, reverse = false, t = 0.0 })
              | b }

    /// 複数のキーが同時に押されている場合、勝つのは1つだけ: 上、下、左、右の順。
    def pick(u: Bool, d: Bool, l: Bool, r: Bool): Option[Dir4.Dir4] =
        if (u) Some(Dir4.Up)
        else if (d) Some(Dir4.Down)
        else if (l) Some(Dir4.Left)
        else if (r) Some(Dir4.Right)
        else None

    /// a から z へ向かう方向（グリッド上で1セル離れている前提）。軸が引き分けの
    /// 場合は水平方向の選択に倒し、最終的に Right になる —— どちらを向くかという
    /// ボード側のルールなので、共有の Dir4 ではなくここに置く。
    pub def directionTo(a: (Int32, Int32), z: (Int32, Int32)): Dir4.Dir4 =
        let (ax, ay) = a;
        let (zx, zy) = z;
        if (zy < ay) Dir4.Up
        else if (zy > ay) Dir4.Down
        else if (zx < ax) Dir4.Left
        else Dir4.Right
}
