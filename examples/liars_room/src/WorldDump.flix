// WorldDump — リモートデバッグの観測本文: view=status の 1 行サマリと view=full の部屋の全容。
// 純粋関数だけで書く（システムの外から任意の瞬間の Session で呼ばれる）。
// 発言は画面の会話ウィンドウと同じ文言（Stmt.speech → segText）で載せるので、
// 外部ツールは歩き回らなくても全証言を一度に読める。
mod WorldDump {

    /// view=status の 1 行サマリ（調査に効く値だけを短く）。
    pub def statusLine(s: LiarsRoom.Session): String =
        let Room.World.World(st) = s#world;
        let (px, py) = st#player;
        "phase=${st#phase} stage=${st#stage} liars=${st#liarCount}"
        + " player=(${px},${py}) memo=${markedCount(st)}/${List.length(st#npcs)}"
        + " memoOpen=${st#memoOpen} memoSel=${st#memoSel}"

    /// view=full の本文。部屋が小さいので rect は使わず常に全部を返す。
    pub def dump(_rect: Rect2.Rect2, s: LiarsRoom.Session): String =
        let Room.World.World(st) = s#world;
        let npcLines = st#npcs |> List.map(npc -> {
            let (cx, cy) = npc#cell;
            "npc id=${npc#id} name=${Palette.nameOf(npc#id)} cell=(${cx},${cy})"
            + " memo=${markOf(npc#id, st)}"
        });
        let sayLines = st#npcs |> List.map(npc -> {
            let segs = Stmt.speech(speaker = npc#id, suffix = LiarsRoom.suffixOf(npc#id),
                                   Room.statementsOf(npc#id, st));
            "say ${Palette.nameOf(npc#id)}: ${Stmt.segText(Palette.nameOf, segs)}"
        });
        String.intercalate("\n",
            statusLine(s) :: List.append(npcLines, sayLines))

    /// メモの見た目と同じ 3 値表示。
    def markOf(id: Int32, st: Room.State): String =
        match Map.get(id, st#memo) {
            case Some(Room.Mark.LiarMark)   => "うそ"
            case Some(Room.Mark.HonestMark) => "ほんと"
            case _                          => "?"
        }

    def markedCount(st: Room.State): Int32 =
        st#npcs |> List.filter(npc -> markOf(npc#id, st) != "?") |> List.length
}
