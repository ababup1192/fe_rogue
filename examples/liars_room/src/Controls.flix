// Controls — キー割り当て: Frame をこのゲームの意味（Room.Input）へ写し、Session を進める。
// 矢印は押しっぱなしで歩き、Z（話す・決定）/ C（メモ）/ X（もどる）/ Enter / Escape は
// 押した瞬間だけ効く。唯一の effect は reloadUi の ui.json 読み直し（F1）。
mod Controls {
    use GameEngine.Key

    /// このフレームのキーをゲームの意味へ写す。upTap / downTap はメニュー用のエッジ版。
    pub def inputOf(frame: App.Frame): Room.Input =
        { up      = App.isDown(Key.Up, frame),
          down    = App.isDown(Key.Down, frame),
          left    = App.isDown(Key.Left, frame),
          right   = App.isDown(Key.Right, frame),
          upTap   = App.justPressed(Key.Up, frame),
          downTap = App.justPressed(Key.Down, frame),
          talk    = App.justPressed(Key.Z, frame),
          memo    = App.justPressed(Key.C, frame),
          cancel  = App.justPressed(Key.X, frame),
          enter   = App.justPressed(Key.Enter, frame),
          esc     = App.justPressed(Key.Escape, frame) }

    /// 毎フレームのシステムその一: キーを Input へ写し、tick のルールで World を進める（純粋）。
    pub def step(frame: App.Frame, s: LiarsRoom.Session): LiarsRoom.Session =
        { world = LiarsRoom.tick(inputOf(frame), frame#dt, s#world) | s }

    /// 毎フレームのシステムその二: 進んだ後の World から UI ページの見た目を導く。
    pub def projectUi(_frame: App.Frame, s: LiarsRoom.Session): LiarsRoom.Session =
        { ui = GameUi.projectUi(s#world, s#ui) | s }

    /// F1 リロード: 生成済みの UI Spec をディスクから読み直す（遊びながらページを直せる）。
    pub def reloadUi(s: LiarsRoom.Session): LiarsRoom.Session \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(s#ui) | s }

    /// 終了判定: タイトル画面での Escape だけがウィンドウを閉じる
    /// （それ以外の Escape は tick が「タイトルへ戻る・閉じる」として受け取る）。
    pub def wantsQuit(frame: App.Frame, s: LiarsRoom.Session): Bool =
        let Room.World.World(state) = s#world;
        App.justPressed(Key.Escape, frame) and state#phase == Room.Phase.Title
}
