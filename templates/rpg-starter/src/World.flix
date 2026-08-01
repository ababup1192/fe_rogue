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
    /// Battle = 魔物と向き合っている、Clear = 薬草がそろった（決定で表紙へ戻る）。
    pub enum Phase with Eq, ToString {
        case Title
        case Play
        case Battle
        case Clear
    }

    /// 戦いのどの段か。Choosing = コマンドを選んでいる、Report = 打ち合いの結果を読んでいる
    /// （決定でつぎの番へ）、Done = 決着（決定で里へ戻る）。
    pub enum BattleStep with Eq, ToString {
        case Choosing
        case Report
        case Done
    }

    /// 戦いの終わり方。
    pub enum Outcome with Eq, ToString {
        case Win
        case Lose
        case Flee
    }

    /// いま戦っている 1 回ぶん。主人公の体力は戦いをまたいで残るので World 側が持ち、
    /// ここには「この戦いの中だけの物」を置く。
    ///   step … いまどの段か。cursor … 選んでいるコマンド（0 = たたかう / 1 = にげる）。
    ///   foeHp … 魔物の残り体力。lines … 下の窓に出す文（上から順）。
    ///   foeHurt … 魔物が殴られたコマを出すか。outcome … 決着（まだなら None）。
    pub type alias Battle = {
        step = BattleStep,
        cursor = Int32,
        foeHp = Int32,
        lines = List[String],
        foeHurt = Bool,
        outcome = Option[Outcome]
    }

    /// 起動時に読む Doc の束（Main と Bake が同じ形で組む）。
    pub type alias Docs = {
        map = MapDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        battle = BattleDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        terrain = TerrainDoc.Doc
    }

    /// ゲームの状態。hero / facing = 主人公のマスと向き、stepGauge = 次の一歩までの残り秒、
    /// steps = 歩いた歩数（歩きのコマ送りに使う）、herbs = まだ拾っていない薬草のマス、
    /// picked = 拾った薬草の数、doorOpen = 扉が開いたか、
    /// dialog = ふきだし（開いている間は歩けない）、talkingTo = 話し相手のマス（ふきだしの位置）。
    /// t = 起動からの積み上げ秒（場面に関係なく進む — 待っている画面でも絵を止めないため）。
    /// heroHp = 主人公の残り体力（戦いをまたいで残る）。battle = いま戦っている 1 回ぶん。
    pub type alias World = {
        map = MapDoc.Doc,
        kind = KindDoc.Doc,
        theme = ThemeDoc.Doc,
        battleDoc = BattleDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        terrain = TerrainDoc.Doc,
        phase = Phase,
        t = Float64,
        hero = Grid.Cell,
        facing = Dir4.Dir4,
        stepGauge = Float64,
        steps = Int32,
        herbs = List[Grid.Cell],
        picked = Int32,
        doorOpen = Bool,
        heroHp = Int32,
        battle = Battle,
        dialog = UiDialog.Dialog,
        talkingTo = Option[Grid.Cell],
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
        { map = docs#map, kind = docs#kind, theme = docs#theme, battleDoc = docs#battle,
          sprites = docs#sprites, terrain = docs#terrain,
          phase = Phase.Title, t = 0.0,
          hero = docs#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = docs#map#herbs, picked = 0, doorOpen = false,
          heroHp = docs#battle#heroMaxHp, battle = noBattle(),
          dialog = UiDialog.closed(), talkingTo = None, activeDocsWritten = "" }

    /// 戦っていないときの空の戦い（場が無い間の置き物）。
    def noBattle(): Battle =
        { step = BattleStep.Choosing, cursor = 0, foeHp = 0,
          lines = Nil, foeHurt = false, outcome = None }

    /// 里を歩ける状態に置き直す（表紙から始めるとき・間取りの Doc を差し替えたとき）。
    /// 薬草は全部戻り、扉は閉じ、体力は満タン、主人公は start のマスに立つ。[遷移: Title→Play]
    def begin(w: World): World =
        { phase = Phase.Play,
          hero = w#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = w#map#herbs, picked = 0, doorOpen = false,
          heroHp = w#battleDoc#heroMaxHp, battle = noBattle(),
          dialog = UiDialog.closed(), talkingTo = None | w }

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
            case Phase.Play   => List.append(base, ("kind", KindDoc.path() :: Nil) :: Nil)
            // 戦いの最中は盤が隠れる。出ているのは魔物の絵と戦いの数・文言だけ。
            case Phase.Battle => ("sprite", spritePath() :: Nil)
                                     :: ("theme", ThemeDoc.path() :: Nil)
                                     :: ("battle", BattleDoc.path() :: Nil) :: Nil
            case _            => base
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
            pickUp({ hero = target, steps = w#steps + 1 | faced }) |> meetFoe
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
    /// 時計（t）だけは場面を問わず進める — 表紙でも戦いの最中でも霧が流れ、魔物が息をする。
    pub def step(direction: Option[Dir4.Dir4], dt: Float64, w: World): World =
        let ticked = { t = w#t + dt | w };
        match ticked#phase {
            case Phase.Play => {
                let talked = { dialog = UiDialog.step(cps = w#kind#cps, dt, ticked#dialog) | ticked };
                if (UiDialog.isOpen(talked#dialog))
                    talked
                else
                    walk(direction, Clock.countdown(talked#stepGauge, dt), talked)
            }
            case _ => ticked
        }

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

    // ══════════════════════════════════════════════════════
    // 戦い（歩数で出会い、殴り合い、勝つか負けるか逃げる）
    // ══════════════════════════════════════════════════════
    //
    //   Play ──encounterSteps 歩ごと(meetFoe)──▶ Battle
    //     ▲                                        │
    //     └────勝ち / 逃げ / 負け(leaveBattle)──────┘
    //
    // 乱数は持ち込まない: 何歩めで出会うかも、一撃の重さも Doc の数から決まる。
    // 決定的なので bake の絵もテストの期待値も揺れない（強さの調整は Doc 側で足りる）。

    /// この歩数で魔物と出会うか。encounterSteps 歩ごとに 1 回。0 以下なら出会わない。
    pub def meetsFoeAt(steps: Int32, doc: BattleDoc.Doc): Bool =
        doc#encounterSteps > 0 and steps > 0 and Int32.modulo(steps, doc#encounterSteps) == 0

    /// 1 歩ぶん進んだあとの出会い判定。里を歩いている間だけ。[遷移: Play→Battle]
    def meetFoe(w: World): World =
        if (w#phase == Phase.Play and meetsFoeAt(w#steps, w#battleDoc))
            { phase = Phase.Battle,
              battle = { step = BattleStep.Report, cursor = 0, foeHp = w#battleDoc#foeMaxHp,
                         lines = "${w#battleDoc#foeName} ${w#battleDoc#foeAppears}" :: Nil,
                         foeHurt = false, outcome = None } | w }
        else w

    /// 戦いのコマンドの並び（見出しは UI の構造なので固定でよい）。
    pub def battleCommands(): List[String] = "たたかう" :: "にげる" :: Nil

    /// 選ぶカーソルを 1 つ動かす（上下。端で止まる）。Choosing の間だけ効く。
    pub def moveCursor(delta: Int32, w: World): World =
        if (w#phase != Phase.Battle or w#battle#step != BattleStep.Choosing) w
        else {
            let last = List.length(battleCommands()) - 1;
            let cursor = Int32.max(0, Int32.min(last, w#battle#cursor + delta));
            { battle = { cursor = cursor | w#battle } | w }
        }

    /// 戦いの決定 1 回分。段によって意味が変わる:
    ///   Report   … 読み終えた → つぎのコマンド選びへ。
    ///   Choosing … 選んだコマンドを実行する（たたかう / にげる）。
    ///   Done     … 決着を読み終えた → 里へ戻る。
    def battleConfirm(w: World): World =
        match w#battle#step {
            case BattleStep.Report =>
                { battle = { step = BattleStep.Choosing, lines = Nil, foeHurt = false | w#battle } | w }
            case BattleStep.Done   => leaveBattle(w)
            case BattleStep.Choosing =>
                if (w#battle#cursor == 1) flee(w) else strike(w)
        }

    /// 「たたかう」1 回分。こちらが殴り、倒せなければ相手が殴り返す。
    def strike(w: World): World =
        let doc = w#battleDoc;
        let foeHp = Int32.max(0, w#battle#foeHp - doc#heroAttack);
        let hitLine = "${doc#foeName} に ${Int32.toString(doc#heroAttack)} ${doc#damageSuffix}";
        if (foeHp <= 0)
            { battle = { step = BattleStep.Done, foeHp = 0, foeHurt = true,
                         lines = hitLine :: doc#heroWins :: Nil,
                         outcome = Some(Outcome.Win) | w#battle } | w }
        else {
            let heroHp = Int32.max(0, w#heroHp - doc#foeAttack);
            let backLine = "こちらに ${Int32.toString(doc#foeAttack)} ${doc#damageSuffix}";
            if (heroHp <= 0)
                { heroHp = 0,
                  battle = { step = BattleStep.Done, foeHp = foeHp, foeHurt = true,
                             lines = hitLine :: backLine :: doc#heroLoses :: Nil,
                             outcome = Some(Outcome.Lose) | w#battle } | w }
            else
                { heroHp = heroHp,
                  battle = { step = BattleStep.Report, foeHp = foeHp, foeHurt = true,
                             lines = hitLine :: backLine :: Nil, outcome = None | w#battle } | w }
        }

    /// 「にげる」1 回分。必ず逃げられる（starter は詰ませない — 難しさは Doc の数で足す）。
    def flee(w: World): World =
        { battle = { step = BattleStep.Done, lines = w#battleDoc#heroFlees :: Nil,
                     foeHurt = false, outcome = Some(Outcome.Flee) | w#battle } | w }

    /// 決着して里へ戻る。倒れていたら入口へ戻って体力が満ちる（詰まない）。
    /// [遷移: Battle→Play]
    def leaveBattle(w: World): World =
        let back = { phase = Phase.Play, battle = noBattle() | w };
        match w#battle#outcome {
            case Some(Outcome.Lose) =>
                { hero = w#map#start, facing = Dir4.Down, heroHp = w#battleDoc#heroMaxHp | back }
            case _ => back
        }

    // ── 決定（話す・進める）の規則 ──

    /// 決定 1 回分。表紙では歩き出し［遷移: Title→Play］、クリア画面では表紙へ戻る［遷移: Clear→Title］。
    /// 里では: ふきだしが開いていれば送り（文字送り中なら全文へ・読み終えていれば閉じる）、
    /// 閉じていれば目の前の住人に話しかける（Play のまま）。
    /// 戦いの最中は battleConfirm へ渡す。
    pub def confirm(w: World): World =
        match w#phase {
            case Phase.Title  => begin(w)
            case Phase.Clear  => { phase = Phase.Title | w }
            case Phase.Battle => battleConfirm(w)
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

    /// 戦いの数値・文言の差し替え。体力の上限が動くので、いまの体力もそこへ収める。
    pub def withBattleDoc(doc: BattleDoc.Doc, w: World): World =
        { battleDoc = doc, heroHp = Int32.min(w#heroHp, doc#heroMaxHp) | w }

    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }

    pub def withSprites(sprites: PxSpriteDoc.Doc, w: World): World = { sprites = sprites | w }

    pub def withTerrain(terrain: TerrainDoc.Doc, w: World): World = { terrain = terrain | w }
}
