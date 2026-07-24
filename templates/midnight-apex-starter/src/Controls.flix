// Controls — 物理キーを「踏む・止める・曲がる・決定」の意図へ写す。
// World はキー名を知らず、ゲームの規則だけを扱う。
mod Controls {
    use GameEngine.Key

    /// このフレームのキーを、World が受け取る入力へ変換する。
    pub def inputOf(frame: App.Frame): World.Input =
        let arrowSteer = App.axis(negative = Key.Left, positive = Key.Right, frame);
        let letterSteer = App.axis(negative = Key.A, positive = Key.D, frame);
        { throttle = App.isDown(Key.Up, frame) or App.isDown(Key.W, frame),
          brake = App.isDown(Key.Down, frame) or App.isDown(Key.S, frame),
          boost = App.isDown(Key.Space, frame),
          steer = clampAxis(arrowSteer + letterSteer),
          confirm = App.justPressed(Key.Space, frame) or App.justPressed(Key.Enter, frame) }

    /// 毎フレームの入力と時間を一つの Tick にし、World を一拍進める。
    pub def step(frame: App.Frame, world: World.World): World.World =
        World.step({ deltaTime = frame#dt, input = inputOf(frame) }, world)

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { tuning = TuningDoc.load(TuningDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          course = CourseDoc.load(CourseDoc.path()),
          copy = CopyDoc.load(CopyDoc.path()),
          scenery = SceneryDoc.load(SceneryDoc.path()),
          sprites = PxSpriteDoc.load(SceneryDoc.spritePath()) }

    pub def reloadTuning(world: World.World): World.World \ Fs.FileRead =
        World.withTuning(TuningDoc.load(TuningDoc.path()), world)

    pub def reloadTheme(world: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), world)

    pub def reloadCopy(world: World.World): World.World \ Fs.FileRead =
        World.withCopy(CopyDoc.load(CopyDoc.path()), world)

    pub def reloadScenery(world: World.World): World.World \ Fs.FileRead =
        World.withScenery(SceneryDoc.load(SceneryDoc.path()), world)

    pub def reloadSprites(world: World.World): World.World \ Fs.FileRead =
        World.withSprites(PxSpriteDoc.load(SceneryDoc.spritePath()), world)

    /// コースを保存した時は新しい道の表紙へ戻す。古い距離を別の道へ継ぎ足さないため。
    pub def reloadCourse(world: World.World): World.World \ Fs.FileRead =
        World.resetWithCourse(CourseDoc.load(CourseDoc.path()), world)

    /// F1 で全 Doc を読み直す。コースを最後に読み、構造変更時の仕切り直しを一度だけ行う。
    pub def reloadAll(world: World.World): World.World \ Fs.FileRead =
        world
            |> reloadTuning
            |> reloadTheme
            |> reloadCopy
            |> reloadScenery
            |> reloadSprites
            |> reloadCourse

    def clampAxis(value: Float64): Float64 =
        Float64.max(-1.0, Float64.min(1.0, value))
}
