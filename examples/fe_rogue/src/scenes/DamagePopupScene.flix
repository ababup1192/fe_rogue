/// DamagePopupScene — 攻撃ヒット時にユニット頭上で数字を浮かす HUD
///
/// 攻撃 / 反撃が当たった瞬間に被弾側のグリッド位置から `5` のようなダメージ量を
/// Label2D で出し、上方向に少し移動しながら寿命満了で消える。LogScene の文字列
/// 「P1 → 敵2 に 5ダメージ」と冗長になるが、戦場上で直感的にダメージ量を見せる
/// のが目的。
///
/// ノード構造:
///   DamagePopups (Marker2D, NodeTag.DamagePopupsRoot)   永続
///     ├─ Popup_0 (Label2D, NodeTag.DamagePopup)
///     ├─ Popup_1 (Label2D, ...)
///     └─ ...                                            寿命は World.popupFx が持つ
///
/// P5-b: 寿命・採番の権威は World の `popupFx` store（`Cmd.SpawnPopupFx` で spawn・
/// `stepWorld` が tick して期限切れを drop）。子 Label2D はテキスト/色/X を持つ描画 view で、
/// gameLoop が毎フレーム `syncView` で store から Y 補間と除去を派生する。
///
/// engine の Tween.tickAll に乗せない理由:
///   - Tween.tweenAlpha は Sprite2D 専用（engine/src/scene/Tween.flix）
///   - Label2D の modulate は {r,g,b} のみで alpha 成分を持たない（Color は engine_core）
///   フェード表現は省き、上方向に float させてから瞬時に消すスタイルにする。
///   寿命を 700ms 程度にすれば違和感は最小。
mod DamagePopupScene {

    def rootName(): String = "DamagePopups"

    /// 親 Marker2D の NodePath。`World/DamagePopups` として固定。
    pub def rootPath(): NodePath = MapScene.worldName() :: rootName() :: Nil

    /// fontManifest で登録した name。フォントアトラスはゲーム全体で共有されるため、
    /// LogScene / BattlePanelScene など他の UI シーンと同じ "ui" を指定しないと
    /// 実行時に別アトラスを要求してクラッシュする。
    def fontName(): String = "ui"

    /// 1 つのポップアップの寿命（出現 → 消滅まで）
    def lifetime(): Duration.Duration = Duration.millis(700)

    /// ポップアップが寿命中に上方向へ移動する総ピクセル数（論理 px）
    def floatDistancePx(): Float64 = 12.0

    /// Label2D の表示フォントサイズ。LDTK タイル 16px に対して読める粒度。
    def fontSize(): Float64 = 8.0

    /// 描画 zIndex。ゲームオブジェクト（スプライト・マップ）よりも前面に重ね、
    /// ダメージ数字がユニットや地形に埋もれないようにする。
    def popupZIndex(): Int32 = 100

    /// プレイヤー攻撃 → 敵（被弾は敵）に使う色: 白
    pub def damageToEnemyColor(): Color = UITheme.white()

    /// 敵攻撃 → プレイヤー（被弾は味方）に使う色: 赤寄り
    pub def damageToPlayerColor(): Color = {r = 1.0f32, g = 0.4f32, b = 0.4f32}

    /// World 配下に親 Marker2D を 1 つだけ生やす。
    /// `Game.start` の Scene 構築チェーンで MapScene の後に挟む（World が必要）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addChildAt(MapScene.worldPath(), rootName(),
            EngineNode.Marker2DWithState(parent, NodeTag.DamagePopupsRoot),  // P5-b: 採番は World へ
            scene)

    /// 指定ワールド座標にダメージ数字をスポーンする。色は呼び出し側で
    /// `damageToEnemyColor()` / `damageToPlayerColor()` を選ぶ。
    /// 親が未登録（add 前）なら no-op。
    pub def emit(worldPos: Vec2.Vec2, damage: Int32, color: Color,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag] \ {GameEngine.Game, World.Command, World.WorldQuery} =
        emitText(worldPos, "${damage}", color, scene)

    /// `emit` の文字列版。ダメージ数値の代わりに任意のテキスト（例: "miss"）を
    /// 同じ float-up 演出で浮かす。命中失敗時に呼び出し側が "miss" を出すのに使う。
    /// 親が未登録（add 前）なら no-op。
    /// P5-b: 寿命は `Cmd.SpawnPopupFx` で World の popupFx store へ（採番は applyCmd＝
    /// ここでは WorldQuery で次 seq を先読みして子ノード名を合わせる。emit→apply が即時
    /// 〔read-after-write〕なので連続 emit でも一致する）。子 Label2D は描画 view。
    pub def emitText(worldPos: Vec2.Vec2, text: String, color: Color,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag] \ {GameEngine.Game, World.Command, World.WorldQuery} =
        match Scene.getEngineNode(rootPath(), scene) {
            case Some(EngineNode.Marker2DWithState(_, NodeTag.DamagePopupsRoot)) =>
                let seq = World.popupFxNextSeqOf(World.WorldQuery.get());
                World.Command.emit(World.Cmd.SpawnPopupFx(
                    {total = Duration.toSeconds(lifetime()), startY = worldPos#y}));
                let atlas = GameEngine.Game.getFontAtlas(fontName());
                let label = Label2D.make(text, atlas, fontSize())
                                |> Node2D.setPosition(worldPos)
                                |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
                                |> Label2D.setVerticalAlignment(VerticalAlignment.Bottom)
                                |> CanvasItem.setModulate(color)
                                |> CanvasItem.setZIndex(popupZIndex());
                scene
                    |> Scene.addChildAt(rootPath(), "Popup_${seq}",
                        EngineNode.Label2DWithState(label, NodeTag.DamagePopup))
            case _ => scene
        }

    /// P5-b: gameLoop（stepWorld の後）から呼ばれる view 派生。World の popupFx store を読み、
    ///   1) 生存 seq の子 Label2D を経過比率で上方向に補間移動（Y のみ・X/テキスト/色はノード保持）
    ///   2) store に無い（期限切れで drop 済み）子を `Scene.removeAt` で除去
    /// する。寿命の tick はここでは行わない（stepWorld が権威）。親未登録なら no-op。
    pub def syncView(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let fx = World.popupFxOf(world);
        // 1) 生存 fx の Y を補間（子が無い場合〔フロア再構築直後等〕は mapAt が no-op）。
        let updated = Map.foldLeftWithKey((acc, seq, d) -> {
            let childPath = List.append(rootPath(), "Popup_${seq}" :: Nil);
            let ratio = (d#total - d#remaining) / d#total;
            let newY = d#startY - floatDistancePx() * ratio;
            Label2D.mapAt(childPath, label -> {
                let currentPos = Node2D.getPosition(label);
                label |> Node2D.setPosition({x = currentPos#x, y = newY})
            }, acc)
        }, scene, fx);
        // 2) store に無い子を除去（期限切れ）。
        let liveNames = Map.foldLeftWithKey((s, seq, _) -> Set.insert("Popup_${seq}", s), Set.empty(), fx);
        Scene.getChildrenAt(rootPath(), updated)
            |> List.foldLeft((acc, name) ->
                if (Set.memberOf(name, liveNames)) acc
                else Scene.removeAt(List.append(rootPath(), name :: Nil), acc), updated)
}
