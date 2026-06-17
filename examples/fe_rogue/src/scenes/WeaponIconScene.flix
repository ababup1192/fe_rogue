/// WeaponIconScene — キャラ左上に常時表示する「装備武器の系統シンボル」アイコン
///
/// ノード構造（ユニット 1 体あたり）:
///   Player_<id> / Enemy_<id> (Marker2D)
///     └─ WeaponIcon (Marker2D, 左上オフセット)
///          ├─ Border  (ColorRect, 濃色の枠 = 視認性のための囲み)
///          ├─ Bg      (ColorRect, 濃紺のプレート背景。枠を 1px 残してインセット)
///          └─ G0,G1,… (Polygon2D / Arc2D, 武器系統の塗りシルエットを直描き = WeaponGlyph)
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

    // ─── 公開 API ─────────────────────────────────────────────
    /// ユニット（Marker2D）の子として、濃紺プレート＋枠で囲った武器系統シルエット（白）を生やす。常時表示。
    /// `equipped` が None（素手）なら子を生やさない（非表示）。アイコンは `WeaponGlyph` が
    /// engine の Polygon2D / Arc2D で直接描く塗りシルエット（スプライト不使用）。
    pub def attach(unitPath: NodePath, equipped: Option[WeaponCatalog.WeaponResource],
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        match equipped {
            case None    => scene
            case Some(w) =>
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
                // プレート背景（濃紺。枠を 1px 残してインセット）。
                let bg = ColorRect.make({x = inner, y = inner}, plateColor())
                    |> ColorRect.setAlpha(boxAlpha())
                    |> Node2D.setPosition({x = 0.0 - half + borderPx(), y = 0.0 - half + borderPx()})
                    |> CanvasItem.setZIndex(iconZIndex() + 1);
                let withBg = Scene.addChildAt(iconPath, "Bg",
                    EngineNode.ColorRectWithState(bg, NodeTag.NoTag), withBorder);
                // 武器系統の塗りシルエットを枠の中央（原点）に直描きで重ねる（G0,G1,…）。
                List.foldLeft((acc, ne) ->
                        let (name, node) = ne;
                        Scene.addChildAt(iconPath, name, node, acc),
                    withBg, WeaponGlyph.weaponGlyph(w#weaponType))
        }

    /// 装備武器が変わったときにアイコンを貼り直す（系統が変われば見た目も変わる）。
    /// 既存の WeaponIcon 子サブツリーを丸ごと取り除いてから `attach` し直す。素手化（None）なら
    /// 子を消すだけ（attach は no-op）。再 attach は modulate が白に戻るため、直前の暗転状態
    /// （祖先 modulate）を退避して引き継ぐ。武器の commit 点（`PlayerScene.equipWeapon`）から呼ぶ。
    pub def refresh(unitPath: NodePath, equipped: Option[WeaponCatalog.WeaponResource],
                     scene: Scene[NodeTag]): Scene[NodeTag] =
        let iconPath = List.append(unitPath, childName() :: Nil);
        let prevMod = match Scene.getEngineNode(iconPath, scene) {
            case Some(EngineNode.Marker2DWithState(m, _)) => CanvasItem.getModulate(m)
            case _                                        => {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        };
        Scene.removeAt(iconPath, scene)
            |> attach(unitPath, equipped)
            |> setModulate(unitPath, prevMod)

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
