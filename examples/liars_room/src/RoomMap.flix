// RoomMap — 部屋のテキストアート記法とパーサ。
//   #  壁      @  プレイヤーの初期位置      0..6  NPC の立ち位置（数字 = NPC id）
//   （空白）床
// 部屋は NPC 数に応じて小・中・大の 3 テンプレートを使い回す。パズル（発言）は Gen が
// 作るので、部屋そのものは手書きの固定データでよい。
mod RoomMap {

    /// パース結果。npcCells はテンプレートに描かれた全立ち位置（使うのは先頭 npcCount 個）。
    pub type alias Parsed = {
        walls = Set[(Int32, Int32)],
        npcCells = Map[Int32, (Int32, Int32)],
        player = (Int32, Int32),
        cols = Int32,
        rows = Int32
    }

    /// NPC 数に合う部屋テンプレート。
    pub def roomFor(npcCount: Int32): String =
        if (npcCount <= 4) small()
        else if (npcCount <= 6) medium()
        else large()

    /// 小部屋（NPC 3〜4 人）。
    def small(): String =
        String.unlines(
            "#########" ::
            "#0     1#" ::
            "#       #" ::
            "#   @   #" ::
            "#       #" ::
            "#2     3#" ::
            "#########" :: Nil)

    /// 中部屋（NPC 5〜6 人）。
    def medium(): String =
        String.unlines(
            "###########" ::
            "#0   1   2#" ::
            "#         #" ::
            "#    @    #" ::
            "#         #" ::
            "#3   4   5#" ::
            "###########" :: Nil)

    /// 大部屋（NPC 7 人）。
    def large(): String =
        String.unlines(
            "#############" ::
            "#0    1    2#" ::
            "#           #" ::
            "#  3     4  #" ::
            "#     @     #" ::
            "#           #" ::
            "#  5     6  #" ::
            "#############" :: Nil)

    /// テキストアートを Parsed へ。テンプレートは同梱の固定データなので、
    /// プレイヤー位置が無いなどの壊れ方は bug! で大声で落とす。
    pub def parse(text: String): Parsed =
        let lines = String.lines(text);
        let cols = lines |> List.map(String.length) |> List.foldLeft(Int32.max, 0);
        let draft = lines |> List.zipWithIndex |> List.foldLeft((acc, row) -> {
            let (y, line) = row;
            String.toList(line) |> List.zipWithIndex |> List.foldLeft((acc2, cellChar) -> {
                let (x, c) = cellChar;
                addCell((x, y), c, acc2)
            }, acc)
        }, emptyDraft());
        match draft#player {
            case Some(player) =>
                { walls = draft#walls, npcCells = draft#npcCells, player = player,
                  cols = cols, rows = List.length(lines) }
            case None => bug!("RoomMap.parse: プレイヤー位置（@）が無い")
        }

    /// パース途中の置き場（player が見つかるまで Option で持つ）。
    type alias Draft = {
        walls = Set[(Int32, Int32)],
        npcCells = Map[Int32, (Int32, Int32)],
        player = Option[(Int32, Int32)]
    }

    def emptyDraft(): Draft =
        { walls = Set.empty(), npcCells = Map.empty(), player = None }

    /// 1 文字ぶんの読み取り。数字は NPC id、それ以外の未知の文字は床として無視する。
    def addCell(cell: (Int32, Int32), c: Char, draft: Draft): Draft =
        match c {
            case '#' => { walls = Set.insert(cell, draft#walls) | draft }
            case '@' => { player = Some(cell) | draft }
            case '0' => putNpc(0, cell, draft)
            case '1' => putNpc(1, cell, draft)
            case '2' => putNpc(2, cell, draft)
            case '3' => putNpc(3, cell, draft)
            case '4' => putNpc(4, cell, draft)
            case '5' => putNpc(5, cell, draft)
            case '6' => putNpc(6, cell, draft)
            case _   => draft
        }

    def putNpc(id: Int32, cell: (Int32, Int32), draft: Draft): Draft =
        { npcCells = Map.insert(id, cell, draft#npcCells) | draft }
}
