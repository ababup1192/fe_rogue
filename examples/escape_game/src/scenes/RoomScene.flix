/// 部屋の背景 + クリック可能ホットスポット（Area2D）を 1 枚の CanvasLayer にまとめる Scene 層。
///
/// 設計意図:
///   - レイヤ root が `NodeTag.Room(Data)` を持ち、`Data#roomId` で
///     「いま何の部屋を表示しているか」を保持する
///   - 背景 Sprite2D は scene.json で 1 枚定義しておき、`enter` でテクスチャを差し替える
///   - **ホットスポット (Area2D + CollisionShape2D) も scene.json に静的に定義**する。
///     エディタ (F1) で位置・サイズを直接ドラッグ編集 → scene.json save → hot reload
///     で反映というワークフローを成立させるため (catalog 由来だと reload で巻き戻る)
///   - tag は `"Hotspot:<hotspotId>"` 規約。`tagParser` が roomId を補って
///     `NodeTag.Hotspot({roomId, hotspotId})` を作る
///   - クリックイベントは `Game.flix` の `InputHandler.onMouseButtonPressed` から
///     `AreaEvent.dispatchClicks` に流れ、`AreaHandler.onAreaClicked` に届く
///
/// レイヤ構成:
///   CanvasLayer "Room" (drawLayer = 5、Background=0 と Inventory=8 の間)
///     ├── Sprite2D "Bg"          — 部屋背景 (テクスチャは catalog から `enter` で注入)
///     └── Area2D "Hotspot_<id>"  — クリック対象 (NodeTag.Hotspot, scene.json 静的)
mod RoomScene {
    use Game.RoomState.{RoomId, HotspotId}

    // ════════════════════════════════════════════════════════════════════════
    // (A) 型定義 — NodeTag に乗せる Data
    // ════════════════════════════════════════════════════════════════════════

    /// 現在表示中の部屋 id。空文字は「未入場」（addRoomLayer 直後の状態）。
    pub type alias Data = { roomId = RoomId }

    /// `NodeTag.Hotspot` に乗せる「どの部屋のどのホットスポットか」。
    /// click 時に yarn ノード名を組み立てるための識別情報。
    pub type alias HotspotData = { roomId = RoomId, hotspotId = HotspotId }

    /// `NodeTag.Room` の初期値（未入場）。
    pub def emptyData(): Data = ({roomId = ""}: Data)

    // ════════════════════════════════════════════════════════════════════════
    // (B) 定数 — ノード名・パス
    // ════════════════════════════════════════════════════════════════════════

    /// レイヤノード名（scene.json と一致させる）。
    pub def layerName(): String = "Room"

    /// レイヤ root への NodePath。
    pub def layerPath(): NodePath = layerName() :: Nil

    /// 背景 Sprite2D の名前（scene.json と一致）。
    def bgName(): String = "Bg"

    /// 背景 Sprite2D への NodePath。
    def bgPath(): NodePath = layerName() :: bgName() :: Nil

    /// ホットスポット Area2D のノード名 prefix。
    /// scene.json で `Hotspot_<hotspotId>` の名前で定義する慣例。
    def areaNamePrefix(): String = "Hotspot_"

    /// scene.json の tag 文字列接頭辞。`Hotspot:<hotspotId>`。
    def hotspotTagPrefix(): String = "Hotspot:"

    /// 背景テクスチャ名生成（catalog の `bgTexture` に prefix `bg_` を付ける）。
    /// 例: `bgTexture = "demo_room"` → `"bg_demo_room"`。
    def bgTextureName(bgTexture: String): String = "bg_" + bgTexture

    /// scene.json のパス。
    def sceneJsonPath(): String = "src/scenes/RoomScene.scene.json"

    /// scene.json から「現在対象としている部屋 id」を tag 解決時にひも付けるためのフォールバック。
    /// scene.json 自体は roomId を含まないので、ロード時点では仮値 `""` を tag に乗せ、
    /// `enter` で `Data#roomId` を更新したタイミングで `applyHotspotTags` が
    /// 各 Hotspot の `data#roomId` を新しい値に上書きする。
    def initialHotspotRoomId(): RoomId = ""

    // ════════════════════════════════════════════════════════════════════════
    // (C) 構築 — addRoomLayer / tagParser
    // ════════════════════════════════════════════════════════════════════════

    /// scene.json の `tag` 文字列を `NodeTag` に変換する。
    ///   - None / "NoTag" → NodeTag.NoTag
    ///   - "Hotspot:<id>" → NodeTag.Hotspot({roomId = "", hotspotId = <id>})
    ///                       (roomId は `enter` で `applyHotspotTags` が後埋め)
    /// その他は Err でロード失敗させる (typo を黙って NoTag に流さない)。
    pub def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        use Json.JsonError.JsonError;
        use Json.Path.Path.Root;
        match opt {
            case None              => Ok(NodeTag.NoTag)
            case Some("NoTag")     => Ok(NodeTag.NoTag)
            case Some(s) =>
                if (String.startsWith({prefix = hotspotTagPrefix()}, s))
                    let id = String.takeRight(String.length(s) - String.length(hotspotTagPrefix()), s);
                    let data = ({roomId = initialHotspotRoomId(), hotspotId = id}: HotspotData);
                    Ok(NodeTag.Hotspot(data))
                else
                    Err(JsonError(Root,
                        Set#{"known tag (got: ${s}; expected NoTag or Hotspot:<id>)"}))
        }

    /// scene.json をロードしてレイヤを 1 枚積む。Root に `NodeTag.Room(emptyData())`
    /// を載せて、後続の `enter` で背景テクスチャと hotspot tag を更新する。
    pub def addRoomLayer(scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(sceneJsonPath(), tagParser, scene)
            |> Scene.setState(layerPath(), NodeTag.Room(emptyData()))

    // ════════════════════════════════════════════════════════════════════════
    // (D) ロジック — enter / yarnNodeNameFor
    // ════════════════════════════════════════════════════════════════════════

    /// `<<room enter <id>>>` の効果を Scene に適用する。
    ///   1. レイヤ root の Data#roomId を更新
    ///   2. 背景 Sprite2D のテクスチャを catalog の `bgTexture` に切替え（visible=true）
    ///   3. 各 Hotspot Area2D の Data#roomId を新しい部屋 id に書き換え
    ///      (Area2D の位置・サイズは scene.json 由来でそのまま、tag だけ更新)
    ///
    /// 未登録の roomId の場合は背景を invisible にして「空っぽ部屋」に整合させる。
    pub def enter(roomId: RoomId, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.setState(layerPath(), NodeTag.Room(({roomId = roomId}: Data)))
            |> applyBackground(roomId)
            |> applyHotspotTags(roomId)

    /// 部屋の背景テクスチャを catalog から引いて Sprite2D に反映する。
    /// 未登録 roomId は visible=false にして「何も描かない」状態にする。
    def applyBackground(roomId: RoomId, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Game.RoomCatalog.find(roomId) {
            case None       => mapBackgroundSprite(s -> CanvasItem.setVisible(false, s), scene)
            case Some(room) =>
                let textureName = bgTextureName(room#bgTexture);
                mapBackgroundSprite(s ->
                    s |> Sprite2D.setTexture(textureName)
                      |> CanvasItem.setVisible(true), scene)
        }

    /// scene.json から読み込んだ Hotspot タグの roomId を実際の部屋 id で上書きする。
    /// scene.json 単体ではどの部屋に属するか分からないので、`enter` のタイミングで
    /// この補完を行う (multi-room 対応で scene.json を分けるなら不要になる)。
    def applyHotspotTags(roomId: RoomId, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.getChildrenAt(layerPath(), scene)
            |> List.filter(name -> String.startsWith({prefix = areaNamePrefix()}, name))
            |> List.foldLeft((sc, name) -> updateHotspotRoomId(name, roomId, sc), scene)

    /// 1 つの Hotspot Area2D の Data#roomId を更新する。
    def updateHotspotRoomId(name: String, roomId: RoomId,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapState(layerName() :: name :: Nil, st -> match st {
            case NodeTag.Hotspot(data) =>
                NodeTag.Hotspot(({roomId = roomId, hotspotId = data#hotspotId}: HotspotData))
            case other => other
        }, scene)

    /// レイヤ root の `Data#roomId` を取り出す（未入場時は空文字）。
    pub def currentRoomId(scene: Scene[NodeTag]): RoomId =
        match Scene.getState(layerPath(), scene) {
            case Some(NodeTag.Room(data)) => data#roomId
            case _                        => ""
        }

    /// 背景 Sprite2D を変換するボイラプレート。
    def mapBackgroundSprite(f: Sprite2D -> Sprite2D, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(bgPath(), engineNode ->
            EngineNode.mapSprite2D(f, engineNode),
            scene)

    /// クリック解決の命名規約。`Hotspot_<roomId>_<hotspotId>`。
    /// `AreaHandler.onAreaClicked` が `HotspotData` から組み立てて `Session.start` に渡す。
    /// Yarn 側はこの規約のノードを定義してクリックを受ける。
    pub def yarnNodeNameFor(roomId: RoomId, hotspotId: HotspotId): String =
        "Hotspot_" + roomId + "_" + hotspotId
}
