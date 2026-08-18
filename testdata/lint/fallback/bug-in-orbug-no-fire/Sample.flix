mod Demo {
    pub def riskyLoadOrBug(path: String): String =
        match tryLoad(path) {
            case Ok(v)  => v
            case Err(e) => bug!("riskyLoad: ${e}")
        }
}
