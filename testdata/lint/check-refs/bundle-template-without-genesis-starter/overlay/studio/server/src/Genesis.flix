mod Genesis {
    pub def genres(): List[Genre] = List#{
        Genre.Genre({ id = "action", starter = "templates/game-starter" })
    }
}
