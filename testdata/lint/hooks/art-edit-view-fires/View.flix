mod Demo {
    pub def draw(): List[Render.Item] =
        RawDraw.box(0.0, 0.0, 10.0, 10.0) ::
        RawDraw.box(10.0, 0.0, 10.0, 10.0) ::
        RawDraw.box(20.0, 0.0, 10.0, 10.0) ::
        RawDraw.box(30.0, 0.0, 10.0, 10.0) ::
        RawDraw.box(40.0, 0.0, 10.0, 10.0) ::
        Nil
}
