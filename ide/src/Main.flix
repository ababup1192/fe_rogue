// ide/src/Main.flix — Step 1-B 切り分け版: 純粋な JFrame のみ。AWTGLCanvas 抜き。
//
// 目的: lwjgl3-awt 依存問題と切り分けるため、まず Swing 単独で起動できることを確認する。
//
// 動作確認:
//   cd ide && ./bin/flix check
//   cd ide && ./bin/flix run
// 期待: 空の青背景の JFrame が出る。× で終了。

import java.lang.{Thread => JThread}
import javax.swing.JFrame
import javax.swing.JPanel
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.Color
import java.awt.Dimension

def main(): Unit \ IO =
    let shouldClose = Array#{false} @ Static;

    let panel = new JPanel();
    panel.setBackground(Color.BLUE);
    panel.setPreferredSize(new Dimension(480, 720));

    let frame = new JFrame("flix_game_engine IDE — Step 1-B (no GL)");
    frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
    frame.add(panel);
    frame.pack();

    frame.addWindowListener(new WindowAdapter {
        def windowClosing(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
            Array.put(true, 0, shouldClose)
        def windowClosed(_this: WindowAdapter, _e: WindowEvent): Unit \ IO =
            Array.put(true, 0, shouldClose)
    });

    frame.setVisible(true);

    waitForClose(shouldClose)

def waitForClose(shouldClose: Array[Bool, Static]): Unit \ IO =
    if (Array.get(0, shouldClose)) ()
    else {
        JThread.sleep(100i64);
        waitForClose(shouldClose)
    }
