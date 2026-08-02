// UiText — ui.text.json(画面に出る文言)の宣言ドキュメント層。
// プレイヤーの目に入る文字はコードに直書きしない — 訳語や言い回しは
// 遊びながら直したくなるし、翻訳のとき探し回ることになるため。
// fail-open — 読めない・壊れているときは defaults() へ倒す。
mod UiText {
    use Util.Json.Json

    pub type alias Doc = { version = Int32, clear = String, gameOver = String }

    pub def path(): String = "assets/ui.text.json"

    pub def defaults(): Doc =
        { version = 1, clear = "CLEAR!", gameOver = "GAME OVER" }

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version  = JsonCodec.intOr("version", d#version, root),
          clear    = JsonCodec.stringOr("clear", d#clear, root),
          gameOver = JsonCodec.stringOr("gameOver", d#gameOver, root) }

    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
