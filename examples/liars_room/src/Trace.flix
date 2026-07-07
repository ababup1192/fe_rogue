// Trace — テストとギャラリーが共有する入力シナリオの部品。
// 1 フレームぶんのキー（エッジは 1 フレームだけ true）と、tick を回す小さなヘルパー。
mod Trace {

    /// テスト用の 1 フレーム: 位相が正確に割り切れる dt（1 マスのスライドは 8 フレーム）。
    pub def dt(): Float64 = 1.0 / 64.0

    // ── 1 フレームぶんのキー ──

    pub def talkTap(): Room.Input = { talk = true | Room.noKeys() }
    pub def memoTap(): Room.Input = { memo = true | Room.noKeys() }
    pub def cancelTap(): Room.Input = { cancel = true | Room.noKeys() }
    pub def enterTap(): Room.Input = { enter = true | Room.noKeys() }
    pub def upOnce(): Room.Input = { up = true, upTap = true | Room.noKeys() }
    pub def downOnce(): Room.Input = { down = true, downTap = true | Room.noKeys() }
    pub def leftHold(): Room.Input = { left = true | Room.noKeys() }
    pub def rightHold(): Room.Input = { right = true | Room.noKeys() }

    // ── tick を回す ──

    pub def step(input: Room.Input, w: Room.World): Room.World =
        LiarsRoom.tick(input, dt(), w)

    /// 同じ入力で n フレーム回す（スライドの着地待ちなどに使う）。
    pub def stepN(n: Int32, input: Room.Input, w: Room.World): Room.World =
        List.range(0, n) |> List.foldLeft((acc, _) -> LiarsRoom.tick(input, dt(), acc), w)

    // ── 体勢を作る ──

    /// プレイヤーを NPC id の 1 マス下に置き、上を向かせる（話しかけられる体勢）。
    pub def facingNpcBelow(id: Int32, w: Room.World): Room.World =
        let Room.World.World(s) = w;
        let cell = s#npcs
            |> List.findLeft(npc -> npc#id == id)
            |> Option.map(npc -> npc#cell);
        match cell {
            case Some((x, y)) => Room.World.World({ player = (x, y + 1), facing = Dir4.Up | s })
            case None         => bug!("Trace.facingNpcBelow: NPC ${id} が居ない")
        }

    /// プレイヤーを任意のセルへ置いて向きを変える（壁ぎわの移動テスト用）。
    pub def placePlayer(cell: (Int32, Int32), facing: Dir4.Dir4, w: Room.World): Room.World =
        let Room.World.World(s) = w;
        Room.World.World({ player = cell, facing = facing | s })
}
