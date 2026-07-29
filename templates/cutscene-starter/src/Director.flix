// Director — 実機でイベントシーンを演じる係（ゲーム側・すべて純粋）。
// World の合図（cue = 始めたいシーンの id）を拾ってシーンを演じ始め、
// 演じている間はプレイヤーの入力を預かり、終わったら片付けて操作を返す。
// 進行そのものは SceneSeq（骨格）と Cutscene.perform（動詞）の仕事 —
// **bake と同じ道具を実機で回すだけ**なので、GIF で目視した動きがそのままゲームに出る。
mod Director {

    /// 毎フレームのシステム（Controls.step の代わりに Main が呼ぶ）。
    /// シーンの最中・合図あり → シーンを 1 コマ進める（入力は預かる）。
    /// どちらも無ければ、ふつうの歩み（Controls.step）。
    pub def step(frame: App.Frame, w: World.World): World.World =
        if (not Option.isEmpty(w#scene) or w#cue != "")
            tick(frame#dt, w)
        else
            Controls.step(frame, w)

    /// 決定キーの解釈。演じている間は預かる（言葉の送りはシーンが自分で進める）。
    pub def interact(frame: App.Frame, w: World.World): World.World =
        if (not Option.isEmpty(w#scene) or w#cue != "") w
        else Controls.interact(frame, w)

    /// シーンを 1 コマ進める（Frame を持たないのはテストから回すため）。
    /// 合図が立っていれば演じ始め、進行中なら 1 コマ演じ、終わったら片付ける。
    pub def tick(dt: Float64, w: World.World): World.World =
        match w#scene {
            case Some(s) => {
                let (s2, w2) = SceneSeq.tick(Cutscene.perform, idle, dt, s, w);
                if (SceneSeq.done(s2)) settle(s2#notes, w2)
                else { scene = Some(s2) | w2 }
            }
            case None => if (w#cue != "") start(w) else w
        }

    /// 合図のシーンを束から探して演じ始める。無ければ合図だけ消して遊びへ戻る
    /// （fail-open — 脚本を消しても遊びは止まらない）。
    def start(w: World.World): World.World =
        match List.find(doc -> doc#id == w#cue, w#scenes) {
            case None      => { cue = "" | w }
            case Some(doc) =>
                { scene = Some(SceneSeq.start(doc#cuts)), cue = ""
                  | Cutscene.stage(doc, w) }
        }

    /// シーンの合間の 1 コマ（SceneSeq へ渡す時間の流し方）。
    def idle(dt: Float64, w: World.World): World.World =
        World.step(None, dt, w)

    /// 演じ終わりの片付け: シーンの口を仕舞い（World.restStage — 幕を上げ、意図を消す）、
    /// 操作をプレイヤーへ返す。幕を下ろしたまま終わる脚本を書いても、遊びが暗闇に
    /// 閉じ込められない。演じながら残った報せ（飛ばしたカットと理由）は捨てずに
    /// World の sceneNotes へ格納する — SceneNotes.step が debug/ へ写し、脚本の誤りが
    /// 実機でも無音にならない。notes は積んだ順の逆で届くので JSON の順へ戻す。
    def settle(notes: List[String], w: World.World): World.World =
        { sceneNotes = List.reverse(notes) | World.restStage(w) }
}
