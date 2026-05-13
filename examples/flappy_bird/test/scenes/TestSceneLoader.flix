// Tests for SceneLoader — JSON ファイルからシーンを読み込んで構築する基盤の検証
//
// MenuScene.scene.json と GroundScene.scene.json を直接読み込み、
// 期待されるノード構造・パラメータが正しく EngineNode へ変換されることを確認する

// ========================================================================
// 共通ヘルパー
// ========================================================================

/// MenuScene.scene.json をテスト用に読み込んだ scene を取得する
def loadedMenuScene(): Scene[NodeTag] \ Fs.FileRead =
    SceneLoader.loadScene("src/scenes/MenuScene.scene.json", Scene.empty())

/// GroundScene.scene.json をテスト用に読み込んだ scene を取得する
def loadedGroundScene(): Scene[NodeTag] \ Fs.FileRead =
    SceneLoader.loadScene("src/scenes/GroundScene.scene.json", Scene.empty())

/// ScoreScene.scene.json をテスト用に読み込んだ scene を取得する（loadSceneWithFont 経由）
def loadedScoreScene(): Scene[NodeTag] \ Fs.FileRead =
    SceneLoader.loadSceneWithFont("src/scenes/ScoreScene.scene.json", testFontAtlas(), Scene.empty())

// ========================================================================
// 構造テスト
// ========================================================================

/// MenuScene.scene.json は menu CanvasLayer をルートに持ち、
/// title_logo / instructions_img / play_button の 3 つの子を持つ
/// （ノード総数 = 4）
@Test
def testMenuSceneJsonStructure(): Unit \ {Assert, Fs.FileRead} =
    let scene = loadedMenuScene();
    Assert.assertEq(
        expected = (4, true, true, true, true),
        (Scene.nodeCount(scene),
         not Option.isEmpty(Scene.getEngineNode("menu" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("menu" :: "title_logo" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("menu" :: "instructions_img" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("menu" :: "play_button" :: Nil, scene))))

// ========================================================================
// CanvasLayer ビルダー
// ========================================================================

/// menu ルートは CanvasLayer で drawLayer = 2
@Test
def testMenuLayerIsCanvasLayer2(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("menu" :: Nil, loadedMenuScene()) {
        case Some(EngineNode.CanvasLayerWithState(canvasLayer, NodeTag.NoTag)) =>
            Assert.assertEq(expected = 2, CanvasLayer.getDrawLayer(canvasLayer))
        case _ => bug!("menu should be CanvasLayer with NoTag")
    }

// ========================================================================
// Sprite2D ビルダー
// ========================================================================

/// title_logo は Sprite2D で texture / pos / scale が JSON 通りに設定される
///                                            ┌─ texture
///                                            │             ┌─ pos
///                                            │             │             ┌─ scale
@Test
def testTitleLogoSprite2D(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode(MenuScene.titleLogoPath(), loadedMenuScene()) {
        case Some(EngineNode.Sprite2DWithState(Sprite2D.Sprite2D(r), NodeTag.NoTag)) =>
            Assert.assertEq(
                expected = ("label_flappy_bird", (144.0, 140.0), (2.0, 2.0)),
                (r#texture, (r#position#x, r#position#y), (r#scale#x, r#scale#y)))
        case _ => bug!("title_logo should be Sprite2D with NoTag")
    }

/// instructions_img は Sprite2D で texture / pos が JSON 通りに設定される
@Test
def testInstructionsSprite2D(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode(MenuScene.instructionsPath(), loadedMenuScene()) {
        case Some(EngineNode.Sprite2DWithState(Sprite2D.Sprite2D(r), NodeTag.NoTag)) =>
            Assert.assertEq(
                expected = ("instructions", (144.0, 340.0)),
                (r#texture, (r#position#x, r#position#y)))
        case _ => bug!("instructions_img should be Sprite2D with NoTag")
    }

// ========================================================================
// TextureButton ビルダー
// ========================================================================

/// play_button は TextureButton で textureNormal / texturePressed /
/// pos / size / centered=true が JSON 通りに設定される
@Test
def testPlayButtonTextureButton(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode(MenuScene.playButtonPath(), loadedMenuScene()) {
        case Some(EngineNode.TextureButtonWithState(button, NodeTag.NoTag)) =>
            let TextureButton.TextureButton(r) = button;
            let pressedTexture = match r#texturePressed {
                case Some(t) => t
                case None    => bug!("play_button should have texturePressed")
            };
            let pos = Node2D.getPosition(button);
            let size = TextureButton.getSize(button);
            Assert.assertEq(
                expected = ("button_play_normal", "button_play_pressed",
                            (144.0, 440.0), (104.0, 58.0), true),
                (r#textureNormal, pressedTexture,
                 (pos#x, pos#y), (size#x, size#y),
                 TextureButton.isCentered(button)))
        case _ => bug!("play_button should be TextureButton with NoTag")
    }

// ========================================================================
// トップレベル配列 + StaticBody2D ビルダー（GroundScene.scene.json）
// ========================================================================

/// GroundScene.scene.json はトップレベル配列で 2 つのルートノード ground_0/ground_1 を
/// 持ち、それぞれに sprite 子ノードが付く（合計 4 ノード）
@Test
def testGroundSceneJsonArrayRoots(): Unit \ {Assert, Fs.FileRead} =
    let scene = loadedGroundScene();
    Assert.assertEq(
        expected = (4, true, true, true, true),
        (Scene.nodeCount(scene),
         not Option.isEmpty(Scene.getEngineNode("ground_0" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("ground_1" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("ground_0" :: "sprite" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("ground_1" :: "sprite" :: Nil, scene))))

/// ground_0 は StaticBody2D で tag=Ground、位置 (168,456)、矩形コリジョン形状を持つ
@Test
def testGroundStaticBody2DWithGroundTag(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("ground_0" :: Nil, loadedGroundScene()) {
        case Some(EngineNode.StaticBody2DWithState(body, NodeTag.Ground)) =>
            let pos = Node2D.getPosition(body);
            let shape = match CollisionObject2D.getCollisionShape(body) {
                case Some(s) => s
                case None    => bug!("ground_0 should have a collision shape")
            };
            let shapeDims = match shape {
                case CollisionShape2D.RectShape2D(r) => (r#width, r#height)
                case _ => bug!("ground_0 should be a RectShape2D")
            };
            Assert.assertEq(
                expected = ((168.0, 456.0), (336.0, 112.0)),
                ((pos#x, pos#y), shapeDims))
        case _ => bug!("ground_0 should be StaticBody2D with Ground tag")
    }

/// ground_0 は groups フィールドで "grounds" グループに登録される
@Test
def testGroundIsInGroundsGroup(): Unit \ {Assert, Fs.FileRead} =
    let scene = loadedGroundScene();
    let groundPaths = Scene.getNodesInGroup("grounds", scene);
    Assert.assertEq(
        expected = 2,
        List.length(groundPaths))

/// ground_0/sprite は Sprite2D で zIndex=10、位置 (0,0) に配置（親 ground_0 からの相対）
@Test
def testGroundSpriteHasZIndex10(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("ground_0" :: "sprite" :: Nil, loadedGroundScene()) {
        case Some(EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag)) =>
            Assert.assertEq(
                expected = ("ground", 10),
                (let Sprite2D.Sprite2D(r) = sprite; r#texture,
                 CanvasItem.getZIndex(sprite)))
        case _ => bug!("ground_0/sprite should be Sprite2D with NoTag")
    }

// ========================================================================
// loadSceneWithFont + Label2D ビルダー（ScoreScene.scene.json）
// ========================================================================

/// ScoreScene.scene.json は hud CanvasLayer + score_label / best_score_label の
/// 3 ノード構成。score_label は centered=true、best_score_label は visible=false
@Test
def testScoreSceneJsonStructure(): Unit \ {Assert, Fs.FileRead} =
    let scene = loadedScoreScene();
    Assert.assertEq(
        expected = (3, true, true, true),
        (Scene.nodeCount(scene),
         not Option.isEmpty(Scene.getEngineNode("hud" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("hud" :: "score_label" :: Nil, scene)),
         not Option.isEmpty(Scene.getEngineNode("hud" :: "best_score_label" :: Nil, scene))))

/// score_label は Label2D で text="0"、fontSize=60、centered=true、可視
@Test
def testScoreLabelLabel2D(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("hud" :: "score_label" :: Nil, loadedScoreScene()) {
        case Some(EngineNode.Label2DWithState(label, NodeTag.NoTag)) =>
            let Label2D.Label2D(r) = label;
            Assert.assertEq(
                expected = ("0", 60.0, true, true, (144.0, 50.0)),
                (r#text, r#fontSize, r#centered, r#visible,
                 (r#position#x, r#position#y)))
        case _ => bug!("score_label should be Label2D with NoTag")
    }

/// best_score_label は visible=false で読み込まれる
@Test
def testBestScoreLabelHiddenByDefault(): Unit \ {Assert, Fs.FileRead} =
    match Scene.getEngineNode("hud" :: "best_score_label" :: Nil, loadedScoreScene()) {
        case Some(EngineNode.Label2DWithState(label, NodeTag.NoTag)) =>
            Assert.assertEq(
                expected = false,
                CanvasItem.isVisible(label))
        case _ => bug!("best_score_label should be Label2D with NoTag")
    }
