// AwtKeyMap — GameEngine の Key / Cursor / MouseButton と AWT の数値定数の対応表
//
// 役割:
//   - LwjglLayer の keyToGlfw / cursorShapeToGlfw / mouseButtonToGlfw に相当する pure な変換
//   - IDE の AWT 入力リスナーが受け取った AWT イベントの数値を GameEngine 側の論理キー / ボタンと
//     突き合わせるために使う
//
// すべて副作用なしの全関数。テストで全バリアントの mapping を直接突き合わせできる

mod AwtKeyMap {

    import java.awt.event.KeyEvent
    import java.awt.event.MouseEvent
    import java.awt.Cursor

    /// GameEngine.Key を AWT KeyEvent.VK_* の数値コードに変換する。
    /// 全 Key バリアントを網羅し、AWT 側の KeyListener.keyPressed/keyReleased で
    /// 受け取った keyCode と直接比較できるようにする
    pub def keyToAwtCode(key: GameEngine.Key): Int32 = match key {
        case GameEngine.Key.W         => unsafe IO { KeyEvent.VK_W }
        case GameEngine.Key.A         => unsafe IO { KeyEvent.VK_A }
        case GameEngine.Key.S         => unsafe IO { KeyEvent.VK_S }
        case GameEngine.Key.D         => unsafe IO { KeyEvent.VK_D }
        case GameEngine.Key.Z         => unsafe IO { KeyEvent.VK_Z }
        case GameEngine.Key.X         => unsafe IO { KeyEvent.VK_X }
        case GameEngine.Key.Up        => unsafe IO { KeyEvent.VK_UP }
        case GameEngine.Key.Down      => unsafe IO { KeyEvent.VK_DOWN }
        case GameEngine.Key.Left      => unsafe IO { KeyEvent.VK_LEFT }
        case GameEngine.Key.Right     => unsafe IO { KeyEvent.VK_RIGHT }
        case GameEngine.Key.Enter     => unsafe IO { KeyEvent.VK_ENTER }
        case GameEngine.Key.Space     => unsafe IO { KeyEvent.VK_SPACE }
        case GameEngine.Key.Escape    => unsafe IO { KeyEvent.VK_ESCAPE }
        case GameEngine.Key.F1        => unsafe IO { KeyEvent.VK_F1 }
        case GameEngine.Key.LeftShift => unsafe IO { KeyEvent.VK_SHIFT }
        case GameEngine.Key.LeftCtrl  => unsafe IO { KeyEvent.VK_CONTROL }
        // macOS の Cmd キー。LWJGL の LeftSuper に対応
        case GameEngine.Key.LeftSuper => unsafe IO { KeyEvent.VK_META }
    }

    /// GameEngine.MouseButton を AWT MouseEvent.BUTTONn の数値に変換する。
    /// AWT の MouseListener#mousePressed の getButton() と直接比較できる
    pub def mouseButtonToAwtCode(button: GameEngine.MouseButton): Int32 = match button {
        case GameEngine.MouseButton.Left   => unsafe IO { MouseEvent.BUTTON1 }
        case GameEngine.MouseButton.Middle => unsafe IO { MouseEvent.BUTTON2 }
        case GameEngine.MouseButton.Right  => unsafe IO { MouseEvent.BUTTON3 }
    }

    /// GameEngine.Cursor を AWT java.awt.Cursor の型定数 (Int32) に変換する。
    /// 4 隅は AWT のネイティブ方向別カーソル (NW/NE/SW/SE) にそれぞれ対応。
    /// 上下・左右の伸縮は E/N で代表させる
    pub def cursorTypeForGameCursor(cursor: GameEngine.Cursor): Int32 = match cursor {
        case GameEngine.Cursor.Default   => unsafe IO { Cursor.DEFAULT_CURSOR }
        case GameEngine.Cursor.HResize   => unsafe IO { Cursor.E_RESIZE_CURSOR }
        case GameEngine.Cursor.VResize   => unsafe IO { Cursor.N_RESIZE_CURSOR }
        case GameEngine.Cursor.AllResize => unsafe IO { Cursor.MOVE_CURSOR }
        case GameEngine.Cursor.Rotate    => unsafe IO { Cursor.HAND_CURSOR }
        case GameEngine.Cursor.NWResize  => unsafe IO { Cursor.NW_RESIZE_CURSOR }
        case GameEngine.Cursor.NEResize  => unsafe IO { Cursor.NE_RESIZE_CURSOR }
        case GameEngine.Cursor.SWResize  => unsafe IO { Cursor.SW_RESIZE_CURSOR }
        case GameEngine.Cursor.SEResize  => unsafe IO { Cursor.SE_RESIZE_CURSOR }
    }

    /// AWT canvas のピクセル座標 (cursorPx) を、design 領域の論理座標に変換する。
    /// シンプルな比例マッピング: letterbox/pillarbox は考慮せず、canvas の全体を
    /// design 全体と対応付ける（LwjglLayer の getMousePosition と同じ単純式）。
    /// canvasPx が 0 のときは 0 を返す（起動直後で peer 未確定のケースを潰す）
    pub def canvasToDesign(input: {cursorPx = Float64, canvasPx = Float64, designSize = Float64}): Float64 =
        if (input#canvasPx == 0.0) 0.0
        else input#cursorPx / input#canvasPx * input#designSize
}
