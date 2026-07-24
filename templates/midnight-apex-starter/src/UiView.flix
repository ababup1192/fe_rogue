// UiView — 走行状態をHUD、警告、場面の幕へ写す純粋な表示層。
// 道路の遠近や機体配置を扱わず、画面情報の読みやすさだけを受け持つ。
mod UiView {

    /// HUDと場面幕を一つのリストへまとめる。
    pub def frame(atlas: FontAtlas, world: World.World): List[Render.PlacedItem] =
        List.flatten(
               hud(atlas, world)
            :: feedback(atlas, world)
            :: overlay(atlas, world)
            :: Nil)

    /// 走行情報を置く描画順。
    def zHud(): Int32 = 70

    /// 場面の幕を置く描画順。
    def zOverlay(): Int32 = 90

    /// 順位・周回・速度に加え、ブースト資源を一本のメーターで示す。
    def hud(atlas: FontAtlas, world: World.World): List[Render.PlacedItem] =
        if (world#phase == World.Phase.Title) Nil
        else {
            let totalCars = List.length(world#rivals) + 1;
            let shownLap = Int32.min(world#lap + 1, world#tuning#totalLaps);
            let energyWidth = 112.0 * world#energy / World.maxEnergy();
               fadedBoxAt(
                   { x = 160.0, y = 15.0 }, { x = 304.0, y = 26.0 },
                   world#theme#night, 0.88f32, zHud())
            :: textAt(
                   "${world#copy#positionLabel} ${Int32.toString(world#rank)}/${Int32.toString(totalCars)}",
                   { x = 18.0, y = 6.0 }, 7.5, world#theme#text, atlas)
            :: textAt(
                   "${world#copy#lapLabel} ${Int32.toString(shownLap)}/${Int32.toString(world#tuning#totalLaps)}",
                   { x = 116.0, y = 6.0 }, 7.5, world#theme#text, atlas)
            :: textAt(
                   "${world#copy#speedLabel} ${Int32.toString(floorToInt(world#speed * 1.35))}",
                   { x = 211.0, y = 6.0 }, 7.5, world#theme#lane, atlas)
            :: textAt(
                   world#copy#energyLabel,
                   { x = 18.0, y = 17.0 }, 6.0, world#theme#muted, atlas)
            :: Render.boxAt(
                   { x = 132.0, y = 20.0 }, { x = 114.0, y = 5.0 },
                   ThemeDoc.darken(world#theme#road, 0.56), zHud() + 1)
            :: Render.boxAt(
                   { x = 75.0 + energyWidth / 2.0, y = 20.0 },
                   { x = energyWidth, y = 3.0 },
                   if (world#boosting) world#theme#player else world#theme#shoulder,
                   zHud() + 2)
            :: textAt(
                   "${world#copy#timeLabel} ${timeText(world#elapsedTime)}",
                   { x = 205.0, y = 17.0 }, 6.0, world#theme#muted, atlas)
            :: Nil
        }

    /// 路外、区間通過、接触を短い画面反応として重ねる。
    def feedback(atlas: FontAtlas, world: World.World): List[Render.PlacedItem] =
        let offRoad =
            if (world#phase == World.Phase.Racing and not world#onRoad)
                fadedBoxAt(
                    { x = 160.0, y = 120.0 }, { x = 312.0, y = 232.0 },
                    world#theme#danger, 0.13f32, zHud() - 1)
                :: centered(atlas, world#copy#offRoadLabel, 12.0,
                            world#theme#danger, 40.0, zHud())
                :: Nil
            else Nil;
        let gate =
            if (world#gateFlash > 0.0)
                centered(
                    atlas,
                    "${world#copy#sectorLabel} ${Int32.toString(world#sector + 1)}/${Int32.toString(Course.sectorCount())}",
                    13.0, world#theme#lane, 43.0, zHud()) :: Nil
            else Nil;
        let impact =
            if (world#impactFlash > 0.0)
                fadedBoxAt(
                    { x = 160.0, y = 120.0 }, { x = 320.0, y = 240.0 },
                    world#theme#danger, 0.20f32, zHud() - 1) :: Nil
            else Nil;
        offRoad ::: gate ::: impact

    /// Title、Countdown、Finish の情報を、走行画面を隠しすぎない範囲で重ねる。
    def overlay(atlas: FontAtlas, world: World.World): List[Render.PlacedItem] =
        match world#phase {
            case World.Phase.Title =>
                   centered(atlas, world#copy#titleTop, 11.0,
                            world#theme#shoulder, 28.0, zOverlay())
                :: centered(atlas, world#copy#titleMain, 43.0,
                            world#theme#player, 43.0, zOverlay())
                :: centered(atlas, world#copy#tagline, 9.0,
                            world#theme#text, 78.0, zOverlay())
                :: fadedBoxAt(
                       { x = 160.0, y = 118.0 }, { x = 252.0, y = 62.0 },
                       world#theme#night, 0.76f32, zOverlay())
                :: centered(atlas, world#copy#steerHint, 8.5,
                            world#theme#muted, 94.0, zOverlay() + 1)
                :: centered(atlas, world#copy#speedHint, 8.0,
                            world#theme#muted, 109.0, zOverlay() + 1)
                :: centered(atlas, world#copy#boostHint, 8.5,
                            world#theme#player, 124.0, zOverlay() + 1)
                :: centered(atlas, world#copy#startHint, 11.0,
                            world#theme#lane, 146.0, zOverlay() + 1)
                :: Nil
            case World.Phase.Countdown =>
                   fadedBoxAt(
                       { x = 160.0, y = 112.0 }, { x = 170.0, y = 92.0 },
                       world#theme#night, 0.62f32, zOverlay())
                :: centered(atlas, world#copy#readyLabel, 10.0,
                            world#theme#muted, 82.0, zOverlay() + 1)
                :: centered(
                       atlas, Int32.toString(ceilToInt(world#countdown)),
                       48.0, world#theme#lane, 99.0, zOverlay() + 1)
                :: Nil
            case World.Phase.Finish =>
                   fadedBoxAt(
                       { x = 160.0, y = 120.0 }, { x = 278.0, y = 150.0 },
                       world#theme#night, 0.82f32, zOverlay())
                :: centered(atlas, world#copy#finishTitle, 35.0,
                            world#theme#lane, 55.0, zOverlay() + 1)
                :: centered(
                       atlas,
                       "${world#copy#positionLabel} ${Int32.toString(world#rank)}/${Int32.toString(List.length(world#rivals) + 1)}",
                       13.0, world#theme#text, 112.0, zOverlay() + 1)
                :: centered(
                       atlas, "${world#copy#timeLabel} ${timeText(world#elapsedTime)}",
                       11.0, world#theme#text, 137.0, zOverlay() + 1)
                :: centered(atlas, world#copy#retryHint, 10.0,
                            world#theme#player, 170.0, zOverlay() + 1)
                :: Nil
            case World.Phase.Crashed =>
                centered(atlas, world#copy#crashedTitle, 16.0,
                         world#theme#danger, 62.0, zOverlay() + 1) :: Nil
            case World.Phase.GameOver =>
                   fadedBoxAt(
                       { x = 160.0, y = 120.0 }, { x = 278.0, y = 126.0 },
                       world#theme#night, 0.82f32, zOverlay())
                :: centered(atlas, world#copy#gameOverTitle, 26.0,
                            world#theme#danger, 82.0, zOverlay() + 1)
                :: centered(atlas, world#copy#retryHint, 10.0,
                            world#theme#player, 150.0, zOverlay() + 1)
                :: Nil
            case World.Phase.Racing => Nil
        }

    /// 左上基準の文字を置く。
    def textAt(text: String, at: Vec2.Vec2, size: Float64, color: Color,
               atlas: FontAtlas): Render.PlacedItem =
        { at = at, item = Render.textTinted(text, atlas, size, color, zHud() + 1) }

    /// 横中央へ文字を置く。
    def centered(atlas: FontAtlas, text: String, size: Float64, color: Color,
                 y: Float64, z: Int32): Render.PlacedItem =
        TextDraw.centered({
            text = text, atlas = atlas, size = size, color = color,
            z = z, centerX = World.designWidth() / 2.0, y = y
        })

    /// 透明度つきの箱を中心座標で置く。
    def fadedBoxAt(center: Vec2.Vec2, size: Vec2.Vec2, color: Color,
                   alpha: Float32, z: Int32): Render.PlacedItem =
        { at = { x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
          item = Render.box(size, color, z) |> Render.fade(alpha) }

    /// 経過秒を小数1桁へそろえる。
    def timeText(seconds: Float64): String =
        let tenths = Float64.floor(seconds * 10.0) / 10.0;
        Float64.toString(tenths)

    /// 非負の値を切り捨てて整数表示へ変える。
    def floorToInt(value: Float64): Int32 =
        Float64.floor(value) |> Float64.tryToInt32 |> Option.getWithDefault(0)

    /// カウントダウンだけは切り上げ、開始直後に0を長く見せない。
    def ceilToInt(value: Float64): Int32 =
        Float64.ceil(value) |> Float64.tryToInt32 |> Option.getWithDefault(0)
}
