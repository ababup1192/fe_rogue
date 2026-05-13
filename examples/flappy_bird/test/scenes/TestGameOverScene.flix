// Tests for GameOverScene — メダル判定と GameOver UI 構築
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// メダル判定
// ========================================================================

/// score 別メダル境界（< 10: なし、10〜19: bronze、20〜29: silver、30〜49: gold、50+: platinum）
@Test
def testMedalThresholds(): Unit \ Assert =
    Assert.assertEq(
        expected = (
            (None: Option[String]),         //  0:  なし
            (None: Option[String]),         //  5:  なし
            Some("medal_bronze"),           // 10:  bronze 境界
            Some("medal_bronze"),           // 15:  bronze 範囲内
            Some("medal_silver"),           // 20:  silver 境界
            Some("medal_gold"),             // 30:  gold 境界
            Some("medal_platinum")),        // 50:  platinum 境界
        (GameOverScene.getMedalTexture(0),
         GameOverScene.getMedalTexture(5),
         GameOverScene.getMedalTexture(10),
         GameOverScene.getMedalTexture(15),
         GameOverScene.getMedalTexture(20),
         GameOverScene.getMedalTexture(30),
         GameOverScene.getMedalTexture(50)))

// ========================================================================
// UI ノード構築
// ========================================================================

/// メダルノードは「今回のスコア」「ベストスコア」のいずれかが 10 以上の時だけ追加される
///   - score=5,  bestScore=0  → なし
///   - score=15, bestScore=15 → あり（今回スコア）
///   - score=3,  bestScore=15 → あり（ベストスコア由来、メダル永続化）
@Test
def testGameOverUIMedalPresence(): Unit \ {Assert, Fs.FileRead} =
    let medalPath = "gameover" :: "medal" :: Nil;
    let buildWith = (score, best) ->
        testScene()
            |> ScoreScene.setScore(score)
            |> ScoreScene.setBestScore(best)
            |> GameOverScene.addGameOverUI(testFontAtlas());
    let hasMedal = scene -> not Option.isEmpty(Scene.getEngineNode(medalPath, scene));
    Assert.assertEq(
        expected = (false, true, true),
        (hasMedal(buildWith(5, 0)),
         hasMedal(buildWith(15, 15)),
         hasMedal(buildWith(3, 15))))

/// addGameOverUI 後に HUD スコアラベルが非表示になる
@Test
def testGameOverHidesHudScore(): Unit \ {Assert, Fs.FileRead} =
    let scene = GameOverScene.addGameOverUI(testFontAtlas(), testScene());
    match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) =>
            Assert.assertFalse(CanvasItem.isVisible(label))
        case _ => bug!("score_label not found")
    }

// ========================================================================
// アニメーション進行: updateAnimation / isAnimationFinished
// ========================================================================

/// アニメは elapsed が animDuration(0.8 秒) に達するまで未完了。
/// 0.5 秒経過時点では未完了、0.9 秒で完了する。
/// updateAnimation を経由しない初期状態（elapsed=0）も未完了。
@Test
def testGameOverAnimationFinishedGate(): Unit \ {Assert, Fs.FileRead} =
    let initial = GameOverScene.addGameOverUI(testFontAtlas(), testScene());
    let half = GameOverScene.updateAnimation(0.5, initial);
    let past = GameOverScene.updateAnimation(0.9, initial);
    Assert.assertEq(
        expected = (false, false, true),
        (GameOverScene.isAnimationFinished(initial),
         GameOverScene.isAnimationFinished(half),
         GameOverScene.isAnimationFinished(past)))

/// updateAnimation は閾値（panelShowTime=0.3 秒）を跨いだ瞬間に
/// 隠れていた score_panel を表示する
///   0.2 秒（< 0.3）: 非表示のまま
///   0.4 秒（>= 0.3）: 表示される
@Test
def testGameOverAnimationShowsPanelAfterThreshold(): Unit \ {Assert, Fs.FileRead} =
    let panelPath = "gameover" :: "score_panel" :: Nil;
    let initial = GameOverScene.addGameOverUI(testFontAtlas(), testScene());
    let beforeThreshold = GameOverScene.updateAnimation(0.2, initial);
    let afterThreshold = GameOverScene.updateAnimation(0.4, initial);
    let panelVisible = scene -> match Scene.getEngineNode(panelPath, scene) {
        case Some(EngineNode.Sprite2DWithState(sprite, _)) => CanvasItem.isVisible(sprite)
        case _ => bug!("score_panel not found")
    };
    Assert.assertEq(
        expected = (false, false, true),
        (panelVisible(initial),
         panelVisible(beforeThreshold),
         panelVisible(afterThreshold)))
