// ide/src/Main.flix — Step C.0: AWTGLCanvas で緑単色クリア
//
// 動作確認:
//   cd ide && ./bin/flix run
// 期待: JFrame の中に緑単色の OpenGL 描画領域が出る。× で終了。
//
// 検証ポイント:
//   - lwjgl3-awt 0.2.4 の AWTGLCanvas が macOS arm64 で動く
//   - `-XstartOnFirstThread` 無しでも AWT + AppKit が動く (ide/bin/flix 経由)
//   - 専用 render Thread から canvas.render() を呼ぶ駆動モデルが機能

import java.lang.{Thread => JThread}
import javax.swing.JFrame
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.Dimension
import org.lwjgl.opengl.awt.AWTGLCanvas
import org.lwjgl.opengl.awt.GLData
import org.lwjgl.opengl.GL
import org.lwjgl.opengl.GL11

def main(): Unit \ IO =
    let shouldClose = Array#{false} @ Static;

    let canvas = new AWTGLCanvas {
        def initGL(_this: AWTGLCanvas): Unit \ IO = {
            println("[ide] initGL called");
            discard GL.createCapabilities();
            GL11.glClearColor(0.0f32, 1.0f32, 0.0f32, 1.0f32);
            println("[ide] GL.createCapabilities done, glClearColor set")
        }
        def paintGL(this: AWTGLCanvas): Unit \ IO = {
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            this.swapBuffers()
        }
    };
    canvas.setPreferredSize(new Dimension(480, 720));

    let frame = new JFrame("flix_game_engine IDE — Step C.0 (AWTGLCanvas only)");
    frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
    frame.add(canvas);
    frame.pack();

    frame.addWindowListener(new WindowAdapter {
        def windowClosing(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
            Array.put(true, 0, shouldClose)
        def windowClosed(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
            Array.put(true, 0, shouldClose)
    });

    frame.setVisible(true);

    // 専用 render Thread: AWTGLCanvas.render() を継続的に呼ぶ。
    // EDT / javax.swing.Timer は使わない (lwjgl3-awt 推奨パターン)。
    spawn {
        renderLoop(canvas, shouldClose)
    } @ Static;

    waitForClose(shouldClose)

def renderLoop(canvas: AWTGLCanvas, shouldClose: Array[Bool, Static]): Unit \ IO =
    // 起動直後は AWT peer 生成中で canvas が valid でない場合がある。
    // JFrame.setVisible(true) → componentResized → peer create という流れを待つ。
    JThread.sleep(200i64);
    println("[ide] render thread starting (canvas.isValid = ${canvas.isValid()})");
    renderLoopInner(canvas, shouldClose)

def renderLoopInner(canvas: AWTGLCanvas, shouldClose: Array[Bool, Static]): Unit \ IO =
    if (Array.get(0, shouldClose)) ()
    else {
        if (canvas.isValid()) {
            canvas.render()
        } else ();
        JThread.sleep(16i64);
        renderLoopInner(canvas, shouldClose)
    }

def waitForClose(shouldClose: Array[Bool, Static]): Unit \ IO =
    if (Array.get(0, shouldClose)) ()
    else {
        JThread.sleep(100i64);
        waitForClose(shouldClose)
    }
