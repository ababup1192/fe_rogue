/// `.ldtkl` を `MapResource.Level` JSON に変換する 1 回限りの bootstrap スクリプト。
///
/// 実行方法 (fe_rogue ディレクトリで):
///   FE_ROGUE_MODE=convert-ldtk ./bin/flix run
///
/// 出力先: assets/maps/{level_0..4, pathway_1..6}.map.json
/// materialId はすべて "inca_stone" で固定 (本 PR では 1 素材のみ)。
mod LdtkConvertScript {

    /// 全 .ldtkl を assets/maps/ に変換出力する。
    /// 親ディレクトリ `assets/maps/` は事前に作成しておくこと。
    pub def convertAll(): Unit \ {IO, Fs.FileRead, Fs.FileWrite} =
        let pairs = ldtklFiles();
        List.forEach(p -> {
            let (inputPath, outputPath) = p;
            convertOne(inputPath, outputPath, "inca_stone")
        }, pairs);
        println("[ConvertLdtk] done: ${List.length(pairs)} file(s)")

    /// (input .ldtkl, output .map.json) のペア一覧。
    def ldtklFiles(): List[(String, String)] =
        ("assets/ldtk/World_Level_0.ldtkl",   "assets/maps/level_0.map.json")   ::
        ("assets/ldtk/World_Level_1.ldtkl",   "assets/maps/level_1.map.json")   ::
        ("assets/ldtk/World_Level_2.ldtkl",   "assets/maps/level_2.map.json")   ::
        ("assets/ldtk/World_Level_3.ldtkl",   "assets/maps/level_3.map.json")   ::
        ("assets/ldtk/World_Level_4.ldtkl",   "assets/maps/level_4.map.json")   ::
        ("assets/ldtk/World_Pathway_1.ldtkl", "assets/maps/pathway_1.map.json") ::
        ("assets/ldtk/World_Pathway_2.ldtkl", "assets/maps/pathway_2.map.json") ::
        ("assets/ldtk/World_Pathway_3.ldtkl", "assets/maps/pathway_3.map.json") ::
        ("assets/ldtk/World_Pathway_4.ldtkl", "assets/maps/pathway_4.map.json") ::
        ("assets/ldtk/World_Pathway_5.ldtkl", "assets/maps/pathway_5.map.json") ::
        ("assets/ldtk/World_Pathway_6.ldtkl", "assets/maps/pathway_6.map.json") :: Nil

    def convertOne(inputPath: String, outputPath: String, materialId: String):
            Unit \ {IO, Fs.FileRead, Fs.FileWrite} =
        println("[ConvertLdtk] ${inputPath} -> ${outputPath}");
        let level = LdtkConverter.convertLdtkl(inputPath, materialId);
        match Persistence.save(outputPath, level) {
            case Ok(_)  => ()
            case Err(e) => bug!("save failed: ${outputPath}: ${e}")
        }
}
