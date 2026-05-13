// Tests for ScoreScene — スコア管理・コイン採点・ベストスコア確定
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// スコア更新と Label2D テキストの同期
// ========================================================================

/// incrementScore は NodeTag.ScoreLabel と Label2D テキストの両方を同時更新する
///   初期 score=0 → "0" / increment 後 score=1 → "1"
@Test
def testScoreScoreLabelSyncedWithText(): Unit \ {Assert, Fs.FileRead} =
    let textOf = scene -> match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) => Label2D.getText(label)
        case _ => bug!("score_label not found")
    };
    let initial = testScene();
    let incremented = ScoreScene.incrementScore(initial);
    Assert.assertEq(
        expected = ((0, "0"), (1, "1")),
        ((ScoreScene.getScore(initial),     textOf(initial)),
         (ScoreScene.getScore(incremented), textOf(incremented))))

// ========================================================================
// onBirdPassedCoin — 二重採点防止
// ========================================================================

/// onBirdPassedCoin はスコアを +1 加算し、対象のコイン NodeTag を NoTag に変える。
/// 二重採点防止の仕組みは Game.flix の AreaHandler 側のパターンマッチで
/// `(BirdArea, Coin)` のみ採点処理にディスパッチする構造。
/// 一度通過した coin は NoTag に変わるので 2 回目以降は採点ハンドラに来ない。
@Test
def testScoreOnBirdPassedCoinIncrementsAndTagsCoin(): Unit \ {Assert, Fs.FileRead} =
    let coinPath = PipeScene.coinPath(PipeScene.pairName(0));
    let initial = testScene();
    let afterPass = withMockAudio(() ->
        ScoreScene.onBirdPassedCoin(coinPath = coinPath, initial));
    let coinTagBefore = match Scene.getState(coinPath, initial) {
        case Some(NodeTag.Coin) => "Coin"
        case _ => "other"
    };
    let coinTagAfter = match Scene.getState(coinPath, afterPass) {
        case Some(NodeTag.NoTag) => "NoTag"
        case _ => "other"
    };
    Assert.assertEq(
        expected = ((0, "Coin"), (1, "NoTag")),
        ((ScoreScene.getScore(initial),   coinTagBefore),
         (ScoreScene.getScore(afterPass), coinTagAfter)))

// ========================================================================
// finalizeScore — ベストスコア確定
// ========================================================================

/// finalizeScore は max(score, bestScore) で best を更新する
///   - score=20, best=10 → best=20（更新）
///   - score=5,  best=15 → best=15（据え置き）
@Test
def testScoreFinalizeMaxOfScoreAndBest(): Unit \ {Assert, Fs.FileRead} =
    let updated = testScene()
        |> ScoreScene.setScore(20)
        |> ScoreScene.setBestScore(10)
        |> ScoreScene.finalizeScore;
    let kept = testScene()
        |> ScoreScene.setScore(5)
        |> ScoreScene.setBestScore(15)
        |> ScoreScene.finalizeScore;
    Assert.assertEq(
        expected = (20, 15),
        (ScoreScene.getBestScore(updated), ScoreScene.getBestScore(kept)))
