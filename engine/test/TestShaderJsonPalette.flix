// shader.json の色を色票の名前（"@名前"）で書けること。
// これが無いと shader.json だけが色票の外に出て、テーマを変えても面だけ古い色のまま残る。
mod TestShaderJsonPalette {

    def palette(): Map[String, Color] =
        Map#{ "sky" => { r = 0.2, g = 0.4, b = 0.6 } }

    /// 面 1 枚ぶんの JSON。色の書き方だけを差し替えて読ませる。
    def docText(color: String): String =
        "{\"name\":\"s\",\"out\":{\"kind\":\"fill\"," +
        "\"shade\":{\"kind\":\"solid\",\"color\":${color}}," +
        "\"alpha\":{\"kind\":\"const\",\"value\":1.0}}}"

    def solidOf(text: String, pal: Map[String, Color]): Option[(Float64, Float64, Float64)] =
        Util.Json.parse(text)
            |> Result.flatMap(json -> ShaderJson.parseWith(pal, json))
            |> Result.toOption
            |> Option.map(spec -> match spec#out {
                   case ShaderDoc.Out.Fill(f) => match f#shade {
                       case ShaderDoc.Shade.Solid(c) => Color.channels(c)
                       case _                        => (-1.0, -1.0, -1.0)
                   }
               })

    @Test
    def testAtNameResolvesFromPalette(): Unit \ Assert =
        Assert.assertEq(expected = Some((0.2, 0.4, 0.6)),
            solidOf(docText("\"@sky\""), palette()))

    @Test
    def testUnknownNameIsError(): Unit \ Assert =
        // 綴り違いを既定色へ落とすと、色の食い違いが絵の中に隠れる。
        Assert.assertEq(expected = None, solidOf(docText("\"@nope\""), palette()))

    @Test
    def testHexStillWorksWithoutPalette(): Unit \ Assert =
        // 色票を渡さない従来の parse は今までどおり（既存の shader.json を壊さない）。
        Assert.assertEq(expected = Some((1.0, 0.0, 0.0)),
            solidOf(docText("\"#ff0000\""), Map.empty()))
}
