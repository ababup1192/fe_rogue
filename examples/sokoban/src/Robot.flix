// Robot — the player character: a tall one-eyed robot ("cyclops"), drawn procedurally
// like the crate. One function returns the parts for any facing direction and any
// walk phase; the pose is a pure function of (dir, phase), never a piece of state.
//
// All four facings share the same ground row and height. The side views use a
// noticeably narrower body slab (profile depth, not front width), one L-bent near-side
// arm instead of two arms flanking the body, and a single foot block at rest — the
// layout a profile silhouette needs, not a front view with the arms trimmed.
//
// The eye is a true circle (a box with cornerRadius = half its size). In profile it is
// a snail-eye lens: the ball bulges ~1.4 units past the leading edge — the one
// deliberate break of the silhouette — held on by a base chord ~4 units tall at the
// edge, so it reads attached, not floating; a body-colored bar hides the part of the
// ball inside the body. The pupil is a capsule squashed to ~55% of its height — a
// disc stuck on the sphere seen edge-on — placed at the lens tip.
//
// The walk-in-place cycle has four beats: rest -> step -> rest -> step. Front and back
// views read a step as a foot lift plus a body bounce, with the arms stretching and
// shrinking in counter-phase (shoulders pinned) — swinging arms seen head-on; the
// profile reads it as a stride — the foot block splits into a front/back pair, the
// forearm swings (back on one step, forward on the next, like alternating arms), and
// the body dips slightly between the spread feet. The eye rides the body's motion on
// every facing: the robot bounces as one creature, gaze included. phase 0.0 is the
// rest pose — a standing robot and a walking robot are the same function at different
// phases.
//
// Parts are laid out on a 16-unit tile grid and scaled by the requested tile size,
// so the same function serves the 8x gallery and the in-game tile.

mod Robot {

    /// One part on the 16-unit grid. r > 0 rounds the corners (r = min(w,h)/2 = circle).
    type alias Part = {
        x = Float64, y = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    /// Walk pose derived from the phase, in grid units. bob/liftL/liftR drive the
    /// front and back views (body raise, per-foot lift); stride/swing drive the
    /// profile (feet opening front/back, forearm shift along the walk axis). swing's
    /// sign also picks which front/back arm shrinks and which stretches on a step.
    type alias Pose = {
        bob = Float64, liftL = Float64, liftR = Float64,
        stride = Float64, swing = Float64
    }

    /// All parts of the robot facing `dir` at walk phase `phase` (0..1, 0 = rest pose),
    /// centered at `center`, on a tile of `size` px.
    pub def parts(center: Vec2.Vec2, size: Float64, dir: Dir4.Dir4,
                  phase: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let pose = poseOf(phase);
        let ps = match dir {
            case Dir4.Down  => front(pose)
            case Dir4.Up    => back(pose)
            case Dir4.Right => side(pose)
            case Dir4.Left  => List.map(mirrorX, side(pose))
        };
        List.map(toItem(center, size), ps)

    /// Four beats per cycle: rest -> step -> rest -> step. Step beats lift a foot
    /// 1.5 units and bounce the body 1 unit (front/back views), and open the stride
    /// with the forearm swung back on the first step and forward on the second
    /// (profile). phase 0 is exactly the rest pose.
    def poseOf(phase: Float64): Pose =
        let p = phase - Float64.floor(phase);
        if (p < 0.25)      { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else if (p < 0.5)  { bob = 1.0, liftL = 1.5, liftR = 0.0, stride = 1.0, swing = -1.0 }
        else if (p < 0.75) { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else               { bob = 1.0, liftL = 0.0, liftR = 1.5, stride = 1.0, swing = 1.0 }

    // ── Facings (16-unit grid, y down, ground row shared at y = 15.5) ──
    // Everything except planted feet rides the walk motion (bounce or dip), eye included.

    /// Front (Down): the round single eye sits centered. The reference facing.
    /// The arms stretch and shrink in counter-phase while walking — the foreshortened
    /// look of arms swinging fore and aft seen head-on — shoulders pinned, hems moving.
    def front(pose: Pose): List[Part] =
        let b = pose#bob;
        let a = 1.2 * pose#swing;
        part(4.5, 2.0 - b, 7.0, 12.0, Palette.robotBody(), 0) ::        // body slab
        part(4.5, 2.0 - b, 7.0, 1.0, Palette.robotTrim(), 1) ::         // top highlight
        round(6.0, 4.0 - b, 4.0, 4.0, Palette.robotEye(), 1) ::         // eye (true circle)
        round(7.1, 5.1 - b, 1.8, 1.8, Palette.robotDark(), 2) ::        // pupil
        part(6.0, 9.6 - b, 4.0, 0.7, Palette.robotDark(), 1) ::         // mouth line
        part(5.4, 11.0 - b, 1.2, 0.6, Palette.robotAccent(), 1) ::      // vent 1
        part(5.4, 12.0 - b, 1.2, 0.6, Palette.robotAccent(), 1) ::      // vent 2
        part(3.0, 5.0 - b, 1.5, 5.0 - a, Palette.robotTrim(), 0) ::     // left arm
        part(11.5, 5.0 - b, 1.5, 5.0 + a, Palette.robotTrim(), 0) ::    // right arm
        part(5.0, 14.0 - pose#liftL, 2.5, 1.5, Palette.robotTrim(), 0) ::   // left foot
        part(8.5, 14.0 - pose#liftR, 2.5, 1.5, Palette.robotTrim(), 0) :: Nil  // right foot

    /// Back (Up): no eye; a dark service panel with accent-lit slits is the "you see
    /// its back" sign — the same dark-ground/yellow-line grammar as the front vents.
    /// Arms stretch and shrink in counter-phase while walking, like the front.
    def back(pose: Pose): List[Part] =
        let b = pose#bob;
        let a = 1.2 * pose#swing;
        part(4.5, 2.0 - b, 7.0, 12.0, Palette.robotBody(), 0) ::        // body slab
        part(4.5, 2.0 - b, 7.0, 1.0, Palette.robotTrim(), 1) ::         // top highlight
        part(5.8, 4.0 - b, 4.4, 4.6, Palette.robotDark(), 1) ::         // back panel
        part(6.4, 5.0 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // slit 1
        part(6.4, 6.1 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // slit 2
        part(6.4, 7.2 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // slit 3
        part(3.0, 5.0 - b, 1.5, 5.0 - a, Palette.robotTrim(), 0) ::     // left arm
        part(11.5, 5.0 - b, 1.5, 5.0 + a, Palette.robotTrim(), 0) ::    // right arm
        part(5.0, 14.0 - pose#liftL, 2.5, 1.5, Palette.robotTrim(), 0) ::   // left foot
        part(8.5, 14.0 - pose#liftR, 2.5, 1.5, Palette.robotTrim(), 0) :: Nil  // right foot

    /// Profile (Right): a narrow slab reading as depth, not front width. The eye is a
    /// snail-eye lens: the ball bulges ~1.4 units past the leading edge, held on by a
    /// ~4-unit base chord at the edge; a body-colored bar hides the part of the ball
    /// inside the body, and the squashed capsule pupil sits at the tip. The near-side
    /// arm is an L — upper arm down, forearm bent forward — whose forearm swings with
    /// the stride; the feet are one block at rest that opens into a front/back pair
    /// mid-step, while the whole body (lens included) dips 0.7 units between the
    /// spread feet.
    def side(pose: Pose): List[Part] =
        let d = 0.7 * pose#bob;
        let st = pose#stride;
        let sw = pose#swing;
        part(5.5, 2.0 + d, 5.0, 12.0, Palette.robotBody(), 0) ::        // narrow profile body slab
        part(5.5, 2.0 + d, 5.0, 1.0, Palette.robotTrim(), 1) ::         // top highlight
        round(7.3, 3.7 + d, 4.6, 4.6, Palette.robotEye(), 1) ::         // lens ball, bulging past the leading edge
        round(10.4, 5.1 + d, 1.0, 1.8, Palette.robotDark(), 2) ::       // pupil: edge-on capsule at the lens tip
        part(7.3, 3.7 + d, 3.2, 4.6, Palette.robotBody(), 3) ::         // hides the part of the ball inside the body
        part(6.9, 8.5 + d, 1.4, 2.5, Palette.robotTrim(), 1) ::         // upper arm, hanging below the lens
        part(6.9 + sw, 9.6 + d, 2.6, 1.4, Palette.robotTrim(), 1) ::    // forearm bent forward; swings against the step
        part(6.85 - 1.3 * st, 14.0, 2.3, 1.5, Palette.robotTrim(), 0) ::    // back foot
        part(6.85 + 1.3 * st, 14.0, 2.3, 1.5, Palette.robotTrim(), 0) :: Nil  // front foot; covers the back foot exactly at rest

    // ── Helpers ──

    def part(x: Float64, y: Float64, w: Float64, h: Float64, c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = 0.0, color = c, z = z }

    def round(x: Float64, y: Float64, w: Float64, h: Float64, c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = Float64.min(w, h) / 2.0, color = c, z = z }

    /// Mirror a part across the tile's vertical center line (Left = mirrored Right).
    def mirrorX(p: Part): Part =
        { x = 16.0 - p#x - p#w | p }

    def toItem(center: Vec2.Vec2, size: Float64, p: Part): (Vec2.Vec2, Render.RenderItem) =
        let s = size / 16.0;
        let tlx = center#x - size / 2.0;
        let tly = center#y - size / 2.0;
        let pos = {x = tlx + p#x * s, y = tly + p#y * s};
        let dim = {x = p#w * s, y = p#h * s};
        if (p#r <= 0.0)
            (pos, Render.solidBox(dim, p#color, p#z))
        else {
            let style = { cornerRadius = p#r * s, borderWidth = 0.0, borderColor = p#color,
                          borderAlpha = 0.0f32, stripeColor = p#color, stripeAlpha = 0.0f32,
                          stripeWidth = 0.0, stripePeriod = 0.0 };
            (pos, Render.RenderItem.Box({ size = dim, color = p#color, alpha = 1.0f32,
                                          style = Some(style), zIndex = p#z }))
        }
}
