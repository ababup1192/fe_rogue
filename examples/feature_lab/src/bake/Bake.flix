// Bake — 成果物（Transition のギャラリー PNG・GIF・コマ送りサイト）を生成する入口。
// 実行: make bake（実体は bin/flix run --entrypoint Bake.all）

mod Bake {

    pub def all(): Unit \ IO =
        Gallery.bakeAll()
}
