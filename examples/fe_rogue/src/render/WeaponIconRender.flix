/// WeaponIconRender — キャラ左上に常時表示する「装備武器の系統シンボル」アイコン
///
/// scene ノードは持たない。装備武器の系統は World store（weaponView）から導出し、
/// `renderPlates`（囲い Rect×2 = drawables チャンネル）と `renderGlyphs`
/// （WeaponGlyph の Polygon/Arc 値 = polygon チャンネル）が毎フレーム直描きする。
/// 待機/行動済みの暗転は waited/enemyActed store からの乗算合成で再現する。
///
/// 仕様:
///   - 表示する絵は「実際の装備武器そのもの」ではなく、武器系統（剣/斧/槍/弓/魔法）を
///     象徴する塗りシルエット。スプライトではなく engine の Polygon / Arc で直接描く
///     （`WeaponGlyph` が系統 → 凸ピース列へ写像）。ビットマップと違いどの zoom でも輪郭がくっきり出る。
///   - 武器だけだと盤面に埋もれて見えづらいので、濃紺のプレート背景を明るい枠で囲って浮かせる。
///   - 武器なし（素手）ユニットでは描かない（weaponView が内側 None）。
///   - 待機/行動済みの暗転は World の unitModulate store を乗算合成して再現する
///     （本体 sprite / HPBar の暗転と同じ単一真実源）。
mod WeaponIconRender {

    // ─── 表示パラメータ ───────────────────────────
    /// キャラ中心（スプライトは centered）から、囲みの中心までのオフセット（px・左上）。要微調整。
    def iconOffset(): Vec2.Vec2 = {x = -9.0, y = -5.0}

    /// 囲み（枠 Rect）の一辺（px）。アイコン実寸 12px（16px セル × scale 0.75）+ 余白。
    def boxSize(): Float64 = 13.0

    /// 枠の太さ（px）。この分だけ背景を内側にインセットして枠線に見せる。
    def borderPx(): Float64 = 1.0

    /// 囲みの基準 zIndex。本体スプライト(10) / HPBar(50) より手前。枠 < 背景 < アイコン。
    def iconZIndex(): Int32 = 60

    // ─── 色 ───────────────────────────────────────────────────
    /// プレート背景色（濃紺）。白いグリフを映えさせるため暗くする（FE3H のアイコン台座に寄せる）。
    def plateColor(): Color = {r = 0.12f32, g = 0.15f32, b = 0.28f32}
    /// 枠色（明るいスレート。暗いプレートの輪郭を締めて視認性を上げる）。
    def borderColor(): Color = {r = 0.50f32, g = 0.55f32, b = 0.70f32}
    /// 囲み（枠・背景）の不透明度。下げるほど下のキャラ/床が透けて見える。
    /// グリフ本体（Polygon / Arc）は不透明のまま残し、囲みだけ薄くする。
    def boxAlpha(): Float32 = 0.6f32

    // ─── 公開 API（直描き） ────────────────────────────

    /// 対象ユニット列（味方＋敵）を「アイコン中心 world 座標・武器系統・暗転」の描画入力に畳む。
    /// 在籍・位置とも World 由来（scene を読まない）。位置は `World.visualPosOf`
    /// （静止=セル中心／移動=renderPos 補間／lunge=往復導出＝本体 sprite と同じ追従）。
    /// 素手（weaponView 内側 None）は描かない。退場（hidden）ユニット・フォグで隠れた敵
    /// （`holesOpt` の lit ゲート）も描かない。
    def iconInputs(world: World, holesOpt: Option[List[GridRect]]):
            List[{center = Vec2.Vec2, weaponType = WeaponCatalog.WeaponType, modColor = Color}] =
        let ofUnit = (ref, modColor) ->
            match (World.visualPosOf(ref, world), World.weaponViewOf(ref, world)) {
                case (Some(unitPos), Some(wv)) =>
                    let center: Vec2.Vec2 = {x = unitPos#x + iconOffset()#x, y = unitPos#y + iconOffset()#y};
                    ({center = center, weaponType = wv#weaponType, modColor = modColor}) :: Nil
                case _ => Nil
            };
        // 暗転は World.unitModulate store（本体/バー/アイコン共通の単一真実源）。
        let players = World.playerIdsOf(world)
            |> List.filter(id -> not World.playerHiddenOf(World.EntityRef.Player(id), world))
            |> List.flatMap(id -> ofUnit(World.EntityRef.Player(id),
                World.modulateOf(World.EntityRef.Player(id), world)));
        // フォグで隠れた敵は描かない（明るい穴の lit ゲート＝本体 sprite と同じ判定）。
        let enemies = World.enemyIdsOf(world)
            |> List.filter(id -> holesOpt
                |> Option.map(holes -> EnemyScene.isLitIn(id, holes, world))
                |> Option.getWithDefault(false))
            |> List.flatMap(id -> ofUnit(World.EntityRef.Enemy(id),
                World.modulateOf(World.EntityRef.Enemy(id), world)));
        List.append(players, enemies)

    /// 囲い（枠＋プレート背景）の Drawable 列（drawables チャンネル）。
    pub def renderPlates(world: World, holesOpt: Option[List[GridRect]],
                          transform: Camera.ViewTransform):
            List[GameEngine.Drawable] \ GameEngine.Game =
        iconInputs(world, holesOpt) |> List.flatMap(inp -> {
            let half = boxSize() / 2.0;
            let inner = boxSize() - 2.0 * borderPx();
            let modColor = inp#modColor;
            let border = Rect.make({x = boxSize(), y = boxSize()}, mulColor(borderColor(), modColor))
                |> Rect.setAlpha(boxAlpha());
            let bg = Rect.make({x = inner, y = inner}, mulColor(plateColor(), modColor))
                |> Rect.setAlpha(boxAlpha());
            let borderDs = rectDrawables(border,
                {x = inp#center#x - half, y = inp#center#y - half}, iconZIndex(), transform);
            let bgDs = rectDrawables(bg,
                {x = inp#center#x - half + borderPx(), y = inp#center#y - half + borderPx()},
                iconZIndex() + 1, transform);
            List.append(borderDs, bgDs)
        })

    /// 武器系統グリフの PolygonRenderCmd 列（polygon チャンネル）。
    /// WeaponGlyph の各ピース（Polygon/Arc 値・アイコン中心基準のローカル位置）を
    /// world 座標へ動かして cmd 化する。暗転は cmd color への乗算で再現。
    pub def renderGlyphs(world: World, holesOpt: Option[List[GridRect]],
                          transform: Camera.ViewTransform):
            List[GameEngine.PolygonRenderCmd] =
        iconInputs(world, holesOpt) |> List.flatMap(inp -> {
            let modColor = inp#modColor;
            WeaponGlyph.weaponGlyph(inp#weaponType) |> List.flatMap(ne -> {
                let (_, piece) = ne;
                pieceCmds(piece, inp#center, modColor, transform)
            })
        })

    /// グリフ 1 ピース（Polygon/Arc の GlyphPiece 値）→ PolygonRenderCmd 列。
    def pieceCmds(piece: WeaponGlyph.GlyphPiece, center: Vec2.Vec2, modColor: Color,
                   transform: Camera.ViewTransform): List[GameEngine.PolygonRenderCmd] =
        let withMod = (cmd: GameEngine.PolygonRenderCmd) ->
            ({color = mulColor(cmd#color, modColor), zIndex = iconZIndex() + 2 | cmd}: GameEngine.PolygonRenderCmd);
        match piece {
            case WeaponGlyph.GlyphPiece.Poly(poly) =>
                let p = Node2D.getPosition(poly);
                let screenPos = Camera.applyToWorldPos(transform, {x = center#x + p#x, y = center#y + p#y});
                withMod(Polygon.toRenderCmd(screenPos, transform#scale, poly)) :: Nil
            case WeaponGlyph.GlyphPiece.Arc(arc) =>
                let p = Node2D.getPosition(arc);
                let screenPos = Camera.applyToWorldPos(transform, {x = center#x + p#x, y = center#y + p#y});
                Arc.toRenderCmds(screenPos, transform#scale, arc) |> List.map(withMod)
        }

    /// Rect 値 1 枚を world 左上座標へ Drawable 化する（UnitHPBarRender と同型）。
    def rectDrawables(rect: Rect, worldTopLeft: Vec2.Vec2, z: Int32,
                       transform: Camera.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Camera.applyToWorldPos(transform, worldTopLeft);
        // Rect.toDrawable は純粋。呼び側の Game eff 連鎖を保つため checked_ecast で持ち上げる。
        checked_ecast(
            (Rect.toDrawable(rect, screenPos) :: Nil)
                |> Render.applyCameraScale(transform)
                |> List.map(d -> {zIndex = z | d}))

    /// 乗算合成（engine の祖先 modulate 伝播の代替）。
    def mulColor(a: Color, b: Color): Color =
        {r = a#r * b#r, g = a#g * b#g, b = a#b * b#b}
}
