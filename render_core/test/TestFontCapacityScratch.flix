// 一時計測用（コミットしない）: 溢れ警告は GL アップロード前に出るので、
// 1 サイズだけベイクして警告の有無を読む（GL 無しでは最後に abort するが計測は先に済む）。

mod TestFontCapacityScratch {

    @Test
    def testMeasureCapacity(): Unit \ IO =
        let entry: RenderAsset.FontEntry = {
            name = "fe12",
            path = "../examples/fe_rogue/assets/fonts/MPLUSU-Medium.ttf",
            fontSize = 12.0
        };
        println("[capacity] bake start fe12");
        let (_, _) = RenderFont.bakeFontAtlas(entry);
        println("[capacity] bake done fe12")
}
