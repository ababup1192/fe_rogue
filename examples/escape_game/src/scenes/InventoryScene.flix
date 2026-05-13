/// 画面上部に固定 5 スロットのインベントリバーを描画する Scene 層。
///
/// 設計意図:
///   - レイヤ root が `NodeTag.Inventory(Data)` を持つ。状態の真実の源は
///     `Game.Inventory.Access` effect (Phase 1 で実装) であり、本 Scene は
///     毎フレーム `process` でその snapshot を読んで scene tree (アイコン
///     Sprite2D の visible/texture と SelectionHighlight の position/visible) に
///     反映するだけ
///   - スロットは 5 個固定。各スロットに `Slot<i>Bg` (背景 ColorRect) と
///     `Slot<i>Icon` (アイコン Sprite2D) のペアを scene.json で静的に配置
///   - 選択中スロットは 1 個だけ `SelectionHighlight` (黄色枠 ColorRect) を
///     スロット直下に重ねて見せる (zIndex 0 で Bg=zIndex 1 の後ろに描画される)
///   - クリック判定は `Game.flix` の InputHandler が `containsPoint` で
///     インベントリバー領域を最優先判定し、ヒット時に `onClick` で `setSelected` を fire
///
/// レイヤ構成 (drawLayer = 8、Room=5 と Dialogue=10 の間):
///   CanvasLayer "Inventory"
///     ├── SelectionHighlight (ColorRect 36×36 黄)        — 選択中スロット下に重ねる
///     ├── Slot0Bg .. Slot4Bg (ColorRect 32×32 暗)        — スロット背景
///     └── Slot0Icon .. Slot4Icon (Sprite2D 24×24 中央)   — アイテムアイコン
mod InventoryScene {
    use Game.Inventory.{ItemId, SlotIndex, Snapshot}

    // ════════════════════════════════════════════════════════════════════════
    // (A) 型定義
    // ════════════════════════════════════════════════════════════════════════

    /// レイヤ root に乗せる Data。
    /// 1 フレーム前の snapshot を保持して「変化がなければ再描画スキップ」を
    /// 可能にするためのキャッシュ。Phase 3 では毎フレーム同期するシンプル版を採用し、
    /// `Data` は識別タグ役を兼ねた最小 record。後で最適化が要れば `lastApplied`
    /// などのフィールドを足す。
    pub type alias Data = { initialized = Bool }

    /// `NodeTag.Inventory` の初期値。
    pub def emptyData(): Data = ({initialized = false}: Data)

    // ════════════════════════════════════════════════════════════════════════
    // (B) 定数
    // ════════════════════════════════════════════════════════════════════════

    /// レイヤノード名 (scene.json と一致)。
    pub def layerName(): String = "Inventory"

    /// レイヤ root への NodePath。
    pub def layerPath(): NodePath = layerName() :: Nil

    /// 選択ハイライトのノード名 (scene.json と一致)。
    def highlightName(): String = "SelectionHighlight"

    /// scene.json のパス。
    def sceneJsonPath(): String = "src/scenes/InventoryScene.scene.json"

    /// インベントリバーの design 座標領域 (top-left 〜 bottom-right)。
    /// クリック領域判定 + ハイライト Y 座標計算で使う。
    /// scene.json の Slot bg 矩形 (y=4 〜 36) を吸収する余白付き。
    pub def barTop(): Float64    = 0.0
    pub def barBottom(): Float64 = 40.0

    /// 個別スロットの top-left 座標とサイズ (scene.json と一致させる)。
    /// 5 スロット、4px 間隔、画面幅 480 に対して中央寄せ。
    /// (152, 4) (188, 4) (224, 4) (260, 4) (296, 4)、各 32×32。
    def slotSize(): Vec2.Vec2 = ({x = 32.0, y = 32.0}: Vec2.Vec2)
    def firstSlotLeft(): Float64 = 152.0
    def slotPitch(): Float64     = 36.0   // 32 (slot) + 4 (gap)
    pub def slotTopLeft(slot: SlotIndex): Vec2.Vec2 =
        ({x = firstSlotLeft() + Int32.toFloat64(slot) * slotPitch(),
          y = 4.0}: Vec2.Vec2)

    /// 選択ハイライト矩形の top-left オフセット (slot 中央から -2,-2)。
    /// scene.json の SelectionHighlight サイズ 36×36 と整合。
    def highlightOffset(): Vec2.Vec2 = ({x = -2.0, y = -2.0}: Vec2.Vec2)

    /// アイコンのテクスチャ名規約。`icon_<itemId>`。
    /// 例: itemId="demo_key" → "icon_demo_key"。
    /// Main.flix の textureManifest と揃える。
    def iconTextureName(id: ItemId): String = "icon_" + id

    /// scene.json のスロットアイコンノード名生成。`Slot<i>Icon`。
    def slotIconName(slot: SlotIndex): String = "Slot${slot}Icon"

    /// scene.json のスロットアイコン NodePath。
    def slotIconPath(slot: SlotIndex): NodePath =
        layerName() :: slotIconName(slot) :: Nil

    /// 選択ハイライトの NodePath。
    def highlightPath(): NodePath =
        layerName() :: highlightName() :: Nil

    // ════════════════════════════════════════════════════════════════════════
    // (C) 構築 — addInventoryLayer
    // ════════════════════════════════════════════════════════════════════════

    /// scene.json をロードしてレイヤを 1 枚積む。Root に `NodeTag.Inventory(emptyData())`
    /// を載せる。`process` で Inventory.Access の snapshot を毎フレーム反映する。
    pub def addInventoryLayer(scene: Scene[NodeTag]):
                               Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(sceneJsonPath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> Scene.setState(layerPath(), NodeTag.Inventory(emptyData()))

    // ════════════════════════════════════════════════════════════════════════
    // (D) ロジック — process / onMouse / containsPoint
    // ════════════════════════════════════════════════════════════════════════

    /// `Game.Inventory.Access` の snapshot を読んで scene tree のアイコン表示と
    /// ハイライト位置を同期する。
    /// 戻り値は更新後の Scene。Game.flix の Node.process redef から呼ばれる。
    pub def process(_layer: CanvasLayer,
                     _data: Data,
                     scene: Scene[NodeTag]):
                     Scene[NodeTag] \ Game.Inventory.Access =
        let snap = Game.Inventory.Access.snapshot();
        scene
            |> applyIcons(snap#items)
            |> applyHighlight(snap#selected)

    /// 5 スロット分のアイコンを items リストから埋める。
    /// items[i] が存在: `sprite_<id>` テクスチャをセット + visible=true
    /// 存在しない:     visible=false
    def applyIcons(items: List[ItemId], scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((sc, slot) -> applyIconAt(slot, items, sc),
                      scene,
                      List.range(0, Game.Inventory.slotCount()))

    /// スロット 1 個分のアイコン更新。
    def applyIconAt(slot: SlotIndex, items: List[ItemId], scene: Scene[NodeTag]): Scene[NodeTag] =
        match List.nth(slot, items) {
            case Some(id) =>
                Scene.mapEngineNode(slotIconPath(slot), engineNode ->
                    EngineNode.mapSprite2D(s ->
                        s |> Sprite2D.setTexture(iconTextureName(id))
                          |> CanvasItem.setVisible(true), engineNode),
                    scene)
            case None =>
                Scene.mapEngineNode(slotIconPath(slot), engineNode ->
                    EngineNode.mapSprite2D(s -> CanvasItem.setVisible(false, s),
                        engineNode),
                    scene)
        }

    /// 選択ハイライトの位置と可視を更新する。
    /// Some(slot) → そのスロットの top-left + 余白に移動 + visible=true
    /// None        → visible=false
    def applyHighlight(selected: Option[SlotIndex], scene: Scene[NodeTag]): Scene[NodeTag] =
        match selected {
            case None       => mapHighlight(r -> CanvasItem.setVisible(false, r), scene)
            case Some(slot) =>
                let topLeft = Vec2.add(slotTopLeft(slot), highlightOffset());
                mapHighlight(r ->
                    r |> Node2D.setPosition(topLeft)
                      |> CanvasItem.setVisible(true), scene)
        }

    /// SelectionHighlight ColorRect を変換するボイラプレート。
    def mapHighlight(f: ColorRect -> ColorRect, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(highlightPath(), engineNode ->
            EngineNode.mapColorRect(f, engineNode),
            scene)

    /// 与えられた点がインベントリバー領域にあるか。Game.flix の InputHandler が
    /// クリック先を「インベントリ vs ホットスポット」に振り分けるのに使う。
    /// 領域は `barTop`〜`barBottom` の Y 帯 (X は画面幅全体)。
    /// 「バー領域だけ」の判定にしておくと、スロット間の余白クリックも吸収して
    /// 「現在の選択を解除」する挙動を作りやすい。
    pub def containsPoint(point: Vec2.Vec2): Bool =
        point#y >= barTop() and point#y < barBottom()

    /// クリックを受けてスロット選択を更新する。
    /// 5 スロットそれぞれの矩形を順に判定し:
    ///   - ヒット かつ 既に選択中 → 解除 (None)
    ///   - ヒット かつ 別スロット → そのスロットを選択 (Some(idx))
    ///   - どこにもヒットしない (バー内のスロット間スペース) → 解除 (None)
    /// 戻り値は scene 自体は変えず (見た目は次フレームの process で同期)。
    pub def onClick(point: Vec2.Vec2, scene: Scene[NodeTag]):
                     Scene[NodeTag] \ Game.Inventory.Access =
        let next = nextSelectionFor(point, Game.Inventory.Access.snapshot()#selected);
        Game.Inventory.Access.setSelected(next);
        scene

    /// 純粋関数: クリック位置と現在の選択から次の選択スロットを決める。
    /// テスト容易性のため `setSelected` から切り出している。
    pub def nextSelectionFor(point: Vec2.Vec2,
                              currentSelected: Option[SlotIndex]):
                              Option[SlotIndex] =
        match hitSlot(point) {
            case None      => None  // バー内空白なら解除
            case Some(idx) =>
                if (currentSelected == Some(idx)) None  // 同一スロット 2 回で解除
                else Some(idx)
        }

    /// 与えられた点が乗っているスロット index (0..slotCount-1) を返す。
    /// バー領域外、もしくはスロット間スペースに乗っているなら None。
    pub def hitSlot(point: Vec2.Vec2): Option[SlotIndex] =
        if (not containsPoint(point)) None
        else
            List.range(0, Game.Inventory.slotCount())
                |> List.find(slot -> isInSlot(point, slot))

    /// スロット矩形 (top-left, slotSize) に点が含まれるか (左上端含む、右下端含まず)。
    def isInSlot(point: Vec2.Vec2, slot: SlotIndex): Bool =
        let tl = slotTopLeft(slot);
        let br = Vec2.add(tl, slotSize());
        point#x >= tl#x and point#x < br#x
        and point#y >= tl#y and point#y < br#y
}
