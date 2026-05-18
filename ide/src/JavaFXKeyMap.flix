// JavaFXKeyMap — GameEngine の Key / Cursor / MouseButton と JavaFX 値の対応表
//
//   - Key: JavaFX KeyCode の enum 定数名 (toString) を文字列で持つ。
//     JavaFXInput.attachListeners が `e.getCode().toString()` で Set に書き、
//     ここの keyToName で同じ文字列を返すことで一致判定する
//   - Cursor: javafx.scene.Cursor 定数に変換
//   - MouseButton: 直接 enum 比較で済むので変換関数は持たない

mod JavaFXKeyMap {
    import javafx.scene.Cursor

    /// GameEngine.Key を JavaFX KeyCode の enum 定数名に変換する。
    /// 例: GameEngine.Key.Up → "UP" (= KeyCode.UP.toString())
    pub def keyToName(key: GameEngine.Key): String = match key {
        case GameEngine.Key.W         => "W"
        case GameEngine.Key.A         => "A"
        case GameEngine.Key.S         => "S"
        case GameEngine.Key.D         => "D"
        case GameEngine.Key.Z         => "Z"
        case GameEngine.Key.X         => "X"
        case GameEngine.Key.Up        => "UP"
        case GameEngine.Key.Down      => "DOWN"
        case GameEngine.Key.Left      => "LEFT"
        case GameEngine.Key.Right     => "RIGHT"
        case GameEngine.Key.Enter     => "ENTER"
        case GameEngine.Key.Space     => "SPACE"
        case GameEngine.Key.Escape    => "ESCAPE"
        case GameEngine.Key.F1        => "F1"
        case GameEngine.Key.LeftShift => "SHIFT"
        case GameEngine.Key.LeftCtrl  => "CONTROL"
        // macOS の Cmd キー
        case GameEngine.Key.LeftSuper => "META"
    }

    /// GameEngine.Cursor を javafx.scene.Cursor に変換する
    pub def cursorForGameCursor(cursor: GameEngine.Cursor): Cursor = match cursor {
        case GameEngine.Cursor.Default   => unsafe IO { Cursor.DEFAULT }
        case GameEngine.Cursor.HResize   => unsafe IO { Cursor.H_RESIZE }
        case GameEngine.Cursor.VResize   => unsafe IO { Cursor.V_RESIZE }
        case GameEngine.Cursor.AllResize => unsafe IO { Cursor.MOVE }
        case GameEngine.Cursor.Rotate    => unsafe IO { Cursor.HAND }
        case GameEngine.Cursor.NWResize  => unsafe IO { Cursor.NW_RESIZE }
        case GameEngine.Cursor.NEResize  => unsafe IO { Cursor.NE_RESIZE }
        case GameEngine.Cursor.SWResize  => unsafe IO { Cursor.SW_RESIZE }
        case GameEngine.Cursor.SEResize  => unsafe IO { Cursor.SE_RESIZE }
    }
}
