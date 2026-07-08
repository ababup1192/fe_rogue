/// CursorScene — 味方ターン中の選択カーソル（入力ポーリング＋論理・視覚状態の駆動）
///
/// FE 風 SRPG の「カーソルでマスを選んでから操作」フローを担う。
/// 味方ターンの開始時はこのカーソルが画面上で動き、味方マス上で Z を押せば
/// 選択 → 移動フェーズに切り替わる（カーソルは非表示・Player の WASD 移動に
/// バトンタッチ）。敵マス上ではカーソルは止まらず、ホバー中だけ赤い移動範囲を
/// 表示する（実体は EnemyRangeScene が担当）。
///
/// 状態と描画の分担:
///   - カーソルは scene ノードを持たない。論理状態（gridPos / hover / hold）も視覚位置
///     （renderPos / スライド補間 / snag タイマー / 可視）も `CursorState.State` resource が権威。
///   - 四隅の角カッコ L字（白）は `RenderWorld.renderCursor` が `CursorState.renderPos` と
///     `cornerBoxes` から直描きする（camera 適用）。見た目定数 `cornerColor` / `cornerZIndex` /
///     `cornerBoxes` はこの module が持つ唯一の真実源。カメラ追従（`CameraScene`）も renderPos を読む。
///
/// 設計意図:
///   - `gridPos` は moveStep のたびに即更新し、見た目の補間は `CursorState` の EcsTween に委ねる。
///     補間中（`CursorState.isTweening`）は次の方向キーをブロックする。
///   - 敵ホバー検知は「フレーム間でカーソルが乗っている敵 id が変化したか」で判定する。
///     `lastHoveredEnemyId` を持ち、変化したフレームだけログ + 範囲再構築を発火する。
///     同じ敵に乗りっぱなしの間は何もしない（ログ・再構築の無限ループ回避）。
///   - 駒に乗った「引っかかり」は `CursorState.snagRemaining`（`beginSnag` で秒セット・`step` で減衰）で
///     表現し、`CursorState.isSnagging` が true の間は方向入力を捨てる。
///   - 表示/非表示は `CursorState.visible` で切り替え、`renderCursor` がそれを読んで L字を出す/出さない。
///
/// 入力ポーリング（`step`）は engine の physicsProcess 巡回でなく gameLoop が明示 System として
/// 1 回呼ぶ（カーソルは scene ノードを持たないため）。
mod CursorScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カーソルの論理・視覚状態は `CursorState.State` resource が持つ。helper と外部（テスト）の
    /// 型参照用に別名を再輸出する。フィールドの意味は `CursorState.Data` の定義を参照。
    pub type alias Data = CursorState.Data

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// 四隅 L字の色（白）。`RenderWorld.renderCursor` が直描きに使う唯一の真実源。
    pub def cornerColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// カーソルの描画 zIndex。駒 (= 10) / HP バー (UnitHPBarRender = 50〜52) /
    /// 武器アイコン (WeaponIconRender = 60〜62) より更に上に表示し、選択マスを常に
    /// 最前面で視認できるようにする (HUD/メニューは CanvasLayer なので更に上)。
    pub def cornerZIndex(): Int32 = 70

    /// 四隅 L字を構成する 8 枚の白ボックス。各要素はセル中心からの左上オフセットと px サイズを持つ。
    /// 隅ごとに横 1 本 + 縦 1 本で L字を作る。`RenderWorld.renderCursor` がこの並びをそのまま
    /// camera 適用して box Drawable にする。
    pub def cornerBoxes(): List[{offset = Vec2.Vec2, size = Vec2.Vec2}] =
        {offset = {x = -15.0, y = -15.0}, size = {x = 9.0, y = 2.0}} ::   // 左上 横
        {offset = {x = -15.0, y = -15.0}, size = {x = 2.0, y = 9.0}} ::   // 左上 縦
        {offset = {x =   6.0, y = -15.0}, size = {x = 9.0, y = 2.0}} ::   // 右上 横
        {offset = {x =  13.0, y = -15.0}, size = {x = 2.0, y = 9.0}} ::   // 右上 縦
        {offset = {x = -15.0, y =  13.0}, size = {x = 9.0, y = 2.0}} ::   // 左下 横
        {offset = {x = -15.0, y =   6.0}, size = {x = 2.0, y = 9.0}} ::   // 左下 縦
        {offset = {x =   6.0, y =  13.0}, size = {x = 9.0, y = 2.0}} ::   // 右下 横
        {offset = {x =  13.0, y =   6.0}, size = {x = 2.0, y = 9.0}} ::   // 右下 縦
        Nil

    /// 動き出し（押した直後の 1 マス目）のスライド時間。最高速より遅くして、
    /// 「ぽんと押したら一瞬の溜めの後に動く」 FE 風のフィーリングを出す。
    def initialSlideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 100)   // ≈ 0.160 秒

    /// 押しっぱなしのときに収束する最高速。プレイヤー (16/120 ≒ 0.133) より高速で、
    /// 連続移動時のキビキビ感を担保する。
    def minSlideDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 240)   // ≈ 0.067 秒

    /// 最高速に達するまでの連続ステップ数。0 → initial、>= stepsToMaxSpeed → min。
    /// 間は線形補間（computeSlideDuration）。
    def stepsToMaxSpeed(): Int32 = 3

    /// 駒（味方/敵）のマスに乗った後、入力を捨てる長さ（150 ミリ秒）。
    /// 最高速 1 マス（0.067 秒）の 2 倍強で、押しっぱなしのリズムから明確にズレて
    /// 「引っかかった」感触になる長さ。`CursorState.beginSnag` に秒で渡す。
    def snagDuration(): Duration.Duration = 150 |> Duration.millis

    /// `snag` 引っかかりを `CursorState` にセットする（駒に乗ったフレームで呼ぶ）。
    def playSnag(): Unit \ CursorState.State =
        CursorState.beginSnag(Duration.toSeconds(snagDuration()))

    /// `holdSteps` から 1 マス分のスライド時間を線形補間する。
    /// 0 ステップなら初速、stepsToMaxSpeed 以上で最高速に張り付く。
    def computeSlideDuration(steps: Int32): Duration.Duration =
        if (steps >= stepsToMaxSpeed()) minSlideDuration()
        else
            let t = Int32.toFloat64(steps) / Int32.toFloat64(stepsToMaxSpeed());
            let initSec = Duration.toSeconds(initialSlideDuration());
            let minSec  = Duration.toSeconds(minSlideDuration());
            (initSec + (minSec - initSec) * t) |> Duration.seconds

    // ────────────────────────────────────────────────────────
    // (C) 初期化（resource seed・scene ノードは持たない）
    // ────────────────────────────────────────────────────────

    /// `CursorState` をパーティ先頭プレイヤー（id=0）のセルで初期化する。scene ノードは積まない
    /// （視覚位置は resource の renderPos が権威で `RenderWorld.renderCursor` が直描き）。
    /// フロア構築時に呼ばれ、初期セル / renderPos を seed する。
    pub def add(): Unit \ {CursorState.State, World.WorldQuery} =
        let initial = firstPlayerPos();
        let pos = MapSnapshot.cellCenter(initial);
        CursorState.State.put({gridPos            = initial,
                               lastHoveredEnemyId = None,
                               holdDir            = None,
                               holdSteps          = 0,
                               renderPos          = pos,
                               tweens             = Map.empty(),
                               snagRemaining      = 0.0,
                               visible            = true})

    /// パーティ先頭プレイヤー（id=0）の grid 位置。`add` 初期化用。World store から直接読む。
    def firstPlayerPos(): {x = Int32, y = Int32} \ World.WorldQuery =
        match PlayerScene.get(0) {
            case Some(d) => d#gridPos
            case None    => {x = 0, y = 0}
        }

    // ────────────────────────────────────────────────────────
    // (D) ロジック — phase 分岐エントリ（gameLoop が明示 System として毎フレ 1 回呼ぶ）
    // ────────────────────────────────────────────────────────

    /// カーソルの入力ポーリング。現フェーズで挙動が変わるため、`TurnPhase.State.get()` で
    /// 4 種類の polling に振り分ける:
    ///   - `PlayerCursor`      → `stepFreeMovement` (4 方向に 1 マスずつスライド)
    ///   - `WeaponSelect`      → `stepWeaponSelectCycle` (フォーカス武器が届く敵を巡回)
    ///   - `PlayerAttack`      → `stepTargetCycle`  (射程内の敵リスト上をジャンプ)
    ///   - `TradeTargetSelect` → `stepTradeCellCycle` (緑マス間サイクル)
    /// それ以外のフェーズ (`PlayerMoving` / `EnemyTurn` 等) では何もしない。
    /// 盤面（Map）の存在は前提とする（本番配線は `stepOnBoard` が Map 存在をゲートしてから呼ぶ。
    /// 単体テストは mock BoardQuery とともに直接呼ぶ fail-open な seam）。
    pub def step(_delta: Duration.Duration):
                Unit
                \ {GameEngine.Game, BoardQuery,
                    GameLogger.GameLogger,
                    EnemyData.RosterQuery, TurnPhase.State,
                    SelectedPlayer.State, CursorState.State, World.WorldQuery,
                    UiWorldState.State, RangeOverlayState.State} =
        match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerCursor       => stepFreeMovement()
            case TurnPhase.Phase.WeaponSelect       => stepWeaponSelectCycle()
            case TurnPhase.Phase.PlayerAttack       => stepTargetCycle()
            case TurnPhase.Phase.TradeTargetSelect  => stepTradeCellCycle()
            case _                                  => ()
        }

    /// gameLoop 用の入力 polling 入口。カーソルは盤面オーバーレイなので、盤面（Map）がある画面で
    /// のみ `step` を回す。盤面レス画面（Title / CharacterSelect 等）は TurnPhase が
    /// `PlayerCursor` のままでも no-op — `stepFreeMovement` が `BoardQuery` 経由で地形を
    /// 読むため、盤面未 seed のまま進むと bug! する（Minimap.step と同じ存在ゲート）。
    pub def stepOnBoard(delta: Duration.Duration):
                        Unit
                        \ {GameEngine.Game, BoardQuery,
                            GameLogger.GameLogger,
                            EnemyData.RosterQuery, TurnPhase.State,
                            SelectedPlayer.State, CursorState.State, World.WorldQuery,
                            UiWorldState.State, RangeOverlayState.State} =
        if (World.hasBoard(World.WorldQuery.get())) step(delta)
        else ()

    /// `WeaponSelect` フェーズの左右ターゲットサイクル。フォーカス中の武器が届く生存敵を
    /// reading order で巡回する（上下は武器リストへ回るので触らない）。入力ゲート・サイクル本体は
    /// `PlayerAttack` と同じ機構（`cycleToTargetIn`）を、対象リストだけ差し替えて使う。
    def stepWeaponSelectCycle():
                              Unit
                              \ {GameEngine.Game, SelectedPlayer.State, CursorState.State,
                                 EnemyData.RosterQuery, World.WorldQuery, UiWorldState.State} =
        if (CursorState.isSnagging()) ()
        else if (CursorState.isTweening()) ()
        else {
            let data = CursorState.State.get();
            match (data#holdDir, readHeldHorizontal()) {
                case (_, None) =>
                    CursorState.State.put({holdDir = None, holdSteps = 0 | data})
                case (Some(_), Some(dir)) =>
                    CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})
                case (None, Some(dir)) =>
                    cycleToTargetIn(weaponSelectTargets(), dir, data)
            }
        }

    /// フォーカス中の武器が届く生存敵を reading order（y→x）で返す。
    /// 選択中味方 / フォーカス武器が取れないときは空。
    def weaponSelectTargets():
            List[EnemyScene.Data] \ {SelectedPlayer.State, EnemyData.RosterQuery, World.WorldQuery, UiWorldState.State} =
        let opt = forM (
            pid    <- SelectedPlayer.State.get()#id;
            // 位置・在庫（weapons）は World 権威＝dataFromWorld（scene 非依存）で読む。
            player <- World.dataFromWorld(pid, World.WorldQuery.get());
            widx   <- WeaponSelectUi.hoveredWeaponIndex();
            weapon <- List.nth(widx, player#weapons)
        ) yield
            // 敵 Data は RosterQuery overlay（World-fresh の hp/isDying）で読む（scene 直読みは stale）。
            EnemyData.RosterQuery.getAll()
                |> List.filter(e -> {
                    let ev = EnemyScene.unitView(e);
                    ev#hp > 0 and not ev#isDying
                        and Weapon.inRange(Weapon.manhattan(player#gridPos, ev#pos), weapon#range)
                })
                |> List.sortBy(e -> (e#gridPos#y, e#gridPos#x));
        Option.getWithDefault(Nil, opt)

    // ────────────────────────────────────────────────────────
    // (D-1) PlayerCursor フェーズの 1 マス進行
    // ────────────────────────────────────────────────────────

    /// `PlayerCursor` フェーズの本体。入力ゲートは 3 段:
    ///   1. snag 引っかかり中 → 入力捨てる
    ///   2. 補間中 → 入力捨てる
    ///   3. それ以外 → 方向キーを読み、加速度を計算して 1 マス進める
    /// 移動後のセルに駒（味方/敵）が居れば snag をセット + holdSteps をリセット
    /// （次は再加速）。敵に乗ったら EnemyRangeScene を再構築 + ログを出す。
    def stepFreeMovement():
                         Unit
                         \ {GameEngine.Game, BoardQuery,
                             GameLogger.GameLogger,
                             EnemyData.RosterQuery, SelectedPlayer.State, CursorState.State, World.WorldQuery,
                             RangeOverlayState.State} =
        if (CursorState.isSnagging()) ()
        else if (CursorState.isTweening()) ()
        else {
            let data = CursorState.State.get();
            match readHeldDirection() {
                case None =>
                    // キーが離れたら hold 状態をリセット（再度押したときに初速から）
                    CursorState.State.put({holdDir = None, holdSteps = 0 | data})
                case Some(dir) =>
                    let board = BoardQuery.board();
                    let nextSteps = stepCountAfter(data#holdDir, data#holdSteps, dir);
                    // マップ端で clamp したうえで、可動域（明るい部屋+半径 ∪ 既訪）外なら
                    // 据え置く。target == gridPos なら下の「端で動けない」分岐が発火する。
                    let candidate = clampToMap(Vec2i.add(data#gridPos, dir), board#map);
                    let target = if (cursorCanEnter(candidate)) candidate
                                 else data#gridPos;
                    if (target#x == data#gridPos#x and target#y == data#gridPos#y)
                        // 端で動けない。hold 状態だけ更新して入力は捨てる。
                        CursorState.State.put({holdDir = Some(dir), holdSteps = nextSteps | data})
                    else {
                        let slide = computeSlideDuration(nextSteps);
                        let movedData = moveStep(target, data, slide);
                        let hovered = handleHoverChange(movedData, board);
                        // フォグで隠れている敵では snag させない（一瞬の引っかかりで
                        // 見えない敵の位置がバレるのを防ぐ）。可視の駒のみ引っかける。
                        let onPiece = isVisiblyOccupied(target, board);
                        if (onPiece) playSnag() else ();
                        CursorState.commitLogical(applyHoldUpdate(hovered, dir, nextSteps, onPiece))
                    }
            }
        }

    /// 直前の `holdDir` と新しい方向から、ステップ数を更新する。
    /// 同方向継続なら +1、別方向 or 初回なら 0 にリセット。
    def stepCountAfter(prev: Option[{x = Int32, y = Int32}], steps: Int32,
                        dir: {x = Int32, y = Int32}): Int32 =
        match prev {
            case Some(p) =>
                if (p#x == dir#x and p#y == dir#y) steps + 1 else 0
            case None => 0
        }

    /// 移動成立後の Data に hold 関連を反映する。
    /// 駒の上に乗ったら holdSteps を 0 に戻す（snag で停止 → 再加速）。
    /// 駒が居なければ holdSteps をそのまま nextSteps に進める。
    def applyHoldUpdate(data: Data, dir: {x = Int32, y = Int32}, nextSteps: Int32,
                         onPiece: Bool): Data =
        if (onPiece)
            {holdDir = Some(dir), holdSteps = 0 | data}
        else
            {holdDir = Some(dir), holdSteps = nextSteps | data}

    /// カーソルを 1 マス移動させる。gridPos は即更新、見た目は `CursorState` の EcsTween に委ねる。
    /// 隣接判定は呼び出し側が済ませている前提（target は data.gridPos + 4 方向単位）。
    /// `slideDuration` 引数で 1 マス分のスライド時間を可変にする（加速制御）。
    /// `lastHoveredEnemyId` / `holdDir` などは呼び出し側で更新するためここでは触らない。
    def moveStep(target: {x = Int32, y = Int32}, data: Data,
                  slideDuration: Duration.Duration): Data \ CursorState.State =
        let startWorld = MapSnapshot.cellCenter(data#gridPos);
        let targetWorld = MapSnapshot.cellCenter(target);
        CursorState.startMove(startWorld, targetWorld, Duration.toSeconds(slideDuration));
        {gridPos = target | data}

    /// 移動後のセルに敵が居るかを判定し、`lastHoveredEnemyId` の遷移に応じて
    /// EnemyRangeScene を出し入れ + ログを出す。返り値の Data は
    /// `lastHoveredEnemyId` を新しい値に更新済み。
    def handleHoverChange(data: Data, board: Board):
            Data \ {GameLogger.GameLogger, EnemyData.RosterQuery, SelectedPlayer.State, World.WorldQuery, RangeOverlayState.State} =
        // フォグで隠れている敵はホバーしても情報を出さない（配置バレ防止）。
        // 見えていない敵セルは「敵が居ない」扱いに倒し、ログ・赤レンジを発火させない。
        let enemyId = enemyIdAt(data#gridPos, board)
                        |> Option.filter(id -> EnemyScene.isVisible(id));
        if (enemyId == data#lastHoveredEnemyId) data
        else {
            match enemyId {
                case Some(id) =>
                    GameLogger.playerLog("${EnemyScene.displayName(id)}を捕捉");
                    // 移動範囲(白)を先に組み、その reachable を読んで攻撃到達範囲(赤)を重ねる
                    EnemyRangeScene.refreshFor(id);
                    EnemyAttackRangeScene.refreshFor(id)
                case None =>
                    EnemyRangeScene.clear();
                    EnemyAttackRangeScene.clear()
            };
            {lastHoveredEnemyId = enemyId | data}
        }

    /// 押されている方向キーを Option で返す（PlayerScene と同じ優先順位で揃えることで
    /// プレイヤー操作とカーソル操作の体感を統一する）
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None

    /// 押されている **左右** 方向キーだけを返す (PlayerAttack のターゲットサイクル用)。
    /// 上下は武器リスト (ItemMenu の focused ItemList ナビ) に回すため無視する。
    def readHeldHorizontal(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None

    /// 明るい部屋の外周からカーソルが踏み出せるタイル数（可動域の余白）。tunable。
    /// カメラはカーソルを追従するため、この値を小さくするほどカーソル/カメラが
    /// fog の手前で止まり、未踏の部屋がカメラに映り込まなくなる。
    def cursorRangeRadius(): Int32 = 1

    /// 候補セルがカーソルの可動域（明るい部屋 +半径 ∪ 訪問済み module）に入っているか。
    /// 範囲は FogScene.cursorRangeRects（明るい部屋を半径拡張 ∪ 既訪 module 矩形）で求め、
    /// 既訪記憶は World（`MinimapScene.visitedModules`）から読む。
    def cursorCanEnter(cell: {x = Int32, y = Int32}): Bool \ World.WorldQuery =
        let world0     = World.WorldQuery.get();
        let placements = World.placementsOf(world0);
        // マップ情報が無い（= 単体テスト等）なら制限しない（fail-open: カーソルを固めない）。
        if (List.isEmpty(placements)) true
        else {
            let roomCount = World.roomCountOf(world0);
            let visited   = MinimapScene.visitedModules();
            let rects = FogScene.cursorRangeRects(PlayerScene.getAll(), placements,
                                                   roomCount, visited, cursorRangeRadius());
            // 可動域がまだ算出できないフレームでも固めない（防御的）。
            List.isEmpty(rects) or FogScene.insideAny(cell, rects)
        }

    /// 候補セルをマップの usedRect 内にクランプする。FE と同じく壁・敵・味方マスは
    /// 通り抜け可能（カーソルは情報表示専用なので地形に縛られない）。
    def clampToMap(coord: {x = Int32, y = Int32}, map: MapSnapshot): {x = Int32, y = Int32} =
        let r = map#usedRect;
        let minX = r#position#x;
        let minY = r#position#y;
        let maxX = r#position#x + r#size#x - 1;
        let maxY = r#position#y + r#size#y - 1;
        {x = Int32.max(minX, Int32.min(maxX, coord#x)),
         y = Int32.max(minY, Int32.min(maxY, coord#y))}

    // ────────────────────────────────────────────────────────
    // (D-2) PlayerAttack フェーズのターゲットサイクル
    // ────────────────────────────────────────────────────────

    /// `PlayerAttack` フェーズの本体。通常の 1 マス進行ではなく **「方向キー押下で射程内の敵に
    /// カーソルをジャンプさせる」** ターゲットサイクル方式。間接武器でも自然に敵を選べる。
    ///   - 押下開始フレームでのみサイクル発火。押しっぱなしの間は連続サイクルしない (誤連打防止)。
    ///   - **左 = 前の敵、右 = 次の敵** (reading order でソート)。上下は武器切り替えに回すので動かさない。
    ///   - 射程内に敵が居なければ何もしない (X キャンセル待ち)。スナップは補間で滑らかに移動。
    def stepTargetCycle():
                        Unit
                        \ {GameEngine.Game, CursorState.State, EnemyData.RosterQuery,
                            RangeOverlayState.State} =
        if (CursorState.isSnagging()) ()
        else if (CursorState.isTweening()) ()
        else {
            let data = CursorState.State.get();
            // 左右だけでターゲットを選ぶ (上下は武器リストへ)。
            match (data#holdDir, readHeldHorizontal()) {
                case (_, None) =>
                    CursorState.State.put({holdDir = None, holdSteps = 0 | data})
                case (Some(_), Some(dir)) =>
                    CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})
                case (None, Some(dir)) =>
                    cycleToTarget(dir, data)
            }
        }

    /// 押下開始時のターゲットサイクル本体。`PlayerAttackRangeScene.targetsInRange` で
    /// 取得した reading-order 順のリストから、方向に応じて prev / next を選ぶ。
    def cycleToTarget(dir: {x = Int32, y = Int32}, data: Data):
                      Unit
                      \ {CursorState.State, EnemyData.RosterQuery, RangeOverlayState.State} =
        cycleToTargetIn(PlayerAttackRangeScene.targetsInRange(), dir, data)

    /// 与えられた敵リストの中で、現在カーソル位置から方向に応じて prev / next へジャンプする。
    /// `cycleToTarget`（PlayerAttack）と `stepWeaponSelectCycle`（WeaponSelect）が対象リストだけ
    /// 差し替えて共有する本体。敵が居なければ holdDir だけ更新して何もしない。
    def cycleToTargetIn(targets: List[EnemyScene.Data],
                        dir: {x = Int32, y = Int32}, data: Data):
                       Unit \ CursorState.State =
        match targets {
            case Nil =>
                CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})
            case _   =>
                let n = List.length(targets);
                let curIdx = findCursorTargetIndex(data#gridPos, targets);
                // 上/左 = 前、下/右 = 次。curIdx == -1 のときは方向に応じて末尾 or 先頭。
                let step = if (dir#x < 0 or dir#y < 0) -1 else 1;
                let nextIdx =
                    if (curIdx < 0)
                        if (step > 0) 0 else n - 1
                    else
                        Int32.modulo(curIdx + step + n, n);
                match List.nth(nextIdx, targets) {
                    case None         =>
                        CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})
                    case Some(target) =>
                        let slide = computeSlideDuration(1);
                        let movedData = moveStep(target#gridPos, data, slide);
                        playSnag();
                        CursorState.commitLogical({holdDir = Some(dir), holdSteps = 1,
                                       lastHoveredEnemyId = Some(target#id) | movedData})
                }
        }

    /// targets リストの中で `cell` と一致する敵の index を返す。一致しなければ -1。
    /// 戻り値 -1 は呼び出し元で `curIdx < 0` として扱われ、方向に応じて先頭/末尾を選ぶ分岐に入る。
    def findCursorTargetIndex(cell: {x = Int32, y = Int32},
                                targets: List[EnemyScene.Data]): Int32 =
        let indexed = List.zipWithIndex(targets);
        match List.find(p -> {
            let (_, d) = p;
            d#gridPos#x == cell#x and d#gridPos#y == cell#y
        }, indexed) {
            case Some((i, _)) => i
            case None         => -1
        }

    // ────────────────────────────────────────────────────────
    // (D-3) TradeTargetSelect フェーズの 1 マス進行 (緑マス間サイクル)
    // ────────────────────────────────────────────────────────

    /// `TradeTargetSelect` フェーズの本体。緑マス (TradeRangeScene の隣接味方マス) を reading order で
    /// ソートして、方向キー押下の瞬間に prev / next の緑マスへサイクルでスナップする。
    /// 入力ゲートは PlayerAttack と同じ (snag / 補間中は捨てる)。
    /// 緑マスが 0 個 (= 隣接味方なし) のときは何もしない (X キャンセル待ち)。
    def stepTradeCellCycle():
                            Unit
                            \ {GameEngine.Game, CursorState.State, RangeOverlayState.State} =
        if (CursorState.isSnagging()) ()
        else if (CursorState.isTweening()) ()
        else {
            let data = CursorState.State.get();
            match (data#holdDir, readHeldDirection()) {
                case (_, None) =>
                    CursorState.State.put({holdDir = None, holdSteps = 0 | data})
                case (Some(_), Some(dir)) =>
                    CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})
                case (None, Some(dir)) =>
                    cycleToTradeCell(dir, data)
            }
        }

    /// 緑マスの中から方向に応じて next / prev のセルへカーソルを飛ばす。
    /// `TradeRangeScene.cells` を reading order (y → x) にソートしてサイクルする。
    /// 緑マスが空ならホールド状態だけ更新して何もしない。
    def cycleToTradeCell(dir: {x = Int32, y = Int32}, data: Data):
                         Unit \ {CursorState.State, RangeOverlayState.State} =
        let sortedCells = TradeRangeScene.cells()
                            |> List.sortBy(c -> (c#y, c#x));
        pickNextCellInCycle(dir, data#gridPos, sortedCells)
            |> Option.map(target -> snapCursorAndUpdateHold(target, dir, data))
            |> Option.getWithDefault(updateHoldOnly(dir, data))

    /// `sortedCells` を方向 (dir) でサイクルし、prev / next のセルを返す。
    /// 上 / 左 = 前、下 / 右 = 次。現在位置がセル外なら、方向に応じて先頭 / 末尾を返す。
    /// セルが空なら None。
    def pickNextCellInCycle(dir: {x = Int32, y = Int32},
                              curPos: {x = Int32, y = Int32},
                              sortedCells: List[{x = Int32, y = Int32}]):
                             Option[{x = Int32, y = Int32}] =
        if (List.isEmpty(sortedCells)) None
        else {
            let n = List.length(sortedCells);
            let curIdx = findCursorCellIndex(curPos, sortedCells);
            let step = if (dir#x < 0 or dir#y < 0) -1 else 1;
            let nextIdx =
                if (curIdx < 0)
                    if (step > 0) 0 else n - 1
                else
                    Int32.modulo(curIdx + step + n, n);
            List.nth(nextIdx, sortedCells)
        }

    /// 目標セルへ補間でスライドし、snag セット + holdDir 更新まで一気に行う。
    def snapCursorAndUpdateHold(target: {x = Int32, y = Int32},
                                  dir: {x = Int32, y = Int32}, data: Data):
                                 Unit \ CursorState.State =
        let slide = computeSlideDuration(1);
        let movedData = moveStep(target, data, slide);
        playSnag();
        CursorState.commitLogical({holdDir = Some(dir), holdSteps = 1 | movedData})

    /// セル移動できなかったとき (空 / 範囲外) の戻り値: holdDir だけ更新して据え置き。
    def updateHoldOnly(dir: {x = Int32, y = Int32}, data: Data): Unit \ CursorState.State =
        CursorState.State.put({holdDir = Some(dir), holdSteps = 1 | data})

    /// セルリストの中で `cell` と一致するセルの index を返す。一致しなければ -1。
    def findCursorCellIndex(cell: {x = Int32, y = Int32},
                              cells: List[{x = Int32, y = Int32}]): Int32 =
        let indexed = List.zipWithIndex(cells);
        match List.find(p -> {
            let (_, c) = p;
            c#x == cell#x and c#y == cell#y
        }, indexed) {
            case Some((i, _)) => i
            case None         => -1
        }


    /// target セルに「見えている駒」が居るか。味方は常に可視。敵はフォグで隠れていれば
    /// 居ないものとして扱う（カーソルの snag が見えない敵の位置を漏らさないように）。
    def isVisiblyOccupied(coord: {x = Int32, y = Int32}, board: Board):
            Bool \ {SelectedPlayer.State, World.WorldQuery} =
        if (not Board.isOccupied(coord, board)) false
        else match enemyIdAt(coord, board) {
            case Some(id) => EnemyScene.isVisible(id)
            case None     => true
        }

    /// 指定セルに居る敵の id を返す（居なければ None）。
    /// Board.enemyPositions のみを参照するため味方は対象外。同セルに2体以上いるケースは想定外。
    def enemyIdAt(coord: {x = Int32, y = Int32}, board: Board): Option[Int32] =
        Board.enemyPositions(board)
            |> List.findMap(entry -> {
                let (id, pos) = entry;
                if (pos#x == coord#x and pos#y == coord#y) Some(id) else None
            })

    // ────────────────────────────────────────────────────────
    // (E) フェーズ切替に伴う見た目操作
    // ────────────────────────────────────────────────────────

    /// カーソルの可視性を切り替える。`CursorState.visible` を書き、
    /// `RenderWorld.renderCursor` がそれを読んで四隅 L字を描く/描かないを決める。
    pub def setVisible(visible: Bool): Unit \ CursorState.State =
        CursorState.setVisible(visible)

    /// フェーズごとに通常カーソルが表示されるべきかの**単一の真理点**。
    /// 下表の「ゲームプレイ復帰フェーズ」の `enter*` は
    /// `setVisible(cursorVisibleForPhase(<自フェーズ>), …)` でこの値を直接使う。
    /// 「カーソルを出し忘れて操作不能な半端状態に陥る」バグの種を表に集約してテストで
    /// 封じるための **テスタビリティ／ロック**。
    ///
    /// 対象（gameplay-return / input・`enter*` が通常カーソルの setVisible を書く）:
    ///   PlayerCursor / PlayerAttack（表示）, PlayerMoving / GatherMove / ItemSelect /
    ///   LevelUpView / StairsExit（非表示）。
    /// 非対象: PlayerCursorAt（snap 専用・同値）, StaffAim / ThrowAim（矢印カーソル）,
    ///   TradeInventory / GatherTrade / TradeTargetSelect（交換メニュー）, AttackForecast /
    ///   EnemyTurn（カーソル Keep）。これらは自前 setVisible リテラルを持ち
    ///   onActionCancelled の戻り先ではないためこの関数を呼ばない。
    /// `case _` は **到達不能**。新フェーズの `enter*` がこの関数を呼ぶのに表へ
    /// 追加し忘れたら **bug! で大声で落ちる**よう全域化する。
    pub def cursorVisibleForPhase(phase: TurnPhase.Phase): Bool =
        match phase {
            case TurnPhase.Phase.PlayerCursor => true
            case TurnPhase.Phase.PlayerAttack => true
            case TurnPhase.Phase.PlayerMoving => false
            case TurnPhase.Phase.GatherMove   => false
            case TurnPhase.Phase.ItemSelect   => false
            case TurnPhase.Phase.LevelUpView  => false
            case TurnPhase.Phase.StairsExit   => false
            case other => bug!("cursorVisibleForPhase: 非対象フェーズ ${other} で呼ばれた（表に未登録）")
        }

    /// カーソルを「選択中プレイヤー」または最初のアクティブプレイヤーの位置にスナップさせ、
    /// ホバー状態をリセットする。敵ターン突入時 / キャンセル復帰時 / プレイヤー移動完了時に呼んで、
    /// 「次にカーソル選択フェーズに戻ったとき味方の上から始まる」状態を作る。
    ///
    /// 注意: `PartyQuery` は `Game.start` の `sceneRef` (フレーム冒頭の snapshot) を読むため、
    /// フレーム内で `setWaited` した直後に呼ぶケースではここのフォールバックが「いま
    /// waited にした駒」を active として拾ってしまう。そうしたパス
    /// (= `commitWaitedAndAdvance`) からは `PhaseTransitions.enterPlayerCursorAt` 経由で
    /// 明示的に snap 先座標を渡し、この関数を経由しないようにする。
    pub def snapToPlayer():
            Unit \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery} =
        let target = snapTargetPos();
        snapToCell(target)

    /// 任意のグリッドセルへ瞬時にカーソルを移動させる。補間 / snag を止めて
    /// hoveredEnemyId と hold 状態を初期化する。`snapToPlayer` の汎用版。
    pub def snapToCell(target: {x = Int32, y = Int32}):
            Unit \ CursorState.State =
        let world = MapSnapshot.cellCenter(target);
        // 論理状態を初期化しつつ、視覚位置を瞬間 set（補間/snag も止める）。
        let d = CursorState.State.get();
        CursorState.State.put({gridPos            = target,
                               lastHoveredEnemyId = None,
                               holdDir            = None,
                               holdSteps          = 0,
                               renderPos          = world,
                               tweens             = Map.empty(),
                               snagRemaining      = 0.0 | d})

    /// `PlayerAttack` フェーズ突入時に、赤マス内に居る「生きている敵」が居れば最初の
    /// 敵にカーソルをスナップする。敵が居なければ選択中プレイヤーへ。
    /// 間接武器 (range > 1) の場合、自分のセルが赤マスに含まれないため
    /// `snapToPlayer` 単独では「カーソルが届かない場所に居る」状態になるのを防ぐ。
    pub def snapToFirstTargetOrPlayer():
            Unit \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery,
                              EnemyData.RosterQuery, RangeOverlayState.State} =
        match List.head(PlayerAttackRangeScene.targetsInRange()) {
            case Some(target) => snapToCell(target#gridPos)
            case None         => snapToPlayer()
        }

    /// `TradeTargetSelect` フェーズ突入時に、緑マスの **最初の隣接味方マス**
    /// (reading order: y 昇順 → x 昇順) にカーソルをスナップする。
    /// 緑マスが空 (= 隣接味方なし) のときは選択中プレイヤー位置にフォールバックする。
    pub def snapToFirstTradeCellOrPlayer():
            Unit \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery,
                              RangeOverlayState.State} =
        let firstCell = TradeRangeScene.cells()
                          |> List.sortBy(c -> (c#y, c#x))
                          |> List.head;
        match firstCell {
            case Some(cell) => snapToCell(cell)
            case None       => snapToPlayer()
        }

    /// snap 先のセルを決める:
    ///   1. 選択中プレイヤーがあればそれ
    ///   2. なければアクティブな最初のプレイヤー
    ///   3. それも無ければ id=0 (waited 含む)
    def snapTargetPos(): {x = Int32, y = Int32}
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                match PlayerData.PartyQuery.get(id) {
                    case Some(d) => d#gridPos
                    case None    => fallbackPos()
                }
            case None => fallbackPos()
        }

    /// 選択無し時の fallback: 最初のアクティブ、または id=0。
    def fallbackPos(): {x = Int32, y = Int32} \ PlayerData.PartyQuery =
        let active = PlayerData.PartyQuery.getAll()
            |> List.filter(d -> not d#waited);
        match List.head(active) {
            case Some(d) => d#gridPos
            case None    =>
                match PlayerData.PartyQuery.get(0) {
                    case Some(d) => d#gridPos
                    case None    => {x = 0, y = 0}
                }
        }

    // ────────────────────────────────────────────────────────
    // (F) 論理状態アクセサ（CursorState resource 経由）
    // ────────────────────────────────────────────────────────

    /// カーソルの論理状態を resource から取り出す。
    pub def getCursorData(): Data \ CursorState.State =
        CursorState.State.get()

    /// カーソルの現在グリッド座標。
    pub def getGridPos(): {x = Int32, y = Int32} \ CursorState.State =
        CursorState.State.get()#gridPos

    /// gameLoop が毎フレーム 1 回呼ぶ視覚 tick。スライド補間を dt 進め renderPos を書き、snag を減らす。
    /// カーソルの補間と引っかかりは CursorState resource が値で持つ。
    pub def stepVisual(dt: Duration.Duration): Unit \ CursorState.State =
        CursorState.step(Duration.toSeconds(dt))
}
