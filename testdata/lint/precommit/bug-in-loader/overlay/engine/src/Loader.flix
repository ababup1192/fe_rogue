mod Loader {
    pub def load(path: String): Doc = match read(path) {
        case Some(d) => d
        case None    => bug!("読めません: ${path}")
    }
}
