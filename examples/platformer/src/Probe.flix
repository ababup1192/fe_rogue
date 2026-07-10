// Probe — テストの pin 値を実測するための一時ツール（テスト整備後に削除する）。

mod Probe {

    pub def main(): Unit \ IO =
        let full = Replay.timeline(Step.update, Trace.dt(),
            List.append(Trace.holdJump(30), Trace.flight(70)), Trace.flatWorld());
        println("full apex y = ${Trace.apexOf(full)}");
        full |> List.zipWithIndex |> List.forEach(pair -> {
            let (i, w) = pair;
            if (i >= 20 and i <= 28)
                println("frame ${i}: y=${Trace.posOf(w)#y} vy=${Trace.velOf(w)#y}")
            else ()
        });
        let tap = Replay.timeline(Step.update, Trace.dt(),
            List.append(Trace.holdJump(4), Trace.flight(90)), Trace.flatWorld());
        println("tap apex y = ${Trace.apexOf(tap)}");
        // 非対称: ジャンプ→頂点のフレーム数と、頂点→接地のフレーム数
        let indexed = List.zipWithIndex(full);
        let apexY = Trace.apexOf(full);
        let apexIndex = indexed
            |> List.findLeft(pair -> { let (_i, w) = pair; Trace.posOf(w)#y <= apexY + 0.0001 })
            |> Option.map(pair -> { let (i, _w) = pair; i })
            |> Option.getWithDefault(-1);
        let landIndex = indexed
            |> List.findLeft(pair -> { let (i, w) = pair; i > apexIndex and Trace.groundedOf(w) })
            |> Option.map(pair -> { let (i, _w) = pair; i })
            |> Option.getWithDefault(-1);
        println("apexIndex=${apexIndex} landIndex=${landIndex} fallFrames=${landIndex - apexIndex}");
        // 着地イベントつき落下（fallingWorld 40px）: 何フレーム目で land が出るか
        let fall = Replay.timeline(Step.update, Trace.dt(), Trace.flight(40), Trace.fallingWorld(40.0));
        List.zipWithIndex(fall) |> List.forEach(pair -> {
            let (i, w) = pair;
            if (List.memberOf("land", Trace.eventsOf(w)))
                println("fall(40) land at frame ${i} vy(before resolve unknown) pos.y=${Trace.posOf(w)#y}")
            else ()
        });
        println("fall(40) final grounded=${Trace.groundedOf(List.last(fall) |> Option.getWithDefault(Trace.fallingWorld(40.0)))}")
}
