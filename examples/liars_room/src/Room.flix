// Room — ゲーム 1 セッションぶんの全状態と、グリッド上の純粋なルール。
// 部屋（壁・NPC の立ち位置）とプレイヤー、パズル（発言と唯一解）、進行フェーズ、
// メモの書き込みまで、フレームが知るべきことはすべてこのレコードにある。
// dt による進行とフェーズ遷移は LiarsRoom に、描画は View にある。
mod Room {

    // ── Input: このフレームのキー入力を素のデータとして ──
    // 移動は押しっぱなし（held）、それ以外は押した瞬間（edge）を loop が判定して渡す。
    pub type alias Input = {
        up = Bool, down = Bool, left = Bool, right = Bool,
        upTap = Bool, downTap = Bool,
        talk = Bool, memo = Bool, hint = Bool, cancel = Bool,
        enter = Bool, esc = Bool, debug = Bool
    }

    /// 中立の入力（何も押されていない）。スライド中などキーを黙らせたいフレームで使う。
    pub def noKeys(): Input =
        { up = false, down = false, left = false, right = false,
          upTap = false, downTap = false,
          talk = false, memo = false, hint = false, cancel = false,
          enter = false, esc = false, debug = false }

    // ── 進行フェーズ ──
    pub enum Phase with Eq, ToString {
        /// タイトル画面。
        case Title
        /// 部屋を歩き回っている（メモはこの間だけ開ける）。
        case Exploring
        /// NPC の発言ウィンドウを表示中。
        case Talking
        /// 「この人を信じる？」の確認メニュー。
        case Confirming
        /// 不正解の演出中（Enter で同じステージをやり直す）。
        case Wrong
        /// 正解（Enter で次のステージへ）。
        case Cleared
        /// 全ステージクリア（Enter でタイトルへ）。
        case Ending
    }

    /// メモの 3 値マーク。プレイヤーが自分で付ける推理の覚え書きで、正誤判定には使わない。
    pub enum Mark with Eq, ToString {
        case Unknown
        case LiarMark
        case HonestMark
    }

    /// マークの巡回（メモ画面で決定キーを押すたびに 1 つ進む）。
    pub def cycleMark(mark: Mark): Mark = match mark {
        case Mark.Unknown    => Mark.LiarMark
        case Mark.LiarMark   => Mark.HonestMark
        case Mark.HonestMark => Mark.Unknown
    }

    /// NPC 1 人ぶん。色と呼び名は id から Palette が引くので持たない。
    pub type alias Npc = { id = Int32, cell = (Int32, Int32), facing = Dir4.Dir4 }

    /// プレイヤーの絵の移動量（1 マスぶんのスライド。sokoban と同じ仕組み）。
    pub type alias Slide = { fromCell = (Int32, Int32), t = Float64 }

    /// フィールドの並びは、部屋とプレイヤー / パズル（(stage, puzzleSeed) から決定論的に
    /// 再構成できる。puzzleSeed はやり直しで同じ問題を出すために覚える）/ 進行 /
    /// メモとヒント（やり直しでは残り、次のステージで消える）/ 演出時計と entropy
    /// （entropy = 毎フレーム進む通し番号。次の出題をプールから選ぶくじ引きに使う）、の順。
    pub type alias State = {
        walls = Set[(Int32, Int32)],
        cols = Int32,
        rows = Int32,
        player = (Int32, Int32),
        facing = Dir4.Dir4,
        walkPhase = Float64,
        slide = Option[Slide],
        stage = Int32,
        puzzleSeed = Int64,
        npcs = List[Npc],
        stmts = List[(Int32, Stmt.Stmt)],
        liarCount = Int32,
        honestSet = Set[Int32],
        phase = Phase,
        talkingTo = Option[Int32],
        dialog = UiDialog.Dialog,
        confirmSel = Int32,
        memo = Map[Int32, Mark],
        memoOpen = Bool,
        memoSel = Int32,
        hintUsed = Bool,
        debugHold = Float64,
        idlePhase = Float64,
        shakeT = Float64,
        resultElapsed = Float64,
        entropy = Int32
    }

    pub enum World {
        case World(State)
    }

    // ── 出発点となる World たち ──

    pub def initialWorld(): World = titleWorld()

    /// タイトル画面。部屋は（ステージ 1 の）ものを一応持つが、描かれない。
    pub def titleWorld(): World =
        let World.World(state) = stageWorld(1, Map.empty(), Stage.pickSeed(1, 0));
        World.World({ phase = Phase.Title | state })

    /// ステージ n への挑戦。memo は引き継ぎたい書き込み（やり直し時）か空（新ステージ）、
    /// seed は出題プールから選んだシード（やり直しなら前回と同じものを渡す）。
    pub def stageWorld(n: Int32, memo: Map[Int32, Mark], seed: Int64): World =
        let difficulty = Stage.difficultyOf(n);
        let generated = Stage.generatedWith(n, seed);
        let parsed = RoomMap.parse(RoomMap.roomFor(difficulty#npcCount));
        let npcs = List.range(0, difficulty#npcCount) |> List.map(id ->
            match Map.get(id, parsed#npcCells) {
                case Some(cell) => { id = id, cell = cell, facing = Dir4.Down }
                case None       => bug!("Room.stageWorld: 部屋テンプレートに NPC ${id} の立ち位置が無い")
            });
        let honest = List.range(0, difficulty#npcCount)
            |> List.filter(id -> not Set.memberOf(id, generated#liars))
            |> List.toSet;
        World.World({
            walls = parsed#walls, cols = parsed#cols, rows = parsed#rows,
            player = parsed#player, facing = Dir4.Up, walkPhase = 0.0, slide = None,
            stage = n, puzzleSeed = seed, npcs = npcs, stmts = generated#stmts,
            liarCount = difficulty#liarCount, honestSet = honest,
            phase = Phase.Exploring, talkingTo = None,
            dialog = UiDialog.closed(), confirmSel = 1,
            memo = memo, memoOpen = false, memoSel = 0, hintUsed = false, debugHold = 0.0,
            idlePhase = 0.0, shakeT = 0.0, resultElapsed = 0.0, entropy = 0
        })

    // ── ヒント ──

    /// 嘘つきの id 列（唯一解の補集合、小さい順）。
    pub def liarsOf(state: State): List[Int32] =
        state#npcs
            |> List.map(npc -> npc#id)
            |> List.filter(id -> not Set.memberOf(id, state#honestSet))

    /// デバッグ用: 全員のメモを正解（嘘つき=うそ・正直者=ほんと）で埋める。
    pub def debugFillMemo(state: State): State =
        let filled = state#npcs |> List.foldLeft((acc, npc) ->
            Map.insert(npc#id,
                if (Set.memberOf(npc#id, state#honestSet)) Mark.HonestMark else Mark.LiarMark,
                acc), state#memo);
        { memo = filled | state }

    /// ヒント: 嘘つきを 1 人確定してメモに「うそ」を書き込み、メモを開いてそこへカーソルを
    /// 当てる。1 ステージに 1 回だけ（使用済みなら何もしない）。
    pub def applyHint(state: State): State =
        if (state#hintUsed)
            state
        else
            match List.head(liarsOf(state)) {
                case None     => state
                case Some(id) =>
                    { memo = Map.insert(id, Mark.LiarMark, state#memo),
                      hintUsed = true, memoOpen = true, memoSel = id | state }
            }

    // ── グリッドのルール ──

    /// NPC が立っているセルの集合（通行不可）。
    pub def npcCells(state: State): Set[(Int32, Int32)] =
        state#npcs |> List.map(npc -> npc#cell) |> List.toSet

    /// 方向キーが押されていれば 1 マスのホップを開始し、そうでなければ立ち止まったまま。
    pub def beginHop(input: Input, state: State): State =
        match pickDir(input#up, input#down, input#left, input#right) {
            case None      => state
            case Some(dir) => move(dir, state)
        }

    /// 行き先が壁か NPC なら向きだけ変える。空いていればセルを即座に変え、
    /// 絵が追いつくためのスライドを開始する。
    def move(dir: Dir4.Dir4, state: State): State =
        let target = Grid.neighbor(state#player, dir);
        let blocked = Set.memberOf(target, state#walls)
            or Set.memberOf(target, npcCells(state));
        if (blocked)
            { facing = dir | state }
        else
            { player = target, facing = dir,
              slide = Some({ fromCell = state#player, t = 0.0 }) | state }

    /// 複数キー同時押しの優先順: 上、下、左、右。
    def pickDir(u: Bool, d: Bool, l: Bool, r: Bool): Option[Dir4.Dir4] =
        if (u) Some(Dir4.Up)
        else if (d) Some(Dir4.Down)
        else if (l) Some(Dir4.Left)
        else if (r) Some(Dir4.Right)
        else None

    /// プレイヤーの正面のセルに立っている NPC（居なければ None）。話しかけの対象。
    pub def facingNpc(state: State): Option[Npc] =
        let front = Grid.neighbor(state#player, state#facing);
        state#npcs |> List.findLeft(npc -> npc#cell == front)

    /// a から z へ向かう方向（話しかけられた NPC がプレイヤーの方を向くのに使う）。
    pub def directionTo(a: (Int32, Int32), z: (Int32, Int32)): Dir4.Dir4 =
        let (ax, ay) = a;
        let (zx, zy) = z;
        if (zy < ay) Dir4.Up
        else if (zy > ay) Dir4.Down
        else if (zx < ax) Dir4.Left
        else Dir4.Right

    /// id の NPC をプレイヤーの方へ向かせる。
    pub def turnNpcToPlayer(id: Int32, state: State): State =
        { npcs = state#npcs |> List.map(npc ->
            if (npc#id == id) { facing = directionTo(npc#cell, state#player) | npc } else npc)
          | state }

    /// id の NPC の発言（表示順）。基本は 1 本、冗長発言が割り当たった NPC は複数しゃべる。
    pub def statementsOf(id: Int32, state: State): List[Stmt.Stmt] =
        state#stmts |> List.filterMap(said -> {
            let (speaker, stmt) = said;
            if (speaker == id) Some(stmt) else None
        })
}
