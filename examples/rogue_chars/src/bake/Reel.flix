// Reel — RogueStage.reel() の振り付けを、キャラの描き手に食わせて
// 1 tick = 1 画に展開する（Gallery の GIF はこれを 1 コマずつ焼く）。
// 死亡後の白骨は共通の Skeleton が描き、フェード段はここでは解釈せず
// Gallery に渡す（フェードの見せ方はギャラリー専用のブレンドだから）。

mod Reel {

    /// リール 1 tick 分の画: Canvas と、フェード段（None = そのまま表示・
    /// Some(0..3) = 白骨を背景へ溶かす段。段 3 で完全に消える）。
    pub type alias Tick = { canvas = PixelCanvas.Canvas, fade = Option[Int32] }

    /// リール全 tick 分の画。hflip 指定の tick は左右反転して返す（右向き確認用）。
    pub def frames(drawFn: (RogueStage.Clip, Int32) -> PixelCanvas.Canvas): List[Tick] =
        RogueStage.reel() |> List.map(step -> match step {
            case RogueStage.ReelStep.Char(c, f, flip) => {
                let cv = drawFn(c, f);
                { canvas = if (flip) PixelCanvas.hflip(cv) else cv, fade = None }
            }
            case RogueStage.ReelStep.Bones(f) =>
                { canvas = Skeleton.draw(f), fade = None }
            case RogueStage.ReelStep.Fade(s) =>
                { canvas = Skeleton.draw(1), fade = Some(s) }
        })
}
