/// WeaponIconScene — キャラ左上に常時表示する「装備武器の系統シンボル」アイコン
///
/// ノード構造（ユニット 1 体あたり）:
///   Player_<id> / Enemy_<id> (Marker2D)
///     └─ WeaponIcon (Marker2D, 左上オフセット)
///          ├─ Border (ColorRect, 濃色の枠 = 視認性のための囲み)
///          ├─ Bg     (ColorRect, 羊皮紙色の背景。枠を 1px 残してインセット)
///          └─ Icon   (Sprite2D, item_weapons / item_skills シートの 1 セル)
///
/// 仕様:
///   - 表示する絵は「実際の装備武器そのもの」ではなく、武器系統（剣/斧/槍/弓/魔法）を
///     象徴する代表アイコン。剣系は一律「てつの剣」、斧系は一律「てつのおの」… のように
///     `symbolSprite` で系統 → 鉄シリーズ（魔法のみ tome 代表）へ写像する。
///   - 武器だけだと盤面に埋もれて見えづらいので、羊皮紙色の背景を濃色の枠で囲って浮かせる。
///   - **スポーン時の装備武器の系統で 1 回だけ決め打ち**し、ゲーム中の持ち替えには追従しない
///     （静的）。よって毎フレーム reconcile・新規 NodeTag・Game.flix dispatch は不要で、
///     `UnitHPBarScene` と同じ「子ノードを attach するだけ」で完結する。
///   - 武器なし（素手）ユニットでは子ノードを生やさない（非表示）。
///   - 待機/行動済みのときは `setModulate` で親 Marker2D の modulate を落とす。engine は祖先
///     modulate を乗算伝播するため枠・背景・アイコンごと暗転する（HPBar の暗転と同位相で呼ぶ）。
mod WeaponIconScene {

    // ─── 子ノード名・表示パラメータ ───────────────────────────
    /// 親ユニット直下の固定の子ノード名（= 囲みの親 Marker2D）。`setModulate` のパス解決にも使う。
    pub def childName(): String = "WeaponIcon"

    /// キャラ中心（スプライトは centered）から、囲みの中心までのオフセット（px・左上）。要微調整。
    def iconOffset(): Vec2.Vec2 = {x = -9.0, y = -5.0}

    /// 囲み（枠 ColorRect）の一辺（px）。アイコン実寸 12px（16px セル × scale 0.75）+ 余白。
    def boxSize(): Float64 = 13.0

    /// 枠の太さ（px）。この分だけ背景を内側にインセットして枠線に見せる。
    def borderPx(): Float64 = 1.0

    /// アイコンの拡大率（16px セルを 12px に。背景枠の中で見やすい大きさ）。
    def iconScale(): Vec2.Vec2 = {x = 0.75, y = 0.75}

    /// 囲みの基準 zIndex。本体スプライト(10) / HPBar(50) より手前。枠 < 背景 < アイコン。
    def iconZIndex(): Int32 = 60

    // ─── 色 ───────────────────────────────────────────────────
    /// 背景色（羊皮紙）。
    def parchmentColor(): Color = {r = 0.91f32, g = 0.84f32, b = 0.65f32}
    /// 枠色（濃い茶。背景を引き締めて視認性を上げる）。
    def borderColor(): Color = {r = 0.30f32, g = 0.22f32, b = 0.13f32}
    /// 囲み（枠・背景）の不透明度。下げるほど下のキャラ/床が透けて見える。
    /// アイコン本体（Sprite2D）は不透明のまま残し、囲みだけ薄くする。
    def boxAlpha(): Float32 = 0.6f32

    // ─── 系統 → 象徴スプライト（純粋・テスト対象） ────────────
    /// 武器系統を象徴する「鉄シリーズ」スプライトへ写像する。frame は weapons.json の
    /// iron_* / tome_apprentice から確定した固定値。魔法のみ別シート（item_skills）。
    /// 将来未対応系統が増えたら None を返す余地を残すが、現状は全系統 Some。
    pub def symbolSprite(wt: WeaponCatalog.WeaponType): Option[Sprite.SpriteResource] = match wt {
        case WeaponCatalog.WeaponType.Sword => Some(weaponSheet(20))
        case WeaponCatalog.WeaponType.Axe   => Some(weaponSheet(288))
        case WeaponCatalog.WeaponType.Lance => Some(weaponSheet(283))
        case WeaponCatalog.WeaponType.Bow   => Some(weaponSheet(294))
        case WeaponCatalog.WeaponType.Magic =>
            Some({texture = "item_skills", hframes = 20, vframes = 30, frame = 0,
                  offset = Vec2.zero(), scale = iconScale(), flipForFacing = false})
    }

    /// item_weapons シート（20×25）の 1 セルを指す SpriteResource を組み立てる内部ヘルパー。
    def weaponSheet(frame: Int32): Sprite.SpriteResource =
        {texture = "item_weapons", hframes = 20, vframes = 25, frame = frame,
         offset = Vec2.zero(), scale = iconScale(), flipForFacing = false}

    // ─── 公開 API ─────────────────────────────────────────────
    /// ユニット（Marker2D）の子として、羊皮紙背景＋枠で囲った武器系統アイコンを生やす。常時表示。
    /// `equipped` が None、または系統にシンボルが無い場合は子を生やさない（非表示）。
    pub def attach(unitPath: NodePath, equipped: Option[WeaponCatalog.WeaponResource],
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        match equipped |> Option.flatMap(w -> symbolSprite(w#weaponType)) {
            case None      => scene
            case Some(spr) =>
                let half = boxSize() / 2.0;
                let inner = boxSize() - 2.0 * borderPx();
                // 囲みの親 Marker2D（左上オフセット）。modulate はこの 1 か所で一括制御する。
                let withParent = Scene.addChildAt(unitPath, childName(),
                    EngineNode.Marker2DWithState(Marker2D.make(iconOffset()), NodeTag.NoTag), scene);
                let iconPath = List.append(unitPath, childName() :: Nil);
                // 枠（濃色）。原点中心に置くため左上を半辺ぶん戻す。
                let border = ColorRect.make({x = boxSize(), y = boxSize()}, borderColor())
                    |> ColorRect.setAlpha(boxAlpha())
                    |> Node2D.setPosition({x = 0.0 - half, y = 0.0 - half})
                    |> CanvasItem.setZIndex(iconZIndex());
                let withBorder = Scene.addChildAt(iconPath, "Border",
                    EngineNode.ColorRectWithState(border, NodeTag.NoTag), withParent);
                // 羊皮紙背景（枠を 1px 残してインセット）。
                let bg = ColorRect.make({x = inner, y = inner}, parchmentColor())
                    |> ColorRect.setAlpha(boxAlpha())
                    |> Node2D.setPosition({x = 0.0 - half + borderPx(), y = 0.0 - half + borderPx()})
                    |> CanvasItem.setZIndex(iconZIndex() + 1);
                let withBg = Scene.addChildAt(iconPath, "Bg",
                    EngineNode.ColorRectWithState(bg, NodeTag.NoTag), withBorder);
                // 武器アイコン（centered なので原点に置けば囲みの中央）。
                let sprite = Sprite2D.make(spr#texture, Vec2.zero(), spr#scale)
                    |> Sprite2D.setHframes(spr#hframes)
                    |> Sprite2D.setVframes(spr#vframes)
                    |> Sprite2D.setFrame(spr#frame)
                    |> CanvasItem.setZIndex(iconZIndex() + 2);
                Scene.addChildAt(iconPath, "Icon",
                    EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), withBg)
        }

    /// 囲み全体（枠・背景・アイコン）の modulate を変える（待機/行動済みの灰色化と復帰）。
    /// 親 Marker2D 1 か所に設定すれば engine の祖先 modulate 乗算伝播で子ごと暗転する。
    /// アイコン未設置（素手）ユニットでは該当パスが無く no-op。HPBar の setModulate と
    /// 同じ箇所で呼ぶことで本体スプライト・HPBar・アイコンの暗転を揃える。
    pub def setModulate(unitPath: NodePath, color: Color, scene: Scene[NodeTag]): Scene[NodeTag] =
        let iconPath = List.append(unitPath, childName() :: Nil);
        Scene.mapEngineNode(iconPath, n -> match n {
            case EngineNode.Marker2DWithState(m, tag) =>
                EngineNode.Marker2DWithState(CanvasItem.setModulate(color, m), tag)
            case other => other
        }, scene)
}
