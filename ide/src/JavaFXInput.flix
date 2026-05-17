// JavaFXInput — JavaFX 入力イベントを Ref に流し、JavaFXLayer の GameEngine.Game effect
// handler から読み出すための入力レイヤ。AwtInput の JavaFX 版。
//
// 責務分割:
//   - InputRefs: FX EDT と main thread のどちらからも触る Ref 群
//   - attachListeners: ImageView / Scene に EventHandler を装着
//   - readXxx: GameEngine.Game handler の本体で呼ぶ読み出し関数
//   - applyCursor: setCursor effect から ImageView に Cursor を反映
//
// AwtInput と異なる点:
//   - imageViewRef を保持 (JavaFXLayer.paintGL の resize で setImage するため)
//   - キーボード listener は Scene 単位 (Node には keyPressed が来ない)
//   - 座標は ImageView 内 local。Y 軸は setScaleY(-1) で表示反転されているため、
//     readMousePosition でも anti-flip して design 座標に変換する
//
// Phase 1 では keyboard / cursor は最小限。順次 JavaFXKeyMap.flix を拡充する

mod JavaFXInput {
    import javafx.scene.Cursor
    import javafx.scene.Scene
    import javafx.scene.image.ImageView
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.MouseButton
    import javafx.scene.input.ScrollEvent
    import javafx.scene.input.KeyEvent
    import javafx.scene.input.KeyCode
    import javafx.event.EventHandler

    pub type alias DesignSize = {width = Float64, height = Float64}

    /// 入力状態 Ref 群。imageViewRef は JavaFXLayer が paintGL から setImage を呼ぶ用
    pub type alias InputRefs = {
        imageViewRef   = Array[Option[ImageView], Static],
        mousePxRef     = Array[(Float64, Float64), Static],
        leftDownRef    = Array[Bool, Static],
        rightDownRef   = Array[Bool, Static],
        middleDownRef  = Array[Bool, Static],
        // JavaFX KeyCode は enum なので、押下中の KeyCode を保持する。
        // GameEngine.Key → JavaFX KeyCode のマッピングは JavaFXKeyMap で行う
        keysDownRef    = Array[Set[String], Static],
        scrollDeltaRef = Array[Float64, Static],
        lastCursorRef  = Array[GameEngine.Cursor, Static]
    }

    pub def newInputRefs(): InputRefs \ IO =
        {
            imageViewRef   = Array#{(None: Option[ImageView])} @ Static,
            mousePxRef     = Array#{(0.0, 0.0)} @ Static,
            leftDownRef    = Array#{false} @ Static,
            rightDownRef   = Array#{false} @ Static,
            middleDownRef  = Array#{false} @ Static,
            keysDownRef    = Array#{(Set.empty(): Set[String])} @ Static,
            scrollDeltaRef = Array#{0.0} @ Static,
            lastCursorRef  = Array#{GameEngine.Cursor.Default} @ Static
        }

    /// ImageView に mouse / scroll、Scene に keyboard listener を装着する。
    /// scene が null になることはほぼ無いが、Stage.show 前に呼ばれた場合に備えて
    /// Option 包みで安全側に倒す
    pub def attachListeners(scene: Scene, imageView: ImageView, refs: InputRefs): Unit \ IO = {
        let onMouseMoved = new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO =
                Array.put((e.getX(), e.getY()), 0, refs#mousePxRef)
        };
        imageView.setOnMouseMoved(onMouseMoved);
        imageView.setOnMouseDragged(onMouseMoved);

        imageView.setOnMousePressed(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                Array.put((e.getX(), e.getY()), 0, refs#mousePxRef);
                setButtonDown(refs, e.getButton(), true);
                // キーボード入力を受け取れるよう Scene にフォーカス
                imageView.requestFocus()
            }
        });
        imageView.setOnMouseReleased(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                Array.put((e.getX(), e.getY()), 0, refs#mousePxRef);
                setButtonDown(refs, e.getButton(), false)
            }
        });
        imageView.setOnScroll(new EventHandler[ScrollEvent] {
            def handle(_this: EventHandler[ScrollEvent], e: ScrollEvent): Unit \ IO = {
                let prev = Array.get(0, refs#scrollDeltaRef);
                // JavaFX の deltaY は下スクロールで負。AwtInput と仕様を揃えるため
                // 「上スクロールで正」に正規化する。AWT は preciseWheelRotation 下で正
                // なので - を付けるのと同じ符号にするためそのまま加算（既に上=正）
                Array.put(prev + e.getDeltaY() / 40.0, 0, refs#scrollDeltaRef)
            }
        });

        // keyboard は Scene 全体で拾う
        if (Object.isNull(scene)) ()
        else {
            scene.setOnKeyPressed(new EventHandler[KeyEvent] {
                def handle(_this: EventHandler[KeyEvent], e: KeyEvent): Unit \ IO = {
                    let cur = Array.get(0, refs#keysDownRef);
                    Array.put(Set.insert(e.getCode().toString(), cur), 0, refs#keysDownRef)
                }
            });
            scene.setOnKeyReleased(new EventHandler[KeyEvent] {
                def handle(_this: EventHandler[KeyEvent], e: KeyEvent): Unit \ IO = {
                    let cur = Array.get(0, refs#keysDownRef);
                    Array.put(Set.remove(e.getCode().toString(), cur), 0, refs#keysDownRef)
                }
            })
        }
    }

    def setButtonDown(refs: InputRefs, btn: MouseButton, isDown: Bool): Unit \ IO =
        // Java enum は Flix の `==` (Eq typeclass) では比較できないので toString 経由で比較。
        // JavaFX MouseButton の name は "PRIMARY" / "SECONDARY" / "MIDDLE" / "BACK" / "FORWARD" / "NONE"
        let name = btn.toString();
        if (name == "PRIMARY")        Array.put(isDown, 0, refs#leftDownRef)
        else if (name == "SECONDARY") Array.put(isDown, 0, refs#rightDownRef)
        else if (name == "MIDDLE")    Array.put(isDown, 0, refs#middleDownRef)
        else ()

    /// マウス位置を design 座標で取得する。FBO サイズ = ImageView サイズなので、
    /// ImageView local 座標を viewport (letterbox 補正後) 経由で design 空間に変換する。
    ///
    /// ImageView は setScaleY(-1) で **表示** だけが上下反転されている。
    /// MouseEvent.getX/getY は un-scaled local 座標を返すので、
    ///   - 視覚上の top をクリック → local Y = viewH
    ///   - 視覚上の bottom をクリック → local Y = 0
    /// になる。これを top-down の視覚 Y に直してから viewport / design 変換する。
    /// この変換を忘れると designY が範囲外 (負 / designH 超) に出て、Editor が
    /// クリック判定で常に外れる
    pub def readMousePosition(refs: InputRefs, design: DesignSize): Vec2.Vec2 \ IO = {
        let (px, py) = Array.get(0, refs#mousePxRef);
        let ivOpt = Array.get(0, refs#imageViewRef);
        match ivOpt {
            case None => Vec2.zero()
            case Some(iv) => {
                let bounds = iv.getBoundsInLocal();
                let viewW = bounds.getWidth();
                let viewH = bounds.getHeight();
                if (viewW <= 0.0 or viewH <= 0.0) Vec2.zero()
                else {
                    let (vpX, vpY, vpW, vpH) = RenderFrame.calcViewport(
                        Float64.tryToInt32(viewW) |> Option.getWithDefault(1i32),
                        Float64.tryToInt32(viewH) |> Option.getWithDefault(1i32),
                        design#width, design#height);
                    // local Y → 視覚 Y (top-down) に変換
                    let visualPy = viewH - py;
                    // 視覚座標での viewport top edge
                    let visualVpTop = viewH - Int32.toFloat64(vpY + vpH);
                    let vpMouseX = px - Int32.toFloat64(vpX);
                    let vpMouseY = visualPy - visualVpTop;
                    let vpFW = Int32.toFloat64(vpW);
                    let vpFH = Int32.toFloat64(vpH);
                    {x = if (vpFW == 0.0) 0.0 else vpMouseX / vpFW * design#width,
                     y = if (vpFH == 0.0) 0.0 else vpMouseY / vpFH * design#height}
                }
            }
        }
    }

    pub def readMouseButtonPressed(refs: InputRefs, button: GameEngine.MouseButton): Bool \ IO =
        match button {
            case GameEngine.MouseButton.Left   => Array.get(0, refs#leftDownRef)
            case GameEngine.MouseButton.Right  => Array.get(0, refs#rightDownRef)
            case GameEngine.MouseButton.Middle => Array.get(0, refs#middleDownRef)
        }

    pub def readKeyPressed(refs: InputRefs, key: GameEngine.Key): Bool \ IO =
        Set.memberOf(JavaFXKeyMap.keyToName(key), Array.get(0, refs#keysDownRef))

    pub def consumeScrollDelta(refs: InputRefs): Float64 \ IO =
        let value = Array.get(0, refs#scrollDeltaRef);
        Array.put(0.0, 0, refs#scrollDeltaRef);
        value

    /// JavaFX Cursor を ImageView に反映。AwtInput と同じく前回と同じ形状なら省略。
    /// ImageView は refs#imageViewRef から引く (customize 完了後に Layer が格納)
    pub def applyCursor(refs: InputRefs, cursor: GameEngine.Cursor): Unit \ IO =
        let prev = Array.get(0, refs#lastCursorRef);
        if (prev == cursor) ()
        else {
            match Array.get(0, refs#imageViewRef) {
                case None => ()
                case Some(iv) => {
                    let fxCursor = JavaFXKeyMap.cursorForGameCursor(cursor);
                    iv.setCursor(fxCursor);
                    Array.put(cursor, 0, refs#lastCursorRef)
                }
            }
        }
}
