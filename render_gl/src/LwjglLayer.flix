// LwjglLayer — ウィンドウ表示・入力の読み取り・音の再生を実機で受け持ち、GameEngine.Game / Audio の
// effect ハンドラを提供する。ゲーム側はこの窓口越しに描画や入力を頼むだけで、GL や OpenAL の
// 細部を知らずに済む。
// 利用例: `withLwjgl(config, ...)` でウィンドウを開き、ゲームループを回す。
// 注意: GL / OpenAL / シェーダ / テクスチャ / フォントベイク / フレーム描画 / 音声デコードは
//   同じ render_gl 内の各 mod（Render / Shader / Texture / Font / Frame / Audio 等）にあり、
//   このファイルは GLFW 外周だけを持って各 effect の本体から呼ぶ。
//   `withLwjgl` の第1引数 EngineConfig と戻り値の effect 制約は公開 API として固定（ゲーム側を変えずに済む）。

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
    import java.lang.Exception
    import java.lang.Math
    import java.awt.BasicStroke
    import java.awt.{Color => AwtColor}
    import java.awt.image.BufferedImage
    import java.io.File
    import java.io.FileWriter
    import java.time.LocalDateTime
    import java.time.format.DateTimeFormatter
    import javax.imageio.ImageIO

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
        case GameEngine.Key.H         => 72
        case GameEngine.Key.Up        => 265
        case GameEngine.Key.Down      => 264
        case GameEngine.Key.Left      => 263
        case GameEngine.Key.Right     => 262
        case GameEngine.Key.Enter     => 257
        case GameEngine.Key.Space     => 32
        case GameEngine.Key.Escape    => 256
        case GameEngine.Key.F1        => 290
        case GameEngine.Key.F8        => 297
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
        case GameEngine.Cursor.Crosshair  => 0x36003  // GLFW_CROSSHAIR_CURSOR
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
    // 注釈の書き出し（saveAnnotation ハンドラの下請け）
    // ========================================================================

    /// タイトルをディレクトリ名に使える形へ整える（英数字以外は "_" に置換）。
    def sanitizeName(name: String): String =
        name |> String.map(c -> if (Char.isLetter(c) or Char.isDigit(c)) c else '_')

    /// 四捨五入で Int32 へ（非負前提。注釈矩形の px 変換用）。
    def roundToInt(v: Float64): Int32 =
        Float64.tryToInt32(v + 0.5) |> Option.getWithDefault(0)

    /// 現在のフレームバッファを読み出して画像にする。GL は左下原点なので
    /// 上下を反転しながら RGBA → RGB へ詰め替える。
    def framebufferImage(fbW: Int32, fbH: Int32): BufferedImage \ IO =
        region rc {
            let buf = MemoryUtil.memAlloc(fbW * fbH * 4);
            GL11.glReadPixels(0, 0, fbW, fbH, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, buf);
            let image = new BufferedImage(fbW, fbH, 1i32);
            let pixels: Array[Int32, rc] = Array.empty(rc, fbW * fbH);
            let xs = List.range(0, fbW);
            List.forEach(y -> {
                let srcRowStart = (fbH - 1 - y) * fbW;
                List.forEach(x -> {
                    let src = (srcRowStart + x) * 4;
                    let r = Int32.bitwiseAnd(Int8.toInt32(buf.get(src)), 255);
                    let g = Int32.bitwiseAnd(Int8.toInt32(buf.get(src + 1)), 255);
                    let b = Int32.bitwiseAnd(Int8.toInt32(buf.get(src + 2)), 255);
                    Array.put(r * 65536 + g * 256 + b, y * fbW + x, pixels)
                }, xs)
            }, List.range(0, fbH));
            MemoryUtil.memFree(buf);
            image.setRGB(0, 0, fbW, fbH, pixels, 0, fbW);
            image
        }

    /// デザイン座標の矩形を、書き出し画像（左上原点）上の px 矩形へ変換する。
    /// 黒帯（レターボックス / ピラーボックス）ぶんのオフセットも織り込む。
    def designRectToImage(rect: Rect2.Rect2, fbW: Int32, fbH: Int32,
                          designW: Float64, designH: Float64): {x = Int32, y = Int32, w = Int32, h = Int32} =
        let (vpX, vpY, vpW, vpH) = RenderFrame.calcViewport(fbW, fbH, designW, designH);
        let sx = Int32.toFloat64(vpW) / designW;
        let sy = Int32.toFloat64(vpH) / designH;
        // glViewport の vpY は下端基準。上下反転済みの画像では上端 = fbH - vpY - vpH
        let topOffset = fbH - vpY - vpH;
        { x = vpX + roundToInt(rect#position#x * sx),
          y = topOffset + roundToInt(rect#position#y * sy),
          w = roundToInt(rect#size#x * sx),
          h = roundToInt(rect#size#y * sy) }

    /// 画像に注釈矩形の赤枠を焼き込む（人間が見てすぐ分かる用。書き込み先は上書き）。
    def burnHighlight(image: BufferedImage, rectPx: {x = Int32, y = Int32, w = Int32, h = Int32}): Unit \ IO =
        let g = image.createGraphics();
        g.setColor(new AwtColor(255, 32, 32));
        g.setStroke(new BasicStroke(3.0f32));
        g.drawRect(rectPx#x, rectPx#y, rectPx#w, rectPx#h);
        g.dispose()

    /// 画像を PNG として書く（親ディレクトリは呼び側が作成済み）。
    def writePngFile(image: BufferedImage, path: String): Unit \ IO =
        discard ImageIO.write(image, "png", new File(path))

    /// テキストをファイルに書く。
    def writeTextFile(path: String, content: String): Unit \ IO =
        let writer = new FileWriter(path);
        writer.write(content);
        writer.close()

    /// カメラのシャッター風の短い効果音を合成して OpenAL のソースにする。
    /// 音の形: 硬い立ち上がりのノイズがすぐ減衰（幕が走る）→ 少し遅れて小さな
    /// ノイズがもう 1 発（幕が戻る）。注釈の保存が成功したときに鳴らす。
    def buildShutterSource(): Int32 \ IO =
        let rate = 44100;
        let sampleCount = rate * 15 / 100;  // 0.15 秒
        let buf = MemoryUtil.memAlloc(sampleCount * 2);
        def fill(i: Int32, seed: Int32): Unit \ IO = {
            if (i >= sampleCount) ()
            else {
                // 線形合同法の白色ノイズ（-1.0〜1.0）
                let nextSeed = seed * 1103515245 + 12345;
                let noise = Int32.toFloat64(Int32.remainder(nextSeed, 10000)) / 10000.0;
                let t = Int32.toFloat64(i) / Int32.toFloat64(rate);
                // 1 発目: 0 秒から 12ms で減衰 / 2 発目: 70ms から 20ms で減衰・小さめ
                let env1 = Math.exp(0.0 - t / 0.012);
                let env2 = if (t > 0.07) Math.exp(0.0 - (t - 0.07) / 0.02) * 0.55 else 0.0;
                let sample = noise * (env1 + env2) * 0.5;
                let s16 = Float64.tryToInt32(sample * 32000.0)
                    |> Option.getWithDefault(0)
                    |> Int32.tryToInt16
                    |> Option.getWithDefault(0i16);
                buf.putShort(i * 2, s16);
                fill(i + 1, nextSeed)
            }
        };
        fill(0, 20260710);
        let alBuffer = AL10.alGenBuffers();
        AL10.alBufferData(alBuffer, AL10.AL_FORMAT_MONO16, buf, rate);
        MemoryUtil.memFree(buf);
        let source = AL10.alGenSources();
        AL10.alSourcei(source, AL10.AL_BUFFER, alBuffer);
        source

    /// README.md の全文（見出し・画像埋め込み・要約・リンク・コメント欄）を組み立てる。
    def readmeText(args: {title = String, stamp = String, frame = Int64, body = String}): String =
        "# 注釈: ${args#title} — frame ${args#frame}（${args#stamp}）\n\n"
        + "![highlighted](highlighted.png)\n\n"
        + "${args#body}\n\n"
        + "- 機械可読データ: [annotation.json](annotation.json)\n"
        + "- 素のフレーム: [screenshot.png](screenshot.png)\n\n"
        + "## コメント\n\n"
        + "（ここに修正指示を書いてください）\n"

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
        // GLFW と AWT は macOS で同じメインスレッド・GL を取り合って固まるため、
        // この窓（GLFW）のプロセスでは AWT を headless に固定する。注釈のスクリーンショット
        // 保存（BufferedImage / Graphics2D / ImageIO）はオフスクリーン描画なので headless でも動く。
        discard System.setProperty("java.awt.headless", "true");
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

        // GL リソース構築は各描画 mod（RenderShader 等）に委譲
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
        // 注釈保存時のシャッター音（合成なのでゲーム側の音声マニフェストに依存しない）
        let shutterSource = buildShutterSource();
        println("  Audio ready");

        let timeHolder = Array#{System.nanoTime()} @ Static;

        // リサイズ中の再描画用に最後のフレームの描画コマンドを保持する (sprites + tileMaps + polygons)
        let renderStateHolder = Array#{((Nil: List[GameEngine.Drawable]),
                                         (Nil: List[GameEngine.TileMapRenderCmd]),
                                         (Nil: List[GameEngine.PolygonRenderCmd]))} @ Static;

        // 6 種のスタンダードカーソルを起動時に作成して再利用する。
        // setCursor 呼び出しの度に都度作成 / 破棄すると重く、リーク源にもなる
        let arrowCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Default));
        let crosshairCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Crosshair));
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
            case GameEngine.Cursor.Crosshair  => crosshairCursor
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
                RenderFrame.renderFrameMixed({
                    spriteShader = spriteShader, tileShader = tileShader, vao = vao,
                    registry = registry, clearColor = config#clearColor,
                    designW = screenW, designH = screenH, fbW = width, fbH = height,
                    sprites = sprites, tileMaps = tileMaps, polygons = polygons,
                    polyVao = polyVao, polyVbo = polyVbo});
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
                RenderFrame.renderFrameMixed({
                    spriteShader = spriteShader, tileShader = tileShader, vao = vao,
                    registry = registry, clearColor = config#clearColor,
                    designW = screenW, designH = screenH, fbW = fbW, fbH = fbH,
                    sprites = sprites, tileMaps = tileMaps, polygons = polygons,
                    polyVao = polyVao, polyVbo = polyVbo});
                GLFW.glfwSwapBuffers(window);
                k(())
            }
            def initTileBuffer(instances, k) = {
                let instanceVBO = RenderSprite.buildTileInstanceVBO(instances);
                let tileVao = RenderSprite.buildTileMapVAO(quadVBO, instanceVBO);
                k((GpuHandle.wrapTileVao(tileVao), List.length(instances)))
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
            def saveAnnotation(req, k) = {
                let saved = try {
                    let now = LocalDateTime.now();
                    let dirStamp = now.format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
                    let readableStamp = now.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
                    let dirPath = "debug/annotations/${dirStamp}_${sanitizeName(config#title)}_f${req#frame}";
                    discard (new File(dirPath)).mkdirs();
                    // 等倍のフレームを back buffer に描き直して読む。swap しないので画面には
                    // 映らず、次のフレーム描画がそのまま上書きする。
                    let stack = MemoryStack.stackPush();
                    let wBuf = stack.mallocInt(1);
                    let hBuf = stack.mallocInt(1);
                    GLFW.glfwGetFramebufferSize(window, wBuf, hBuf);
                    let fbW = wBuf.get(0);
                    let fbH = hBuf.get(0);
                    discard MemoryStack.stackPop();
                    RenderFrame.renderFrameMixed({
                        spriteShader = spriteShader, tileShader = tileShader, vao = vao,
                        registry = registry, clearColor = config#clearColor,
                        designW = screenW, designH = screenH, fbW = fbW, fbH = fbH,
                        sprites = req#sprites, tileMaps = req#tileMaps,
                        polygons = req#polygons, polyVao = polyVao, polyVbo = polyVbo});
                    let image = framebufferImage(fbW, fbH);
                    writePngFile(image, "${dirPath}/screenshot.png");
                    burnHighlight(image, designRectToImage(req#rect, fbW, fbH, screenW, screenH));
                    writePngFile(image, "${dirPath}/highlighted.png");
                    writeTextFile("${dirPath}/annotation.json", req#json);
                    if (req#worldDump != "")
                        writeTextFile("${dirPath}/world.json", req#worldDump)
                    else ();
                    writeTextFile("${dirPath}/README.md",
                        readmeText({title = config#title, stamp = readableStamp,
                                    frame = req#frame, body = req#readmeBody}));
                    println("annotation saved: ${dirPath}");
                    AL10.alSourceStop(shutterSource);
                    AL10.alSourcePlay(shutterSource);
                    Some(dirPath)
                } catch {
                    case ex: Exception =>
                        println("annotation save failed: ${ex.getMessage()}");
                        None
                };
                k(saved)
            }
            def setDebugBadge(enabled, k) = {
                let title = if (enabled) "${config#title} (Debug)" else config#title;
                GLFW.glfwSetWindowTitle(window, title);
                k(())
            }
        };

        // セッション終了時にカーソルハンドルを開放
        GLFW.glfwDestroyCursor(arrowCursor);
        GLFW.glfwDestroyCursor(crosshairCursor);
        GLFW.glfwDestroyCursor(hResizeCursor);
        GLFW.glfwDestroyCursor(vResizeCursor);
        GLFW.glfwDestroyCursor(allResizeCursor);
        GLFW.glfwDestroyCursor(nwseResizeCursor);
        GLFW.glfwDestroyCursor(neswResizeCursor);

        // OpenAL cleanup
        AL10.alDeleteSources(shutterSource);
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);

        Callbacks.glfwFreeCallbacks(window);
        GLFW.glfwDestroyWindow(window);
        GLFW.glfwTerminate();
        result
}
