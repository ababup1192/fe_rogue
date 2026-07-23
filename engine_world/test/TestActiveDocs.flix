// ActiveDocs のテスト。テストするのは「エディタが読める形か」だけ —
// { "active": { id: パス } } に畳まれ、1 本は文字列・複数は列で出ること。
// いつ書くか(書き込みのスキップ)は IO の振る舞いなのでテストしない。
mod TestActiveDocs {
    use Util.Json.Json.{JObject, JString, JArray}

    /// 出力を JSON として読み戻すと active の下に id が並び、
    /// パス 1 本は文字列・複数は列・空の一覧は空オブジェクトになる。
    @Test
    def testJsonShapesForEditor(): Unit \ Assert =
        let one = ("theme", "assets/x.theme.json" :: Nil) :: Nil;
        let many = ("ui", "assets/ui/a.ui.json" :: "assets/ui/b.ui.json" :: Nil) :: Nil;
        Assert.assertEq(
            expected = (
                Some(JObject(Map#{"active" => JObject(Map#{"theme" => JString("assets/x.theme.json")})})),
                Some(JObject(Map#{"active" => JObject(Map#{"ui" =>
                    JArray(Vector#{JString("assets/ui/a.ui.json"), JString("assets/ui/b.ui.json")})})})),
                Some(JObject(Map#{"active" => JObject(Map.empty())}))
            ),
            (JsonCompat.parse(ActiveDocs.json(one)),
             JsonCompat.parse(ActiveDocs.json(many)),
             JsonCompat.parse(ActiveDocs.json(Nil))))
}
