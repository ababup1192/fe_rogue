// ItemPickupPopupUi — アイテム取得を知らせる中央ポップアップ（World-entity UI 版）。
//
// UI ツリーは ItemPickupPopup.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。見た目は
// UiRender が毎フレーム描く。ここは「拾った瞬間に文言をセットしてフェードを先頭から開始し、取得音を予約する」
// 純粋トリガーと、「予約があれば取得音を 1 回鳴らし、フェード（窓 alpha・枠色・文字色・可視）を進める」
// 毎フレームの配線を持つ。演出状態（stage / elapsed / soundPending / text）は ItemPickupPopupState resource が権威。
//
// 床のアイテムを拾った瞬間に、画面中央の窓へ「○○を手に入れた」を出し、フェードイン → 少し表示 →
// フェードアウトで消す。あわせて取得音を鳴らす。取得処理（PlayerScene.addPickedItem）の effect 行を
// 増やさずに済むよう、`show` 系は純粋（音は `frameStep` が鳴らす）で状態だけを書く。
//
// 文字のフェードについて:
//   UI text の glyph は常に不透明（CanvasItem alpha に従わない）。そこで窓（box）は fill alpha で本当に
//   フェードし、文字は tint を「窓の背景色 → 白」に補間し、薄い区間では非表示にして“フェードしているように”見せる。
//   窓の枠は box の枠 alpha を独立に動かせないため、枠色を「窓の背景色 → 白」に補間して見かけ上フェードさせる。
//
// ノード構造（ItemPickupPopup.ui.json / layer=6。他 HUD より前面）:
//   ItemPickupPopup (none, 画面固定 HUD)
//     ├─ window  (box, 画面中央の約40%サイズ)   ← fill alpha でフェード・枠色を補間
//     └─ textBox (none, 中央寄せ) → label (text) ← tint 補間 + 可視ゲートで擬似フェード

mod ItemPickupPopupUi {

    use ItemPickupPopupState.Stage

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/ItemPickupPopup.ui.json")

    /// root（可視トグルの対象）と、フェードで触る窓・文字ノードの名前パス。
    pub def rootPath(): String = "ItemPickupPopup"
    def windowPath(): String = "ItemPickupPopup/window"
    def labelPath(): String = "ItemPickupPopup/textBox/label"

    // ========================================================================
    // 定数（配色・しきい値・段階の長さ）
    // ========================================================================

    /// 取得音（project.json の "sounds" に登録した name と一致させる）。
    def getItemSound(): String = "get_item"

    /// 窓の背景色（濃紺）／枠色（白）／文字色（白）。
    def windowBgColor(): Color = {r = 0.05f32, g = 0.07f32, b = 0.12f32}
    def borderColor(): Color = UITheme.white()
    def textColor(): Color = UITheme.white()

    /// フェードのピーク不透明度（背景／枠）。
    def maxBgAlpha(): Float64 = 0.85
    def maxBorderAlpha(): Float64 = 0.95

    /// 文字を表示し始める濃さのしきい値。これ未満では文字を出さない
    /// （窓がほぼ透明な区間で不透明な文字だけが浮くのを防ぐ）。
    def textShowThreshold(): Float64 = 0.35

    /// 浮かび上がり / 表示保持 / 消える の各時間。
    def fadeInDuration(): Duration.Duration = Duration.millis(300)
    def holdDuration(): Duration.Duration = Duration.millis(1100)
    def fadeOutDuration(): Duration.Duration = Duration.millis(400)

    // ========================================================================
    // 公開トリガー（純粋）— 状態 resource だけを書く
    // ========================================================================

    /// アイテムを拾ったときに呼ぶ。文言を「${itemName}を手に入れた」にして、フェードを先頭から開始し、
    /// 取得音の予約を立てる。副作用は無く（音は `frameStep` が鳴らす）、既に表示中でも先頭からやり直す。
    pub def show(itemName: String): Unit \ ItemPickupPopupState.State =
        showWith("${itemName}を手に入れた", true)

    /// 取得以外の通知（例: 「持ち物がいっぱいです」）を中央ポップアップに出す。
    /// 取得音は鳴らさず、フェードイン → 表示保持 → フェードアウトの演出だけ流す。
    pub def showMessage(text: String): Unit \ ItemPickupPopupState.State =
        showWith(text, false)

    /// 「持ち物がいっぱいです」を中央ポップアップで知らせる薄いラッパ。
    pub def showFull(): Unit \ ItemPickupPopupState.State =
        showMessage("持ち物がいっぱいです")

    /// 取得音だけを次フレームに予約する（中央ポップアップは出さない）。`show` と違い stage / text を触らないので、
    /// `frameStep` が `get_item` を 1 回鳴らすだけ（`step` は stage に関わらず先頭で `soundPending` を消費して
    /// playSound を返す）。移動着地の自動取得など「大きな通知は不要だが取得音は鳴らしたい」経路で使う。純粋。
    pub def reserveGetItemSound(): Unit \ ItemPickupPopupState.State =
        let d = ItemPickupPopupState.State.get();
        ItemPickupPopupState.State.put({soundPending = true | d})

    /// 文言と「取得音を鳴らすか」を受け取り、フェードを先頭から開始する共通処理。
    /// `playSound = true` のときだけ `frameStep` が取得音を 1 回鳴らす。text は状態に持たせ、
    /// `frameStep` が毎フレーム UI へ流し込む（トリガーは UI を直接触らない）。
    def showWith(text: String, playSound: Bool): Unit \ ItemPickupPopupState.State =
        ItemPickupPopupState.State.put(
            {stage = Stage.FadeIn, elapsed = Duration.zero(), soundPending = playSound, text = text})

    // ========================================================================
    // 純粋: 1 フレーム分の状態更新
    // ========================================================================

    /// `step` の結果。
    /// `data`      — 次フレームへ持ち越す新しい状態。
    /// `ratio`     — 表示の濃さ 0.0（非表示）〜1.0（はっきり）。窓 alpha と文字の見え方に使う。
    /// `playSound` — このフレームで取得音を鳴らすなら true（予約を消費したフレームだけ true）。
    pub type alias StepResult = {
        data      = ItemPickupPopupState.PopupData,
        ratio     = Float64,
        playSound = Bool
    }

    /// 1 フレーム分の状態更新（副作用なし。テスト対象）。
    /// 取得音の予約を消費し（`playSound`）、今の段階を経過時間で進めて、表示の濃さ `ratio` を返す。
    pub def step(data: ItemPickupPopupState.PopupData, dt: Duration.Duration): StepResult =
        let playSound = data#soundPending;
        let cleared = {soundPending = false | data};
        match cleared#stage {
            case Stage.Idle =>
                {data = cleared, ratio = 0.0, playSound = playSound}
            case Stage.FadeIn =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, fadeInDuration()))
                    {data = {stage = Stage.Hold, elapsed = Duration.zero() | cleared},
                     ratio = 1.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared},
                     ratio = easeOut(Duration.ratio(elapsed, fadeInDuration())),
                     playSound = playSound}
            case Stage.Hold =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, holdDuration()))
                    {data = {stage = Stage.FadeOut, elapsed = Duration.zero() | cleared},
                     ratio = 1.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared}, ratio = 1.0, playSound = playSound}
            case Stage.FadeOut =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, fadeOutDuration()))
                    {data = {stage = Stage.Idle, elapsed = Duration.zero() | cleared},
                     ratio = 0.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared},
                     ratio = 1.0 - easeIn(Duration.ratio(elapsed, fadeOutDuration())),
                     playSound = playSound}
        }

    /// `>=` なので、ちょうど total に達したフレームも「段階終了」とみなす（境界フレームを次段階に送らない）。
    def isOver(elapsed: Duration.Duration, total: Duration.Duration): Bool =
        Duration.toSeconds(elapsed) >= Duration.toSeconds(total)

    /// 出はゆっくり減速、消えはゆっくり加速（ふんわりしたフェード）。
    def easeOut(ratio: Float64): Float64 =
        1.0 - (1.0 - ratio) * (1.0 - ratio)
    def easeIn(ratio: Float64): Float64 =
        ratio * ratio

    // ========================================================================
    // 毎フレーム System
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。`step` で状態を進め、予約があれば取得音を 1 回鳴らし、
    /// 文言と表示の濃さ ratio を窓 alpha・枠色・文字色・可視へ反映する。ノード不在（タイトル/選択画面）でも
    /// 安全: 状態は Idle のまま進まず（soundPending も Playing 経路でしか立たない）、setXxx は対象不在で no-op。
    pub def frameStep(delta: Duration.Duration):
                    Unit \ {GameEngine.Audio, ItemPickupPopupState.State, UiWorldState.State} =
        let data = ItemPickupPopupState.State.get();
        let result = step(data, delta);
        ItemPickupPopupState.State.put(result#data);
        if (result#playSound) AudioStreamPlayer.play(getItemSound()) else ();
        UiWorldState.State.put(applyAppearance(result#ratio, result#data#text, UiWorldState.State.get()))

    /// 表示の濃さ ratio と文言を UI へ反映する（純粋・テスト対象）。
    ///   窓: fill alpha = ratio × ピーク不透明度。ratio が 0 なら窓ごと非表示。枠色は「窓背景 → 白」を
    ///       ratio×枠ピークで補間（枠 alpha を独立に動かせないため色で擬似フェード）。
    ///   文字: 文言を流し込み、しきい値以上で表示。tint を「窓背景 → 白」に補間（濃いほど白く＝読める）。
    pub def applyAppearance(ratio: Float64, text: String, ui: UiStore.UiWorld): UiStore.UiWorld =
        let windowVisible = ratio > 0.0;
        let bgAlpha = toAlpha(ratio * maxBgAlpha());
        let borderTone = toAlpha(ratio * maxBorderAlpha());
        let borderModulate = lerpColor(windowBgColor(), borderColor(), borderTone);
        let textVisible = ratio >= textShowThreshold();
        let textTone = toAlpha(textColorRamp(ratio));
        let textModulate = lerpColor(windowBgColor(), textColor(), textTone);
        ui
            // root は ui.json 既定で不可視。ratio>0 のフレームだけ subtree を見せる（Idle 中は畳む）。
            |> UiStore.setVisible(rootPath(), windowVisible)
            |> UiStore.setVisible(windowPath(), windowVisible)
            |> UiStore.setBoxAlpha(windowPath(), bgAlpha)
            |> UiStore.setBoxBorderColor(windowPath(), borderModulate)
            |> UiStore.setText(labelPath(), text)
            |> UiStore.setVisible(labelPath(), textVisible)
            |> UiStore.setTextTint(labelPath(), textModulate)

    /// 文字の色補間量。表示しきい値で 0、ピークで 1 になるように 0..1 へ伸ばす
    /// （しきい値未満は toAlpha のクランプで 0 に丸められる）。
    def textColorRamp(ratio: Float64): Float64 =
        (ratio - textShowThreshold()) / (1.0 - textShowThreshold())

    /// 0.0〜1.0 の Float64 を Float32 の alpha 値へ（範囲外はクランプ）。
    def toAlpha(value: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, value)

    /// alpha チャネルは変更しない（Color 型は r/g/b のみ。RGB のみ補間）。
    def lerpColor(startColor: Color, endColor: Color, t: Float32): Color =
        {r = startColor#r + (endColor#r - startColor#r) * t,
         g = startColor#g + (endColor#g - startColor#g) * t,
         b = startColor#b + (endColor#b - startColor#b) * t}
}
