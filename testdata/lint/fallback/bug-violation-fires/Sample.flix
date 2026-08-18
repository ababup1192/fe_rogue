mod Demo {
    pub def riskyLoad(path: String): String =
        match tryLoad(path) {
            case Ok(v)  => v
            case Err(_) => bug!("riskyLoad: ${path}")
        }
}
