/// LogScene — 画面下部にゲームログを表示する HUD
///
/// CanvasLayer 配下に半透明の背景 ColorRect と複数の Label2D を並べる。
/// `flushFromEffect` を gameLoop の毎フレーム末尾で呼ぶと、
/// `GameLogger` effect で蓄積されたメッセージを drain し、Label2D 群を
/// 再構築する（即時シフト方式）。
///
/// ノード構造:
///   Log (CanvasLayer, NodeTag.Log({entries, maxLines}))
///     ├─ Bg     (ColorRect, modulate=黒, alpha=1.0, size=(panelW, panelH))
///     ├─ Line_0 (Label2D)   ← 最新行 (最上行)
///     ├─ Line_1 (Label2D)
///     └─ ... (新→古、idx=0 が最上 = 新しいものほど上)
///
/// 座標系は論理解像度 (designWidth × designHeight = 128×128) ベース。
/// CanvasLayer 配下も同じ projection で描画されるので、ここで使う数値は
/// すべて論理 px。下部に幅一杯・高さ panelH の帯として配置する。
mod LogScene {

    /// 1 行分の表示エントリ。GameLogger.Entry と同形だが、Scene 側で
    /// 独立に保持する（effect とノード状態を分離）
    pub type alias Entry = { text = String, color = Color }

    /// 親 CanvasLayer に紐づくデータ
    pub type alias Data = {
        entries  = List[Entry],   // 新→古の順（idx=0 が最新 = 最下行）
        maxLines = Int32
    }

    // ────────────────────────────────────────────────────────
    // 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Log"
    pub def logPath(): NodePath = name() :: Nil

    /// 表示行数の上限
    def maxLinesDefault(): Int32 = 5
    /// fontManifest で登録した name と一致させる
    def fontName(): String = "ui"
    /// 論理 px のフォントサイズ。fontManifest のベイクサイズ (16) と整数比 0.25 で
    /// 縮小し、ベイクの細部情報を活かしつつコンパクトに表示する
    def fontSize(): Float64 = 4.0
    /// 行高（論理 px）。fontSize より少し広めに取り、ascent/descent ぶんの余裕を確保する
    def lineHeight(): Float64 = 5.0
    /// パネル左端からテキストまでの内側余白（論理 px）
    def padding(): Float64 = 2.0
    /// パネル高さ（論理 px）。lineHeight × maxLines + 上下パディング
    def panelHeight(): Float64 = 28.0
    /// 背景色（黒）
    def bgColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    /// 背景の不透明度（半透明黒）
    def bgAlpha(): Float32 = 0.6f32
    /// CanvasLayer のレイヤー番号。盤面より前面に出す
    def drawLayer(): Int32 = 1

    // ────────────────────────────────────────────────────────
    // 構築
    // ────────────────────────────────────────────────────────

    /// Scene に Log ノード（CanvasLayer + 背景 ColorRect）を追加する。
    /// Label2D は `flushFromEffect` で動的に追加される（初期は空）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let vp = GameEngine.Game.getViewportRect();
        let panelW = vp#size#x;            // 横幅は画面いっぱい
        let panelH = panelHeight();
        let panelY = vp#size#y - panelH;   // 下端揃え
        let layer = CanvasLayer.make(drawLayer())
                    |> Node2D.setPosition({x = 0.0, y = panelY});
        let data: Data = { entries = Nil, maxLines = maxLinesDefault() };
        let withParent = Scene.addNode(name(),
            EngineNode.CanvasLayerWithState(layer, NodeTag.Log(data)),
            scene);
        let bg = ColorRect.make({x = panelW, y = panelH}, bgColor())
                 |> ColorRect.setAlpha(bgAlpha());
        Scene.addChild(name(), "Bg",
            EngineNode.ColorRectWithState(bg, NodeTag.NoTag),
            withParent)

    /// gameLoop が毎フレーム末尾で呼ぶ flush。GameLogger に蓄積された Entry を
    /// drain して LogScene のデータに反映し、Label2D 群を再構築する。
    /// drain が空の場合は何もしない。
    pub def flushFromEffect(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameLogger.GameLogger} =
        let drained = GameLogger.GameLogger.drainEntries();
        match drained {
            case Nil => scene
            case _   => rebuild(drained, scene)
        }

    // ────────────────────────────────────────────────────────
    // 内部
    // ────────────────────────────────────────────────────────

    /// 既存の Line_<idx> を全削除し、新エントリ（古→新）を反映して再構築する
    def rebuild(newOnes: List[GameLogger.Entry],
                scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match Scene.getState(logPath(), scene) {
            case Some(NodeTag.Log(data)) =>
                let asEntries = List.map(e ->
                    ({text = e#text, color = e#color}: Entry), newOnes);
                let merged  = mergeEntries(asEntries, data#entries, data#maxLines);
                let cleared = removeAllLines(data#entries, scene);
                let updatedState: Data = { entries = merged | data };
                let withState = Scene.setState(logPath(),
                    NodeTag.Log(updatedState), cleared);
                addLineChildren(merged, withState)
            case _ => scene
        }

    /// 新規エントリ（古→新）と既存エントリ（新→古）を合体し、
    /// 新→古順かつ maxLines で打ち切ったリストを返す
    def mergeEntries(newOnes: List[Entry], existing: List[Entry],
                     cap: Int32): List[Entry] =
        let prepended = List.append(List.reverse(newOnes), existing);
        List.take(cap, prepended)

    /// 既存エントリ数だけ Line_<i> を全削除する
    def removeAllLines(prev: List[Entry], scene: Scene[NodeTag]): Scene[NodeTag] =
        let n = List.length(prev);
        List.foldLeft(acc -> idx ->
            Scene.removeAt(name() :: "Line_${idx}" :: Nil, acc),
            scene, List.range(0, n))

    /// 新エントリ列を Line_<i> として子追加する。
    /// idx=0 が最新で最下行、idx が増えるほど上に並ぶ。
    def addLineChildren(entries: List[Entry],
                        scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let indexed = List.zip(List.range(0, List.length(entries)), entries);
        List.foldLeft(acc -> entry -> {
            let (idx, e) = entry;
            // idx=0 が最新で最上行。新しいものほど上、古いものほど下に流れる
            let y = padding() + Int32.toFloat64(idx) * lineHeight();
            // zIndex を Bg(=0) より大きくして、必ず背景の前面に描画させる。
            // 同じ zIndex だと CanvasLayer 配下の描画順が不定で、Bg がグリフを
            // 部分的に上書きして「文字の続きが消える」現象が出る
            let label = Label2D.make(e#text, atlas, fontSize())
                |> CanvasItem.setModulate(e#color)
                |> CanvasItem.setZIndex(1)
                |> Node2D.setPosition({x = padding(), y = y});
            Scene.addChild(name(), "Line_${idx}",
                EngineNode.Label2DWithState(label, NodeTag.NoTag),
                acc)
        }, scene, indexed)
}
