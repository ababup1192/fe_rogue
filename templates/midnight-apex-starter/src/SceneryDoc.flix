// SceneryDoc — 背景と速度表現を Studio から調整するための値。
mod SceneryDoc {
    use Util.Json.Json

    pub type alias Doc = {
        version = Int32,
        panoramaStrength = Float64,
        farParallax = Float64,
        nearParallax = Float64,
        spriteScale = Int32,
        spriteColumns = Int32,
        farTop = Float64,
        nearTop = Float64,
        circuitStride = Int32,
        circuitLineWidth = Float64,
        circuitInnerRatio = Float64,
        circuitMiddleRatio = Float64,
        circuitOuterRatio = Float64,
        circuitTraceCount = Int32,
        circuitBranchCount = Int32,
        circuitViaEvery = Int32,
        circuitViaSize = Float64,
        circuitPadEvery = Int32,
        circuitBrightness = Float64,
        circuitScrollMultiplier = Float64,
        speedLineThreshold = Float64,
        speedLineLength = Float64,
        boostLineLength = Float64,
        speedLineAlpha = Float64,
        boostLineAlpha = Float64
    }

    pub def path(): String = "assets/apex.scenery.json"
    pub def spritePath(): String = "assets/apex.sprite.json"

    pub def defaults(): Doc =
        { version = 1,
          panoramaStrength = 112.0,
          farParallax = 0.32,
          nearParallax = 1.18,
          spriteScale = 3,
          spriteColumns = 80,
          farTop = 14.0,
          nearTop = 24.0,
          circuitStride = 1,
          circuitLineWidth = 0.85,
          circuitInnerRatio = 0.96,
          circuitMiddleRatio = 0.58,
          circuitOuterRatio = 0.04,
          circuitTraceCount = 9,
          circuitBranchCount = 4,
          circuitViaEvery = 2,
          circuitViaSize = 1.25,
          circuitPadEvery = 3,
          circuitBrightness = 0.48,
          circuitScrollMultiplier = 3.0,
          speedLineThreshold = 0.52,
          speedLineLength = 34.0,
          boostLineLength = 74.0,
          speedLineAlpha = 0.30,
          boostLineAlpha = 0.70 }

    pub def fromJson(text: String): Option[Doc] =
        DocValue.root(text)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let defaults = defaults();
        { version = integer("version", defaults#version, root),
          panoramaStrength = positive("panoramaStrength", defaults#panoramaStrength, root),
          farParallax = nonNegative("farParallax", defaults#farParallax, root),
          nearParallax = nonNegative("nearParallax", defaults#nearParallax, root),
          spriteScale = integer("spriteScale", defaults#spriteScale, root),
          spriteColumns = integer("spriteColumns", defaults#spriteColumns, root),
          farTop = nonNegative("farTop", defaults#farTop, root),
          nearTop = nonNegative("nearTop", defaults#nearTop, root),
          circuitStride = integer("circuitStride", defaults#circuitStride, root),
          circuitLineWidth = positive("circuitLineWidth", defaults#circuitLineWidth, root),
          circuitInnerRatio = ratio("circuitInnerRatio", defaults#circuitInnerRatio, root),
          circuitMiddleRatio = ratio("circuitMiddleRatio", defaults#circuitMiddleRatio, root),
          circuitOuterRatio = ratio("circuitOuterRatio", defaults#circuitOuterRatio, root),
          circuitTraceCount = integer("circuitTraceCount", defaults#circuitTraceCount, root),
          circuitBranchCount = integer("circuitBranchCount", defaults#circuitBranchCount, root),
          circuitViaEvery = integer("circuitViaEvery", defaults#circuitViaEvery, root),
          circuitViaSize = positive("circuitViaSize", defaults#circuitViaSize, root),
          circuitPadEvery = integer("circuitPadEvery", defaults#circuitPadEvery, root),
          circuitBrightness = ratio("circuitBrightness", defaults#circuitBrightness, root),
          circuitScrollMultiplier = positive("circuitScrollMultiplier", defaults#circuitScrollMultiplier, root),
          speedLineThreshold = ratio("speedLineThreshold", defaults#speedLineThreshold, root),
          speedLineLength = positive("speedLineLength", defaults#speedLineLength, root),
          boostLineLength = positive("boostLineLength", defaults#boostLineLength, root),
          speedLineAlpha = ratio("speedLineAlpha", defaults#speedLineAlpha, root),
          boostLineAlpha = ratio("boostLineAlpha", defaults#boostLineAlpha, root) }

    def positive(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.Positive, root)

    def nonNegative(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.NonNegative, root)

    def ratio(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.UnitInterval, root)

    def integer(key: String, fallback: Int32, root: Map[String, Json]): Int32 =
        DocValue.int(key, fallback, DocValue.IntRule.Positive, root)

    pub def load(filePath: String): Doc \ Fs.FileRead =
        DocValue.load(filePath, defaults(), fromJson)
}
