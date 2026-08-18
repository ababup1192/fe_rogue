mod TitleView {
    pub def draw(): List[Item] = List#{
        RawDraw.box(10.0, 10.0, 100.0, 20.0),
        RawDraw.box(10.0, 40.0, 100.0, 20.0),
        RawDraw.box(10.0, 70.0, 100.0, 20.0),
        RawDraw.box(10.0, 100.0, 100.0, 20.0),
        RawDraw.circleAt(60.0, 130.0, 8.0),
        RawDraw.circleAt(90.0, 130.0, 8.0)
    }
}
