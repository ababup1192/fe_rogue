/// BattlePanelScene — 攻撃前の戦闘予報ミニウィンドウ
///
/// `WeaponSelect`（武器選択）/ `PlayerAttack`（ターゲット選択）フェーズで、
/// 「命中 / 必殺 / 武器相性（すくみ）の矢印」だけを並べた小さなウィンドウを出す。
/// 攻撃側（味方・青）と反撃側（敵・赤）の 2 行構成で、丸（●）と三角（▲▼）は文字でなく
/// Polygon2D ノードで描く（色は HTML プロトタイプ準拠）。
///
/// **画面空間（CanvasLayer）** に置く。World 空間に置くと camera zoom 下で engine の
/// Label2D が字送り（位置）をズームせず文字が散らばって枠から溢れるため。
/// 「攻撃側・対象に被らない」配置は、対象ユニットのワールド座標を `Camera2D` の
/// ViewTransform で画面座標へ写し（`reposition`）、対象から見て攻撃側と反対側へ panel を
/// 毎フレーム移動して実現する（盤面追従だが描画は画面空間）。
///
/// 各行は「命中/必殺ラベル・数値・%」を別ラベルに分けて、HTML プロトタイプ同様に
/// **ラベル/%は小さく薄く、数値は大きく、必殺系は黄色**で描く（1 ラベルだと色/サイズを
/// 出し分けられないため）。配置は 2 行共通の固定列（`computeColumns`）で揃え、数値は
/// 3 桁ぶんを確保した列の右端へ右詰めする（命中値/反撃値/必殺値の縦ラインが桁数に依らず揃う）。
///
/// ノード構造（CanvasLayer・永続。可視性は process がフェーズで切り替える）:
///   BattleForecast (CanvasLayer, layer=3, NodeTag.BattlePanel)   ← scene.json
///     └─ panel (Panel)        … 角丸の枠（bg 兼 子の親。毎フレーム対象近傍へ移動）
///          ├─ aDot (Polygon2D)             攻撃側マーカー（青丸）
///          ├─ aHitLbl/aHitNum/aHitPct      "命中" + 数値 + "%"
///          ├─ aCritLbl/aCritNum/aCritPct   "必殺" + 数値 + "%"（黄）
///          ├─ aTri (Polygon2D)             攻撃側の相性矢印（▲緑 / ▼桃 / 中立は非表示）
///          ├─ dDot (Polygon2D)             反撃側マーカー（赤丸）
///          ├─ dHitLbl/dHitNum/dHitPct      "反撃" + 数値 + "%"（反撃不可は "反撃 --"）
///          ├─ dCritLbl/dCritNum/dCritPct   "必殺" + 数値 + "%"（黄）
///          └─ dTri (Polygon2D)             反撃側の相性矢印
mod BattlePanelScene {

    /// 「減る分」点滅サイクルの累積時間を持つ resource。
    /// process が毎フレーム delta で進め、`blinkDark` で暗/明を判定する。LogScene.State と同型の Ref-backed handler。
    /// `Game.start` で `with BattlePanelScene.withState(rc)` を注入し、`FrameAef.ProcessT` に足す。
    pub eff State {
        def get(): Duration.Duration
        def put(elapsed: Duration.Duration): Unit
    }

    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[Duration.Duration, r] = Ref.fresh(rc, Duration.zero());
            run {
                thunk()
            } with handler State {
                def get(k)          = k(Ref.get(ref))
                def put(elapsed, k) = { Ref.put(elapsed, ref); k() }
            }
        }

    // ────────────────────────────────────────────────────────
    // (B) 定数 — ノード名 / パス
    // ────────────────────────────────────────────────────────

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/BattlePanelScene.scene.json")

    /// fontManifest で登録した name と一致させる（LogScene / WeaponMenuScene と同じ "ui"）
    def fontName(): String = "ui"

    def rootName(): String  = "BattleForecast"
    def panelName(): String = "panel"
    def aDotName(): String     = "aDot"
    def aHitLblName(): String  = "aHitLbl"
    def aHitNumName(): String  = "aHitNum"
    def aHitPctName(): String  = "aHitPct"
    def aCritLblName(): String = "aCritLbl"
    def aCritNumName(): String = "aCritNum"
    def aCritPctName(): String = "aCritPct"
    def aTriName(): String     = "aTri"
    def dDotName(): String     = "dDot"
    def dHitLblName(): String  = "dHitLbl"
    def dHitNumName(): String  = "dHitNum"
    def dHitPctName(): String  = "dHitPct"
    def dCritLblName(): String = "dCritLbl"
    def dCritNumName(): String = "dCritNum"
    def dCritPctName(): String = "dCritPct"
    def dTriName(): String     = "dTri"

    /// CanvasLayer ルートの NodePath（dispatch 対象 / 状態タグの置き場）。
    pub def rootPath(): NodePath = rootName() :: Nil
    /// 枠 Panel（bg 兼 子の親）。毎フレーム移動・リサイズする対象。
    def panelPath(): NodePath = rootName() :: panelName() :: Nil
    /// 丸/ラベル/三角は panel の子。panel を動かせば一緒に動く。
    def childPath(name: String): NodePath = rootName() :: panelName() :: name :: Nil

    // ────────────────────────────────────────────────────────
    // (B') 定数 — レイアウト（design px。CanvasLayer なのでズーム非適用＝そのまま画面 px）
    // ────────────────────────────────────────────────────────

    def winH(): Float64 = 12.0
    /// 命中/反撃/必殺ラベル・% の小さめフォント（薄色）。一回り小さめ。
    def labelFont(): Float64 = 2.3
    /// 数値（命中値・必殺値）の大きめフォント。
    def numFont(): Float64 = 3.6
    /// 行マーカー（丸）の半径（直径 ≈ 4px 相当の小さめ）。
    def dotRadius(): Float64 = 0.4
    /// 相性三角の半幅 / 半高。
    def triHalfW(): Float64 = 1.5
    def triHalfH(): Float64 = 1.3
    /// 列のすき間（ラベル↔数値 / 数値↔% / グループ↔グループ / 三角前）。
    def segGap(): Float64 = 0.5
    def pctGap(): Float64 = 0.3
    def groupGap(): Float64 = 2.2
    def triGap(): Float64 = 2.0
    /// ウィンドウ右端の余白。
    def padRight(): Float64 = 3.0
    /// 文字の縦オフセット（design px）。正で丸中心より上、負で下。
    /// 参考に合わせて丸中心よりわずかに下げる。
    def textNudge(): Float64 = 0.25

    /// 各要素の x（左基準）/ 行中心 y。x とウィンドウ幅は毎フレーム process が実測で決める。
    def dotX(): Float64  = 3.5
    def hitX(): Float64  = 6.0
    def triXInit(): Float64 = 40.0
    def row1CenterY(): Float64 = 3.6
    def row2CenterY(): Float64 = 8.4

    /// 子（丸・ラベル・三角）の zIndex。枠 Panel（scene.json で 0）より前面に出す。
    def contentZIndex(): Int32 = 1

    // ────────────────────────────────────────────────────────
    // (B'') 定数 — 配色（HTML プロトタイプ準拠。bg/枠色は scene.json 側）
    // ────────────────────────────────────────────────────────

    /// 反撃側マーカーの赤 #e0463f。
    def enemyDotColor(): Color = {r = 0.878f32, g = 0.275f32, b = 0.247f32}
    /// 命中/反撃ラベル・% の薄い青灰（#7d8aa3 ＝ UITheme.faint）。
    def faintColor(): Color = UITheme.faint()
    /// 命中値・反撃値（数値）= 白。
    def numColor(): Color = UITheme.white()
    /// 必殺系（ラベル・数値・%）の黄 #f5c542。
    def critColor(): Color = {r = 0.961f32, g = 0.773f32, b = 0.259f32}
    /// 有利（▲）の緑 #7fe08a。
    def advantageColor(): Color = {r = 0.498f32, g = 0.878f32, b = 0.541f32}
    /// 不利（▼）の桃赤 #ff9a90。
    def disadvantageColor(): Color = {r = 1.0f32, g = 0.604f32, b = 0.565f32}

    // ────────────────────────────────────────────────────────
    // (C) 構築 — add
    // ────────────────────────────────────────────────────────

    /// CanvasLayer + panel（枠）を scene.json から読み、panel 配下に丸・ラベル・三角を生やす。
    /// 初期は全子ノードを非表示にし、`process` がフェーズと対象に応じて表示・更新する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                      SceneLoader.constTagParser(NodeTag.NoTag), scene)
            |> Scene.setState(rootPath(), NodeTag.BattlePanel)   // 状態は BattlePanelScene.State resource へ
            |> addDot(aDotName(), row1CenterY(), UITheme.allyBlue())
            |> addDot(dDotName(), row2CenterY(), enemyDotColor())
            // 攻撃側の行（ラベル/% は薄色で左寄せ、数値は白で右詰め＝3 桁列の右端基準）
            |> addLabel(aHitLblName(),  atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row1CenterY())
            |> addLabel(aHitNumName(),  atlas, numFont(),   numColor(),   HorizontalAlignment.Right, row1CenterY())
            |> addLabel(aHitPctName(),  atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row1CenterY())
            // 必殺は「命中」ラベルと同じ font / 色（薄色）に揃える。数値だけ黄で目立たせる。
            |> addLabel(aCritLblName(), atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row1CenterY())
            |> addLabel(aCritNumName(), atlas, numFont(),   critColor(),  HorizontalAlignment.Right, row1CenterY())
            |> addLabel(aCritPctName(), atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row1CenterY())
            // 反撃側の行
            |> addLabel(dHitLblName(),  atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row2CenterY())
            |> addLabel(dHitNumName(),  atlas, numFont(),   numColor(),   HorizontalAlignment.Right, row2CenterY())
            |> addLabel(dHitPctName(),  atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row2CenterY())
            |> addLabel(dCritLblName(), atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row2CenterY())
            |> addLabel(dCritNumName(), atlas, numFont(),   critColor(),  HorizontalAlignment.Right, row2CenterY())
            |> addLabel(dCritPctName(), atlas, labelFont(), faintColor(), HorizontalAlignment.Left,  row2CenterY())
            |> addTri(aTriName(), row1CenterY())
            |> addTri(dTriName(), row2CenterY())
            |> setAllVisible(false)

    /// 行マーカー（丸）を Polygon2D で panel の子に追加する。
    def addDot(name: String, centerY: Float64, color: Color,
               scene: Scene[NodeTag]): Scene[NodeTag] =
        let dot = Polygon2D.circle(dotRadius(), color)
            |> Node2D.setPosition(({x = dotX(), y = centerY}: Vec2.Vec2))
            |> CanvasItem.setZIndex(contentZIndex());
        Scene.addChildAt(panelPath(), name,
            EngineNode.Polygon2DWithState(dot, NodeTag.NoTag), scene)

    /// ラベル（1 セグメント）を panel の子に追加する。テキストは空で生成し、process で `setText`。
    /// 縦は丸の中心に合わせるため VerticalAlignment.Center（フォントが違っても同じ行に揃う）。
    /// `align` は横揃え: ラベル・% は Left、数値は Right（3 桁ぶんの列右端へ右詰め）。
    def addLabel(name: String, atlas: FontAtlas, font: Float64, color: Color,
                 align: HorizontalAlignment, centerY: Float64,
                 scene: Scene[NodeTag]): Scene[NodeTag] =
        let label = Label2D.make("", atlas, font)
            |> Node2D.setPosition(({x = hitX(), y = centerY - textNudge()}: Vec2.Vec2))
            |> Label2D.setHorizontalAlignment(align)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(color)
            |> CanvasItem.setZIndex(contentZIndex());
        Scene.addChildAt(panelPath(), name,
            EngineNode.Label2DWithState(label, NodeTag.NoTag), scene)

    /// 相性三角を Polygon2D で panel の子に追加する（頂点・色・可視・x は process で確定）。
    def addTri(name: String, centerY: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let tri = Polygon2D.make(triUpPoints(), advantageColor())
            |> Node2D.setPosition(({x = triXInit(), y = centerY}: Vec2.Vec2))
            |> CanvasItem.setZIndex(contentZIndex());
        Scene.addChildAt(panelPath(), name,
            EngineNode.Polygon2DWithState(tri, NodeTag.NoTag), scene)

    /// 上向き三角（▲ = 有利）の頂点列（局所座標）。
    def triUpPoints(): List[Vec2.Vec2] =
        ({x = 0.0,              y = 0.0 - triHalfH()}: Vec2.Vec2) ::
        ({x = 0.0 - triHalfW(), y = triHalfH()}: Vec2.Vec2) ::
        ({x = triHalfW(),       y = triHalfH()}: Vec2.Vec2) :: Nil

    /// 下向き三角（▼ = 不利）の頂点列（局所座標）。
    def triDownPoints(): List[Vec2.Vec2] =
        ({x = 0.0,              y = triHalfH()}: Vec2.Vec2) ::
        ({x = 0.0 - triHalfW(), y = 0.0 - triHalfH()}: Vec2.Vec2) ::
        ({x = triHalfW(),       y = 0.0 - triHalfH()}: Vec2.Vec2) :: Nil

    // ────────────────────────────────────────────────────────
    // (D) ロジック — process
    // ────────────────────────────────────────────────────────

    /// `Game.flix` の `process` redef から `BattlePanel` タグの CanvasLayer に dispatch される。
    /// 予報を出すのは 2 フェーズ:
    ///   - WeaponSelect : 武器選択中。カーソルが乗っている対象の敵 × カーソル中の武器で予報
    ///                    （WeaponSelectUi がカーソルを対象の敵へスナップする）
    ///   - PlayerAttack : 赤マスで敵を選択中。カーソル上の敵 × 装備武器で予報
    /// それ以外のフェーズや対象が居ないときはウィンドウを隠し、足元 HP バー予測も消す。
    /// `GameEngine.Game` は viewport / カメラ ViewTransform 取得（対象ワールド座標→画面座標）に使う。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                       PlayerData.PartyQuery, EnemyData.RosterQuery, World.Command, World.WorldQuery,
                       BattlePanelScene.State, UnitHPBarRender.ForecastState, UiWorldState.State} =
        let phase  = TurnPhase.State.get();
        let synced = syncTargetToCursor(phase, scene);
        // 「減る分」の暗⇄明点滅サイクルを進める。累積時間は resource が持つ。
        // dark フラグ（前半=暗 / 後半=明）を足元 HP バー予測に渡す。
        let elapsed = Duration.add(BattlePanelScene.State.get(), delta);
        BattlePanelScene.State.put(elapsed);
        let dark    = blinkDark(elapsed);
        match buildForecast(phase, synced) {
            case Some(view) =>
                let textd = synced |> setAllVisible(true) |> updateContent(view);
                // 2 行で縦ラインを揃えるため固定列を一度だけ算出し、両行へ同じ列を使う。
                // 数値は 3 桁ぶんを確保した列の右端へ右詰め（命中・反撃・必殺の数値が桁数に依らず揃う）。
                let atlas = GameEngine.Game.getFontAtlas(fontName());
                let cols  = computeColumns(atlas, textd);
                let aEnd  = cols#groupEndX;   // 攻撃側は必殺まで常に出る
                let dEnd  = if (view#counter) cols#groupEndX else cols#hitNumRight;  // 反撃なしは "反撃 --" まで
                let sA = layoutRow(aHitLblName(), aHitNumName(), aHitPctName(),
                                   aCritLblName(), aCritNumName(), aCritPctName(),
                                   true, cols, row1CenterY(), textd);
                let sD = layoutRow(dHitLblName(), dHitNumName(), dHitPctName(),
                                   dCritLblName(), dCritNumName(), dCritPctName(),
                                   view#counter, cols, row2CenterY(), sA);
                let triCx    = Float64.max(aEnd, dEnd) + triGap() + triHalfW();
                let contentW = triCx + triHalfW() + padRight();
                let shown = sD
                    |> setNodeX(childPath(aTriName()), triCx, row1CenterY())
                    |> setNodeX(childPath(dTriName()), triCx, row2CenterY())
                    |> resizeBg(contentW)
                    |> reposition(view, contentW);
                // 足元 HP バーの「減る分」は ForecastState resource へ put し、
                // UnitHPBarRender.renderBars が直描き時に反映する。
                UnitHPBarRender.ForecastState.put(Some(
                    {attackerId = view#attackerId, playerHpPost = view#playerHpPost,
                     defenderId = view#defenderId, enemyHpPost = view#enemyHpPost,
                     dark = dark}));
                (node, shown)
            case None =>
                UnitHPBarRender.ForecastState.put(None);
                let hidden = synced
                    |> setAllVisible(false);
                (node, hidden)
        }

    /// 「減る分」点滅の暗フレーム判定。周期 `blinkPeriodSec()` 秒の前半を暗（dark=true）、
    /// 後半を明（dark=false）にする。`elapsed` は process が delta で進めるサイクル累積時間。
    def blinkPeriodSec(): Float64 = 1.0
    def blinkDark(elapsed: Duration.Duration): Bool =
        let s = Duration.toSeconds(elapsed);
        let p = blinkPeriodSec();
        let inCycle = s - p * Float64.floor(s / p);
        inCycle < p / 2.0

    /// 2 行で縦ラインを揃えるための固定列 x（design px・左基準。数値列は右端）。
    type alias Columns = {
        hitNumRight = Float64, hitPctX = Float64,
        critLblX = Float64, critNumRight = Float64, critPctX = Float64,
        groupEndX = Float64
    }

    /// 固定列を算出する。命中/反撃ラベル幅・% 幅は実ノードから、数値列は "000"（3 桁）の
    /// 実測幅を確保する。これで命中値/反撃値/必殺値が桁数に依らず同じ縦ラインに揃う。
    def computeColumns(atlas: FontAtlas, scene: Scene[NodeTag]): Columns =
        let labelW = measureWidthAt(childPath(aHitLblName()), scene);
        let pctW   = measureWidthAt(childPath(aHitPctName()), scene);
        let num3W  = Label2D.measure(Label2D.make("000", atlas, numFont()))#x;
        let hitNumRight  = hitX() + labelW + segGap() + num3W;
        let hitPctX      = hitNumRight + pctGap();
        let critLblX     = hitPctX + pctW + groupGap();
        let critNumRight = critLblX + labelW + segGap() + num3W;
        let critPctX     = critNumRight + pctGap();
        {hitNumRight = hitNumRight, hitPctX = hitPctX,
         critLblX = critLblX, critNumRight = critNumRight, critPctX = critPctX,
         groupEndX = critPctX + pctW}

    /// 1 行（命中/必殺グループ）を固定列に配置する。ラベル・% は左寄せ、数値は列右端へ右詰め。
    /// 反撃なし（hasCrit=false）の行は命中グループだけ置く（"反撃 --"。必殺列は空文字で不可視）。
    def layoutRow(hitLbl: String, hitNum: String, hitPct: String,
                  critLbl: String, critNum: String, critPct: String,
                  hasCrit: Bool, cols: Columns, centerY: Float64,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        let y = centerY - textNudge();
        let base = scene
            |> setNodeX(childPath(hitLbl), hitX(),          y)
            |> setNodeX(childPath(hitNum), cols#hitNumRight, y)
            |> setNodeX(childPath(hitPct), cols#hitPctX,     y);
        if (hasCrit)
            base
                |> setNodeX(childPath(critLbl), cols#critLblX,     y)
                |> setNodeX(childPath(critNum), cols#critNumRight, y)
                |> setNodeX(childPath(critPct), cols#critPctX,     y)
        else base

    /// 枠 Panel を内容幅に合わせてリサイズする（% のはみ出し防止）。
    def resizeBg(contentW: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        Panel.mapAt(panelPath(),
            Panel.setSize(({x = contentW, y = winH()}: Vec2.Vec2)), scene)

    /// PlayerAttack 中、攻撃対象をカーソル位置の敵に毎フレーム同期する。
    /// カーソルが敵に乗っていなければ対象をクリアする（予報は出ない）。
    def syncTargetToCursor(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, CursorState.State, World.Command, World.WorldQuery} =
        if (phase != TurnPhase.Phase.PlayerAttack) scene
        else match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) =>
                match EnemyScene.findIdAt(CursorScene.getGridPos(), scene) {
                    case Some(enemyId) => CombatDriver.setAttackTargetId(attackerId, enemyId, scene)
                    case None          => CombatDriver.clearAttackTargetId(attackerId, scene)
                }
        }

    /// 枠 panel を、対象ユニットの**画面座標**の近傍へ移動する。
    /// 対象 / 攻撃側のワールド座標を camera ViewTransform で画面 px に写し、対象の
    /// 右 → 上 → 下 の順で「画面内に収まり、かつ攻撃側に被らない」最初の位置を選ぶ。
    /// 左は常設 UI（コマンド / 武器ウィンドウ）と被るので候補に入れない。
    /// カメラ未登録時（テスト等）は移動しない。
    def reposition(view: ForecastView, contentW: Float64,
                   scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match viewTransform(scene) {
            case None                 => scene
            case Some((vt, vpW, vpH)) =>
                let st   = Camera2D.applyToWorldPos(vt, MapSnapshot.cellCenter(view#targetCell));
                let sa   = Camera2D.applyToWorldPos(vt, MapSnapshot.cellCenter(view#attackerCell));
                let half = MapSnapshot.tileSize() / 2.0 * vt#scale#x;  // 半タイルを画面 px に換算
                let pos  = anchorPos(st, sa, half, contentW, vpW, vpH);
                Panel.mapAt(panelPath(), Node2D.setPosition(pos), scene)
        }

    /// アクティブカメラの ViewTransform と viewport(design px) を取る。未登録なら None。
    def viewTransform(scene: Scene[NodeTag]):
            Option[(Camera2D.ViewTransform, Float64, Float64)] \ GameEngine.Game =
        match Scene.getEngineNode(CameraScene.cameraPath(), scene) {
            case Some(EngineNode.Camera2DWithState(cam, _)) =>
                let camPos = Scene.globalPositionAt(CameraScene.cameraPath(), scene);
                let vp = GameEngine.Game.getViewportRect();
                let vt = Camera2D.getViewTransform(cam, camPos,
                            {viewportWidth = vp#size#x, viewportHeight = vp#size#y});
                Some((vt, vp#size#x, vp#size#y))
            case _ => None
        }

    /// panel の左上画面座標を決める。対象 `st` の 右 → 上 → 下 を候補にし、
    /// 「画面内に収まり、攻撃側 `sa` に被らない」最初の候補を採用する（左は常設 UI と
    /// 被るので候補にしない）。どれも不適なら右候補を画面内へクランプして使う。
    def anchorPos(st: Vec2.Vec2, sa: Vec2.Vec2, half: Float64, contentW: Float64,
                  vpW: Float64, vpH: Float64): Vec2.Vec2 =
        let gap = 4.0;
        let right = ({x = st#x + half + gap,     y = st#y - winH() / 2.0}: Vec2.Vec2);
        let above = ({x = st#x - contentW / 2.0, y = st#y - half - gap - winH()}: Vec2.Vec2);
        let below = ({x = st#x - contentW / 2.0, y = st#y + half + gap}: Vec2.Vec2);
        let good = c -> fitsOnScreen(c, contentW, vpW, vpH) and not coversPoint(c, contentW, sa);
        match List.findLeft(good, right :: above :: below :: Nil) {
            case Some(c) => c
            case None    => clampToScreen(right, contentW, vpW, vpH)
        }

    /// panel 矩形（左上 c, サイズ contentW×winH）が画面（design 矩形）内に収まるか。
    def fitsOnScreen(c: Vec2.Vec2, contentW: Float64, vpW: Float64, vpH: Float64): Bool =
        let m = 2.0;
        c#x >= m and c#x + contentW <= vpW - m and c#y >= m and c#y + winH() <= vpH - m

    /// 点 p が panel 矩形（左上 c, サイズ contentW×winH）に含まれるか（攻撃側被り判定）。
    def coversPoint(c: Vec2.Vec2, contentW: Float64, p: Vec2.Vec2): Bool =
        p#x >= c#x and p#x <= c#x + contentW and p#y >= c#y and p#y <= c#y + winH()

    /// 画面（design 矩形）からはみ出さないよう左上座標をクランプする。
    def clampToScreen(p: Vec2.Vec2, contentW: Float64, vpW: Float64, vpH: Float64): Vec2.Vec2 =
        let m = 2.0;
        let maxX = Float64.max(m, vpW - contentW - m);
        let maxY = Float64.max(m, vpH - winH() - m);
        {x = p#x |> Float64.max(m) |> Float64.min(maxX),
         y = p#y |> Float64.max(m) |> Float64.min(maxY)}

    /// 各ラベルのテキストと三角（相性矢印）を予報から確定する。色・フォントは add で固定済み。
    /// 反撃が無いときは反撃数値を "--"、% と必殺グループを空にして矢印も消す。
    def updateContent(view: ForecastView, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> setLabelText(aHitLblName(),  "命中")
            |> setLabelText(aHitNumName(),  "${view#aHit}")
            |> setLabelText(aHitPctName(),  "%")
            |> setLabelText(aCritLblName(), "必殺")
            |> setLabelText(aCritNumName(), "${view#aCrit}")
            |> setLabelText(aCritPctName(), "%")
            |> setLabelText(dHitLblName(),  "反撃")
            |> setLabelText(dHitNumName(),  if (view#counter) "${view#dHit}" else "--")
            |> setLabelText(dHitPctName(),  if (view#counter) "%" else "")
            |> setLabelText(dCritLblName(), if (view#counter) "必殺" else "")
            |> setLabelText(dCritNumName(), if (view#counter) "${view#dCrit}" else "")
            |> setLabelText(dCritPctName(), if (view#counter) "%" else "")
            |> updateTriangle(childPath(aTriName()), Some(view#aRel))
            |> updateTriangle(childPath(dTriName()), if (view#counter) Some(view#dRel) else None)

    def setLabelText(name: String, text: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Label2D.mapAt(childPath(name), Label2D.setText(text), scene)

    /// 相性 Relation に応じて三角の頂点・色・可視を切り替える。中立 / 反撃なし（None）は非表示。
    def updateTriangle(path: NodePath, rel: Option[WeaponTriangle.Relation],
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        match rel {
            case Some(WeaponTriangle.Relation.Advantage) =>
                setTriangle(path, triUpPoints(), advantageColor(), scene)
            case Some(WeaponTriangle.Relation.Disadvantage) =>
                setTriangle(path, triDownPoints(), disadvantageColor(), scene)
            case _ =>
                setPolyVisible(path, false, scene)
        }

    /// 三角ノードに頂点・色をセットして表示する。
    def setTriangle(path: NodePath, points: List[Vec2.Vec2], color: Color,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(path, en -> EngineNode.mapPolygon2D(p -> p
            |> Polygon2D.setPoints(points)
            |> CanvasItem.setModulate(color)
            |> CanvasItem.setVisible(true), en), scene)

    // ────────────────────────────────────────────────────────
    // (D-layout) ノード位置 / 計測ヘルパー
    // ────────────────────────────────────────────────────────

    /// Label2D / Polygon2D ノードの位置を (x, y) にセットする（型ごとに分岐）。
    def setNodeX(path: NodePath, x: Float64, y: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(path, en -> match en {
            case EngineNode.Label2DWithState(l, t) =>
                EngineNode.Label2DWithState(Node2D.setPosition(({x = x, y = y}: Vec2.Vec2), l), t)
            case EngineNode.Polygon2DWithState(p, t) =>
                EngineNode.Polygon2DWithState(Node2D.setPosition(({x = x, y = y}: Vec2.Vec2), p), t)
            case other => other
        }, scene)

    /// 指定 Label2D の描画幅（design px）。未登録 / 空文字なら 0。
    def measureWidthAt(path: NodePath, scene: Scene[NodeTag]): Float64 =
        match Scene.getEngineNode(path, scene) {
            case Some(EngineNode.Label2DWithState(l, _)) => Label2D.measure(l)#x
            case _                                       => 0.0
        }

    // ────────────────────────────────────────────────────────
    // (D') 可視性ヘルパー — 子ノードは親可視性を見ない実装なので個別に切り替える
    // ────────────────────────────────────────────────────────

    /// 枠・丸・ラベル・三角すべての visible をまとめて切り替える。
    /// （Label2D / Polygon2D / Panel は描画パス上で親の visible を参照しないため、
    ///  CursorScene.setVisible と同様に各子へ個別に setVisible する）
    def setAllVisible(visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let labels = aHitLblName() :: aHitNumName() :: aHitPctName()
                  :: aCritLblName() :: aCritNumName() :: aCritPctName()
                  :: dHitLblName() :: dHitNumName() :: dHitPctName()
                  :: dCritLblName() :: dCritNumName() :: dCritPctName() :: Nil;
        let withLabels = List.foldLeft((acc, name) ->
            Label2D.mapAt(childPath(name), CanvasItem.setVisible(visible), acc), scene, labels);
        withLabels
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> setPolyVisible(childPath(aDotName()), visible)
            |> setPolyVisible(childPath(dDotName()), visible)
            |> setPolyVisible(childPath(aTriName()), visible)
            |> setPolyVisible(childPath(dTriName()), visible)

    /// Polygon2D ノードの可視性を変える（型付き `mapAt` が無いため mapEngineNode 経由）。
    def setPolyVisible(path: NodePath, visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(path,
            en -> EngineNode.mapPolygon2D(p -> CanvasItem.setVisible(visible, p), en), scene)

    // ────────────────────────────────────────────────────────
    // (D'') 足元 HP バーのダメージ予測（パネルとは独立した盤面フィードバック）
    // ────────────────────────────────────────────────────────

    // 予報は ForecastState resource へ put し renderBars が消費する（put(None) が全消しに相当）。

    // ────────────────────────────────────────────────────────
    // (D''') 予報の組み立て（純計算 + クエリ）
    // ────────────────────────────────────────────────────────

    /// 予報ビュー。ウィンドウ表示と HP バー予測に必要な値だけを持つ。
    type alias ForecastView = {
        attackerCell = {x = Int32, y = Int32}, targetCell = {x = Int32, y = Int32},
        attackerId = Int32, defenderId = Int32,
        aHit = Int32, aCrit = Int32, aRel = WeaponTriangle.Relation,
        counter = Bool, dHit = Int32, dCrit = Int32, dRel = WeaponTriangle.Relation,
        playerHpCur = Int32, playerHpPost = Int32,
        enemyHpCur = Int32, enemyHpPost = Int32
    }

    /// 攻撃中の武器選択リストでアクティブな武器（カーソル上の敵に届く選択武器）。
    /// 敵が居ない / 届く武器が無いなら None（予報は出ない）。
    def selectedAttackWeapon(scene: Scene[NodeTag]):
            Option[UnitCatalog.WeaponResource]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, World.WorldQuery} =
        forM (
            idx      <- ItemMenuScene.activeAttackWeaponIndex(scene);
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
            w        <- List.nth(idx, player#weapons)
        ) yield w

    /// フェーズに応じて予報ビューを組み立てる。
    ///   - WeaponSelect : カーソル中の武器 × カーソルが乗っている敵
    ///   - PlayerAttack : 選択中の敵 × 装備武器
    /// 揃わない / 別フェーズなら None。
    def buildForecast(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               World.WorldQuery, UiWorldState.State} =
        match phase {
            case TurnPhase.Phase.WeaponSelect => buildWeaponSelectForecast(scene)
            case TurnPhase.Phase.PlayerAttack => buildAttackForecast(scene)
            case _                            => None
        }

    /// PlayerAttack: 選択中味方 / カーソル上の敵 / 装備（活性）武器が揃ったら予報。
    def buildAttackForecast(scene: Scene[NodeTag]): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(pid);
            eid    <- player#attackTargetId;
            enemy  <- EnemyData.RosterQuery.get(eid);
            weapon <- selectedAttackWeapon(scene)
        ) yield computeView(pid, player, eid, enemy, weapon)

    /// WeaponSelect: 選択中味方 / カーソル中の武器 / カーソルが乗っている敵が揃ったら予報。
    /// カーソルは `WeaponSelectUi` が「その武器が届く最寄りの敵」へスナップ済み。
    def buildWeaponSelectForecast(scene: Scene[NodeTag]): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               World.WorldQuery, UiWorldState.State} =
        forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(pid);
            widx   <- WeaponSelectUi.hoveredWeaponIndex();
            weapon <- List.nth(widx, player#weapons);
            eid    <- EnemyScene.findIdAt(CursorScene.getGridPos(), scene);
            enemy  <- EnemyData.RosterQuery.get(eid)
        ) yield computeView(pid, player, eid, enemy, weapon)

    /// 予報ビューを純計算で組み立てる。命中 / 必殺は `Combat.estimate`（faction 非依存）、
    /// すくみは `WeaponTriangle.relationOpt`。HP は攻撃 / 反撃ダメージから戦闘後 HP を逆算する。
    def computeView(pid: Int32, player: PlayerScene.Data,
                    eid: Int32, enemy: EnemyScene.Data,
                    weapon: UnitCatalog.WeaponResource): ForecastView =
        let aRel = WeaponTriangle.relationOpt(weapon#weaponType,
                       enemy#weapon |> Option.map(w -> w#weaponType));
        let aForecast = Combat.estimate(PlayerScene.combatViewWith(player, weapon),
                                        EnemyScene.combatView(enemy));
        let counter = formatCounter(player, weapon, enemy);
        let enemyHpPost  = Int32.max(0, enemy#hp - aForecast#damage);
        let playerHpPost = Int32.max(0, player#hp - counter#damage);
        {attackerCell = player#gridPos, targetCell = enemy#gridPos,
         attackerId = pid, defenderId = eid,
         aHit = aForecast#hit, aCrit = aForecast#crit, aRel = aRel,
         counter = counter#canCounter, dHit = counter#hit, dCrit = counter#crit, dRel = counter#rel,
         playerHpCur = player#hp, playerHpPost = playerHpPost,
         enemyHpCur = enemy#hp, enemyHpPost = enemyHpPost}

    /// 反撃側（敵 → 味方）の命中 / 必殺 / 相性 / 反撃ダメージ。
    /// 武器なし or 射程外なら反撃不可（canCounter=false、数値 0）。相性は射程に依らず武器で決まる。
    def formatCounter(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                      enemy: EnemyScene.Data):
            {canCounter = Bool, hit = Int32, crit = Int32,
             rel = WeaponTriangle.Relation, damage = Int32} =
        match enemy#weapon {
            case None     =>
                {canCounter = false, hit = 0, crit = 0,
                 rel = WeaponTriangle.Relation.Neutral, damage = 0}
            case Some(ew) =>
                let rel = WeaponTriangle.relationOpt(ew#weaponType, Some(weapon#weaponType));
                let d = Weapon.manhattan(enemy#gridPos, player#gridPos);
                if (not Weapon.canReach(d, ew))
                    {canCounter = false, hit = 0, crit = 0, rel = rel, damage = 0}
                else {
                    let ef = Combat.estimate(EnemyScene.combatView(enemy),
                                             PlayerScene.combatViewWith(player, weapon));
                    {canCounter = true, hit = ef#hit, crit = ef#crit, rel = rel, damage = ef#damage}
                }
        }

    // ────────────────────────────────────────────────────────
    // (D'''') 確定 / キャンセル（フェーズ遷移。ウィンドウ自体は process が追従）
    // ────────────────────────────────────────────────────────

    /// `PlayerAttack` + Z: 戦闘予報を確認した上で攻撃モーションを開始する。
    /// 遷移先は入力をロックする `PlayerAttackHold`（Z 連打での再起動を防ぐ）。
    pub def confirm(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, World.WorldQuery,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State, CursorState.State,
                              PlayerData.PartyQuery, EnemyData.RosterQuery, World.Command} =
        let started = forM (
            attackerId <- SelectedPlayer.State.get()#id;
            player     <- PlayerData.PartyQuery.get(attackerId);
            defenderId <- player#attackTargetId;
            enemy      <- EnemyData.RosterQuery.get(defenderId)
        ) yield {
            let idx      = ItemMenuScene.activeAttackWeaponIndex(scene) |> Option.getWithDefault(0);
            let equipped = PlayerScene.equipWeapon(attackerId, idx, scene);
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("${PlayerScene.displayName(attackerId, scene)}の攻撃");
            CombatDriver.startAttack(Faction.Player, attackerId, defenderId, enemy#gridPos, equipped)
        };
        Option.getWithDefault(scene, started)

    /// `PlayerAttack` + X: 攻撃をやめて行動メニュー (ActionSelect) に戻る。
    /// 待機にはせず、`attackTargetId` をクリアしてカーソルを選択中味方に戻す。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State, CursorState.State,
                              PlayerData.PartyQuery, World.Command} =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) =>
                CombatDriver.clearAttackTargetId(attackerId, scene)
                    |> CursorScene.snapToPlayer
        }
}
