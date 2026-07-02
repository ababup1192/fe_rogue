/// WeaponIconRender — キャラ左上に常時表示する「装備武器の系統シンボル」アイコン
///
/// scene ノードは持たない。装備武器の系統は World store（weaponView）から導出し、
/// `renderPlates`（囲い ColorRect×2 = drawables チャンネル）と `renderGlyphs`
/// （WeaponGlyph の Polygon2D/Arc2D 値 = polygon チャンネル）が毎フレーム直描きする。
/// 待機/行動済みの暗転は waited/enemyActed store からの乗算合成で再現する。
///
/// 仕様:
///   - 表示する絵は「実際の装備武器そのもの」ではなく、武器系統（剣/斧/槍/弓/魔法）を
///     象徴する塗りシルエット。スプライトではなく engine の Polygon2D / Arc2D で直接描く
///     （`WeaponGlyph` が系統 → 凸ピース列へ写像）。ビットマップと違いどの zoom でも輪郭がくっきり出る。
///   - 武器だけだと盤面に埋もれて見えづらいので、濃紺のプレート背景を明るい枠で囲って浮かせる。
///   - スポーン時に `attach` で生やし、装備変更時は `refresh` で貼り直す（武器系統が変われば
///     見た目も変わる）。毎フレーム reconcile・新規 NodeTag・Game.flix dispatch は不要で、更新は
///     武器切り替えの単一 commit 点 `PlayerScene.equipWeapon` から `refresh` を呼ぶイベント駆動。
///   - 武器なし（素手）ユニットでは子ノードを生やさない（非表示）。
///   - 待機/行動済みのときは `setModulate` で親 Marker2D の modulate を落とす。engine は祖先
///     modulate を乗算伝播するため枠・背景・アイコンごと暗転する（HPBar の暗転と同位相で呼ぶ）。
mod WeaponIconRender {

    // ─── 子ノード名・表示パラメータ ───────────────────────────
    /// 親ユニット直下の固定の子ノード名（= 囲みの親 Marker2D）。`setModulate` のパス解決にも使う。
    pub def childName(): String = "WeaponIcon"

    /// キャラ中心（スプライトは centered）から、囲みの中心までのオフセット（px・左上）。要微調整。
    def iconOffset(): Vec2.Vec2 = {x = -9.0, y = -5.0}

    /// 囲み（枠 ColorRect）の一辺（px）。アイコン実寸 12px（16px セル × scale 0.75）+ 余白。
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
    /// グリフ本体（Polygon2D / Arc2D）は不透明のまま残し、囲みだけ薄くする。
    def boxAlpha(): Float32 = 0.6f32

    // ─── 公開 API（直描き） ────────────────────────────

    /// 対象ユニット列（味方＋敵）を「アイコン中心 world 座標・武器系統・暗転」の描画入力に畳む。
    /// 素手（weaponView 内側 None）は描かない。退場（hidden）ユニットも描かない。
    def iconInputs(world: World, scene: Scene[NodeTag]):
            List[{center = Vec2.Vec2, weaponType = WeaponCatalog.WeaponType, modColor = Color}] =
        let ofUnit = (ref, unitPath, modColor) ->
            match (World.posOf(ref, world), Scene.getEngineNode(unitPath, scene),
                   World.weaponViewOf(ref, world)) {
                case (Some(_), Some(_), Some(wv)) =>
                    let markerG = Scene.globalPositionAt(unitPath, scene);
                    let center: Vec2.Vec2 = {x = markerG#x + iconOffset()#x, y = markerG#y + iconOffset()#y};
                    ({center = center, weaponType = wv#weaponType, modColor = modColor}) :: Nil
                case _ => Nil
            };
        // 暗転は World.unitModulate store（本体/バー/アイコン共通の単一真実源）。
        let players = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#hidden)
            |> List.flatMap(d -> ofUnit(World.EntityRef.Player(d#id), PlayerScene.playerPath(d#id),
                World.modulateOf(World.EntityRef.Player(d#id), world)));
        // フォグで隠れた敵は描かない（applyFog が marker を隠す＝isVisible が真実源）。
        let enemies = EnemyScene.getAll(scene)
            |> List.filter(d -> EnemyScene.isVisible(d#id, scene))
            |> List.flatMap(d -> ofUnit(World.EntityRef.Enemy(d#id), EnemyScene.enemyPath(d#id),
                World.modulateOf(World.EntityRef.Enemy(d#id), world)));
        List.append(players, enemies)

    /// 囲い（枠＋プレート背景）の Drawable 列（drawables チャンネル）。
    pub def renderPlates(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ GameEngine.Game =
        iconInputs(world, scene) |> List.flatMap(inp -> {
            let half = boxSize() / 2.0;
            let inner = boxSize() - 2.0 * borderPx();
            let modColor = inp#modColor;
            let border = ColorRect.make({x = boxSize(), y = boxSize()}, mulColor(borderColor(), modColor))
                |> ColorRect.setAlpha(boxAlpha());
            let bg = ColorRect.make({x = inner, y = inner}, mulColor(plateColor(), modColor))
                |> ColorRect.setAlpha(boxAlpha());
            let borderDs = rectDrawables(border,
                {x = inp#center#x - half, y = inp#center#y - half}, iconZIndex(), transform);
            let bgDs = rectDrawables(bg,
                {x = inp#center#x - half + borderPx(), y = inp#center#y - half + borderPx()},
                iconZIndex() + 1, transform);
            List.append(borderDs, bgDs)
        })

    /// 武器系統グリフの PolygonRenderCmd 列（polygon チャンネル）。
    /// WeaponGlyph の各ピース（Polygon2D/Arc2D 値・アイコン中心基準のローカル位置）を
    /// world 座標へ動かして cmd 化する。暗転は cmd color への乗算で再現。
    pub def renderGlyphs(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.PolygonRenderCmd] =
        iconInputs(world, scene) |> List.flatMap(inp -> {
            let modColor = inp#modColor;
            WeaponGlyph.weaponGlyph(inp#weaponType) |> List.flatMap(ne -> {
                let (_, node) = ne;
                pieceCmds(node, inp#center, modColor, transform)
            })
        })

    /// グリフ 1 ピース（Polygon2D/Arc2D の EngineNode 値）→ PolygonRenderCmd 列。
    def pieceCmds(node: EngineNode[NodeTag], center: Vec2.Vec2, modColor: Color,
                   transform: Camera2D.ViewTransform): List[GameEngine.PolygonRenderCmd] =
        let withMod = (cmd: GameEngine.PolygonRenderCmd) ->
            ({color = mulColor(cmd#color, modColor), zIndex = iconZIndex() + 2 | cmd}: GameEngine.PolygonRenderCmd);
        match node {
            case EngineNode.Polygon2DWithState(poly, _) =>
                let p = Node2D.getPosition(poly);
                let screenPos = Camera2D.applyToWorldPos(transform, {x = center#x + p#x, y = center#y + p#y});
                withMod(Polygon2D.toRenderCmd(screenPos, transform#scale, poly)) :: Nil
            case EngineNode.Arc2DWithState(arc, _) =>
                let p = Node2D.getPosition(arc);
                let screenPos = Camera2D.applyToWorldPos(transform, {x = center#x + p#x, y = center#y + p#y});
                Arc2D.toRenderCmds(screenPos, transform#scale, arc) |> List.map(withMod)
            case _ => Nil
        }

    /// ColorRect 値 1 枚を world 左上座標へ Drawable 化する（UnitHPBarRender と同型）。
    def rectDrawables(rect: ColorRect, worldTopLeft: Vec2.Vec2, z: Int32,
                       transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Camera2D.applyToWorldPos(transform, worldTopLeft);
        GameEngine.Renderable.toDrawables(EngineNode.ColorRectWithState(rect, NodeTag.NoTag), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {zIndex = z | d})

    /// 乗算合成（engine の祖先 modulate 伝播の代替）。
    def mulColor(a: Color, b: Color): Color =
        {r = a#r * b#r, g = a#g * b#g, b = a#b * b#b}
}
