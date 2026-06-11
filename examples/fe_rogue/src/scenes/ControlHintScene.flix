/// ControlHintScene — 「いま決定 / キャンセルボタンで何が起きるか」を画面隅に常時出す操作ガイド HUD。
///
/// このゲームは決定ボタン (Z) の意味がカーソルの位置で変わる:
///   - 味方の上で Z   → その味方を選んで動かす
///   - 何もないマスで Z → しゅうごう / ターンエンドのメニュー
///   - 移動中に Z      → こうどうメニュー (こうげき / こうかん / たいき 等)
/// これを知らせる表示がこれまで無く、知っている人しか操作できなかった。そこで画面下部
/// (ミニマップと同じ高さ) の右側に「十字ボタン: ◯◯ ／ 決定ボタン: △△」のような案内を
/// 毎フレーム文脈に合わせて出す。ボタンは物理キー名 (Z/X) ではなく役割名 (決定 / キャンセル /
/// 十字) で呼び、「決定ボタン: 決定」のような自明な案内は出さない。
///
/// 判定ロジックは新しく書かず、入力処理が使うのと同じ純粋関数を再利用する:
///   - `TurnInputBridge.buildContext` で現フレームの状況を `TurnRules.Context` にまとめ
///   - `TurnRules.decide` に決定 (Confirm) を渡して「いま Z で起きる遷移」を得る
///   - その遷移とフェーズを `hintFor` で表示文言に変換する
/// こうすると実際の操作とガイドが絶対にズレない。盤面は process では `BoardQuery` が
/// 使えない (`FrameAef.ProcessT` に含まれない) ため、純粋な `BoardSnapshot.fromScene` で作る。
///
/// 自走モデル: 専用ノードの `process` が毎フレーム文言を計算し、前フレームと変わったときだけ
/// テキストを書き換える。文言が空 (敵ターンなど入力を受け付けないフェーズ) のときは
/// `PhaseBannerScene` と同じく CanvasLayer を画面外へずらして帯ごと隠す。
///
/// ノード構造 (drawLayer=4):
///   ControlHint (CanvasLayer, NodeTag.ControlHint(直近に表示した 1 行))  ← offset(x) で出し入れ
///     ├─ band (ColorRect, 文字を読みやすくする半透明の帯。ミニマップ下端にそろえる, NoTag)
///     └─ text (Label2D, 右寄せ, NoTag)
mod ControlHintScene {

    // ─── 定数 ─────────────────────────────────────────────────

    def rootName(): String = "ControlHint"
    def bandName(): String = "band"
    def textName(): String = "text"

    def rootPath(): NodePath = rootName() :: Nil
    def textPath(): NodePath = rootName() :: textName() :: Nil

    /// UITheme 統一ポリシーにより全 HUD で共通フォントを使う。
    def fontName(): String = "ui"

    /// 描画レイヤー。フロア表示 (FloorLabel) と同じく前面寄り、ログ (layer=1) より前。
    def drawLayer(): Int32 = 4

    /// 帯 < 文字 の重ね順。
    def bandZIndex(): Int32 = 0
    def textZIndex(): Int32 = 1

    /// 文字サイズ (論理 px)。3 ボタン分の案内が右側に収まる控えめな大きさ。
    def fontSize(): Float64 = 3.8

    /// 帯の高さ (論理 px)。
    def bandHeight(): Float64 = 9.0
    /// ミニマップ右端と帯の左端の間に空ける隙間 (論理 px)。
    def bandGap(): Float64 = 1.0

    /// 文字の右端を画面右端からどれだけ内側に置くか。
    def textMarginRight(): Float64 = 3.0

    /// 帯・文字の色。
    def bandColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def bandAlpha(): Float32 = 0.5f32
    def textColor(): Color = UITheme.white()

    /// CanvasLayer の横オフセット。CanvasLayer のオフセットは子ノードの絶対座標ではなく
    /// レイヤー全体をシフトするため、設計解像度 170px を大きく超える負値にすることで
    /// 帯と文字を確実に画面外へ追い出せる。-170 では端にかかる恐れがあるため余裕を持たせる。
    def homeX(): Float64 = 0.0
    def offHiddenX(): Float64 = -300.0

    // ─── 構築 ─────────────────────────────────────────────────

    /// 右下にガイド帯一式を追加する。`GameLifecycle.buildPlayingScene` の UI 群で 1 回呼ぶ。
    /// 初期テキストは空で、帯は画面外 (offHiddenX) に置いておく。最初のフレームの `process` が
    /// 文言を計算して表示位置へ出す。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let screenWidth = Int32.toFloat64(Game.designWi());
        // ミニマップ (左下) と同じ下端 y にそろえ、ミニマップ右端のすぐ右から画面右端まで帯を張る。
        let minimap = MinimapScene.targetRect();
        let bandBottomY = Int32.toFloat64(minimap#y1);
        let bandTopY = bandBottomY - bandHeight();
        let bandLeftX = Int32.toFloat64(minimap#x1) + bandGap();
        let bandW = screenWidth - bandLeftX;
        let textRightX = screenWidth - textMarginRight();
        let textCenterY = bandTopY + bandHeight() / 2.0;
        let layer = CanvasLayer.make(drawLayer())
            |> CanvasLayer.setOffset({x = offHiddenX(), y = 0.0});
        let band = ColorRect.make({x = bandW, y = bandHeight()}, bandColor())
            |> ColorRect.setAlpha(bandAlpha())
            |> Node2D.setPosition({x = bandLeftX, y = bandTopY})
            |> CanvasItem.setZIndex(bandZIndex());
        let text = Label2D.make("", atlas, fontSize())
            |> Node2D.setPosition({x = textRightX, y = textCenterY})
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Right)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(textZIndex());
        scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.ControlHint("")))
            |> Scene.addChild(rootName(), bandName(),
                EngineNode.ColorRectWithState(band, NodeTag.NoTag))
            |> Scene.addChild(rootName(), textName(),
                EngineNode.Label2DWithState(text, NodeTag.NoTag))

    // ─── ロジック (純粋) ───────────────────────────────────────

    /// フェーズと「いま決定で起きる遷移」から、十字 (dpad) / 決定 (decide) / キャンセル (cancel)
    /// それぞれのボタンの行き先を表す短い文言を返す。空文字はそのボタンの案内を出さないことを表す。
    ///
    /// 方針:
    ///   - ボタンは物理キー名でなく役割名 (十字 / 決定 / キャンセル) で呼ぶ
    ///   - 「決定」「キャンセル」のように押せば自明な行き先は案内しない (例: メニューの確定・戻る)。
    ///     行き先が状況で変わる・固有名がある場合だけ出す (例: 移動・行動 / メニュー / こうげきせず)
    ///
    /// `zTransition` は `TurnRules.decide` に決定を渡した結果。カーソルが味方の上か空マスかで
    /// 中身が変わるフェーズ (PlayerCursor / PlayerMoving / PlayerAttack / TradeTargetSelect) は
    /// これを見て決定ボタンの案内を出し分ける。`decide` が `Stay` を返すメニュー系フェーズ
    /// (ActionSelect / ItemSelect など、入力処理が直接捌く) は遷移から意味が取れないので、
    /// フェーズごとの固定文言を返す。
    pub def hintFor(phase: TurnPhase.Phase, zTransition: TurnRules.Transition):
            {dpad = String, decide = String} =
        match phase {
            // カーソル移動中。味方の上か空マスかで決定の行き先が変わる。
            // カーソルを十字で動かすのは自明なので十字ボタンの案内は出さない。
            case TurnPhase.Phase.PlayerCursor =>
                let decide = match zTransition {
                    case TurnRules.Transition.CursorSelectPlayer(_) => "移動・行動"
                    case TurnRules.Transition.CursorOpenGatherMenu  => "メニュー"
                    case _                                          => ""
                };
                {dpad = "", decide = decide}
            // 味方を選んで動かしている最中。決定で行動メニュー。
            // 移動が十字なのは自明なので十字ボタンの案内は出さない。
            // また zTransition を見ず固定にする。Tween 中 (playerBusy) は decide が一瞬
            // 無効 (Stay) になり、毎歩「行動」が点滅して見えてしまうため。
            case TurnPhase.Phase.PlayerMoving =>
                {dpad = "", decide = "行動"}
            // 攻撃対象選択。←・→ で対象を変えられる。敵の上でだけ決定が「こうげき」。
            // キャンセルの案内は出さない。
            case TurnPhase.Phase.PlayerAttack =>
                let decide = match zTransition {
                    case TurnRules.Transition.OpenAttackForecast(_, _, _, _) => "こうげき"
                    case _                                                   => ""
                };
                {dpad = "←・→: 攻撃対象の変更", decide = decide}
            // 交換相手の選択。隣接味方の上でだけ決定が「こうかん」。
            case TurnPhase.Phase.TradeTargetSelect =>
                let decide = match zTransition {
                    case TurnRules.Transition.OpenTradeInventory(_) => "こうかん"
                    case _                                          => ""
                };
                {dpad = "", decide = decide}
            // 杖の発射方向を十字で選ぶ。
            case TurnPhase.Phase.StaffAim         => {dpad = "十字ボタン: ほうこう", decide = ""}
            // 戦闘予報。予報が出た時点で攻撃相手は確定しており、決定の結果は常に「こうげき」で
            // あるため zTransition を見ず固定にする。
            case TurnPhase.Phase.AttackForecast   => {dpad = "",       decide = "こうげき"}
            // ローグ自由移動。決定でメニュー (歩くのが十字なのは自明なので案内しない)。
            case TurnPhase.Phase.RogueMove        => {dpad = "",     decide = "メニュー"}
            // メニュー表示中 (ActionSelect / ItemSelect / ItemActionSelect / TradeInventory) は
            // 項目自体が画面に見えているので案内不要。入力を受け付けないフェーズ (敵ターン・
            // 演出ホールド・自動移動など) も含め、ここに来たら何も出さない (帯を隠す)。
            case _ => {dpad = "", decide = ""}
        }

    /// 文言レコードを画面に出す 1 行に整える。空文字のボタンは省き、残りを「／」で繋ぐ。
    /// すべて空なら空文字 (= 帯を隠す)。
    /// `dpad` は十字キーの案内で、ボタン名込みの整形済み文字列をそのまま使う。
    /// フェーズによって "十字ボタン: ほうこう"（全方向）や "←・→: 攻撃対象の変更"（左右のみ）
    /// のように書式が変わるため、呼び出し側で整形済みにして渡す設計にしている。
    /// `decide` は行き先だけを持ち、ここで "決定ボタン: ◯◯" に整える。
    pub def renderLine(hint: {dpad = String, decide = String}): String =
        (hint#dpad
            :: segment("決定ボタン", hint#decide)
            :: Nil)
            |> List.filter(part -> part != "")
            |> String.intercalate(" ／ ")

    /// ボタン名と行き先を「決定ボタン: ◯◯」の形にする。行き先が空なら空文字 (案内しない)。
    def segment(buttonName: String, action: String): String =
        if (action == "") "" else "${buttonName}: ${action}"

    // ─── ロジック (毎フレーム・副作用あり) ──────────────────────

    /// Game.flix の physicsProcess ループから NodeTag.ControlHint を持つノードに対して
    /// 毎フレーム呼ばれる。現フレームの文言を計算し、前フレームと変わったときだけテキストと
    /// 表示位置を書き換える (毎フレームの無駄な再構築を避ける)。文言が空なら帯ごと画面外へ隠す。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, TurnPhase.State, SelectedPlayer.State,
                        PlayerData.PartyQuery, EnemyData.RosterQuery} =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.ControlHint(shown)) =>
                let board = BoardSnapshot.fromScene(scene);
                let context = TurnInputBridge.buildContext(TurnRules.Input.Confirm, board, scene);
                let line = renderLine(hintFor(context#phase, TurnRules.decide(context)));
                if (line == shown) (node, scene)
                else {
                    let offsetX = if (line == "") offHiddenX() else homeX();
                    let next = scene
                        |> Label2D.mapAt(textPath(), Label2D.setText(line))
                        |> setOffsetX(offsetX)
                        |> setState(line);
                    match Scene.getEngineNode(path, next) {
                        case Some(latest) => (latest, next)
                        case None         => (node, next)
                    }
                }
            case _ => (node, scene)
        }

    /// CanvasLayer の横オフセットを与えて帯と文字をまとめて動かす (表示 / 画面外)。
    def setOffsetX(offsetX: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, tag) =>
                EngineNode.CanvasLayerWithState(
                    CanvasLayer.setOffset({x = offsetX, y = 0.0}, layer), tag)
            case other => other
        }, scene)

    /// 直近に表示した 1 行を CanvasLayer の状態として書き戻す。
    def setState(line: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.ControlHint(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.ControlHint(line))
            case other => other
        }, scene)
}
