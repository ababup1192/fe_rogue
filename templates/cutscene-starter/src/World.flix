// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 見下ろしの里を 1 マスずつ歩き、住人に話しかけ、薬草を拾う。
// 扉の鍵は物ではなく約束 — 頼まれた数の薬草を持って約束の相手と話すと扉が開く。
// 盤面のデータ（rows・配置・文言）は MapDoc、手触りは KindDoc — 実行中の状態はこの World だけが持つ。
//
// 場面の移り変わり（Phase）:
//
//     Title ──決定(confirm/begin)──▶ Play ──薬草が goal 個(pickUp)──▶ Clear
//       ▲                                                                │
//       └─────────────────────決定(confirm)──────────────────────────────┘
//
// 遷移を起こす関数の doc には [遷移: X→Y] を付けてある（探すときの目印）。
//
// Doc が壊れていても止まらない（fail-open の 3 段）:
//   読めない → 既定値で起動（Controls.loadDocs / *Doc.defaults）
//   一部が欠け → その欄だけ既定値（fromJson が欄ごとに拾う）
//   型が違う   → その欄は既定値のまま（数を入れる欄に文字 等）
// だからプレイヤーの前でクラッシュしない。編集ミスは既定に倒れて遊びは続く。
mod World {

    /// いま画面が何をしているか。Title = 表紙（決定で歩き出す）、Play = 里を歩いている、
    /// Clear = 薬草がそろった（決定で表紙へ戻る）。
    pub enum Phase with Eq, ToString {
        case Title
        case Play
        case Clear
    }

    /// 起動時に読む Doc の束（Main と Bake が同じ形で組む）。
    pub type alias Docs = {
        map = MapDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        terrain = TerrainDoc.Doc,
        scenes = List[CutsceneDoc.Doc]
    }

    /// ゲームの状態。hero / facing = 主人公のマスと向き、stepGauge = 次の一歩までの残り秒、
    /// steps = 歩いた歩数（歩きのコマ送りに使う）、herbs = まだ拾っていない薬草のマス、
    /// picked = 拾った薬草の数、doorOpen = 扉が開いたか、
    /// dialog = ふきだし（開いている間は歩けない）、talkingTo = 話し相手のマス（ふきだしの位置）。
    pub type alias World = {
        map = MapDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        terrain = TerrainDoc.Doc,
        phase = Phase,
        hero = Grid.Cell,
        facing = Dir4.Dir4,
        stepGauge = Float64,
        steps = Int32,
        herbs = List[Grid.Cell],
        picked = Int32,
        doorOpen = Bool,
        dialog = UiDialog.Dialog,
        talkingTo = Option[Grid.Cell],
        // 火の玉(敵)。居るマスと、次の 1 歩までの残り秒。間取りの Doc が宣言しなければ居ない。
        wisp = Option[Grid.Cell],
        wispGauge = Float64,
        // 火の玉の向かい先(イベントシーンが指す目的のマス)。向かっている間は主人公を
        // 追わず、着いたら消える。遊びの間は None のまま。
        wispGoal = Option[Grid.Cell],
        // 主人公の向かい先(イベントシーンの意図)。入力と同じ規則で 1 歩ずつ歩き、
        // 着いたら消える。遊びの間は None のまま。
        heading = Option[Grid.Cell],
        // 白い瞬き・画面の揺れの残り秒(イベントシーンの口。0 なら画面には影も出ない)。
        flash = Float64,
        quake = Float64,
        // 読み込んだイベントシーンの束と、演じている最中のシーンの進行状態。
        // 進行を回すのは Director(World は状態を運ぶだけ — 演じ方は知らない)。
        scenes = List[CutsceneDoc.Doc],
        scene = Option[SceneSeq.State[CutsceneDoc.Guarded, Cutscene.Progress]],
        // シーン開始の合図(始めたいシーンの id。空なら無し)。begin が間取りの opening から
        // 立て、Director が拾って演じ始める — World は Cutscene の関数を呼ばない。
        cue = String,
        // 暗転の幕の濃さ(0 = 無し、1 = 真っ黒)。イベントシーン(Cutscene)の口 —
        // 遊びの間は 0 のままで、画面には影も出ない。
        curtain = Float64,
        // 直前に演じ終えたシーンの報せ(飛ばしたカットとその理由。JSON と同じ順)。
        // Director.settle が格納し、SceneNotes.step が debug/ へ写す。
        sceneNotes = List[String],
        // SceneNotes.step が前回書いた内容の指紋(同じ報せを毎フレーム書かないため)。
        sceneNotesWritten = String,
        activeDocsWritten = String
    }

    // ── 盤の寸法（design 480×300 の中の定数。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 300.0

    /// タイルの 1 辺（px）。24×15 マスで画面がちょうど埋まる。
    pub def tileSize(): Float64 = 20.0

    pub def spritePath(): String = "assets/rpg.sprite.json"

    pub def terrainPath(): String = "assets/rpg.terrain.json"

    /// ゲーム開始時の状態。表紙から始まる。
    pub def initial(docs: Docs): World =
        { map = docs#map, kind = docs#kind, theme = docs#theme, sprites = docs#sprites,
          terrain = docs#terrain,
          phase = Phase.Title,
          hero = docs#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = docs#map#herbs, picked = 0, doorOpen = false,
          dialog = UiDialog.closed(), talkingTo = None,
          wisp = docs#map#wisp, wispGauge = 0.0, wispGoal = None,
          heading = None, flash = 0.0, quake = 0.0,
          scenes = docs#scenes, scene = None, cue = "", curtain = 0.0,
          sceneNotes = Nil, sceneNotesWritten = "",
          activeDocsWritten = "" }

    /// シーンの口を仕舞う — イベントシーンが触る欄(向かい先・瞬き・揺れ・幕・進行・合図)を
    /// ぜんぶ遊びの既定へ戻す。歩き出し(begin)・場面の仕度(stagedAt)・脚本の差し替え
    /// (withScenes)・演じ終わり(Director.settle)が同じ列をここで畳む —
    /// 口が増えたらこの 1 箇所に足せば、仕舞い忘れの写経ずれが起きない。
    pub def restStage(w: World): World =
        { wispGoal = None, heading = None, flash = 0.0, quake = 0.0,
          scene = None, cue = "", curtain = 0.0 | w }

    /// 里を歩ける状態に置き直す（表紙から始めるとき・間取りの Doc を差し替えたとき）。
    /// 薬草は全部戻り、扉は閉じ、主人公は start のマスに立つ。[遷移: Title→Play]
    def begin(w: World): World =
        { phase = Phase.Play,
          hero = w#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = w#map#herbs, picked = 0, doorOpen = false,
          dialog = UiDialog.closed(), talkingTo = None,
          wisp = w#map#wisp, wispGauge = 0.0,
          cue = w#map#opening | restStage(w) }

    // ── 収支の導出 ──

    /// クリアに要る薬草の数。置いてある数より多くは求めない（詰みを作らない）。最低 1。
    pub def goalOf(w: World): Int32 =
        Int32.max(1, Int32.min(w#map#goal, List.length(w#map#herbs)))

    /// ともっている灯りの数（薬草を拾うたびひとつ点く。灯りの数より多くは点かない）。
    pub def lampsLit(w: World): Int32 =
        Int32.min(w#picked, List.length(w#map#lamps))

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。
    /// Studio の「表示中」バッジの材料（ActiveDocs.step が debug/ に名乗る）。
    /// 表紙とクリアの幕でも盤は霧の下に見えているので map / theme / sprite は常に表示中。
    /// 手触り（kind: 歩く速さ・文字送り）は里を歩いている間だけ —
    /// 全部を常時 active にしない（バッジの意味が死ぬ）。
    pub def activeDocs(w: World): List[(String, List[String])] =
        let base = ("map", MapDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("sprite", spritePath() :: Nil)
            :: ("terrain", terrainPath() :: Nil)
            :: Nil;
        match w#phase {
            case Phase.Play => List.append(base, ("kind", KindDoc.path() :: Nil) :: Nil)
            case _          => base
        }

    // ── 歩ける・ぶつかるの規則 ──

    /// cell へ歩けるか。盤の中で、石垣でなく、住人が立っておらず、閉じた扉でもないこと。
    pub def walkable(cell: Grid.Cell, w: World): Bool =
        Grid.inRectOf(cell, MapDoc.cols(w#map), MapDoc.rowCount(w#map))
            and not MapDoc.solidAt(cell, w#map)
            and Option.isEmpty(MapDoc.villagerAt(cell, w#map))
            and not (MapDoc.sameCell(cell, w#map#door#cell) and not w#doorOpen)

    /// 1 歩の規則: まず向きを変え、行き先に歩ければ進み、薬草があれば拾う。
    /// 歩けなければ向きだけ変わる（壁の前で足踏みしない）。
    pub def stepOnce(direction: Dir4.Dir4, w: World): World =
        let faced = { facing = direction | w };
        let target = Grid.neighborOf(w#hero, direction);
        if (walkable(target, faced))
            pickUp({ hero = target, steps = w#steps + 1 | faced })
        else
            faced

    /// いま立っているマスの薬草を拾う。goal に届いたらクリア（Phase.Clear）。[遷移: Play→Clear]
    /// 拾った薬草は盤から消えるので、同じマスをまた踏んでも二度は数えない。
    def pickUp(w: World): World =
        if (List.exists(cell -> MapDoc.sameCell(cell, w#hero), w#herbs)) {
            let picked = w#picked + 1;
            { herbs = List.filter(cell -> not MapDoc.sameCell(cell, w#hero), w#herbs),
              picked = picked,
              phase = if (picked >= goalOf(w)) Phase.Clear else w#phase | w }
        } else w

    /// 毎フレーム: ふきだしの文字送りを進め、開いていなければ歩みを進める。
    /// ふきだしが開いている間は歩けない（会話中に動かないのはルール）。
    /// 歩く速さは KindDoc（walk マス/秒）— 押しっぱなしで 1/walk 秒ごとに 1 歩。
    pub def step(direction: Option[Dir4.Dir4], dt: Float64, w0: World): World =
        let w = { flash = Clock.countdown(w0#flash, dt),
                  quake = Clock.countdown(w0#quake, dt) | w0 };
        match w#phase {
            case Phase.Play => {
                let talked = { dialog = UiDialog.step(cps = w#kind#cps, dt, w#dialog) | w };
                if (UiDialog.isOpen(talked#dialog))
                    talked
                else
                    walk(steer(direction, talked), Clock.countdown(talked#stepGauge, dt), talked)
                        |> settleHeading
                        |> haunt(dt)
            }
            case _ => w
        }

    /// 今この拍に踏み出すべき向き。入力が押されていればそれが勝ち、押されていなければ
    /// 向かい先(heading)への最短の 1 歩(Steering.chase)を選ぶ。道が無ければ踏み出さない。
    def steer(direction: Option[Dir4.Dir4], w: World): Option[Dir4.Dir4] =
        match (direction, w#heading) {
            case (Some(_), _)       => direction
            case (None, None)       => None
            case (None, Some(goal)) =>
                Steering.chase(c -> { let (cx, cy) = c; walkable({ x = cx, y = cy }, w) },
                               (w#hero#x, w#hero#y), (goal#x, goal#y),
                               MapDoc.cols(w#map) * MapDoc.rowCount(w#map))
                    |> Option.map(cell -> {
                        let (cx, cy) = cell;
                        if (cx < w#hero#x) Dir4.Left
                        else if (cx > w#hero#x) Dir4.Right
                        else if (cy < w#hero#y) Dir4.Up
                        else Dir4.Down
                    })
        }

    /// 向かい先(heading)に着いていたら意図を消す。
    def settleHeading(w: World): World =
        match w#heading {
            case Some(goal) if MapDoc.sameCell(w#hero, goal) => { heading = None | w }
            case _ => w
        }

    // ── 火の玉（敵）の規則 ──

    /// 火の玉が浮かんで入れるマスか。石垣だけが行き止まり — 畑も閉じた木戸も越えていく
    /// （浮いているので床を踏まない）。住人のマスには入らない（すり抜けさせない）。
    /// **主人公のマスには入れる** — 入った拍が「つかまった」。
    pub def wispCanFloat(cell: Grid.Cell, w: World): Bool =
        Grid.inRectOf(cell, MapDoc.cols(w#map), MapDoc.rowCount(w#map))
            and not MapDoc.solidAt(cell, w#map)
            and Option.isEmpty(MapDoc.villagerAt(cell, w#map))

    /// 火の玉が 1 歩詰めるまでの秒（kind#wisp マス/秒の逆数）。
    def wispInterval(w: World): Float64 =
        1.0 / Float64.max(0.5, w#kind#wisp)

    /// 火の玉の歩の間隔（イベントシーンが脚本どおりの速さで滑らせるための読み口）。
    pub def wispPace(w: World): Float64 =
        wispInterval(w)

    /// 火の玉の拍を 1 コマぶん先送りする — イベントシーンが**気まぐれな追跡**を凍らせる口。
    /// 脚本の指図（wispGoal）があるときは凍らせない — 指図された動きは演じている間も進む。
    pub def calmWisp(w: World): World =
        if (not Option.isEmpty(w#wispGoal)) w
        else { wispGauge = Float64.max(w#wispGauge, wispInterval(w)) | w }

    /// 事実の名前 → いま成り立っているか（イベントシーンの守衛 only / unless が引く表）。
    /// 何が条件になれるかはゲームの個性なので World が持つ — この里では
    /// "door"（木戸が開いた）と "herb"（薬草を 1 つ以上持っている）。知らない名前は偽。
    pub def holdsFact(name: String, w: World): Bool =
        match name {
            case "door" => w#doorOpen
            case "herb" => w#picked > 0
            case _      => false
        }

    /// 火の玉の拍。残り秒が尽きるたび 1 歩動く — 向かい先（wispGoal。イベントシーンの
    /// 指図）があればそちらへ、無ければ主人公へ最短の 1 歩（Steering.chase）を詰める。
    /// 主人公のマスへ入ったら「つかまった」— 主人公は入り口へ戻され、火の玉は棲み処へ帰る。
    /// 道が無ければその拍は動かない（盤面が変われば次の拍でまた考える）。
    def haunt(dt: Float64, w: World): World =
        match w#wisp {
            case None       => w
            case Some(cell) => {
                let gauge = Clock.countdown(w#wispGauge, dt);
                if (gauge > 0.0) { wispGauge = gauge | w }
                else match w#wispGoal {
                    case Some(goal) =>
                        // 指図のある火の玉は主人公を捕まえない(演出の駒に徹する)。
                        if (MapDoc.sameCell(cell, goal))
                            { wispGoal = None, wispGauge = wispInterval(w) | w }
                        else {
                            let sent = Steering.chase(c -> { let (cx, cy) = c;
                                    wispCanFloat({ x = cx, y = cy }, w)
                                        and not MapDoc.sameCell({ x = cx, y = cy }, w#hero) },
                                (cell#x, cell#y), (goal#x, goal#y),
                                MapDoc.cols(w#map) * MapDoc.rowCount(w#map))
                                |> Option.map(c -> { let (cx, cy) = c; { x = cx, y = cy } })
                                |> Option.getWithDefault(cell);
                            { wisp = Some(sent), wispGauge = wispInterval(w) | w }
                        }
                    case None => {
                        let stalked = Steering.chase(c -> { let (cx, cy) = c;
                                wispCanFloat({ x = cx, y = cy }, w) },
                            (cell#x, cell#y), (w#hero#x, w#hero#y),
                            MapDoc.cols(w#map) * MapDoc.rowCount(w#map))
                            |> Option.map(c -> { let (cx, cy) = c; { x = cx, y = cy } })
                            |> Option.getWithDefault(cell);
                        if (MapDoc.sameCell(stalked, w#hero)) caught(w)
                        else { wisp = Some(stalked), wispGauge = wispInterval(w) | w }
                    }
                }
            }
        }

    /// つかまった拍。主人公は入り口へ戻され、火の玉は棲み処へ帰り、ひとことが出る。
    /// 薬草と扉はそのまま — 罰は「歩き直し」だけ（詰みを作らない）。
    def caught(w: World): World =
        { hero = w#map#start, facing = Dir4.Down,
          wisp = w#map#wisp, wispGauge = wispInterval(w),
          dialog = UiDialog.openWith(
              { speaker = "", body = RichText.plain(w#map#caught) :: Nil } :: Nil),
          talkingTo = Some(w#map#start) | w }

    /// イベントシーン（Cutscene）の始まりの状態に置く。マス・向きを合わせ、
    /// ふきだしを閉じた歩ける状態で始める。この関数が World に居るのは、
    /// 場面の仕度が World の内臓（phase・dialog・幕）に触るから —
    /// 外から旗を立てさせると、仕組みを変えた人がそこに気づけない。
    /// 立ちマスが石垣なら立ち位置は動かさない（fail-open — 誤りは画に見える）。
    pub def stagedAt(spot: { cell = Grid.Cell, facing = Dir4.Dir4 }, w: World): World =
        let placed = { phase = Phase.Play, facing = spot#facing,
                       stepGauge = 0.0,
                       dialog = UiDialog.closed(), talkingTo = None | restStage(w) };
        if (walkable(spot#cell, placed)) { hero = spot#cell | placed } else placed

    /// 歩みの拍。向きは押せばすぐ変わり、gauge が 0 になった拍だけ 1 歩進む。
    /// 実際に進んだら次の一歩まで stepInterval を貯め直す。
    def walk(direction: Option[Dir4.Dir4], gauge: Float64, w: World): World =
        match direction {
            case None => { stepGauge = gauge | w }
            case Some(d) =>
                if (gauge > 0.0)
                    { stepGauge = gauge, facing = d | w }
                else {
                    let stepped = stepOnce(d, { stepGauge = gauge | w });
                    if (not MapDoc.sameCell(stepped#hero, w#hero))
                        { stepGauge = stepInterval(w) | stepped }
                    else stepped
                }
        }

    /// 1 歩にかける秒数（walk マス/秒の逆数。1 未満の walk は 1 マス/秒に倒す）。
    def stepInterval(w: World): Float64 =
        1.0 / Float64.max(1.0, w#kind#walk)

    // ── 決定（話す・進める）の規則 ──

    /// 決定 1 回分。表紙では歩き出し［遷移: Title→Play］、クリア画面では表紙へ戻る［遷移: Clear→Title］。
    /// 里では: ふきだしが開いていれば送り（文字送り中なら全文へ・読み終えていれば閉じる）、
    /// 閉じていれば目の前の住人に話しかける（Play のまま）。
    pub def confirm(w: World): World =
        match w#phase {
            case Phase.Title => begin(w)
            case Phase.Clear => { phase = Phase.Title | w }
            case Phase.Play =>
                if (UiDialog.isOpen(w#dialog)) {
                    let dialog = UiDialog.advance(w#dialog);
                    { dialog = dialog,
                      talkingTo = if (UiDialog.isOpen(dialog)) w#talkingTo else None | w }
                } else
                    talk(Grid.neighborOf(w#hero, w#facing), w)
        }

    /// 目の前のマスに住人がいれば話しかける。いなければ何も起きない。
    def talk(cell: Grid.Cell, w: World): World =
        match MapDoc.villagerAt(cell, w#map) {
            case None           => w
            case Some(villager) => speak(villager, w)
        }

    /// 住人の 1 行を選び、ふきだしを開く。約束の相手（door の promise）だけは特別で、
    /// 扉が閉じている間: 薬草が足りなければ頼まれごと（ask）、足りていれば扉が開いて opened。
    /// それ以外（扉が開いた後も）はその住人のいつもの 1 行。
    def speak(villager: MapDoc.Villager, w: World): World =
        let door = w#map#door;
        let isPromise = villager#id == door#promise and not w#doorOpen;
        let fulfilled = isPromise and w#picked >= door#need;
        let line = if (fulfilled) door#opened
                   else if (isPromise) door#ask
                   else villager#line;
        { doorOpen = w#doorOpen or fulfilled,
          dialog = UiDialog.openWith(
              { speaker = villager#id, body = RichText.plain(line) :: Nil } :: Nil),
          talkingTo = Some(villager#cell) | w }

    // ── Doc の差し替え（保存即反映） ──

    /// 間取りの差し替え。歩いている途中なら盤を作り直す（編集がその場で画面に出る。
    /// 拾いかけの薬草は戻る — 盤が変わったら仕切り直すのが一番迷わない）。
    pub def withMap(map: MapDoc.Doc, w: World): World =
        let w1 = { map = map | w };
        match w1#phase {
            case Phase.Play => begin(w1)
            case _          => w1
        }

    pub def withKind(kind: KindDoc.Doc, w: World): World = { kind = kind | w }

    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }

    pub def withSprites(sprites: PxSpriteDoc.Doc, w: World): World = { sprites = sprites | w }

    pub def withTerrain(terrain: TerrainDoc.Doc, w: World): World = { terrain = terrain | w }

    /// イベントシーンの束の差し替え(保存即反映)。演じている最中のシーンは打ち切る —
    /// 古い脚本の続きを演じても、保存した人が見たいのは新しい脚本だから。
    pub def withScenes(scenes: List[CutsceneDoc.Doc], w: World): World =
        { scenes = scenes | restStage(w) }
}
