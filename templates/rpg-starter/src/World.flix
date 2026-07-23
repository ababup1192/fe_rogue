// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 見下ろしの里を 1 マスずつ歩き、住人に話しかけ、薬草を拾う。
// 扉の鍵は物ではなく約束 — 頼まれた数の薬草を持って約束の相手と話すと扉が開く。
// 盤面のデータ（rows・配置・文言）は MapDoc、手触りは KindDoc — 実行中の状態はこの World だけが持つ。
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
        sprites = PxSpriteDoc.Doc
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
        activeDocsWritten = String
    }

    // ── 盤の寸法（design 480×300 の中の定数。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 300.0

    /// タイルの 1 辺（px）。24×15 マスで画面がちょうど埋まる。
    pub def tileSize(): Float64 = 20.0

    pub def spritePath(): String = "assets/rpg.sprite.json"

    /// ゲーム開始時の状態。表紙から始まる。
    pub def initial(docs: Docs): World =
        { map = docs#map, kind = docs#kind, theme = docs#theme, sprites = docs#sprites,
          phase = Phase.Title,
          hero = docs#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = docs#map#herbs, picked = 0, doorOpen = false,
          dialog = UiDialog.closed(), talkingTo = None, activeDocsWritten = "" }

    /// 里を歩ける状態に置き直す（表紙から始めるとき・間取りの Doc を差し替えたとき）。
    /// 薬草は全部戻り、扉は閉じ、主人公は start のマスに立つ。
    def begin(w: World): World =
        { phase = Phase.Play,
          hero = w#map#start, facing = Dir4.Down, stepGauge = 0.0, steps = 0,
          herbs = w#map#herbs, picked = 0, doorOpen = false,
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

    /// いま立っているマスの薬草を拾う。goal に届いたらクリア（Phase.Clear）。
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
    pub def step(direction: Option[Dir4.Dir4], dt: Float64, w: World): World =
        match w#phase {
            case Phase.Play => {
                let talked = { dialog = UiDialog.step(cps = w#kind#cps, dt, w#dialog) | w };
                if (UiDialog.isOpen(talked#dialog))
                    talked
                else
                    walk(direction, Clock.countdown(talked#stepGauge, dt), talked)
            }
            case _ => w
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

    // ── 決定（話す・進める）の規則 ──

    /// 決定 1 回分。表紙では歩き出し、クリア画面では表紙へ戻る。
    /// 里では: ふきだしが開いていれば送り（文字送り中なら全文へ・読み終えていれば閉じる）、
    /// 閉じていれば目の前の住人に話しかける。
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
}
