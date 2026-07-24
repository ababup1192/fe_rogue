// View — World を未来都市の後方視点レースへ写す純粋な描画層。
// 道、ゲート、ライバルは Perspective を共有し、同じ奥行きに置かれる。
mod View {

    /// 描画順を意味ごとに固定する。
    type alias Layers = {
        sky = Int32,
        road = Int32,
        rail = Int32,
        rival = Int32,
        player = Int32
    }

    /// World を一枚の画面へ写す入口。
    pub def frame(context: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        List.flatten(
               background(world)
            :: SceneryView.draw(world, layers()#sky + 5)
            :: speedLines(world)
            :: road(world)
            :: rivals(world)
            :: player(world)
            :: Nil)
        ::: UiView.frame(context#atlas, world)

    /// 各描画群の前後関係。
    def layers(): Layers =
        { sky = 0, road = 10, rail = 24, rival = 35, player = 48 }

    /// 夜空、都市のシルエット、地平線の発光帯を敷く。
    def background(world: World.World): List[Render.PlacedItem] =
        let layer = layers();
        let projection = Perspective.config(World.designWidth(), World.designHeight());
        let horizon = projection#horizonY;
        let groundColor =
            if (world#phase == World.Phase.Racing and world#sector == 4)
                world#theme#night
            else
                world#theme#ground;
        let city =
            if (world#phase == World.Phase.Racing and world#sector == 4)
                Nil
            else
                CityscapeView.draw(world, horizon, layer#sky + 3);
           Render.boxAt(
               { x = 160.0, y = 120.0 }, { x = 320.0, y = 240.0 },
               groundColor, layer#sky)
        :: Render.boxAt(
               { x = 160.0, y = horizon / 2.0 },
               { x = 320.0, y = horizon },
               world#theme#night, layer#sky + 1)
        :: Nil
        ::: Render.glowAt(
               { x = 160.0, y = horizon }, 68.0, world#theme#shoulder,
               { alpha = 0.20, blend = DrawCmd.BlendMode.Add }, layer#sky + 2)
        ::: city

    /// 高速時だけ、消失点から外へ広がる流線を前進量に合わせて動かす。
    def speedLines(world: World.World): List[Render.PlacedItem] =
        if (world#phase != World.Phase.Racing
            or world#speed
                < world#tuning#maxSpeed * world#scenery#speedLineThreshold)
            Nil
        else {
            let layer = layers();
            let speedRatio = Float64.min(1.35, world#speed / world#tuning#maxSpeed);
            let length =
                if (world#boosting)
                    world#scenery#boostLineLength
                else
                    world#scenery#speedLineLength;
            let alpha =
                if (world#boosting)
                    world#scenery#boostLineAlpha
                else
                    world#scenery#speedLineAlpha;
            let phase = wrap(world#totalProgress * 1.6, 37.0);
            let projection = Perspective.config(World.designWidth(), World.designHeight());
            List.range(0, 12) |> List.map(index -> {
                let y = projection#horizonY
                    + wrap(Int32.toFloat64(index) * 23.0 + phase, 178.0);
                let side = if (Int32.modulo(index, 2) == 0) -1.0 else 1.0;
                let spread = (y - projection#horizonY) * 0.47;
                let x = 160.0 + side * spread;
                Render.lineSeg(
                    { x = x, y = y },
                    { x = x + side * length * 0.32,
                      y = y + length * speedRatio },
                    if (world#boosting) 2.2 else 1.2,
                    if (Int32.modulo(index, 3) == 0)
                        world#theme#player
                    else
                        world#theme#shoulder,
                    layer#road - 1)
                    |> fadePlaced(alpha * speedRatio)
            })
        }

    /// 奥から手前へ台形を重ね、カーブと道幅を遠近つきの路面にする。
    def road(world: World.World): List[Render.PlacedItem] =
        let projection = Perspective.config(World.designWidth(), World.designHeight());
        let sampleAt = CourseProjection.sampler(
            World.designWidth(), world#course);
        let slices = Perspective.slices(
            visibleProgress(world), sampleAt, projection);
        slices
            |> consecutivePairs
            |> List.reverse
            |> List.zipWithIndex
            |> List.flatMap(entry -> {
                let (index, pair) = entry;
                roadSegment(index, pair, world)
            })

    /// 隣り合う断面を1枚の路面、路肩、中央灯へ変換する。
    def roadSegment(index: Int32,
                    pair: (CourseProjection.Slice, CourseProjection.Slice),
                    world: World.World): List[Render.PlacedItem] =
        let (near, far) = pair;
        let layer = layers();
        let roadColor =
            if (Int32.modulo(near#meta#rowIndex, 2) == 0)
                world#theme#road
            else
                world#theme#roadShade;
        let sector = Course.sectorIndex(near#progress, world#course);
        let leftRail =
            if (sector == 3) world#theme#player
            else if (sector == 4) world#theme#lane
            else world#theme#shoulder;
        let rightRail =
            if (sector == 3) world#theme#rivalB
            else if (sector == 4) world#theme#shoulder
            else world#theme#rivalA;
        let walled = Course.hasWalls(near#progress, world#course);
        let railWidth =
            if (walled) Float64.max(1.5, near#scale * 7.0)
            else Float64.max(0.7, near#scale * 2.0);
        let z = layer#road + index;
        let roadPoly =
            { x = near#centerX - near#halfWidth, y = near#y }
            :: { x = near#centerX + near#halfWidth, y = near#y }
            :: { x = far#centerX + far#halfWidth, y = far#y }
            :: { x = far#centerX - far#halfWidth, y = far#y }
            :: Nil;
        let lane =
            if (Int32.modulo(near#meta#rowIndex, 4) <= 1)
                laneMarker(near, far, world#theme#lane, z + 2)
            else
                Nil;
        let gate =
            if (Course.sectorIndex(near#progress, world#course)
                != Course.sectorIndex(far#progress, world#course))
                gateAt(far, world#theme, layer#rail + index)
            else
                Nil;
        let boost =
            if (Course.isBoostStrip(near#progress, world#course))
                boostPlate(near, far, world#theme, z + 3)
            else
                Nil;
        let jumpRamp =
            if (Course.isJumpRamp(near#progress, world#course))
                jumpPlate(near, far, world#theme, z + 4)
            else
                Nil;
        let landmark = courseLandmark(near, sector, world#theme, layer#rail + index + 2);
           { at = Vec2.zero(), item = Render.polygon(roadPoly, roadColor, z) }
        :: Render.lineSeg(
               { x = near#centerX - near#halfWidth, y = near#y },
               { x = far#centerX - far#halfWidth, y = far#y },
               railWidth,
               leftRail, layer#rail + index)
        :: Render.lineSeg(
               { x = near#centerX + near#halfWidth, y = near#y },
               { x = far#centerX + far#halfWidth, y = far#y },
               railWidth,
               rightRail, layer#rail + index)
        :: lane ::: boost ::: jumpRamp ::: gate ::: landmark

    /// 中央の破線を台形にし、消失点への収束を強める。
    def laneMarker(near: CourseProjection.Slice, far: CourseProjection.Slice,
                   color: Color, z: Int32): List[Render.PlacedItem] =
        let nearHalf = Float64.max(0.5, near#scale * 1.8);
        let farHalf = Float64.max(0.4, far#scale * 1.8);
        ProjectedStrip.quad(near, far, nearHalf, farHalf, 0.0, 0.0, color, z)
            :: Nil

    /// `=` の断面を横切る発光板。World も同じ記号を読んで無料ブーストを与える。
    def boostPlate(near: CourseProjection.Slice, far: CourseProjection.Slice,
                   theme: ThemeDoc.Doc, z: Int32): List[Render.PlacedItem] =
        let nearHalf = near#halfWidth * 0.72;
        let farHalf = far#halfWidth * 0.72;
        (ProjectedStrip.quad(
            near, far, nearHalf, farHalf, 0.0, 0.0, theme#player, z)
            |> fadePlaced(0.48))
        :: ProjectedStrip.crossbar(
               near, nearHalf, 0.0, Float64.max(1.0, near#scale * 4.0),
               theme#lane, z + 1)
        :: Nil

    /// `^` の断面を、手前が持ち上がった黄色い発光台として見せる。
    def jumpPlate(near: CourseProjection.Slice, far: CourseProjection.Slice,
                  theme: ThemeDoc.Doc, z: Int32): List[Render.PlacedItem] =
        let nearHalf = near#halfWidth * 0.82;
        let farHalf = far#halfWidth * 0.76;
        let lift = 15.0 * near#scale;
           (ProjectedStrip.quad(
                near, far, nearHalf, farHalf, lift, 0.0, theme#lane, z)
                |> fadePlaced(0.78))
        :: ProjectedStrip.crossbar(
               near, nearHalf, lift, Float64.max(1.0, near#scale * 4.5),
               theme#player, z + 1)
        :: Nil

    /// 技術区間はトンネル骨格、空中細橋は路肩ビーコンで景色の文法を変える。
    def courseLandmark(slice: CourseProjection.Slice, sector: Int32,
                       theme: ThemeDoc.Doc, z: Int32): List[Render.PlacedItem] =
        if (sector == 3 and Int32.modulo(slice#meta#rowIndex, 3) == 0)
            tunnelRib(slice, theme, z)
        else if (sector == 4 and Int32.modulo(slice#meta#rowIndex, 2) == 0)
            skyBeacons(slice, theme, z)
        else
            Nil

    /// 折り返し区間を囲むネオン骨格。
    def tunnelRib(slice: CourseProjection.Slice, theme: ThemeDoc.Doc,
                  z: Int32): List[Render.PlacedItem] =
        ProjectedStrip.rib(
            slice, 54.0 * slice#scale,
            Float64.max(1.0, slice#scale * 3.0),
            theme#player, theme#rivalB, z)

    /// 空中細橋の端を示す対のビーコン。
    def skyBeacons(slice: CourseProjection.Slice, theme: ThemeDoc.Doc,
                   z: Int32): List[Render.PlacedItem] =
        ProjectedStrip.beacons(
            slice, 12.0 * slice#scale,
            theme#lane, theme#shoulder, 0.62, 0.62, z)

    /// 区間境界を道路幅に沿う浮遊ゲートとして置く。
    def gateAt(slice: CourseProjection.Slice, theme: ThemeDoc.Doc,
               z: Int32): List[Render.PlacedItem] =
        ProjectedStrip.crossbar(
            slice, slice#halfWidth, 0.0,
            Float64.max(1.0, slice#scale * 5.0), theme#lane, z)
        :: ProjectedStrip.beacons(
               slice, 13.0 * slice#scale,
               theme#shoulder, theme#player, 0.72, 0.68, z + 1)

    /// 前方にいるライバルだけを、距離と車線から同じ遠近空間へ置く。
    def rivals(world: World.World): List[Render.PlacedItem] =
        if (world#phase == World.Phase.Title) titleRivals(world)
        else {
            let colors = world#theme#rivalA :: world#theme#rivalB :: Nil;
            let projection = Perspective.config(World.designWidth(), World.designHeight());
            let sampleAt = CourseProjection.sampler(
                World.designWidth(), world#course);
            world#rivals |> List.zipWithIndex |> List.flatMap(entry -> {
                let (index, rival) = entry;
                let distance = rival#totalProgress - world#totalProgress;
                if (distance <= 4.0 or distance >= projection#viewDistance) Nil
                else {
                    let depth = Perspective.depthOfDistance(distance, projection);
                    let slice = Perspective.atDepth(
                        depth, world#totalProgress, sampleAt, projection);
                    let color = List.nth(index, colors)
                        |> Option.getWithDefault(world#theme#rivalA);
                    CarView.draw({
                        center = { x = Perspective.laneX(rival#laneOffset, slice),
                                   y = slice#y - 7.0 * slice#scale },
                        color = color,
                        z = layers()#rival + floorToInt((1.0 - depth) * 10.0),
                        scale = Float64.max(0.25, slice#scale * 0.82),
                        boosting = false,
                        bank = 0.0,
                        thrust = 0.55,
                        silhouette =
                            if (index == 0) CarView.Silhouette.Dart
                            else CarView.Silhouette.Twin
                    })
                }
            })
        }

    /// 表紙では三角隊形を奥行きに置き、開始前から追走構図を見せる。
    def titleRivals(world: World.World): List[Render.PlacedItem] =
        let base = visibleProgress(world);
        let projection = Perspective.config(World.designWidth(), World.designHeight());
        let sampleAt = CourseProjection.sampler(
            World.designWidth(), world#course);
        let far = Perspective.atDepth(0.47, base, sampleAt, projection);
        let mid = Perspective.atDepth(0.28, base, sampleAt, projection);
        CarView.draw({
            center = { x = Perspective.laneX(-0.34, far), y = far#y },
            color = world#theme#rivalA, z = layers()#rival,
            scale = far#scale * 0.78, boosting = true,
            bank = -0.12, thrust = 1.0,
            silhouette = CarView.Silhouette.Dart
        })
        ::: CarView.draw({
            center = { x = Perspective.laneX(0.30, mid), y = mid#y },
            color = world#theme#rivalB, z = layers()#rival + 2,
            scale = mid#scale * 0.78, boosting = false,
            bank = 0.10, thrust = 0.56,
            silhouette = CarView.Silhouette.Twin
        })

    /// 自機を画面下に固定し、ハンドル量だけ路面中央から横へ動かす。
    def player(world: World.World): List[Render.PlacedItem] =
        {
            let sample = Course.sample(
                { totalProgress = visibleProgress(world),
                  screenWidth = World.designWidth() },
                world#course);
            let lateral =
                if (world#phase == World.Phase.Title) 0.0
                else (world#playerX - sample#centerX) * 1.12;
            let height = TimedHop.height(world#tuning#jumpHeight, world#jump);
            let groundCenter = { x = 160.0 + lateral, y = 207.0 };
            let machineCenter = { x = groundCenter#x, y = groundCenter#y - height };
            let airborne = TimedHop.isAirborne(world#jump);
            let speedRatio = Float64.min(
                1.0, world#speed / world#tuning#boostMaxSpeed);
            let thrust = Float64.min(
                1.0, speedRatio * 0.78
                    + if (world#throttling) 0.24 else 0.0);
            let bounceBank =
                if (world#tuning#wallBounceSpeed <= 0.0) 0.0
                else world#bounceVelocity / world#tuning#wallBounceSpeed * 0.22;
            let bank = clamp(-0.34, 0.34, world#steering * 0.30 + bounceBank);
            let shadow =
                if (airborne)
                    Render.ellipseAt(
                        groundCenter,
                        { x = 25.0 - height * 0.20,
                          y = 6.0 - height * 0.04 },
                        ThemeDoc.darken(world#theme#night, 0.48),
                        layers()#player - 2)
                        |> fadePlaced(0.54 - height / world#tuning#jumpHeight * 0.24)
                    :: Nil
                else
                    Nil;
            let machine =
                if (world#phase == World.Phase.Crashed
                    or world#phase == World.Phase.GameOver)
                    Nil
                else
                    CarView.draw({
                        center = machineCenter,
                        color = world#theme#player,
                        z = layers()#player,
                        scale = 1.16 + if (airborne) 0.08 else 0.0,
                        boosting = world#boosting or world#phase == World.Phase.Title,
                        bank = bank,
                        thrust =
                            if (world#phase == World.Phase.Title) 1.0 else thrust,
                        silhouette = CarView.Silhouette.Player
                    });
            shadow ::: machine
                ::: FxView.crash(world, machineCenter, layers()#player + 3)
        }

    /// Title ではS字入口を顔にし、走行中は現在地をそのまま使う。
    def visibleProgress(world: World.World): Float64 =
        if (world#phase == World.Phase.Title)
            Course.rowDistance() * 8.5
        else
            world#totalProgress

    /// 隣接する断面をすべて組にする。
    def consecutivePairs(values: List[CourseProjection.Slice]):
        List[(CourseProjection.Slice, CourseProjection.Slice)] =
        match values {
            case first :: second :: rest =>
                (first, second) :: consecutivePairs(second :: rest)
            case _ => Nil
        }

    /// PlacedItem の位置を保ったまま透明度を変える。
    def fadePlaced(alpha: Float64, placed: Render.PlacedItem): Render.PlacedItem =
        { at = placed#at,
          item = placed#item |> Render.fade(Float64.truncateToFloat32(alpha)) }

    /// 正の値を周期内へ戻し、流線が画面下から消えるたび地平線へ循環させる。
    def wrap(value: Float64, period: Float64): Float64 =
        value - Float64.floor(value / period) * period

    /// 非負の値を切り捨てて整数表示へ変える。
    def floorToInt(value: Float64): Int32 =
        Float64.floor(value) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    /// 表示用の値を安全な範囲へ収める。
    def clamp(lower: Float64, upper: Float64, value: Float64): Float64 =
        Float64.max(lower, Float64.min(upper, value))

}
