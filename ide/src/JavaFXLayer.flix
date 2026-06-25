// JavaFXLayer — GameEngine.Game / GameEngine.Audio effect の実装 handler。
// `withJavaFX` を main から呼ぶと JavaFX ウィンドウとレンダループが立ち上がる。
//
// 構造:
//   - AWTGLCanvas を **隠し JFrame** に置いて GL コンテキストを確保（画面外 -10000,-10000）
//   - FBO（テクスチャ color attachment）に renderFrameMixed の出力をレンダ
//   - glReadPixels で CPU ByteBuffer に転送
//   - Platform.runLater で JavaFX PixelBuffer → WritableImage を更新
//   - ImageView (setScaleY(-1) で Y 反転) を Stage に置いて表示
//   - SwingTimer (EDT 駆動) で 60Hz canvas.render() を呼ぶ
//   - 終了は Runtime.halt(0)（AWT EDT が non-daemon でフリーズするため shutdown hook 回避）
//
// AWTGLCanvas を SwingNode に入れると heavyweight + native NSView の問題で
// JavaFX scene graph に映らない（macOS で完全黒）。FBO + readback で回避する。
//
// 入力は JavaFXInput が ImageView に EventHandler を付け、InputRefs に書く。
// AWT listener は使わない（canvas が hidden で発火しない）

mod JavaFXLayer {
    import java.lang.{Thread => JThread}
    import java.lang.Integer
    import java.lang.Number
    import java.lang.Object
    import java.lang.Runnable
    import java.lang.Runtime
    import java.lang.System
    import java.nio.ByteBuffer
    import javafx.application.Platform
    import javafx.stage.Stage
    import javafx.stage.WindowEvent
    import javafx.stage.Screen
    import javafx.scene.Scene
    import javafx.scene.image.ImageView
    import javafx.scene.image.WritableImage
    import javafx.scene.image.PixelBuffer
    import javafx.scene.image.PixelFormat
    import javafx.scene.image.WritablePixelFormat
    import javafx.geometry.Rectangle2D
    import javafx.util.Callback
    import javafx.event.EventHandler
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javax.swing.JFrame
    import javax.swing.JPanel
    import javax.swing.{Timer => SwingTimer}
    import java.awt.BorderLayout
    import java.awt.event.ActionListener
    import java.awt.event.ActionEvent
    import org.lwjgl.opengl.awt.AWTGLCanvas
    import org.lwjgl.opengl.GL
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL12
    import org.lwjgl.opengl.GL30
    import org.lwjgl.openal.AL
    import org.lwjgl.openal.AL10
    import org.lwjgl.openal.ALC
    import org.lwjgl.openal.ALC10
    import org.lwjgl.system.MemoryUtil
    import org.lwjgl.BufferUtils

    /// customizeStage は FXML 読み込みと Stage への scene 設定を呼び出し側に委譲する。
    /// JavaFXLayer は WritableImage だけを生成して渡し、ImageView 自体は FXML で
    /// 宣言される (canvasView fx:id)。customize が FXML からその ImageView を取り出して
    /// setImage(initialImage) し、Layer に返却する。Layer は返却された ImageView 参照を
    /// 入力 listener や resize 時の setImage に使う。
    ///
    /// この設計で「見た目 (scaleY=-1, preserveRatio, fitWidth/Height バインド) は FXML 側、
    /// データ (WritableImage の中身) と振る舞い (入力・resize) は Flix 側」が綺麗に分離される
    /// pendingConfigRef: Project 切替時に caller (Main.flix) が新 config を積む。
    /// paintGL が AWT EDT 上で消費し、texture/font/projection/audio を再初期化する
    pub def withJavaFX(config: GameEngine.EngineConfig,
                        pendingConfigRef: Array[Option[GameEngine.EngineConfig], Static],
                        customizeStage: (Stage, WritableImage) -> ImageView \ IO,
                        f: Unit -> a \ ef):
            a \ ef - GameEngine.Game - GameEngine.Audio + IO + Chan + NonDet =

        // ----- 状態 Ref (initGL / paintGL / effect handler で共有) -----
        // 現在有効な engine config。Project 切替時に paintGL が pendingConfigRef を消費して
        // ここに新値を書く。handler は常にこの ref を読む (closure 捕捉ではなく動的読出し)
        let currentConfigRef = Array#{config} @ Static;
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

        // FBO の現在サイズ。Stage リサイズに追従して付け替える
        let initialW = config#windowWidth;
        let initialH = config#windowHeight;
        let curW = Array#{initialW} @ Static;
        let curH = Array#{initialH} @ Static;

        // エディタ自由カメラ (panX, panY, zoom)。setEditorView で main thread から書き込み、
        // paintGL (AWT EDT) の投影と getMousePosition の逆変換が読む。
        // fbo_px = (design_px - pan) * zoom * renderScale。
        let editorViewRef = Array#{(0.0, 0.0, 1.0)} @ Static;
        // ディスプレイの出力スケール（Retina で 2.0 等）。FBO を物理解像度でレンダして
        // 拡大ボケを防ぐ。sizeListener が更新、投影 / マウス逆変換が読む。
        let renderScaleRef = Array#{1.0} @ Static;

        // FBO + 色テクスチャ
        let fboArr = Array#{0i32} @ Static;
        let texArr = Array#{0i32} @ Static;

        // CPU 側ピクセル → JavaFX PixelBuffer。リサイズ時に AWT 側で全部作り直し、
        // imageView.setImage は Platform.runLater で FX thread に切替えて適用
        let pixels0: ByteBuffer = BufferUtils.createByteBuffer(initialW * initialH * 4i32);
        let pf: WritablePixelFormat[ByteBuffer] = PixelFormat.getByteBgraPreInstance();
        let pb0: PixelBuffer[ByteBuffer] = new PixelBuffer(initialW, initialH, pixels0, pf);
        let image0: WritableImage = new WritableImage(pb0);
        let pixelsRef: Array[ByteBuffer, Static]              = Array#{pixels0} @ Static;
        let pbRef:     Array[PixelBuffer[ByteBuffer], Static] = Array#{pb0}     @ Static;

        // FX → AWT 方向の resize 通知
        let needResize = Array#{false} @ Static;
        let pendingW = Array#{initialW} @ Static;
        let pendingH = Array#{initialH} @ Static;

        // 入力 (JavaFXInput が listener から書き、GameEngine.Game handler が読む)
        let inputRefs = JavaFXInput.newInputRefs();

        // initGL 完了通知用 channel
        let (initTx, initRx) = Channel.buffered(1);

        // screenW/H/designSize は currentConfigRef から動的に算出する小ヘルパー。
        // 各所でリードして、Project 切替後も最新の design 寸法が即座に反映される
        // (initGL は最初の config で 1 度だけ projection matrix を set。以降の更新は
        // paintGL の config swap パスで再 set する)

        // ----- OpenAL 初期化 (GL コンテキスト独立) -----
        println("[JavaFXLayer] Initializing audio...");
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
        let audioRegistry0 = RenderAudio.loadAudioRegistry(config#soundManifest);
        // audio registry も Project 切替で差し替えるため Ref 化
        let audioRegistryRef = Array#{audioRegistry0} @ Static;
        println("[JavaFXLayer] Audio ready");

        // ----- AWTGLCanvas (隠し JFrame に置く) -----
        println("[JavaFXLayer] Creating AWTGLCanvas...");
        let canvas = new AWTGLCanvas {
            def initGL(_this: AWTGLCanvas): Unit \ IO = {
                println("[JavaFXLayer] initGL: GL.createCapabilities + render_core init");
                discard GL.createCapabilities();
                GL11.glEnable(GL11.GL_BLEND);
                GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

                let initScreenW = Int32.toFloat64(config#designWidth);
                let initScreenH = Int32.toFloat64(config#designHeight);
                let spriteShader = RenderShader.createShaderProgram(
                    RenderShader.vertexShaderSource(),
                    RenderShader.fragmentShaderSource());
                RenderShader.setProjectionMatrix(spriteShader, initScreenW, initScreenH);

                let tileShader = RenderShader.createShaderProgram(
                    RenderShader.tileVertexShaderSource(),
                    RenderShader.tileFragmentShaderSource());
                RenderShader.setProjectionMatrix(tileShader, initScreenW, initScreenH);

                let (vao, quadVBO) = RenderSprite.initSpriteRenderer();

                println("[JavaFXLayer] Loading textures...");
                let registry0 = RenderTexture.loadTextureRegistry(config#textureManifest);
                println("[JavaFXLayer] Baking font atlases...");
                let (fontAtlases, registry) = RenderFont.bakeFontAtlases(config#fontManifest, registry0);

                Array.put(spriteShader, 0, spriteShaderArr);
                Array.put(tileShader,   0, tileShaderArr);
                Array.put(vao,          0, vaoArr);
                Array.put(quadVBO,      0, quadVBOArr);
                Array.put(registry,     0, registryArr);
                Array.put(fontAtlases,  0, fontAtlasesArr);

                // FBO + 色テクスチャを生成（最初は初期サイズ）
                let fbo = GL30.glGenFramebuffers();
                let tex = GL11.glGenTextures();
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, tex);
                GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0i32, GL11.GL_RGBA, initialW, initialH, 0i32,
                                   GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, MemoryUtil.NULL);
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
                GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, fbo);
                GL30.glFramebufferTexture2D(GL30.GL_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0,
                                             GL11.GL_TEXTURE_2D, tex, 0i32);
                let status = GL30.glCheckFramebufferStatus(GL30.GL_FRAMEBUFFER);
                println("[JavaFXLayer] FBO status=${status} (complete=${GL30.GL_FRAMEBUFFER_COMPLETE})");
                GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, 0i32);
                Array.put(fbo, 0, fboArr);
                Array.put(tex, 0, texArr);

                Array.put(true, 0, initDoneArr);
                println("[JavaFXLayer] render_core ready")
            }
            def paintGL(_this: AWTGLCanvas): Unit \ IO = {
                if (Array.get(0, initDoneArr)) {
                    // ----- Project 切替 (pendingConfigRef) を消費 -----
                    // GL コンテキストを持つ EDT 上でしか texture/font/shader 操作ができないため、
                    // ここで一括 re-init する。古い GL リソースは glDeleteTextures を呼ばず leak
                    // させる (IDE での Project 切替は稀。leak は許容範囲)
                    match Array.get(0, pendingConfigRef) {
                        case None => ()
                        case Some(newConfig) => {
                            println("[JavaFXLayer] config swap: ${newConfig#title} (${newConfig#designWidth}x${newConfig#designHeight})");
                            let newScreenW = Int32.toFloat64(newConfig#designWidth);
                            let newScreenH = Int32.toFloat64(newConfig#designHeight);
                            // texture registry を再ロード
                            let newRegistry0 = RenderTexture.loadTextureRegistry(newConfig#textureManifest);
                            // font atlases を再ベイク (registry に追加されて戻る)
                            let (newFontAtlases, newRegistry) =
                                RenderFont.bakeFontAtlases(newConfig#fontManifest, newRegistry0);
                            // 両 shader の projection matrix を新 design 寸法で更新
                            RenderShader.setProjectionMatrix(Array.get(0, spriteShaderArr),
                                                              newScreenW, newScreenH);
                            RenderShader.setProjectionMatrix(Array.get(0, tileShaderArr),
                                                              newScreenW, newScreenH);
                            // audio registry を入れ替え (古いソースを delete)
                            Map.forEach((_, src) -> AL10.alDeleteSources(src),
                                        Array.get(0, audioRegistryRef));
                            let newAudio = RenderAudio.loadAudioRegistry(newConfig#soundManifest);
                            // 全 ref を新値で上書き
                            Array.put(newRegistry,    0, registryArr);
                            Array.put(newFontAtlases, 0, fontAtlasesArr);
                            Array.put(newAudio,       0, audioRegistryRef);
                            Array.put(newConfig,      0, currentConfigRef);
                            Array.put(None,           0, pendingConfigRef);
                            println("[JavaFXLayer] config swap done")
                        }
                    };
                    // resize 反映
                    if (Array.get(0, needResize)) {
                        let nw = Array.get(0, pendingW);
                        let nh = Array.get(0, pendingH);
                        let tex = Array.get(0, texArr);
                        GL11.glBindTexture(GL11.GL_TEXTURE_2D, tex);
                        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0i32, GL11.GL_RGBA, nw, nh, 0i32,
                                           GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, MemoryUtil.NULL);
                        let newPixels = BufferUtils.createByteBuffer(nw * nh * 4i32);
                        let newPb: PixelBuffer[ByteBuffer] = new PixelBuffer(nw, nh, newPixels, pf);
                        let newImage: WritableImage = new WritableImage(newPb);
                        Array.put(newPixels, 0, pixelsRef);
                        Array.put(newPb, 0, pbRef);
                        Array.put(nw, 0, curW);
                        Array.put(nh, 0, curH);
                        Array.put(false, 0, needResize);
                        // FX 側 ImageView に新画像を流す。imageView 参照は customizeStage に
                        // 渡したものを inputRefs 経由で覚えておく
                        let imageViewOpt = Array.get(0, inputRefs#imageViewRef);
                        match imageViewOpt {
                            case Some(iv) =>
                                Platform.runLater(new Runnable {
                                    def $run(_innerThis: Runnable): Unit \ IO =
                                        iv.setImage(newImage)
                                })
                            case None => ()
                        }
                    } else ();

                    let w = Array.get(0, curW);
                    let h = Array.get(0, curH);
                    let fbo = Array.get(0, fboArr);
                    let pixels = Array.get(0, pixelsRef);
                    let pb = Array.get(0, pbRef);

                    GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, fbo);

                    let spriteShader = Array.get(0, spriteShaderArr);
                    let tileShader   = Array.get(0, tileShaderArr);
                    let vao          = Array.get(0, vaoArr);
                    let registry     = Array.get(0, registryArr);
                    let (sprites, tileMaps) = Array.get(0, renderStateArr);
                    // エディタは FBO 全面を使う自由カメラビュー (Godot 風の無限グレーキャンバス)。
                    // ノード座標は design-px のまま、pan/zoom を投影に焼き込む。
                    // calcViewport には FBO サイズを渡して全面 (レターボックス無し) にする。
                    // 投影範囲 design-px = [pan, pan + fbSize/zoom]: fbo_px = (design - pan) * zoom。
                    let fbWf = Int32.toFloat64(w);
                    let fbHf = Int32.toFloat64(h);
                    let (evPanX, evPanY, evZoomRaw) = Array.get(0, editorViewRef);
                    let evZoom = if (evZoomRaw <= 0.0) 1.0 else evZoomRaw;
                    // FBO は物理解像度。design→物理 = (design-pan)*zoom*renderScale。
                    // 「画面 px」定数（ハンドル/線）が論理 px を意味するよう renderScale を掛ける。
                    let evScale = Array.get(0, renderScaleRef);
                    let projZoom = evZoom * (if (evScale <= 0.0) 1.0 else evScale);
                    let projLeft = evPanX;
                    let projRight = evPanX + fbWf / projZoom;
                    let projTop = evPanY;
                    let projBottom = evPanY + fbHf / projZoom;
                    RenderShader.setProjectionMatrixRect(spriteShader, projLeft, projRight, projTop, projBottom);
                    RenderShader.setProjectionMatrixRect(tileShader, projLeft, projRight, projTop, projBottom);
                    // 一様な灰色 (#4D4D4D)。内側・外側(帯)とも同色。
                    let editorBg = {r = 0.302f32, g = 0.302f32, b = 0.302f32};
                    RenderFrame.renderFrameMixed(spriteShader, tileShader, vao, registry,
                        editorBg, editorBg, fbWf, fbHf, w, h, sprites, tileMaps,
                        (Nil: List[GameEngine.PolygonRenderCmd]), vao, vao);

                    pixels.position(0i32);
                    GL11.glReadPixels(0i32, 0i32, w, h,
                                      GL12.GL_BGRA, GL11.GL_UNSIGNED_BYTE, pixels);
                    GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, 0i32);

                    let wF = Int32.toFloat64(w);
                    let hF = Int32.toFloat64(h);
                    Platform.runLater(new Runnable {
                        def $run(_innerThis: Runnable): Unit \ IO =
                            pb.updateBuffer(new Callback[PixelBuffer[ByteBuffer], Rectangle2D] {
                                def call(_cbThis: Callback[PixelBuffer[ByteBuffer], Rectangle2D],
                                          _b: PixelBuffer[ByteBuffer]): Rectangle2D \ IO =
                                    new Rectangle2D(0.0, 0.0, wF, hF)
                            })
                    })
                } else ()
            }
        };
        patchCanvasGLDataToCore33(canvas);
        canvas.setIgnoreRepaint(true);

        // ----- 隠し JFrame (GL コンテキスト確保用) -----
        let hostFrame = new JFrame("javafx-gl-host");
        hostFrame.setUndecorated(true);
        hostFrame.setSize(initialW, initialH);
        hostFrame.setLocation(-10000i32, -10000i32);
        let hostPanel = new JPanel(new BorderLayout());
        hostPanel.add(canvas, BorderLayout.CENTER);
        hostFrame.getContentPane().add(hostPanel, BorderLayout.CENTER);
        hostFrame.setVisible(true);

        // ----- JavaFX runtime 起動 + Stage 構築 -----
        // Platform.startup は同期だが Runnable は別スレッド (FX Application Thread) で実行される。
        // ImageView の生成は customize 内 (FXML) で行い、Layer は WritableImage だけ渡す
        let initialImage = image0;

        Platform.startup(new Runnable {
            def $run(_innerThis: Runnable): Unit \ IO = {
                let stage = new Stage();
                stage.setTitle(config#title);
                let imageView = customizeStage(stage, initialImage);
                Array.put(Some(imageView), 0, inputRefs#imageViewRef);
                // ImageView の fit{Width,Height} は customize 側で親 Pane の幅高に
                // bind されている前提。これらは DoubleProperty なので Number で監視可能。
                // boundsInLocalProperty は Bounds を返し ChangeListener[Number] と一致しない
                let sizeListener = new ChangeListener[Number] {
                    def changed(_cThis: ChangeListener[Number],
                                 _obs: ObservableValue[Object],
                                 _old: Number, _new: Number): Unit \ IO = {
                        // 物理解像度でレンダ（Retina で 2x）。ImageView は論理サイズで表示するので
                        // 高解像度画像が等倍デバイス px に乗ってくっきりする。
                        let scale = Screen.getPrimary().getOutputScaleX();
                        Array.put(scale, 0, renderScaleRef);
                        let nw = Float64.tryToInt32(imageView.getFitWidth() * scale)
                                  |> Option.getWithDefault(initialW)
                                  |> Int32.max(1i32);
                        let nh = Float64.tryToInt32(imageView.getFitHeight() * scale)
                                  |> Option.getWithDefault(initialH)
                                  |> Int32.max(1i32);
                        if (nw == Array.get(0, curW) and nh == Array.get(0, curH)) ()
                        else {
                            Array.put(nw, 0, pendingW);
                            Array.put(nh, 0, pendingH);
                            Array.put(true, 0, needResize)
                        }
                    }
                };
                imageView.fitWidthProperty().addListener(sizeListener);
                imageView.fitHeightProperty().addListener(sizeListener);
                stage.setOnCloseRequest(new EventHandler[WindowEvent] {
                    def handle(_eThis: EventHandler[WindowEvent], _e: WindowEvent): Unit \ IO =
                        Array.put(true, 0, shouldCloseArr)
                });
                // JavaFX 側の入力 listener を ImageView / Scene に貼る
                JavaFXInput.attachListeners(stage.getScene(), imageView, inputRefs);
                stage.show()
            }
        });

        // ----- SwingTimer で 60Hz canvas.render() -----
        let renderTimer = new SwingTimer(16i32, new ActionListener {
            def actionPerformed(_aThis: ActionListener, _e: ActionEvent): Unit \ IO = {
                if (Array.get(0, shouldCloseArr)) ()
                else if (canvas.isValid()
                         and canvas.getWidth() > 0i32
                         and canvas.getHeight() > 0i32)
                    canvas.render()
                else ()
            }
        });
        renderTimer.start();

        // ----- initGL の完了通知 spawn -----
        spawn {
            initSignalWatcher(initDoneArr, initTx)
        } @ Static;

        // ----- initGL の完了待ち -----
        select {
            case _ <- recv(initRx) => ()
        };
        println("[JavaFXLayer] initGL completed, starting user code");

        let timeHolder = Array#{System.nanoTime()} @ Static;

        // ----- effect handler を install してユーザコードを実行 -----
        let result = run {
            f()
        } with handler GameEngine.Audio {
            def playAudio(name, k) = {
                match Map.get(name, Array.get(0, audioRegistryRef)) {
                    case Some(src) => AL10.alSourceStop(src); AL10.alSourcePlay(src)
                    case None      => ()
                };
                k(())
            }
            def stopAudio(name, k) = {
                match Map.get(name, Array.get(0, audioRegistryRef)) {
                    case Some(src) => AL10.alSourceStop(src)
                    case None      => ()
                };
                k(())
            }
            def setVolume(name, volume, k) = {
                match Map.get(name, Array.get(0, audioRegistryRef)) {
                    case Some(src) => AL10.alSourcef(src, AL10.AL_GAIN, volume)
                    case None      => ()
                };
                k(())
            }
            def setLooping(name, loop, k) = {
                match Map.get(name, Array.get(0, audioRegistryRef)) {
                    case Some(src) =>
                        let v = if (loop) AL10.AL_TRUE else AL10.AL_FALSE;
                        AL10.alSourcei(src, AL10.AL_LOOPING, v)
                    case None      => ()
                };
                k(())
            }
        } with handler GameEngine.Game {
            def renderCommands(sprites, tileMaps, _polygons, k) = {
                // Polygon2D（_polygons）はシーンエディタ描画では未対応（無視）。
                Array.put((sprites, tileMaps), 0, renderStateArr);
                k(())
            }
            def initTileBuffer(_instances, k) = {
                // Step C.1 では未対応 (paintGL が render thread 側で GL コンテキスト保持。
                // VBO 作成キューは後続で)
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
                let clamped = Float64.min(dtSec, Array.get(0, currentConfigRef)#maxDeltaTime);
                k(clamped |> Duration.seconds)
            }
            def isKeyPressed(key, k) = k(JavaFXInput.readKeyPressed(inputRefs, key))
            def getMousePosition(k) = {
                // canvas px → FBO px (preserveRatio=false の線形写像) → design-px へ逆変換。
                // design = pan + fbo_px / zoom。投影 (fbo = (design-pan)*zoom) の逆。
                // エディタ操作計算は design-px で行うので、ここで pan/zoom を打ち消して返す。
                let ds = {width = Int32.toFloat64(Array.get(0, curW)),
                          height = Int32.toFloat64(Array.get(0, curH))};
                let fboPos = JavaFXInput.readMousePosition(inputRefs, ds);
                let (evPanX, evPanY, evZoomRaw) = Array.get(0, editorViewRef);
                let evZoom = if (evZoomRaw <= 0.0) 1.0 else evZoomRaw;
                let evScale = Array.get(0, renderScaleRef);
                let projZoom = evZoom * (if (evScale <= 0.0) 1.0 else evScale);
                k({x = evPanX + fboPos#x / projZoom, y = evPanY + fboPos#y / projZoom})
            }
            def isMouseButtonPressed(button, k) = k(JavaFXInput.readMouseButtonPressed(inputRefs, button))
            def consumeScrollDelta(k) = k(JavaFXInput.consumeScrollDelta(inputRefs))
            def consumeScrollPan(k) = k(JavaFXInput.consumeScrollPan(inputRefs))
            def getFontAtlas(name, k) = {
                let atlases = Array.get(0, fontAtlasesArr);
                match Map.get(name, atlases) {
                    case Some(atlas) => k(atlas)
                    case None => bug!("Font atlas not found: ${name}")
                }
            }
            def getViewportRect(k) = {
                let curCfg = Array.get(0, currentConfigRef);
                let sW = Int32.toFloat64(curCfg#designWidth);
                let sH = Int32.toFloat64(curCfg#designHeight);
                k({position = Vec2.zero(), size = {x = sW, y = sH}})
            }
            def getTextureInfo(name, k) = {
                k(Map.get(name, Array.get(0, registryArr)))
            }
            def setCursor(cursor, k) = {
                JavaFXInput.applyCursor(inputRefs, cursor);
                k(())
            }
            def setEditorView(panX, panY, zoom, k) = {
                Array.put((panX, panY, zoom), 0, editorViewRef);
                k(())
            }
        };

        // ----- クリーンアップ -----
        Map.forEach((_, src) -> AL10.alDeleteSources(src), Array.get(0, audioRegistryRef));
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);
        result

    /// initDoneArr を 20ms 周期で観測し、true になったら channel に signal を送る
    def initSignalWatcher(initDoneArr: Array[Bool, Static],
                           tx: Sender[Unit]): Unit \ {Chan, IO} =
        if (Array.get(0, initDoneArr))
            Channel.send((), tx)
        else {
            JThread.sleep(20i64);
            initSignalWatcher(initDoneArr, tx)
        }

    /// AWTGLCanvas のコンストラクタが protected で no-arg 版しか Flix から呼べないので、
    /// reflection で内部 GLData を OpenGL 3.3 Core Profile に書き換える
    def patchCanvasGLDataToCore33(canvas: AWTGLCanvas): Unit \ IO =
        let superCls = canvas.getClass().getSuperclass();
        let dataField = superCls.getDeclaredField("data");
        dataField.setAccessible(true);
        let glData = dataField.get(canvas);
        let glDataCls = glData.getClass();
        glDataCls.getField("majorVersion").setInt(glData, 3i32);
        glDataCls.getField("minorVersion").setInt(glData, 3i32);
        glDataCls.getField("swapInterval").set(glData, Integer.valueOf(1i32));
        glDataCls.getField("forwardCompatible").setBoolean(glData, true);
        let profileField = glDataCls.getField("profile");
        let profileType = profileField.getType();
        let coreField = profileType.getField("CORE");
        let coreValue = coreField.get(MemoryUtil.NULL);
        profileField.set(glData, coreValue)

    /// AWT EDT と FX runtime が non-daemon で残り続けるため Platform.exit / System.exit では
    /// 落ちない。shutdown hook を回避して即終了する。Main.flix の最後で呼ぶ。
    pub def halt(): Unit \ IO =
        Runtime.getRuntime().halt(0i32)
}
