/// ItemPickupPopupUi の純粋な状態更新 `step` を検証する。
///
/// `step` は (1) 取得音の予約を1回だけ消費する、(2) フェードの段階を時間で進めて
/// 表示の濃さ `ratio` を返す、を担う。ポップアップの alpha・文字色・可視への反映は scene 副作用なので、
/// ここでは扱わず実機確認に委ねる。
///
/// 段階の長さ: 浮かび上がり 300ms / 表示保持 1100ms / 消える 400ms。
/// 「段階が終わる」系のテストは、どの段階の長さ(最大 1100ms)も確実に超える 2 秒(2000ms)を
/// 1 回進めて、次の段階へ移ることを確認する。
mod TestItemPickupPopupUi {

    use ItemPickupPopupState.Stage

    // ════════════════════════════════════════════════════════
    // 取得音: 予約を最初の1フレームだけ消費する
    // ════════════════════════════════════════════════════════

    /// 音の予約あり(soundPending=true)の最初の step で playSound=true になり、
    /// 持ち越す状態では予約が消える(soundPending=false)。
    @Test
    def testSoundPlaysOnFirstFrame(): Unit \ Assert =
        let result = ItemPickupPopupUi.step(
            {stage = Stage.FadeIn, elapsed = Duration.zero(), soundPending = true, text = ""},
            Duration.millis(50));
        Assert.assertEq(expected = (true, false),
                        (result#playSound, result#data#soundPending))

    /// 予約なし(soundPending=false)のフレームでは音を鳴らさない。
    @Test
    def testSoundSilentWhenNotPending(): Unit \ Assert =
        let result = ItemPickupPopupUi.step(
            {stage = Stage.FadeIn, elapsed = Duration.millis(100), soundPending = false, text = ""},
            Duration.millis(50));
        Assert.assertEq(expected = false, result#playSound)

    // ════════════════════════════════════════════════════════
    // 段階遷移: 浮かび上がり → 保持 → 消える → 非表示
    // ════════════════════════════════════════════════════════

    /// 浮かび上がり(300ms)が終わると保持段階へ移り、表示は最大の濃さ(ratio=1)になる。
    @Test
    def testFadeInEndsAtFullOpacity(): Unit \ Assert =
        let result = ItemPickupPopupUi.step(
            {stage = Stage.FadeIn, elapsed = Duration.zero(), soundPending = false, text = ""},
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Hold, 1.0),
                        (result#data#stage, result#ratio))

    /// 保持(1100ms)が終わると消える段階へ移る。消え始めなのでまだ最大の濃さ(ratio=1)。
    @Test
    def testHoldEndsStartsFadeOut(): Unit \ Assert =
        let result = ItemPickupPopupUi.step(
            {stage = Stage.Hold, elapsed = Duration.zero(), soundPending = false, text = ""},
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.FadeOut, 1.0),
                        (result#data#stage, result#ratio))

    /// 消える(400ms)が終わると非表示(Idle)になり、表示の濃さは 0 になる。
    @Test
    def testFadeOutEndsHidden(): Unit \ Assert =
        let result = ItemPickupPopupUi.step(
            {stage = Stage.FadeOut, elapsed = Duration.zero(), soundPending = false, text = ""},
            Duration.millis(2000));
        Assert.assertEq(expected = (Stage.Idle, 0.0),
                        (result#data#stage, result#ratio))

    // ════════════════════════════════════════════════════════
    // reserveGetItemSound: 取得音だけ予約し、中央ポップアップは出さない
    // ════════════════════════════════════════════════════════

    /// アイテム取得時に呼ぶ `reserveGetItemSound` は、ポップアップ(stage)を動かさず
    /// `soundPending` だけ true にする。これにより次フレームの step が get_item を 1 回鳴らし
    /// （`testSoundPlaysOnFirstFrame` 参照）、ポップアップは出ない(stage=Idle 維持)。
    /// 状態は resource（`ItemPickupPopupState.State`）が持つ。withState で包み、reserveGetItemSound の
    /// 後に State を読んで soundPending=true・stage=Idle 維持を確認する。
    @Test
    def testReserveGetItemSoundReservesWithoutPopup(): Unit \ Assert =
        region rc {
            let observed = ItemPickupPopupState.withState(rc, () -> {
                ItemPickupPopupUi.reserveGetItemSound();
                let d = ItemPickupPopupState.State.get();
                (d#soundPending, d#stage)
            });
            Assert.assertEq(expected = (true, Stage.Idle), observed)
        }
}
