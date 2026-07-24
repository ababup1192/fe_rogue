// CourseProjection — 文字格子のコースと汎用射影をつなぐ、ゲーム固有の変換境界。
mod CourseProjection {

    /// 行番号は路面色と基板模様に使うが、Perspective自身には意味を持たせない。
    pub type alias Meta = { rowIndex = Int32 }

    /// このゲームで使う投影済み断面の短い呼び名。
    pub type alias Slice = Perspective.Slice[Meta]

    /// Course.sampleを、Perspectiveが要求する純粋な断面サンプラーへ変換する。
    pub def sampler(screenWidth: Float64, course: CourseDoc.Doc):
            Float64 -> Perspective.Section[Meta] =
        progress -> {
            let sample = Course.sample(
                { totalProgress = progress, screenWidth = screenWidth },
                course);
            { centerX = sample#centerX,
              width = sample#width,
              meta = { rowIndex = sample#rowIndex } }
        }
}
