// 入力。マウスのドラッグでスライダーをつまんで動かし、time を送る。
// 押した瞬間はカーソル下のスライダーを探して掴み、押している間は掴んだままずらす。
// Space キーでページを切り替える（0=水・1=岸）。

mod Controls {

    /// 毎フレーム: ページ切替を見て、どのスライダーを掴んでいるか決め、
    /// 掴んでいれば値を更新し、time を進める。
    /// マウスを離してドラッグが終わった瞬間に、いまのページの値をファイルへ自動保存する。
    pub def step(frame: App.Frame, world: World.World): World.World \ Fs.FileWrite =
        let cur = frame#cursor;
        // Space を押した瞬間にページを 0↔1 で切り替える。切替時は掴みを解除する。
        let togglePage = App.justPressed(GameEngine.Key.Space, frame);
        let page = if (togglePage) (if (world#page == 0) 1 else 0) else world#page;
        // どのスライダーを掴んでいるか。離した/ページ切替は None、押し続けなら継続、押した瞬間は探す。
        let dragging =
            if (not frame#mouseDown or togglePage) None
            else match world#dragging {
                case Some(k) => Some(k)
                case None    => hitSlider(page, cur)
            };
        // 掴んでいれば、カーソルの横位置をトラック上の 0..1 に直して値へ変換し、World を更新。
        let edited = match dragging {
            case Some(k) => match findDef(page, k) {
                case Some(d) =>
                    let t = clamp01((cur#x - Sliders.trackX()) / Sliders.trackW());
                    Sliders.set(world, k, d#lo + t * (d#hi - d#lo))
                case None => world
            }
            case None => world
        };
        // マウスホイールで「池の大きさ」を変える（＝dungeon でカメラを寄せ引きした見え方）。
        // 上=池を大きく(網が大きく粗く)、下=池を小さく(網が細かく)。網の細かさは池サイズに連動。
        let pondScale = pondZoomStep(frame#wheel, edited#pondScale);
        let world2 = { time = world#time + frame#dt, dragging = dragging, page = page,
                       pondScale = pondScale | edited };
        // ドラッグ中→非ドラッグ（＝マウスを離した瞬間）に、いまのページの値を自動保存。
        let wasDragging = match world#dragging { case Some(_) => true  case None => false };
        let nowIdle     = match dragging       { case Some(_) => false case None => true  };
        if (wasDragging and nowIdle) {
            let _ = if (world#page == 0) Store.save(world2) else Store.saveShore(world2);
            world2
        } else world2

    def pondZoomStep(wheel: Float64, s: Float64): Float64 =
        let s2 =
            if (wheel > 0.0) s * 1.06
            else if (wheel < 0.0) s / 1.06
            else s;
        Float64.max(0.3, Float64.min(1.0, s2))

    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))

    /// カーソルがどの行のトラック上にあるか（縦は行±8、横はトラック±10 の範囲）。
    /// スライダーの並びは表示中ページで変わる。
    def hitSlider(page: Int32, cur: Vec2.Vec2): Option[String] =
        let indexed = List.mapWithIndex((i, d) -> (i, d), Sliders.defsFor(page));
        List.foldLeft((acc, pair) -> match acc {
            case Some(_) => acc
            case None =>
                let (i, d) = pair;
                let ry = Sliders.rowY(i);
                if (cur#y >= ry - 8.0 and cur#y <= ry + 8.0 and
                    cur#x >= Sliders.trackX() - 10.0 and
                    cur#x <= Sliders.trackX() + Sliders.trackW() + 10.0)
                    Some(d#key) else None
        }, None, indexed)

    /// key に一致するスライダー定義を、表示中ページの並びから探す。
    def findDef(page: Int32, key: String): Option[Sliders.Def] =
        List.foldLeft((acc, d) -> match acc {
            case Some(_) => acc
            case None    => if (d#key == key) Some(d) else None
        }, None, Sliders.defsFor(page))
}
