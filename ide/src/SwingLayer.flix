// SwingLayer — JFrame + AWTGLCanvas で GameEngine.Game / GameEngine.Audio
// effect を実装する handler。LwjglLayer.withLwjgl と同じシグネチャ。
//
// 構造:
//   - JFrame に AWTGLCanvas を埋め込む
//   - initGL (canvas.render() の中で 1 度だけ呼ばれる) で render_core の GL
//     リソース (シェーダ・スプライト VAO・テクスチャ・フォント) を初期化する
//   - paintGL は最新の renderCommands を Ref から取って renderFrameMixed を呼ぶ
//   - OpenAL は GL コンテキストと独立なので main thread で初期化できる
//   - 専用 render Thread が canvas.render() を 60Hz で回す
//   - withWindowAdapter で × クリックを shouldClose フラグに反映
//
// 入力 (キー / マウス) は Step C.1 ではすべて stub (常に false / 0.0)。
// Step C.2 で AWT listener から InputState Ref に流すよう拡張する予定。

mod SwingLayer {
    import java.lang.{Thread => JThread}
    import javax.swing.JFrame
    import java.awt.event.WindowAdapter
    import java.awt.event.WindowEvent
    import java.awt.Dimension
    import org.lwjgl.opengl.awt.AWTGLCanvas
    import org.lwjgl.opengl.awt.GLData
    import org.lwjgl.opengl.GL
    import org.lwjgl.opengl.GL11
    import org.lwjgl.openal.AL
    import org.lwjgl.openal.AL10
    import org.lwjgl.openal.ALC
    import org.lwjgl.openal.ALC10
    import org.lwjgl.system.MemoryUtil
    import java.lang.System
    import java.lang.Integer
    import java.lang.reflect.Field

    pub def withSwing(config: GameEngine.EngineConfig, f: Unit -> a \ ef): a \ ef - GameEngine.Game - GameEngine.Audio + IO =
        // ----- 状態 Ref (initGL の中で書き込み、paintGL / handler で読む) -----
        let spriteShaderArr = Array#{0i32} @ Static;
        let tileShaderArr   = Array#{0i32} @ Static;
        let vaoArr          = Array#{0i32} @ Static;
        let quadVBOArr      = Array#{0i32} @ Static;
        let registryArr = Array#{(Map.empty(): RenderAsset.TextureRegistry)} @ Static;
        let fontAtlasesArr = Array#{(Map.empty(): Map[String, FontAtlas])} @ Static;
        let renderStateArr =
            Array#{((Nil: List[GameEngine.Drawable]),
                    (Nil: List[GameEngine.TileMapRenderCmd]))} @ Static;
        let initDoneArr  = Array#{false} @ Static;
        let shouldCloseArr = Array#{false} @ Static;

        let screenW = Int32.toFloat64(config#designWidth);
        let screenH = Int32.toFloat64(config#designHeight);

        // ----- OpenAL 初期化 (GL コンテキストと独立なので main thread で OK) -----
        println("[SwingLayer] Initializing audio...");
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
        let audioRegistry = RenderAudio.loadAudioRegistry(config#soundManifest);
        println("[SwingLayer] Audio ready");

        // ----- AWTGLCanvas: initGL で render_core を初期化、paintGL で描画 -----
        // AWTGLCanvas のコンストラクタは protected で Flix から直接 GLData 引数版を
        // 呼べないため、no-arg で生成してから内部の data フィールドの public フィールド
        // を reflection で書き換えて OpenGL 3.3 Core Profile を要求する。
        println("[SwingLayer] Creating AWTGLCanvas...");
        let canvas = new AWTGLCanvas {
            def initGL(_this: AWTGLCanvas): Unit \ IO = {
                println("[SwingLayer] initGL: GL.createCapabilities + render_core init");
                discard GL.createCapabilities();
                GL11.glEnable(GL11.GL_BLEND);
                GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

                let spriteShader = RenderShader.createShaderProgram(
                    RenderShader.vertexShaderSource(),
                    RenderShader.fragmentShaderSource());
                RenderShader.setProjectionMatrix(spriteShader, screenW, screenH);

                let tileShader = RenderShader.createShaderProgram(
                    RenderShader.tileVertexShaderSource(),
                    RenderShader.tileFragmentShaderSource());
                RenderShader.setProjectionMatrix(tileShader, screenW, screenH);

                let (vao, quadVBO) = RenderSprite.initSpriteRenderer();

                println("[SwingLayer] Loading textures...");
                let registry0 = RenderTexture.loadTextureRegistry(config#textureManifest);
                println("[SwingLayer] Baking font atlases...");
                let (fontAtlases, registry) = RenderFont.bakeFontAtlases(config#fontManifest, registry0);

                Array.put(spriteShader, 0, spriteShaderArr);
                Array.put(tileShader,   0, tileShaderArr);
                Array.put(vao,          0, vaoArr);
                Array.put(quadVBO,      0, quadVBOArr);
                Array.put(registry,     0, registryArr);
                Array.put(fontAtlases,  0, fontAtlasesArr);
                Array.put(true,         0, initDoneArr);
                println("[SwingLayer] render_core ready")
            }
            def paintGL(this: AWTGLCanvas): Unit \ IO = {
                if (Array.get(0, initDoneArr)) {
                    let spriteShader = Array.get(0, spriteShaderArr);
                    let tileShader   = Array.get(0, tileShaderArr);
                    let vao          = Array.get(0, vaoArr);
                    let registry     = Array.get(0, registryArr);
                    let (sprites, tileMaps) = Array.get(0, renderStateArr);
                    let fbW = this.getFramebufferWidth();
                    let fbH = this.getFramebufferHeight();
                    RenderFrame.renderFrameMixed(spriteShader, tileShader, vao, registry,
                        config#clearColor, screenW, screenH, fbW, fbH, sprites, tileMaps);
                    this.swapBuffers()
                } else ()
            }
        };
        canvas.setPreferredSize(new Dimension(config#windowWidth, config#windowHeight));
        println("[SwingLayer] AWTGLCanvas created; patching GLData for GL 3.3 Core...");
        // canvas が継承する protected final GLData data フィールドを reflection で取り、
        // その GLData のフィールド (public 非 final) を書き換える。
        patchCanvasGLDataToCore33(canvas);
        println("[SwingLayer] GLData patched");

        // ----- JFrame セットアップ -----
        println("[SwingLayer] Creating JFrame...");
        let frame = new JFrame(config#title);
        frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        frame.add(canvas);
        frame.pack();
        frame.addWindowListener(new WindowAdapter {
            def windowClosing(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
                Array.put(true, 0, shouldCloseArr)
            def windowClosed(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
                Array.put(true, 0, shouldCloseArr)
        });
        println("[SwingLayer] Calling frame.setVisible(true)...");
        frame.setVisible(true);
        println("[SwingLayer] frame.setVisible returned");

        // ----- 専用 render Thread: AWTGLCanvas.render() を 60Hz 駆動 -----
        // 起動直後は AWT peer 構築待ちで isValid が false の可能性があるため、
        // 200ms 待ってから loop に入る
        println("[SwingLayer] Spawning render thread...");
        spawn {
            JThread.sleep(200i64);
            renderLoop(canvas, shouldCloseArr)
        } @ Static;
        println("[SwingLayer] Render thread spawned, waiting for initGL...");

        // ----- initGL の完了を待つ (f が描画リソースを前提に書かれているため) -----
        waitForInit(initDoneArr);
        println("[SwingLayer] initGL completed, starting user code");

        let timeHolder = Array#{System.nanoTime()} @ Static;

        // ----- effect handler を installしてユーザコードを実行 -----
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
        } with handler GameEngine.Game {
            // renderCommands は paintGL が読む Ref に書き込むだけ。
            // 実際の glDraw* は render thread の paintGL で実行される。
            def renderCommands(sprites, tileMaps, k) = {
                Array.put((sprites, tileMaps), 0, renderStateArr);
                k(())
            }
            // GL コンテキストが render thread 側にあるため、ここから直接 VBO を
            // 作ることができない。Step C.1 では TileMap 未対応 (dummy 返却) とし、
            // 次フェーズで paintGL 経由のキュー機構を入れる。
            def initTileBuffer(_instances, k) = {
                k((0, 0))
            }
            def shouldClose(k) = {
                k(Array.get(0, shouldCloseArr))
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
            // 入力系は Step C.1 ではすべて stub。Step C.2 で AWT listener 経由に。
            def isKeyPressed(_key, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_button, k) = k(false)
            def consumeScrollDelta(k) = k(0.0)
            def getFontAtlas(name, k) = {
                let atlases = Array.get(0, fontAtlasesArr);
                match Map.get(name, atlases) {
                    case Some(atlas) => k(atlas)
                    case None => bug!("Font atlas not found: ${name}")
                }
            }
            def getViewportRect(k) = {
                k({position = Vec2.zero(), size = {x = screenW, y = screenH}})
            }
            def getTextureInfo(name, k) = {
                k(Map.get(name, Array.get(0, registryArr)))
            }
            def setCursor(_cursor, k) = k(())
        };

        // ----- クリーンアップ -----
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);
        result

    def renderLoop(canvas: AWTGLCanvas, shouldCloseArr: Array[Bool, Static]): Unit \ IO =
        if (Array.get(0, shouldCloseArr)) ()
        else {
            if (canvas.isValid()) {
                canvas.render()
            } else ();
            JThread.sleep(16i64);
            renderLoop(canvas, shouldCloseArr)
        }

    def waitForInit(initDoneArr: Array[Bool, Static]): Unit \ IO =
        if (Array.get(0, initDoneArr)) ()
        else {
            JThread.sleep(20i64);
            waitForInit(initDoneArr)
        }

    // ========================================================================
    // AWTGLCanvas の継承する protected final GLData data フィールドを reflection で
    // 取り出し、その public フィールドを OpenGL 3.3 Core Profile に書き換える。
    //
    // AWTGLCanvas のコンストラクタは protected なので Flix からは no-arg バージョン
    // (内部で `this(new GLData())` を呼ぶ) しか呼べない。new GLData() はデフォルト値
    // のため何もしないと macOS では legacy OpenGL 2.1 Compatibility が選ばれる。
    // canvas.render() (= beforeRender 内で platformCanvas.create(this, data, ...) を呼ぶ)
    // が走るまでに data の値を更新すれば、生成される GL コンテキストは 3.3 Core になる。
    // ========================================================================

    def patchCanvasGLDataToCore33(canvas: AWTGLCanvas): Unit \ IO =
        // 1. canvas は AWTGLCanvas の synthetic 子クラス。data フィールドは
        //    親クラス側に declared されているので getSuperclass().getDeclaredField を使う
        let superCls = canvas.getClass().getSuperclass();
        let dataField = superCls.getDeclaredField("data");
        dataField.setAccessible(true);
        let glData = dataField.get(canvas);   // 既存の (デフォルト) GLData
        // 2. GLData の public フィールド (非 final) を更新
        let glDataCls = glData.getClass();
        glDataCls.getField("majorVersion").setInt(glData, 3);
        glDataCls.getField("minorVersion").setInt(glData, 3);
        // swapInterval は java.lang.Integer (boxed) なので set + Integer.valueOf を使う
        glDataCls.getField("swapInterval").set(glData, Integer.valueOf(1));
        glDataCls.getField("forwardCompatible").setBoolean(glData, true);
        // 3. profile (enum GLData.Profile) は CORE を設定
        let profileField = glDataCls.getField("profile");
        let profileType = profileField.getType();
        let coreField = profileType.getField("CORE");
        let coreValue = coreField.get(MemoryUtil.NULL);
        profileField.set(glData, coreValue)
}
