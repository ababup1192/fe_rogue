/// LevelUpPanelScene — レベルアップ時のステータス変化パネル
///
/// `LevelUpView` フェーズで画面中央に表示される。攻撃解決でレベルアップを検出した味方の
/// `pendingLevelUp`（`LevelSystem.Result`）を読み、ヘッダに「{兵種名} Lv {前} -> Lv {後}」、
/// 本文に各ステータスを並べる。
///
/// 演出（時間で進む簡易ステートマシン。音の再生終了は検知できないので、各音の長さぶん待つ）:
///   1. パネルを出す瞬間に bonus.ogg を鳴らす。この間はステータスの「左側」(現在値) だけ見せる。
///   2. bonus.ogg が鳴り終わったら、**上昇したステータスだけ** 右側「-> 新値 +1」を 1 つずつ出す。
///   3. 1 つ出すたびに status_up.mp3 を鳴らし、鳴り終わったら次へ。無ければ終わり。
///   4. `+1` は丸括弧を外し、目立つ色（金色）で色付けする。
/// Z / Enter / X で閉じると `confirm` が `pendingLevelUp` を消して通常のターン確定に戻る。
///
/// ノード構造（visible のとき）。本文は列ごとに Label2D を分け、数値列を右揃えにして
/// フォントのスペース幅・全角幅に依存せず桁と `+1` がそろうようにしている:
///   LevelUpPanel (CanvasLayer, layer=5)
///     ├─ panel      (Panel, NodeTag.LevelUpPanel(PanelState))
///     ├─ header     (Label2D, NoTag) — 「{兵種名} Lv 前 -> 後」
///     ├─ bodyLabels (Label2D, 左揃え) — ステータス名 9 行
///     ├─ bodyBefore (Label2D, 右揃え) — 現在値 9 行
///     ├─ bodyArrow  (Label2D, 左揃え) — "->"（上昇を出した行だけ）
///     ├─ bodyAfter  (Label2D, 右揃え) — 新値（同上）
///     ├─ bodyPlus   (Label2D, 左揃え・金色) — "+1"（同上）
///     └─ footer     (Label2D, NoTag)
mod LevelUpPanelScene {

    use JsonCompat.PathTag.Root

    // ────────────────────────────────────────────────────────
    // (A) 演出ステート
    // ────────────────────────────────────────────────────────

    /// パネル表示中の演出の進行状態。Panel ノードのタグに載せてフレーム間で持ち越す。
    ///   - `started`  : bonus.ogg を鳴らして演出を開始済みか（LevelUpView 突入の最初のフレームで true）。
    ///   - `revealed` : 右側「-> 新値 +1」を出し終えた「上昇ステータス」の数。
    ///   - `timer`    : 次のアクション（最初の reveal / 次の reveal）までの残り待ち時間。フレームごとに delta だけ減算し 0 になったら次の演出へ進む。
    pub type alias PanelState = {
        started  = Bool,
        revealed = Int32,
        timer    = Duration.Duration
    }

    /// 演出開始前の初期状態。LevelUpView の外では常にこれに戻し、次のレベルアップで鳴らし直す。
    def initialState(): PanelState =
        {started = false, revealed = 0, timer = Duration.zero()}

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/LevelUpPanelScene.scene.json")

    /// fontManifest で登録した name（BattlePanel / LogScene と同じ "ui"）。
    def fontName(): String = "ui"

    /// 効果音名（assets/audio のファイル名から拡張子を除いたもの）。
    def bonusSound(): String    = "bonus"
    def statusUpSound(): String = "status_up"

    /// 各音の長さ。鳴り終わりを検知する API が無いので、音の長さぶん待って「鳴り終わった」とみなす。
    /// （bonus.ogg ≈ 2.04 秒 / status_up.ogg ≈ 0.82 秒）
    def bonusDuration(): Duration.Duration    = Duration.millis(2036)
    def statusUpDuration(): Duration.Duration = Duration.millis(816)

    /// 上昇しなかった行を「さっと（無音で）」出すときの待ち時間。ごく短くして一瞬で送る。
    def quickDuration(): Duration.Duration = Duration.millis(90)

    /// `+1` の色（レベルアップを喜ぶ明るい金色 #FFE94A）。`+1` 列の Label2D を丸ごとこの色にする。
    def plusColor(): Color = {r = 1.0f32, g = 0.914f32, b = 0.29f32}

    /// 本文の通常テキスト色（白）。ラベル・数値・矢印列に使う。
    def whiteColor(): Color = UITheme.white()

    def rootName(): String       = "LevelUpPanel"
    def panelName(): String      = "panel"
    def headerName(): String     = "header"
    // 本文は列ごとに別ノードに分ける。各列を Label2D の右揃え（数値）/左揃え（ラベル・矢印・+1）で
    // 固定 x に置くことで、フォントのスペース幅や全角幅に依存せず桁と `+1` がそろう。
    def bodyLabelsName(): String = "bodyLabels"
    def bodyBeforeName(): String = "bodyBefore"
    def bodyArrowName(): String  = "bodyArrow"
    def bodyAfterName(): String  = "bodyAfter"
    def bodyPlusName(): String   = "bodyPlus"
    def bodyLabels2Name(): String = "bodyLabels2"
    def bodyBefore2Name(): String = "bodyBefore2"
    def bodyArrow2Name(): String  = "bodyArrow2"
    def bodyAfter2Name(): String  = "bodyAfter2"
    def bodyPlus2Name(): String   = "bodyPlus2"
    def footerName(): String     = "footer"

    def panelPath(): NodePath      = rootName() :: panelName()      :: Nil
    def headerPath(): NodePath     = rootName() :: headerName()     :: Nil
    def bodyLabelsPath(): NodePath = rootName() :: bodyLabelsName() :: Nil
    def bodyBeforePath(): NodePath = rootName() :: bodyBeforeName() :: Nil
    def bodyArrowPath(): NodePath  = rootName() :: bodyArrowName()  :: Nil
    def bodyAfterPath(): NodePath  = rootName() :: bodyAfterName()  :: Nil
    def bodyPlusPath(): NodePath   = rootName() :: bodyPlusName()   :: Nil
    def bodyLabels2Path(): NodePath = rootName() :: bodyLabels2Name() :: Nil
    def bodyBefore2Path(): NodePath = rootName() :: bodyBefore2Name() :: Nil
    def bodyArrow2Path(): NodePath  = rootName() :: bodyArrow2Name()  :: Nil
    def bodyAfter2Path(): NodePath  = rootName() :: bodyAfter2Name()  :: Nil
    def bodyPlus2Path(): NodePath   = rootName() :: bodyPlus2Name()   :: Nil
    def footerPath(): NodePath     = rootName() :: footerName()     :: Nil

    /// SceneLoader から呼ばれる tag 文字列 → NodeTag の変換。
    /// 既知の値（"NoTag" / "LevelUpPanel"）以外は `JsonError` を返す（SceneLoader がロードを中断する）。
    /// "LevelUpPanel" は演出開始前の `initialState` を付与して返す。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                   => Ok(NodeTag.NoTag)
            case Some("NoTag")          => Ok(NodeTag.NoTag)
            case Some("LevelUpPanel")   => Ok(NodeTag.LevelUpPanel(initialState()))
            case Some(unknown)          =>
                Err(JsonCompat.jsonError(Root, Set#{"LevelUpPanelScene tag (got: ${unknown})"}))
        }

    /// scene にパネルを追加する。`GameLifecycle.buildPlayingScene` の構築パイプで 1 回呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    // ────────────────────────────────────────────────────────
    // (C) 毎フレーム処理（演出ステートマシン）
    // ────────────────────────────────────────────────────────

    /// LevelUpPanel ノード（Panel）に対して毎フレーム dispatch される。
    /// Scene は immutable に扱う設計のため演出ステートを Scene 外に持てない。
    /// Panel ノードのタグ（`NodeTag.LevelUpPanel(PanelState)`）を状態置き場にすることで、
    /// フレーム間の演出進行をイミュータブルな Scene 更新として表現している。
    /// LevelUpView 中は演出を 1 フレームぶん進め、可視性と本文を再評価する。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ {TurnPhase.State, GameEngine.Audio} =
        let phase = TurnPhase.State.get();
        let next =
            if (phase != TurnPhase.Phase.LevelUpView)
                // 表示外: 隠してステートを初期化（次のレベルアップで bonus を鳴らし直すため）。
                scene |> applyVisibility(false) |> writeState(initialState())
            else match pendingResult(scene) {
                case None         => applyVisibility(true, scene)
                case Some(result) => stepReveal(delta, result, scene)
            };
        match Scene.getEngineNode(panelPath(), next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 演出を 1 フレーム進める。bonus → 各ステータス行を上から 1 行ずつ出す。
    /// 上昇した行は status_up を鳴らしてゆっくり、上昇しなかった行は無音で一瞬で送る。
    /// `revealed` は「出し終えた行数」(0 .. List.length(result#changes)、例: 9 ステータスなら 0..9)。
    def stepReveal(delta: Duration.Duration, result: LevelSystem.Result,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        let st   = currentState(scene);
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
        scene
            |> applyVisibility(true)
            |> applyContent(result, nextState#revealed)
            |> writeState(nextState)

    /// 次のステップを出す。上昇した行は 1 行だけ status_up を鳴らしてゆっくり、
    /// 据え置きの行は**連続する分をまとめて**無音で一気に出し、待ちは（各行ではなく）まとめて 1 回ぶん。
    def revealNextStep(result: LevelSystem.Result, revealed: Int32):
            PanelState \ GameEngine.Audio =
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

    // ────────────────────────────────────────────────────────
    // (D) 可視性・内容・ステート読み書き
    // ────────────────────────────────────────────────────────

    /// Panel と各ラベル/列の visible をまとめて切り替える（Label2D は親の可視性を見ないので個別に）。
    def applyVisibility(visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(headerPath(),     CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyLabelsPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyBeforePath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyArrowPath(),  CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyAfterPath(),  CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyPlusPath(),   CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyLabels2Path(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyBefore2Path(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyArrow2Path(),  CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyAfter2Path(),  CanvasItem.setVisible(visible))
            |> Label2D.mapAt(bodyPlus2Path(),   CanvasItem.setVisible(visible))
            |> Label2D.mapAt(footerPath(),     CanvasItem.setVisible(visible))

    /// ヘッダと本文の各列を「出し終えた行数」`revealed` に合わせて書き込む。
    /// ラベル列は固定。現在値は出した行だけ、矢印/新値/+1 は出した行のうち上昇した行だけ出す。
    /// 数値は列ごとに右揃え（Label2D の Right アライメント）なので桁・`+1` がそろう。
    def applyContent(result: LevelSystem.Result, revealed: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        // 2 列レイアウト: 前半 4 ステータスを左列、後半 4 を右列に割る。
        // reveal の判定は global index（左 0..half-1 / 右 half..）で行う。
        let changes = result#changes;
        let half    = (List.length(changes) + 1) / 2;
        let left    = List.take(half, changes);
        let right   = List.drop(half, changes);
        scene
            |> Label2D.mapAt(headerPath(), Label2D.setText(formatHeader(result)))
            |> setColumn(bodyLabelsPath(), HorizontalAlignment.Left,  whiteColor(), colLabelsOf(left))
            |> setColumn(bodyBeforePath(), HorizontalAlignment.Right, whiteColor(), colBeforeOf(left, 0, revealed))
            |> setColumn(bodyArrowPath(),  HorizontalAlignment.Left,  whiteColor(), colArrowOf(left, 0, revealed))
            |> setColumn(bodyAfterPath(),  HorizontalAlignment.Right, whiteColor(), colAfterOf(left, 0, revealed))
            |> setColumn(bodyPlusPath(),   HorizontalAlignment.Left,  plusColor(),  colPlusOf(left, 0, revealed))
            |> setColumn(bodyLabels2Path(), HorizontalAlignment.Left,  whiteColor(), colLabelsOf(right))
            |> setColumn(bodyBefore2Path(), HorizontalAlignment.Right, whiteColor(), colBeforeOf(right, half, revealed))
            |> setColumn(bodyArrow2Path(),  HorizontalAlignment.Left,  whiteColor(), colArrowOf(right, half, revealed))
            |> setColumn(bodyAfter2Path(),  HorizontalAlignment.Right, whiteColor(), colAfterOf(right, half, revealed))
            |> setColumn(bodyPlus2Path(),   HorizontalAlignment.Left,  plusColor(),  colPlusOf(right, half, revealed))

    /// 列 Label2D にテキスト・揃え・色をまとめて設定する。
    def setColumn(path: NodePath, align: HorizontalAlignment, color: Color,
                   text: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Label2D.mapAt(path, label ->
            label
                |> Label2D.setText(text)
                |> Label2D.setHorizontalAlignment(align)
                |> CanvasItem.setModulate(color), scene)

    /// Panel ノードのタグから現在の演出ステートを読む。未設定なら初期状態。
    def currentState(scene: Scene[NodeTag]): PanelState =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.LevelUpPanel(st)) => st
            case _                              => initialState()
        }

    /// 演出ステートを Panel ノードのタグに書き戻す。
    def writeState(st: PanelState, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(panelPath(), n -> match n {
            case EngineNode.PanelWithState(panel, NodeTag.LevelUpPanel(_)) =>
                EngineNode.PanelWithState(panel, NodeTag.LevelUpPanel(st))
            case other => other
        }, scene)

    /// レベルアップ保留中の味方の結果を 1 つ拾う（味方ターンなので同時に複数は出ない）。
    def pendingResult(scene: Scene[NodeTag]): Option[LevelSystem.Result] =
        PlayerScene.getAll(scene)
            |> List.filterMap(d -> d#pendingLevelUp)
            |> List.head

    /// `List.length` の薄いラッパー。名前を付けることで `confirm` での閾値比較の意図を明示する。
    /// `confirm` が「全行出し切ったか（`st#revealed < total`）」を判定するときに使う。
    def totalRows(result: LevelSystem.Result): Int32 =
        List.length(result#changes)

    // ────────────────────────────────────────────────────────
    // (E) 入力
    // ────────────────────────────────────────────────────────

    /// `LevelUpView` + Z/Enter/X の確定。2 段階にする:
    ///   1 回目（まだ全行を出し切っていない）→ 残りを**一気に全部出して止める**（閉じない）。
    ///   2 回目（既に全て出ている）→ 今表示中の味方のパネルを閉じる。まだレベルアップ待ちの
    ///      味方が居れば（敵ターン中の複数反撃など）演出を初期化して次の味方を表示し、居なければ復帰する。
    pub def confirm(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State} =
        let st    = currentState(scene);
        let total = pendingResult(scene) |> Option.map(totalRows) |> Option.getWithDefault(0);
        if (st#revealed < total)
            // まだ出し切っていない → 全行を即座に表示して止める（閉じない）。
            // revealed を total に飛ばすと process が次フレームで全行・全 `+1` を描く。
            writeState({revealed = total, started = true, timer = st#timer}, scene)
        else match firstPendingId(scene) {
            case None     => resume(scene)
            case Some(id) =>
                // 今表示中（先頭）の味方の保留を 1 件だけ消す。
                let cleared = PlayerScene.mapPlayer(id, dd -> {pendingLevelUp = None | dd}, scene);
                if (PlayerScene.anyPendingLevelUp(cleared))
                    // まだ他に居る → 演出 state を初期化し、次の味方を最初（bonus）から表示。
                    PhaseTransitions.enterLevelUpView(writeState(initialState(), cleared))
                else
                    resume(cleared)
        }

    /// パネルを閉じ切ったあとの復帰先を文脈で分ける:
    ///   - 自分の攻撃中（SelectedPlayer あり）→ `commitWaitedAndAdvance` でターンを確定・続行。
    ///   - 敵ターン中の反撃由来（SelectedPlayer なし）→ 敵ターンに戻って続行（キューはそのまま）。
    def resume(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State} =
        match SelectedPlayer.State.get()#id {
            case Some(_) => TurnFlow.commitWaitedAndAdvance(scene)
            case None    => PhaseTransitions.enterEnemyTurn(scene)
        }

    /// レベルアップ表示待ちの味方のうち先頭（= いま表示している味方）の id。
    /// `confirm` は先頭 id の `pendingLevelUp` だけを 1 件消すので、
    /// 「先頭 = 今表示中」という不変条件が保たれる。
    def firstPendingId(scene: Scene[NodeTag]): Option[Int32] =
        PlayerScene.getAll(scene)
            |> List.filter(d -> Option.nonEmpty(d#pendingLevelUp))
            |> List.map(d -> d#id)
            |> List.head

    // ────────────────────────────────────────────────────────
    // (F) テキスト整形
    // ────────────────────────────────────────────────────────

    /// ヘッダ行「{兵種名}   Lv {前} -> Lv {後}」。
    def formatHeader(result: LevelSystem.Result): String =
        "${result#unitName}   Lv ${result#fromLevel} -> Lv ${result#toLevel}"

    /// ラベル列（左揃え）。サブリスト（左列 or 右列）のステータス名を縦に並べる（常に全行表示）。
    def colLabelsOf(changes: List[LevelSystem.StatChange]): String =
        changes |> List.map(change -> change#label) |> joinLines

    /// 現在値列（右揃え）。global index（offset + i）< revealed の行にだけ「前の値」を出す。
    def colBeforeOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed) "${change#before}" else "")
            |> joinLines

    /// 矢印列（左揃え）。出した行のうち上昇した行だけ "->"。
    def colArrowOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "->" else "")
            |> joinLines

    /// 新値列（右揃え）。出した行のうち上昇した行だけ「後の値」。
    def colAfterOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "${change#after}" else "")
            |> joinLines

    /// `+1` 列（左揃え・金色）。出した行のうち上昇した行だけ "+1"。
    def colPlusOf(changes: List[LevelSystem.StatChange], offset: Int32, revealed: Int32): String =
        changes
            |> List.mapWithIndex(i -> change -> if (offset + i < revealed and change#gained) "+1" else "")
            |> joinLines

    /// 末尾改行なしで各行を結合。Label2D.setText に渡す前提で末尾 \n を付けない。
    /// 空リストのとき `""` を返し、Label2D の setText に渡すと空欄（行なし）として安全に扱われる。
    def joinLines(lines: List[String]): String =
        match lines {
            case Nil          => ""
            case head :: rest => List.foldLeft((acc, line) -> "${acc}\n${line}", head, rest)
        }

}
