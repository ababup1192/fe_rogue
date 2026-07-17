// World — 実験場の状態。今日の実験（Transition）は「最後にどの種類を選んだか」と
// 「いま再生中か（Idle か）」、それにラベル UI のページで足りる。
// steps は別実験（固定タイムステップ）の検証用カウンタ: withFixedStep を有効にした Main で
// updateSystems が回った回数を数え、可変 dt と同じ絵になるかを目視できるようにする。
// bgm は別実験（AudioFade + マスター音量）の状態: フェードの向き・進み具合・全体つまみを持つ。
// settings はコンフィグ画面が編集する「保存される設定」、configMenu はその画面自体の
// 開閉・カーソル・ドラッグなど「画面の一時的な UI 状態」（保存しない）。設定と画面状態を
// 分けるのは、設定だけを Persistence でセーブ/ロードしたいため（画面が開いているかどうかを
// セーブファイルに残す意味は無い）。

mod World {

    /// 遷移の再生に使う所要時間（秒）。長すぎず・短すぎず、見比べやすい長さ。
    pub def duration(): Float64 = 1.2

    /// BGM フェードの所要時間（秒）。耳で「だんだん」が分かる長さ。
    pub def bgmDuration(): Float64 = 2.0

    /// BGM 実験の状態。
    pub type alias Bgm = {
        rising = Bool,                     // true = フェードイン中（無音へ向かうなら false）
        progress = Transition.Progress,    // フェードの進み具合（B で向きを反転して引き継ぐ）
        playing = Bool                     // playAudio を一度呼んだか（起動後の初回だけ鳴らし始める）
    }

    /// コンフィグ画面が編集し、ディスクへ保存する設定一式。
    /// masterVolume はスライダーの値（B/M デモの bgm フェードとは独立 — フェードは
    /// 「曲の出入り」、masterVolume は「全体の音量つまみ」で役目が違う）。
    /// Eq は ConfigApply.step が「前フレームと変わったフィールドだけ実機へ反映する」ための比較に使う。
    pub type alias Settings = {
        masterVolume  = Float64,  // 0.0-1.0。GameEngine.Audio.setMasterVolume へそのまま渡す
        bgmOn         = Bool,     // BGM トグル行の on/off
        fullscreen    = Bool,     // フルスクリーントグル行の on/off（Enter デモと共有の真実源）
        cursorVisible = Bool      // カーソル表示トグル行の on/off（H デモと共有の真実源）
    }

    /// 起動直後の既定設定。全開の音量・BGM on・ウィンドウ表示・カーソル表示。
    pub def defaultSettings(): Settings =
        { masterVolume = 1.0, bgmOn = true, fullscreen = false, cursorVisible = true }

    /// 2 つの設定が全フィールド一致するか（record は Eq を自動導出できないため、
    /// タプル化して比較する）。ConfigApply.step が「保存が要るか」を判定するのに使う。
    pub def settingsEqual(a: Settings, b: Settings): Bool =
        (a#masterVolume, a#bgmOn, a#fullscreen, a#cursorVisible) ==
        (b#masterVolume, b#bgmOn, b#fullscreen, b#cursorVisible)

    /// コンフィグ画面の行の並び（上から順。カーソル移動・ハイライト位置に使う）。
    pub def configRowPaths(): List[String] =
        configRows() |> List.map(row -> { let (path, _meta) = row; path })

    /// 行の名前パスと meta 文字列の対。ui.json の各行に置いた "meta" 宣言と同じ文字列で、
    /// 行 index → 行の種類（ConfigMenuUi.rowKindOf）を引く唯一の表。
    pub def configRows(): List[(String, String)] =
        ("Config/menu/masterVolumeRow", "volume") :: ("Config/menu/bgmRow", "bgm") ::
        ("Config/menu/fullscreenRow", "fullscreen") :: ("Config/menu/cursorRow", "cursor") ::
        ("Config/menu/closeRow", "close") :: Nil

    /// cursor 位置の行の meta（範囲外は "close" — 決定キーだけ効く安全側）。
    pub def configRowMeta(cursor: Int32): String =
        List.nth(cursor, configRows()) |> Option.map(row -> { let (_path, meta) = row; meta })
            |> Option.getWithDefault("close")

    /// コンフィグ画面の一時的な UI 状態（保存しない）。open=画面の開閉、
    /// cursor=選択中の行 index、dragging=スライダーの track をつまんでいる間だけ Some
    /// （その行の名前パス。値は毎フレーム mouseDown が続く限り更新し、離した瞬間に None へ戻す）。
    pub type alias ConfigMenu = { open = Bool, cursor = Int32, dragging = Option[String] }

    pub def initialConfigMenu(): ConfigMenu = { open = false, cursor = 0, dragging = None }

    /// カンテラ実験の暗闇モード。Bright=通常表示（暗幕なし）、Dark=暗闇のみ
    /// （Light.multiLightItems を lights=Nil で呼ぶ全面暗幕、光源なし）、
    /// DarkWithLight=穴あき暗幕+ハロ（Light.singleLightItems）。
    /// LeftShift は Bright ⇔ DarkWithLight をトグルする（Dark は比較用の対照カット専用で
    /// ゲーム内操作からは経由しない — bakeLanternComparisonPngs の3枚がそれぞれ1モードに対応する）。
    pub enum LanternMode with Eq {
        case Bright
        case Dark
        case DarkWithLight
    }

    /// カンテラ実験の状態。at はプレイヤー（=光源）の位置、mode は今の暗闇の見せ方。
    /// walls は壁と影（Shadow）のデモの表示スイッチ（既定 off — 常時表示にすると
    /// 既存の lantern 系 bake の絵が変わってしまうため、トグルで足す）。
    pub type alias Lantern = { at = Vec2.Vec2, mode = LanternMode, walls = Bool }

    pub type alias World = {
        kind = Transition.Kind,                   // 最後に選んだ種類（Idle 中の Space もこれを再生）
        playing = Option[Transition.Progress],    // None = Idle（覆いなし）/ Some = 再生中の進み具合
        steps = Int32,
        bgm = Bgm,
        ui = UiStore.UiWorld,
        settings = Settings,        // コンフィグ画面が編集し、保存/復元する設定
        appliedSettings = Settings, // 直近で実機（GameEngine）へ反映した設定
        // （settings と食い違うフィールドだけ ConfigApply.step が反映して揃える。
        // 「変化した時だけ呼ぶ」を大元の入力手段（キー/コンフィグ画面）によらず一本化するための影）。
        configMenu = ConfigMenu,    // コンフィグ画面の開閉・カーソル・ドラッグ（保存しない）
        blend = Option[DrawCmd.BlendMode],  // None = デモ非表示 / Z/X/C で重ね方を選ぶと表示
        // None = デモ非表示 / 矢印キーを押した瞬間に現れる（他デモと同じ Option パターン。
        // 常時表示にすると他シーンの bake（blend/fps/遷移 GIF）にも部屋と目印が映り込んでしまう）。
        lantern = Option[Lantern],
        // カンテラの光の質感（assets/Lantern.light.json）。at は光源位置の初期値の目安に
        // すぎず、実行中は lantern#at（World が持つプレイヤー位置）が正 — LightDoc.toConfigWithLights
        // で毎フレーム差し替える（「json は質感、位置はゲーム」の分業）。
        lightDoc = LightDoc.Spec
    }

    /// 起動直後は Idle（覆いなし）で始める。いきなり遷移を再生すると画面が
    /// フェードアウトして「消えた」ように見え、フルスクリーン等の起動確認ができないため。
    /// BGM は無音からのフェードインで始まる。
    /// ui/lightDoc は外の世界（ファイル）に触れるので、読み込み済みの物を Main から受け取る。
    /// settings は起動時に保存済みファイルがあれば読み込んだ値、無ければ既定値を Main が渡す
    /// （ここでは常に defaultSettings を仮置きせず、呼び側の読み込み結果をそのまま受け取る）。
    /// blend デモは初期非表示（None）。常時表示にすると遷移 GIF や fps 見本の bake に
    /// 映り込み、既存の gallery の絵が変わってしまう。
    /// appliedSettings は起動直後の実機状態（既定値）で始める。settings が保存済みの値で
    /// 始まっていても、実機（音量・ウィンドウ）への反映は ConfigApply.step の最初の 1 回に任せる
    /// ことで、起動処理を「初期化」と「反映」の 2 箇所に分けずに済む。
    pub def initial(ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, settings: Settings): World =
        { kind = Transition.Kind.FadeOut, playing = None, steps = 0,
          bgm = { rising = true, progress = Transition.start(bgmDuration()), playing = false },
          ui = ui, settings = settings, appliedSettings = defaultSettings(), configMenu = initialConfigMenu(),
          blend = None,
          lantern = None, lightDoc = lightDoc }

    /// いまの BGM 音量（フェードの向きと進み具合から導く。実機へ流す値と同じ計算）。
    pub def bgmVolume(bgm: Bgm): Float64 =
        let fade = if (bgm#rising) AudioFade.fadeIn() else AudioFade.fadeOut();
        AudioFade.volumeOf(fade, Transition.tOf(bgm#progress))

    /// HUD と statusLine の遷移表示。Idle のときは操作案内を出す
    /// （何も再生していない画面で種類名だけ出ていると「再生中に見える」ため）。
    pub def transitionLabel(world: World): String =
        world#playing
            |> Option.map(_ -> kindLabel(world#kind))
            |> Option.getWithDefault("idle (W/A/S/D)")

    /// いまの再生位置 t（Idle のときは 0）。
    pub def transitionT(world: World): Float64 =
        world#playing |> Option.map(Transition.tOf) |> Option.getWithDefault(0.0)

    /// 画面下の 1 行サマリ（遷移・固定ステップ・BGM・フルスクリーン・カーソル・ブレンド・カンテラ）。
    pub def statusLine(world: World): String =
        "transition=${transitionLabel(world)} t=${round2(transitionT(world))} steps=${world#steps}"
            + " bgm=${round2(bgmVolume(world#bgm))} master=${round2(world#settings#masterVolume)}"
            + " fullscreen=${onOff(world#settings#fullscreen)} cursor=${onOff(world#settings#cursorVisible)}"
            + " blend=${blendLabel(world#blend)} ${lanternLabel(world#lantern)}"
            + " config=${onOff(world#configMenu#open)}"

    /// blend デモの表示名（HUD の bind と statusLine の両方が使う）。非表示中は操作案内。
    pub def blendLabel(blend: Option[DrawCmd.BlendMode]): String =
        blend |> Option.map(modeLabel) |> Option.getWithDefault("off (Z/X/C)")

    /// カンテラ実験の表示名。非表示中は操作案内、表示中は暗闇の on/off を出す
    /// （LeftShift が行き来する Bright/DarkWithLight の2値として見せる — Dark はゲーム内
    /// 操作から経由しないため on/off 表記のままで足りる）。
    pub def lanternLabel(lantern: Option[Lantern]): String =
        lantern
            |> Option.map(l -> "darkness=${onOff(l#mode == LanternMode.DarkWithLight)}${wallsSuffix(l)}")
            |> Option.getWithDefault("lantern=off (Arrows to start)")

    /// walls=off のときは何も足さない（既存 bake の文字列＝絵をバイト単位で変えないため）。
    def wallsSuffix(l: Lantern): String = if (l#walls) " walls=on" else ""

    /// ブレンドモード単体の表示名（gallery のカード名にも使う）。
    pub def modeLabel(mode: DrawCmd.BlendMode): String =
        match mode {
            case DrawCmd.BlendMode.Normal   => "Normal"
            case DrawCmd.BlendMode.Add      => "Add"
            case DrawCmd.BlendMode.Multiply => "Multiply"
        }

    /// on/off 表記。statusLine と HUD 表示（GameUi.bindText）の両方が使う共通表記。
    pub def onOff(b: Bool): String = if (b) "on" else "off"

    def round2(x: Float64): Float64 = Float64.round(x * 100.0) / 100.0

    pub def kindLabel(kind: Transition.Kind): String =
        match kind {
            case Transition.Kind.FadeOut   => "FadeOut"
            case Transition.Kind.FadeIn    => "FadeIn"
            case Transition.Kind.WipeLeft  => "WipeLeft"
            case Transition.Kind.WipeRight => "WipeRight"
        }
}
