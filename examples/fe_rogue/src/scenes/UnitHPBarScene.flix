/// UnitHPBarScene — FE 風 HP バー（ColorRect ベース）
///
/// ノード構造:
///   HPBar (Marker2D, NodeTag.HPBar({remaining, maxHp, currentHp}))
///     ├─ Bg     (ColorRect, bar 全体サイズ、黒)         ← border と cell 間 gap を兼ねる
///     ├─ Cell_0 (ColorRect, セル幅 × 高さ、明緑 or 暗緑)
///     └─ ...
///
/// 表示則:
///   - インデックス < currentHp → 明黄緑（生き残り）
///   - それ以上                  → 暗緑（失った HP）
///   - セル間 1 px の隙間は Bg の黒が見えて FE 流の「刻み」になる
///
/// 可視/不可視:
///   - 平時は **不可視**（親 Marker2D を visible=false）
///   - `update` で damage が入ると 1.5 秒のカウントダウンと共に可視化
///   - `tickAll` を毎フレーム呼ぶことで timer を減らし、`remaining > 0` の間は可視
///   - HP 比率 ≤ 30% のときは timer 切れ後も常時可視（警告状態）
///
/// max HP に応じてセル数（= バー幅）が変わる。1 HP = 1 cell = 1 px + 1 px gap = 2 px。
mod UnitHPBarScene {

    /// HP バーをキャラのどちら側に出すか。
    /// プレイヤーは Above、敵は Below を渡すことで隣接時の重なりを避ける。
    pub enum BarPosition with Eq {
        case Above
        case Below
    }

    // ─── 状態（親 Marker2D に紐づく） ─────────────────────────

    /// 親 Marker2D の NodeTag に格納する状態。timer の残りと現在 HP を保持する。
    /// timer の単位は秒（Duration）。
    pub type alias HPBarData = {
        remaining = Duration.Duration,
        maxHp = Int32,
        currentHp = Int32
    }

    // ─── ピクセル定数 ─────────────────────────────────────────

    def cellWidthPx(): Float64 = 1.0
    def cellHeightPx(): Float64 = 4.0
    def cellGapPx(): Float64 = 1.0
    def borderPx(): Float64 = 1.0

    // ─── 色 ───────────────────────────────────────────────────

    /// 生きてるセルの色: 黄緑（lime green）
    def fillColorHealthy(): Color = {r = 0.5f32, g = 0.9f32, b = 0.2f32}

    /// 失った HP のセル色: 同系の暗緑
    def fillColorDamaged(): Color = {r = 0.15f32, g = 0.25f32, b = 0.08f32}

    /// cell 間 gap の色。完全な黒。
    def bgColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}

    /// 味方（プレイヤー）用の縁色: 青。
    def borderColorPlayer(): Color = {r = 0.25f32, g = 0.5f32, b = 0.95f32}

    /// 敵用の縁色: 赤。
    def borderColorEnemy(): Color = {r = 0.9f32, g = 0.25f32, b = 0.25f32}

    /// BarPosition から縁色を引く。
    /// Above = 味方 = 青、Below = 敵 = 赤、というゲーム規約。
    def borderColorFor(position: BarPosition): Color = match position {
        case BarPosition.Above => borderColorPlayer()
        case BarPosition.Below => borderColorEnemy()
    }

    // ─── レイアウト ───────────────────────────────────────────

    def barTopY(): Float64 = -10.0
    def barBottomY(): Float64 = 12.0
    def barZIndex(): Int32 = 50

    pub def childName(): String = "HPBar"

    // ─── 可視化ルール ─────────────────────────────────────────

    /// damage 後に bar を出し続ける時間。
    def combatVisibleDuration(): Duration.Duration = Duration.millis(1500)

    /// この比率以下なら timer 切れ後も常時可視（警告）。
    def lowHpThreshold(): Float64 = 0.3

    // ─── サイズ・位置の計算ヘルパ ─────────────────────────────

    /// N セルの bar 外形サイズ。
    /// inner 幅 = N * cellW + (N-1) * gap、outer 幅 = inner + 2*border。
    def computeOuterSize(cellCount: Int32): Vec2.Vec2 = {
        let n = Int32.toFloat64(cellCount);
        let innerW = n * cellWidthPx() + (n - 1.0) * cellGapPx();
        let outerW = innerW + 2.0 * borderPx();
        {x = outerW, y = cellHeightPx() + 2.0 * borderPx()}
    }

    /// セル i の親 Marker2D ローカル左上座標。
    def cellLocalPos(cellIdx: Int32): Vec2.Vec2 = {
        let i = Int32.toFloat64(cellIdx);
        {
            x = borderPx() + i * (cellWidthPx() + cellGapPx()),
            y = borderPx()
        }
    }

    /// HP インデックスから色を決める。`idx < currentHp` なら生存（明緑）、それ以上は暗緑。
    def colorForIndex(idx: Int32, currentHp: Int32): Color =
        if (idx < currentHp) fillColorHealthy() else fillColorDamaged()

    def cellName(idx: Int32): String = "Cell_${idx}"

    /// 現在 HP / 最大 HP の比率を 0.0..1.0 で返す。maxHp <= 0 は full 扱い。
    def hpRatio(currentHp: Int32, maxHp: Int32): Float64 =
        if (maxHp <= 0) 1.0
        else Int32.toFloat64(currentHp) / Int32.toFloat64(maxHp)

    // ─── 公開 API ─────────────────────────────────────────────

    /// unit Marker2D の子として HP バー（親 Marker2D + Bg + maxHp 個の Cell ColorRect）を生やす。
    /// 平時は親を visible=false にしておく（戦闘や低 HP のときだけ可視化）。
    pub def attach(unitPath: NodePath, maxHp: Int32, position: BarPosition, scene: Scene[NodeTag]): Scene[NodeTag] =
        if (maxHp <= 0) scene
        else {
            let outerSize = computeOuterSize(maxHp);
            let yOffset = match position {
                case BarPosition.Above => barTopY()
                case BarPosition.Below => barBottomY()
            };
            let barOffset: Vec2.Vec2 = {
                x = 0.0 - outerSize#x / 2.0,
                y = yOffset
            };
            let data: HPBarData = {
                remaining = Duration.zero(),
                maxHp = maxHp,
                currentHp = maxHp
            };
            // 親 Marker2D（初期は不可視）
            let parent = Marker2D.make(barOffset)
                |> CanvasItem.setVisible(false);
            let barPath = List.append(unitPath, childName() :: Nil);
            let withParent =
                Scene.addChildAt(unitPath, childName(),
                    EngineNode.Marker2DWithState(parent, NodeTag.HPBar(data)), scene);
            // 背景 ColorRect（外枠 = 味方青 / 敵赤）
            let bg = ColorRect.make(outerSize, borderColorFor(position))
                |> CanvasItem.setZIndex(barZIndex());
            let withBg =
                Scene.addChildAt(barPath, "Bg",
                    EngineNode.ColorRectWithState(bg, NodeTag.NoTag), withParent);
            // 内側 ColorRect（黒）— cell 間 1px gap の見え方を担う
            let innerSize: Vec2.Vec2 = {
                x = outerSize#x - 2.0 * borderPx(),
                y = outerSize#y - 2.0 * borderPx()
            };
            let innerBg = ColorRect.make(innerSize, bgColor())
                |> Node2D.setPosition({x = borderPx(), y = borderPx()})
                |> CanvasItem.setZIndex(barZIndex() + 1);
            let withInnerBg =
                Scene.addChildAt(barPath, "InnerBg",
                    EngineNode.ColorRectWithState(innerBg, NodeTag.NoTag), withBg);
            // セル群（初期は全て明緑）
            List.foldLeft(acc -> i -> {
                let cell = ColorRect.make({x = cellWidthPx(), y = cellHeightPx()},
                                           fillColorHealthy())
                    |> Node2D.setPosition(cellLocalPos(i))
                    |> CanvasItem.setZIndex(barZIndex() + 2);
                Scene.addChildAt(barPath, cellName(i),
                    EngineNode.ColorRectWithState(cell, NodeTag.NoTag), acc)
            }, withInnerBg, List.range(0, maxHp))
        }

    /// HP 変化を反映する。各セル ColorRect の modulate 色を切り替えると同時に、
    /// 親 HPBarData の `remaining` をリセット（戦闘表示タイマー再点火）して即可視化する。
    /// 対象ユニットに HPBar が未設置なら no-op。
    pub def update(unitPath: NodePath, currentHp: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let barPath = List.append(unitPath, childName() :: Nil);
        // 1. セルの色を更新
        let cellNames = Scene.getChildrenAt(barPath, scene)
            |> List.filter(name -> String.startsWith({prefix = "Cell_"}, name));
        let withCells = List.foldLeft(acc -> name -> {
            match Int32.fromString(String.dropLeft(5, name)) {
                case Some(idx) =>
                    let color = colorForIndex(idx, currentHp);
                    let cellPath = List.append(barPath, name :: Nil);
                    Scene.mapEngineNode(cellPath, n ->
                        EngineNode.mapColorRect(c -> CanvasItem.setModulate(color, c), n),
                        acc)
                case None => acc
            }
        }, scene, cellNames);
        // 2. 親 Marker2D の HPBarData を更新（timer 再点火 + currentHp 更新）+ 可視化
        Scene.mapEngineNode(barPath, n -> match n {
            case EngineNode.Marker2DWithState(m, NodeTag.HPBar(d)) =>
                let newData: HPBarData = {
                    remaining = combatVisibleDuration(),
                    currentHp = currentHp
                    | d
                };
                let newMarker = CanvasItem.setVisible(true, m);
                EngineNode.Marker2DWithState(newMarker, NodeTag.HPBar(newData))
            case other => other
        }, withCells)

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から、各 HPBar ノードに
    /// 対して per-node dispatch される。timer を dt 分減らして可視性を再評価する。
    /// 可視条件: `remaining > 0` OR HP 比率 ≤ 30% (警告)。
    pub def process(dt: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) =
        let next = Scene.mapEngineNode(path, n -> match n {
            case EngineNode.Marker2DWithState(m, NodeTag.HPBar(d)) =>
                let newRemaining = Duration.subClampedToZero(d#remaining, dt);
                let ratio = hpRatio(d#currentHp, d#maxHp);
                let shouldShow = Duration.isPositive(newRemaining) or ratio <= lowHpThreshold();
                let newMarker = CanvasItem.setVisible(shouldShow, m);
                let newData: HPBarData = {remaining = newRemaining | d};
                EngineNode.Marker2DWithState(newMarker, NodeTag.HPBar(newData))
            case other => other
        }, scene);
        (node, next)
}
