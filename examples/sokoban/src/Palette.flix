// Palette — role-named color constants picked from DB32 (DawnBringer 32), the project's
// standard palette.
//
// Convention: drawing code never hardcodes color literals; it refers only to the role
// names defined here. Each def returns the exact DB32 hex value normalized by /255
// (no eyeballing, no approximation). Limiting choices to 32 colors removes the paralysis
// of color picking. Role names are added in the chapter that first uses them.

mod Palette {

    // ── Background ──
    def background(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── Wooden crate ──
    pub def cratePlank(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}  // #8f563b
    pub def crateFrame(): Color = {r = 0.400000f32, g = 0.223529f32, b = 0.192157f32}  // #663931
    pub def crateSeam(): Color  = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c
    pub def crateBrace(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32}  // #d9a066

    // ── Robot (the player) ──
    pub def robotBody(): Color = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    pub def robotTrim(): Color = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}  // #639bff
    pub def robotEye(): Color  = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    pub def robotDark(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    pub def robotAccent(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236

    // ── Board tiles ──
    pub def wallFace(): Color  = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a
    pub def wallTop(): Color   = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}  // #847e87
    pub def wallShade(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def floorTile(): Color = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32}  // #323c39
    pub def goalMark(): Color  = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550

    // ── Rewind clock ──
    pub def clockFace(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
    pub def clockRim(): Color  = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    // ── Text ──
    pub def titleText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
    pub def clearText(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236

    // background equals the clearColor in project.json; this is the code-side accessor.
    pub def clearColor(): Color = background()
}
