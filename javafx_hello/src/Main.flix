import javafx.application.Platform
import javafx.stage.Stage
import javafx.stage.WindowEvent
import javafx.scene.Scene
import javafx.scene.Node
import javafx.scene.image.ImageView
import javafx.scene.image.WritableImage
import javafx.scene.image.PixelBuffer
import javafx.scene.image.PixelFormat
import javafx.scene.image.WritablePixelFormat
import javafx.scene.input.MouseEvent
import javafx.scene.layout.StackPane
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
import org.lwjgl.system.MemoryUtil
import org.lwjgl.BufferUtils
import java.lang.{Thread => JThread}
import java.lang.Integer
import java.lang.Number
import java.lang.Object
import java.lang.Runnable
import java.lang.Runtime
import java.lang.System
import java.nio.ByteBuffer

/// 落とし穴 spike:
///   - リサイズ追従 (Stage 変更 → FBO/buffer 再生成)
///   - ImageView クリック座標
///   - paintGL の実時間計測 (60 frame 移動平均)
def main(): Unit \ IO + Chan + NonDet = {
    let closeFlag = Array#{false} @ Static;
    let (closeTx, closeRx) = Channel.buffered(1);

    Platform.startup(new Runnable {
        def $run(_this: Runnable): Unit \ IO = buildAndShowStage(closeFlag)
    });

    spawn { closeWatcher(closeFlag, closeTx) } @ Static;

    println("[main] waiting for close signal");
    select {
        case _ <- recv(closeRx) => println("[main] close signal received")
    };
    println("[main] calling Runtime.halt(0)");
    Runtime.getRuntime().halt(0i32)
}

def buildAndShowStage(closeFlag: Array[Bool, Static]): Unit \ IO = {
    let initialW = 640i32;
    let initialH = 480i32;

    // ----- 動的に変わる状態 (resize で全部入れ替わる) -----
    // 現在の FBO テクスチャサイズ。paintGL が GL viewport / glReadPixels に使う
    let curW = Array#{initialW} @ Static;
    let curH = Array#{initialH} @ Static;

    let pixels0: ByteBuffer = BufferUtils.createByteBuffer(initialW * initialH * 4i32);
    let pf: WritablePixelFormat[ByteBuffer] = PixelFormat.getByteBgraPreInstance();
    let pb0: PixelBuffer[ByteBuffer] = new PixelBuffer(initialW, initialH, pixels0, pf);
    let image0: WritableImage = new WritableImage(pb0);

    // 現在の buffer/pb/image。AWT thread が新規作成し、FX thread が読む
    let pixelsRef: Array[ByteBuffer, Static]              = Array#{pixels0} @ Static;
    let pbRef:     Array[PixelBuffer[ByteBuffer], Static] = Array#{pb0}     @ Static;
    let imageRef:  Array[WritableImage, Static]           = Array#{image0}  @ Static;

    // FBO + texture id
    let fboArr = Array#{0i32} @ Static;
    let texArr = Array#{0i32} @ Static;
    let initDone = Array#{false} @ Static;

    // pending resize 通知 (FX → AWT)
    let needResize = Array#{false} @ Static;
    let pendingW = Array#{initialW} @ Static;
    let pendingH = Array#{initialH} @ Static;

    // perf 計測: 直近 60 frame の paintGL 全体時間 + readback 時間 (nanoseconds 合算)
    let frameCount = Array#{0i32} @ Static;
    let frameNsSum = Array#{0i64} @ Static;
    let readbackNsSum = Array#{0i64} @ Static;

    let imageView = new ImageView(image0);
    imageView.setScaleY(-1.0);

    let canvas = new AWTGLCanvas {
        def initGL(_this: AWTGLCanvas): Unit \ IO = {
            println("[gl] initGL");
            discard GL.createCapabilities();

            // 最初の FBO + texture (initialW x initialH)
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
            println("[gl] FBO status=${status} (complete=${GL30.GL_FRAMEBUFFER_COMPLETE})");
            GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, 0i32);

            Array.put(fbo, 0, fboArr);
            Array.put(tex, 0, texArr);
            Array.put(true, 0, initDone);
            println("[gl] initGL done")
        }
        def paintGL(_this: AWTGLCanvas): Unit \ IO = {
            if (Array.get(0, initDone)) {
                let frameStart = System.nanoTime();

                // ----- resize 処理 -----
                if (Array.get(0, needResize)) {
                    let nw = Array.get(0, pendingW);
                    let nh = Array.get(0, pendingH);
                    println("[gl] resizing FBO to ${nw}x${nh}");

                    // 既存テクスチャを新サイズで再確保 (FBO ID は使い回し)
                    let tex = Array.get(0, texArr);
                    GL11.glBindTexture(GL11.GL_TEXTURE_2D, tex);
                    GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0i32, GL11.GL_RGBA, nw, nh, 0i32,
                                       GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, MemoryUtil.NULL);

                    // CPU 側 buffer / PixelBuffer / WritableImage を再生成
                    let newPixels = BufferUtils.createByteBuffer(nw * nh * 4i32);
                    let newPb: PixelBuffer[ByteBuffer] = new PixelBuffer(nw, nh, newPixels, pf);
                    let newImage: WritableImage = new WritableImage(newPb);
                    Array.put(newPixels, 0, pixelsRef);
                    Array.put(newPb, 0, pbRef);
                    Array.put(newImage, 0, imageRef);
                    Array.put(nw, 0, curW);
                    Array.put(nh, 0, curH);
                    Array.put(false, 0, needResize);

                    // FX 側で ImageView.setImage を差し替え
                    Platform.runLater(new Runnable {
                        def $run(_innerThis: Runnable): Unit \ IO = {
                            imageView.setImage(newImage);
                            // 反転表示のオフセット補正は scaleY が center 基点なので不要
                            ()
                        }
                    })
                } else ();

                let w = Array.get(0, curW);
                let h = Array.get(0, curH);
                let fbo = Array.get(0, fboArr);
                let pixels = Array.get(0, pixelsRef);
                let pb = Array.get(0, pbRef);

                GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, fbo);
                GL11.glViewport(0i32, 0i32, w, h);

                // 時間変化する clear color (3秒で R↔B 推移)
                let tMs = System.currentTimeMillis() `Int64.remainder` 3000i64;
                let phase = Int64.toFloat32(tMs) / 3000.0f32;
                GL11.glClearColor(phase, 0.3f32, 1.0f32 - phase, 1.0f32);
                GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);

                let readbackStart = System.nanoTime();
                pixels.position(0i32);
                GL11.glReadPixels(0i32, 0i32, w, h,
                                  GL12.GL_BGRA, GL11.GL_UNSIGNED_BYTE, pixels);
                let readbackDt = System.nanoTime() - readbackStart;
                GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, 0i32);

                Platform.runLater(new Runnable {
                    def $run(_innerThis: Runnable): Unit \ IO =
                        pb.updateBuffer(new Callback[PixelBuffer[ByteBuffer], Rectangle2D] {
                            def call(_cbThis: Callback[PixelBuffer[ByteBuffer], Rectangle2D],
                                      _b: PixelBuffer[ByteBuffer]): Rectangle2D \ IO = {
                                let wF = Int32.toFloat64(w);
                                let hF = Int32.toFloat64(h);
                                new Rectangle2D(0.0, 0.0, wF, hF)
                            }
                        })
                });

                let frameDt = System.nanoTime() - frameStart;
                Array.put(Array.get(0, frameCount) + 1i32, 0, frameCount);
                Array.put(Array.get(0, frameNsSum) + frameDt, 0, frameNsSum);
                Array.put(Array.get(0, readbackNsSum) + readbackDt, 0, readbackNsSum);
                let n = Array.get(0, frameCount);
                if (n >= 60i32) {
                    let avgFrameUs = Array.get(0, frameNsSum) / Int32.toInt64(n) / 1000i64;
                    let avgReadUs  = Array.get(0, readbackNsSum) / Int32.toInt64(n) / 1000i64;
                    println("[perf ${w}x${h}] avg paintGL=${avgFrameUs}us readback=${avgReadUs}us over ${n} frames");
                    Array.put(0i32, 0, frameCount);
                    Array.put(0i64, 0, frameNsSum);
                    Array.put(0i64, 0, readbackNsSum)
                } else ()
            } else ()
        }
    };

    patchCanvasGLDataToCore33(canvas);
    canvas.setIgnoreRepaint(true);

    let hostFrame = new JFrame("gl-host");
    hostFrame.setUndecorated(true);
    hostFrame.setSize(initialW, initialH);
    hostFrame.setLocation(-10000i32, -10000i32);
    let hostPanel = new JPanel(new BorderLayout());
    hostPanel.add(canvas, BorderLayout.CENTER);
    hostFrame.getContentPane().add(hostPanel, BorderLayout.CENTER);
    hostFrame.setVisible(true);

    let root = new StackPane();
    let imageViewAsNode: Node = checked_cast(imageView);
    discard root.getChildren().add(imageViewAsNode);
    let scene = new Scene(root, Int32.toFloat64(initialW), Int32.toFloat64(initialH));

    // ----- scene size 変更を pending に -----
    let sizeListener = new ChangeListener[Number] {
        def changed(_this: ChangeListener[Number],
                     _obs: ObservableValue[Object],
                     _old: Number, _new: Number): Unit \ IO = {
            let nw = Int32.max(1i32, Float64.tryToInt32(scene.getWidth()) |> Option.getWithDefault(initialW));
            let nh = Int32.max(1i32, Float64.tryToInt32(scene.getHeight()) |> Option.getWithDefault(initialH));
            // 同じサイズなら無視
            if (nw == Array.get(0, curW) and nh == Array.get(0, curH)) ()
            else {
                Array.put(nw, 0, pendingW);
                Array.put(nh, 0, pendingH);
                Array.put(true, 0, needResize)
            }
        }
    };
    scene.widthProperty().addListener(sizeListener);
    scene.heightProperty().addListener(sizeListener);

    // ----- ImageView クリックで座標 -----
    imageView.setOnMouseClicked(new EventHandler[MouseEvent] {
        def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
            let viewX = e.getX();
            let viewY = e.getY();
            // imageView は scaleY=-1 で上下反転表示。e.getX/Y は反転前 (local) 座標なので
            // 表示上の y は (viewHeight - viewY) を見ているわけだが、設計座標は OpenGL 系の
            // bottom-up なら viewY のまま、JavaFX 系で扱うなら反転を補正する
            let w = Array.get(0, curW);
            let h = Array.get(0, curH);
            println("[click] view=(${viewX}, ${viewY}) design(${w}x${h})=(${viewX}, ${Int32.toFloat64(h) - viewY})")
        }
    });

    let stage = new Stage();
    stage.setTitle("JavaFX + OpenGL pitfall spike (resize/input/perf)");
    stage.setScene(scene);
    stage.setOnCloseRequest(new EventHandler[WindowEvent] {
        def handle(_eThis: EventHandler[WindowEvent], _e: WindowEvent): Unit \ IO = {
            println("[fx] onCloseRequest fired");
            Array.put(true, 0, closeFlag)
        }
    });
    stage.show();

    let renderTimer = new SwingTimer(16i32, new ActionListener {
        def actionPerformed(_aThis: ActionListener, _e: ActionEvent): Unit \ IO = {
            if (canvas.isValid()
                and canvas.getWidth() > 0i32
                and canvas.getHeight() > 0i32)
                canvas.render()
            else ()
        }
    });
    renderTimer.start()
}

def closeWatcher(closeFlag: Array[Bool, Static], tx: Sender[Unit]): Unit \ {Chan, IO} =
    if (Array.get(0, closeFlag))
        Channel.send((), tx)
    else {
        JThread.sleep(20i64);
        closeWatcher(closeFlag, tx)
    }

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
