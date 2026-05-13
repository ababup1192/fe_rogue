// GroundScene — 地面タイルの構築・リサイクル
//
// 地面 1 枚分の構造は `GroundScene.scene.json` を PackedScene として読み込み、
// `PackedScene.instantiate` で N 枚に複製する。初期 2 枚もリサイクルの新タイルも
// 同じテンプレートを使うため、定義の重複が無い。
//
//   StaticBody2DWithState(body, Ground)
//     └── Sprite2DWithState(sprite, NoTag)

mod GroundScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// 地面グループ名（一括操作用）
    pub def groundGroup(): String = "grounds"

    /// 地面タイルの幅（px）。参考実装 168 の 2 倍
    def groundWidth(): Float64 = 336.0

    /// 地面タイルの高さ（px）。参考実装 56 の 2 倍
    def groundHeight(): Float64 = 112.0

    /// 地面の中心 Y 座標。画面下端(512) から高さの半分を引いた値
    pub def groundCenterY(): Float64 = 512.0 - groundHeight() / 2.0

    /// 地面の上端 Y 座標（鳥の位置クランプに使用）
    pub def groundTopY(): Float64 = 512.0 - groundHeight()

    // ========================================================================
    // シーン構築（PackedScene 経由）
    // ========================================================================

    /// 地面プレハブ JSON のパス
    def sceneJsonPath(): String = "src/scenes/GroundScene.scene.json"

    /// プレハブをロードする（毎回ファイル I/O が走るが、HotReload で
    /// 編集 → 次 spawn から反映されるという副作用がある）
    def loadTemplate(): PackedScene \ Fs.FileRead =
        PackedScene.load(sceneJsonPath())

    /// 1 枚を name + xCenter で spawn する。template を引数で受け取るので
    /// 連続 spawn でも load を 1 回にできる（addGrounds がそうしている）
    def spawnGroundFromTemplate(name: String, xCenter: Float64,
                                  template: PackedScene,
                                  scene: Scene[NodeTag]):
                                 Scene[NodeTag] \ {Fs.FileRead, GameEngine.Game} =
        let opts: InstantiateOpts = {
            parentPath = Nil,
            nameOverride = Some(name),
            positionOverride = Some({x = xCenter, y = groundCenterY()})
        };
        PackedScene.instantiate({
            opts = opts,
            tagParser = Game.parseNodeTag,
            template = template,
            fontAtlas = None,
            scene = scene
        })

    /// 初期地面タイルを配置する（2 枚で画面幅 + スクロールバッファをカバー）
    /// 画面外になったタイルの再配置は NodeRemovedHandler が担う
    pub def addGrounds(scene: Scene[NodeTag]): Scene[NodeTag] \ {Fs.FileRead, GameEngine.Game} =
        let template = loadTemplate();
        scene
            |> spawnGroundFromTemplate("ground_0", 168.0, template)
            |> spawnGroundFromTemplate("ground_1", 504.0, template)

    /// 地面グループ内の最右端 X 座標を返す（リサイクル位置決定に使用）
    def maxGroundX(scene: Scene[NodeTag]): Float64 =
        Scene.getNodesInGroup(groundGroup(), scene)
            |> List.map(p -> Scene.globalPositionAt(p, scene)#x)
            |> List.maximum
            |> Option.getWithDefault(0.0)

    /// リサイクル時に新タイルを spawn する
    /// 新タイルの X は現在の最右端 + groundWidth。ID は X 座標から導出
    pub def spawnRecycledGround(scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {Fs.FileRead, GameEngine.Game} =
        let template = loadTemplate();
        let nextX = maxGroundX(scene) + groundWidth();
        let id = Float64.tryToInt32(nextX) |> Option.getWithDefault(0);
        spawnGroundFromTemplate("ground_${id}", nextX, template, scene)

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// 地面タイルが画面左端を完全に通過したらノードを除去する
    /// 除去通知は NodeRemovedHandler が Recycle 効果に変換し、上位ハンドラが
    /// 最右端に新タイルを再スポーンする
    pub def process(node: EngineNode[NodeTag], path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.StaticBody2DWithState(_, NodeTag.Ground) =>
                let pos = Scene.globalPositionAt(path, scene);
                let halfWidth = groundWidth() / 2.0;
                if (pos#x + halfWidth < Game.getViewportLeftX(scene))
                    (node, Scene.removeAtAndNotify(path, scene))
                else
                    (node, scene)
            case _ => (node, scene)
        }
}
