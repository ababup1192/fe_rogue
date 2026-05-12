/// Dialogue 層の effect・型・純粋遷移を集約するモジュール。
///
/// 提供するもの:
///
///   - 2 つの effect: `Session` / `DialogueView`
///   - view 用の整形済み型: `PresentedLine` / `PresentedChoice`
///   - 1 フレーム単位で受け渡す view イベント: `ViewEvent`
///   - 対話 UI の論理状態: `UIState` と、その純粋遷移（`applyEvent` /
///     `moveCursor` / `emptyState`）と表示用整形（`formatBody`）
///   - ジャンルごとのリズム・寸法をまとめた `DialogueProfile` と既製 profile
///     （`jrpgProfile` / `visualNovelProfile`）
///   - facade `withDialog`（Runner / SceneView を 1 行で適用）
///
/// 描画やノード木の知識は持たないので、別の Scene 実装に差し替えても再利用できる。
/// JRPG / VN / その他の表現スタイルの違いは `DialogueProfile` の値で吸収する。
mod Dialogue {

    // ════════════════════════════════════════════════════════════════════════
    // データ型
    // ════════════════════════════════════════════════════════════════════════

    /// Yarn の行 ID（`line:foo123` のような StringTable のキー）。
    pub type alias LineId = String

    /// 1 行の本文（置換マーカー解決済み。表示にそのまま乗せる）。
    pub type alias LineText = String

    /// 話者名（半角コロンの左側から抽出した値）。
    pub type alias SpeakerName = String

    /// 選択肢として表示するラベル文字列。
    pub type alias ChoiceLabel = String

    /// Yarn の `<<command ...>>` から得られる生コマンド行。
    pub type alias CommandText = String

    /// 表示用に整形された 1 行。`text` は置換マーカー解決済み。
    /// `speaker` は表記から取り出した話者名。Runner / Scene が `extractSpeaker` を
    /// 使って埋める想定だが、別の表記法を使うシナリオでは独自に詰めて良い。
    pub type alias PresentedLine = {
        lineId  = LineId,
        text    = LineText,
        speaker = Option[SpeakerName]
    }

    /// 表示用に整形された 1 つの選択肢。
    /// `index` は VM の `selectChoice` に渡す番号と一致する。
    pub type alias PresentedChoice = {
        index     = Int32,
        text      = ChoiceLabel,
        available = Bool
    }

    /// `DialogueView` の各操作を 1 件のイベントとして表したもの。
    /// `SceneView` handler が `MutDeque` に積み、`Inbox.takeAll` 経由で
    /// 1 フレーム分まとめて取り出される。`StubView` も同じ enum をテストログとして使う。
    pub enum ViewEvent with Eq, ToString {
        /// `presentLine` 受信。本文と、表記から取り出した話者名（無ければ `None`）。
        case Line(LineText, Option[SpeakerName])
        /// `presentChoices` 受信。表示すべき選択肢のラベル列。
        case Choices(List[ChoiceLabel])
        /// `dismissLine` 受信。表示中の行を消す。
        case Dismiss
        /// `runCommand` 受信。実コマンド文字列。
        case Command(CommandText)
        /// `dialogueComplete` 受信。対話完了。
        case Complete
    }

    /// 古い行のスクロール / フェード演出 + 完了時に流す保留イベントのペア。
    /// `progress` は 0.0 → 1.0 で進む。`oldLines` は演出開始時のパネルに
    /// 表示されていた行列。`pendingEvent` は演出が終わってから `applyEventInner`
    /// で実反映される 1 件のイベント（= 演出中は次の文章を出さないというゲート）。
    /// `transition` が `None` のときはこのペアごと存在しないので、Scene 側は
    /// `transitionView(state)` から `oldLines` と `progress` を見ればよい。
    pub type alias Transition = {
        oldLines     = List[LineText],
        progress     = Float64,
        pendingEvent = ViewEvent
    }

    /// ジャンルごとの「対話リズム・寸法」をまとめた値。
    /// `UIState` が 1 つ保持し、純粋遷移はそこから読み出すことでコードの分岐を減らす。
    /// Scene 構築時に `jrpgProfile()` / `visualNovelProfile()` から選ぶか、
    /// 個別フィールドを上書きしてカスタムプロファイルを作る。
    ///
    /// フィールド:
    ///   - `maxLinesPerPanel`: 1 パネルに溜める最大行数。1 で行ごとパネル切替（VN 風）
    ///   - `breakOnSpeakerLine`: 名前 prefix 付き Line を「新パネル + 確定キー待ち」扱いにするか。
    ///       false なら名前 prefix は単なる装飾（log スタイル等）
    ///   - `autoNextContinuation`: 継続行で typewriter 完了時に自動で次へ進めるか。
    ///       false なら毎行確定キーが要る（VN 風）
    ///   - `transitionDuration`: パネル切り替え演出の継続時間
    ///   - `revealCharsPerSecond`: typewriter の送出速度（文字 / 秒）
    ///   - `blinkPeriod`: 続行待ちインジケータの点滅 1 サイクル長。半周期で ON/OFF 切替
    ///   - `nextIndicatorGlyph`: 続行待ちインジケータの表示記号。描画側で表示可能なフォントを用意する
    pub type alias DialogueProfile = {
        maxLinesPerPanel          = Int32,
        breakOnSpeakerLine        = Bool,
        autoNextContinuation   = Bool,
        transitionDuration        = Duration.Duration,
        revealCharsPerSecond      = Float64,
        blinkPeriod               = Duration.Duration,
        nextIndicatorGlyph     = String
    }

    /// JRPG 風（3 行パネル / 名前 prefix で待機 / 継続行は自動送り / "▼" 点滅）。
    pub def jrpgProfile(): DialogueProfile = {
        maxLinesPerPanel          = 3,
        breakOnSpeakerLine        = true,
        autoNextContinuation   = true,
        transitionDuration        = Duration.seconds(0.6),
        revealCharsPerSecond      = 40.0,
        blinkPeriod               = Duration.seconds(0.5),
        nextIndicatorGlyph     = "▼"
    }

    /// ビジュアルノベル風（1 行 1 パネル / 毎行確定キー待ち / 軽い演出）。
    pub def visualNovelProfile(): DialogueProfile = {
        maxLinesPerPanel          = 1,
        breakOnSpeakerLine        = false,
        autoNextContinuation   = false,
        transitionDuration        = Duration.seconds(0.2),
        revealCharsPerSecond      = 50.0,
        blinkPeriod               = Duration.seconds(0.5),
        nextIndicatorGlyph     = "▼"
    }

    /// 対話 UI の論理状態。Scene 表現（CanvasLayer / RichTextLabel など）から
    /// 独立した純粋データなので、別の描画実装に差し替えても再利用できる。
    ///
    /// 設計:
    ///   - `lines` は同じ話者の発話を `profile#maxLinesPerPanel` まで蓄積する（古→新）
    ///   - `profile#breakOnSpeakerLine` が true の場合、名前 prefix 付き Line は新パネル化扱い：
    ///     - 旧 lines + 完了時に流すイベントを `transition` に退避し、スクロールアウトする
    ///     - 演出完了時に `applyEventInner` で実反映する
    ///       （= 演出が終わるまで次の文章は出さない）
    ///   - 上限超え / Options / Complete も同じく新パネル化扱い
    ///   - 名前なし継続 Line のあとは `lastLineHadName = false`。typewriter 完了時に
    ///     `profile#autoNextContinuation` が true なら `shouldAutoNext` が true になり、
    ///     Scene 側 process が自動 submitNext を呼ぶ
    ///   - typewriter は `lines` 全体（連続文字列扱い）にかかる
    pub type alias UIState = {
        speaker         = Option[SpeakerName], // 現在のパネルの話者（":" の左側から抽出）
        lines           = List[LineText],      // 蓄積中の発話（古→新）
        choices         = List[ChoiceLabel],   // 選択肢中なら non-empty
        cursor          = Int32,               // choices 内の選択中 index（0 始まり）
        visible         = Bool,                // 完了後 / 未開始は false
        revealProgress  = Float64,             // パネル全体の typewriter 進捗（文字数累積）
        elapsed         = Duration.Duration,   // 表示中の経過時間（点滅用）
        lastLineHadName = Bool,                // 最新 line に名前 prefix が付いていたか
        transition      = Option[Transition],  // 直前パネルのスクロール演出 + 完了時の保留イベント
        profile         = DialogueProfile      // ジャンルごとのリズム・寸法
    }

    // ════════════════════════════════════════════════════════════════════════
    // UIState の純粋遷移と整形
    // ════════════════════════════════════════════════════════════════════════

    /// 初期状態（未開始 = 非表示）。`profile` で表現スタイルを選ぶ。
    pub def emptyState(profile: DialogueProfile): UIState = {
        speaker = None,
        lines = Nil,
        choices = Nil,
        cursor = 0,
        visible = false,
        revealProgress = 0.0,
        elapsed = Duration.zero(),
        lastLineHadName = false,
        transition = None,
        profile = profile
    }

    /// `text` の "<speaker>:" 部分を取り出す。コロンが無ければ `None`。
    /// 区切りは Yarn の慣例に合わせ半角 `:` のみ。全角コロン `：` を使う場合は
    /// 呼び出し側で正規化するか、独自の抽出関数で `PresentedLine#speaker` を埋める。
    pub def extractSpeaker(text: LineText): Option[SpeakerName] =
        let indexed = List.zipWithIndex(String.toList(text));
        match List.find(match (_, c) -> c == ':', indexed) {
            case Some((idx, _)) =>
                let speaker = String.slice(start = 0, end = idx, text);
                Some(String.trim(speaker))
            case None => None
        }

    /// 1 件の `ViewEvent` を状態に反映する純粋関数。
    /// `eventStartsNewPanel` が真なら旧 lines + イベント本体を `transition` に
    /// 退避する（演出完了時に `applyEventInner` で適用）。
    /// 偽なら直ちに `applyEventInner` で反映する。
    pub def applyEvent(event: ViewEvent, state: UIState): UIState =
        if (eventStartsNewPanel(event, state))
            beginPanelTransition(event, state)
        else
            applyEventInner(event, state)

    /// イベントを受けたら **新パネル化（= transition でゲート）** すべきか。
    ///
    /// 通常時 (transition なし):
    ///   - lines 空: false（最初の行は即時表示してよい。transition する旧 lines も
    ///     無いので保留する意味も無い）
    ///   - それ以外: 名前付き Line / 上限到達 Line / Choices / Complete で true
    ///
    /// transition 中:
    ///   - panel 起点系 (Line / Choices / Complete) は **常に true** を返し、
    ///     `beginPanelTransition` の「pendingEvent 上書き」経路に流す。
    ///     これは旧 session の `Complete` が新 session の `Line` に追い越されるケースを
    ///     正しく処理するため: lines が空 (= transition 開始直後) でも、新イベントを
    ///     `applyEventInner` 経由で生に反映してしまうと、後続の演出完了で旧
    ///     `pendingEvent` が走って消されてしまう。差し替え経路に乗せれば、演出完了時に
    ///     最新のイベントが描画される。
    ///   - Dismiss / Command は panel を変えないので false（演出と無関係に実行）
    def eventStartsNewPanel(event: ViewEvent, state: UIState): Bool =
        let inTransition = Option.nonEmpty(state#transition);
        match event {
            case ViewEvent.Line(_, speaker) =>
                if (inTransition) true
                else if (List.isEmpty(state#lines)) false
                else (state#profile#breakOnSpeakerLine and Option.nonEmpty(speaker))
                  or List.length(state#lines) >= state#profile#maxLinesPerPanel
            case ViewEvent.Choices(_) =>
                inTransition or not List.isEmpty(state#lines)
            case ViewEvent.Complete =>
                inTransition or not List.isEmpty(state#lines)
            case ViewEvent.Dismiss    => false
            case ViewEvent.Command(_) => false
        }

    /// 旧 lines + 完了時イベントを transition に退避し、適用を演出完了まで保留する。
    /// transition 進行中に新イベントが来た場合は、進捗（`progress` / `oldLines`）は
    /// 保持しつつ `pendingEvent` だけ最新で上書きする（既存挙動と同じ）。
    def beginPanelTransition(event: ViewEvent, state: UIState): UIState =
        let nextTransition: Transition = match state#transition {
            case Some(t) => { pendingEvent = event | t }
            case None    => { oldLines = state#lines, progress = 0.0, pendingEvent = event }
        };
        { speaker = state#speaker,
           lines = Nil,
           choices = Nil,
           cursor = 0,
           visible = true,
           revealProgress = 0.0,
           elapsed = state#elapsed,
           lastLineHadName = state#lastLineHadName,
           transition = Some(nextTransition),
           profile = state#profile }

    /// transition を伴わない実適用ロジック。
    /// `applyEvent` 直接呼び出し（lines 空 / 継続 line / Dismiss / Command）と、
    /// `tickTransition` 完了時の保留イベント反映の両方から呼ばれる。
    def applyEventInner(event: ViewEvent, state: UIState): UIState =
        match event {
            case ViewEvent.Line(text, speaker) => acceptLineInner(text, speaker, state)
            case ViewEvent.Choices(choices)    => startChoicesInner(choices, state)
            case ViewEvent.Dismiss             => state
            case ViewEvent.Command(_)          => state
            case ViewEvent.Complete            =>
                { elapsed = state#elapsed | emptyState(state#profile) }
        }

    /// transition なしで Line を反映する。lines 空なら新規行として、非空なら append として扱う。
    /// （新パネルが必要な状況は `applyEvent` 側で `transition` の `pendingEvent` に逃がしている）
    def acceptLineInner(text: LineText, speaker: Option[SpeakerName], state: UIState): UIState =
        let hasName = Option.nonEmpty(speaker);
        if (List.isEmpty(state#lines))
            // 初回 / transition 後の最初の行
            { speaker = if (hasName) speaker else state#speaker,
               lines = text :: Nil,
               choices = Nil,
               cursor = 0,
               visible = true,
               revealProgress = 0.0,
               elapsed = state#elapsed,
               lastLineHadName = hasName,
               transition = state#transition,
               profile = state#profile }
        else
            // 継続 line（名前なし & 上限内）。typewriter は連続のまま。
            { speaker = state#speaker,
               lines = List.append(state#lines, text :: Nil),
               choices = Nil,
               cursor = 0,
               visible = true,
               revealProgress = state#revealProgress,
               elapsed = state#elapsed,
               lastLineHadName = false,
               transition = state#transition,
               profile = state#profile }

    /// transition なしで Choices を反映する。
    def startChoicesInner(choices: List[ChoiceLabel], state: UIState): UIState =
        { speaker = None,
           lines = Nil,
           choices = choices,
           cursor = 0,
           visible = true,
           revealProgress = 0.0,
           elapsed = state#elapsed,
           lastLineHadName = false,
           transition = state#transition,
           profile = state#profile }

    /// `delta` だけカーソルを動かした状態を返す。
    /// 範囲外は wrap-around（先頭から末尾へ、末尾から先頭へ）。
    /// choices が空のときは状態を変えない。
    pub def moveCursor(delta: Int32, state: UIState): UIState =
        let choiceCount = List.length(state#choices);
        if (choiceCount <= 0) state
        else {
            let raw = state#cursor + delta;
            let normalized =
                if (raw < 0) choiceCount - 1
                else if (raw >= choiceCount) 0
                else raw;
            { cursor = normalized | state }
        }

    /// 選択肢の `index` を直接カーソルにセットする。
    /// `index` が `[0, choices.length)` の外、または `choices` が空のときは状態を変えない。
    /// マウスホバー由来の絶対指定（`DialogueScene.onMouseMotion`）から使う。
    /// `moveCursor` と違って wrap-around しない（ヒットテストの結果を素直に反映するため）。
    pub def setCursor(index: Int32, state: UIState): UIState =
        let choiceCount = List.length(state#choices);
        if (choiceCount <= 0) state
        else if (index < 0 or index >= choiceCount) state
        else { cursor = index | state }

    /// 1 フレーム経過分の更新。typewriter / transition / 経過時間の 3 つを進める。
    pub def tick(delta: Duration.Duration, state: UIState): UIState =
        state
            |> tickReveal(delta)
            |> tickTransition(delta)
            |> tickElapsed(delta)

    /// 1 フレーム分のイベント列を `applyEvent` で順に反映してから `tick(delta)` する。
    /// Scene 側 `process` の標準パイプライン。`Dialogue.SceneView.Inbox.takeAll`
    /// の結果をそのまま渡す想定。別 Scene 実装に差し替えても再利用できる。
    pub def applyFrame(delta: Duration.Duration, events: List[ViewEvent], state: UIState): UIState =
        List.foldLeft((s, event) -> applyEvent(event, s), state, events)
            |> tick(delta)

    /// 1 フレーム分の標準処理を 1 関数で実行する副作用版ヘルパ。
    ///   1. `Dialogue.SceneView.Inbox.takeAll` で 1 フレーム分のイベントを取り出す
    ///   2. `applyFrame(delta, events, state)` で状態に畳み込み + tick
    ///   3. `shouldAutoNext(newState)` が true なら `Dialogue.Session.submitNext()` を呼ぶ
    /// 戻り値は `(newState, addedLineCount)`。`addedLineCount > 0` のフレームは新しい行が
    /// 表示開始されたフレームなので、トーク SE などの演出トリガに使える。
    pub def processFrame(delta: Duration.Duration, state: UIState):
                          (UIState, Int32) \ Dialogue.SceneView.Inbox + Dialogue.Session =
        let events = Dialogue.SceneView.Inbox.takeAll();
        let newState = applyFrame(delta, events, state);
        if (shouldAutoNext(newState)) Dialogue.Session.submitNext() else ();
        let added = List.length(newState#lines) - List.length(state#lines);
        (newState, Int32.max(0, added))

    /// 表示中の経過時間を進める。点滅などのアニメーションに使う。
    def tickElapsed(delta: Duration.Duration, state: UIState): UIState =
        if (not state#visible) state
        else { elapsed = Duration.add(state#elapsed, delta) | state }

    /// パネル内の全行の合計文字数。typewriter は **panel 全体を 1 つの連続列** として
    /// 進むため、cap や完了判定はこの合計と比較する。
    def totalCharCount(state: UIState): Int32 =
        List.foldLeft((acc, line) -> acc + String.length(line), 0, state#lines)

    /// typewriter を進める内部関数。cap は **panel 内全行の合計文字数**。
    /// 行が append されると cap が伸びるので、そのまま typewriter が次行へ流れていく。
    def tickReveal(delta: Duration.Duration, state: UIState): UIState =
        if (not state#visible) state
        else if (not List.isEmpty(state#choices)) state
        else if (List.isEmpty(state#lines)) state
        else {
            let cap = Int32.toFloat64(totalCharCount(state));
            let dt = Duration.toSeconds(delta);
            let advanced =
                state#revealProgress + dt * state#profile#revealCharsPerSecond;
            { revealProgress = Float64.min(cap, advanced) | state }
        }

    /// transition の `progress` を進め、1.0 を超えたら `None` に戻す。
    /// ちょうど完了したフレームで保留イベント（`transition#pendingEvent`）を
    /// `applyEventInner` で反映する（= 演出が終わるまで次の文章は出さないというゲート）。
    def tickTransition(delta: Duration.Duration, state: UIState): UIState =
        match state#transition {
            case None => state
            case Some(transition) =>
                let advanced =
                    transition#progress + Duration.toSeconds(delta) / Duration.toSeconds(state#profile#transitionDuration);
                if (advanced >= 1.0) {
                    let cleared = { transition = None | state };
                    applyEventInner(transition#pendingEvent, cleared)
                } else {
                    let updated: Transition = { progress = advanced | transition };
                    { transition = Some(updated) | state }
                }
        }

    /// **パネル全体** が完全に表示済みなら true。
    /// choices モード（typewriter 対象外）と非表示・未開始は常に true 扱い。
    pub def isPanelFullyRevealed(state: UIState): Bool =
        if (not state#visible) true
        else if (not List.isEmpty(state#choices)) true
        else if (List.isEmpty(state#lines)) true
        else state#revealProgress >= Int32.toFloat64(totalCharCount(state))

    /// typewriter を即座に完了させる（パネル内の残り文字を一気に表示）。
    pub def forceFullReveal(state: UIState): UIState =
        { revealProgress = Int32.toFloat64(totalCharCount(state)) | state }

    /// パネルに表示する本文を組み立てる。
    /// - choices 非空 → カーソル行に `> `、それ以外に `  ` を付けて改行連結
    /// - line モード → `revealProgress` 文字数を全行に **連続して** 分配し、
    ///   各行を「self.length 以下に切り詰めた可視部分」で組み立てて改行連結。
    ///   続行 ▼ インジケータは別ノードで描画するためここには含めない。
    pub def formatBody(state: UIState): String =
        if (not List.isEmpty(state#choices))
            List.mapWithIndex((index, choice) ->
                if (index == state#cursor) "> ${choice}"
                else "  ${choice}",
                state#choices)
                |> String.intercalate("\n")
        else if (List.isEmpty(state#lines)) ""
        else {
            let revealed =
                Float64.floor(state#revealProgress)
                    |> Float64.tryToInt32
                    |> Option.getWithDefault(0)
                    |> Int32.max(0);
            // 可視文字数ベースで slice する。`[color=red]` のタグ自体は 0 文字扱いで、
            // 切り出した時点で開いている色タグは末尾で閉じられるため、typewriter の
            // 途中フレームでも `[col` のような中途半端な表記が画面に出ない。
            let step = (acc, line) -> {
                let (rendered, remaining) = acc;
                let visibleLen = Markup.BBCode.visibleLength(line);
                let take = Int32.min(remaining, visibleLen);
                let visible = Markup.BBCode.sliceVisible(line, Int32.max(0, take));
                (List.append(rendered, visible :: Nil), remaining - take)
            };
            let (linesOut, _) =
                List.foldLeft(step, ((Nil: List[String]), revealed), state#lines);
            String.intercalate("\n", linesOut)
        }

    /// transition が表示中なら、その内容（テキスト・進捗）を返す。
    /// 描画レイヤ側でスクロール量・modulate フェードに換算する。
    pub def transitionView(state: UIState): Option[Transition] =
        state#transition

    /// パネル全体が typewriter 完了 + 入出力待ちが何も無い状態かどうか（共通プレディケート）。
    /// `transition` が `None` の時点で保留イベントも無いので、Option を 1 つ確認すれば足りる。
    def isPanelIdle(state: UIState): Bool =
        state#visible
            and List.isEmpty(state#choices)
            and Option.isEmpty(state#transition)
            and isPanelFullyRevealed(state)
            and not List.isEmpty(state#lines)

    /// **ユーザの確定キーを待っている** 状況なら true。
    /// 「名前 prefix の Line で締められた panel」または「上限まで埋まった panel」が対象。
    /// `profile#breakOnSpeakerLine` が false なら名前 prefix は無視され、
    /// 上限ベースの判定だけになる。
    pub def shouldShowNextIndicator(state: UIState): Bool =
        isPanelIdle(state)
            and ((state#profile#breakOnSpeakerLine and state#lastLineHadName)
                 or List.length(state#lines) >= state#profile#maxLinesPerPanel)

    /// **自動で次の Line に進む** べき状況なら true。
    /// `profile#autoNextContinuation` が true で、名前 prefix なしの継続行のあと、
    /// まだ panel に余裕があるとき。Scene 側 process がこれを見て `Session.submitNext` を呼ぶ。
    pub def shouldAutoNext(state: UIState): Bool =
        isPanelIdle(state)
            and state#profile#autoNextContinuation
            and not (state#profile#breakOnSpeakerLine and state#lastLineHadName)
            and List.length(state#lines) < state#profile#maxLinesPerPanel

    /// 点滅インジケータの ON/OFF を `elapsed` から決める。
    /// 半周期ごとに切り替わる（`profile#blinkPeriod` × 2 で 1 サイクル）。
    pub def isBlinkOn(state: UIState): Bool =
        let cycles =
            Float64.floor(Duration.toSeconds(state#elapsed) / Duration.toSeconds(state#profile#blinkPeriod))
                |> Float64.tryToInt32
                |> Option.getWithDefault(0);
        Int32.modulo(cycles, 2) == 0

    /// 確定キー（決定ボタン）が押されたときに、現在の `UIState` から導かれる
    /// アクション。Scene 側は `match Dialogue.confirmAction(state) { ... }` で
    /// 4 ケースに振り分ければよく、`isPanelFullyRevealed` / `shouldShowNextIndicator` /
    /// `choices` などの低水準述語の優先順位を Scene が再発明する必要がなくなる。
    pub enum ConfirmAction with Eq, ToString {
        /// 何もしない（非表示・transition 中・auto-next 待ち など）。
        case Ignore
        /// typewriter 進行中。`forceFullReveal` で残り文字を一気に出す。
        case ForceFullReveal
        /// 選択肢提示中。同梱の `cursor` で `Session.submitSelect` を呼ぶ。
        case SelectChoice(Int32)
        /// ▼ 待ち中。`Session.submitNext` で次の行へ。
        case AdvanceLine
    }

    /// 現在の `UIState` を見て、確定キーで取るべき `ConfirmAction` を返す。
    /// 優先順位は (1) 非表示なら無視、(2) 選択肢中なら確定、(3) typewriter 進行中なら一気出し、
    /// (4) ▼ 待ちなら次行送り、(5) それ以外（auto-next 中・transition 中など）は無視。
    pub def confirmAction(state: UIState): ConfirmAction =
        if (not state#visible) ConfirmAction.Ignore
        else if (not List.isEmpty(state#choices)) ConfirmAction.SelectChoice(state#cursor)
        else if (not isPanelFullyRevealed(state)) ConfirmAction.ForceFullReveal
        else if (shouldShowNextIndicator(state)) ConfirmAction.AdvanceLine
        else ConfirmAction.Ignore

    // ════════════════════════════════════════════════════════════════════════
    // effects
    // ════════════════════════════════════════════════════════════════════════

    /// ゲームロジック・入力レイヤ → 対話駆動の API。
    pub eff Session {
        /// 指定ノードから対話を開始する。
        def start(nodeName: String): Unit

        /// 対話を強制中断する。VM 状態をクリアし、view にも完了通知を送る。
        def stop(): Unit

        /// 現在対話実行中なら true。
        def isActive(): Bool

        /// 現在の行表示を完了し、次の命令に進む。
        def submitNext(): Unit

        /// 選択肢を確定する。`choiceIndex` は presentChoices で渡された index と同じ。
        def submitSelect(choiceIndex: Int32): Unit

        /// コマンド実行完了の通知。
        def submitCommandDone(): Unit

        /// VM を `nodeName` で初期化し、最初の命令を走らせる前に `variables` を流し込む。
        /// `<<load>>` 由来。`start` と違い、ノード冒頭で変数を読む式（`${$brave}` 等）も
        /// 復元値を見るので、ロード直後にセリフが正しい変数で描画される。
        def restart(nodeName: String, variables: Map[String, Yarn.Types.Value]): Unit
    }

    /// プレゼンターが満たす契約。エンジン非依存。
    /// 実エンジンに乗せるときは UI を操作する handler を `with DialogueView ...` で注入する。
    pub eff DialogueView {
        /// 1 行表示する。表示完了後、ユーザの submitNext を待つ。
        def presentLine(line: PresentedLine): Unit

        /// 選択肢を提示する。確定はユーザの selectChoice を待つ。
        def presentChoices(choices: List[PresentedChoice]): Unit

        /// 表示中の行を消す（次の line / choices に行く前のクリア）。
        def dismissLine(): Unit

        /// Yarn コマンドを実行依頼する。
        /// 完了は呼び出し元から `Session.submitCommandDone` で返ってくる。
        def runCommand(commandText: String): Unit

        /// 対話が完了したことを通知する。
        def dialogueComplete(): Unit
    }

    // ════════════════════════════════════════════════════════════════════════
    // facade — 対話 handler 一式を 1 行で適用する
    // ════════════════════════════════════════════════════════════════════════

    /// `Runner` / `SceneView`（DialogueView + Inbox + CommandInbox）を 1 つにまとめた
    /// facade。region と event queue を内部に閉じ込めるため、呼び出し側は
    /// scene 構築・入力・gameLoop だけに集中できる。
    ///
    /// `body` 内で `Dialogue.Session.start` などを呼ぶと、view 側のイベントは
    /// `Dialogue.SceneView.Inbox.takeAll` 経由で取り出せる（Scene 側の `process`
    /// で消化する想定）。
    ///
    /// 本番用は `<<command>>` を非同期扱いにする（コマンドは `CommandInbox` 経由で
    /// gameLoop 側ルータが処理し、完了タイミングで `Session.submitCommandDone` を呼ぶ）。
    /// テスト用に同期完了させたい場合は `Dialogue.Test.withTestDialog` を使う。
    pub def withDialog(yarnProject: Yarn.Types.YarnProject,
                        body: Unit -> a \ ef):
                         a \ (ef - Session - DialogueView
                                 - Yarn.VariableAccess
                                 - Dialogue.SceneView.Inbox
                                 - Dialogue.SceneView.CommandInbox)
                              + Yarn.BuiltinExtension.Access =
        region rc {
            run body() with Dialogue.Runner.withRunner(rc, yarnProject, false)
                       with Dialogue.SceneView.withSceneView(rc)
        }
}
