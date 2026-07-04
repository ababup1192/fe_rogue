// ReplayScript のテスト。多相 executeWith を玩具アルファベットで駆動して実行順を pin し、
// Key 固定の execute が同じ順序を生む（多相版への委譲）ことを固定する。
// applyKey / tick は副作用ゆえ、region 内の Ref に呼び出し列を記録して観察する。

mod TestReplayScript {

    /// executeWith は「先頭 tick → 各 Press で applyKey＋間フレーム → Wait で n フレーム」。
    /// 玩具では tick を 0、Press(k) の key を k(正) として記録する。betweenFrames=1、
    /// script = Press(1)・Wait(2)・Press(2) なら列は [0,1,0, 0,0, 2,0]。
    @Test
    def testExecuteWithToyAlphabet(): Unit \ Assert =
        let log = region rc {
            let logRef = Ref.fresh(rc, (Nil: List[Int32]));
            let push = v -> Ref.put(v :: Ref.get(logRef), logRef);
            let script =
                ReplayScript.PlayStep.Press(1) ::
                ReplayScript.PlayStep.Wait(2) ::
                ReplayScript.PlayStep.Press(2) :: Nil;
            ReplayScript.executeWith(1, script, k -> push(k), () -> push(0));
            List.reverse(Ref.get(logRef))
        };
        Assert.assertEq(expected = 0 :: 1 :: 0 :: 0 :: 0 :: 2 :: 0 :: Nil, log)

    // Key 固定の execute で記録した (tick=".", key=Key の文字列) の呼び出し列。
    def viaExecute(): List[String] = region rc {
        let logRef = Ref.fresh(rc, (Nil: List[String]));
        let push = s -> Ref.put(s :: Ref.get(logRef), logRef);
        let steps =
            ReplayScript.Step.KeyPress(ReplayScript.Key.Up) ::
            ReplayScript.Step.Wait(2) ::
            ReplayScript.Step.KeyPress(ReplayScript.Key.Down) :: Nil;
        ReplayScript.execute(1, steps, k -> push("${k}"), () -> push("."));
        List.reverse(Ref.get(logRef))
    }

    // 同じ内容を多相 executeWith（PlayStep[Key]）で組んだときの呼び出し列。
    def viaExecuteWith(): List[String] = region rc {
        let logRef = Ref.fresh(rc, (Nil: List[String]));
        let push = s -> Ref.put(s :: Ref.get(logRef), logRef);
        let steps =
            ReplayScript.PlayStep.Press(ReplayScript.Key.Up) ::
            ReplayScript.PlayStep.Wait(2) ::
            ReplayScript.PlayStep.Press(ReplayScript.Key.Down) :: Nil;
        ReplayScript.executeWith(1, steps, k -> push("${k}"), () -> push("."));
        List.reverse(Ref.get(logRef))
    }

    /// execute は executeWith への委譲ゆえ、同じ内容の Step 列と PlayStep[Key] 列は
    /// applyKey / tick を同じ順で呼ぶ。
    @Test
    def testExecuteMatchesExecuteWith(): Unit \ Assert =
        Assert.assertEq(expected = viaExecute(), viaExecuteWith())
}
