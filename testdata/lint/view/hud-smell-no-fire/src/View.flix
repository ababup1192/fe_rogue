mod Demo {
    pub def draw(): List[Render.Item] =
        Render.text("Score: 100", 4.0, 4.0) :: Nil

    pub def withHudView(app: App.Frame): App.Frame = app
}
