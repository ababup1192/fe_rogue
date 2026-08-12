// Bake — make bake の入口。生成されるアセット（効果音・ギャラリー）をまとめて生成する。
// テストは検証だけ、生成はここ、という分業（sokoban と同じ流儀）。
mod Bake {

    pub def all(): Unit \ IO =
        SfxBake.bakeAll();
        NpcGallery.bakeAll();
        GameGallery.bakeAll();
        println("bake: done")
}
