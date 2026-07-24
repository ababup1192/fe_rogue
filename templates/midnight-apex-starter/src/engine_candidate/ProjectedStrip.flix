// ProjectedStrip — 遠近投影された2断面の間へ、面や目印を描く部品。
mod ProjectedStrip {

    /// 近側と遠側で幅・持ち上げ量が異なる台形を描く。
    pub def quad(near: Perspective.Slice[a], far: Perspective.Slice[a],
                 nearHalf: Float64, farHalf: Float64,
                 nearLift: Float64, farLift: Float64,
                 color: Color, z: Int32): Render.PlacedItem =
        let vertices =
            { x = near#centerX - nearHalf, y = near#y - nearLift }
            :: { x = near#centerX + nearHalf, y = near#y - nearLift }
            :: { x = far#centerX + farHalf, y = far#y - farLift }
            :: { x = far#centerX - farHalf, y = far#y - farLift }
            :: Nil;
        { at = Vec2.zero(), item = Render.polygon(vertices, color, z) }

    /// 断面を横切る線を描く。
    pub def crossbar(slice: Perspective.Slice[a], halfWidth: Float64,
                     lift: Float64, width: Float64,
                     color: Color, z: Int32): Render.PlacedItem =
        Render.lineSeg(
            { x = slice#centerX - halfWidth, y = slice#y - lift },
            { x = slice#centerX + halfWidth, y = slice#y - lift },
            width, color, z)

    /// 道路断面を囲うコの字型の骨組み。
    pub def rib(slice: Perspective.Slice[a], height: Float64, width: Float64,
                leftColor: Color, rightColor: Color,
                z: Int32): List[Render.PlacedItem] =
        let left = { x = slice#centerX - slice#halfWidth, y = slice#y };
        let right = { x = slice#centerX + slice#halfWidth, y = slice#y };
        let leftTop = { x = left#x, y = left#y - height };
        let rightTop = { x = right#x, y = right#y - height };
           Render.lineSeg(left, leftTop, width, leftColor, z)
        :: Render.lineSeg(leftTop, rightTop, width, leftColor, z)
        :: Render.lineSeg(rightTop, right, width, rightColor, z)
        :: Nil

    /// 道の左右端へ、同じ奥行きの発光標識を置く。
    pub def beacons(slice: Perspective.Slice[a], size: Float64,
                    leftColor: Color, rightColor: Color,
                    leftAlpha: Float64, rightAlpha: Float64,
                    z: Int32): List[Render.PlacedItem] =
        Render.glowAt(
            { x = slice#centerX - slice#halfWidth, y = slice#y },
            size, leftColor,
            { alpha = leftAlpha, blend = DrawCmd.BlendMode.Add }, z)
        ::: Render.glowAt(
            { x = slice#centerX + slice#halfWidth, y = slice#y },
            size, rightColor,
            { alpha = rightAlpha, blend = DrawCmd.BlendMode.Add }, z)
}
