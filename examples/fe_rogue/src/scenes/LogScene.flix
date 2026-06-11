/// LogScene — 画面下部にゲームログを表示する HUD
///
/// CanvasLayer 配下に半透明の背景 ColorRect と 1 個の RichTextLabel を並べる。
/// `flushFromEffect` を gameLoop の毎フレーム末尾で呼ぶと、
/// `GameLogger` effect で蓄積されたメッセージを drain し、
/// RichTextLabel のテキストを更新する。`scrollFollowing = true` なので
/// 新しい行が追加されると自動で末尾までスクロールする。
///
/// ノード構造:
///   Log (CanvasLayer, NodeTag.Log({entries, maxLines}))
///     ├─ Bg   (ColorRect, modulate=黒, alpha=半透明, size=(panelW, panelH))
///     └─ Text (RichTextLabel, scrollFollowing=true, BBCode カラー対応)
///
/// 座標系は論理解像度 (designWidth × designHeight = 128×128) ベース。
/// CanvasLayer 配下も同じ projection で描画されるので、ここで使う数値は
/// すべて論理 px。下部に幅一杯・高さ panelH の帯として配置する。
mod LogScene {

    /// 1 行分の表示エントリ。BBCode に変換してから RichTextLabel に流す。
    /// color は engine の Color (`{r,g,b}` Float32) を構造的レコードで展開。
    /// Flix 0.72.0 では cross-package type alias がコンパイル時に解決されないバグがあるため、
    /// Color 型エイリアスを使わず構造的レコードで展開している。
    pub type alias Entry = { text = String, color = {r = Float32, g = Float32, b = Float32} }

    /// 親 CanvasLayer に紐づくデータ
    pub type alias Data = {
        entries  = List[Entry],   // append で reverse() して prepend するため新→旧順
        maxLines = Int32          // 履歴上限。超えたら末尾（最古）から落とす
    }

    def name(): String = "Log"
    pub def logPath(): NodePath = name() :: Nil
    def panelChildName(): String = "panel"
    def textChildName(): String = "Text"
    /// Text は Panel の子なので `[Log, panel, Text]` の 3 段
    pub def textPath(): NodePath = name() :: panelChildName() :: textChildName() :: Nil

    /// 履歴上限（行数）。過去ログをスクロールで遡れるよう表示行数より多めに確保する
    def maxLinesDefault(): Int32 = 200
    /// fontManifest で登録した name と一致させる
    def fontName(): String = "ui"
    /// パネル高さ（論理 px）。`isMouseOverPanel` のヒット判定で使う。
    /// scene.json の Container `rect.height` と一致させる
    def panelHeight(): Float64 = 28.0
    /// scene.json のパス
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/LogScene.scene.json")

    /// Scene に Log ノード（CanvasLayer + 背景 ColorRect + RichTextLabel + Container）を追加する。
    /// 構造とレイアウトは scene.json で宣言、flix は `NodeTag.Log` の初期値を注入するだけ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let data: Data = { entries = Nil, maxLines = maxLinesDefault() };
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                       SceneLoader.constTagParser(NodeTag.NoTag),
                                       scene)
            |> Scene.setState(logPath(), NodeTag.Log(data))

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から、`NodeTag.Log` ノードに
    /// 対して dispatch される (log は 1 個のみなので 1 フレーム 1 回)。
    /// scroll delta はパネル外でも必ず消費する — 他ノードの処理に干渉させないため。
    /// GLFW yoffset は wheel up が正・wheel down が負。ログは「新が上」なので
    /// wheel down で過去ログ (下方向) を見たい → scrollY を増やす方向に符号反転する。
    /// scene 経由で self (logPath / textPath) を更新するため、最後に scene から self の
    /// 最新ノードを取り直して返す (古い node で打ち消されないように)。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, GameLogger.GameLogger} =
        let drained = GameLogger.drainEntries();
        let afterFlush = match drained {
            case Nil => scene
            case _   => append(drained, scene)
        };
        let delta = GameEngine.Game.consumeScrollDelta();
        let next =
            if (delta == 0.0) afterFlush
            else if (not isMouseOverPanel()) afterFlush
            else {
                let dy = -1.0 * delta * scrollPxPerTick();
                Scene.mapEngineNode(textPath(),
                    n -> EngineNode.mapRichTextLabel(
                        l -> RichTextLabel.setScrollY(
                            RichTextLabel.getScrollY(l) + dy, l), n),
                    afterFlush)
            };
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 1 ホイール tick あたりのスクロール量（論理 px）。マウスホイールの 1 段で
    /// だいたい 1 行ぶん（lineHeight に近い値）動かす
    def scrollPxPerTick(): Float64 = 5.0

    /// マウスカーソルがログパネルの矩形内にあるか
    def isMouseOverPanel(): Bool \ GameEngine.Game =
        let mouse = GameEngine.Game.getMousePosition();
        let vp = GameEngine.Game.getViewportRect();
        let panelTop = vp#size#y - panelHeight();
        mouse#y >= panelTop and mouse#y <= vp#size#y
            and mouse#x >= 0.0 and mouse#x <= vp#size#x

    /// drain 順（古→新）で渡ってくる新エントリを reverse して既存リスト先頭に prepend することで
    /// 全体の「新→旧」順を維持する。テキスト更新後は scrollY を 0 に戻す（最新行が常に画面上端に来るように）。
    def append(newOnes: List[GameLogger.Entry],
               scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(logPath(), scene) {
            case Some(NodeTag.Log(data)) =>
                let asEntries = List.map(e ->
                    ({text = e#text, color = e#color}: Entry), newOnes);
                let merged = capEntries(
                    List.append(List.reverse(asEntries), data#entries),
                    data#maxLines);
                let updatedState: Data = { entries = merged | data };
                let withState = Scene.setState(logPath(),
                    NodeTag.Log(updatedState), scene);
                let bbcode = entriesToBBCode(merged);
                Scene.mapEngineNode(textPath(),
                    n -> EngineNode.mapRichTextLabel(
                        l -> l |> RichTextLabel.setText(bbcode)
                               |> RichTextLabel.setScrollY(0.0), n),
                    withState)
            case _ => scene
        }

    /// 新→旧順なので先頭 n 件が最新になる — List.take で古いエントリを末尾から落とす
    def capEntries(entries: List[Entry], cap: Int32): List[Entry] =
        List.take(cap, entries)

    /// 各行 `[color=#rrggbb]text[/color]` を改行で連結する。
    def entriesToBBCode(entries: List[Entry]): String =
        let lines = List.map(e ->
            "[color=#" + colorToHex(e#color) + "]" + e#text + "[/color]",
            entries);
        String.intercalate("\n", lines)

    /// Color (Float32 0..1) を 6 桁 hex 文字列に変換する
    def colorToHex(color: Color): String =
        floatChannelToHex(color#r) + floatChannelToHex(color#g) + floatChannelToHex(color#b)

    /// 0..1 の Float32 を 0..255 の 2 桁 hex に変換する。範囲外はクランプ。
    def floatChannelToHex(f: Float32): String =
        let i = Float32.round(f * 255.0f32)
                |> Float32.tryToInt32
                |> Option.map(n -> Int32.max(0, Int32.min(255, n)))
                |> Option.getWithDefault(0);
        hexDigit(i / 16) + hexDigit(Int32.remainder(i, 16))

    /// 0..15 の Int32 を 1 文字の hex 文字列に変換する
    def hexDigit(d: Int32): String = match d {
        case 0  => "0"
        case 1  => "1"
        case 2  => "2"
        case 3  => "3"
        case 4  => "4"
        case 5  => "5"
        case 6  => "6"
        case 7  => "7"
        case 8  => "8"
        case 9  => "9"
        case 10 => "a"
        case 11 => "b"
        case 12 => "c"
        case 13 => "d"
        case 14 => "e"
        case _  => "f"
    }
}
