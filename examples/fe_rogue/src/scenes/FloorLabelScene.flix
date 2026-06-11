/// FloorLabelScene — 現在の階層を画面左上に常時表示する HUD ラベル（例: "3F", "10F"）。
///
/// 階層が変わるとき（次フロアへ進む / ゲームオーバーで 1F へ戻る）は
/// `GameLifecycle.buildPlayingScene` がシーンごと作り直されるため、
/// このラベルのテキストは構築時に一度だけ設定すればよく、毎フレームの更新は不要。
/// そのため process ディスパッチも専用 NodeTag も持たず、ノードはすべて NodeTag.NoTag で置く。
///
/// ノード構造（layer=4）:
///   FloorLabel (CanvasLayer, NodeTag.NoTag)
///     └─ text (Label2D, NodeTag.NoTag)
mod FloorLabelScene {

    def rootName(): String = "FloorLabel"
    def textChildName(): String = "text"
    def textPath(): NodePath = rootName() :: textChildName() :: Nil

    def fontName(): String = "ui"
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/FloorLabelScene.scene.json")

    /// `floorLabel` は `FloorCatalog.FloorResource#label`（"1F" / "10F" 等）をそのまま渡す。
    /// 2 桁フロアでも崩れないよう、scene.json 側で十分な左マージンと文字サイズを確保している。
    pub def add(floorLabel: String, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                       SceneLoader.constTagParser(NodeTag.NoTag),
                                       scene)
            |> Label2D.mapAt(textPath(), Label2D.setText(floorLabel))
}
