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
// 入力 (キー / マウス / ホイール) は AwtInput モジュールに装着した AWT listener から
// Ref に流れ込み、GameEngine.Game effect の handler が読み取る

mod SwingLayer {
    import java.lang.{Thread => JThread}
    import javax.swing.JFrame
    import javax.swing.{Timer => SwingTimer}
    import java.awt.event.WindowAdapter
    import java.awt.event.WindowEvent
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import java.awt.event.HierarchyListener
    import java.awt.event.HierarchyEvent
    import java.awt.event.ComponentAdapter
    import java.awt.event.ComponentEvent
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

    /// customizeFrame は JFrame に対する UI 構築をすべて呼び出し側に委譲するためのフック。
    /// SwingLayer が呼ぶタイミング: AWTGLCanvas 生成・GLData パッチ・JFrame 生成・
    /// WindowListener 装着が済んだ後、setVisible(true) する前。
    /// 呼び出し側はここで:
    ///   - canvas を frame のレイアウト (BorderLayout.CENTER 等) に add する
    ///   - frame.setSize / setLayout でウィンドウサイズ・配置を設定する
    ///   - JMenuBar や sidebar JPanel を frame に取り付ける
    /// を行う。canvas を frame にどう配置するかは IDE 側のレイアウト責務。
    pub def withSwing(config: GameEngine.EngineConfig,
                      customizeFrame: (JFrame, AWTGLCanvas) -> Unit \ IO,
                      f: Unit -> a \ ef):
            a \ ef - GameEngine.Game - GameEngine.Audio + IO + Chan + NonDet =
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
        let inputRefs = AwtInput.newInputRefs();

        // initGL の完了通知用 Channel。Java method override 内では Chan effect を
        // 直接持ち込めないため、initGL は initDoneArr に true を書くだけで、
        // 別 spawn の watcher (Flix scope = Chan + NonDet が許される) がフラグを観測して
        // 1 度だけ channel に signal を流す。main thread は recv でブロックする
        let (initTx, initRx) = Channel.buffered(1);

        let screenW = Int32.toFloat64(config#designWidth);
        let screenH = Int32.toFloat64(config#designHeight);
        let designSize = {width = screenW, height = screenH};

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
        // canvas の preferred size は設定しない。
        // BorderLayout.CENTER などのレイアウトに add された際に親コンテナのスペースを
        // フルに使う。renderFrameMixed が design/window アスペクト比から viewport を
        // 計算し、letterbox/pillarbox で正しい比率を保つ。
        println("[SwingLayer] AWTGLCanvas created; patching GLData for GL 3.3 Core...");
        // canvas が継承する protected final GLData data フィールドを reflection で取り、
        // その GLData のフィールド (public 非 final) を書き換える。
        patchCanvasGLDataToCore33(canvas);
        println("[SwingLayer] GLData patched");
        // AWT MouseListener / MouseMotionListener / KeyListener を装着し、
        // 入力イベントを inputRefs に流す
        AwtInput.attachListeners(canvas, inputRefs);

        // ----- JFrame セットアップ -----
        // SwingLayer は基本的なフレーム生成と WindowListener 装着だけを担当し、
        // 実際の UI 配置 (canvas をどこに add するか、メニュー、サイズ等) は
        // customizeFrame コールバックに委譲する。
        println("[SwingLayer] Creating JFrame...");
        let frame = new JFrame(config#title);
        frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        frame.addWindowListener(new WindowAdapter {
            def windowClosing(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
                Array.put(true, 0, shouldCloseArr)
            def windowClosed(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
                Array.put(true, 0, shouldCloseArr)
        });
        println("[SwingLayer] Calling customizeFrame...");
        customizeFrame(frame, canvas);
        println("[SwingLayer] Calling frame.setVisible(true)...");
        frame.setVisible(true);
        println("[SwingLayer] frame.setVisible returned");

        // ----- SwingTimer による render 駆動 (16ms ≈ 60Hz) -----
        // 以前は spawn でスレッドを切って canvas.render() を回していたが、Flix の spawn は
        // virtual thread を作るため、macOS の JAWT (canvas の native peer 取得) が
        // carrier thread を unmount された瞬間に SIGBUS で落ちる事例があった。
        // SwingTimer のコールバックは EDT (Swing の OS スレッド) で実行されるので、
        // JAWT が要求する安定したカーネルスレッドの上で確実に動く。
        //
        // 起動タイミング:
        //   AWTGLCanvas は次の 3 条件が揃った後でないと最初の render() が成功しない:
        //     (1) isDisplayable() — peer 構築済み
        //     (2) isShowing()     — 親 frame の visible が伝播済み
        //     (3) getWidth() > 0  — レイアウトが流れて canvas に実寸が割り当て済み
        //   特に (3) は macOS でしばしば遅れて確定する。サイズ 0 のまま render() を呼ぶと
        //   lwjgl3-awt の `initCalled` フラグが立った後で GL コンテキストが無効化されたまま
        //   固着し、その後ずっと paintGL が白いままになる事象が観測されている。
        //   HierarchyListener (showing/displayability 遷移) と ComponentListener (resize)
        //   の両方を装着し、いずれかが発火するたびに条件チェックして 1 度だけ start する
        let timerStartedArr = Array#{false} @ Static;
        let tryStartRenderTimer = () -> {
            if (Array.get(0, timerStartedArr)) ()
            else if (canvas.isDisplayable() and canvas.isShowing()
                     and canvas.getWidth() > 0i32 and canvas.getHeight() > 0i32) {
                // 重複起動を防ぐため先にフラグを立てる
                Array.put(true, 0, timerStartedArr);
                println("[SwingLayer] Canvas peer + size ready (${canvas.getWidth()}x${canvas.getHeight()}); starting SwingTimer");
                let renderTimer = new SwingTimer(16i32, new ActionListener {
                    def actionPerformed(_this: ActionListener, _e: ActionEvent): Unit \ IO = {
                        if (Array.get(0, shouldCloseArr)) ()
                        else if (canvas.isValid()
                                 and canvas.getWidth() > 0i32
                                 and canvas.getHeight() > 0i32)
                            canvas.render()
                        else ()
                    }
                });
                renderTimer.start()
            } else ()
        };

        canvas.addHierarchyListener(new HierarchyListener {
            def hierarchyChanged(_this: HierarchyListener, _e: HierarchyEvent): Unit \ IO =
                tryStartRenderTimer()
        });
        // resize / shown が後追いで発火するケース (macOS でしばしば発生) を拾う
        canvas.addComponentListener(new ComponentAdapter {
            def componentResized(_this: ComponentAdapter, _e: ComponentEvent): Unit \ IO =
                tryStartRenderTimer()
            def componentShown(_this: ComponentAdapter, _e: ComponentEvent): Unit \ IO =
                tryStartRenderTimer()
        });

        // 既に peer 確定済み (setVisible 後に hierarchyChanged が既に飛んだ後) の
        // ケースに備えて 1 度試す。各 listener とどちらが先でもフラグで重複排除
        tryStartRenderTimer();
        println("[SwingLayer] Render timer arming; waiting for initGL...");

        // ----- initGL の完了通知 spawn -----
        // initDoneArr を観測して true になったら一度だけ Channel.send する。
        // HotReload.startWatcher と同じパターン。
        // spawn の中なので Chan + NonDet effect が使える
        spawn {
            initSignalWatcher(initDoneArr, initTx)
        } @ Static;

        // ----- initGL の完了を待つ (f が描画リソースを前提に書かれているため) -----
        // default 節なしの select は recv が signal を受け取るまでブロックする。
        // HotReload.pollReload が select default で非ブロッキングなのと対称的な使い方
        select {
            case _ <- recv(initRx) => ()
        };
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
            // 入力系は AwtInput が AWT listener から流し込んだ Ref を読み取る
            def isKeyPressed(key, k) = k(AwtInput.readKeyPressed(inputRefs, key))
            def getMousePosition(k) = k(AwtInput.readMousePosition(inputRefs, canvas, designSize))
            def isMouseButtonPressed(button, k) = k(AwtInput.readMouseButtonPressed(inputRefs, button))
            def consumeScrollDelta(k) = k(AwtInput.consumeScrollDelta(inputRefs))
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
            def setCursor(cursor, k) = {
                AwtInput.applyCursor(inputRefs, canvas, cursor);
                k(())
            }
        };

        // ----- クリーンアップ -----
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);
        result

    /// initDoneArr を 20ms 周期で観測し、true になった瞬間に channel に 1 回だけ
    /// signal を送って終了する。main thread の `Channel.recv` がそれを受け取って
    /// ブロックを解除する。
    /// HotReload と同じ「spawn 内で Chan effect を使う」パターンで、initGL (Java method
    /// override = IO 固定) から effect 境界を越えて signal を渡す手段になる
    def initSignalWatcher(initDoneArr: Array[Bool, Static],
                           tx: Sender[Unit]): Unit \ {Chan, IO} =
        if (Array.get(0, initDoneArr))
            Channel.send((), tx)
        else {
            JThread.sleep(20i64);
            initSignalWatcher(initDoneArr, tx)
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
