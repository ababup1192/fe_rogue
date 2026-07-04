// Worldline のメモリ実測ベンチ（教材・記事の素材）。
//
// 「World 相当のレコードを N 手 record した Worldline」の JVM ヒープを、GC を数回挟んだ
// used = totalMemory - freeMemory の前後差で近似測定する。共有テスト JVM 上での GC 前後差は
// 他テストのゴミ・JIT・確保粒度でノイズが乗るため、これは厳密な retained size ではなく桁の目安。
// アサートは決定論的な length のみに掛け、実測バイト数は println で情報として出す
// （数値ベースの assert はフレークするので張らない — 測定の限界は報告参照）。

mod TestWorldlineBench {

    import java.lang.Runtime
    import java.lang.System

    /// World を模したそこそこの大きさのレコード（複数フィールド）。
    type alias FauxWorld = { hp = Int32, x = Float64, y = Float64, score = Int32, tag = Int32 }

    def fauxWorld(i: Int32): FauxWorld =
        { hp = 100 - i, x = Int32.toFloat64(i), y = Int32.toFloat64(i) * 2.0, score = i, tag = i }

    /// GC を促してから used ヒープ（バイト）を読む。近似ゆえ 2 回 gc で安定を狙う。
    def usedHeap(): Int64 \ IO = {
        let rt = Runtime.getRuntime();
        System.gc(); System.gc();
        rt.totalMemory() - rt.freeMemory()
    }

    /// N 手 record した Worldline（cap = N で全保持）を作り、前後のヒープ差を測って報告する。
    /// length が cap+1 に達することだけを assert（決定論）。バイト数は参考出力。
    @Test
    def testMemoryFootprintOfDeepHistory(): Unit \ {Assert, IO} =
        let n = 20000;
        let before = usedHeap();
        let wl = List.range(0, n)
            |> List.foldLeft((acc, i) -> Worldline.record(fauxWorld(i), acc),
                             Worldline.make(fauxWorld(0), n));
        // 生きたまま測る: wl を after 測定後に触って GC 回収を防ぐ。
        let after = usedHeap();
        let usedBytes = after - before;
        let perRecord = usedBytes / Int64.max(1i64, Int32.toInt64(n));
        println("[Worldline bench] N=${n} recorded; heap delta ~= ${usedBytes} bytes (~${perRecord} B/record). "
            + "current.score=${Worldline.current(wl)#score}, length=${Worldline.length(wl)}");
        Assert.assertEq(expected = n + 1, Worldline.length(wl))
}
