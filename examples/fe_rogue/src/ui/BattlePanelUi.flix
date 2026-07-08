// BattlePanelUi — 攻撃前の戦闘予報ミニウィンドウ（World-entity UI 版）。
//
// UI ツリーは BattlePanel.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。見た目は
// UiRender が毎フレーム描く。ここは「命中 / 必殺 / 武器相性（すくみ）の矢印だけを並べた小窓を、対象の
// 敵の近傍に出す」ゲーム側の配線を持つ。攻撃側（味方・青）と反撃側（敵・赤）の 2 行構成で、丸（●）は
// box の角丸で、相性の三角（▲▼）は poly（凸三角）で描く。
//
// **画面固定 HUD（layer=3・camera 免除）** に置く。World 空間に置くと camera zoom 下でテキストの
// 字送りがズームせず枠から溢れるため。「攻撃側・対象に被らない」配置は、対象ユニットのワールド座標を
// アクティブ Camera の ViewTransform で画面座標へ写し、対象から見て攻撃側と反対側へ panel を毎フレーム
// 移動して実現する（盤面追従だが描画は画面固定）。
//
// 各行は「命中/必殺ラベル・数値・%」を別 text に分けて、ラベル/% は小さく薄く、数値は大きく、必殺系は
// 黄色で描く。配置は 2 行共通の固定列（`computeColumns`）で揃え、数値は 3 桁ぶんを確保した列の右端へ
// 右詰めする（数値の縦ラインが桁数に依らず揃う）。World-entity UI の text は右揃えを持たないため、
// 数値は実測幅ぶん左へずらして右端を揃える（`putRight`）。
//
// 演出状態（「減る分」点滅サイクルの累積時間）は BattlePanelState resource が権威。予報の数値は
// PartyQuery / RosterQuery / World / 選択カーソルから毎フレーム読む。足元 HP バーの「減る分」予測は
// UnitHPBarRender.ForecastState へ put し renderBars が消費する。
//
// ノード構造（BattlePanel.ui.json / layer=3）:
//   BattlePanel (none, 画面固定 HUD)
//     └─ panel (box, 角丸枠。毎フレーム対象近傍へ setAbs・内容幅へ setWidthPx)
//          ├─ aDot / dDot (box, 角丸=丸)   攻撃側=青丸 / 反撃側=赤丸
//          ├─ aHitLbl/aHitNum/aHitPct       "命中" + 数値 + "%"
//          ├─ aCritLbl/aCritNum/aCritPct    "必殺" + 数値 + "%"（黄）
//          ├─ aTriUp/aTriDown (poly)        攻撃側の相性矢印（▲緑 / ▼桃・片方だけ可視）
//          ├─ dHitLbl/dHitNum/dHitPct       "反撃" + 数値 + "%"（反撃不可は "反撃 --"）
//          ├─ dCritLbl/dCritNum/dCritPct    "必殺" + 数値 + "%"（黄）
//          └─ dTriUp/dTriDown (poly)        反撃側の相性矢印
mod BattlePanelUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/BattlePanel.ui.json")

    /// fontManifest で登録した name と一致させる（LogUi / WeaponSelectUi と同じ "ui"）。
    def fontName(): String = "ui"

    /// root（可視トグルの対象）と panel / 子ノードの名前パス。
    pub def rootPath(): String  = "BattlePanel"
    def panelPath(): String     = "BattlePanel/panel"
    def childPath(name: String): String = "BattlePanel/panel/${name}"

    def aTriUpPath(): String   = childPath("aTriUp")
    def aTriDownPath(): String = childPath("aTriDown")
    def dTriUpPath(): String   = childPath("dTriUp")
    def dTriDownPath(): String = childPath("dTriDown")

    // ========================================================================
    // 定数 — レイアウト（design px。画面固定なのでそのまま画面 px）
    // ========================================================================

    def winH(): Float64 = 12.0
    /// 命中/反撃/必殺ラベル・% の小さめフォント（薄色）。
    def labelFont(): Float64 = 2.3
    /// 数値（命中値・必殺値）の大きめフォント。
    def numFont(): Float64 = 3.6
    /// 相性三角の半幅 / 半高（ui.json の poly points と整合）。
    def triHalfW(): Float64 = 1.5
    def triHalfH(): Float64 = 1.3
    /// 列のすき間（ラベル↔数値 / 数値↔% / グループ↔グループ / 三角前）。
    def segGap(): Float64 = 0.5
    def pctGap(): Float64 = 0.3
    def groupGap(): Float64 = 2.2
    def triGap(): Float64 = 2.0
    /// ウィンドウ右端の余白。
    def padRight(): Float64 = 3.0
    /// 文字の縦オフセット（design px）。丸中心よりわずかに上へ寄せる。
    def textNudge(): Float64 = 0.25

    /// 各要素の左基準 x / 行中心 y。
    def hitX(): Float64  = 6.0
    def row1CenterY(): Float64 = 3.6
    def row2CenterY(): Float64 = 8.4

    // ========================================================================
    // 毎フレーム System
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。予報を出すのは 2 フェーズ:
    ///   - WeaponSelect : 武器選択中。カーソルが乗っている対象の敵 × カーソル中の武器で予報。
    ///   - PlayerAttack : 赤マスで敵を選択中。カーソル上の敵 × 装備武器で予報。
    /// それ以外のフェーズや対象が居ないときはウィンドウを隠し、足元 HP バー予測も消す。
    pub def frameStep(delta: Duration.Duration): Unit
            \ {GameEngine.Game, TurnPhase.State, SelectedPlayer.State, CursorState.State,
               PlayerData.PartyQuery, EnemyData.RosterQuery, World.Command, World.WorldQuery,
               BattlePanelState.State, UnitHPBarRender.ForecastState, UiWorldState.State, CameraState.State} =
        let phase  = TurnPhase.State.get();
        syncTargetToCursor(phase);
        // 「減る分」の暗⇄明点滅サイクルを進める。累積時間は resource が持つ。
        let elapsed = Duration.add(BattlePanelState.State.get(), delta);
        BattlePanelState.State.put(elapsed);
        let dark = blinkDark(elapsed);
        let ui0  = UiWorldState.State.get();
        match buildForecast(phase) {
            case Some(view) =>
                let atlas = GameEngine.Game.getFontAtlas(fontName());
                let cols  = computeColumns(atlas);
                let aEnd  = cols#groupEndX;   // 攻撃側は必殺まで常に出る
                let dEnd  = if (view#counter) cols#groupEndX else cols#hitNumRight;  // 反撃なしは "反撃 --" まで
                let triCx    = Float64.max(aEnd, dEnd) + triGap() + triHalfW();
                let contentW = triCx + triHalfW() + padRight();
                let shown = ui0
                    |> UiStore.setVisible(rootPath(), true)
                    |> renderRow(rowAPaths(), rowATexts(view), true, cols, row1CenterY(), atlas)
                    |> renderRow(rowDPaths(), rowDTexts(view), view#counter, cols, row2CenterY(), atlas)
                    |> updateTriangle(aTriUpPath(), aTriDownPath(), Some(view#aRel))
                    |> updateTriangle(dTriUpPath(), dTriDownPath(), if (view#counter) Some(view#dRel) else None)
                    |> setTriPos(aTriUpPath(), aTriDownPath(), triCx, row1CenterY())
                    |> setTriPos(dTriUpPath(), dTriDownPath(), triCx, row2CenterY())
                    |> resizeBg(contentW)
                    |> reposition(view, contentW);
                UiWorldState.State.put(shown);
                // 足元 HP バーの「減る分」は ForecastState resource へ put し renderBars が反映する。
                UnitHPBarRender.ForecastState.put(Some(
                    {attackerId = view#attackerId, playerHpPost = view#playerHpPost,
                     defenderId = view#defenderId, enemyHpPost = view#enemyHpPost,
                     dark = dark}))
            case None =>
                UnitHPBarRender.ForecastState.put(None);
                UiWorldState.State.put(UiStore.setVisible(rootPath(), false, ui0))
        }

    /// 「減る分」点滅の暗フレーム判定。周期 `blinkPeriodSec()` 秒の前半を暗（dark=true）、後半を明にする。
    def blinkPeriodSec(): Float64 = 1.0
    def blinkDark(elapsed: Duration.Duration): Bool =
        let s = Duration.toSeconds(elapsed);
        let p = blinkPeriodSec();
        let inCycle = s - p * Float64.floor(s / p);
        inCycle < p / 2.0

    // ========================================================================
    // 行の描画（テキスト + 位置）
    // ========================================================================

    /// 1 行の 6 セル（命中ラベル/数値/% ＋ 必殺ラベル/数値/%）のパス束 / テキスト束。
    /// paths と texts で同じ形なので type alias を共有する。
    pub type alias RowCells = {
        hitLbl = String, hitNum = String, hitPct = String,
        critLbl = String, critNum = String, critPct = String
    }

    def rowAPaths(): RowCells =
        {hitLbl = childPath("aHitLbl"), hitNum = childPath("aHitNum"), hitPct = childPath("aHitPct"),
         critLbl = childPath("aCritLbl"), critNum = childPath("aCritNum"), critPct = childPath("aCritPct")}
    def rowDPaths(): RowCells =
        {hitLbl = childPath("dHitLbl"), hitNum = childPath("dHitNum"), hitPct = childPath("dHitPct"),
         critLbl = childPath("dCritLbl"), critNum = childPath("dCritNum"), critPct = childPath("dCritPct")}

    /// 攻撃側の各セルのテキスト（命中・必殺は常に出る）。
    def rowATexts(view: ForecastView): RowCells =
        {hitLbl = "命中", hitNum = "${view#aHit}", hitPct = "%",
         critLbl = "必殺", critNum = "${view#aCrit}", critPct = "%"}

    /// 反撃側の各セルのテキスト。反撃不可なら数値を "--"、% を空にする（必殺は renderRow が空にする）。
    def rowDTexts(view: ForecastView): RowCells =
        {hitLbl = "反撃",
         hitNum = if (view#counter) "${view#dHit}" else "--",
         hitPct = if (view#counter) "%" else "",
         critLbl = "必殺", critNum = "${view#dCrit}", critPct = "%"}

    /// 1 行を固定列に配置する。ラベル・% は左寄せ、数値は列右端へ右詰め（実測幅ぶん左へずらす）。
    /// 反撃なし（hasCrit=false）の行は命中グループだけ置き、必殺列は空文字で消す。
    def renderRow(paths: RowCells, texts: RowCells, hasCrit: Bool, cols: Columns,
                  rowCenter: Float64, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let base = ui
            |> putLeft(paths#hitLbl, texts#hitLbl, hitX(), rowCenter, labelFont(), atlas)
            |> putRight(paths#hitNum, texts#hitNum, cols#hitNumRight, rowCenter, numFont(), atlas)
            |> putLeft(paths#hitPct, texts#hitPct, cols#hitPctX, rowCenter, labelFont(), atlas);
        if (hasCrit)
            base
                |> putLeft(paths#critLbl, texts#critLbl, cols#critLblX, rowCenter, labelFont(), atlas)
                |> putRight(paths#critNum, texts#critNum, cols#critNumRight, rowCenter, numFont(), atlas)
                |> putLeft(paths#critPct, texts#critPct, cols#critPctX, rowCenter, labelFont(), atlas)
        else
            base
                |> UiStore.setText(paths#critLbl, "")
                |> UiStore.setText(paths#critNum, "")
                |> UiStore.setText(paths#critPct, "")

    /// テキストを左基準 x・行中心 rowCenter（縦中央そろえ）に置く。
    def putLeft(path: String, text: String, leftX: Float64, rowCenter: Float64,
                font: Float64, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let m = measure(text, atlas, font);
        ui
            |> UiStore.setText(path, text)
            |> UiStore.setAbs(path, {x = leftX, y = rowCenter - textNudge() - m#y / 2.0})

    /// 数値を列右端 rightX に右詰め（実測幅ぶん左へずらす）で、行中心へ縦中央そろえに置く。
    def putRight(path: String, text: String, rightX: Float64, rowCenter: Float64,
                 font: Float64, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let m = measure(text, atlas, font);
        ui
            |> UiStore.setText(path, text)
            |> UiStore.setAbs(path, {x = rightX - m#x, y = rowCenter - textNudge() - m#y / 2.0})

    /// テキストの内在サイズ（design px）。engine_world の TextDraw.size（寸法測りの唯一の入口）へ委譲する。
    def measure(text: String, atlas: FontAtlas, font: Float64): Vec2.Vec2 =
        TextDraw.size(text, atlas, font)

    // ========================================================================
    // 固定列の算出
    // ========================================================================

    /// 2 行で縦ラインを揃えるための固定列 x（design px・左基準。数値列は右端）。
    pub type alias Columns = {
        hitNumRight = Float64, hitPctX = Float64,
        critLblX = Float64, critNumRight = Float64, critPctX = Float64,
        groupEndX = Float64
    }

    /// 固定列を算出する。命中/反撃ラベル幅・% 幅は実測、数値列は "000"（3 桁）の実測幅を確保する。
    /// これで命中値/反撃値/必殺値が桁数に依らず同じ縦ラインに揃う。
    def computeColumns(atlas: FontAtlas): Columns =
        let labelW = measure("命中", atlas, labelFont())#x;
        let pctW   = measure("%", atlas, labelFont())#x;
        let num3W  = measure("000", atlas, numFont())#x;
        let hitNumRight  = hitX() + labelW + segGap() + num3W;
        let hitPctX      = hitNumRight + pctGap();
        let critLblX     = hitPctX + pctW + groupGap();
        let critNumRight = critLblX + labelW + segGap() + num3W;
        let critPctX     = critNumRight + pctGap();
        {hitNumRight = hitNumRight, hitPctX = hitPctX,
         critLblX = critLblX, critNumRight = critNumRight, critPctX = critPctX,
         groupEndX = critPctX + pctW}

    // ========================================================================
    // 三角（相性矢印）の可視・位置
    // ========================================================================

    /// 相性 Relation に応じて上/下三角の可視を切り替える。中立 / 反撃なし（None）は両方非表示。
    def updateTriangle(upPath: String, downPath: String, rel: Option[WeaponTriangle.Relation],
                       ui: UiStore.UiWorld): UiStore.UiWorld =
        match rel {
            case Some(WeaponTriangle.Relation.Advantage) =>
                ui |> UiStore.setVisible(upPath, true) |> UiStore.setVisible(downPath, false)
            case Some(WeaponTriangle.Relation.Disadvantage) =>
                ui |> UiStore.setVisible(upPath, false) |> UiStore.setVisible(downPath, true)
            case _ =>
                ui |> UiStore.setVisible(upPath, false) |> UiStore.setVisible(downPath, false)
        }

    /// 上/下三角のレイアウト矩形左上を、中心が (cx, rowCenter) に来るよう置く（poly points は矩形基準）。
    def setTriPos(upPath: String, downPath: String, cx: Float64, rowCenter: Float64,
                  ui: UiStore.UiWorld): UiStore.UiWorld =
        let pos = {x = cx - triHalfW(), y = rowCenter - triHalfH()};
        ui |> UiStore.setAbs(upPath, pos) |> UiStore.setAbs(downPath, pos)

    /// 枠 panel を内容幅に合わせてリサイズする（% のはみ出し防止。高さは ui.json で固定 = winH）。
    def resizeBg(contentW: Float64, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiStore.setWidthPx(panelPath(), contentW, ui)

    // ========================================================================
    // 対象近傍への配置（camera ViewTransform で画面座標へ）
    // ========================================================================

    /// 枠 panel を、対象ユニットの**画面座標**の近傍へ移動する。
    /// 対象 / 攻撃側のワールド座標を camera ViewTransform で画面 px に写し、対象の
    /// 右 → 上 → 下 の順で「画面内に収まり、かつ攻撃側に被らない」最初の位置を選ぶ。
    /// カメラ未登録時（テスト等）は移動しない（前回位置を保つ）。
    def reposition(view: ForecastView, contentW: Float64,
                   ui: UiStore.UiWorld): UiStore.UiWorld \ {GameEngine.Game, CameraState.State} =
        let (vt, vpW, vpH) = viewTransform();
        let st   = Camera.applyToWorldPos(vt, MapSnapshot.cellCenter(view#targetCell));
        let sa   = Camera.applyToWorldPos(vt, MapSnapshot.cellCenter(view#attackerCell));
        let half = MapSnapshot.tileSize() / 2.0 * vt#scale#x;  // 半タイルを画面 px に換算
        let pos  = anchorPos(st, sa, half, contentW, vpW, vpH);
        UiStore.setAbs(panelPath(), pos, ui)

    /// カメラの ViewTransform と viewport(design px) を取る。視点は `CameraState` resource が権威。
    def viewTransform(): (Camera.ViewTransform, Float64, Float64) \ {GameEngine.Game, CameraState.State} =
        let vp = GameEngine.Game.getViewportRect();
        let vt = CameraState.viewTransform({viewportWidth = vp#size#x, viewportHeight = vp#size#y});
        (vt, vp#size#x, vp#size#y)

    /// panel の左上画面座標を決める。対象 `st` の 右 → 上 → 下 を候補にし、
    /// 「画面内に収まり、攻撃側 `sa` に被らない」最初の候補を採用する（左は常設 UI と被るので候補外）。
    /// どれも不適なら右候補を画面内へクランプして使う。
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

    // ========================================================================
    // 対象同期
    // ========================================================================

    /// PlayerAttack 中、攻撃対象をカーソル位置の敵に毎フレーム同期する。
    /// カーソルが敵に乗っていなければ対象をクリアする（予報は出ない）。
    def syncTargetToCursor(phase: TurnPhase.Phase):
            Unit \ {SelectedPlayer.State, CursorState.State, World.Command, World.WorldQuery} =
        if (phase != TurnPhase.Phase.PlayerAttack) ()
        else match SelectedPlayer.State.get()#id {
            case None             => ()
            case Some(attackerId) =>
                match EnemyScene.findIdAt(CursorScene.getGridPos()) {
                    case Some(enemyId) => CombatDriver.setAttackTargetId(attackerId, enemyId)
                    case None          => CombatDriver.clearAttackTargetId(attackerId)
                }
        }

    // ========================================================================
    // 予報の組み立て（純計算 + クエリ）
    // ========================================================================

    /// 予報ビュー。ウィンドウ表示と HP バー予測に必要な値だけを持つ。
    pub type alias ForecastView = {
        attackerCell = {x = Int32, y = Int32}, targetCell = {x = Int32, y = Int32},
        attackerId = Int32, defenderId = Int32,
        aHit = Int32, aCrit = Int32, aRel = WeaponTriangle.Relation,
        counter = Bool, dHit = Int32, dCrit = Int32, dRel = WeaponTriangle.Relation,
        playerHpCur = Int32, playerHpPost = Int32,
        enemyHpCur = Int32, enemyHpPost = Int32
    }

    /// 攻撃中の武器選択リストでアクティブな武器（カーソル上の敵に届く選択武器）。
    /// 敵が居ない / 届く武器が無いなら None（予報は出ない）。
    def selectedAttackWeapon():
            Option[UnitCatalog.WeaponResource]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, World.WorldQuery} =
        forM (
            idx      <- ItemMenuUi.activeAttackWeaponIndex();
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
            w        <- List.nth(idx, player#weapons)
        ) yield w

    /// フェーズに応じて予報ビューを組み立てる。揃わない / 別フェーズなら None。
    def buildForecast(phase: TurnPhase.Phase): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               World.WorldQuery, UiWorldState.State} =
        match phase {
            case TurnPhase.Phase.WeaponSelect => buildWeaponSelectForecast()
            case TurnPhase.Phase.PlayerAttack => buildAttackForecast()
            case _                            => None
        }

    /// PlayerAttack: 選択中味方 / カーソル上の敵 / 装備（活性）武器が揃ったら予報。
    def buildAttackForecast(): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(pid);
            eid    <- player#attackTargetId;
            enemy  <- EnemyData.RosterQuery.get(eid);
            weapon <- selectedAttackWeapon()
        ) yield computeView(pid, player, eid, enemy, weapon)

    /// WeaponSelect: 選択中味方 / カーソル中の武器 / カーソルが乗っている敵が揃ったら予報。
    /// カーソルは `WeaponSelectUi` が「その武器が届く最寄りの敵」へスナップ済み。
    def buildWeaponSelectForecast(): Option[ForecastView]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               World.WorldQuery, UiWorldState.State} =
        forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(pid);
            widx   <- WeaponSelectUi.hoveredWeaponIndex();
            weapon <- List.nth(widx, player#weapons);
            eid    <- EnemyScene.findIdAt(CursorScene.getGridPos());
            enemy  <- EnemyData.RosterQuery.get(eid)
        ) yield computeView(pid, player, eid, enemy, weapon)

    /// 予報ビューを純計算で組み立てる。命中 / 必殺は `Combat.estimate`、すくみは
    /// `WeaponTriangle.relationOpt`。HP は攻撃 / 反撃ダメージから戦闘後 HP を逆算する。
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

    // ========================================================================
    // 確定 / キャンセル（フェーズ遷移。ウィンドウ自体は frameStep が追従）
    // ========================================================================

    /// `PlayerAttack` + Z: 戦闘予報を確認した上で攻撃モーションを開始する。
    /// 遷移先は入力をロックする `PlayerAttackHold`（Z 連打での再起動を防ぐ）。
    pub def confirm():
            Unit \ {World.WorldQuery,
                    GameLogger.GameLogger,
                    TurnPhase.State, SelectedPlayer.State, CursorState.State,
                    PlayerData.PartyQuery, EnemyData.RosterQuery, World.Command} =
        let started = forM (
            attackerId <- SelectedPlayer.State.get()#id;
            player     <- PlayerData.PartyQuery.get(attackerId);
            defenderId <- player#attackTargetId;
            enemy      <- EnemyData.RosterQuery.get(defenderId)
        ) yield {
            let idx = ItemMenuUi.activeAttackWeaponIndex() |> Option.getWithDefault(0);
            PlayerScene.equipWeapon(attackerId, idx);
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("${PlayerScene.displayName(attackerId)}の攻撃");
            CombatDriver.startAttack(Faction.Player, attackerId, defenderId, enemy#gridPos)
        };
        Option.getWithDefault((), started)

    /// `PlayerAttack` + X: 攻撃をやめて行動メニュー (ActionSelect) に戻る。
    /// 待機にはせず、`attackTargetId` をクリアしてカーソルを選択中味方に戻す。
    pub def cancel():
            Unit \ {TurnPhase.State, SelectedPlayer.State, CursorState.State,
                    PlayerData.PartyQuery, World.Command} =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        match SelectedPlayer.State.get()#id {
            case None             => ()
            case Some(attackerId) =>
                CombatDriver.clearAttackTargetId(attackerId);
                CursorScene.snapToPlayer()
        }
}
