// Probe — 崖まわり choreography の実測（テスト整備後に削除する）。

mod Probe {

    def show(label: String, worlds: List[Field.World]): Unit \ IO =
        let final = List.last(worlds) |> Option.getWithDefault(Field.initialWorld());
        let died = worlds |> List.exists(w -> List.memberOf("death", Trace.eventsOf(w)));
        println("${label}: pos=(${Trace.posOf(final)#x},${Trace.posOf(final)#y})"
            + " grd=${Trace.groundedOf(final)} died=${died} deaths=${Trace.deathsOf(final)}")

    pub def main(): Unit \ IO =
        // (a) 狭い穴: 浮き床 A に乗って渡る → segB へ降りる
        let narrowWorld = { player = Trace.restingPlayer(60.0) | Field.initialWorld() };
        let narrow = Replay.timeline(Step.update, Trace.dt(),
            List.append(Trace.rightJump(12), Trace.holdRight(60)), narrowWorld);
        show("narrow(viaA)", narrow);
        let narrowStop = Replay.timeline(Step.update, Trace.dt(),
            List.flatten(Trace.rightJump(12) :: Trace.holdRight(45) :: Trace.flight(10) :: Nil), narrowWorld);
        show("narrow(stop)", narrowStop);
        // (b) 広い穴: segB を dash 助走 → 低ホップ
        let wideWorld = { player = Trace.restingPlayer(155.0) | Field.initialWorld() };
        let hop5 = List.flatten(Trace.holdRightDash(10) :: Trace.rightDashJump(5) :: Trace.holdRightDash(40) :: Nil);
        show("wide(dash hop5)", Replay.timeline(Step.update, Trace.dt(), hop5, wideWorld));
        let hop4 = List.flatten(Trace.holdRightDash(10) :: Trace.rightDashJump(4) :: Trace.holdRightDash(40) :: Nil);
        show("wide(dash hop4)", Replay.timeline(Step.update, Trace.dt(), hop4, wideWorld));
        let hop6 = List.flatten(Trace.holdRightDash(10) :: Trace.rightDashJump(6) :: Trace.holdRightDash(40) :: Nil);
        show("wide(dash hop6)", Replay.timeline(Step.update, Trace.dt(), hop6, wideWorld));
        // (c) 素の走りで同じことをすると落ちる
        let walkHop = List.flatten(Trace.holdRight(10) :: Trace.rightJump(5) :: Trace.holdRight(60) :: Nil);
        show("wide(walk hop5)", Replay.timeline(Step.update, Trace.dt(), walkHop, wideWorld));
        // (d) segB 右端から歩いて落ちる
        let fall = Replay.timeline(Step.update, Trace.dt(),
            List.append(Trace.holdRight(10), Trace.flight(40)),
            { player = Trace.restingPlayer(190.0) | Field.initialWorld() });
        show("gap2 walk-off", fall)
}
