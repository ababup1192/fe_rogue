/// CursorScene — 味方ターン中の選択カーソル（Marker2D + 子 Sprite2D）
///
/// FE 風 SRPG の「カーソルでマスを選んでから操作」フローを担う。
/// 味方ターンの開始時はこのカーソルが画面上で動き、味方マス上で Z を押せば
/// 選択 → 移動フェーズに切り替わる（カーソルは非表示・Player の WASD 移動に
/// バトンタッチ）。敵マス上ではカーソルは止まらず、ホバー中だけ赤い移動範囲を
/// 表示する（実体は EnemyRangeScene が担当）。
///
/// ノード構造（Player と並列のトップレベル）:
///   Cursor (Marker2D, NodeTag.Cursor(Data))
///     └─ Sprite (Sprite2D, cursor.png)
///
/// 設計意図:
///   - 親 Marker2D に位置と論理状態（gridPos / lastHoveredEnemyId）を持たせ、
///     子 Sprite2D は表示専用にする。Player と同じ構造で統一感を維持する
///   - `gridPos` は moveStep のたびに即更新し、見た目の補間は engine の Tween に委ねる
///     （Player.moveTo と完全に同じ機構）。Tween 中は次の方向キーをブロックする
///   - 敵ホバー検知は「フレーム間でカーソルが乗っている敵 id が変化したか」で判定する。
///     `lastHoveredEnemyId` を Data に持ち、変化したフレームだけログ + 範囲再構築を発火する。
///     同じ敵に乗りっぱなしの間は何もしない（ログ・再構築の無限ループ回避）
///   - 表示/非表示は親 Marker2D の `visible` フラグで切り替える。子 Sprite は
///     親子可視性 AND で連動して消える（`drawContextWalk` の挙動）
mod CursorScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カーソル固有の状態。
    /// `gridPos`: カーソルが指している論理マス。moveStep で即更新される
    /// `lastHoveredEnemyId`: 直前フレームでカーソルが乗っていた敵 id。
    ///   None ↔ Some(id) や Some(a) ↔ Some(b) の遷移をログ・赤レンジ再構築の
    ///   トリガーに使う。同じ id の間は no-op に倒すためのキャッシュ。
    /// `holdDir`: 直前フレームに方向キーが押されていた向き。None ↔ Some の遷移と
    ///   別方向への切替で `holdSteps` を 0 にリセットする。
    /// `holdSteps`: 同方向に連続で進んだマス数。`computeSlideDuration` で
    ///   1 マス分のスライド時間を初速 → 最高速に補間するのに使う。
    /// 駒（味方/敵）に乗ったときの「引っかかり」は AnimationPlayer の `snag` 空アニメ
    /// で表現する。`AnimationPlayer.Scheduler.isPlaying(cursorPath())` が true の間は
    /// 方向入力を捨てる。`snag` アニメ完了 + Tween 完了で次の移動が始まる。
    pub type alias Data = {
        gridPos            = {x = Int32, y = Int32},
        lastHoveredEnemyId = Option[Int32],
        holdDir            = Option[{x = Int32, y = Int32}],
        holdSteps          = Int32
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Cursor"
    pub def cursorPath(): NodePath = name() :: Nil
    /// 子 Sprite ノード名 (scene.json で参照されている)。未使用 (構築は scene.json 経由) だが
    /// 将来 sprite path を組む際に使えるよう残す
    def _spriteName(): String = "Sprite"

    /// `cursor.png` テクスチャ名（Main.flix の textureManifest と整合）
    /// `cursor.png` テクスチャ名は scene.json に書かれている (sprite ノードの texture フィールド)。
    /// この constant は参照されないが、ドキュメント目的で残す。
    def _textureName(): String = "cursor"

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える
    def tileSize(): Float64 = 16.0

    /// カーソルの描画 zIndex。Player Sprite (= 10) より更に上に表示し、
    /// 駒の上に被せても視認できるようにする。
    /// scene.json で sprite.zIndex として記述済み。コード参照用に残す (未使用)
    def _spriteZIndex(): Int32 = 20

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
    /// 「引っかかった」感触になる長さ。
    def snagDuration(): Duration.Duration = 150 |> Duration.millis

    /// `snag` アニメーション。tracks / methods を持たない純粋なタイマー用途で、
    /// `AnimationPlayer.Scheduler.isPlaying(cursorPath())` がこの長さの間 true を返す。
    def snagAnimation(): AnimationPlayer.Animation =
        {
            name    = AnimEvent.tagToString(AnimEvent.Tag.Snag),
            length  = snagDuration(),
            tracks  = Nil,
            methods = Nil
        }

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
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// シーン定義 JSON のパス。Marker2D Cursor + 子 Sprite2D (cursor.png, zIndex=20) の
    /// 構造を持つ。位置はパーティ先頭プレイヤーから計算するため post-load で setPosition する。
    /// Cursor(Data) は Data を含むため scene.json では復元できず post-load で setState する。
    def scenePath(): String = "src/scenes/CursorScene.scene.json"

    /// MapScene + PlayerScene 登録済みの scene にカーソルを追加する。
    /// 初期位置はパーティ先頭プレイヤー（id=0）と同じセル。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let initial = firstPlayerPos(scene);
        let pos = cellCenter(initial);
        let data: Data = {
            gridPos            = initial,
            lastHoveredEnemyId = None,
            holdDir            = None,
            holdSteps          = 0
        };
        SceneLoader.loadScene(scenePath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> Scene.setState(cursorPath(), NodeTag.Cursor(data))
            // Marker2D は EngineNode に mapMarker2D ヘルパーが無いので直接 match で position 更新
            |> Scene.mapEngineNode(cursorPath(), n -> match n {
                case EngineNode.Marker2DWithState(marker, st) =>
                    EngineNode.Marker2DWithState(Node2D.setPosition(pos, marker), st)
                case other => other
            })

    /// パーティ先頭プレイヤー（id=0）の grid 位置。`add` 初期化用。
    def firstPlayerPos(scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        match PlayerScene.get(0, scene) {
            case Some(d) => d#gridPos
            case None    => {x = 0, y = 0}
        }

    /// グリッド座標 → セル中心ピクセル座標（MapScene の mapToLocal 慣習に揃える）
    def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 毎フレーム engine から呼ばれる `physicsProcess`。
    /// `PlayerCursor` フェーズのみ動かす（Game.flix が NodeTag マッチで dispatch する）。
    /// 入力ゲートは 3 段:
    ///   1. `snag` アニメ再生中 → 駒上での「引っかかり」中。入力捨てる
    ///   2. Tween 中 → 補間中。入力捨てる
    ///   3. それ以外 → 方向キーを読み、加速度を計算して 1 マス進める
    /// 移動後のセルに駒（味方/敵）が居れば `snag` を再生 + holdSteps をリセット
    /// （次は再加速）。敵に乗ったら EnemyRangeScene を再構築 + ログを出す（既存）。
    pub def physicsProcess(_delta: Duration.Duration,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery,
                               Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)) =>
                if (AnimationPlayer.Scheduler.isPlaying(cursorPath())) (node, scene)
                else if (Tween.Scheduler.isActive(cursorPath())) (node, scene)
                else
                    match readHeldDirection() {
                        case None =>
                            // キーが離れたら hold 状態をリセット（再度押したときに初速から）
                            let nextData = {holdDir = None, holdSteps = 0 | data};
                            (EngineNode.Marker2DWithState(marker,
                                                           NodeTag.Cursor(nextData)),
                             scene)
                        case Some(dir) =>
                            let board = BoardQuery.board();
                            let nextSteps = stepCountAfter(data#holdDir,
                                                            data#holdSteps, dir);
                            let target = clampToMap(Vec2i.add(data#gridPos, dir),
                                                     board#map);
                            if (target#x == data#gridPos#x and target#y == data#gridPos#y) {
                                // 端で動けない。hold 状態だけ更新して入力は捨てる。
                                let nextData = {holdDir = Some(dir),
                                                  holdSteps = nextSteps | data};
                                (EngineNode.Marker2DWithState(marker,
                                                               NodeTag.Cursor(nextData)),
                                 scene)
                            }
                            else {
                                let slide = computeSlideDuration(nextSteps);
                                let (newMarker, movedData) =
                                    moveStep(target, marker, data, slide);
                                let (hovered, updatedScene) =
                                    handleHoverChange(movedData, board, scene);
                                let onPiece = Board.isOccupied(target, board);
                                if (onPiece) AnimationPlayer.play(cursorPath(), snagAnimation())
                                else ();
                                let finalData = applyHoldUpdate(hovered, dir,
                                                                 nextSteps, onPiece);
                                (EngineNode.Marker2DWithState(newMarker,
                                                                NodeTag.Cursor(finalData)),
                                 updatedScene)
                            }
                    }
            case _ => (node, scene)
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
    /// 駒の上に乗ったら holdSteps を 0 に戻す（snag アニメ再生で停止 → 再加速）。
    /// 駒が居なければ holdSteps をそのまま nextSteps に進める。
    def applyHoldUpdate(data: Data, dir: {x = Int32, y = Int32}, nextSteps: Int32,
                         onPiece: Bool): Data =
        if (onPiece)
            {holdDir = Some(dir), holdSteps = 0 | data}
        else
            {holdDir = Some(dir), holdSteps = nextSteps | data}

    /// カーソルを 1 マス移動させる。gridPos は即更新、見た目は Tween に委ねる。
    /// 隣接判定は呼び出し側が済ませている前提（target は data.gridPos + 4 方向単位）。
    /// `slideDuration` 引数で 1 マス分のスライド時間を可変にする（加速制御）。
    /// `lastHoveredEnemyId` / `holdDir` などは呼び出し側で更新するためここでは触らない。
    def moveStep(target: {x = Int32, y = Int32}, marker: Marker2D, data: Data,
                  slideDuration: Duration.Duration):
            (Marker2D, Data) \ Tween.Scheduler =
        let startWorld = cellCenter(data#gridPos);
        let targetWorld = cellCenter(target);
        Tween.tweenPosition(cursorPath(), startWorld, targetWorld, slideDuration);
        (marker, {gridPos = target | data})

    /// 移動後のセルに敵が居るかを判定し、`lastHoveredEnemyId` の遷移に応じて
    /// EnemyRangeScene を出し入れ + ログを出す。返り値の Data は
    /// `lastHoveredEnemyId` を新しい値に更新済み。呼び出し側は **これを** Cursor
    /// ノードの NodeTag に詰めて返す（foldNodes が EngineNode を path に書き戻すため、
    /// `mapCursor` で scene 経由に書いても上書きされてしまう）。
    def handleHoverChange(data: Data, board: Board,
                           scene: Scene[NodeTag]):
            (Data, Scene[NodeTag]) \ GameLogger.GameLogger =
        let enemyId = enemyIdAt(data#gridPos, board);
        if (enemyId == data#lastHoveredEnemyId) (data, scene)
        else
            let nextScene = match enemyId {
                case Some(id) =>
                    GameLogger.playerLog("敵${id}を捕捉");
                    EnemyRangeScene.refreshFor(id, scene)
                case None =>
                    EnemyRangeScene.clear(scene)
            };
            ({lastHoveredEnemyId = enemyId | data}, nextScene)

    /// 押されている方向キーを Option で返す（PlayerScene と同じ優先順位で揃える）
    def readHeldDirection(): Option[{x = Int32, y = Int32}] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2i.up())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2i.down())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2i.left())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2i.right())
        else None

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
    // (D-2) 攻撃フェーズ用 polling
    // ────────────────────────────────────────────────────────

    /// `PlayerAttack` フェーズ専用の `physicsProcess`。
    /// 通常の `physicsProcess` と違い:
    ///   - clamp は赤マス（PlayerAttackRangeScene）+ **選択中プレイヤー自身のマス**
    ///     → 範囲外のセルへ移動しようとしても動かない。フェーズ突入時のスナップ先
    ///       （選択中プレイヤーマス）に戻れるよう、そのマスも通行可とする
    ///   - 敵 hover 検知は不要（このフェーズでは EnemyRangeScene を出さない）
    ///   - snag は **敵のみ** に発動（選択中味方マスは「戻り場」なので引っかからない）。
    ///     EnemyScene.findIdAt で直接判定して BoardQuery 依存を避ける
    /// 加速ロジック（hold steps + computeSlideDuration）は `physicsProcess` と共通。
    ///
    /// Game.flix が NodeTag マッチで dispatch する。
    pub def physicsProcessAttack(_delta: Duration.Duration,
                                  node: EngineNode[NodeTag],
                                  _path: NodePath,
                                  scene: Scene[NodeTag]):
                                 (EngineNode[NodeTag], Scene[NodeTag])
                                 \ {GameEngine.Game,
                                     Tween.Scheduler, AnimationPlayer.Scheduler,
                                     SelectedPlayer.State} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)) =>
                if (AnimationPlayer.Scheduler.isPlaying(cursorPath())) (node, scene)
                else if (Tween.Scheduler.isActive(cursorPath())) (node, scene)
                else
                    match readHeldDirection() {
                        case None =>
                            let nextData = {holdDir = None, holdSteps = 0 | data};
                            (EngineNode.Marker2DWithState(marker,
                                                           NodeTag.Cursor(nextData)),
                             scene)
                        case Some(dir) =>
                            let candidate = Vec2i.add(data#gridPos, dir);
                            let isSelectedCell = isSelectedPlayerCell(candidate, scene);
                            let nextSteps = stepCountAfter(data#holdDir,
                                                            data#holdSteps, dir);
                            // 赤マス内 OR 選択中プレイヤー自身のマスのみ移動可。
                            if (not (PlayerAttackRangeScene.isInRange(candidate, scene)
                                     or isSelectedCell)) {
                                let nextData = {holdDir = Some(dir),
                                                  holdSteps = nextSteps | data};
                                (EngineNode.Marker2DWithState(marker,
                                                               NodeTag.Cursor(nextData)),
                                 scene)
                            }
                            else {
                                let slide = computeSlideDuration(nextSteps);
                                let (newMarker, movedData) =
                                    moveStep(candidate, marker, data, slide);
                                let onEnemy =
                                    not Option.isEmpty(EnemyScene.findIdAt(candidate, scene));
                                if (onEnemy) AnimationPlayer.play(cursorPath(), snagAnimation())
                                else ();
                                let finalData = applyHoldUpdate(movedData, dir,
                                                                 nextSteps, onEnemy);
                                (EngineNode.Marker2DWithState(newMarker,
                                                                NodeTag.Cursor(finalData)),
                                 scene)
                            }
                    }
            case _ => (node, scene)
        }

    /// `cell` が選択中プレイヤーの位置と一致するか。
    /// 未選択（None）の場合は false。
    def isSelectedPlayerCell(cell: {x = Int32, y = Int32},
                              scene: Scene[NodeTag]): Bool \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None     => false
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case Some(d) =>
                        d#gridPos#x == cell#x and d#gridPos#y == cell#y
                    case None    => false
                }
        }

    /// 指定セルに居る敵の id を返す（居なければ None）
    def enemyIdAt(coord: {x = Int32, y = Int32}, board: Board): Option[Int32] =
        Board.enemyPositions(board)
            |> List.findMap(entry -> {
                let (id, pos) = entry;
                if (pos#x == coord#x and pos#y == coord#y) Some(id) else None
            })

    // ────────────────────────────────────────────────────────
    // (E) フェーズ切替に伴う見た目操作
    // ────────────────────────────────────────────────────────

    /// カーソルの可視性を切り替える。Marker2D の visible を変えれば子 Sprite も
    /// 親子可視性 AND で同じ状態になる（`drawContextWalk` の挙動）
    pub def setVisible(visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(cursorPath(),
            n -> CanvasItem.setVisible(visible, n), scene)

    /// カーソルを「選択中プレイヤー」または最初のアクティブプレイヤーの位置にスナップさせ、
    /// ホバー状態をリセットする。
    /// 敵ターン突入時 / キャンセル復帰時 / プレイヤー移動完了時に呼んで、
    /// 「次にカーソル選択フェーズに戻ったとき味方の上から始まる」状態を作る。
    pub def snapToPlayer(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              SelectedPlayer.State} =
        let target = snapTargetPos(scene);
        let world = cellCenter(target);
        // 進行中の Tween / snag アニメをキャンセルして即座に位置を確定させる。
        Tween.Scheduler.cancel(cursorPath());
        AnimationPlayer.Scheduler.stop(cursorPath());
        let snapped = Scene.setGlobalPositionAt(cursorPath(), world, scene);
        mapCursor((m, d) ->
            (m, {gridPos            = target,
                 lastHoveredEnemyId = None,
                 holdDir            = None,
                 holdSteps          = 0 | d}),
            snapped)

    /// snap 先のセルを決める:
    ///   1. 選択中プレイヤーがあればそれ
    ///   2. なければアクティブな最初のプレイヤー
    ///   3. それも無ければ id=0 (waited 含む)
    def snapTargetPos(scene: Scene[NodeTag]): {x = Int32, y = Int32} \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case Some(d) => d#gridPos
                    case None    => fallbackPos(scene)
                }
            case None => fallbackPos(scene)
        }

    /// 選択無し時の fallback: 最初のアクティブ、または id=0。
    def fallbackPos(scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        let active = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#waited);
        match List.head(active) {
            case Some(d) => d#gridPos
            case None    =>
                match PlayerScene.get(0, scene) {
                    case Some(d) => d#gridPos
                    case None    => {x = 0, y = 0}
                }
        }

    // ────────────────────────────────────────────────────────
    // (F) ボイラプレート — pattern match を関数化
    // ────────────────────────────────────────────────────────

    /// Cursor の Marker2D と Data をまとめて変換する。
    pub def mapCursor(f: (Marker2D, Data) -> (Marker2D, Data),
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(cursorPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Cursor(newData))
            case other => other
        }, scene)

    /// Cursor の Data を取り出す。未登録なら bug!（add 後に呼ぶ前提）。
    pub def getCursorData(scene: Scene[NodeTag]): Data =
        match Scene.getState(cursorPath(), scene) {
            case Some(NodeTag.Cursor(data)) => data
            case _ => bug!("CursorScene: cursor not found at ${cursorPath()}")
        }

    /// カーソルの現在グリッド座標。
    pub def getGridPos(scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        getCursorData(scene)#gridPos
}
