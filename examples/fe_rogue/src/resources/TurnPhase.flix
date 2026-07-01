/// TurnPhase / TurnRules / TurnInputBridge — ターン進行に関わるロジックを集約したファイル
///
/// 同居理由: 3 つは `TurnPhase.Phase`（現フェーズ）と `TurnRules.Context`（判断入力）を
/// 中心データとして共有しており、別ファイルに分けると往復読みが必要になる:
///   - `TurnPhase`        : Phase enum + 現フェーズの State effect
///   - `TurnRules`        : 純粋判断 (フェーズ × 入力 × 盤面 → Transition)
///     ↑ Phase を読む側。`TurnRules.Context#phase` で参照する
///   - `TurnInputBridge`  : 入力 → Context build → decide → apply の 3 段 pipeline
///     ↑ Phase を書く側 (apply 内で TurnPhase.State.put を呼ぶ)。Context は TurnRules へ渡す
///
/// ────────────────────────────────────────────────────────
///
/// TurnPhase — 味方ターン内の細分化フェーズと敵ターンを 1 つの enum で扱う effect
///
/// ターン制 SRPG の入力契約は単純な「敵ターン中か否か」だけでは表現できない。
/// 味方ターンには「カーソルでマスを選ぶ」「味方を動かす」「攻撃対象を選ぶ」の 3 段が
/// あり、Z / X / WASD のそれぞれが意味を変える。`EnemyTurn.Queue.isEmpty()` だけでは
/// 「味方ターン中のどのサブフェーズか」を区別できないため、専用のフェーズ effect を持つ。
///
/// 設計意図:
///   - 入力ハンドラ・各 Scene の `physicsProcess` がフェーズで分岐するための単一情報源
///   - フェーズ切替は **どの handler から put してもよい**（決定キー押下の InputHandler、
///     敵ターン終了処理など）。実体の更新は次フレーム冒頭で全 Scene が `get` で観測する
///   - `EnemyTurn.Queue` と二重管理になるが、Queue は「敵 step の駆動キュー」、Phase は
///     「入力 / 描画 / カメラの分岐用シグナル」と責務を分離する。Phase が EnemyTurn の
///     間は Queue 非空が成立する不変条件は、Game.flix が両方を同時に書き換えて維持する
///
/// 使い方:
///   - `Game.start` で `with TurnPhase.withState(rc)` を 1 行注入する
///   - 起動時の初期値は `PlayerCursor`（味方のターン・カーソル選択フェーズ）
///   - 決定キー：味方マスで Z → `PlayerMoving` / 移動中に Z → `PlayerAttack` /
///              攻撃中に Z（赤マス上の敵）→ ダメージ適用 + `EnemyTurn`
///   - キャンセルキー：移動中に X → `PlayerCursor` に戻す /
///                    攻撃中に X → 攻撃せず即 `EnemyTurn`（敵フェーズへスキップ）
///   - 敵ターン終了（`finishEnemyTurn`）→ `PlayerCursor` に戻す
mod TurnPhase {

    /// 入力分岐・描画制御の単一情報源として全フェーズを列挙する ADT。
    /// 味方ターンのサブフェーズ（カーソル / 移動 / 行動選択…）から敵ターンまで、
    /// ゲーム進行中に取りうる全状態を網羅する。`PlayerCursor` が起動時デフォルト。
    pub enum Phase with Eq, ToString {
        /// 味方ターン・カーソル選択フェーズ。WASD/方向キーでカーソルを動かす。
        case PlayerCursor
        /// 味方ターン・選択した味方を動かしているフェーズ。WASD/方向キーで味方を動かす。
        case PlayerMoving
        /// 味方ターン・行動選択フェーズ。
        /// PlayerMoving で Z を押した瞬間に入り、画面に「こうげき / たいき」の ActionMenu が出る。
        /// 「こうげき」は射程内に敵が居るときだけ表示、「たいき」は同セルに別味方が居ないときだけ表示。
        /// 上下キーで項目を選び Enter/Z で確定。X/Escape でウィンドウを閉じて `PlayerMoving`
        /// に戻る (別の場所に動かし直せる)。
        case ActionSelect
        /// 味方ターン・武器選択フェーズ。
        /// ActionMenu「攻撃」確定で入り、ActionMenu の右隣に武器選択ウィンドウ (WeaponSelectScene)
        /// が出る。ActionMenu は表示したまま「攻撃」行をハイライト維持し、focus は武器側に移る。
        /// 上下キーで武器を選び Enter/Z で確定すると、その武器を装備 (weapons 先頭へ) してから
        /// 既存の攻撃フロア (`PlayerScene.enterAttackPhase`) に入る。X/Escape で ActionSelect に戻る。
        case WeaponSelect
        /// 味方ターン・アイテム選択フェーズ。
        /// ActionMenu の「アイテム」確定で入り、画面に ItemMenu が出る。
        /// 武器 + 杖を 1 つの ItemList に並べ、上下キーで選び Enter/Z で確定すると
        /// `ItemActionSelect` フェーズに進む。X/Escape で ActionMenu に戻る。
        case ItemSelect
        /// 味方ターン・アイテム個別アクションフェーズ。
        /// ItemSelect でアイテムを選んだ瞬間に入り、サブメニュー（武器なら「装備/捨てる」、
        /// 杖なら「使う/捨てる」）が ItemList に並ぶ。Enter/Z で確定、X/Escape で ItemSelect に戻る。
        /// 「装備」「捨てる」はターン消費せず ItemSelect に戻る。
        /// 杖の「使う」は `StaffAim` フェーズに進む。
        case ItemActionSelect
        /// 味方ターン・杖の方向選択フェーズ。
        /// 杖の「使う」確定で入り、WASD/方向キーで縦横 4 方向の発射方向を選ぶ。
        /// 方向確定で杖が直線に飛び、効果が発動 → ターンを進める。
        /// X/Escape で杖をキャンセル（耐久を消費せず ItemActionSelect に戻る）。
        case StaffAim
        /// 味方ターン・アイテム投擲の方向選択フェーズ（「投げる」確定で入る）。
        /// StaffAim と同じ矢印カーソルで方向を選び、Z で投げる（命中ロールあり）。
        /// X/Escape でキャンセル（消費せず ItemActionSelect に戻る）。
        case ThrowAim
        /// 味方ターン・物交換の相手選択フェーズ。
        /// ActionMenu の「こうかん」確定で入り、選択中味方の上下左右 1 マスの
        /// 他味方マスが緑マスで描かれる (`TradeRangeScene`)。カーソルは緑マス上
        /// のみ移動可。Z で交換相手を確定 → `TradeInventory` フェーズへ。
        /// X/Escape で交換をキャンセルし `ActionSelect` に戻る
        /// (行動継続: ActionMenu に戻る)。
        case TradeTargetSelect
        /// 味方ターン・物交換のインベントリ画面フェーズ。
        /// `TradeTargetSelect` で交換相手を Z で確定すると入り、画面に
        /// 「じぶん (左) / あいて (右)」の 2 ペインの ItemList が出る
        /// (`TradeMenuScene`)。↑↓ でアイテム移動、Enter/Z で確定。
        /// 自分側で 1 個選ぶ → focus があいて側に切替 → あいて側で 1 個選んで
        /// スワップ実行 → focus がじぶん側に戻る (連続交換可能)。
        /// 未選択で X/Escape → `ActionSelect` に戻る (行動継続)。
        case TradeInventory
        /// 味方ターン・戦闘予報フェーズ。
        /// PlayerAttack で敵に対して Z を押した瞬間に入り、装備中武器（weapons の先頭）で
        /// 戦闘予報パネルが出る。味方と敵の HP / 威力 / 命中 を並べる。
        /// Z で攻撃を実行、X/Escape で `PlayerAttack` に戻る。
        case AttackForecast
        /// 味方ターン・攻撃対象選択フェーズ。
        /// 味方の周囲（射程内）に赤マスが出て、カーソルは赤マス内のみ移動可。
        /// 赤マス上の敵に Z でダメージ → 敵ターンへ自動遷移、X で攻撃せず敵ターンへ。
        case PlayerAttack
        /// 味方ターン・攻撃で敵を倒した直後の演出ホールド。
        /// `attack_lunge` が完了し倒した敵が `death_blink` 中の間、カメラを瀕死の敵
        /// （= カーソル位置）に留めるための過渡状態。入力は受け付けない。
        /// `Pacing.State.hold` が抜けた瞬間に GameManager が `commitWaitedAndAdvance`
        /// を呼び、PlayerCursor または EnemyTurn に遷移する。
        case PlayerAttackHold
        /// レベルアップのステータス変化パネルを表示して入力待ちにするフェーズ。
        /// 攻撃解決でレベルアップを検出した味方の `pendingLevelUp` を LevelUpPanelScene が表示し、
        /// Z / Enter で閉じると通常のターン確定（commitWaitedAndAdvance）に戻る。
        /// その間は移動・選択など他の入力を受け付けない（モーダル）。
        case LevelUpView
        /// 集合（行軍）モード。「集合」確定で入る。主人公(id 0)だけを WASD で移動範囲内まで
        /// 動かし、主人公が 1 マス進むたびに各味方が最短 1 歩で追従する。Z で移動を確定して
        /// 隣接メニュー（交換 / 全員待機 / キャンセル）を開き、X で集合開始位置へ巻き戻す。
        /// カーソルは非表示。敵ターンは発生しない（確定後の「全員待機」で敵ターンへ進む）。
        case GatherMove
        /// 集合「階段で離脱」中。届く味方を 1 体ずつ階段へ歩かせ退場させる自動進行フェーズ。
        /// 入力は無効・カーソル非表示。`StairsExitScene` の driver が進める。
        case StairsExit
        /// 敵ターン。入力は無効、カーソル非表示、カメラはプレイヤーに固定。
        case EnemyTurn
        /// 全滅後のモーダル選択フェーズ。盤面はフリーズし、`GameOverMenuScene` の選択肢
        /// （最初から / そのフロアの最初から）だけを受け付ける。確定で run が再構築される。
        case GameOver
        /// 中断確認のモーダルフェーズ。「中断」選択で入り、`SuspendConfirmScene` の
        /// 「本当に中断しますか？ はい / いいえ」だけを受け付ける。はいで保存しタイトルへ、いいえで PlayerCursor に戻る。
        case SuspendConfirm
    }

    /// フェーズの読み書きを表す effect。
    /// 内部 `Ref` の存在は handler に隠蔽し、`Game.flix` 側からは effect op だけ見える。
    /// 隠蔽により Scene が直接 Ref を触れなくなり、`put` が単一経路（handler 内）に限定される。
    /// 複数の handler が共存しても同じ `Ref` を通じてフェーズが一元管理される。
    pub eff State {
        /// 現在のフェーズを返す。
        def get(): Phase
        /// 新しいフェーズを設定する。次フレーム以降で全 Scene が観測する。
        def put(target: Phase): Unit
    }

    /// `Tween.withScheduler` と同じ流儀の handler 注入。
    /// `Region[r]` を受け取る設計により、呼び出し側（`Game.start`）が `Ref` の
    /// ライフタイムを制御できる（region を超えて Ref が生存しない安全性が型で保証される）。
    /// 内部 `phaseRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let phaseRef: Ref[Phase, r] = Ref.fresh(rc, Phase.PlayerCursor);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(phaseRef))
                def put(target, k) = {
                    Ref.put(target, phaseRef);
                    k()
                }
            }
        }
}

/// TurnRules — 「フェーズ × 入力 × 盤面 → 次にどう遷移するか」の純粋ルール
///
/// 入力ハンドラから `decide(context)` を呼ぶと、その状況で起きる遷移を `Transition`
/// として返す。Game.flix 側はこれを match して、対応する Scene 操作 / effect handler
/// を起動する（実体の副作用は呼び出し側に閉じ込めて、ここは純粋に保つ）。
///
/// 呼び手から見ると: `Context` を組み立て → `decide` 呼び出し → `Transition` を
/// `TurnInputBridge.apply` に渡す、という 3 段パイプラインの中段に位置する。
mod TurnRules {

    /// プレイヤーが押した決定 / キャンセルのどちらか。
    /// 実際のキー（Z / X / Space / Enter）からの変換は呼び出し側が行う。
    pub enum Input with Eq, ToString {
        case Confirm
        case Cancel
    }

    /// 1 回の入力に対して起きる遷移。`Stay` は何もしないことを表す（無効入力など）。
    /// 各バリアントは Scene 操作 / effect handler 起動に必要な情報を全部抱える
    /// （apply 側で再ルックアップしないで済むように）。
    /// 純粋値として渡せるよう effect を持たず、副作用は受け取った `apply` 側に委ねる。
    ///
    /// 位置は `{x = Int32, y = Int32}` ではなく `(x, y)` の Int32 ペアで持つ。
    /// （Vec2i は record alias で auto-derive Eq に対応していないため。）
    pub enum Transition with Eq, ToString {
        /// 何も起きない（入力無効・条件未成立）
        case Stay
        /// PlayerCursor 中、カーソル位置にアクティブ味方が居て選択した
        case CursorSelectPlayer(Int32)
        /// PlayerCursor 中、カーソルが空き床マスで ActionMenu を開く（「集合 / ターンエンド」）。
        /// 「集合」確定で GatherMove へ向かい、主人公が隊列を率いて動き始める。
        case CursorOpenGatherMenu
        /// PlayerMoving 中の Confirm: 行動選択ウィンドウ (ActionSelect) を開く。
        /// 「こうげき / たいき」を文脈に応じて並べ、ItemList の Enter/X で次フェーズを決める。
        case MovingOpenActionMenu
        /// PlayerMoving 中の Cancel: 選択駒を origin に戻して PlayerCursor へ
        case MovingCancel
        /// PlayerAttack 中の Confirm: 敵を明確に選んだ → 装備中武器で AttackForecast に直行
        /// 引数: (attackerId, defenderId, defender の x, defender の y)
        case OpenAttackForecast(Int32, Int32, Int32, Int32)
        /// PlayerAttack 中の Cancel: 攻撃せず waited にして次のセレクトへ
        case AttackSkip
        /// TradeTargetSelect 中の Confirm: カーソル位置に居る隣接味方を交換相手として確定。
        /// 引数: partnerId (= 交換相手の player id)。
        /// 確定後は `enterTradeInventory` を呼び、TradeInventory フェーズに遷移する。
        case OpenTradeInventory(Int32)
        /// TradeTargetSelect 中の Cancel: 緑マス overlay を片付けて ActionSelect に戻す
        /// (= ActionMenu を再表示する。ターン消費しない)。
        case TradeCancel
        /// GatherMove 中の Confirm: 主人公の移動を確定して隣接メニュー (交換 / 全員待機 /
        /// キャンセル) を開く。主人公が味方マスと重なっている間は発火しない。
        case GatherOpenMenu
        /// GatherMove 中の Cancel: 主人公＋追従味方を集合開始位置へ巻き戻して PlayerCursor へ。
        case GatherCancel
    }

    /// `decide` に渡すコンテキスト一式。Scene[NodeTag] / Tween / 各 effect から
    /// 「いま判断に必要な値」だけを抜き出した record。テストでは直接合成できる。
    ///
    /// フィールドの意味:
    ///   - `phase`: 現在のフェーズ（TurnPhase.State.get の値）
    ///   - `input`: 押されたキーの分類（Confirm / Cancel）
    ///   - `board`: 盤面スナップショット（BoardQuery.board の値）
    ///   - `cursor`: カーソルのグリッド位置（CursorScene.getGridPos の値）
    ///   - `selected`: 選択中味方 id（SelectedPlayer.State.get の値）
    ///   - `waitedPlayerIds`: 既に行動済みの味方 id（findActiveIdAt で除外する用）
    ///   - `dyingEnemyIds`: 死亡演出中の敵 id（findIdAt で除外する用）
    ///   - `playerBusy`: 選択中味方が Tween 中なら true（Confirm/Cancel のガードに使う）
    pub type alias Context = {
        phase           = TurnPhase.Phase,
        input           = Input,
        board           = Board,
        cursor          = {x = Int32, y = Int32},
        selected        = Option[Int32],
        waitedPlayerIds = List[Int32],
        dyingEnemyIds   = List[Int32],
        playerBusy      = Bool
    }

    /// フェーズ × 入力 × 盤面 → 遷移を決める。Scene/effect を一切触らない純粋関数。
    pub def decide(context: Context): Transition =
        match (context#phase, context#input) {
            case (TurnPhase.Phase.PlayerCursor, Input.Confirm) =>
                match activePlayerAt(context) {
                    case Some(playerId) => Transition.CursorSelectPlayer(playerId)
                    case None           =>
                        // アクティブ味方が居ないセル(壁・床の空きマス・敵上・waited 味方上など)では
                        // 常に空マスメニュー(しゅうごう / ターンエンド)を開く。
                        // しゅうごうはロードへ合流するだけでセルを問わないので、どこでもメニューを開けてよい。
                        Transition.CursorOpenGatherMenu
                }
            case (TurnPhase.Phase.PlayerMoving, Input.Confirm) =>
                // Tween 中はガード。さらに「自分以外の味方と同セルで重なっている」
                // 場合も Z を完全に無視する (ActionMenu すら開かない)。
                // 移動中は味方マスを通過できるが、停止しての行動決定は許さない。
                if (context#playerBusy) Transition.Stay
                else match context#selected {
                    case Some(pid) =>
                        if (Board.isOverlappingAlly(pid, context#board)) Transition.Stay
                        else Transition.MovingOpenActionMenu
                    case None => Transition.Stay
                }
            // ActionSelect / ItemSelect / ItemActionSelect / StaffAim / AttackForecast は
            // InputHandler が Z/X を直接処理し、TurnRules 経由では遷移しない
            case (TurnPhase.Phase.ActionSelect, _) =>
                Transition.Stay
            case (TurnPhase.Phase.WeaponSelect, _) =>
                Transition.Stay
            case (TurnPhase.Phase.ItemSelect, _) =>
                Transition.Stay
            case (TurnPhase.Phase.ItemActionSelect, _) =>
                Transition.Stay
            case (TurnPhase.Phase.StaffAim, _) =>
                Transition.Stay
            case (TurnPhase.Phase.ThrowAim, _) =>
                Transition.Stay
            case (TurnPhase.Phase.AttackForecast, _) =>
                Transition.Stay
            // TradeInventory は MenuHandler が ItemList の Enter/Escape を直接処理する
            // ため、TurnRules 経由では遷移しない (キー押下は handleMenus パスに乗る)。
            case (TurnPhase.Phase.TradeInventory, _) =>
                Transition.Stay
            case (TurnPhase.Phase.PlayerMoving, Input.Cancel) =>
                if (context#playerBusy) Transition.Stay
                else Transition.MovingCancel
            case (TurnPhase.Phase.PlayerAttack, Input.Confirm) =>
                // 生きている敵が cursor に居て、かつ選択中駒があれば装備中武器で AttackForecast へ
                match (aliveEnemyAt(context), context#selected) {
                    case (Some(defenderId), Some(attackerId)) =>
                        Transition.OpenAttackForecast(attackerId, defenderId,
                            context#cursor#x, context#cursor#y)
                    case _ => Transition.Stay
                }
            case (TurnPhase.Phase.PlayerAttack, Input.Cancel) =>
                Transition.AttackSkip
            case (TurnPhase.Phase.TradeTargetSelect, Input.Confirm) =>
                // カーソル位置に隣接味方が居れば OpenTradeInventory を発火。
                // カーソル制限は CursorScene 側で緑マスに絞っているので、ここに
                // 来る時点で味方マスに乗っている想定だが、防御的に確認する。
                match adjacentAllyAtCursor(context) {
                    case Some(partnerId) => Transition.OpenTradeInventory(partnerId)
                    case None            => Transition.Stay
                }
            case (TurnPhase.Phase.TradeTargetSelect, Input.Cancel) =>
                Transition.TradeCancel
            case (TurnPhase.Phase.GatherMove, Input.Confirm) =>
                // Tween 中はガード。主人公が味方マスと重なっている間は確定不可
                // （味方マスをすり抜けられる代わりに重なり中は決定させない。PlayerMoving と対称）。
                if (context#playerBusy) Transition.Stay
                else match context#selected {
                    case Some(pid) =>
                        if (Board.isOverlappingAlly(pid, context#board)) Transition.Stay
                        else Transition.GatherOpenMenu
                    case None => Transition.Stay
                }
            case (TurnPhase.Phase.GatherMove, Input.Cancel) =>
                if (context#playerBusy) Transition.Stay
                else Transition.GatherCancel
            // EnemyTurn は入力無視（自動進行で抜ける）。
            case _ => Transition.Stay
        }

    /// cursor 位置にアクティブ（waited でない）な味方の id を返す。居なければ None。
    /// PlayerScene.findActiveIdAt の純粋版（Board と waitedPlayerIds から復元）。
    /// TurnRules はテスト可能な純粋関数モジュールであるため Scene effect を直接呼べない。
    /// そのため盤面データを Context に持ち込み、effect なしで同等のルックアップを再現する。
    def activePlayerAt(context: Context): Option[Int32] =
        Board.playerPositions(context#board)
            |> List.findMap(entry -> {
                let (playerId, position) = entry;
                if (samePosition(position, context#cursor)
                    and not isInList(playerId, context#waitedPlayerIds))
                    Some(playerId)
                else None
            })

    /// cursor 位置に居る「選択中味方以外の味方」の id を返す (= 交換相手候補)。
    /// 居なければ None。waited フィルタは ActionMenuScene の項目フィルタ側でかかっており、
    /// ここでは行わない (交換相手として選んだ味方が waited でも構わない仕様)。
    def adjacentAllyAtCursor(context: Context): Option[Int32] =
        Board.playerPositions(context#board)
            |> List.findMap(entry -> {
                let (playerId, position) = entry;
                if (samePosition(position, context#cursor)
                    and context#selected != Some(playerId))
                    Some(playerId)
                else None
            })

    /// cursor 位置に「生きている」敵の id を返す。居なければ None。
    /// EnemyScene.findIdAt の純粋版（Board と dyingEnemyIds から復元）。
    /// `activePlayerAt` と同様、TurnRules が Scene effect を呼べないため、
    /// 盤面データを Context に持ち込んで effect なしで同等のルックアップを再現する。
    def aliveEnemyAt(context: Context): Option[Int32] =
        Board.enemyPositions(context#board)
            |> List.findMap(entry -> {
                let (enemyId, position) = entry;
                if (samePosition(position, context#cursor)
                    and not isInList(enemyId, context#dyingEnemyIds))
                    Some(enemyId)
                else None
            })

    def samePosition(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    def isInList(target: Int32, list: List[Int32]): Bool =
        List.exists(value -> value == target, list)
}

/// TurnInputBridge — 入力 → 純粋判断 (TurnRules.decide) → Scene 適用 の 3 段 pipeline
///
/// `Game.flix` の `InputHandler` instance から「PlayerCursor / PlayerMoving / PlayerAttack
/// の Z/X 入力」が来たときに呼ばれるブリッジ。流れ:
///   1. `buildContext` で現フレームの状態から純粋な `TurnRules.Context` を構築
///   2. `TurnRules.decide` (純粋関数) で次の `Transition` を決める
///   3. `apply` の中央 match で対応する 1 つの Scene 関数を呼ぶ
///
/// `AttackSkip` だけは `TurnPhase.State.put` / `EnemyTurn.Queue` / `SelectedPlayer.State`
/// の複数 effect を跨ぐため、直接 Scene 関数を呼ばず `TurnFlow.commitWaitedAndAdvance`
/// を経由する（他の Transition は必ず単一の Scene 関数に収まる）。
mod TurnInputBridge {

    /// 1 回のキー入力 (Confirm / Cancel) を処理する。
    pub def handle(input: TurnRules.Input, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery, EnemyData.RosterQuery, World.Command, World.WorldQuery} =
        let context = buildContext(input, BoardQuery.board(), scene);
        apply(TurnRules.decide(context), scene)

    /// 現フレームの scene と各 effect から `TurnRules.Context` を組み立てる。
    /// `board` のみ呼び出し側から注入する。`FrameAef.ProcessT` に `BoardQuery`
    /// が含まれないため、`buildContext` 自身が `BoardQuery` 効果を要求しない設計にして
    /// process 経路からも再利用できるようにしている。
    ///
    /// `TurnRules.decide` は純粋関数だが、その入力 (Context) を作るには:
    ///   - `TurnPhase.State.get()` (現フェーズ)
    ///   - `SelectedPlayer.State.get()` (選択中味方 id)
    ///   - `CursorScene.getGridPos(scene)` (カーソル位置)
    ///   - `PlayerScene.getAll` / `EnemyScene.getAll` (waited / dying の id 集合)
    ///   - `World.isAnimating(...)` (選択中味方が移動中か)
    /// と複数の窓口を引く必要がある。これを 1 関数に集約する。
    pub def buildContext(input: TurnRules.Input, board: Board, scene: Scene[NodeTag]):
            TurnRules.Context \ {World.WorldQuery,
                                  TurnPhase.State, SelectedPlayer.State,
                                  PlayerData.PartyQuery, EnemyData.RosterQuery} =
        let selected = SelectedPlayer.State.get()#id;
        let busy = match selected {
            case Some(id) => World.isAnimating(World.EntityRef.Player(id), World.WorldQuery.get())
            case None     => false
        };
        let waitedIds = PlayerData.PartyQuery.getAll()
            |> List.filterMap(d -> if (d#waited) Some(d#id) else None);
        let dyingIds = EnemyData.RosterQuery.getAll()
            |> List.filterMap(e -> if (e#isDying) Some(e#id) else None);
        {
            phase           = TurnPhase.State.get(),
            input           = input,
            board           = board,
            cursor          = CursorScene.getGridPos(scene),
            selected        = selected,
            waitedPlayerIds = waitedIds,
            dyingEnemyIds   = dyingIds,
            playerBusy      = busy
        }

    /// `decide` が返した `Transition` をシーンに適用する。
    /// Scene 操作・effect 呼び出しをここに集約することで、`TurnRules` 側を
    /// 純粋関数（テスト容易・effect なし）に保つ。副作用はこの関数が一手に引き受ける。
    def apply(transition: TurnRules.Transition,
               scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery, World.Command} =
        match transition {
            case TurnRules.Transition.Stay                              => scene
            case TurnRules.Transition.CursorSelectPlayer(playerId)      =>
                PlayerScene.beginSelection(playerId, scene)
            case TurnRules.Transition.CursorOpenGatherMenu              =>
                ActionMenuScene.openFromCursor(scene)
            case TurnRules.Transition.MovingOpenActionMenu              =>
                ActionMenuScene.openFromMoving(scene)
            case TurnRules.Transition.MovingCancel                      =>
                PlayerScene.cancelSelection(scene)
            case TurnRules.Transition.OpenAttackForecast(attackerId, defenderId, _defX, _defY) =>
                // 装備中武器 (weapons.head) を自動使用するので武器選択は介さず AttackForecast 直行。
                // attackTargetId を立てて BattlePanelScene が予報を組み立てる。
                CombatScene.setAttackTargetId(attackerId, defenderId, scene)
                    |> PhaseTransitions.enterAttackForecast
            case TurnRules.Transition.AttackSkip                        =>
                TurnFlow.commitWaitedAndAdvance(scene)
            case TurnRules.Transition.OpenTradeInventory(partnerId)     =>
                PhaseTransitions.enterTradeInventory(partnerId, scene)
            case TurnRules.Transition.TradeCancel                       =>
                PhaseTransitions.enterActionSelectFromTrade(scene)
            case TurnRules.Transition.GatherOpenMenu                    =>
                ActionMenuScene.openFromGather(scene)
            case TurnRules.Transition.GatherCancel                      =>
                PlayerScene.cancelSelection(scene)
        }
}
