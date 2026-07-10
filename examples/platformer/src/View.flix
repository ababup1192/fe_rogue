// View — World から「(置き場所, 見せたい物) のリスト」への投影。
// ここに状態は無い: 地形もプレイヤーも HUD も、渡された World の純粋な関数である。
// 背景は作らない（clearColor の一色）。地形は色分けしたボックス、プレイヤーは球体（円）。
// 着地の瞬間だけ、squashLeft の残り時間から潰れた楕円（横長の全角丸ボックス）を導いて描く —
// タイマー 1 本だけが状態で、形は毎フレーム計算する。
// HUD は運動学の生値を常時表示する: 手触り調整中に「いま何が起きているか」を目で読むため。

mod View {

    // ── 描画レイヤー（下から上へ）──
    def zGround(): Int32 = 0
    def zPlatform(): Int32 = 5
    def zPlayer(): Int32 = 10
    def zText(): Int32 = 100

    /// World を絵へ。地形 → プレイヤー → HUD の順で重ねる（カメラは固定・全部が画面の空間）。
    pub def frame(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        let cam = CameraRig.fixed();
        let items = List.flatten(
            platformBoxes(world#platforms) ::
            playerItems(world#player) ::
            hudTexts(atlas, world) :: Nil);
        CameraRig.apply(cam, items)

    // ── 地形 ──

    /// 地形 1 枚 = 色分けした矩形。地面・浮き床・壁を id 帯でなく寸法で見分けはせず、
    /// 「地面 = 一番厚い」「壁 = 縦長」「それ以外 = 浮き床」の役割は色だけで示す。
    def platformBoxes(platforms: List[Field.Platform]): List[Render.Placed] =
        platforms |> List.map(platform ->
            flatBox(platform#pos, platform#size, platformColor(platform), zOf(platform)))

    def platformColor(platform: Field.Platform): Color =
        if (platform#size#y > platform#size#x) Palette.wall()
        else if (platform#size#y >= 30.0) Palette.ground()   // 分厚い = 地面（崖で分割されても同色）
        else Palette.platform()

    def zOf(platform: Field.Platform): Int32 =
        if (platform#size#y >= 30.0) zGround() else zPlatform()

    // ── プレイヤー（球体・着地の瞬間だけ潰れる）──

    /// squashLeft が残っている間は横に広く縦に低い全角丸ボックス（= 楕円の近似）を、
    /// それ以外は真円を描く。潰れても足元（下端）は地面に着けたまま。
    def playerItems(player: Field.Player): List[Render.Placed] =
        let r = Field.playerRadius();
        let ratio = if (Field.squashTime() > 0.0) player#squashLeft / Field.squashTime() else 0.0;
        let w = r * 2.0 * (1.0 + 0.35 * ratio);
        let h = r * 2.0 * (1.0 - 0.35 * ratio);
        let topLeft = { x = player#pos#x - w / 2.0, y = player#pos#y + r - h };
        (topLeft, Render.box({ x = w, y = h }, Palette.player(), zPlayer())
            |> Render.rounded(h / 2.0)) :: Nil

    // ── HUD（運動学の生値と操作の案内）──

    def hudTexts(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        let player = world#player;
        let status =
            "v=(${fmt(player#vel#x)},${fmt(player#vel#y)})"
            + " grd=${if (player#grounded) "T" else "F"}"
            + " coy=${fmt(player#coyoteLeft * 1000.0)}"
            + " buf=${fmt(player#bufferLeft * 1000.0)}"
            + " deaths=${world#deaths}";
        ({ x = 6.0, y = 4.0 },
         Render.textTinted(status, atlas, 8.0, Palette.hudText(), zText())) ::
        ({ x = 6.0, y = Field.designH() - 12.0 },
         Render.textTinted("ARROWS move / Z dash / SPACE jump / F1 reload", atlas, 8.0,
                           Palette.hintText(), zText())) :: Nil

    /// HUD 用に 1 桁小数へ丸める（RemoteDebug の書式を共用）。
    def fmt(v: Float64): String = RemoteDebug.fmt1(v)

    // ── 形の補助 ──

    /// 中心座標とサイズから左上原点の Box を置く（Render.box は左上原点）。
    def flatBox(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): Render.Placed =
        ({ x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
         Render.box(size, color, z))
}
