// TuningDoc — 走りの手触りと得点を外から調整するための Doc。
// ここは数値を安全に読む所まで。加速や勝敗の判断は World に置く。
mod TuningDoc {
    use Util.Json.Json

    /// 走りの手触りと収支。各項目の説明と編集範囲はschemaに置く。
    pub type alias Doc = {
        version = Int32,
        maxSpeed = Float64,
        boostMaxSpeed = Float64,
        acceleration = Float64,
        boostAcceleration = Float64,
        brakePower = Float64,
        coastDrag = Float64,
        steerSpeed = Float64,
        brakeSteerMultiplier = Float64,
        offRoadGrip = Float64,
        offRoadMaxSpeed = Float64,
        offRoadDrag = Float64,
        collisionSpeedLoss = Float64,
        wallBounceSpeed = Float64,
        fallMargin = Float64,
        jumpDuration = Float64,
        jumpHeight = Float64,
        airSteerGrip = Float64,
        boostDrain = Float64,
        energyRecharge = Float64,
        collisionEnergyLoss = Float64,
        rivalSpeedA = Float64,
        rivalSpeedB = Float64,
        totalLaps = Int32,
        scorePerPass = Int32,
        finishBonus = Int32
    }

    pub def path(): String = "assets/apex.tuning.json"

    /// JSON が無い時にも遊べる安全な既定値。
    pub def defaults(): Doc =
        { version = 1,
          maxSpeed = 190.0,
          boostMaxSpeed = 270.0,
          acceleration = 92.0,
          boostAcceleration = 175.0,
          brakePower = 150.0,
          coastDrag = 34.0,
          steerSpeed = 118.0,
          brakeSteerMultiplier = 1.8,
          offRoadGrip = 0.55,
          offRoadMaxSpeed = 72.0,
          offRoadDrag = 120.0,
          collisionSpeedLoss = 56.0,
          wallBounceSpeed = 210.0,
          fallMargin = 22.0,
          jumpDuration = 1.35,
          jumpHeight = 58.0,
          airSteerGrip = 0.72,
          boostDrain = 34.0,
          energyRecharge = 12.0,
          collisionEnergyLoss = 24.0,
          rivalSpeedA = 142.0,
          rivalSpeedB = 158.0,
          totalLaps = 2,
          scorePerPass = 500,
          finishBonus = 2000 }

    /// JSON から Doc を読む。形が壊れていれば None、危険な数値だけならその欄を既定値へ戻す。
    pub def fromJson(text: String): Option[Doc] =
        DocValue.root(text)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let defaults = defaults();
        { version = DocValue.int("version", defaults#version, DocValue.IntRule.Positive, root),
          maxSpeed = positive("maxSpeed", defaults#maxSpeed, root),
          boostMaxSpeed = positive("boostMaxSpeed", defaults#boostMaxSpeed, root),
          acceleration = positive("acceleration", defaults#acceleration, root),
          boostAcceleration = positive("boostAcceleration", defaults#boostAcceleration, root),
          brakePower = positive("brakePower", defaults#brakePower, root),
          coastDrag = nonNegative("coastDrag", defaults#coastDrag, root),
          steerSpeed = positive("steerSpeed", defaults#steerSpeed, root),
          brakeSteerMultiplier = positive("brakeSteerMultiplier", defaults#brakeSteerMultiplier, root),
          offRoadGrip = ratio("offRoadGrip", defaults#offRoadGrip, root),
          offRoadMaxSpeed = positive("offRoadMaxSpeed", defaults#offRoadMaxSpeed, root),
          offRoadDrag = positive("offRoadDrag", defaults#offRoadDrag, root),
          collisionSpeedLoss = nonNegative("collisionSpeedLoss", defaults#collisionSpeedLoss, root),
          wallBounceSpeed = positive("wallBounceSpeed", defaults#wallBounceSpeed, root),
          fallMargin = positive("fallMargin", defaults#fallMargin, root),
          jumpDuration = positive("jumpDuration", defaults#jumpDuration, root),
          jumpHeight = positive("jumpHeight", defaults#jumpHeight, root),
          airSteerGrip = ratio("airSteerGrip", defaults#airSteerGrip, root),
          boostDrain = positive("boostDrain", defaults#boostDrain, root),
          energyRecharge = nonNegative("energyRecharge", defaults#energyRecharge, root),
          collisionEnergyLoss = nonNegative("collisionEnergyLoss", defaults#collisionEnergyLoss, root),
          rivalSpeedA = positive("rivalSpeedA", defaults#rivalSpeedA, root),
          rivalSpeedB = positive("rivalSpeedB", defaults#rivalSpeedB, root),
          totalLaps = DocValue.int("totalLaps", defaults#totalLaps, DocValue.IntRule.Positive, root),
          scorePerPass = DocValue.int("scorePerPass", defaults#scorePerPass, DocValue.IntRule.NonNegative, root),
          finishBonus = DocValue.int("finishBonus", defaults#finishBonus, DocValue.IntRule.NonNegative, root) }

    def positive(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.Positive, root)

    def nonNegative(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.NonNegative, root)

    def ratio(key: String, fallback: Float64, root: Map[String, Json]): Float64 =
        DocValue.float(key, fallback, DocValue.FloatRule.UnitInterval, root)

    /// ファイルを読み、失敗した時は既定値で続ける。
    pub def load(filePath: String): Doc \ Fs.FileRead =
        DocValue.load(filePath, defaults(), fromJson)
}
