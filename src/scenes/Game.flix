pub enum NodeTag {
    case NoTag
}

instance Node[NodeTag] {
    type Aef = {}
}

instance InputEvent.InputHandler[NodeTag] {
    type Aef = {}
}

instance ButtonEvent.ButtonHandler[NodeTag] {
    type Aef = {}
}

instance AreaEvent.AreaHandler[NodeTag] {
    type Aef = {}
    pub def onAreaEntered(_selfPath: NodePath, _selfState: NodeTag,
                          _otherPath: NodePath, _otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
}

instance NodeRemovedHandler[NodeTag] {
    type Aef = {}
}

mod Game {

    pub def screenWi(): Int32 = 1280
    pub def screenHi(): Int32 = 720

    pub def start(): Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                              Chan, NonDet, IO, Fs.Glob, Fs.ModificationTime} =
        region rc {
            run {
                gameLoop(Scene.empty())
            } with Editor.withState(rc)
        }

    def gameLoop(scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let sceneAfterEditor = Editor.handleInput(scene);
            let updatedScene = if (Editor.isOn()) sceneAfterEditor
                               else sceneAfterEditor
                                   |> GameEngine.process(delta = dt, paused = false)
                                   |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                                gravity = PhysicsStep.defaultGravity())
                                   |> GameEngine.handleInput
                                   |> GameEngine.handleButtons
                                   |> GameEngine.handleCollisions;
            GameEngine.render(updatedScene);
            gameLoop(updatedScene)
        }
}
