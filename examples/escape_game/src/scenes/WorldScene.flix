/// 背景レイヤとキャラレイヤを 1 枚ずつ Scene に追加するモジュール。
///
/// story.yarn の `<<bg ...>>` / `<<sprite show/hide ...>>` コマンドで切り替える表示の
/// 受け皿となる。状態は Sprite2D のテクスチャ名／可視フラグだけで足りるので NodeTag は
/// 拡張せず `NodeTag.NoTag` のまま、CommandRouter から `Scene.mapEngineNode` で
/// 直接書き換える方式を取る。
///
/// レイヤ構成:
///   CanvasLayer "Background" (drawLayer = 0)
///     └── Sprite2D "Bg" — 背景。`setBackground` でテクスチャ差し替え
///   CanvasLayer "Characters" (drawLayer = 5)
///     ├── Sprite2D "ou"     — 王
///     ├── Sprite2D "chest"  — たからばこ
///     └── Sprite2D "dragon" — ドラゴン
///
/// 対話レイヤ（DialogueScene, drawLayer = 10）よりも下のレイヤに置くことで、
/// 会話パネルが必ず最前面に被るようにしている。
mod WorldScene {

    // ════════════════════════════════════════════════════════════════════════
    // (B) Constants — ノード名・パス・配置
    // ════════════════════════════════════════════════════════════════════════

    def backgroundLayerName(): String = "Background"
    def backgroundSpriteName(): String = "Bg"

    def charactersLayerName(): String = "Characters"

    /// 背景スプライトへの NodePath。
    def backgroundPath(): NodePath =
        backgroundLayerName() :: backgroundSpriteName() :: Nil

    /// 指定キャラスプライトへの NodePath。
    def characterPath(name: String): NodePath =
        charactersLayerName() :: name :: Nil

    // 対話レイヤ（drawLayer = 10）より下に置く
    def backgroundDrawLayer(): Int32 = 0
    def charactersDrawLayer(): Int32 = 5

    /// 背景スプライトの中心位置（design 320×240 の中央）。centered=true なので
    /// 320×240 の画像がぴったり画面いっぱいに収まる。
    def backgroundCenter(): Vec2.Vec2 = {x = 160.0, y = 120.0}

    /// キャラの中心 X（design 中央）。Y は身長に応じてキャラごとに調整。
    def characterCenterX(): Float64 = 160.0

    // ════════════════════════════════════════════════════════════════════════
    // (C) 構築 — addWorldLayers
    // ════════════════════════════════════════════════════════════════════════

    /// 既存の Scene に背景レイヤとキャラレイヤを 1 枚ずつ追加する。
    /// 背景もキャラも初期状態は visible = false。
    /// 何も `<<bg>>` / `<<sprite show>>` が来ない間は何も描かれない。
    pub def addWorldLayers(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> addBackgroundLayer
            |> addCharactersLayer

    /// 背景用 CanvasLayer + 背景 Sprite2D 1 枚を追加する。
    def addBackgroundLayer(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(backgroundDrawLayer());
        let invisibleLayer = CanvasItem.setVisible(true, layer);
        let sprite =
            Sprite2D.make("", backgroundCenter(), {x = 1.0, y = 1.0})
                |> CanvasItem.setVisible(false);
        scene
            |> Scene.addNode(backgroundLayerName(),
                EngineNode.CanvasLayerWithState(invisibleLayer, NodeTag.NoTag))
            |> Scene.addChild(backgroundLayerName(), backgroundSpriteName(),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// キャラ用 CanvasLayer に story.yarn で使われる 3 体を invisible で並べる。
    /// `<<sprite show <name> ...>>` が来たタイミングで visible に切り替える。
    def addCharactersLayer(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(charactersDrawLayer());
        scene
            |> Scene.addNode(charactersLayerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> addCharacter("ou", "char_ou", {x = characterCenterX(), y = 80.0})
            |> addCharacter("chest", "char_chest", {x = characterCenterX(), y = 120.0})
            |> addCharacter("dragon", "char_dragon", {x = characterCenterX(), y = 80.0})

    /// キャラ 1 体を Sprite2D としてキャラレイヤ直下に追加する（初期 invisible）。
    def addCharacter(name: String, texture: String, position: Vec2.Vec2,
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        let sprite =
            Sprite2D.make(texture, position, {x = 1.0, y = 1.0})
                |> CanvasItem.setVisible(false);
        Scene.addChild(charactersLayerName(), name,
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), scene)

    // ════════════════════════════════════════════════════════════════════════
    // (D) ロジック — テクスチャ差し替え／可視切替
    // ════════════════════════════════════════════════════════════════════════

    /// 背景テクスチャを `bg_<name>` に切り替え、レイヤを表示状態にする。
    /// 例: `setBackground("dungeon", scene)` → `bg_dungeon` テクスチャを表示。
    /// 未登録の名前を渡しても Scene.mapEngineNode が no-op になり story は止まらない。
    pub def setBackground(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let textureName = "bg_${name}";
        Scene.mapEngineNode(backgroundPath(), engineNode ->
            engineNode
                |> EngineNode.mapSprite2D(sprite ->
                    sprite
                        |> Sprite2D.setTexture(textureName)
                        |> CanvasItem.setVisible(true)),
            scene)

    /// 指定キャラ Sprite2D を visible=true にする。
    /// 知らない name は path が見つからず no-op になる。
    pub def showCharacter(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(characterPath(name), engineNode ->
            EngineNode.mapSprite2D(sprite -> CanvasItem.setVisible(true, sprite),
                engineNode),
            scene)

    /// 指定キャラ Sprite2D を visible=false にする。
    pub def hideCharacter(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(characterPath(name), engineNode ->
            EngineNode.mapSprite2D(sprite -> CanvasItem.setVisible(false, sprite),
                engineNode),
            scene)

    /// 背景／キャラレイヤの CanvasLayer position に shake オフセットを書き込む。
    /// `<<shake>>` の毎フレーム適用用で、対話レイヤ（drawLayer=10）には影響させない
    /// （UI は安定したまま、ワールドだけが揺れる流儀）。
    pub def setShakeOffset(offset: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.mapEngineNode(backgroundLayerName() :: Nil, layer ->
                EngineNode.mapCanvasLayer(cl -> CanvasLayer.setOffset(offset, cl),
                    layer))
            |> Scene.mapEngineNode(charactersLayerName() :: Nil, layer ->
                EngineNode.mapCanvasLayer(cl -> CanvasLayer.setOffset(offset, cl),
                    layer))
}
