// Tests for Button node

// ========================================================================
// テスト用ヘルパー
// ========================================================================

/// テスト用の空 FontAtlas
def buttonTestFontAtlas(): FontAtlas = {
    textureName = "font_test",
    fontSize = 32.0,
    textureSize = 512.0,
    ascent = 0.0,
    descent = 0.0,
    lineGap = 0.0,
    glyphs = Map.empty()
}

/// テスト用のデフォルト Button
def testButton(): Button =
    Button.make("Start", buttonTestFontAtlas(), 24.0, {x = 200.0, y = 50.0})

// ========================================================================
// Button.make: デフォルト値
// ========================================================================

/// make で生成されたボタンのテキストが正しい
@Test
def testButtonMakeText(): Unit \ Assert =
    Assert.assertEq(expected = "Start", Button.getText(testButton()))

/// make で生成されたボタンのサイズが正しい
@Test
def testButtonMakeSize(): Unit \ Assert =
    let size = Button.getSize(testButton());
    Assert.assertEq(expected = (200.0, 50.0), (size#x, size#y))

/// make で生成されたボタンが visible
@Test
def testButtonMakeVisible(): Unit \ Assert =
    Assert.assertTrue(CanvasItem.isVisible(testButton()))

/// make で生成されたボタンが disabled=false
@Test
def testButtonMakeNotDisabled(): Unit \ Assert =
    Assert.assertFalse(Button.isDisabled(testButton()))

/// make で生成されたボタンの visualState が Normal
@Test
def testButtonMakeNormal(): Unit \ Assert =
    Assert.assertEq(expected = ButtonVisualState.Normal, Button.getVisualState(testButton()))

/// make で生成されたボタンの justPressed が false
@Test
def testButtonMakeNotJustPressed(): Unit \ Assert =
    Assert.assertFalse(Button.isJustPressed(testButton()))

// ========================================================================
// setText / getText
// ========================================================================

/// setText → getText で往復する
@Test
def testButtonSetGetText(): Unit \ Assert =
    let btn = testButton() |> Button.setText("Play");
    Assert.assertEq(expected = "Play", Button.getText(btn))

// ========================================================================
// updateInteraction: Normal 状態
// ========================================================================

/// マウスが範囲外のとき Normal
@Test
def testButtonInteractionOutside(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 50.0, y = 50.0};  // 範囲外
    let result = Button.updateInteraction(mousePos, false, globalPos, btn);
    Assert.assertEq(expected = ButtonVisualState.Normal, Button.getVisualState(result))

// ========================================================================
// updateInteraction: Hovered 状態
// ========================================================================

/// マウスが範囲内 + ボタン非押下 → Hovered
@Test
def testButtonInteractionHovered(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};  // 範囲内
    let result = Button.updateInteraction(mousePos, false, globalPos, btn);
    Assert.assertEq(expected = ButtonVisualState.Hovered, Button.getVisualState(result))

// ========================================================================
// updateInteraction: Pressed 状態
// ========================================================================

/// マウスが範囲内 + ボタン押下 → Pressed
@Test
def testButtonInteractionPressed(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};  // 範囲内
    let result = Button.updateInteraction(mousePos, true, globalPos, btn);
    Assert.assertEq(expected = ButtonVisualState.Pressed, Button.getVisualState(result))

// ========================================================================
// updateInteraction: justPressed
// ========================================================================

/// Pressed → マウスボタン離し → justPressed=true, Hovered
@Test
def testButtonInteractionJustPressed(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};
    // まず Pressed にする
    let pressed = Button.updateInteraction(mousePos, true, globalPos, btn);
    // 離す → justPressed
    let released = Button.updateInteraction(mousePos, false, globalPos, pressed);
    Assert.assertEq(expected = ButtonVisualState.Hovered, Button.getVisualState(released));
    Assert.assertTrue(Button.isJustPressed(released))

/// justPressed 後の次フレームで justPressed がクリアされる
@Test
def testButtonJustPressedClears(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};
    let pressed = Button.updateInteraction(mousePos, true, globalPos, btn);
    let released = Button.updateInteraction(mousePos, false, globalPos, pressed);
    // justPressed=true を確認
    Assert.assertTrue(Button.isJustPressed(released));
    // 次フレーム: まだ範囲内 + 非押下 → Hovered, justPressed=false
    let nextFrame = Button.updateInteraction(mousePos, false, globalPos, released);
    Assert.assertFalse(Button.isJustPressed(nextFrame))

// ========================================================================
// updateInteraction: disabled
// ========================================================================

/// disabled 時はマウスが範囲内でも変化しない
@Test
def testButtonInteractionDisabled(): Unit \ Assert =
    let btn = testButton() |> Button.setDisabled(true);
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};
    let result = Button.updateInteraction(mousePos, true, globalPos, btn);
    Assert.assertEq(expected = ButtonVisualState.Normal, Button.getVisualState(result));
    Assert.assertFalse(Button.isJustPressed(result))

// ========================================================================
// EngineNode 経由の CanvasItem 操作
// ========================================================================

/// EngineNode.ButtonWithState の isVisible
@Test
def testButtonEngineNodeVisible(): Unit \ Assert =
    let node: EngineNode[String] = EngineNode.ButtonWithState(testButton(), "test");
    Assert.assertTrue(CanvasItem.isVisible(node))

/// EngineNode.ButtonWithState の setVisible
@Test
def testButtonEngineNodeSetVisible(): Unit \ Assert =
    let node: EngineNode[String] = EngineNode.ButtonWithState(testButton(), "test");
    let hidden = CanvasItem.setVisible(false, node);
    Assert.assertFalse(CanvasItem.isVisible(hidden))

// ========================================================================
// EngineNode 経由の Node2D 操作
// ========================================================================

/// EngineNode.ButtonWithState の getPosition / setPosition
@Test
def testButtonEngineNodePosition(): Unit \ Assert =
    let node: EngineNode[String] = EngineNode.ButtonWithState(testButton(), "test");
    let moved = Node2D.setPosition({x = 42.0, y = 84.0}, node);
    let pos = Node2D.getPosition(moved);
    Assert.assertEq(expected = (42.0, 84.0), (pos#x, pos#y))

/// EngineNode.ButtonWithState の mapButton
@Test
def testButtonEngineNodeMapButton(): Unit \ Assert =
    let node: EngineNode[String] = EngineNode.ButtonWithState(testButton(), "test");
    let updated = EngineNode.mapButton(Button.setText("Hello"), node);
    match updated {
        case EngineNode.ButtonWithState(btn, _) =>
            Assert.assertEq(expected = "Hello", Button.getText(btn))
        case _ => bug!("Expected ButtonWithState")
    }

// ========================================================================
// EngineNode 経由の Control 操作
// ========================================================================

/// EngineNode.ControlWithState の isVisible
@Test
def testControlEngineNodeVisible(): Unit \ Assert =
    let ctrl = Control.make({x = 100.0, y = 50.0});
    let node: EngineNode[String] = EngineNode.ControlWithState(ctrl, "test");
    Assert.assertTrue(CanvasItem.isVisible(node))

/// EngineNode.ControlWithState の setPosition
@Test
def testControlEngineNodePosition(): Unit \ Assert =
    let ctrl = Control.make({x = 100.0, y = 50.0});
    let node: EngineNode[String] = EngineNode.ControlWithState(ctrl, "test");
    let moved = Node2D.setPosition({x = 10.0, y = 20.0}, node);
    let pos = Node2D.getPosition(moved);
    Assert.assertEq(expected = (10.0, 20.0), (pos#x, pos#y))

// ========================================================================
// clearJustPressed
// ========================================================================

/// clearJustPressed で justPressed フラグがリセットされる
@Test
def testButtonClearJustPressed(): Unit \ Assert =
    let btn = testButton();
    let globalPos: Vec2.Vec2 = {x = 100.0, y = 100.0};
    let mousePos: Vec2.Vec2 = {x = 150.0, y = 120.0};
    let pressed = Button.updateInteraction(mousePos, true, globalPos, btn);
    let released = Button.updateInteraction(mousePos, false, globalPos, pressed);
    Assert.assertTrue(Button.isJustPressed(released));
    let cleared = Button.clearJustPressed(released);
    Assert.assertFalse(Button.isJustPressed(cleared))

// ========================================================================
// toDrawables: テキストのグリフ位置がボタン矩形内に収まること
// ========================================================================

/// STBTruetype 準拠のグリフメトリクス（yOff が負）を持つフォントアトラス
def realisticFontAtlas(): FontAtlas =
    // fontSize=32 での典型的メトリクス
    let glyph: TextLayout.GlyphMetrics = {
        xOff = 1.0, yOff = -23.0,
        glyphW = 16.0, glyphH = 24.0,
        advance = 18.0,
        s0 = 0.0, t0 = 0.0, s1 = 0.03125, t1 = 0.046875
    };
    {   textureName = "font_test",
        fontSize = 32.0,
        textureSize = 512.0,
        ascent = 23.0,
        descent = 1.0,
        lineGap = 0.0,
        // 'S'=83 のみ登録
        glyphs = Map#{83 => glyph}
    }

/// テキスト "S" のグリフ Y 座標がボタン上端 (globalPos.y) より下にあること
/// 現状: yOff=-23, scale=60/32=1.875 → glyphY = (0 + (-23))*1.875 + 540 = 496.875
/// ボタン上端=520 なので 23px はみ出している
@Test
def testButtonTextWithinTopBound(): Unit \ Assert =
    let atlas = realisticFontAtlas();
    let btn = Button.make("S", atlas, 60.0, {x = 180.0, y = 100.0});
    let globalPos: Vec2.Vec2 = {x = 150.0, y = 520.0};
    let drawables = Button.toDrawables(btn, globalPos);
    // 最初は背景矩形、2番目以降がグリフ
    let glyphs = List.drop(1, drawables);
    match List.head(glyphs) {
        case Some(d) =>
            // グリフの Y 座標がボタン上端 (520.0) 以上であるべき
            Assert.assertTrue(d#position#y >= globalPos#y)
        case None => bug!("no glyph drawables")
    }

/// テキスト "S" のグリフ下端がボタン下端 (globalPos.y + size.y) より上にあること
@Test
def testButtonTextWithinBottomBound(): Unit \ Assert =
    let atlas = realisticFontAtlas();
    let btn = Button.make("S", atlas, 60.0, {x = 180.0, y = 100.0});
    let globalPos: Vec2.Vec2 = {x = 150.0, y = 520.0};
    let drawables = Button.toDrawables(btn, globalPos);
    let glyphs = List.drop(1, drawables);
    match List.head(glyphs) {
        case Some(d) =>
            // グリフの下端 = position.y + displayH
            // displayH = texHeight * scale.y = 512 * (h / 512) = h
            let glyphBottom = d#position#y + 512.0 * d#scale#y;
            let buttonBottom = globalPos#y + 100.0;
            Assert.assertTrue(glyphBottom <= buttonBottom)
        case None => bug!("no glyph drawables")
    }
