// SceneNotes — 実機で演じたイベントシーンの報せ(飛ばしたカット・打ち切り)を
// debug/scene-notes.log へ写す窓口。bake は焼き終わりに println で報せるが、
// 実機再生(Director)には標準出力を眺める人が居ない — だからファイルに残す。
// 書くのは「報せが有り、前回書いた内容と違う」拍だけ(ActiveDocs.step と同じ流儀 —
// 指紋は World の sceneNotesWritten)。書き込みの失敗は握り潰す(補助ログで、
// 書けない環境でもゲーム本体を止める理由にならない)。
mod SceneNotes {

    /// 書き出し先。debug/ は .gitignore 済みの作業用置き場。
    pub def path(): String = "debug/scene-notes.log"

    /// 毎フレームのシステムから呼ぶ(Main の update で ActiveDocs.step の直前)。
    /// sceneNotes が空なら書かない(誤り無しの演じ終わりで古い報せを消さない —
    /// 見つけた人が読み終わるまで残る)。同じ報せは一度しか書かない。
    pub def step(w: World.World): World.World \ Fs.FileWrite =
        let current = String.intercalate("\n", w#sceneNotes);
        if (List.isEmpty(w#sceneNotes) or current == w#sceneNotesWritten) w
        else {
            run {
                discard Fs.WriteFile.write({str = current + "\n"}, path())
            } with Fs.WriteFile.runWithFileWrite;
            { sceneNotesWritten = current | w }
        }
}
