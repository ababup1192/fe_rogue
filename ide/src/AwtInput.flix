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
    import java.awt.Toolkit
    import java.awt.Point
    import java.awt.Color
    import java.awt.BasicStroke
    import java.awt.Graphics2D
    import java.awt.RenderingHints
    import java.awt.image.BufferedImage
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
        lastCursorRef  = Array[GameEngine.Cursor, Static],
        // Rotate 用のカスタムカーソル。AWT 標準には回転を表すカーソルが無いので、
        // BufferedImage に円弧 + 矢印を描いて Toolkit.createCustomCursor で生成し、
        // ここにキャッシュする。setCursor のたびに再生成しない
        rotateCursorRef = Array[Cursor, Static]
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
            lastCursorRef  = Array#{GameEngine.Cursor.Default} @ Static,
            rotateCursorRef = Array#{buildRotateCursor()} @ Static
        }

    /// 回転を表す curved-arrow カーソルを 32x32 の BufferedImage に描いて生成する。
    /// 仕様:
    ///   - 円弧 (中心 (16,16) 半径 9) を 270° 描き、ホットスポットは中央
    ///   - 円弧の両端に小さい三角形の矢印 (進行方向の接線) を付け、双方向回転を表現
    ///   - 視認性のため白の影 + 黒の本線で 2 重に描き、暗い背景でも明るい背景でも見える
    /// `Graphics.drawArc` / `Graphics.fillPolygon` は int パラメータで動くので
    /// Arc2D / Path2D の inner class (Flix の Java 構文では new しづらい) を回避できる
    def buildRotateCursor(): Cursor \ IO =
        let img = new BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB);
        let g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                            RenderingHints.VALUE_ANTIALIAS_ON);
        // 影: 太線の白で先に縁取り
        g.setColor(new Color(255i32, 255i32, 255i32, 200i32));
        g.setStroke(new BasicStroke(4.0f32));
        drawRotateGlyph(g);
        // 本線: 細めの黒
        g.setColor(new Color(20i32, 20i32, 20i32, 255i32));
        g.setStroke(new BasicStroke(2.0f32));
        drawRotateGlyph(g);
        g.dispose();
        Toolkit.getDefaultToolkit().createCustomCursor(img, new Point(16, 16), "rotate")

    /// 回転矢印グリフ本体 (円弧 + 両端の矢印)。影 / 本線で 2 回呼ぶ。
    /// drawArc(x, y, w, h, startAngle, arcAngle): 角度は度数、(x,y) は外接矩形の左上、
    /// startAngle は 3 時方向を 0° として反時計回りに正
    def drawRotateGlyph(g: Graphics2D): Unit \ IO =
        // 中心 (16,16) 半径 9 → 外接矩形 (7,7,18,18)、角度 -45° 開始 270° 弧
        // → 上 / 左 / 下を覆い、右下に開口部
        g.drawArc(7i32, 7i32, 18i32, 18i32, -45i32, 270i32);
        // 弧の終端 (角度 -45°: 右下方向、座標 ≒ (23,23)) に矢印。接線は (1,1)
        drawArrowHead(g, 23i32, 23i32, 1i32, 1i32);
        // 弧の始端 (角度 225° = -45+270: 左下、座標 ≒ (9,23)) に矢印。接線は (-1,1)
        drawArrowHead(g, 9i32, 23i32, -1i32, 1i32)

    /// (cx, cy) を底辺中点として (dx, dy) 方向に伸びる三角形矢印を fillPolygon で描く。
    /// dx/dy は ±1 の単位ベクトル (要素ごとに ±1)。 大きさはピクセル直接指定で OK
    def drawArrowHead(g: Graphics2D, cx: Int32, cy: Int32, dx: Int32, dy: Int32): Unit \ IO =
        let size = 6i32;
        let half = 3i32;
        // 進行方向の前方頂点
        let tipX = cx + dx * size;
        let tipY = cy + dy * size;
        // 進行方向に垂直な底辺の左右 2 点 (90° 回転は (-y, x))
        let leftX  = cx + (0i32 - dy) * half;
        let leftY  = cy + dx * half;
        let rightX = cx + dy * half;
        let rightY = cy + (0i32 - dx) * half;
        let xs = Array#{tipX, leftX, rightX} @ Static;
        let ys = Array#{tipY, leftY, rightY} @ Static;
        g.fillPolygon(xs, ys, 3i32)

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
    /// 引くので毎回呼んでも安い。Rotate だけは AWT 標準にカーソルが無いため、
    /// 起動時に作ったカスタム curved-arrow カーソルを使う
    pub def applyCursor(refs: InputRefs, canvas: AWTGLCanvas, cursor: GameEngine.Cursor): Unit \ IO =
        let prev = Array.get(0, refs#lastCursorRef);
        if (prev == cursor) ()
        else {
            let awtCursor = match cursor {
                case GameEngine.Cursor.Rotate => Array.get(0, refs#rotateCursorRef)
                case _ =>
                    let cursorType = AwtKeyMap.cursorTypeForGameCursor(cursor);
                    Cursor.getPredefinedCursor(cursorType)
            };
            // setCursor は AWT で実質スレッドセーフに扱える数少ない API なので、
            // ゲームループから直接呼んでも EDT に投げ直さず反映する
            canvas.setCursor(awtCursor);
            Array.put(cursor, 0, refs#lastCursorRef)
        }
}
