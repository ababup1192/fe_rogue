// LevelUpPanelUi — レベルアップ時のステータス変化パネル（World-entity UI 版）。
//
// UI ツリーは LevelUpPanel.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。見た目は
// UiRender が毎フレーム描く。ここは「LevelUpView 中に演出を 1 フレームぶん進め、可視・本文を UiStore へ
// 反映する」毎フレームの配線と、「Z / Enter / X で閉じる」確定のゲームロジックを持つ。
// 演出状態（started / revealed / timer）は LevelUpPanelState resource が権威。
//
// `LevelUpView` フェーズで画面中央に表示される。攻撃解決でレベルアップを検出した味方の
// `pendingLevelUp`（`LevelSystem.Result`）を読み、ヘッダに「{兵種名} Lv {前} -> Lv {後}」、
// 本文に各ステータスを 2 列で並べる。
//
// 演出（時間で進む簡易ステートマシン。音の再生終了は検知できないので、各音の長さぶん待つ）:
//   1. パネルを出す瞬間に bonus.ogg を鳴らす。この間はステータスの「左側」(現在値) だけ見せる。
//   2. bonus.ogg が鳴り終わったら、**上昇したステータスだけ** 右側「-> 新値 +1」を 1 つずつ出す。
//   3. 1 つ出すたびに status_up.mp3 を鳴らし、鳴り終わったら次へ。無ければ終わり。
//   4. `+1` は目立つ色（金色）で色付けする。
// Z / Enter / X で閉じると `confirm` が `pendingLevelUp` を消して通常のターン確定に戻る。
//
// ノード構造（LevelUpPanel.ui.json / layer=5）。本文は列ごとに text ノードを分け、各列の x は
// ラベル幅を実測して frameStep が毎フレーム置く（4 文字ラベルでも数値列に被らない）:
//   LevelUpPanel (none, 画面固定 HUD)
//     ├─ panel (box) — 中央の青枠
//     ├─ header (text) 「{兵種名} Lv 前 -> 後」
//     ├─ bodyLabels / bodyBefore / bodyArrow / bodyAfter / bodyPlus  … 左列（前半ステータス）
//     ├─ bodyLabels2 / bodyBefore2 / bodyArrow2 / bodyAfter2 / bodyPlus2 … 右列（後半ステータス）
//     └─ footer (text) 「Z / Enter で 閉じる」
mod LevelUpPanelUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/LevelUpPanel.ui.json")

    /// root（可視トグルの対象）と各ノードの名前パス。
    pub def rootPath(): String   = "LevelUpPanel"
    def panelPath(): String      = "LevelUpPanel/panel"
    def headerPath(): String     = "LevelUpPanel/header"
    def bodyLabelsPath(): String = "LevelUpPanel/bodyLabels"
    def bodyBeforePath(): String = "LevelUpPanel/bodyBefore"
    def bodyArrowPath(): String  = "LevelUpPanel/bodyArrow"
    def bodyAfterPath(): String  = "LevelUpPanel/bodyAfter"
    def bodyPlusPath(): String   = "LevelUpPanel/bodyPlus"
    def bodyLabels2Path(): String = "LevelUpPanel/bodyLabels2"
    def bodyBefore2Path(): String = "LevelUpPanel/bodyBefore2"
    def bodyArrow2Path(): String  = "LevelUpPanel/bodyArrow2"
    def bodyAfter2Path(): String  = "LevelUpPanel/bodyAfter2"
    def bodyPlus2Path(): String   = "LevelUpPanel/bodyPlus2"
    def footerPath(): String     = "LevelUpPanel/footer"

    // ========================================================================
    // 定数（効果音・演出タイミング・配色）
    // ========================================================================

    /// 効果音名（assets/audio のファイル名から拡張子を除いたもの）。
    def bonusSound(): String    = "bonus"
    def statusUpSound(): String = "status_up"

    /// 各音の長さ。鳴り終わりを検知する API が無いので、音の長さぶん待って「鳴り終わった」とみなす。
    /// （bonus.ogg ≈ 2.04 秒 / status_up.ogg ≈ 0.82 秒）
    def bonusDuration(): Duration.Duration    = Duration.millis(2036)
    def statusUpDuration(): Duration.Duration = Duration.millis(816)

    /// 上昇しなかった行を「さっと（無音で）」出すときの待ち時間。ごく短くして一瞬で送る。
    def quickDuration(): Duration.Duration = Duration.millis(90)

    /// `+1` の色（レベルアップを喜ぶ明るい金色 #FFE94A）。`+1` 列の text を丸ごとこの色にする。
    def plusColor(): Color = {r = 1.0f32, g = 0.914f32, b = 0.29f32}

    /// 本文の通常テキスト色（白）。ラベル・数値・矢印列に使う。
    def whiteColor(): Color = UITheme.white()

    // ========================================================================
    // 定数 — レイアウト（design px。画面固定 HUD なのでそのまま画面 px）
    // ========================================================================

    /// 本文フォント名（fontManifest で登録した "ui"）と本文フォントサイズ。
    def fontName(): String = "ui"
    def bodyFont(): Float64 = 5.0

    /// 本文（列）の縦位置（各列は複数行 text ノード。上端をここに揃える）。
    def bodyTopY(): Float64 = 30.0

    /// 列どうしのすき間。ラベル↔数値・数値↔矢印などの間・左列↔右列の間。
    def labelGap(): Float64 = 1.0
    def colGap(): Float64   = 0.8
    def groupGap(): Float64 = 2.0

    /// 左列の左端 x（ラベル列の開始）。右列の開始は左列幅から算出する。
    def leftOriginX(): Float64 = 14.0

    /// 数値列に確保する幅の基準（2 桁ぶん）。text ノードは行ごとの右揃えを持たないため、
    /// 2 桁ぶんの幅を確保した固定列に置く（2 桁は右端まで満ちる／1 桁は列内で左寄り）。
    /// 桁数で列 x が動かない（＝演出中に列が横滑りしない）ようにするため、内容ではなく "00" で測る。
    def numRef(): String = "00"

    // ========================================================================
    // 毎フレーム System（演出ステートマシン）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。LevelUpView 中は演出を 1 フレームぶん進め、
    /// 可視性と本文を再評価して UiStore へ反映する。表示外はパネルを隠してステートを初期化する
    /// （次のレベルアップで bonus を鳴らし直すため）。
    pub def frameStep(delta: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, TurnPhase.State, LevelUpPanelState.State, UiWorldState.State} =
        let phase = TurnPhase.State.get();
        let ui0 = UiWorldState.State.get();
        let ui1 =
            if (phase != TurnPhase.Phase.LevelUpView) {
                // 表示外: 隠してステートを初期化（次のレベルアップで bonus を鳴らし直すため）。
                LevelUpPanelState.State.put(LevelUpPanelState.initialState());
                applyVisibility(false, ui0)
            } else match pendingResult(scene) {
                case None         => applyVisibility(true, ui0)
                case Some(result) =>
                    // ラベル幅を実測して列 x を組む（4 文字ラベルでも数値列に被らない）。
                    let atlas = GameEngine.Game.getFontAtlas(fontName());
                    stepReveal(delta, result, computeColumns(atlas, result#changes), ui0)
            };
        UiWorldState.State.put(ui1);
        scene

    /// 演出を 1 フレーム進める。bonus → 各ステータス行を上から 1 行ずつ出す。
    /// 上昇した行は status_up を鳴らしてゆっくり、上昇しなかった行は無音で一瞬で送る。
    /// `revealed` は「出し終えた行数」(0 .. List.length(result#changes))。
    def stepReveal(delta: Duration.Duration, result: LevelSystem.Result, cols: Columns, ui: UiStore.UiWorld):
            UiStore.UiWorld \ {GameEngine.Audio, LevelUpPanelState.State} =
        let st   = LevelUpPanelState.State.get();
        let rows = List.length(result#changes);
        let nextState =
            if (not st#started) {
                // 表示の瞬間: bonus.ogg を鳴らし、鳴り終わるまで本文の数値は出さない。
                AudioStreamPlayer.play(bonusSound());
                {started = true, revealed = 0, timer = bonusDuration()}
            } else {
                let remaining = Duration.subClampedToZero(st#timer, delta);
                if (not Duration.isPositive(remaining) and st#revealed < rows)
                    // 直前の待ちが明けた & まだ出していない行がある → 次のステップを出す。
                    revealNextStep(result, st#revealed)
                else
                    {started = true, revealed = st#revealed, timer = remaining}
            };
        LevelUpPanelState.State.put(nextState);
        ui |> applyVisibility(true) |> applyContent(result, nextState#revealed, cols)

    /// 次のステップを出す。上昇した行は 1 行だけ status_up を鳴らしてゆっくり、
    /// 据え置きの行は**連続する分をまとめて**無音で一気に出し、待ちは（各行ではなく）まとめて 1 回ぶん。
    def revealNextStep(result: LevelSystem.Result, revealed: Int32):
            LevelUpPanelState.PanelState \ GameEngine.Audio =
        if (rowGained(result, revealed)) {
            AudioStreamPlayer.play(statusUpSound());
            {started = true, revealed = revealed + 1, timer = statusUpDuration()}
        } else
            // 据え置き行は次の上昇行（または末尾）まで一気に revealed を進める → まとめて 1 回の待ち。
            {started = true, revealed = nextGainedIndex(result, revealed), timer = quickDuration()}

    /// `index` 以降で最初に「上昇した行」のインデックス。無ければ総行数（= まとめて末尾まで出す）。
    def nextGainedIndex(result: LevelSystem.Result, index: Int32): Int32 =
        if (index >= List.length(result#changes)) index
        else if (rowGained(result, index)) index
        else nextGainedIndex(result, index + 1)

    /// `index` 行目のステータスが上昇したか。範囲外は false。
    def rowGained(result: LevelSystem.Result, index: Int32): Bool =
        List.nth(index, result#changes) |> Option.map(change -> change#gained) |> Option.getWithDefault(false)

    // ========================================================================
    // 可視性・内容
    // ========================================================================

    /// パネルと各ラベル/列の visible をまとめて切り替える。
    def applyVisibility(visible: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        List.foldLeft((acc, path) -> UiStore.setVisible(path, visible, acc), ui,
            rootPath() :: panelPath() :: headerPath()
            :: bodyLabelsPath() :: bodyBeforePath() :: bodyArrowPath() :: bodyAfterPath() :: bodyPlusPath()
            :: bodyLabels2Path() :: bodyBefore2Path() :: bodyArrow2Path() :: bodyAfter2Path() :: bodyPlus2Path()
            :: footerPath() :: Nil)

    /// ヘッダと本文の各列を「出し終えた行数」`revealed` に合わせて書き込む。
    /// ラベル列は固定。現在値は出した行だけ、矢印/新値/+1 は出した行のうち上昇した行だけ出す。
    /// 前半ステータスを左列、後半を右列に割る（reveal 判定は global index）。
    /// 各列の x は `cols`（実測ラベル幅から算出）に置く。ラベル列の右隣に数値列を確保するので、
    /// 4 文字ラベルでも数値・矢印に被らない。
    def applyContent(result: LevelSystem.Result, revealed: Int32, cols: Columns, ui: UiStore.UiWorld): UiStore.UiWorld =
        let changes = result#changes;
        let half    = (List.length(changes) + 1) / 2;
        let left    = List.take(half, changes);
        let right   = List.drop(half, changes);
        ui
            |> UiStore.setText(headerPath(), formatHeader(result))
            |> setColumn(bodyLabelsPath(), cols#leftLabelX,  whiteColor(), colLabelsOf(left))
            |> setColumn(bodyBeforePath(), cols#leftBeforeX, whiteColor(), colBeforeOf(left, 0, revealed))
            |> setColumn(bodyArrowPath(),  cols#leftArrowX,  whiteColor(), colArrowOf(left, 0, revealed))
            |> setColumn(bodyAfterPath(),  cols#leftAfterX,  whiteColor(), colAfterOf(left, 0, revealed))
            |> setColumn(bodyPlusPath(),   cols#leftPlusX,   plusColor(),  colPlusOf(left, 0, revealed))
            |> setColumn(bodyLabels2Path(), cols#rightLabelX,  whiteColor(), colLabelsOf(right))
            |> setColumn(bodyBefore2Path(), cols#rightBeforeX, whiteColor(), colBeforeOf(right, half, revealed))
            |> setColumn(bodyArrow2Path(),  cols#rightArrowX,  whiteColor(), colArrowOf(right, half, revealed))
            |> setColumn(bodyAfter2Path(),  cols#rightAfterX,  whiteColor(), colAfterOf(right, half, revealed))
            |> setColumn(bodyPlus2Path(),   cols#rightPlusX,   plusColor(),  colPlusOf(right, half, revealed))

    /// 列 text にテキスト・色・位置をまとめて設定する。y は全列共通の本文上端。
    def setColumn(path: String, x: Float64, color: Color, text: String, ui: UiStore.UiWorld): UiStore.UiWorld =
        ui
            |> UiStore.setText(path, text)
            |> UiStore.setTextTint(path, color)
            |> UiStore.setAbs(path, {x = x, y = bodyTopY()})

    // ========================================================================
    // 列 x の算出（実測ラベル幅ベース）
    // ========================================================================

    /// 左列・右列それぞれ 5 サブ列（ラベル / 現在値 / 矢印 / 新値 / +1）の左端 x（design px）。
    /// World-entity UI の text は行ごとの右揃えを持たないため、数値列は 2 桁ぶんの幅を確保した固定列に
    /// 置く（putRight 方式の複数行版。2 桁は列右端まで満ち、1 桁は列内で左寄り）。
    pub type alias Columns = {
        leftLabelX = Float64, leftBeforeX = Float64, leftArrowX = Float64,
        leftAfterX = Float64, leftPlusX = Float64,
        rightLabelX = Float64, rightBeforeX = Float64, rightArrowX = Float64,
        rightAfterX = Float64, rightPlusX = Float64
    }

    /// 1 グループ（片側の列）の x とグループ右端。ラベル幅の右隣に数値列（2 桁ぶん）を確保する。
    pub type alias Group = {
        labelX = Float64, beforeX = Float64, arrowX = Float64,
        afterX = Float64, plusX = Float64, endX = Float64
    }

    /// 列 x を組む。ラベル幅は実測の最大値（全行常に表示なので演出中に変わらない）、数値列は "00"、
    /// 矢印列は "->"、+1 列は "+1" の実測幅を確保する。左列を左端から積み、右列は左列の右端 + すき間から。
    def computeColumns(atlas: FontAtlas, changes: List[LevelSystem.StatChange]): Columns =
        let widths = {label = maxLabelWidth(atlas, changes), num = measure(numRef(), atlas),
                      arrow = measure("->", atlas), plus = measure("+1", atlas)};
        let leftG  = groupFrom(leftOriginX(), widths);
        let rightG = groupFrom(leftG#endX + groupGap(), widths);
        {leftLabelX = leftG#labelX, leftBeforeX = leftG#beforeX, leftArrowX = leftG#arrowX,
         leftAfterX = leftG#afterX, leftPlusX = leftG#plusX,
         rightLabelX = rightG#labelX, rightBeforeX = rightG#beforeX, rightArrowX = rightG#arrowX,
         rightAfterX = rightG#afterX, rightPlusX = rightG#plusX}

    /// `originX` から 1 グループの各列 x を積む。数値列（before/after）は 2 桁ぶん（num）を確保する。
    def groupFrom(originX: Float64,
                  widths: {label = Float64, num = Float64, arrow = Float64, plus = Float64}): Group =
        let labelX  = originX;
        let beforeX = labelX + widths#label + labelGap();
        let arrowX  = beforeX + widths#num + colGap();
        let afterX  = arrowX + widths#arrow + colGap();
        let plusX   = afterX + widths#num + colGap();
        {labelX = labelX, beforeX = beforeX, arrowX = arrowX, afterX = afterX, plusX = plusX,
         endX = plusX + widths#plus}

    /// 全ラベルの実測幅の最大値（left/right 両列で共通の列幅にするため）。空リストは 0。
    def maxLabelWidth(atlas: FontAtlas, changes: List[LevelSystem.StatChange]): Float64 =
        changes |> List.foldLeft((acc, change) -> Float64.max(acc, measure(change#label, atlas)), 0.0)

    /// テキストの内在幅（design px）。engine の Label2D.measure を本文フォントで再利用する。
    def measure(text: String, atlas: FontAtlas): Float64 =
        Label2D.measure(Label2D.make(text, atlas, bodyFont()))#x

    /// レベルアップ保留中の味方の結果を 1 つ拾う（味方ターンなので同時に複数は出ない）。
    def pendingResult(scene: Scene[NodeTag]): Option[LevelSystem.Result] =
        PlayerScene.getAll(scene)
            |> List.filterMap(d -> d#pendingLevelUp)
            |> List.head

    /// `List.length` の薄いラッパー。`confirm` での閾値比較の意図を明示する。
    def totalRows(result: LevelSystem.Result): Int32 =
        List.length(result#changes)

    // ========================================================================
    // 入力（確定）
    // ========================================================================

    /// `LevelUpView` + Z/Enter/X の確定。2 段階にする:
    ///   1 回目（まだ全行を出し切っていない）→ 残りを**一気に全部出して止める**（閉じない）。
    ///   2 回目（既に全て出ている）→ 今表示中の味方のパネルを閉じる。まだレベルアップ待ちの
    ///      味方が居れば演出を初期化して次の味方を表示し、居なければ復帰する。
    pub def confirm(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {RangeOverlayState.State,
                              GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State, CursorState.State, World.Command, World.WorldQuery,
                              LevelUpPanelState.State} =
        let st    = LevelUpPanelState.State.get();
        let total = pendingResult(scene) |> Option.map(totalRows) |> Option.getWithDefault(0);
        if (st#revealed < total) {
            // まだ出し切っていない → 全行を即座に表示して止める（閉じない）。
            // revealed を total に飛ばすと frameStep が次フレームで全行・全 `+1` を描く。
            LevelUpPanelState.State.put({revealed = total, started = true, timer = st#timer});
            scene
        } else match firstPendingId(scene) {
            // 全行出し切り後の閉じ＝ターン復帰は turn 層（`TurnFlow.resumeAfterLevelUpView`）が担う。
            case None     => TurnFlow.resumeAfterLevelUpView(scene)
            case Some(id) =>
                // 今表示中（先頭）の味方の保留を 1 件だけ消す。
                let cleared = PlayerScene.mapPlayer(id, dd -> {pendingLevelUp = None | dd}, scene);
                if (PlayerScene.anyPendingLevelUp(cleared)) {
                    // まだ他に居る → 演出 state を初期化し、次の味方を最初（bonus）から表示。
                    LevelUpPanelState.State.put(LevelUpPanelState.initialState());
                    PhaseTransitions.enterLevelUpView(cleared)
                } else
                    TurnFlow.resumeAfterLevelUpView(cleared)
        }

    /// レベルアップ表示待ちの味方のうち先頭（= いま表示している味方）の id。
    /// `confirm` は先頭 id の `pendingLevelUp` だけを 1 件消すので、
    /// 「先頭 = 今表示中」という不変条件が保たれる。
    def firstPendingId(scene: Scene[NodeTag]): Option[Int32] =
        PlayerScene.getAll(scene)
            |> List.filter(d -> Option.nonEmpty(d#pendingLevelUp))
            |> List.map(d -> d#id)
            |> List.head

    // ========================================================================
    // テキスト整形（純関数・テスト対象）
    // ========================================================================

    /// ヘッダ行「{兵種名}   Lv {前} -> Lv {後}」。
    pub def formatHeader(result: LevelSystem.Result): String =
        "${result#unitName}   Lv ${result#fromLevel} -> Lv ${result#toLevel}"

    /// ラベル列。サブリスト（左列 or 右列）のステータス名を縦に並べる（常に全行表示）。
    pub def colLabelsOf(changes: List[LevelSystem.StatChange]): String =
        changes |> List.map(change -> change#label) |> joinLines

    /// 現在値列。global index（offset + i）< revealed の行にだけ「前の値」を出す。
    pub def colBeforeOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed) "${change#before}" else "")
            |> joinLines

    /// 矢印列。出した行のうち上昇した行だけ "->"。
    pub def colArrowOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "->" else "")
            |> joinLines

    /// 新値列。出した行のうち上昇した行だけ「後の値」。
    pub def colAfterOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "${change#after}" else "")
            |> joinLines

    /// `+1` 列（金色）。出した行のうち上昇した行だけ "+1"。
    pub def colPlusOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "+1" else "")
            |> joinLines

    /// 末尾改行なしで各行を結合。空リストのとき `""` を返す。
    def joinLines(lines: List[String]): String =
        match lines {
            case Nil          => ""
            case head :: rest => List.foldLeft((acc, line) -> "${acc}\n${line}", head, rest)
        }
}
