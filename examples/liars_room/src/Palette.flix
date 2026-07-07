// Palette — この作品で使う色をぜんぶ名前で持つ（コード中に色リテラルを書かない）。
// 色は DB32 パレットから選ぶ。NPC の色は「見た目の色」と「呼び名」の対応もここが持つ。
mod Palette {

    /// NPC を見分ける 7 色。ステージの NPC 数ぶんだけ先頭から使う。
    pub enum NpcColor with Eq, Order {
        case Blue
        case Green
        case Red
        case Yellow
        case Purple
        case White
        case Orange
    }

    /// id 順（0 = あお、1 = みどり、…）に並べた全色。
    pub def npcColors(): List[NpcColor] =
        NpcColor.Blue :: NpcColor.Green :: NpcColor.Red :: NpcColor.Yellow
            :: NpcColor.Purple :: NpcColor.White :: NpcColor.Orange :: Nil

    /// NPC id → 色。範囲外は bug!（ステージ生成が 7 人以下を保証する）。
    pub def colorOf(id: Int32): NpcColor =
        match List.nth(id, npcColors()) {
            case Some(color) => color
            case None        => bug!("Palette.colorOf: NPC id ${id} は 7 色の範囲外")
        }

    /// 呼び名（発言・メモ・答え合わせの文言で共有する）。
    pub def npcName(color: NpcColor): String = match color {
        case NpcColor.Blue   => "あお"
        case NpcColor.Green  => "みどり"
        case NpcColor.Red    => "あか"
        case NpcColor.Yellow => "きいろ"
        case NpcColor.Purple => "むらさき"
        case NpcColor.White  => "しろ"
        case NpcColor.Orange => "オレンジ"
    }

    /// NPC id → 呼び名（colorOf との合成の近道）。
    pub def nameOf(id: Int32): String =
        npcName(colorOf(id))

    /// シルエットの本体色（DB32）。
    pub def npcBody(color: NpcColor): Color = match color {
        case NpcColor.Blue   => {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
        case NpcColor.Green  => {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32}  // #6abe30
        case NpcColor.Red    => {r = 0.674510f32, g = 0.196078f32, b = 0.196078f32}  // #ac3232
        case NpcColor.Yellow => {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
        case NpcColor.Purple => {r = 0.462745f32, g = 0.258824f32, b = 0.541176f32}  // #76428a
        case NpcColor.White  => {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff
        case NpcColor.Orange => {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}  // #df7126
    }

    /// シルエットの陰色（腕・脚に使う）。DB32 の中から各色の一段暗い隣人を選ぶ。
    pub def npcShade(color: NpcColor): Color = match color {
        case NpcColor.Blue   => {r = 0.247059f32, g = 0.247059f32, b = 0.454902f32}  // #3f3f74
        case NpcColor.Green  => {r = 0.294118f32, g = 0.411765f32, b = 0.184314f32}  // #4b692f
        case NpcColor.Red    => {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c
        case NpcColor.Yellow => {r = 0.541176f32, g = 0.435294f32, b = 0.188235f32}  // #8a6f30
        case NpcColor.Purple => {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c
        case NpcColor.White  => {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}  // #9badb7
        case NpcColor.Orange => {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}  // #8f563b
    }

    /// NPC id → 塗り分け一式（帽子なし）。
    pub def npcSkin(id: Int32): Human.Skin =
        let color = colorOf(id);
        { body = npcBody(color), shade = npcShade(color), hat = None }

    /// プレイヤーの塗り分け（黒いシルエット + 焦げ茶の探偵帽。色とシルエットの両方で主役と分かる）。
    pub def playerSkin(): Human.Skin =
        { body = {r = 0.000000f32, g = 0.000000f32, b = 0.000000f32},   // #000000
          shade = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32},  // #323c39（腕脚の分離用の暗灰）
          hat = Some({r = 0.400000f32, g = 0.223529f32, b = 0.192157f32}) }  // #663931

    // ── 部屋と盤面上の印 ──

    /// 床（市松の 2 色。どちらも DB32 のグレー）。
    pub def floorA(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def floorB(): Color = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a

    /// 壁。
    pub def wall(): Color = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}    // #45283c
    pub def wallTop(): Color = {r = 0.400000f32, g = 0.223529f32, b = 0.192157f32} // #663931

    /// メモのマーク（頭上アイコンとメモ画面の文字で共有）。
    pub def markLiar(): Color = {r = 0.674510f32, g = 0.196078f32, b = 0.196078f32}   // #ac3232
    pub def markHonest(): Color = {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32} // #6abe30
    pub def markUnknown(): Color = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32} // #847e87

    /// ウィンドウのクリア色（project.json の clearColor と同じ。ギャラリーの背景にも使う）。
    pub def clearColor(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034

    /// 話しかけられることを示す頭上の「▼」。
    pub def talkIndicator(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32} // #fbf236
}
