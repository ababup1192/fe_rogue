/// UnitHPBarScene — キャラ足元に常時表示する連続フィル HP ゲージ（ColorRect ベース）
///
/// ノード構造:
///   HPBar (Marker2D, NodeTag.HPBar({maxHp, currentHp}))
///     ├─ Bg   (ColorRect, バー全体・暗トラック = 枠兼用)
///     └─ Fill (ColorRect, 残量比ぶんの幅・チーム色 = 味方青 / 敵赤)
///
/// 仕様:
///   - 幅は 1 マス × 0.9 固定（最大 HP に依らない）。足元（下）へ中央寄せ。**常時表示**。
///   - フィルは残量比 currentHp/maxHp の幅。残りは暗トラックが見える。
///   - 待機/行動済みのときは親 Marker2D の modulate を下げる（`setModulate`）。
///     engine は祖先 modulate を乗算伝播するため Bg/Fill ごと暗転する。
mod UnitHPBarScene {

    /// HP バーのチーム。フィル色の出し分けに使う（味方=青 / 敵=赤）。
    pub enum Team with Eq {
        case Player
        case Enemy
    }

    // ─── 状態（親 Marker2D の NodeTag に格納） ─────────────────
    pub type alias HPBarData = {
        maxHp = Int32,
        currentHp = Int32
    }

    // ─── 色 ───────────────────────────────────────────────────
    /// 味方フィル色: 青。
    def fillColorPlayer(): Color = {r = 0.25f32, g = 0.5f32, b = 0.95f32}
    /// 敵フィル色: 赤。
    def fillColorEnemy(): Color = {r = 0.9f32, g = 0.25f32, b = 0.25f32}
    def fillColorFor(team: Team): Color = match team {
        case Team.Player => fillColorPlayer()
        case Team.Enemy  => fillColorEnemy()
    }
    /// 残量トラック（暗背景・枠兼用）。
    def trackColor(): Color = {r = 0.08f32, g = 0.08f32, b = 0.08f32}

    /// 攻撃予報中に「これから減る分」を示す暗色オーバーレイの子ノード名。
    def dmgPreviewName(): String = "DmgPreview"
    /// 点滅の「暗」側 modulate（フィル色を暗く落とす乗算色）。減少分が暗く沈んで見える。
    def dmgDarkModulate(): Color = {r = 0.3f32, g = 0.3f32, b = 0.3f32}
    /// 点滅の「明」側 modulate（通常色 = フィルと同色に見え、満タンに戻って見える）。
    def dmgNormalModulate(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    // ─── サイズ・位置 ─────────────────────────────────────────
    /// バー幅 = 1 マス × 0.9（最大 HP 非依存）。
    def barWidthPx(): Float64 = MapScene.tileSize() * 0.9
    /// バー高さ（調整可）。
    def barHeightPx(): Float64 = 5.0
    def borderPx(): Float64 = 1.0
    /// 足元オフセット（ユニット中心からの下方向 px、スプライト 0.8 倍の足元あたり・調整可）。
    def barFeetY(): Float64 = 13.0
    def barZIndex(): Int32 = 50

    pub def childName(): String = "HPBar"

    /// フィル領域（枠 1px インセット）の幅・高さ。
    def innerWidthPx(): Float64 = barWidthPx() - 2.0 * borderPx()
    def innerHeightPx(): Float64 = barHeightPx() - 2.0 * borderPx()

    /// 残量比（0..1 にクランプ）。maxHp<=0 は 0 扱い。
    def hpRatio(currentHp: Int32, maxHp: Int32): Float64 =
        if (maxHp <= 0) 0.0
        else {
            let r = Int32.toFloat64(currentHp) / Int32.toFloat64(maxHp);
            if (r < 0.0) 0.0 else if (r > 1.0) 1.0 else r
        }

    /// 残量比から Fill 幅（px）を求める純粋関数（テスト対象）。
    pub def fillWidth(currentHp: Int32, maxHp: Int32, innerW: Float64): Float64 =
        innerW * hpRatio(currentHp, maxHp)

    /// チームのフィル色（テスト用に公開）。
    pub def teamFillColor(team: Team): Color = fillColorFor(team)

    // ─── 公開 API ─────────────────────────────────────────────

    /// unit Marker2D の子として HP ゲージ（親 Marker2D + Bg + Fill）を生やす。常時表示。
    pub def attach(unitPath: NodePath, maxHp: Int32, team: Team, scene: Scene[NodeTag]): Scene[NodeTag] =
        if (maxHp <= 0) scene
        else {
            let barOffset: Vec2.Vec2 = {x = 0.0 - barWidthPx() / 2.0, y = barFeetY()};
            let data: HPBarData = {maxHp = maxHp, currentHp = maxHp};
            // 親 Marker2D（常時表示。make 既定で visible=true）
            let parent = Marker2D.make(barOffset);
            let barPath = List.append(unitPath, childName() :: Nil);
            let withParent =
                Scene.addChildAt(unitPath, childName(),
                    EngineNode.Marker2DWithState(parent, NodeTag.HPBar(data)), scene);
            // 背景トラック（暗・全体サイズ = 枠兼用）
            let bg = ColorRect.make({x = barWidthPx(), y = barHeightPx()}, trackColor())
                |> CanvasItem.setZIndex(barZIndex());
            let withBg =
                Scene.addChildAt(barPath, "Bg",
                    EngineNode.ColorRectWithState(bg, NodeTag.NoTag), withParent);
            // フィル（チーム色）= 初期満タン（innerW）、枠 1px インセット
            let fill = ColorRect.make({x = innerWidthPx(), y = innerHeightPx()}, fillColorFor(team))
                |> Node2D.setPosition({x = borderPx(), y = borderPx()})
                |> CanvasItem.setZIndex(barZIndex() + 1);
            let withFill = Scene.addChildAt(barPath, "Fill",
                EngineNode.ColorRectWithState(fill, NodeTag.NoTag), withBg);
            // ダメージ予測オーバーレイ（初期は非表示・幅 0）。フィルと同色をフィル最前面
            // （zIndex +2）に重ね、攻撃予報中だけ「減る分」の矩形へ被せて暗色で点滅させる。
            let preview = ColorRect.make({x = 0.0, y = innerHeightPx()}, fillColorFor(team))
                |> Node2D.setPosition({x = borderPx(), y = borderPx()})
                |> CanvasItem.setZIndex(barZIndex() + 2)
                |> CanvasItem.setVisible(false);
            Scene.addChildAt(barPath, dmgPreviewName(),
                EngineNode.ColorRectWithState(preview, NodeTag.NoTag), withFill)
        }

    /// HP 変化を反映する。Fill の幅を残量比でリサイズし、HPBarData.currentHp を更新する。
    /// 対象ユニットに HPBar が未設置なら no-op。
    pub def update(unitPath: NodePath, currentHp: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let barPath = List.append(unitPath, childName() :: Nil);
        match Scene.getState(barPath, scene) {
            case Some(NodeTag.HPBar(d)) =>
                let w = fillWidth(currentHp, d#maxHp, innerWidthPx());
                let fillPath = List.append(barPath, "Fill" :: Nil);
                let withFill = Scene.mapEngineNode(fillPath, n ->
                    EngineNode.mapColorRect(c -> ColorRect.setSize({x = w, y = innerHeightPx()}, c), n),
                    scene);
                Scene.mapEngineNode(barPath, n -> match n {
                    case EngineNode.Marker2DWithState(m, NodeTag.HPBar(dd)) =>
                        EngineNode.Marker2DWithState(m, NodeTag.HPBar({currentHp = currentHp | dd}))
                    case other => other
                }, withFill)
            case _ => scene
        }

    /// HPBar 親 Marker2D の modulate を設定する。祖先伝播で Bg/Fill ごと暗転/復帰する。
    /// 待機（プレイヤー）・行動済み（敵）の本体スプライト暗転と揃えて呼ぶ。
    pub def setModulate(unitPath: NodePath, color: Color, scene: Scene[NodeTag]): Scene[NodeTag] =
        let barPath = List.append(unitPath, childName() :: Nil);
        Scene.mapEngineNode(barPath, n -> match n {
            case EngineNode.Marker2DWithState(m, tag) =>
                EngineNode.Marker2DWithState(CanvasItem.setModulate(color, m), tag)
            case other => other
        }, scene)

    /// 攻撃予報中、対象ユニットの HP バーで「これから減る分」(postHp..currentHp) を
    /// 暗色オーバーレイで示す。`dark=true` のフレームは暗 modulate（= 減少分が暗く沈む）、
    /// `false` のフレームは通常色（= フィルと同色で満タンに見える）。点滅は呼び出し側が
    /// `dark` を毎フレーム切り替えて作る（BattlePanel の HP 点滅と同位相にする）。
    /// ダメージが無い（postHp >= currentHp）か HPBar 未設置なら非表示にする。
    pub def showDamageForecast(unitPath: NodePath, currentHp: Int32, postHp: Int32,
                                dark: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let barPath = List.append(unitPath, childName() :: Nil);
        match Scene.getState(barPath, scene) {
            case Some(NodeTag.HPBar(d)) =>
                if (postHp >= currentHp) hideDamageForecast(unitPath, scene)
                else {
                    let innerW = innerWidthPx();
                    let xStart = borderPx() + fillWidth(postHp, d#maxHp, innerW);
                    let w      = fillWidth(currentHp, d#maxHp, innerW)
                                 - fillWidth(postHp, d#maxHp, innerW);
                    let modColor = if (dark) dmgDarkModulate() else dmgNormalModulate();
                    let previewPath = List.append(barPath, dmgPreviewName() :: Nil);
                    Scene.mapEngineNode(previewPath, n ->
                        EngineNode.mapColorRect(c ->
                            c |> ColorRect.setSize({x = w, y = innerHeightPx()})
                              |> Node2D.setPosition({x = xStart, y = borderPx()})
                              |> CanvasItem.setModulate(modColor)
                              |> CanvasItem.setVisible(true), n),
                        scene)
                }
            case _ => scene
        }

    /// ダメージ予測オーバーレイを隠す（攻撃予報を抜けた / 対象が変わった / ダメージ無し）。
    /// HPBar や DmgPreview が無いパスでも安全な no-op。
    pub def hideDamageForecast(unitPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        let previewPath =
            List.append(List.append(unitPath, childName() :: Nil), dmgPreviewName() :: Nil);
        Scene.mapEngineNode(previewPath, n ->
            EngineNode.mapColorRect(c -> CanvasItem.setVisible(false, c), n), scene)

    /// 常時表示のため per-frame 処理は不要。Game.flix のディスパッチ互換のための no-op。
    pub def process(_dt: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) =
        (node, scene)
}
