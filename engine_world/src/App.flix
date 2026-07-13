// App — ゲームを「宣言」で組み立てて走らせるランナー。ゲーム側は初期 World にシステムと
// 絵と音を繋いで launch を呼ぶだけ、窓・時計・キー・描画・末尾再帰のループはすべてここが引き受ける。
// 外の世界に触れる処理（effect）はこのモジュールが独占するので、ゲームのシステムは
// (Frame, w) -> w の純粋関数として書ける: 押されているキーとエッジと dt は、毎フレーム
// App が Frame という値に焼いて渡す。World の型 w には触れない（初期値・システム・絵・音は
// ぜんぶゲーム側が持ち込む。初期値の組み立てに effect が要るなら、main が自分のハンドラで
// 組んでから App.make へ渡せばよい）。

mod App {
    import java.lang.System

    // ── システムが受け取る 1 フレームぶんの外界 ──

    /// このフレームの入力と時計のスナップショット。キーの生読みはランナーが済ませてあるので、
    /// システムは down（押されている）と justPressed（この瞬間押された）を値として引くだけ。
    pub type alias Frame = {
        down = Set[GameEngine.Key],        // いま押されているキー
        justPressed = Set[GameEngine.Key], // このフレームで新しく押されたキー（エッジ）
        dt = Float64,                      // 前フレームからの経過秒（エンジンがクランプ済み）
        viewport = Vec2.Vec2               // design 解像度の幅・高さ（project.json の designWidth/Height）
    }

    /// key がいま押されているか（押しっぱなしも true）。移動などの連続入力に。
    pub def isDown(key: GameEngine.Key, frame: Frame): Bool =
        Set.memberOf(key, frame#down)

    /// key がこのフレームで新しく押されたか（押しっぱなしは false）。決定・発射などの単発入力に。
    pub def justPressed(key: GameEngine.Key, frame: Frame): Bool =
        Set.memberOf(key, frame#justPressed)

    /// 負方向・正方向のキーの押し下げを -1 / 0 / +1 に畳む（両押しは打ち消して 0）。
    /// 左右移動などの軸入力に。同型のキー 2 つは順序を取り違えやすいので名前で渡す。
    pub def axis(negative: {negative = GameEngine.Key},
                 positive: {positive = GameEngine.Key}, frame: Frame): Float64 =
        (if (isDown(positive#positive, frame)) 1.0 else 0.0) -
        (if (isDown(negative#negative, frame)) 1.0 else 0.0)

    // ── App: 宣言の入れ物 ──

    /// ゲーム 1 本の宣言。make で空を作り、addStartup / addSystem / reloadOn / withView /
    /// withAudio / quitWhen で部品を繋ぎ、launch へ渡す。w はゲームが持ち込む World の型。
    /// ef はゲームのシステム・絵・音・終了判定が帯びる効果（外の世界に触れる処理）の行。
    /// 純粋なゲームは ef = {}（Pure）、effect で状態を持つゲームは自分の効果行を ef に載せて
    /// 同じ App に乗せる（効果多相）。
    pub type alias App[w: Type, ef: Eff] = {
        init = Vec2.Vec2 -> w \ ef,                                // design 解像度 → 出発点の World（launch が画面サイズを渡して呼ぶ）
        startupSystems = List[w -> w \ ef],                        // 起動時に 1 回だけ・追加順
        updateSystems = List[(Frame, w) -> w \ ef],                // 毎フレーム・追加順
        reload = Option[(GameEngine.Key, w -> w \ {Fs.FileRead})], // ホットリロード（キーと、ファイル読みの副作用）
        // World を (置き場所, 見せたい物) の列へ投影する。None のゲームは App に描画させず自分の
        // システム内で描く（タイルマップ等の複数チャンネルを直接組むゲーム向け）。
        view = Option[(FontAtlas, w) -> List[Render.Placed] \ ef],
        audio = { before = w, after = w } -> List[String] \ ef,    // 1 フレームの前後から鳴らす音名を導く
        quit = (Frame, w) -> Bool \ ef,                            // 終了判定（既定 = Escape のエッジ）
        debug = Bool,                                              // デバッグ機能（F8 の時間停止・注釈・巻き戻し）を有効にするか
        // view = None のゲームがデバッグ機能を使うための生投影（フォントアトラス名と、World →
        // 描画チャンネル 3 本）。描画はせずチャンネルを返すだけの関数を繋ぐ。
        debugView = Option[(String, w -> (List[GameEngine.Drawable], List[GameEngine.TileMapRenderCmd], List[GameEngine.PolygonRenderCmd]) \ ef)],
        // 注釈の矩形（デザイン座標）と表示中の瞬間の World からテキストを組む。
        // 注釈チケットに world.json として同梱され、リモートデバッグの view=full にもなる。
        worldDump = Option[(Rect2.Rect2, w) -> String \ ef],
        // World の 1 行サマリ。リモートデバッグ（HTTP）の view=status と trace の源。
        statusLine = Option[w -> String \ ef]
    }

    /// 初期 World だけを持つ空の App。絵はまだ無い（withView で繋ぐまで何も描かない）。
    /// 初期値を画面サイズから組みたいゲームは makeWith を使う。
    pub def make(init: w): App[w, ef] =
        makeWith(_ -> checked_ecast(init))

    /// 初期 World を design 解像度（project.json の designWidth/Height）から組む入口。
    /// launch が画面サイズを読んで f へ渡すので、ゲーム側はエンジン API に触れない。
    pub def makeWith(f: Vec2.Vec2 -> w \ ef): App[w, ef] =
        // 既定の hook は純粋だが、フィールド型は効果多相 ef。Pure は任意の ef に安全に広げられるので
        // 本体を checked_ecast で ef へ widen して型を合わせる（呼び出し側が ef を絞る）。
        { init = f,
          startupSystems = Nil,
          updateSystems = Nil,
          reload = None,
          view = None,
          audio = _worlds -> checked_ecast(Nil),
          quit = (frame, _world) -> checked_ecast(justPressed(GameEngine.Key.Escape, frame)),
          debug = false,
          debugView = None,
          worldDump = None,
          statusLine = None }

    /// 起動時に 1 回だけ走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addStartup(sys: w -> w \ ef, app: App[w, ef]): App[w, ef] =
        { startupSystems = List.append(app#startupSystems, sys :: Nil) | app }

    /// 毎フレーム走るシステムを末尾へ繋ぐ（追加順に適用される）。
    pub def addSystem(sys: (Frame, w) -> w \ ef, app: App[w, ef]): App[w, ef] =
        { updateSystems = List.append(app#updateSystems, sys :: Nil) | app }

    /// key が押された瞬間に World を作り直すホットリロードを繋ぐ（ファイル読みの副作用つき）。
    /// 遊びながら設定ファイルを編集し、キー一発で効きを変える用途に。
    pub def reloadOn(key: GameEngine.Key, f: w -> w \ {Fs.FileRead}, app: App[w, ef]): App[w, ef] =
        { reload = Some((key, f)) | app }

    /// World を絵（(置き場所, 見せたい物) の列）へ投影する関数を繋ぐ。
    pub def withView(v: (FontAtlas, w) -> List[Render.Placed] \ ef,
                     app: App[w, ef]): App[w, ef] =
        { view = Some(v) | app }

    /// 1 フレームの前後の World（{before, after}）から鳴らす音名を導く関数を繋ぐ
    /// （再生は App が引き受ける）。
    pub def withAudio(sfx: { before = w, after = w } -> List[String] \ ef, app: App[w, ef]): App[w, ef] =
        { audio = sfx | app }

    /// 終了判定を差し替える。既定は「Escape のエッジで終了」だが、モーダル表示中は
    /// Escape をパネル閉じに使いたい、といったゲームはここで自分の条件を宣言する。
    pub def quitWhen(f: (Frame, w) -> Bool \ ef, app: App[w, ef]): App[w, ef] =
        { quit = f | app }

    /// デバッグ機能（F8 の時間停止・矩形注釈・時間スクラブ）の有効 / 無効を宣言する。
    /// 既定は無効。プレイヤーに配るビルドで時間巻き戻しや内部情報の書き出しが
    /// 使えてしまわないよう、開発時だけ true を渡す（debugFromEnv と組み合わせる）。
    pub def withDebug(enabled: Bool, app: App[w, ef]): App[w, ef] =
        { debug = enabled | app }

    /// 環境変数 DEBUG が空でない値で設定されていれば true（例: `DEBUG=true flix run`）。
    /// Main から `App.withDebug(App.debugFromEnv())` の形で使う。
    pub def debugFromEnv(): Bool \ IO =
        let value = System.getenv("DEBUG");
        not Object.isNull(value) and value != ""

    /// 自前描画（view = None）のゲームがデバッグ機能（F8）を使えるようにする生投影を繋ぐ。
    /// f は World を描画チャンネル（drawable / tileMap / polygon）へ投影する（描画はしない）。
    /// font は一時停止中のメッセージ表示に使うフォントアトラス名（そのゲームが持つ物を指定）。
    pub def withDebugView(font: {font = String},
                          f: w -> (List[GameEngine.Drawable], List[GameEngine.TileMapRenderCmd], List[GameEngine.PolygonRenderCmd]) \ ef,
                          app: App[w, ef]): App[w, ef] =
        { debugView = Some((font#font, f)) | app }

    /// 注釈（F8 の矩形）を書き出すとき「囲った瞬間の World」をテキストにしてチケットへ
    /// world.json として同梱する関数を繋ぐ。絵の情報（annotation.json）とシムの中身を
    /// 突き合わせられるので、見た目と状態の食い違いを注釈だけで特定できるようになる。
    /// f が受け取る矩形はデザイン座標。何をどこまで書くかはゲームが決める
    /// （全フィールドでなく、調査に効く要約でよい）。
    pub def withWorldDump(f: (Rect2.Rect2, w) -> String \ ef, app: App[w, ef]): App[w, ef] =
        { worldDump = Some(f) | app }

    /// World の 1 行サマリ（例: "phase=Playing ball=(163.2,207.9) lives=3"）を繋ぐ。
    /// リモートデバッグ（HTTP）の view=status の本文と、/step の trace の行になる。
    /// 調査に効く値だけを短く。長い一覧は withWorldDump（view=full）側に任せる。
    pub def withStatusLine(f: w -> String \ ef, app: App[w, ef]): App[w, ef] =
        { statusLine = Some(f) | app }

    // ── 純粋な芯（テストはここを直接叩く）──

    /// 前フレームと今フレームのキー集合から Frame を組む。justPressed は差分
    /// （今あって前に無いキー）なので、押しっぱなしはエッジにならない。
    pub def frameOf(prev: {prev = Set[GameEngine.Key]},
                    current: {current = Set[GameEngine.Key]}, dt: Float64,
                    viewport: Vec2.Vec2): Frame =
        { down = current#current,
          justPressed = Set.difference(current#current, prev#prev),
          dt = dt,
          viewport = viewport }

    /// システムの列を追加順（左から右）に World へ畳み込む。
    pub def applySystems(frame: Frame, systems: List[(Frame, w) -> w \ ef], world: w): w \ ef =
        List.foldLeft((acc, sys) -> sys(frame, acc), world, systems)

    // ── ランナー: 起動して、閉じるまで回す ──

    /// App を走らせる単一の効果多相ランナー。startup を 1 回だけ畳み、いま押されているキーを prev の
    /// 種にしてループへ入る（起動時にすでに押されているキーは、一度離すまでエッジにならない）。
    ///
    /// ウィンドウ（GameEngine.Game/Audio）・Fs・ゲーム固有の effect（ef）は 隠蔽せず呼び出し側の
    /// Main が `with` で明示的に張る（effect-oriented の素直な形）。効果多相なので純粋なゲーム（ef = {}）も
    /// effect で状態を持つゲームも同じ launch を使う。前者は Main で LwjglLayer + Fs を張り、後者は加えて
    /// 自分の effect ハンドラ束を張った内側で呼ぶ。
    /// デバッグ有効（withDebug）かつ環境変数 DEBUG_HTTP_PORT があれば、リモートデバッグの
    /// HTTP 口も一緒に立ち上がる（例: `DEBUG=1 DEBUG_HTTP_PORT=7777 flix run`）。
    pub def launch(app: App[w, ef]): Unit \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead + IO) =
        let init = app#init;
        let world0 = List.foldLeft((acc, sys) -> sys(acc), init(GameEngine.Game.getViewportRect()#size), app#startupSystems);
        let bridge = if (canDebug(app)) Option.map(RemoteDebug.start, RemoteDebug.portFromEnv())
                     else None;
        loop(app, world0, InputEvent.currentKeys(), Annotate.initial(), Nil, bridge, false);
        Option.forEach(RemoteDebug.shutdown, bridge)

    /// 時間スクラブ用に持ち回す直近の World の数（60fps で約 5 秒）。
    /// World は不変値なので、保持しているのは共有構造への参照だけで軽い。
    def historyLimit(): Int32 = 300

    /// 毎フレーム: キーを読み Frame に焼く → 終了判定 → リモートコマンド → リロード →
    /// システム → 音 → 描画 → 末尾再帰。前フレームのキー集合・アノテーション状態・
    /// 直近の World 履歴は引数で次のフレームへ渡し続ける。
    ///
    /// F8 で時間停止をトグルできる（view を繋いだゲームのみ）。停止中は World に触れず、
    /// 凍結した絵の上でズーム・パン・矩形ドラッグ（注釈の書き出し）と、← → での時間スクラブ
    /// （直近約 5 秒を 1 フレーム単位で戻る / 進む）だけが動く。解除するとスクラブ位置の
    /// World から再開するので、狙った瞬間へ巻き戻してやり直せる。
    /// 停止中もキーと dt は毎フレーム読み続けるので、解除時に押しっぱなしキーの
    /// 誤エッジや巨大な dt は発生しない。
    ///
    /// bridge はリモートデバッグの HTTP 口（無効なら None）。remoteHold が真の間は
    /// HTTP 側が停止の主導権を持つので、F8 での解除は効かない（/resume で戻す）。
    def loop(app: App[w, ef], world: w, prevKeys: Set[GameEngine.Key],
             anno: Annotate.State, history: List[w],
             bridge: Option[RemoteDebug.Bridge], remoteHold: Bool): Unit \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead + IO) =
        let currentKeys = InputEvent.currentKeys();
        let frame = frameOf(prev = prevKeys, current = currentKeys, readDt(), GameEngine.Game.getViewportRect()#size);
        let wantsQuit = app#quit;
        if (GameEngine.Game.shouldClose() or wantsQuit(frame, world)) ()
        else {
            let remoteRaw = match bridge {
                case Some(b) => RemoteDebug.pollRequest(b)
                case None    => None
            };
            match (remoteRaw, bridge) {
                case (Some(raw), Some(b)) =>
                    // リモートコマンドを処理した実フレームは通常の進行を休む
                    // （停止中は元々進まないし、実行中でも 1 フレームの息継ぎに過ぎない）。
                    let next = handleRemote(app, b, raw,
                        { world = world, anno = anno, history = history, hold = remoteHold });
                    loop(app, next#world, currentKeys, next#anno, next#history, bridge, next#hold)
                case _ => {
                    let toggled = justPressed(GameEngine.Key.F8, frame) and canDebug(app) and not remoteHold;
                    let pausedNow = if (toggled) not anno#paused else anno#paused;
                    // デバッグモードの出入りをウィンドウタイトルとカーソル形状で示す
                    // （停止中は正確に囲うための十字カーソル）
                    if (toggled) {
                        GameEngine.Game.setDebugBadge(pausedNow);
                        GameEngine.Game.setCursor(
                            if (pausedNow) GameEngine.Cursor.Crosshair else GameEngine.Cursor.Default)
                    } else ();
                    if (pausedNow) {
                        let nextAnno = pausedStep(app, world, history, frame, { paused = true | anno });
                        loop(app, world, currentKeys, nextAnno, history, bridge, remoteHold)
                    } else if (anno#paused) {
                        // 一時停止を抜けるフレーム: スクラブ位置の World から再開する。
                        // 巻き戻したぶんの履歴とフレーム番号も、そこを現在として数え直す。
                        let resumed = resumePoint(anno, history, world);
                        renderFrame(app, resumed#world);
                        loop(app, resumed#world, currentKeys, resumed#anno, resumed#history, bridge, remoteHold)
                    } else {
                        let reloaded = applyReload(app, frame, world);
                        let advanced = applySystems(frame, app#updateSystems, reloaded);
                        playSounds(app, reloaded, advanced);
                        renderFrame(app, advanced);
                        // 時間スクラブ用の履歴（debug が無効なら一切持たない = 本番ビルドは無負荷）
                        let nextHistory = if (canDebug(app))
                                              List.take(historyLimit(), advanced :: history)
                                          else Nil;
                        loop(app, advanced, currentKeys, { frame = anno#frame + 1i64 | anno }, nextHistory, bridge, remoteHold)
                    }
                }
            }
        }

    /// 一時停止を抜ける地点: スクラブで表示していた瞬間の World を現在とし、
    /// 履歴とフレーム番号もそこを基準に数え直す（未来側の履歴は捨てる）。
    def resumePoint(anno: Annotate.State, history: List[w], world: w): { world = w, anno = Annotate.State, history = List[w] } =
        { world = worldAt(history, anno#scrub, world),
          history = List.drop(anno#scrub, history),
          anno = { frame = anno#frame - Int32.toInt64(anno#scrub) | Annotate.resetView(anno) } }

    /// 履歴の back フレーム前の World（範囲外なら fallback）。先頭が「停止した瞬間」。
    def worldAt(history: List[w], back: Int32, fallback: w): w =
        history |> List.drop(back) |> List.head |> Option.getWithDefault(fallback)

    /// デバッグ機能が使える構成か（debug 有効 かつ 凍結画面を描く手段 = view か debugView がある）。
    def canDebug(app: App[w, ef]): Bool =
        app#debug and (Option.nonEmpty(app#view) or Option.nonEmpty(app#debugView))

    /// 一時停止中に扱う 1 フレームぶんの描画チャンネル（エンジンへそのまま渡せる形）。
    type alias DebugChannels = {
        drawables = List[GameEngine.Drawable],
        tileMaps = List[GameEngine.TileMapRenderCmd],
        polygons = List[GameEngine.PolygonRenderCmd]
    }

    /// 一時停止中の 1 フレーム。← → の時間スクラブで表示する瞬間を選び、マウスを読んで
    /// ズーム・パン・ドラッグを進め、矩形が確定したら「表示中の瞬間」の注釈一式を書き出し、
    /// その World の絵に見え方とドラッグ中の矩形を重ねて描く。
    /// World には一切触れない（凍結中の絵は選んだ World から毎フレーム投影し直す）。
    /// 絵の出どころは view（Placed 投影）か debugView（生チャンネル投影）のどちらか。
    def pausedStep(app: App[w, ef], world: w, history: List[w], frame: Frame,
                   anno: Annotate.State): Annotate.State \ (ef + GameEngine.Game) =
        let design = GameEngine.Game.getViewportRect()#size;
        let historyLen = Int32.max(1, List.length(history));
        let scrubbed = Annotate.scrubStep(
            { back = isDown(GameEngine.Key.Left, frame),
              backEdge = justPressed(GameEngine.Key.Left, frame),
              fwd = isDown(GameEngine.Key.Right, frame),
              fwdEdge = justPressed(GameEngine.Key.Right, frame) },
            historyLen, anno);
        let displayed = worldAt(history, scrubbed#scrub, world);
        let input = { cursor = GameEngine.Game.getMousePosition(),
                      leftDown = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left),
                      middleDown = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Middle),
                      spaceDown = isDown(GameEngine.Key.Space, frame),
                      scroll = GameEngine.Game.consumeScrollDelta(),
                      design = design };
        let (next, emitted) = Annotate.step(input, scrubbed);
        // 注釈のフレーム番号は「表示中の瞬間」のもの（スクラブぶんを引く）
        let shownFrame = next#frame - Int32.toInt64(next#scrub);
        // 矩形が確定した瞬間だけ、表示中の World をゲームのダンプ関数でテキスト化する
        // （world.json としてチケットに同梱。繋がれていなければ空 = 同梱しない）
        let dumpText = match (emitted, app#worldDump) {
            case (Some(rect), Some(f)) => f(rect, displayed)
            case _                     => ""
        };
        match app#view {
            case Some(toItems) =>
                let atlas = GameEngine.Game.getFontAtlas("default");
                let items = toItems(atlas, displayed);
                let (sprites, polygons) = Render.draw(items);
                let hitList = match emitted {
                    case Some(rect) => Annotate.hits(name -> GameEngine.Game.getTextureInfo(name), rect, items)
                    case None       => Nil
                };
                finishPaused({ design = design, cursor = input#cursor, atlas = atlas,
                               historyLen = historyLen, shownFrame = shownFrame },
                             next, emitted, dumpText,
                             { drawables = sprites, tileMaps = Nil, polygons = polygons }, hitList)
            case None => match app#debugView {
                case Some((fontName, toChannels)) =>
                    let atlas = GameEngine.Game.getFontAtlas(fontName);
                    let (drawables, tileMaps, polygons) = toChannels(displayed);
                    let hitList = match emitted {
                        case Some(rect) =>
                            Annotate.hitsFromDrawables(name -> GameEngine.Game.getTextureInfo(name), rect, drawables)
                        case None => Nil
                    };
                    finishPaused({ design = design, cursor = input#cursor, atlas = atlas,
                                   historyLen = historyLen, shownFrame = shownFrame },
                                 next, emitted, dumpText,
                                 { drawables = drawables, tileMaps = tileMaps, polygons = polygons }, hitList)
                case None => next
            }
        }

    /// 一時停止フレームの締め: 矩形が確定していれば注釈を書き出してトーストを出し、凍結画面を描く。
    def finishPaused(ctx: { design = Vec2.Vec2, cursor = Vec2.Vec2, atlas = FontAtlas,
                            historyLen = Int32, shownFrame = Int64 },
                     anno: Annotate.State, emitted: Option[Rect2.Rect2], dumpText: String,
                     channels: DebugChannels, hitList: List[Annotate.Hit]): Annotate.State \ GameEngine.Game =
        let shown = match emitted {
            case Some(rect) => match writeAnnotation(ctx#design, rect, ctx#shownFrame, dumpText, channels, hitList) {
                case Some(path) => Annotate.showToast("Saved debug file\n${path}", anno)
                case None       => anno
            }
            case None => Annotate.tickToast(anno)
        };
        renderPaused(ctx, shown, channels);
        shown

    /// 確定した矩形の注釈一式（JSON・README の要約・等倍の描画命令）を組んでエンジンへ渡す。
    /// ファイルへの書き出しとスクリーンショット撮影・シャッター音はエンジンの saveAnnotation が
    /// 引き受ける。戻り値は保存先のディレクトリパス（失敗時 None）。
    def writeAnnotation(design: Vec2.Vec2, rect: Rect2.Rect2, frameNo: Int64, dumpText: String,
                        channels: DebugChannels, hitList: List[Annotate.Hit]): Option[String] \ GameEngine.Game =
        let body = Annotate.readmeBody({ frame = frameNo, rect = rect }, hitList);
        GameEngine.Game.saveAnnotation({
            frame = frameNo, rect = rect,
            json = Annotate.annotationJson({ frame = frameNo, design = design, rect = rect }, hitList),
            readmeBody = if (dumpText == "") body else body + "\n- シム状態のダンプ: world.json",
            worldDump = dumpText,
            sprites = channels#drawables, tileMaps = channels#tileMaps, polygons = channels#polygons })

    /// 凍結中の絵を描く: ドラッグ中の矩形を重ね、ズーム・パンを適用して描画命令にする。
    /// 保存完了メッセージとスクラブ位置は見え方の適用後に重ねるので、ズーム中も画面に固定される。
    /// 等倍・ずらし無し・表示物無しのときは通常描画と同じ命令列になる。
    def renderPaused(ctx: { design = Vec2.Vec2, cursor = Vec2.Vec2, atlas = FontAtlas,
                            historyLen = Int32, shownFrame = Int64 },
                     anno: Annotate.State, channels: DebugChannels): Unit \ GameEngine.Game =
        let view = Annotate.viewOf(ctx#design, anno);
        let overlay = match anno#dragStart {
            case Some(start) => Annotate.overlayItems(start, Annotate.toDesign(view, ctx#cursor))
            case None        => Nil
        };
        let (overlaySprites, overlayPolygons) = Render.draw(overlay);
        let toastPlaced = match anno#toast {
            case Some(t) => Annotate.toastItems(ctx#atlas, t#message)
            case None    => Nil
        };
        let scrubPlaced = if (anno#scrub > 0 and anno#scrubShow > 0)
                              Annotate.scrubIndicatorItems(ctx#atlas, ctx#design, anno#scrub, ctx#historyLen)
                          else Nil;
        let (fixedSprites, fixedPolygons) = Render.draw(List.append(toastPlaced, scrubPlaced));
        GameEngine.Game.renderCommands(
            List.append(Annotate.applyInspect(view, List.append(channels#drawables, overlaySprites)), fixedSprites),
            Annotate.applyInspectTiles(view, channels#tileMaps),
            List.append(Annotate.applyInspectPoly(view, List.append(channels#polygons, overlayPolygons)), fixedPolygons))

    /// reloadOn で繋いだキーが押された瞬間だけ、リロード関数で World を作り直す。
    def applyReload(app: App[w, ef], frame: Frame, world: w): w \ {Fs.FileRead} =
        match app#reload {
            case Some((key, f)) => if (justPressed(key, frame)) f(world) else world
            case None           => world
        }

    /// audio の導いた音名を鳴らす（システム適用の前後の World から導く）。
    def playSounds(app: App[w, ef], before: w, after: w): Unit \ (ef + GameEngine.Audio) =
        let derive = app#audio;
        derive({ before = before, after = after }) |> List.forEach(name -> GameEngine.Audio.playAudio(name))

    /// 時計は World の外に住む。エンジンが値をクランプするので、長いカクつきでも先へワープしない。
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// view の投影した絵を描画命令にしてエンジンへ渡す（タイルマップは使わないので空の列を添える）。
    /// view = None のゲームは App では描かない（自分のシステム内で renderCommands を呼ぶ）。
    def renderFrame(app: App[w, ef], world: w): Unit \ (ef + GameEngine.Game) =
        match app#view {
            case None          => ()
            case Some(toItems) =>
                let atlas = GameEngine.Game.getFontAtlas("default");
                let (sprites, polygons) = Render.draw(toItems(atlas, world));
                GameEngine.Game.renderCommands(sprites, Nil, polygons)
        }

    // ── リモートデバッグ（HTTP）: コマンド処理 ──
    //
    // 外部プロセス（AI エージェント等）が curl で送るコマンドをゲームループ側で処理する。
    // 主役は /step: ゲームを止めたまま「キー入力の台本」を 1 コマ = 1 フレームで実行し、
    // 進んだ結果（鳴った音・状態サマリ）を 1 応答で返す。実時間を追いかけられない相手でも、
    // ゲーム側が待つことでフレーム精度の操作と観測ができる。

    /// リモートコマンド処理が次の実フレームへ持ち回す状態。
    type alias RemoteNext[w] = {
        world = w,               // 現在の World（/step で進み得る）
        anno = Annotate.State,   // 停止・スクラブ等の状態（/halt /step で paused になる）
        history = List[w],       // スクラブ用の履歴（/step の合成フレームも積む）
        hold = Bool              // HTTP 側が停止の主導権を持っているか（真の間 F8 は無効）
    }

    /// リクエスト 1 件を捌き、応答をブリッジへ書いてから次の状態を返す。
    /// どの経路でも必ず 1 回 respond する（しないと HTTP 側が 10 秒待って 503 になる）。
    def handleRemote(app: App[w, ef], bridge: RemoteDebug.Bridge, raw: String,
                     ctx: RemoteNext[w]): RemoteNext[w] \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead + IO) =
        let request = RemoteDebug.parseRequest(raw);
        match (request#method, request#path) {
            case ("GET", "/help")    => answer(RemoteDebug.helpText(), bridge, ctx)
            case ("POST", "/halt")   => remoteHalt(app, bridge, ctx)
            case ("POST", "/resume") => remoteResume(bridge, ctx)
            case ("GET", "/state")   => remoteState(app, bridge, request, ctx)
            case ("POST", "/step")   => remoteStepCommand(app, bridge, request, ctx)
            case (m, p)              => answer("error: no route for ${m} ${p} (see GET /help)\n", bridge, ctx)
        }

    /// 応答を書いてから next を返すだけの小さな合流点。
    def answer(text: String, bridge: RemoteDebug.Bridge, next: RemoteNext[w]): RemoteNext[w] \ IO =
        RemoteDebug.respond(text, bridge);
        next

    /// 停止に入る見た目（ウィンドウタイトルのバッジと十字カーソル）。F8 と同じ絵柄。
    def enterHaltMarkers(): Unit \ GameEngine.Game =
        GameEngine.Game.setDebugBadge(true);
        GameEngine.Game.setCursor(GameEngine.Cursor.Crosshair)

    /// 停止を抜ける見た目（バッジを外して通常カーソルへ）。
    def exitHaltMarkers(): Unit \ GameEngine.Game =
        GameEngine.Game.setDebugBadge(false);
        GameEngine.Game.setCursor(GameEngine.Cursor.Default)

    /// POST /halt: 時間を止めて lockstep モードへ入る。既に停止中でも安全（冪等）。
    def remoteHalt(app: App[w, ef], bridge: RemoteDebug.Bridge,
                   ctx: RemoteNext[w]): RemoteNext[w] \ (ef + GameEngine.Game + IO) =
        if (not ctx#anno#paused) enterHaltMarkers() else ();
        let shownFrame = ctx#anno#frame - Int32.toInt64(ctx#anno#scrub);
        let displayed = worldAt(ctx#history, ctx#anno#scrub, ctx#world);
        answer("ok mode=halted frame=${shownFrame}\n[status]\n${statusText(app, displayed)}\n",
               bridge, { anno = { paused = true | ctx#anno }, hold = true | ctx })

    /// POST /resume: 実時間の進行へ戻す。スクラブで過去を見ていたらそこから再開する。
    def remoteResume(bridge: RemoteDebug.Bridge,
                     ctx: RemoteNext[w]): RemoteNext[w] \ (GameEngine.Game + IO) =
        if (not ctx#anno#paused)
            answer("ok mode=running frame=${ctx#anno#frame}\n", bridge, { hold = false | ctx })
        else {
            exitHaltMarkers();
            let resumed = resumePoint(ctx#anno, ctx#history, ctx#world);
            answer("ok mode=running frame=${resumed#anno#frame}\n", bridge,
                   { world = resumed#world, anno = resumed#anno, history = resumed#history, hold = false })
        }

    /// GET /state: 進めずに観測だけ返す。停止中はスクラブで表示中の瞬間を見る。
    def remoteState(app: App[w, ef], bridge: RemoteDebug.Bridge, request: RemoteDebug.Request,
                    ctx: RemoteNext[w]): RemoteNext[w] \ (ef + GameEngine.Game + IO) =
        match RemoteDebug.parseParams(request#params) {
            case Err(message) => answer(message + "\n", bridge, ctx)
            case Ok(stepParams) =>
                let displayed = worldAt(ctx#history, ctx#anno#scrub, ctx#world);
                let modeName = if (ctx#anno#paused) "halted" else "running";
                let shownFrame = ctx#anno#frame - Int32.toInt64(ctx#anno#scrub);
                answer("ok frame=${shownFrame} mode=${modeName}\n" + viewBlock(app, stepParams, displayed),
                       bridge, ctx)
        }

    /// POST /step: 台本を 1 コマ = 1 フレームで実行し、結果を 1 応答に束ねて返す。
    /// 実行中に来たら自動で停止してから進める。スクラブで過去を見ていたら
    /// 「表示中の瞬間から再開して進める」（F8 解除と同じ意味論。未来側の履歴は捨てる）。
    def remoteStepCommand(app: App[w, ef], bridge: RemoteDebug.Bridge, request: RemoteDebug.Request,
                          ctx: RemoteNext[w]): RemoteNext[w] \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead + IO) =
        match (RemoteDebug.parseParams(request#params), RemoteDebug.parseScript(request#body)) {
            case (Err(message), _) => answer(message + "\n", bridge, ctx)
            case (_, Err(message)) => answer(message + "\n", bridge, ctx)
            case (Ok(stepParams), Ok(script)) =>
                if (List.isEmpty(script))
                    answer("error: empty script (body needs idle/press/hold lines; see GET /help)\n", bridge, ctx)
                else {
                    if (not ctx#anno#paused) enterHaltMarkers() else ();
                    let base = resumePoint(ctx#anno, ctx#history, ctx#world);
                    let outcome = remoteStep(app, base#world, base#anno#frame, script, stepParams);
                    let annoAfter = { paused = true,
                                      frame = base#anno#frame + Int32.toInt64(outcome#framesRun) | base#anno };
                    let historyAfter = List.take(historyLimit(),
                                                 List.append(outcome#newHistory, base#history));
                    let total = Int32.min(List.length(script), stepParams#maxFrames);
                    let text = RemoteDebug.stepHeader({ stepped = outcome#framesRun, total = total,
                                                        frame = annoAfter#frame,
                                                        stoppedBy = outcome#stoppedBy, quit = outcome#quit })
                             + RemoteDebug.eventsBlock(outcome#sounds)
                             + RemoteDebug.traceBlock(outcome#traceLines)
                             + viewBlock(app, stepParams, outcome#world);
                    answer(text, bridge,
                           { world = outcome#world, anno = annoAfter, history = historyAfter, hold = true })
                }
        }

    /// 応答に載せる観測本文（[status] / [full] / [scene] のブロック）。
    def viewBlock(app: App[w, ef], stepParams: RemoteDebug.StepParams, world: w): String \ (ef + GameEngine.Game) =
        match stepParams#view {
            case RemoteDebug.View.Silent  => ""
            case RemoteDebug.View.Status  => "[status]\n" + statusText(app, world) + "\n"
            case RemoteDebug.View.Summary => "[status]\n" + statusText(app, world) + "\n"
            case RemoteDebug.View.Full    =>
                let rect = Option.getWithDefault(GameEngine.Game.getViewportRect(), stepParams#rect);
                match app#worldDump {
                    case Some(dump) => "[full]\n" + RemoteDebug.capBody(dump(rect, world)) + "\n"
                    case None       => "[full]\n(no worldDump wired; try view=scene)\n"
                }
            case RemoteDebug.View.Scene   =>
                let rect = Option.getWithDefault(GameEngine.Game.getViewportRect(), stepParams#rect);
                sceneText(app, rect, world) + "\n"
        }

    /// view=status の本文。ゲームが withStatusLine を繋いでいなければその旨を返す。
    def statusText(app: App[w, ef], world: w): String \ ef =
        match app#statusLine {
            case Some(toLine) => toLine(world)
            case None         => "(no statusLine wired; use view=scene or wire App.withStatusLine)"
        }

    /// view=scene の本文。view（Placed 投影）か debugView（生チャンネル投影）から、
    /// 矩形に重なる描画物を列挙する。どちらも無いゲームは観測手段が無い旨を返す。
    def sceneText(app: App[w, ef], rect: Rect2.Rect2, world: w): String \ (ef + GameEngine.Game) =
        match (app#view, app#debugView) {
            case (Some(toItems), _) =>
                let atlas = GameEngine.Game.getFontAtlas("default");
                let hitList = Annotate.hits(name -> GameEngine.Game.getTextureInfo(name), rect,
                                            toItems(atlas, world));
                RemoteDebug.sceneBlock(rect, hitList)
            case (None, Some((_, toChannels))) =>
                let (drawables, _, _) = toChannels(world);
                let hitList = Annotate.hitsFromDrawables(name -> GameEngine.Game.getTextureInfo(name),
                                                         rect, drawables);
                RemoteDebug.sceneBlock(rect, hitList)
            case (None, None) => "[scene]\n(no view/debugView wired)"
        }

    // ── リモートデバッグ（HTTP）: /step の実行器 ──

    /// /step 1 回ぶんの実行結果。
    type alias StepOutcome[w] = {
        world = w,                       // 実行後の World
        newHistory = List[w],            // 実行中に積んだ World（新しい順・上限つき）
        framesRun = Int32,               // 実際に進んだコマ数
        sounds = List[(Int64, String)],  // (絶対フレーム番号, 音名) の時系列
        stoppedBy = String,              // "script" / "until:sfx" / "until:quiet" / "quit" / "max"
        quit = Bool,                     // 終了条件（ウィンドウ閉 / quitWhen）に触れて止まったか
        traceLines = List[String]        // trace=status:K で集めた行（時系列）
    }

    /// /step の台本実行中に持ち回る折り畳みの状態。
    type alias StepFold[w] = {
        world = w,                        // いまの World
        prev = Set[GameEngine.Key],       // 前のコマのキー集合（エッジ判定用）
        done = Int32,                     // 進んだコマ数
        quietRun = Int32,                 // 無音が続いているコマ数（until=quiet 用）
        acc = List[w],                    // 積んだ World（新しい順）
        stopped = String,                 // 停止理由（"" = 続行）
        quit = Bool,                      // 終了条件に触れたか
        trace = List[String]              // trace の行（新しい順）
    }

    /// 台本をコマ送りで実行する芯。TestWorldJourney の headless 駆動と同じ発想で、
    /// Game / Audio をプロキシハンドラで包んで本番のシステム列をそのまま回す:
    ///   - dt は実時計でなく固定値（既定 1/60 秒）→ 何度やっても同じ結果になる
    ///   - キーは台本のコマから返す（Frame 経由でも直読みでも台本に従う）
    ///   - 描画は捨てる（vsync 待ちが無くなるので数百コマが一瞬で回る）
    ///   - 音は鳴らさず (フレーム番号, 音名) で記録して観測データにする
    /// それ以外の操作（GLFW のイベント処理を含む shouldClose 等）は実ハンドラへ素通しする。
    def remoteStep(app: App[w, ef], world0: w, frame0: Int64, script: RemoteDebug.Script,
                   stepParams: RemoteDebug.StepParams): StepOutcome[w] \ (ef + GameEngine.Game + GameEngine.Audio + Fs.FileRead) =
        region rc {
            let soundsRef: Ref[List[(Int64, String)], rc] = Ref.fresh(rc, Nil);
            let frameNoRef: Ref[Int64, rc] = Ref.fresh(rc, frame0);
            let keysRef: Ref[Set[GameEngine.Key], rc] = Ref.fresh(rc, Set.empty());
            let effective = List.take(stepParams#maxFrames, script);
            let truncated = List.length(script) > List.length(effective);
            let start: StepFold[w] = { world = world0, prev = Set.empty(), done = 0, quietRun = 0,
                                       acc = Nil, stopped = "", quit = false, trace = Nil };
            let final = run {
                List.foldLeft((state, frameKeys) -> {
                    if (state#stopped != "") state
                    else {
                        Ref.put(frameKeys, keysRef);
                        let frameNo = Ref.get(frameNoRef) + 1i64;
                        Ref.put(frameNo, frameNoRef);
                        // 実ハンドラへ素通し = glfwPollEvents が回り、窓が固まらない・閉じられる
                        let closing = GameEngine.Game.shouldClose();
                        let frame = frameOf(prev = state#prev, current = frameKeys, stepParams#dtSeconds, GameEngine.Game.getViewportRect()#size);
                        let wantsQuit = app#quit;
                        if (closing or wantsQuit(frame, state#world))
                            { stopped = "quit", quit = true | state }
                        else {
                            let capturedBefore = List.length(Ref.get(soundsRef));
                            let reloaded = applyReload(app, frame, state#world);
                            let advanced = applySystems(frame, app#updateSystems, reloaded);
                            // 音の 2 経路: システムが直接鳴らした分はプロキシが記録済み、
                            // withAudio 由来はここで導出して記録する。
                            let derive = app#audio;
                            derive({ before = reloaded, after = advanced })
                                |> List.forEach(name ->
                                       Ref.put((frameNo, name) :: Ref.get(soundsRef), soundsRef));
                            let soundsNow = Ref.get(soundsRef)
                                |> List.take(List.length(Ref.get(soundsRef)) - capturedBefore)
                                |> List.map(snd);
                            let (stoppedNow, quietNow) =
                                RemoteDebug.stopCheck(stepParams#stopWhen, soundsNow, state#quietRun);
                            let traceNow = match stepParams#traceEvery {
                                case Some(every) =>
                                    if (Int32.modulo(state#done + 1, every) == 0)
                                        "f=${frameNo} ${statusText(app, advanced)}" :: state#trace
                                    else state#trace
                                case None => state#trace
                            };
                            { world = advanced, prev = frameKeys, done = state#done + 1,
                              quietRun = quietNow, acc = advanced :: state#acc,
                              stopped = stoppedNow, quit = false, trace = traceNow }
                        }
                    }
                }, start, effective)
            } with handler GameEngine.Game {
                def getDeltaTime(k)             = k(Duration.seconds(stepParams#dtSeconds))
                def isKeyPressed(key, k)        = k(Set.memberOf(key, Ref.get(keysRef)))
                def renderCommands(_s, _t, _p, k) = k(())
                def shouldClose(k)              = k(GameEngine.Game.shouldClose())
                def initTileBuffer(instances, k) = k(GameEngine.Game.initTileBuffer(instances))
                def getMousePosition(k)         = k(GameEngine.Game.getMousePosition())
                def isMouseButtonPressed(b, k)  = k(GameEngine.Game.isMouseButtonPressed(b))
                def consumeScrollDelta(k)       = k(GameEngine.Game.consumeScrollDelta())
                def getFontAtlas(name, k)       = k(GameEngine.Game.getFontAtlas(name))
                def getViewportRect(k)          = k(GameEngine.Game.getViewportRect())
                def getTextureInfo(name, k)     = k(GameEngine.Game.getTextureInfo(name))
                def setCursor(cursor, k)        = k(GameEngine.Game.setCursor(cursor))
                def saveAnnotation(req, k)      = k(GameEngine.Game.saveAnnotation(req))
                def setDebugBadge(enabled, k)   = k(GameEngine.Game.setDebugBadge(enabled))
            } with handler GameEngine.Audio {
                def playAudio(name, k)  = {
                    Ref.put((Ref.get(frameNoRef), name) :: Ref.get(soundsRef), soundsRef);
                    k()
                }
                def stopAudio(name, k)          = k(GameEngine.Audio.stopAudio(name))
                def setVolume(name, volume, k)  = k(GameEngine.Audio.setVolume(name, volume))
                def setLooping(name, looping, k) = k(GameEngine.Audio.setLooping(name, looping))
            };
            { world = final#world,
              newHistory = List.take(historyLimit(), final#acc),
              framesRun = final#done,
              sounds = List.reverse(Ref.get(soundsRef)),
              stoppedBy = if (final#stopped != "") final#stopped
                          else if (truncated) "max" else "script",
              quit = final#quit,
              traceLines = List.reverse(final#trace) }
        }
}
