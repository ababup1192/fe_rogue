// Bake — 成果物（ギャラリーの PNG・GIF・WAV・コマ送りサイトと、BGM 実験用の音源）を生成する入口。
// 実行: make bake（実体は bin/flix run --entrypoint Bake.all）

mod Bake {

    pub def all(): Unit \ IO =
        SfxBake.bakeAll();
        Gallery.bakeAll()
}
