// World — MIDNIGHT APEX の状態と、次の状態を作る純粋な規則。
//
//   Title ──決定──▶ Countdown ──3秒──▶ Racing ──規定周回──▶ Finish
//     ▲                                     │                    │
//     └──────────────決定──── GameOver ◀── Crashed ◀─エネルギー0─┘
//
// Racing の一拍は、操舵 → 加減速 → 前進 → ライバル進行 → 接触 → 追い抜き →
// 周回と順位、の順。道路の中心と幅は Course.sample だけを使い、描画とのずれを作らない。
mod World {

    /// いま表示している場面。
    pub enum Phase with Eq, ToString {
        case Title
        case Countdown
        case Racing
        case Finish
        case Crashed
        case GameOver
    }

    /// キーをゲーム内の意図へ読み替えた入力。
    pub type alias Input = {
        throttle = Bool,
        brake = Bool,
        boost = Bool,
        steer = Float64,
        confirm = Bool
    }

    /// 一拍ぶんの入力と経過時間。同じ Float64 を並べず、意味を名前で読めるようにする。
    pub type alias Tick = {
        deltaTime = Float64,
        input = Input
    }

    /// 起動時に読むゲーム設定と見た目の Doc。
    pub type alias Docs = {
        tuning = TuningDoc.Doc,
        theme = ThemeDoc.Doc,
        course = CourseDoc.Doc,
        copy = CopyDoc.Doc,
        scenery = SceneryDoc.Doc,
        sprites = PxSpriteDoc.Doc
    }

    /// ライバル1台の進行状態。
    /// laneOffset は道路幅に対する左右位置、passed は追い抜き得点の二重計上を防ぐ印。
    pub type alias Rival = {
        totalProgress = Float64,
        laneOffset = Float64,
        cruiseSpeed = Float64,
        passed = Bool
    }

    /// ゲーム全体の状態。走行中に変わる値の唯一の保管場所。
    pub type alias World = {
        tuning = TuningDoc.Doc,
        theme = ThemeDoc.Doc,
        course = CourseDoc.Doc,
        copy = CopyDoc.Doc,
        scenery = SceneryDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        phase = Phase,
        countdown = Float64,
        playerX = Float64,
        speed = Float64,
        totalProgress = Float64,
        lap = Int32,
        elapsedTime = Float64,
        rank = Int32,
        rivals = List[Rival],
        score = Int32,
        energy = Float64,
        boosting = Bool,
        trackBoosting = Bool,
        throttling = Bool,
        braking = Bool,
        steering = Float64,
        audioStarted = Bool,
        jump = TimedHop.State,
        wallCooldown = Float64,
        bounceVelocity = Float64,
        crashTime = Float64,
        sector = Int32,
        gateFlash = Float64,
        impactFlash = Float64,
        collisionCooldown = Float64,
        onRoad = Bool,
        activeDocsWritten = String
    }

    pub def designWidth(): Float64 = 320.0
    pub def designHeight(): Float64 = 240.0
    pub def playerY(): Float64 = 205.0
    pub def carWidth(): Float64 = 18.0
    pub def carHeight(): Float64 = 30.0
    pub def maxEnergy(): Float64 = 100.0

    /// 入力が無い一拍を作る。テストや bake でも同じ意味を使える。
    pub def noInput(): Input =
        { throttle = false, brake = false, boost = false, steer = 0.0, confirm = false }

    /// 表紙から始まる初期状態。
    pub def initial(docs: Docs): World =
        let rivals = initialRivals(docs#tuning);
        { tuning = docs#tuning,
          theme = docs#theme,
          course = docs#course,
          copy = docs#copy,
          scenery = docs#scenery,
          sprites = docs#sprites,
          phase = Phase.Title,
          countdown = 0.0,
          playerX = designWidth() / 2.0,
          speed = 0.0,
          totalProgress = 0.0,
          lap = 0,
          elapsedTime = 0.0,
          rank = List.length(rivals) + 1,
          rivals = rivals,
          score = 0,
          energy = maxEnergy(),
          boosting = false,
          trackBoosting = false,
          throttling = false,
          braking = false,
          steering = 0.0,
          audioStarted = false,
          jump = TimedHop.grounded(),
          wallCooldown = 0.0,
          bounceVelocity = 0.0,
          crashTime = 0.0,
          sector = 0,
          gateFlash = 0.0,
          impactFlash = 0.0,
          collisionCooldown = 0.0,
          onRoad = true,
          activeDocsWritten = "" }

    def initialRivals(tuning: TuningDoc.Doc): List[Rival] =
        { totalProgress = 72.0, laneOffset = -0.24, cruiseSpeed = tuning#rivalSpeedA, passed = false }
            :: { totalProgress = 132.0, laneOffset = 0.24, cruiseSpeed = tuning#rivalSpeedB, passed = false }
            :: Nil

    /// 1拍進める。場面ごとの意味をここで分け、Controls や View に進行規則を漏らさない。
    pub def step(tick: Tick, world: World): World =
        let advanced = match world#phase {
            case Phase.Title =>
                if (tick#input#confirm) beginCountdown(world) else world
            case Phase.Countdown =>
                tickCountdown(tick#deltaTime, world)
            case Phase.Racing =>
                tickRacing(tick, world)
            case Phase.Finish =>
                if (tick#input#confirm) reset(world) else world
            case Phase.Crashed =>
                tickCrashed(tick#deltaTime, world)
            case Phase.GameOver =>
                if (tick#input#confirm) reset(world)
                else world
        };
        let racing = advanced#phase == Phase.Racing;
        { throttling = racing and tick#input#throttle,
          braking = racing and tick#input#brake,
          steering = if (racing) tick#input#steer else 0.0,
          trackBoosting = racing and advanced#trackBoosting,
          audioStarted = true | advanced }

    /// [遷移: Title→Countdown] 走行値を初期化し、3秒の開始合図へ入る。
    def beginCountdown(world: World): World =
        let fresh = initial(docsOf(world));
        { phase = Phase.Countdown, countdown = 3.0 | fresh }

    /// 残り時間が0になった拍で走行を始める。[遷移: Countdown→Racing]
    def tickCountdown(deltaTime: Float64, world: World): World =
        let remaining = Float64.max(0.0, world#countdown - deltaTime);
        if (remaining <= 0.0)
            { phase = Phase.Racing, countdown = 0.0 | world }
        else
            { countdown = remaining | world }

    /// Racing の一拍。各関数は World を末尾に受け、上から順に一日の流れとして読める。
    def tickRacing(tick: Tick, world: World): World =
        world
            |> steer(tick)
            |> resolveCourseBoundary
            |> resolveOpenCourseFall
            |> refreshRoadContact
            |> changeSpeed(tick)
            |> updateEnergy(tick)
            |> advancePlayer(tick#deltaTime)
            |> advanceJump(tick#deltaTime)
            |> advanceRivals(tick#deltaTime)
            |> resolveCollision
            |> resolvePasses
            |> updateRaceProgress(tick#deltaTime)
            |> tickEffects(tick#deltaTime)

    /// 速度に応じてハンドルを効かせる。停止中も少し動けるため、開始直後に向きを整えられる。
    def steer(tick: Tick, world: World): World =
        let speedRatio = clamp(0.25, 1.15, world#speed / world#tuning#maxSpeed);
        let grip =
            if (TimedHop.isAirborne(world#jump)) world#tuning#airSteerGrip
            else if (world#onRoad) 1.0
            else world#tuning#offRoadGrip;
        let brakeTurn =
            if (tick#input#brake) world#tuning#brakeSteerMultiplier else 1.0;
        let steeringMovement = tick#input#steer * world#tuning#steerSpeed
            * speedRatio * grip * brakeTurn * tick#deltaTime;
        let bounceMovement = world#bounceVelocity * tick#deltaTime;
        let halfWidth = carWidth() / 2.0;
        { playerX = clamp(
              halfWidth, designWidth() - halfWidth,
              world#playerX + steeringMovement + bounceMovement) | world }

    /// 路肩のさらに外へ出た時、車体を路面内へ戻してエネルギーを失う。
    /// 壁の待ち時間中も位置だけは戻し、1回の接触を毎拍の損傷に数えない。
    def resolveCourseBoundary(world: World): World =
        let road = Course.sample(
            { totalProgress = world#totalProgress, screenWidth = designWidth() },
            world#course);
        let roadLeft = road#centerX - road#width / 2.0;
        let roadRight = road#centerX + road#width / 2.0;
        let shoulderWidth = carWidth() * 0.35;
        let hitLeft = world#playerX < roadLeft - shoulderWidth;
        let hitRight = world#playerX > roadRight + shoulderWidth;
        let safeLeft = roadLeft + carWidth() / 2.0;
        let safeRight = roadRight - carWidth() / 2.0;
        if (TimedHop.isAirborne(world#jump)
            or not Course.hasWalls(world#totalProgress, world#course)
            or (not hitLeft and not hitRight))
            world
        else {
            let inward = if (hitLeft) world#tuning#wallBounceSpeed
                         else -world#tuning#wallBounceSpeed;
            let safeX = if (hitLeft) safeLeft else safeRight;
            let bounded = { playerX = safeX, bounceVelocity = inward | world };
            if (world#wallCooldown > 0.0)
                bounded
            else
                bounded
                    |> applyDamage({
                        energyLoss = world#tuning#collisionEnergyLoss,
                        speedLoss = world#tuning#collisionSpeedLoss
                    })
                    |> (damaged -> {
                        wallCooldown = 0.55,
                        impactFlash = 0.48 | damaged
                    })
        }

    /// 壁のない区間でも、車体の一部が出ただけでは従来どおり路外減速に留める。
    /// 端から十分離れた時だけ落下にするのは、細い道で立て直す余地を残すため。
    def resolveOpenCourseFall(world: World): World =
        let road = Course.sample(
            { totalProgress = world#totalProgress, screenWidth = designWidth() },
            world#course);
        let leftEdge = road#centerX - road#width / 2.0;
        let rightEdge = road#centerX + road#width / 2.0;
        let fellLeft = world#playerX < leftEdge - world#tuning#fallMargin;
        let fellRight = world#playerX > rightEdge + world#tuning#fallMargin;
        if (world#phase != Phase.Racing
            or TimedHop.isAirborne(world#jump)
            or Course.hasWalls(world#totalProgress, world#course)
            or (not fellLeft and not fellRight))
            world
        else
            { phase = Phase.Crashed,
              energy = 0.0,
              speed = 0.0,
              boosting = false,
              trackBoosting = false,
              crashTime = 0.0,
              impactFlash = 0.8 | world }

    /// アクセル、ブレーキ、自然減速から次の速度を作る。
    /// 路外では毎拍係数を掛けず、秒あたり一定量を落とすため、フレーム数で手触りが変わらない。
    def changeSpeed(tick: Tick, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else {
        let boosting = canManualBoost(tick#input, world)
            or canTrackBoost(tick#input, world);
        let normalMax = world#tuning#maxSpeed;
        let boostMax = Float64.max(normalMax, world#tuning#boostMaxSpeed);
        let offRoadMax = Float64.min(normalMax, world#tuning#offRoadMaxSpeed);
        let requested =
            if (tick#input#brake)
                world#speed - world#tuning#brakePower * tick#deltaTime
            else if (boosting)
                world#speed + world#tuning#boostAcceleration * tick#deltaTime
            else if (world#speed > normalMax)
                world#speed - world#tuning#coastDrag * tick#deltaTime
            else if (tick#input#throttle)
                world#speed + world#tuning#acceleration * tick#deltaTime
            else
                world#speed - world#tuning#coastDrag * tick#deltaTime;
        let speedLimit = if (boosting) boostMax else Float64.max(normalMax, world#speed);
        let roadLimited =
            if (world#onRoad or TimedHop.isAirborne(world#jump) or requested <= offRoadMax)
                requested
            else
                Float64.max(offRoadMax,
                    requested - world#tuning#offRoadDrag * tick#deltaTime);
        { speed = clamp(0.0, speedLimit, roadLimited) | world }
        }

    /// 手動ブーストは路面上または空中で、エネルギー有り・ブレーキ無しの時だけ使える。
    def canManualBoost(input: Input, world: World): Bool =
        input#boost
            and not input#brake
            and (world#onRoad or TimedHop.isAirborne(world#jump))
            and world#energy > 0.0

    /// コースの `=` 上ではエネルギーを使わず加速する。
    def canTrackBoost(input: Input, world: World): Bool =
        not input#brake
            and world#onRoad
            and not TimedHop.isAirborne(world#jump)
            and Course.isBoostStrip(world#totalProgress, world#course)

    /// 手動ブーストだけがエネルギーを使い、加速帯では回復を続ける。
    def updateEnergy(tick: Tick, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else {
        let manualBoost = canManualBoost(tick#input, world);
        let trackBoost = canTrackBoost(tick#input, world);
        let energy =
            if (trackBoost)
                world#energy + world#tuning#energyRecharge * tick#deltaTime
            else if (manualBoost)
                world#energy - world#tuning#boostDrain * tick#deltaTime
            else if (tick#input#boost)
                world#energy
            else
                world#energy + world#tuning#energyRecharge * tick#deltaTime;
        { energy = clamp(0.0, maxEnergy(), energy),
          boosting = manualBoost or trackBoost,
          trackBoosting = trackBoost | world }
            |> crashIfDepleted
        }

    def advancePlayer(deltaTime: Float64, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else {
            let progress = world#totalProgress + world#speed * deltaTime;
            let crossedRamp = Course.crossedJumpRamp({
                fromProgress = world#totalProgress,
                toProgress = progress
            }, world#course);
            { totalProgress = progress,
              jump =
                  if (crossedRamp and not TimedHop.isAirborne(world#jump))
                      TimedHop.start(world#tuning#jumpDuration, world#jump)
                  else
                      world#jump | world }
                |> refreshRoadContact
        }

    /// TimedHopの時間を進める。高さはTimedHop.heightからViewが導くため、Worldには座標を置かない。
    def advanceJump(deltaTime: Float64, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else
            { jump = TimedHop.step(deltaTime, world#jump) | world }

    /// 現在位置と操舵後のXから路面内外を導き、古い接地状態を次の規則へ渡さない。
    def refreshRoadContact(world: World): World =
        let road = Course.sample(
            { totalProgress = world#totalProgress, screenWidth = designWidth() },
            world#course);
        let onRoad = Course.contains({ centerX = world#playerX, halfWidth = carWidth() / 2.0 }, road);
        { onRoad = onRoad | world }

    def advanceRivals(deltaTime: Float64, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else
            { rivals = world#rivals
                |> List.map(rival -> {
                    totalProgress = rival#totalProgress + rival#cruiseSpeed * deltaTime | rival
                })
              | world }

    /// 車体が近い時だけ速度を失う。同じ接触を毎拍数えないよう短い待ち時間を置く。
    def resolveCollision(world: World): World =
        if (world#phase != Phase.Racing
            or TimedHop.isAirborne(world#jump)
            or world#collisionCooldown > 0.0) world
        else {
            let collided = world#rivals |> List.exists(rival -> touchesPlayer(rival, world));
            if (collided)
                world
                    |> applyDamage({
                        energyLoss = world#tuning#collisionEnergyLoss,
                        speedLoss = world#tuning#collisionSpeedLoss
                    })
                    |> (damaged -> {
                        impactFlash = 0.45,
                        collisionCooldown = 0.65 | damaged
                    })
            else
                world
        }

    /// 損傷源に共通する収支。0になった拍は完走判定より先に爆発へ入る。
    def applyDamage(damage: { energyLoss = Float64, speedLoss = Float64 },
                    world: World): World =
        let energy = Float64.max(0.0, world#energy - damage#energyLoss);
        { energy = energy,
          speed = if (energy <= 0.0)
                      0.0
                  else
                      Float64.max(0.0, world#speed - damage#speedLoss),
          phase = if (energy <= 0.0) Phase.Crashed else world#phase,
          boosting = if (energy <= 0.0) false else world#boosting,
          crashTime = if (energy <= 0.0) 0.0 else world#crashTime | world }

    /// ブーストを使い切った時も、共用エネルギーが0なら爆発へ入る。
    def crashIfDepleted(world: World): World =
        if (world#energy <= 0.0)
            { phase = Phase.Crashed, speed = 0.0, boosting = false,
              trackBoosting = false, crashTime = 0.0 | world }
        else
            world

    def touchesPlayer(rival: Rival, world: World): Bool =
        let rivalRoad = Course.sample(
            { totalProgress = rival#totalProgress, screenWidth = designWidth() }, world#course);
        let rivalX = Course.laneCenter(rival#laneOffset, rivalRoad);
        Float64.abs(rival#totalProgress - world#totalProgress) <= carHeight()
            and Float64.abs(rivalX - world#playerX) <= carWidth()

    /// 初めて抜いたライバルだけを印付けし、得点を一度だけ加える。
    def resolvePasses(world: World): World =
        if (world#phase != Phase.Racing)
            world
        else {
            let newlyPassed = rival -> not rival#passed and world#totalProgress >= rival#totalProgress;
            let count = List.count(newlyPassed, world#rivals);
            let rivals = world#rivals
                |> List.map(rival -> if (newlyPassed(rival)) { passed = true | rival } else rival);
            { rivals = rivals,
              score = world#score + count * world#tuning#scorePerPass,
              rank = rankOf(world#totalProgress, rivals) | world }
        }

    /// 周回、区間、順位、時間を更新し、規定周回へ達したら結果を凍結する。
    def updateRaceProgress(deltaTime: Float64, world: World): World =
        if (world#phase != Phase.Racing)
            world
        else {
            let length = Course.lapLength(world#course);
            let completedLaps = floorToInt(world#totalProgress / length);
            let nextSector = Course.sectorIndex(world#totalProgress, world#course);
            let sectorChanged = nextSector != world#sector;
            let rank = rankOf(world#totalProgress, world#rivals);
            let elapsedTime = world#elapsedTime + deltaTime;
            if (completedLaps >= world#tuning#totalLaps)
                { phase = Phase.Finish,
                  lap = world#tuning#totalLaps,
                  elapsedTime = elapsedTime,
                  rank = rank,
                  score = world#score + world#tuning#finishBonus | world }
            else
                { lap = completedLaps,
                  elapsedTime = elapsedTime,
                  rank = rank,
                  sector = nextSector,
                  gateFlash = if (sectorChanged) 0.6 else world#gateFlash | world }
        }

    def tickEffects(deltaTime: Float64, world: World): World =
        { gateFlash = Float64.max(0.0, world#gateFlash - deltaTime),
          impactFlash = Float64.max(0.0, world#impactFlash - deltaTime),
          collisionCooldown = Float64.max(0.0, world#collisionCooldown - deltaTime),
          wallCooldown = Float64.max(0.0, world#wallCooldown - deltaTime),
          bounceVelocity = approachZero(
              world#bounceVelocity, world#tuning#wallBounceSpeed * 3.2 * deltaTime) | world }

    /// 0.85秒は入力・順位・時間を止めて爆発を見せ、その後に再挑戦画面へ移る。
    def tickCrashed(deltaTime: Float64, world: World): World =
        let elapsed = world#crashTime + deltaTime;
        { crashTime = elapsed,
          phase = if (elapsed >= 0.85) Phase.GameOver else Phase.Crashed,
          impactFlash = Float64.max(0.0, world#impactFlash - deltaTime) | world }

    def rankOf(playerProgress: Float64, rivals: List[Rival]): Int32 =
        1 + List.count(rival -> rival#totalProgress > playerProgress, rivals)

    /// Finish から同じ Doc の表紙へ戻る。[遷移: Finish→Title]
    def reset(world: World): World =
        initial(docsOf(world))

    def docsOf(world: World): Docs =
        { tuning = world#tuning,
          theme = world#theme,
          course = world#course,
          copy = world#copy,
          scenery = world#scenery,
          sprites = world#sprites }

    /// 数値の保存即反映。ライバルの巡航速度も新しい値へそろえる。
    pub def withTuning(tuning: TuningDoc.Doc, world: World): World =
        let rivals = world#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (index, rival) = entry;
            let speed = if (index == 0) tuning#rivalSpeedA else tuning#rivalSpeedB;
            { cruiseSpeed = speed | rival }
        });
        { tuning = tuning, rivals = rivals | world }

    pub def withTheme(theme: ThemeDoc.Doc, world: World): World = { theme = theme | world }
    pub def withCopy(copy: CopyDoc.Doc, world: World): World = { copy = copy | world }
    pub def withScenery(scenery: SceneryDoc.Doc, world: World): World =
        { scenery = scenery | world }
    pub def withSprites(sprites: PxSpriteDoc.Doc, world: World): World =
        { sprites = sprites | world }

    /// コース構造が変わった時は表紙へ戻す。進行中の距離を別形の道へ無理に当てないため。
    pub def resetWithCourse(course: CourseDoc.Doc, world: World): World =
        { audioStarted = world#audioStarted |
          initial({
              tuning = world#tuning,
              theme = world#theme,
              course = course,
              copy = world#copy,
              scenery = world#scenery,
              sprites = world#sprites
          }) }

    /// Studio に「いま表示している Doc」を知らせる。
    pub def activeDocs(_world: World): List[(String, List[String])] =
        ("course", CourseDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("copy", CopyDoc.path() :: Nil)
            :: ("tuning", TuningDoc.path() :: Nil)
            :: ("scenery", SceneryDoc.path() :: Nil)
            :: ("sprite", SceneryDoc.spritePath() :: Nil)
            :: Nil

    def floorToInt(value: Float64): Int32 =
        Float64.floor(value) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    def clamp(lower: Float64, upper: Float64, value: Float64): Float64 =
        Float64.max(lower, Float64.min(upper, value))

    def approachZero(value: Float64, amount: Float64): Float64 =
        if (value > 0.0) Float64.max(0.0, value - amount)
        else Float64.min(0.0, value + amount)
}
