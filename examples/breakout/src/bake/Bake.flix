// Bake — 成果物（ギャラリーの PNG・GIF・コマ送りサイトと、効果音の WAV）をまとめて生成する入口。
// 実行: make bake（実体は bin/flix run --entrypoint Bake.all）
// テスト（make test）は検証だけを行い、生成はこの入口が担う。

mod Bake {

    pub def all(): Unit \ IO =
        Gallery.bakeAll();
        SfxBake.bakeAll()
}
