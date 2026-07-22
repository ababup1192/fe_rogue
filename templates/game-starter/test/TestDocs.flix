// JSON 橋渡しのテスト（1 Doc につき最大 3 本まで。同型の重複は書かない）。
mod TestDocs {

    @Test
    def testSampleBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        let doc = SampleDoc.fromJson("{ broken") |> Option.getWithDefault(SampleDoc.defaults());
        Assert.assertEq(expected = SampleDoc.defaults()#speed, doc#speed)

    @Test
    def testSampleOverridesOneField(): Unit \ Assert =
        let doc = SampleDoc.fromJson("{\"version\":1, \"speed\": 99.0}")
            |> Option.getWithDefault(SampleDoc.defaults());
        Assert.assertEq(expected = 99.0, doc#speed)
}
