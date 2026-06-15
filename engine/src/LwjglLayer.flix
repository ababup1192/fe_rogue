// LwjglLayer — GLFW ウィンドウ + 入力 polling + GameEngine.Game/Audio effect handler。
//
// GL / OpenAL / シェーダ / テクスチャ / フォントベイク / フレーム描画 / 音声デコードは
// `render_core` パッケージ (RenderCore.*) に分離済み。このファイルは GLFW 外周だけを残し、
// 各 effect メソッドの本体で RenderCore.* の関数を呼び出す。
//
// withLwjgl のシグネチャは公開 API として固定: ゲーム側 (examples/* の Main.flix) を
// 変更せずに済むよう、第 1 引数 EngineConfig と戻り値の effect 制約は保持する。

mod LwjglLayer {
    import org.lwjgl.glfw.GLFW
    import org.lwjgl.glfw.GLFWGamepadState
    import org.lwjgl.glfw.Callbacks
    import org.lwjgl.glfw.GLFWFramebufferSizeCallbackI
    import org.lwjgl.glfw.GLFWMouseButtonCallbackI
    import org.lwjgl.glfw.GLFWScrollCallbackI
    import org.lwjgl.opengl.GL
    import org.lwjgl.opengl.GL11
    import org.lwjgl.openal.AL
    import org.lwjgl.openal.AL10
    import org.lwjgl.openal.ALC
    import org.lwjgl.openal.ALC10
    import org.lwjgl.system.MemoryStack
    import org.lwjgl.system.MemoryUtil
    import java.lang.System

    // ========================================================================
    // GLFW Code Mapping (engine の論理キー → GLFW 数値コード)
    // ========================================================================

    def keyToGlfw(key: GameEngine.Key): Int32 = match key {
        case GameEngine.Key.W         => 87
        case GameEngine.Key.A         => 65
        case GameEngine.Key.S         => 83
        case GameEngine.Key.D         => 68
        case GameEngine.Key.Z         => 90
        case GameEngine.Key.X         => 88
        case GameEngine.Key.C         => 67
        case GameEngine.Key.M         => 77
        case GameEngine.Key.Up        => 265
        case GameEngine.Key.Down      => 264
        case GameEngine.Key.Left      => 263
        case GameEngine.Key.Right     => 262
        case GameEngine.Key.Enter     => 257
        case GameEngine.Key.Space     => 32
        case GameEngine.Key.Escape    => 256
        case GameEngine.Key.F1        => 290
        case GameEngine.Key.LeftShift => 340
        case GameEngine.Key.LeftCtrl  => 341
        case GameEngine.Key.LeftSuper => 343
    }

    def mouseButtonToGlfw(button: GameEngine.MouseButton): Int32 = match button {
        case GameEngine.MouseButton.Left   => 0
        case GameEngine.MouseButton.Right  => 1
        case GameEngine.MouseButton.Middle => 2
    }

    /// GLFW 3.4 (LWJGL 3.4.1 同梱) の cursor shape 定数。
    /// 4 隅は GLFW では対角単位 (NWSE / NESW) の 2 種しか無いので、
    /// NW + SE → GLFW_RESIZE_NWSE_CURSOR、NE + SW → GLFW_RESIZE_NESW_CURSOR にエイリアス。
    def cursorShapeToGlfw(cursor: GameEngine.Cursor): Int32 = match cursor {
        case GameEngine.Cursor.Default    => 0x36001  // GLFW_ARROW_CURSOR
        case GameEngine.Cursor.HResize    => 0x36005  // GLFW_HRESIZE_CURSOR
        case GameEngine.Cursor.VResize    => 0x36006  // GLFW_VRESIZE_CURSOR
        case GameEngine.Cursor.AllResize  => 0x36009  // GLFW_RESIZE_ALL_CURSOR
        case GameEngine.Cursor.Rotate     => 0x36004  // GLFW_POINTING_HAND_CURSOR
        case GameEngine.Cursor.NWResize   => 0x36007  // GLFW_RESIZE_NWSE_CURSOR
        case GameEngine.Cursor.SEResize   => 0x36007  // GLFW_RESIZE_NWSE_CURSOR
        case GameEngine.Cursor.NEResize   => 0x36008  // GLFW_RESIZE_NESW_CURSOR
        case GameEngine.Cursor.SWResize   => 0x36008  // GLFW_RESIZE_NESW_CURSOR
    }

    // ========================================================================
    // LWJGL Handler for GameEngine.Game / GameEngine.Audio effects
    // ========================================================================

    /// `rootDir` 直下の project.json を読んで `withLwjgl` を起動する便利ラッパ。
    /// examples の Main.flix からは `with LwjglLayer.withProject(".")` の形で
    /// 直接 with-chain に並べて使う。loadProject 失敗時は bug! で停止する
    /// (project.json が壊れているのは開発者が直すべき状態)。
    pub def withProject(rootDir: String, f: Unit -> a \ ef):
            a \ ef - GameEngine.Game - GameEngine.Audio + IO + Fs.FileRead =
        match ProjectLoader.loadProject(rootDir) {
            case Ok(proj)  => withLwjgl(proj#config, f)
            case Err(msg) => bug!("Failed to load project.json: ${msg}")
        }

    pub def withLwjgl(config: GameEngine.EngineConfig, f: Unit -> a \ ef): a \ ef - GameEngine.Game - GameEngine.Audio + IO =
        if (not GLFW.glfwInit()) {
            println("GLFW init failed");
            bug!("GLFW failed")
        } else ();

        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MAJOR, 3);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MINOR, 3);
        GLFW.glfwWindowHint(GLFW.GLFW_OPENGL_PROFILE, GLFW.GLFW_OPENGL_CORE_PROFILE);
        GLFW.glfwWindowHint(GLFW.GLFW_OPENGL_FORWARD_COMPAT, GL11.GL_TRUE);
        GLFW.glfwWindowHint(GLFW.GLFW_RESIZABLE, GL11.GL_TRUE);

        let window = GLFW.glfwCreateWindow(config#windowWidth, config#windowHeight, config#title, MemoryUtil.NULL, MemoryUtil.NULL);
        GLFW.glfwMakeContextCurrent(window);
        GLFW.glfwSwapInterval(1);
        // Sticky mouse buttons: 1 フレーム未満の press→release（macOS の
        // トラックパッド「タップでクリック」など）が polling で取りこぼされる
        // のを防ぐ。次回 `glfwGetMouseButton` 呼び出し時に PRESS を 1 度返してから
        // RELEASE に落ちる。
        GLFW.glfwSetInputMode(window, GLFW.GLFW_STICKY_MOUSE_BUTTONS, GL11.GL_TRUE);
        discard GL.createCapabilities();

        let fbStack = MemoryStack.stackPush();
        let fbWidthBuf = fbStack.mallocInt(1);
        let fbHeightBuf = fbStack.mallocInt(1);
        GLFW.glfwGetFramebufferSize(window, fbWidthBuf, fbHeightBuf);
        let fbWidth = fbWidthBuf.get(0);
        let fbHeight = fbHeightBuf.get(0);
        discard MemoryStack.stackPop();
        println("Framebuffer size: ${fbWidth}x${fbHeight}");

        GL11.glEnable(GL11.GL_BLEND);
        GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

        let screenW = Int32.toFloat64(config#designWidth);
        let screenH = Int32.toFloat64(config#designHeight);

        // GL リソース構築は render_core に委譲
        let spriteShader = RenderShader.createShaderProgram(
            RenderShader.vertexShaderSource(),
            RenderShader.fragmentShaderSource());
        RenderShader.setProjectionMatrix(spriteShader, screenW, screenH);

        let tileShader = RenderShader.createShaderProgram(
            RenderShader.tileVertexShaderSource(),
            RenderShader.tileFragmentShaderSource());
        RenderShader.setProjectionMatrix(tileShader, screenW, screenH);

        let (vao, quadVBO) = RenderSprite.initSpriteRenderer();
        let (polyVao, polyVbo) = RenderSprite.initPolygonRenderer();

        println("Loading textures...");
        let registry0 = RenderTexture.loadTextureRegistry(config#textureManifest);

        println("Baking font atlases...");
        let (fontAtlases, registry) = RenderFont.bakeFontAtlases(config#fontManifest, registry0);

        // ===== OpenAL audio init =====
        println("Initializing audio...");
        let alDevice = ALC10.nalcOpenDevice(MemoryUtil.NULL);
        if (alDevice == 0i64) {
            println("Failed to open OpenAL device");
            bug!("Failed to open OpenAL device")
        } else ();
        let alcCaps = ALC.createCapabilities(alDevice);
        let alContext = ALC10.nalcCreateContext(alDevice, MemoryUtil.NULL);
        if (alContext == 0i64) {
            println("Failed to create OpenAL context");
            bug!("Failed to create OpenAL context")
        } else ();
        if (not ALC10.alcMakeContextCurrent(alContext)) {
            println("Failed to make OpenAL context current");
            bug!("Failed to make OpenAL context current")
        } else ();
        discard AL.createCapabilities(alcCaps);

        println("  Loading sounds...");
        let audioRegistry = RenderAudio.loadAudioRegistry(config#soundManifest);
        println("  Audio ready");

        let timeHolder = Array#{System.nanoTime()} @ Static;

        // リサイズ中の再描画用に最後のフレームの描画コマンドを保持する (sprites + tileMaps + polygons)
        let renderStateHolder = Array#{((Nil: List[GameEngine.Drawable]),
                                         (Nil: List[GameEngine.TileMapRenderCmd]),
                                         (Nil: List[GameEngine.PolygonRenderCmd]))} @ Static;

        // 6 種のスタンダードカーソルを起動時に作成して再利用する。
        // setCursor 呼び出しの度に都度作成 / 破棄すると重く、リーク源にもなる
        let arrowCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Default));
        let hResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.HResize));
        let vResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.VResize));
        let allResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.AllResize));
        let rotateCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Rotate));
        // 4 隅: GLFW では対角単位 (NWSE/NESW) しか無いので、NW+SE と NE+SW は同じ
        // ハンドルを共有する。AWT 側は方向別の 4 種を持っており、IDE では AWT 経路の方が
        // ホバー時に表示されるためここの集約は問題にならない。
        let nwseResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.NWResize));
        let neswResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.NEResize));
        // 同じ Cursor を毎フレーム渡されたときに glfwSetCursor を抑制するためのキャッシュ
        let lastCursorHolder = Array#{(GameEngine.Cursor.Default: GameEngine.Cursor)} @ Static;
        let cursorOf = cursor -> match cursor {
            case GameEngine.Cursor.Default    => arrowCursor
            case GameEngine.Cursor.HResize    => hResizeCursor
            case GameEngine.Cursor.VResize    => vResizeCursor
            case GameEngine.Cursor.AllResize  => allResizeCursor
            case GameEngine.Cursor.Rotate     => rotateCursor
            case GameEngine.Cursor.NWResize   => nwseResizeCursor
            case GameEngine.Cursor.SEResize   => nwseResizeCursor
            case GameEngine.Cursor.NEResize   => neswResizeCursor
            case GameEngine.Cursor.SWResize   => neswResizeCursor
        };

        // マウスホイールの y 方向 delta を 1 フレームぶん蓄積する。
        // consumeScrollDelta ハンドラが値を読み出して 0 に戻す。
        let scrollDeltaHolder = Array#{0.0} @ Static;
        discard GLFW.glfwSetScrollCallback(window, new GLFWScrollCallbackI {
            def invoke(_this: GLFWScrollCallbackI, _w: Int64, _xoffset: Float64, yoffset: Float64): Unit \ IO = {
                let prev = Array.get(0, scrollDeltaHolder);
                Array.put(prev + yoffset, 0, scrollDeltaHolder)
            }
        });

        // マウスボタンの「PRESS が来た」フラグを 1 フレームぶん保持する。
        // [0]=Left, [1]=Right, [2]=Middle. `shouldClose` が glfwPollEvents の **直前**
        // にリセットし、polling 中に来た callback が立てる。
        let mouseButtonPressedHolder = Array#{false, false, false} @ Static;
        discard GLFW.glfwSetMouseButtonCallback(window, new GLFWMouseButtonCallbackI {
            def invoke(_this: GLFWMouseButtonCallbackI, _w: Int64,
                        button: Int32, action: Int32, _mods: Int32): Unit \ IO = {
                // GLFW_PRESS = 1。0..2 範囲外は無視。
                if (action == 1 and button >= 0 and button <= 2)
                    Array.put(true, button, mouseButtonPressedHolder)
                else ()
            }
        });

        // ===== Gamepad (Xbox レイアウト) =====
        // GLFW gamepad API でコントローラ入力を読み、isKeyPressed に OR する。
        // これにより Key を参照する全 Scene を無改修でコントローラ対応にできる
        // (currentKeys() も isKeyPressed 経由なので onKeyPressed のエッジ検出も反映される)。
        // GLFWGamepadState.create() は GC 管理のダイレクトバッファ上に確保されるため明示解放は不要。
        // 状態は shouldClose で 1 フレーム 1 回更新し、padPressed が読み出す。
        let gamepadState = GLFWGamepadState.create();
        let gamepadConnectedHolder = Array#{false} @ Static;
        let padBtn = (idx: Int32) -> gamepadState.buttons(idx) != 0i8;
        let padAxis = (idx: Int32) -> gamepadState.axes(idx);
        // 方向は D-pad と左スティック（デッドゾーン 0.5）の両方で受ける。
        // GLFW のスティック Y 軸は上が負。
        let padUp    = () -> padBtn(GLFW.GLFW_GAMEPAD_BUTTON_DPAD_UP)    or (padAxis(GLFW.GLFW_GAMEPAD_AXIS_LEFT_Y) < -0.5f32);
        let padDown  = () -> padBtn(GLFW.GLFW_GAMEPAD_BUTTON_DPAD_DOWN)  or (padAxis(GLFW.GLFW_GAMEPAD_AXIS_LEFT_Y) >  0.5f32);
        let padLeft  = () -> padBtn(GLFW.GLFW_GAMEPAD_BUTTON_DPAD_LEFT)  or (padAxis(GLFW.GLFW_GAMEPAD_AXIS_LEFT_X) < -0.5f32);
        let padRight = () -> padBtn(GLFW.GLFW_GAMEPAD_BUTTON_DPAD_RIGHT) or (padAxis(GLFW.GLFW_GAMEPAD_AXIS_LEFT_X) >  0.5f32);
        // 物理キー → ゲームパッド入力の対応。**1 ボタン = 1 キー**を厳守する。
        // 1 ボタンを複数キーに割り当てると、その 1 押しで複数キーが同フレームに「新規押下」
        // 扱いになり onKeyPressed が複数回発火する。例えば A→Z/Space/Enter にすると Confirm が
        // 3 連発し、メニューを開いた直後に確定して行動を消費してしまう
        // (キーボードは 1 キー 1 入力なのでこの問題は出ない)。
        // fe_rogue: 決定=Z=A / メニュー確定=Enter=Start / キャンセル=X=B /
        // ミニマップ=M=Y / 危険範囲トグル=LeftShift=LB。
        // Escape はマップ上でゲーム終了を誘発するためパッドには **割り当てない**。
        // キャンセル / メニュー戻りは X=B で十分 (dispatchMenuKey が X→Cancel を全サブメニューで処理)。
        // 方向は arrows のみ (CursorScene は W/A/S/D と Up/Down/Left/Right の両対応なので arrows で足りる)。
        let padPressed = (key: GameEngine.Key) ->
            if (not Array.get(0, gamepadConnectedHolder)) false
            else match key {
                case GameEngine.Key.Up        => padUp()
                case GameEngine.Key.Down      => padDown()
                case GameEngine.Key.Left      => padLeft()
                case GameEngine.Key.Right     => padRight()
                case GameEngine.Key.Z         => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_A)
                case GameEngine.Key.X         => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_B)
                case GameEngine.Key.Enter     => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_START)
                // Y = 集合ショートカット(Key.C)、ミニマップ(Key.M)は X ボタンへ移動。
                case GameEngine.Key.C         => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_Y)
                case GameEngine.Key.M         => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_X)
                case GameEngine.Key.LeftShift => padBtn(GLFW.GLFW_GAMEPAD_BUTTON_LEFT_BUMPER)
                case _                        => false
            };

        // macOS ではリサイズ中に glfwPollEvents がブロックされるため、
        // フレームバッファサイズ変更コールバックで再描画を行う
        discard GLFW.glfwSetFramebufferSizeCallback(window, new GLFWFramebufferSizeCallbackI {
            def invoke(_this: GLFWFramebufferSizeCallbackI, cbWindow: Int64, width: Int32, height: Int32): Unit \ IO = {
                let (sprites, tileMaps, polygons) = Array.get(0, renderStateHolder);
                RenderFrame.renderFrameMixed(spriteShader, tileShader, vao, registry,
                                 config#clearColor, screenW, screenH,
                                 width, height, sprites, tileMaps, polygons, polyVao, polyVbo);
                GLFW.glfwSwapBuffers(cbWindow)
            }
        });

        let result = run {
            f()
        } with handler GameEngine.Audio {
            def playAudio(name, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourceStop(src); AL10.alSourcePlay(src)
                    case None      => ()
                };
                k(())
            }
            def stopAudio(name, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourceStop(src)
                    case None      => ()
                };
                k(())
            }
            def setVolume(name, volume, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourcef(src, AL10.AL_GAIN, volume)
                    case None      => ()
                };
                k(())
            }
            def setLooping(name, loop, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) =>
                        let v = if (loop) AL10.AL_TRUE else AL10.AL_FALSE;
                        AL10.alSourcei(src, AL10.AL_LOOPING, v)
                    case None      => ()
                };
                k(())
            }
        } with handler GameEngine.Game {
            def renderCommands(sprites, tileMaps, polygons, k) = {
                Array.put((sprites, tileMaps, polygons), 0, renderStateHolder);
                let stack = MemoryStack.stackPush();
                let wBuf = stack.mallocInt(1);
                let hBuf = stack.mallocInt(1);
                GLFW.glfwGetFramebufferSize(window, wBuf, hBuf);
                let fbW = wBuf.get(0);
                let fbH = hBuf.get(0);
                discard MemoryStack.stackPop();
                RenderFrame.renderFrameMixed(spriteShader, tileShader, vao, registry,
                                 config#clearColor, screenW, screenH, fbW, fbH,
                                 sprites, tileMaps, polygons, polyVao, polyVbo);
                GLFW.glfwSwapBuffers(window);
                k(())
            }
            def initTileBuffer(instances, k) = {
                let instanceVBO = RenderSprite.buildTileInstanceVBO(instances);
                let tileVao = RenderSprite.buildTileMapVAO(quadVBO, instanceVBO);
                k((tileVao, List.length(instances)))
            }
            def shouldClose(k) = {
                // glfwPollEvents の **直前** に PRESS フラグをリセット。
                // poll 中に発火した callback が立てたフラグが、その後の
                // `isMouseButtonPressed` 経路で 1 フレーム間だけ true として読まれ、
                // 次フレーム冒頭でクリアされる。
                Array.put(false, 0, mouseButtonPressedHolder);
                Array.put(false, 1, mouseButtonPressedHolder);
                Array.put(false, 2, mouseButtonPressedHolder);
                GLFW.glfwPollEvents();
                // ゲームパッド状態を 1 フレーム 1 回更新（接続かつ gamepad マッピング有効時のみ）。
                let padConnected = GLFW.glfwJoystickIsGamepad(GLFW.GLFW_JOYSTICK_1);
                if (padConnected) discard GLFW.glfwGetGamepadState(GLFW.GLFW_JOYSTICK_1, gamepadState) else ();
                Array.put(padConnected, 0, gamepadConnectedHolder);
                k(GLFW.glfwWindowShouldClose(window))
            }
            def getDeltaTime(k) = {
                let currentTime = System.nanoTime();
                let prev = Array.get(0, timeHolder);
                Array.put(currentTime, 0, timeHolder);
                let dtNanos = currentTime - prev;
                let dtSec = Int64.toFloat64(dtNanos) / 1000000000.0;
                let clamped = Float64.min(dtSec, config#maxDeltaTime);
                k(clamped |> Duration.seconds)
            }
            def isKeyPressed(key, k) = {
                let code = keyToGlfw(key);
                let kb = GLFW.glfwGetKey(window, code) == 1;
                // キーボード OR ゲームパッド。エッジ検出は Scene 側 (prevKeyState) が行うため
                // ここでは押下状態を返すだけでよい。
                k(kb or padPressed(key))
            }
            def getMousePosition(k) = {
                let mStack = MemoryStack.stackPush();
                let xBuf = mStack.mallocDouble(1);
                let yBuf = mStack.mallocDouble(1);
                GLFW.glfwGetCursorPos(window, xBuf, yBuf);
                let cursorX = xBuf.get(0);
                let cursorY = yBuf.get(0);
                discard MemoryStack.stackPop();
                // ウィンドウサイズからデザイン座標に変換
                let wStack = MemoryStack.stackPush();
                let winW = wStack.mallocInt(1);
                let winH = wStack.mallocInt(1);
                GLFW.glfwGetWindowSize(window, winW, winH);
                let windowW = Int32.toFloat64(winW.get(0));
                let windowH = Int32.toFloat64(winH.get(0));
                discard MemoryStack.stackPop();
                let designX = cursorX / windowW * screenW;
                let designY = cursorY / windowH * screenH;
                k({x = designX, y = designY})
            }
            def isMouseButtonPressed(button, k) = {
                let code = mouseButtonToGlfw(button);
                // 物理状態 OR 当フレーム内に callback が観測した PRESS。
                let polled = GLFW.glfwGetMouseButton(window, code) == 1;
                let buffered = Array.get(code, mouseButtonPressedHolder);
                k(polled or buffered)
            }
            def consumeScrollDelta(k) = {
                let v = Array.get(0, scrollDeltaHolder);
                Array.put(0.0, 0, scrollDeltaHolder);
                k(v)
            }
            def getFontAtlas(name, k) = {
                match Map.get(name, fontAtlases) {
                    case Some(atlas) => k(atlas)
                    case None => bug!("Font atlas not found: ${name}")
                }
            }
            def getViewportRect(k) = {
                k({position = Vec2.zero(), size = {x = screenW, y = screenH}})
            }
            def getTextureInfo(name, k) = {
                k(Map.get(name, registry))
            }
            def setCursor(cursor, k) = {
                let prev = Array.get(0, lastCursorHolder);
                if (prev != cursor) {
                    GLFW.glfwSetCursor(window, cursorOf(cursor));
                    Array.put(cursor, 0, lastCursorHolder)
                } else ();
                k(())
            }
        };

        // セッション終了時にカーソルハンドルを開放
        GLFW.glfwDestroyCursor(arrowCursor);
        GLFW.glfwDestroyCursor(hResizeCursor);
        GLFW.glfwDestroyCursor(vResizeCursor);
        GLFW.glfwDestroyCursor(allResizeCursor);
        GLFW.glfwDestroyCursor(nwseResizeCursor);
        GLFW.glfwDestroyCursor(neswResizeCursor);

        // OpenAL cleanup
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);

        Callbacks.glfwFreeCallbacks(window);
        GLFW.glfwDestroyWindow(window);
        GLFW.glfwTerminate();
        result
}
