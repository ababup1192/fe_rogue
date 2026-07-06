// Sfx — World の前後から「このフレームで鳴らす音」を導く純関数の番地。衝突音は Step が
// 盤に記録した事実（core#sfx）を名前へ写し、局面音（サーブ・ミス・クリア・ゲームオーバー）は
// 局面の変わり目から導く。再生（GameEngine.Audio）は App が持ち、ここは名前の列を返すだけ ——
// だからテストは「何が鳴るか」を具体値で固定できる。

mod Sfx {

    /// このフレームで鳴らす音の名前（project.json の sounds に載る名前）。
    pub def events(before: Field.World, after: Field.World): List[String] =
        List.append(phaseSounds(before#phase, after#phase), hitSounds(after#phase))

    /// 衝突音: 進行中の盤が記録した事実を名前へ（同じ音は 1 フレームに 1 回へ畳む）。
    /// 凍結盤（Cleared / GameOver）は読まない —— そこに残る記録は最後のフレームの残骸で、
    /// 毎フレーム鳴り続けてしまう。局面の変わり目の音（ファンファーレ）がその幕引きを担う。
    def hitSounds(phase: Field.Phase): List[String] =
        match phase {
            case Field.Phase.Playing(core, _) => core#sfx |> List.map(nameOf) |> List.distinct
            case _                            => Nil
        }

    def nameOf(sfx: Field.Sfx): String =
        match sfx {
            case Field.Sfx.PaddleHit  => "paddle"
            case Field.Sfx.WallHit    => "wall"
            case Field.Sfx.BlockChip  => "chip"
            case Field.Sfx.BlockBreak => "break"
        }

    /// 局面音: 変わり目の 1 フレームだけ鳴る。サーブ（発射）・ミス（落下）・クリア・ゲームオーバー。
    /// 面の開始（Title/Cleared/GameOver から Playing へ）は静かに始まる —— launch のサーブ音が開幕を告げる。
    def phaseSounds(before: Field.Phase, after: Field.Phase): List[String] =
        match (before, after) {
            case (Field.Phase.Playing(_, Field.BallState.Waiting), Field.Phase.Playing(_, Field.BallState.Moving(_))) =>
                "serve" :: Nil
            case (Field.Phase.Playing(_, Field.BallState.Moving(_)), Field.Phase.Playing(_, Field.BallState.Waiting)) =>
                "miss" :: Nil
            case (Field.Phase.Playing(_, _), Field.Phase.Cleared(_))  => "clear" :: Nil
            case (Field.Phase.Playing(_, _), Field.Phase.GameOver(_)) => "gameover" :: Nil
            case _                                                    => Nil
        }
}
