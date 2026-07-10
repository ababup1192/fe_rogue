// Sfx — World の前後から「このフレームで鳴らす音」を導く純関数。
// Step が World に記録した出来事（events）を名前へ写すだけ。再生（GameEngine.Audio）は App が
// 持ち、ここは名前の列を返すだけ —— だからテストは「何が鳴るか」を具体値で固定できるし、
// リモートデバッグの until=sfx:land は WAV が無くてもこの名前で止まれる。

mod Sfx {

    /// このフレームで鳴らす音の名前（project.json の sounds に載る名前）。
    /// 前後の World は同じ型で取り違えやすいので、名前つきの record で受け取る。
    pub def events(worlds: { before = Field.World, after = Field.World }): List[String] =
        worlds#after#events |> List.map(Field.eventName) |> List.distinct
}
