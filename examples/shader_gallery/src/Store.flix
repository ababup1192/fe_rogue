// スライダーの値をファイルに保存/読込する。スライダーを離すたびに save し、
// 起動時に load する。ファイルが無い/壊れていれば初期値に倒れる（fail-open）。
// 水ページと岸ページは別ファイルに保存する。

mod Store {

    /// 水パラメータの保存先。プロジェクト直下（"." ＝ project.json のある場所）からの相対。
    def path(): String = "assets/pond_params.txt"

    /// 岸パラメータの保存先。水とは別ファイル。
    def shorePath(): String = "assets/shore_params.txt"

    /// 今の World から Settings を抜き出してテキストで書き出す。
    pub def save(w: World.World): Unit \ Fs.FileWrite =
        let s = { params = w#params, bgR = w#bgR, bgG = w#bgG, bgB = w#bgB, pondScale = w#pondScale,
                  floorR = w#floorR, floorG = w#floorG, floorB = w#floorB };
        run {
            discard Fs.WriteFile.write({ str = World.settingsToText(s) }, path())
        } with Fs.WriteFile.runWithFileWrite

    /// 今の World の岸パラメータをテキストで書き出す。
    pub def saveShore(w: World.World): Unit \ Fs.FileWrite =
        run {
            discard Fs.WriteFile.write({ str = World.shoreToText(w#shore) }, shorePath())
        } with Fs.WriteFile.runWithFileWrite

    /// 保存ファイルを読んで Settings にする。読めない/壊れていれば None。
    pub def load(): Option[World.Settings] \ Fs.FileRead =
        let r = run { Fs.ReadFile.read(path()) } with Fs.ReadFile.runWithFileRead;
        match r {
            case Ok(text) => World.settingsFromText(text)
            case Err(_)   => None
        }

    /// 岸パラメータの保存ファイルを読んで Shore にする。読めない/壊れていれば None。
    pub def loadShore(): Option[World.Shore] \ Fs.FileRead =
        let r = run { Fs.ReadFile.read(shorePath()) } with Fs.ReadFile.runWithFileRead;
        match r {
            case Ok(text) => World.shoreFromText(text)
            case Err(_)   => None
        }
}
