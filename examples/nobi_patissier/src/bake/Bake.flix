// Bake — make bake の入口。絵作りフェーズでは候補シートとダッシュボードを焼く。
mod Bake {

    pub def all(): Unit \ IO =
        ArtGallery.bakeAll();
        println("bake: done")
}
