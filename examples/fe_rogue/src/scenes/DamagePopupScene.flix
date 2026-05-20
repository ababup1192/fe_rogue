/// DamagePopupScene — 攻撃ヒット時にユニット頭上で数字を浮かす HUD
///
/// 攻撃 / 反撃が当たった瞬間に被弾側のグリッド位置から `5` のようなダメージ量を
/// Label2D で出し、上方向に少し移動しながら寿命満了で消える。LogScene の文字列
/// 「P1 → 敵2 に 5ダメージ」と冗長になるが、戦場上で直感的にダメージ量を見せる
/// のが目的。
///
/// ノード構造:
///   DamagePopups (Marker2D, NodeTag.DamagePopupsRoot({nextSeq}))   永続
///     ├─ Popup_0 (Label2D, NodeTag.DamagePopup({remaining, total, startY}))
///     ├─ Popup_1 (Label2D, ...)
///     └─ ...                                                       寿命付き
///
/// 親 Marker2D は World 配下の (0,0) に 1 つだけ生やし、ゲームを通して再利用する。
/// 子 Label2D はヒット毎に動的に追加し、`tick` 毎フレーム呼び出しで寿命が尽きたら
/// `Scene.removeAt` で消す。子名は連番 `Popup_<seq>`（親 state の nextSeq）で衝突を避ける。
///
/// engine の Tween.tickAll に乗せない理由:
///   - Tween.tweenAlpha は Sprite2D 専用（engine/src/scene/Tween.flix）
///   - Label2D の modulate は {r,g,b} のみで alpha 成分を持たない（Color は engine_core）
///   フェード表現は省き、上方向に float させてから瞬時に消すスタイルにする。
///   寿命を 700ms 程度にすれば違和感は最小。
mod DamagePopupScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 親 Marker2D に紐づくデータ。子 Popup_<seq> の連番採番にだけ使う。
    pub type alias RootData = { nextSeq = Int32 }

    /// 各 Popup_<seq> Label2D に紐づくデータ。
    /// `remaining`: 残り寿命。tick で dt を引いていき、0 以下になったら削除。
    /// `total`:     初期寿命。経過比率の計算用（startY → 上方向への補間に使う）。
    /// `startY`:    生成時のワールド Y。経過比率から現在 Y を逆算する。
    pub type alias PopupData = {
        remaining = Duration.Duration,
        total     = Duration.Duration,
        startY    = Float64
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def rootName(): String = "DamagePopups"

    /// 親 Marker2D の NodePath。`World/DamagePopups` 固定。
    pub def rootPath(): NodePath = MapScene.worldName() :: rootName() :: Nil

    /// fontManifest で登録した name と一致させる（LogScene / ForecastPanelScene と同じ "ui"）
    def fontName(): String = "ui"

    /// 1 つのポップアップの寿命（出現 → 消滅まで）
    def lifetime(): Duration.Duration = Duration.millis(700)

    /// ポップアップが寿命中に上方向へ移動する総ピクセル数（論理 px）
    def floatDistancePx(): Float64 = 12.0

    /// Label2D の表示フォントサイズ。LDTK タイル 16px に対して読める粒度。
    def fontSize(): Float64 = 8.0

    /// 描画 zIndex。Player Sprite (= 10) より上に出す。
    def popupZIndex(): Int32 = 100

    /// プレイヤー攻撃 → 敵（被弾は敵）に使う色: 白
    pub def damageToEnemyColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 敵攻撃 → プレイヤー（被弾は味方）に使う色: 赤寄り
    pub def damageToPlayerColor(): Color = {r = 1.0f32, g = 0.4f32, b = 0.4f32}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// World 配下に親 Marker2D を 1 つだけ生やす。
    /// `Game.start` の Scene 構築チェーンで MapScene の後に挟む（World が必要）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addChildAt(MapScene.worldPath(), rootName(),
            EngineNode.Marker2DWithState(parent,
                NodeTag.DamagePopupsRoot({nextSeq = 0})),
            scene)

    /// 指定ワールド座標にダメージ数字をスポーンする。色は呼び出し側で
    /// `damageToEnemyColor()` / `damageToPlayerColor()` を選ぶ。
    /// 親が未登録（add 前）なら no-op。
    pub def emit(worldPos: Vec2.Vec2, damage: Int32, color: Color,
                   scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match Scene.getEngineNode(rootPath(), scene) {
            case Some(EngineNode.Marker2DWithState(parent, NodeTag.DamagePopupsRoot(root))) =>
                let seq = root#nextSeq;
                let atlas = GameEngine.Game.getFontAtlas(fontName());
                let label = Label2D.make("${damage}", atlas, fontSize())
                                |> Node2D.setPosition(worldPos)
                                |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
                                |> Label2D.setVerticalAlignment(VerticalAlignment.Bottom)
                                |> CanvasItem.setModulate(color)
                                |> CanvasItem.setZIndex(popupZIndex());
                let popupData: PopupData = {
                    remaining = lifetime(),
                    total     = lifetime(),
                    startY    = worldPos#y
                };
                scene
                    |> Scene.setEngineNode(rootPath(),
                        EngineNode.Marker2DWithState(parent,
                            NodeTag.DamagePopupsRoot({nextSeq = seq + 1})))
                    |> Scene.addChildAt(rootPath(), "Popup_${seq}",
                        EngineNode.Label2DWithState(label, NodeTag.DamagePopup(popupData)))
            case _ => scene
        }

    // ────────────────────────────────────────────────────────
    // (D) 毎フレーム更新
    // ────────────────────────────────────────────────────────

    /// 毎フレーム呼ぶ。各 Popup_<seq> の remaining を dt 分減らし、上方向に補間移動し、
    /// 寿命満了の子は `Scene.removeAt` で取り除く。`commonEpilogue` から呼ぶ。
    /// 親未登録なら no-op。
    pub def tick(dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag] =
        let childNames = Scene.getChildrenAt(rootPath(), scene);
        List.foldLeft(acc -> childName -> {
            let childPath = MapScene.worldName() :: rootName() :: childName :: Nil;
            match Scene.getEngineNode(childPath, acc) {
                case Some(EngineNode.Label2DWithState(label, NodeTag.DamagePopup(data))) =>
                    let newRemaining = Duration.subClampedToZero(data#remaining, dt);
                    if (Duration.isExpired(newRemaining))
                        Scene.removeAt(childPath, acc)
                    else {
                        // ratio: 0.0（生成直後）→ 1.0（寿命満了）
                        let elapsed = Duration.sub(data#total, newRemaining);
                        let ratio = Duration.ratio(elapsed, data#total);
                        let newY = data#startY - floatDistancePx() * ratio;
                        let currentPos = Node2D.getPosition(label);
                        let newPos: Vec2.Vec2 = {x = currentPos#x, y = newY};
                        let newLabel = label |> Node2D.setPosition(newPos);
                        let newData: PopupData = {remaining = newRemaining | data};
                        Scene.setEngineNode(childPath,
                            EngineNode.Label2DWithState(newLabel,
                                NodeTag.DamagePopup(newData)),
                            acc)
                    }
                case _ => acc
            }
        }, scene, childNames)
}
