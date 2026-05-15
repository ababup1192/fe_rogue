// Tests for AwtKeyMap — GameEngine.Key / Cursor / MouseButton と AWT 数値定数の対応
//
// 検証の観点:
//   - 全バリアントが AWT 側の定数と一致するか
//   - 別の Key / Cursor / MouseButton 同士は別の数値になるか（誤マッピングを検出）
//   - canvas → design 座標変換が比例計算で動くか

mod TestAwtKeyMap {

    import java.awt.event.KeyEvent
    import java.awt.event.MouseEvent
    import java.awt.Cursor

    // ========================================================================
    // keyToAwtCode — 全 Key バリアントの AWT 定数対応
    // ========================================================================

    /// アルファベットキー (W/A/S/D/Z/X) は AWT の VK_* 定数と一致する。
    /// 1 つのタプルでまとめて確認することで「どれかが取り違わっている」状態を 1 件で検出できる
    @Test
    def testKeyToAwtCodeAlphabetKeys(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { KeyEvent.VK_W },
                        unsafe IO { KeyEvent.VK_A },
                        unsafe IO { KeyEvent.VK_S },
                        unsafe IO { KeyEvent.VK_D },
                        unsafe IO { KeyEvent.VK_Z },
                        unsafe IO { KeyEvent.VK_X }),
            (AwtKeyMap.keyToAwtCode(GameEngine.Key.W),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.A),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.S),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.D),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.Z),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.X)))

    /// 矢印キー
    @Test
    def testKeyToAwtCodeArrowKeys(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { KeyEvent.VK_UP },
                        unsafe IO { KeyEvent.VK_DOWN },
                        unsafe IO { KeyEvent.VK_LEFT },
                        unsafe IO { KeyEvent.VK_RIGHT }),
            (AwtKeyMap.keyToAwtCode(GameEngine.Key.Up),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.Down),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.Left),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.Right)))

    /// 装飾系・特殊キー: F1 (editor トグル) と Cmd/Ctrl (undo) と Shift。
    /// LeftSuper は macOS の Cmd = VK_META に対応する
    @Test
    def testKeyToAwtCodeModifiersAndF1(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { KeyEvent.VK_F1 },
                        unsafe IO { KeyEvent.VK_SHIFT },
                        unsafe IO { KeyEvent.VK_CONTROL },
                        unsafe IO { KeyEvent.VK_META }),
            (AwtKeyMap.keyToAwtCode(GameEngine.Key.F1),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.LeftShift),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.LeftCtrl),
             AwtKeyMap.keyToAwtCode(GameEngine.Key.LeftSuper)))

    /// 全 Key バリアントが別々の AWT コードにマッピングされる（取り違え検出）。
    /// allKeys() の長さと、コードを Set にしたサイズが一致すれば重複なし
    @Test
    def testKeyToAwtCodeAllDistinct(): Unit \ Assert =
        let codes = GameEngine.allKeys() |> List.map(AwtKeyMap.keyToAwtCode);
        Assert.assertEq(
            expected = (List.length(GameEngine.allKeys()), List.length(GameEngine.allKeys())),
            (List.length(codes), Set.size(List.toSet(codes))))

    // ========================================================================
    // mouseButtonToAwtCode — マウスボタン
    // ========================================================================

    /// Left/Middle/Right が AWT MouseEvent.BUTTON1/2/3 にマッピングされる
    @Test
    def testMouseButtonToAwtCode(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { MouseEvent.BUTTON1 },
                        unsafe IO { MouseEvent.BUTTON2 },
                        unsafe IO { MouseEvent.BUTTON3 }),
            (AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Left),
             AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Middle),
             AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Right)))

    // ========================================================================
    // cursorTypeForGameCursor — マウスカーソル形状
    // ========================================================================

    /// Default は AWT DEFAULT_CURSOR、AllResize は MOVE_CURSOR にマッピング
    @Test
    def testCursorTypeDefaultAndAll(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { Cursor.DEFAULT_CURSOR },
                        unsafe IO { Cursor.MOVE_CURSOR }),
            (AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.Default),
             AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.AllResize)))

    /// H/V 伸縮は AWT の E/N リサイズカーソルに対応
    @Test
    def testCursorTypeHResizeAndVResize(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { Cursor.E_RESIZE_CURSOR },
                        unsafe IO { Cursor.N_RESIZE_CURSOR }),
            (AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.HResize),
             AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.VResize)))

    /// 4 隅のリサイズは AWT のネイティブ corner cursor (↖↗↙↘) にそれぞれ対応
    @Test
    def testCursorTypeCornerResize(): Unit \ Assert =
        Assert.assertEq(
            expected = (unsafe IO { Cursor.NW_RESIZE_CURSOR },
                        unsafe IO { Cursor.NE_RESIZE_CURSOR },
                        unsafe IO { Cursor.SW_RESIZE_CURSOR },
                        unsafe IO { Cursor.SE_RESIZE_CURSOR }),
            (AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.NWResize),
             AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.NEResize),
             AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.SWResize),
             AwtKeyMap.cursorTypeForGameCursor(GameEngine.Cursor.SEResize)))

    // ========================================================================
    // canvasToDesign — AWT ピクセル → design 論理座標
    // ========================================================================

    /// canvas 全体がそのまま design 全体に対応するとき、比例計算で論理座標が得られる。
    /// 例: 800px canvas で 400px の位置は design 1280 のときに 1280 * 400 / 800 = 640
    @Test
    def testCanvasToDesignProportional(): Unit \ Assert =
        Assert.assertEq(
            expected = 640.0,
            AwtKeyMap.canvasToDesign({cursorPx = 400.0, canvasPx = 800.0, designSize = 1280.0}))

    /// canvas 端 (0) と canvas 末尾 (= canvasPx) は design の端と末尾に一致する
    @Test
    def testCanvasToDesignAtEdges(): Unit \ Assert =
        Assert.assertEq(
            expected = (0.0, 1280.0),
            (AwtKeyMap.canvasToDesign({cursorPx = 0.0,   canvasPx = 800.0, designSize = 1280.0}),
             AwtKeyMap.canvasToDesign({cursorPx = 800.0, canvasPx = 800.0, designSize = 1280.0})))

    /// 起動直後など canvasPx = 0 のとき (AWT peer 未確定) は 0 を返してクラッシュさせない
    @Test
    def testCanvasToDesignZeroCanvasGuardsAgainstDivByZero(): Unit \ Assert =
        Assert.assertEq(
            expected = 0.0,
            AwtKeyMap.canvasToDesign({cursorPx = 100.0, canvasPx = 0.0, designSize = 1280.0}))
}
