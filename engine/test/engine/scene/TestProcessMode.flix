// Tests for ProcessMode.shouldProcess

/// shouldProcess の真理値表（4 ProcessMode × paused on/off）
///
///   |             | notPaused | paused |
///   | Pausable    | true      | false  |
///   | WhenPaused  | false     | true   |
///   | Always      | true      | true   |
///   | Disabled    | false     | false  |
@Test
def testShouldProcessTruthTable(): Unit \ Assert =
    let on = mode -> ProcessMode.shouldProcess(false, mode);
    let off = mode -> ProcessMode.shouldProcess(true, mode);
    Assert.assertEq(
        expected = (
            (true, false),
            (false, true),
            (true, true),
            (false, false)),
        ((on(ProcessMode.Pausable),   off(ProcessMode.Pausable)),
         (on(ProcessMode.WhenPaused), off(ProcessMode.WhenPaused)),
         (on(ProcessMode.Always),     off(ProcessMode.Always)),
         (on(ProcessMode.Disabled),   off(ProcessMode.Disabled))))
