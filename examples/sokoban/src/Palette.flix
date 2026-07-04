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

    // ── Text ──
    pub def titleText(): Color = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a

    // background equals the clearColor in project.json; this is the code-side accessor.
    pub def clearColor(): Color = background()
}
