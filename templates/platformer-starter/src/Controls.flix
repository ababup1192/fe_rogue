// Controls — キーを World.Input へ写し、World.step で 1 歩進める(純粋)。
// ←→(または A・D)で歩き、Space か ↑(W)でジャンプ、↓(S)で一方通行から降りる。
// B(または Shift・X)を押しっぱなしで B ダッシュ — 最高速が dashMult 倍になり、
// 離しても decel でゆるく戻るので勢いが残る。
// Doc の保存即反映(watchFile)と F1 一括リロードの台帳もここに 1 枚だけ置く。
mod Controls {
    use GameEngine.Key

    /// このフレームのキーを World.Input へ。
    /// ジャンプは「押しっぱなし」(可変ジャンプの維持)と「押した瞬間」(先行入力の
    /// 取り置き)を別に読む — ゆるしの実装は World/Player 側にある。
    pub def inputOf(frame: App.Frame): World.Input =
        let arrows = App.axis(negative = Key.Left, positive = Key.Right, frame);
        let letters = App.axis(negative = Key.A, positive = Key.D, frame);
        let held = k -> App.isDown(k, frame);
        let pressed = k -> App.justPressed(k, frame);
        { dir = Num.clamp(-1.0, 1.0, arrows + letters),
          jumpHeld = held(Key.Space) or held(Key.Up) or held(Key.W),
          jumpPressed = pressed(Key.Space) or pressed(Key.Up) or pressed(Key.W),
          drop = held(Key.Down) or held(Key.S),
          dash = held(Key.B) or held(Key.LeftShift) or held(Key.X) }

    pub def step(frame: App.Frame, w: World.World): World.World =
        World.step(inputOf(frame), frame#dt, w)

    /// Doc の台帳(DocTable)。watchFile(保存即反映)と F1 の一括リロードは
    /// どちらもこの 1 枚から導出する — 足し忘れで「保存しても効かない」を作らないため。
    /// docId は project.json の editor.resources[] の id と同じ物 — これで
    /// 「いま画面に出ているファイル」を Studio に名乗れる(ActiveDocs)。
    pub def docTable(): List[DocTable.Entry[World.World]] =
        { docId = Some("motion"), path = MotionDoc.path(),      reload = World.reloadMotion }
            :: { docId = Some("rules"),   path = RulesDoc.path(),    reload = World.reloadRules }
            :: { docId = Some("enemies"), path = EnemyDoc.path(),    reload = World.reloadEnemies }
            :: { docId = Some("stages"),  path = StageDoc.path(),    reload = World.reloadStages }
            :: { docId = Some("theme"),   path = Theme.path(),       reload = World.reloadTheme }
            :: { docId = Some("text"),    path = UiText.path(),      reload = World.reloadUiText }
            :: { docId = Some("sprite"),  path = World.spritePath(), reload = World.reloadSprites }
            :: Nil

    /// App.game の reloads(保存即反映の watchFile)へ渡す形。
    pub def reloads(): List[(String, World.World -> World.World \ Fs.FileRead)] =
        DocTable.reloads(docTable())

    /// F1: 台帳の順に全 Doc を読み直す(絵と数値の一括リロード)。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        DocTable.reloadAll(docTable(), w)
}
