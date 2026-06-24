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

    /// シーン定義 JSON のパス。Background / Characters CanvasLayer と各 Sprite2D を
    /// 全部 visible=false で並べた状態をエンジンが復元する。texture / visible の
    /// 動的書き換えは setBackground / showCharacter / hideCharacter が担当する。
    def sceneJsonPath(): String = "src/scenes/WorldScene.scene.json"

    // ════════════════════════════════════════════════════════════════════════
    // (C) 構築 — addWorldLayers
    // ════════════════════════════════════════════════════════════════════════

    /// 既存の Scene に背景レイヤとキャラレイヤを 1 枚ずつ追加する。
    /// 構造は WorldScene.scene.json から読み込み (Background / Characters の
    /// CanvasLayer + Sprite2D 群、すべて visible=false 初期状態)。
    /// NodeTag は WorldScene 領域では全部 NoTag なので constTagParser を使う。
    pub def addWorldLayers(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(sceneJsonPath(),
            SceneLoader.constTagParser(NodeTag.NoTag), scene)

    // ════════════════════════════════════════════════════════════════════════
    // (D) ロジック — テクスチャ差し替え／可視切替
    // ════════════════════════════════════════════════════════════════════════

    /// 背景テクスチャを `bg_<name>` に切り替え、レイヤを表示状態にする。
    /// 例: `setBackground("dungeon", scene)` → `bg_dungeon` テクスチャを表示。
    /// 未登録の名前を渡しても Sprite2D.mapAt が no-op になり story は止まらない。
    pub def setBackground(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let textureName = "bg_${name}";
        Sprite2D.mapAt(backgroundPath(), sprite ->
            sprite
                |> Sprite2D.setTexture(textureName)
                |> CanvasItem.setVisible(true),
            scene)

    /// 指定キャラ Sprite2D を visible=true にする。
    /// 知らない name は path が見つからず no-op になる。
    pub def showCharacter(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Sprite2D.mapAt(characterPath(name),
            sprite -> CanvasItem.setVisible(true, sprite), scene)

    /// 指定キャラ Sprite2D を visible=false にする。
    pub def hideCharacter(name: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        Sprite2D.mapAt(characterPath(name),
            sprite -> CanvasItem.setVisible(false, sprite), scene)

    /// 背景／キャラレイヤの CanvasLayer position に shake オフセットを書き込む。
    /// `<<shake>>` の毎フレーム適用用で、対話レイヤ（drawLayer=10）には影響させない
    /// （UI は安定したまま、ワールドだけが揺れる流儀）。
    pub def setShakeOffset(offset: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> CanvasLayer.mapAt(backgroundLayerName() :: Nil,
                cl -> CanvasLayer.setOffset(offset, cl))
            |> CanvasLayer.mapAt(charactersLayerName() :: Nil,
                cl -> CanvasLayer.setOffset(offset, cl))
}
