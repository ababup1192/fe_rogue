// AwtInput — AWT 入力イベントを Ref に流し、SwingLayer の GameEngine.Game effect ハンドラから
// 読み出すための入力レイヤ
//
// 責務分割:
//   - InputRefs: AWT EDT が書き込み、メインループ (Game.* handler) が読む Ref 群
//   - attachListeners: AWTGLCanvas に MouseListener / MouseMotionListener / KeyListener を装着
//   - readXxx: GameEngine.Game handler の本体で呼ぶ読み出し関数
//   - applyCursor: setCursor effect から呼ばれて canvas.setCursor を叩く
//
// AWT のイベントは EDT 上で発生し、Ref への書き込みは atomic な put である前提で同期は省略。
// マウス座標は AWT canvas のピクセル空間で記録し、読み出し時に design 座標へ変換する
// (canvas のリサイズに毎フレーム追従するため)

mod AwtInput {
    import java.awt.Cursor
    import java.awt.event.MouseAdapter
    import java.awt.event.MouseEvent
    import java.awt.event.MouseMotionListener
    import java.awt.event.MouseWheelListener
    import java.awt.event.MouseWheelEvent
    import java.awt.event.KeyAdapter
    import java.awt.event.KeyEvent
    import org.lwjgl.opengl.awt.AWTGLCanvas

    /// design 座標系の論理サイズ (EngineConfig.designWidth / designHeight)。
    /// マウス座標を AWT canvas → design 空間に変換するときに使う
    pub type alias DesignSize = {width = Float64, height = Float64}

    /// AWT 入力状態を保持する Ref 群。すべて Static で alloc し、EDT と main thread の
    /// どちらからも触る。
    ///   mousePxRef:        AWT canvas のピクセル座標 (cursorX, cursorY)。MouseMotionListener が書く
    ///   leftDownRef:       マウス左ボタンの現在の押下状態。MouseListener が書く
    ///   rightDownRef:      マウス右ボタンの現在の押下状態
    ///   middleDownRef:     マウス中ボタンの現在の押下状態
    ///   keysDownRef:       現在押下中のキーコード集合。KeyListener が AWT KeyEvent.VK_* を出し入れする
    ///   scrollDeltaRef:    最後の consumeScrollDelta 以降に蓄積されたホイール delta (y 方向)
    ///   lastCursorRef:     直近に AWT に渡したカーソル形状。同じ形状が連続して setCursor を呼んでも
    ///                      AWT call を省くため
    pub type alias InputRefs = {
        mousePxRef     = Array[(Float64, Float64), Static],
        leftDownRef    = Array[Bool, Static],
        rightDownRef   = Array[Bool, Static],
        middleDownRef  = Array[Bool, Static],
        keysDownRef    = Array[Set[Int32], Static],
        scrollDeltaRef = Array[Float64, Static],
        lastCursorRef  = Array[GameEngine.Cursor, Static]
    }

    /// 空の入力状態を作る (Ref 群の確保のみ。listener は attachListeners で別途装着する)
    pub def newInputRefs(): InputRefs \ IO =
        {
            mousePxRef     = Array#{(0.0, 0.0)} @ Static,
            leftDownRef    = Array#{false} @ Static,
            rightDownRef   = Array#{false} @ Static,
            middleDownRef  = Array#{false} @ Static,
            keysDownRef    = Array#{(Set.empty(): Set[Int32])} @ Static,
            scrollDeltaRef = Array#{0.0} @ Static,
            lastCursorRef  = Array#{GameEngine.Cursor.Default} @ Static
        }

    /// AWTGLCanvas に MouseListener / MouseMotionListener / MouseWheelListener / KeyListener を装着し、
    /// AWT イベントを refs に流す。キーイベントを受け取るため canvas を focusable にし、
    /// クリック時にフォーカスを掴むよう mousePressed でも requestFocusInWindow を呼ぶ
    pub def attachListeners(canvas: AWTGLCanvas, refs: InputRefs): Unit \ IO =
        canvas.setFocusable(true);

        let onMouseMove = (event: MouseEvent) ->
            Array.put((Int32.toFloat64(event.getX()), Int32.toFloat64(event.getY())),
                      0, refs#mousePxRef);

        let mouseAdapter = new MouseAdapter {
            def mousePressed(_this: MouseAdapter, event: MouseEvent): Unit \ IO = {
                canvas.requestFocusInWindow();
                onMouseMove(event);
                setButtonDown(refs, event.getButton(), true)
            }
            def mouseReleased(_this: MouseAdapter, event: MouseEvent): Unit \ IO = {
                onMouseMove(event);
                setButtonDown(refs, event.getButton(), false)
            }
            def mouseEntered(_this: MouseAdapter, event: MouseEvent): Unit \ IO =
                onMouseMove(event)
            def mouseExited(_this: MouseAdapter, event: MouseEvent): Unit \ IO =
                onMouseMove(event)
        };
        canvas.addMouseListener(mouseAdapter);
        canvas.addMouseMotionListener(new MouseMotionListener {
            def mouseMoved(_this: MouseMotionListener, event: MouseEvent): Unit \ IO =
                onMouseMove(event)
            def mouseDragged(_this: MouseMotionListener, event: MouseEvent): Unit \ IO =
                onMouseMove(event)
        });
        canvas.addMouseWheelListener(new MouseWheelListener {
            def mouseWheelMoved(_this: MouseWheelListener, event: MouseWheelEvent): Unit \ IO = {
                let prev = Array.get(0, refs#scrollDeltaRef);
                // AWT は下スクロールで preciseWheelRotation 正、ゲームは上で正のため反転する
                Array.put(prev - event.getPreciseWheelRotation(), 0, refs#scrollDeltaRef)
            }
        });
        canvas.addKeyListener(new KeyAdapter {
            def keyPressed(_this: KeyAdapter, event: KeyEvent): Unit \ IO = {
                let cur = Array.get(0, refs#keysDownRef);
                Array.put(Set.insert(event.getKeyCode(), cur), 0, refs#keysDownRef)
            }
            def keyReleased(_this: KeyAdapter, event: KeyEvent): Unit \ IO = {
                let cur = Array.get(0, refs#keysDownRef);
                Array.put(Set.remove(event.getKeyCode(), cur), 0, refs#keysDownRef)
            }
        })

    /// AWT が報告したボタン番号 (BUTTON1/2/3) を該当 Ref にセットする
    def setButtonDown(refs: InputRefs, awtButton: Int32, isDown: Bool): Unit \ IO =
        if (awtButton == AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Left))
            Array.put(isDown, 0, refs#leftDownRef)
        else if (awtButton == AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Right))
            Array.put(isDown, 0, refs#rightDownRef)
        else if (awtButton == AwtKeyMap.mouseButtonToAwtCode(GameEngine.MouseButton.Middle))
            Array.put(isDown, 0, refs#middleDownRef)
        else ()

    /// 現在のマウス位置を design 座標で取得する。
    /// 描画は RenderFrame.calcViewport で letterbox/pillarbox されているので、
    /// マウス座標も同じ viewport で逆変換しないと「ハンドルの見た目」と「クリックの当たり位置」
    /// がズレる。canvas 全体ではなく viewport 内に入っている部分だけが design 領域に対応する。
    /// canvas の AWT 座標 (Y は下向き) は GL の framebuffer 座標 (Y は上向き) と上下が
    /// 反転しているので、viewport の Y オフセットは canvas 高さから引いて求める
    pub def readMousePosition(refs: InputRefs, canvas: AWTGLCanvas, design: DesignSize): Vec2.Vec2 \ IO =
        let (px, py) = Array.get(0, refs#mousePxRef);
        let canvasW = canvas.getWidth();
        let canvasH = canvas.getHeight();
        if (canvasW <= 0i32 or canvasH <= 0i32) Vec2.zero()
        else {
            let (vpX, vpY, vpW, vpH) =
                RenderFrame.calcViewport(canvasW, canvasH, design#width, design#height);
            // GL viewport の Y 原点は下端。AWT の Y 原点は上端。viewport 上辺の AWT-y は
            // canvasH - (vpY + vpH)
            let awtVpTop = Int32.toFloat64(canvasH - (vpY + vpH));
            let vpMouseX = px - Int32.toFloat64(vpX);
            let vpMouseY = py - awtVpTop;
            let vpFW = Int32.toFloat64(vpW);
            let vpFH = Int32.toFloat64(vpH);
            {x = if (vpFW == 0.0) 0.0 else vpMouseX / vpFW * design#width,
             y = if (vpFH == 0.0) 0.0 else vpMouseY / vpFH * design#height}
        }

    /// 指定マウスボタンが現在押されているかを返す
    pub def readMouseButtonPressed(refs: InputRefs, button: GameEngine.MouseButton): Bool \ IO =
        match button {
            case GameEngine.MouseButton.Left   => Array.get(0, refs#leftDownRef)
            case GameEngine.MouseButton.Right  => Array.get(0, refs#rightDownRef)
            case GameEngine.MouseButton.Middle => Array.get(0, refs#middleDownRef)
        }

    /// 指定キーが現在押されているかを返す
    pub def readKeyPressed(refs: InputRefs, key: GameEngine.Key): Bool \ IO =
        Set.memberOf(AwtKeyMap.keyToAwtCode(key), Array.get(0, refs#keysDownRef))

    /// 最後の consume 以降に蓄積されたスクロール delta を返し、内部蓄積を 0 にリセットする
    pub def consumeScrollDelta(refs: InputRefs): Float64 \ IO =
        let value = Array.get(0, refs#scrollDeltaRef);
        Array.put(0.0, 0, refs#scrollDeltaRef);
        value

    /// AWT にカーソル形状を反映する。前回と同じ形状なら AWT call を省略 (連続呼び出しで
    /// flicker しないように)。`Cursor.getPredefinedCursor` は AWT の内部キャッシュを
    /// 引くので毎回呼んでも安い
    pub def applyCursor(refs: InputRefs, canvas: AWTGLCanvas, cursor: GameEngine.Cursor): Unit \ IO =
        let prev = Array.get(0, refs#lastCursorRef);
        if (prev == cursor) ()
        else {
            let cursorType = AwtKeyMap.cursorTypeForGameCursor(cursor);
            let awtCursor = Cursor.getPredefinedCursor(cursorType);
            // setCursor は AWT で実質スレッドセーフに扱える数少ない API なので、
            // ゲームループから直接呼んでも EDT に投げ直さず反映する
            canvas.setCursor(awtCursor);
            Array.put(cursor, 0, refs#lastCursorRef)
        }
}
