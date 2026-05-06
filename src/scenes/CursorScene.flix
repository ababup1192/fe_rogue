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
    pub type alias Data = {
        gridPos            = Vec2.Vec2i,
        lastHoveredEnemyId = Option[Int32]
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Cursor"
    pub def cursorPath(): NodePath = name() :: Nil
    def spriteName(): String = "Sprite"

    /// `cursor.png` テクスチャ名（Main.flix の textureManifest と整合）
    def textureName(): String = "cursor"

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える
    def tileSize(): Float64 = 16.0

    /// カーソルの描画 zIndex。Player Sprite (= 10) より更に上に表示し、
    /// 駒の上に被せても視認できるようにする。
    def spriteZIndex(): Int32 = 20

    /// 1 マス分のスライド時間（秒）。プレイヤー (16/120 ≒ 0.133) より高速にして、
    /// FE のカーソルらしいキビキビ感を出す。
    def slideDuration(): Float64 = 16.0 / 240.0   // ≈ 0.067 秒

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene 登録済みの scene にカーソルを追加する。
    /// 初期位置はパーティ先頭プレイヤー（id=0）と同じセル。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let initial = firstPlayerPos(scene);
        let pos = cellCenter(initial);
        let marker = Marker2D.make(pos);
        let sprite = Sprite2D.make(textureName(), Vec2.zero(), Vec2.one())
                        |> CanvasItem.setZIndex(spriteZIndex());
        let data: Data = { gridPos = initial, lastHoveredEnemyId = None };
        scene
            |> Scene.addNode(name(),
                              EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)))
            |> Scene.addChild(name(), spriteName(),
                               EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// パーティ先頭プレイヤー（id=0）の grid 位置。`add` 初期化用。
    def firstPlayerPos(scene: Scene[NodeTag]): Vec2.Vec2i =
        match PlayerScene.get(0, scene) {
            case Some(d) => d#gridPos
            case None    => {x = 0, y = 0}
        }

    /// グリッド座標 → セル中心ピクセル座標（MapScene の mapToLocal 慣習に揃える）
    def cellCenter(cell: Vec2.Vec2i): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2.fromI(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 毎フレーム engine から呼ばれる `physicsProcess`。
    /// `PlayerCursor` フェーズのみ動かす（Game.flix が NodeTag マッチで dispatch する）。
    /// Tween 中なら入力を捨て、そうでなければ方向キーで 1 マス分の移動を試み、
    /// 移動後のセルに敵が居れば `EnemyRangeScene` を再構築 + ログを出す。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery, Tween.Scheduler,
                               GameLogger.GameLogger} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)) =>
                if (Tween.Scheduler.isActive(cursorPath())) (node, scene)
                else
                    match readHeldDirection() {
                        case None => (node, scene)
                        case Some(dir) =>
                            let board = BoardQuery.board();
                            let target = clampToMap(Vec2.addI(data#gridPos, dir),
                                                     board#map);
                            if (target#x == data#gridPos#x and target#y == data#gridPos#y)
                                (node, scene)   // 端で動けない
                            else {
                                let (newMarker, movedData) =
                                    moveStep(target, marker, data);
                                let (finalData, updatedScene) =
                                    handleHoverChange(movedData, board, scene);
                                (EngineNode.Marker2DWithState(newMarker,
                                                                NodeTag.Cursor(finalData)),
                                 updatedScene)
                            }
                    }
            case _ => (node, scene)
        }

    /// カーソルを 1 マス移動させる。gridPos は即更新、見た目は Tween に委ねる。
    /// 隣接判定は呼び出し側が済ませている前提（target は data.gridPos + 4 方向単位）。
    /// `lastHoveredEnemyId` は呼び出し側で再評価するためここでは触らない。
    def moveStep(target: Vec2.Vec2i, marker: Marker2D, data: Data):
            (Marker2D, Data) \ Tween.Scheduler =
        let startWorld = cellCenter(data#gridPos);
        let targetWorld = cellCenter(target);
        Tween.tweenPosition(cursorPath(), startWorld, targetWorld, slideDuration());
        (marker, {gridPos = target, lastHoveredEnemyId = data#lastHoveredEnemyId})

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
                    GameLogger.GameLogger.playerLog("敵${id}を捕捉");
                    EnemyRangeScene.refreshFor(id, scene)
                case None =>
                    EnemyRangeScene.clear(scene)
            };
            ({lastHoveredEnemyId = enemyId | data}, nextScene)

    /// 押されている方向キーを Option で返す（PlayerScene と同じ優先順位で揃える）
    def readHeldDirection(): Option[Vec2.Vec2i] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2.upI())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2.downI())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2.leftI())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2.rightI())
        else None

    /// 候補セルをマップの usedRect 内にクランプする。FE と同じく壁・敵・味方マスは
    /// 通り抜け可能（カーソルは情報表示専用なので地形に縛られない）。
    def clampToMap(coord: Vec2.Vec2i, map: MapSnapshot): Vec2.Vec2i =
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
    ///
    /// Game.flix が NodeTag マッチで dispatch する。
    pub def physicsProcessAttack(_delta: Float64,
                                  node: EngineNode[NodeTag],
                                  _path: NodePath,
                                  scene: Scene[NodeTag]):
                                 (EngineNode[NodeTag], Scene[NodeTag])
                                 \ {GameEngine.Game, Tween.Scheduler,
                                     SelectedPlayer.State} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Cursor(data)) =>
                if (Tween.Scheduler.isActive(cursorPath())) (node, scene)
                else
                    match readHeldDirection() {
                        case None      => (node, scene)
                        case Some(dir) =>
                            let candidate = Vec2.addI(data#gridPos, dir);
                            let isSelectedCell = isSelectedPlayerCell(candidate, scene);
                            // 赤マス内 OR 選択中プレイヤー自身のマスのみ移動可。
                            if (not (PlayerAttackRangeScene.isInRange(candidate, scene)
                                     or isSelectedCell))
                                (node, scene)
                            else {
                                let (newMarker, movedData) =
                                    moveStep(candidate, marker, data);
                                (EngineNode.Marker2DWithState(newMarker,
                                                                NodeTag.Cursor(movedData)),
                                 scene)
                            }
                    }
            case _ => (node, scene)
        }

    /// `cell` が選択中プレイヤーの位置と一致するか。
    /// 未選択（None）の場合は false。
    def isSelectedPlayerCell(cell: Vec2.Vec2i,
                              scene: Scene[NodeTag]): Bool \ SelectedPlayer.State =
        match SelectedPlayer.State.get() {
            case None     => false
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case Some(d) =>
                        d#gridPos#x == cell#x and d#gridPos#y == cell#y
                    case None    => false
                }
        }

    /// 指定セルに居る敵の id を返す（居なければ None）
    def enemyIdAt(coord: Vec2.Vec2i, board: Board): Option[Int32] =
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
            Scene[NodeTag] \ {Tween.Scheduler, SelectedPlayer.State} =
        let target = snapTargetPos(scene);
        let world = cellCenter(target);
        // 進行中の Tween をキャンセルして即座に位置を確定させる。
        Tween.Scheduler.cancel(cursorPath());
        let snapped = Scene.setGlobalPositionAt(cursorPath(), world, scene);
        mapCursor((m, d) ->
            (m, {gridPos = target, lastHoveredEnemyId = None | d}),
            snapped)

    /// snap 先のセルを決める:
    ///   1. 選択中プレイヤーがあればそれ
    ///   2. なければアクティブな最初のプレイヤー
    ///   3. それも無ければ id=0 (waited 含む)
    def snapTargetPos(scene: Scene[NodeTag]): Vec2.Vec2i \ SelectedPlayer.State =
        match SelectedPlayer.State.get() {
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case Some(d) => d#gridPos
                    case None    => fallbackPos(scene)
                }
            case None => fallbackPos(scene)
        }

    /// 選択無し時の fallback: 最初のアクティブ、または id=0。
    def fallbackPos(scene: Scene[NodeTag]): Vec2.Vec2i =
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
    pub def getGridPos(scene: Scene[NodeTag]): Vec2.Vec2i =
        getCursorData(scene)#gridPos
}
