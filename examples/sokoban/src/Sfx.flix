// Sfx — Session の前後から「このフレームで鳴らす音」を導く純関数。どの音かの判定
// （Sokoban.sfxEvent）は盤面と履歴の差分だけから決まり、再生（GameEngine.Audio）は
// App が持つ。だからテストは「何が鳴るか」を具体値で固定できる。

mod Sfx {

    /// このフレームで鳴らす音の名前（project.json の sounds に載る名前）。
    /// 前後の Session は同じ型で取り違えやすいので、名前つきの record で受け取る。
    pub def events(sessions: { before = Sokoban.Session, after = Sokoban.Session }): List[String] =
        Sokoban.sfxEvent(sessions#before#line, sessions#after#line) |> Option.toList
}
