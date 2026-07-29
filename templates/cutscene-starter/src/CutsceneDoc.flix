// CutsceneDoc — イベントシーン 1 本（*.cutscene.json）の宣言ドキュメント層。
// **1 ファイル = 1 シーン**。始まりの立ち位置と、カット（何がどの順で起きるか）の列を持つ。
// カットは分岐も変数も書けない逐次の表 —「表であってスクリプトではない」。
// 歩きの経路・言葉の間・幕の滑りはコード（Cutscene / SceneSeq / Steering）側の仕事。
// 行き先は目的のマスで書く（歩数の写経をしない）— 間取りを編集しても脚本は書き直さない。
// この Doc は **bake と実機の両方が同じ脚本として演じる** — bake は make cutscene
// （保存 → 焼き直し → GIF 目視）で、実機は World の scenes に載って Director が
// 合図（cue）を拾って演じる（保存即反映は watchFile。Main の reloads を参照）。
// fail-open — 読めない・壊れているときは defaults() へ倒し、読めないカットは
// Broken の印になって番号つきで報される（無音では飛ばない）。
mod CutsceneDoc {
    use Util.Json.Json

    /// カット 1 つ。上から順に 1 つずつ演じられ、終わったら次へ進む。
    pub enum Cut {
        /// その場で待つ（秒）。霧の流れも灯りも生きたまま時間だけが流れる。
        case Wait(Float64)
        /// 主人公が目的のマスまで移る（経路はコード側が間取りから導く。中身は Stride）。
        case WalkTo(Stride)
        /// 主人公が向きだけ変える（足は出さない）。
        case Face(Dir4.Dir4)
        /// 主人公のひとりごと（ふきだしが主人公の頭の上に出る。1 要素 = 1 回の送り）。
        case Say(List[String])
        /// その向きの相手に話しかける（住人の 1 行・約束の頼まれごと・扉が開く —
        /// どの言葉が出るかは World の既存の規則がそのまま決める）。
        case Talk(Dir4.Dir4)
        /// 火の玉が目的のマスまで詰める（居なければ飛ぶ。主人公は捕まえない）。
        /// waits = false（JSON の noWait）なら指図だけ出して次のカットへ —
        /// 以後のカット（歩き・言葉）と同時に詰めてくる。
        case WispTo({ cell = Grid.Cell, waits = Bool })
        /// そのマスに火の玉がふっと現れる。
        case WispAppear(Grid.Cell)
        /// 火の玉がふっと消える（居なければ何も起きない）。
        case WispVanish
        /// 画面が白く瞬く（雷・衝撃の印。かける秒だけ書けば減衰はコード側）。
        case Flash(Float64)
        /// 画面が揺れる（かける秒。揺れ幅は演出の形なのでコード側）。
        case Shake(Float64)
        /// 画面を暗転させる／明ける（dark = true で黒へ、false で黒から。secs = かける秒）。
        case Fade({ dark = Bool, secs = Float64 })
        /// 読めなかったカット（知らない鍵・形違い）。**列から抜かずにここへ倒す** —
        /// 抜くとカットの通し番号が JSON とずれ、報せの「カット3」が別の行を指してしまう。
        case Broken
    }

    /// 移り方 1 つぶん。cell = 目的のマス、dash = 走る（歩く速さを倍に。JSON の鍵は
    /// "run" — run は Flix の予約語なのでコード側では dash と呼ぶ）、
    /// back = 後ずさり（向きを変えずに下がる — 怖いものから目を離さない）、
    /// waits = 着くまで待つか（JSON の noWait で false — 命じて待たず、
    /// 以後のカットと同時に歩く）。
    pub type alias Stride = { cell = Grid.Cell, dash = Bool, back = Bool, waits = Bool }

    /// 守衛つきのカット 1 行。only = この事実が成り立つ時だけ効く、
    /// unless = 成り立つ時は黙る（どちらも空なら誰でも）。
    /// **分岐ではなく条件行** — 効かない行はただ黙って飛ぶ。事実の名前が何を指すかは
    /// World.holdsFact（この里では "door" = 木戸が開いた / "herb" = 薬草を持っている）。
    pub type alias Guarded = { only = String, unless = String, cut = Cut }

    /// イベントシーン 1 本。id = 焼いた GIF の名前になる、name = 人が読む呼び名、
    /// start = 始まりの立ちマス、facing = 始まりの向き、cuts = 演じる順のカットの列。
    pub type alias Doc = {
        version = Int32,
        id = String,
        name = String,
        start = Grid.Cell,
        facing = Dir4.Dir4,
        cuts = List[Guarded]
    }

    /// 読むシーンのファイル一覧（シーンを足したらここに 1 行足す）。
    pub def paths(): List[String] =
        "assets/opening.cutscene.json"
            :: "assets/intro.cutscene.json"
            :: "assets/chase.cutscene.json"
            :: "assets/kiri-no-yoru.cutscene.json"
            :: Nil

    /// コード側の既定値。カットの無い空のシーン（読めなくても bake は止まらない）。
    pub def defaults(): Doc =
        { version = 1,
          id = "cutscene",
          name = "イベントシーン",
          start = { x = 2, y = 2 },
          facing = Dir4.Down,
          cuts = Nil }

    /// カットの種類の名前（JSON の鍵と同じ綴り）。Cut はマスを抱くので Eq を導出できない —
    /// テストとログが「どの種類がどの順で並んだか」を見る唯一の入口。
    pub def kindOf(cut: Cut): String =
        match cut {
            case Cut.Wait(_)       => "wait"
            case Cut.WalkTo(walk)  => if (walk#back) "backTo" else "walkTo"
            case Cut.Face(_)       => "face"
            case Cut.Say(_)        => "say"
            case Cut.Talk(_)       => "talk"
            case Cut.WispTo(_)     => "wispTo"
            case Cut.WispAppear(_) => "wispAppear"
            case Cut.WispVanish    => "wispVanish"
            case Cut.Flash(_)      => "flash"
            case Cut.Shake(_)      => "shake"
            case Cut.Fade(_)       => "fade"
            case Cut.Broken        => "broken"
        }

    // ── JSON からの読み込み ──

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          id = JsonCodec.stringOr("id", d#id, root),
          name = JsonCodec.stringOr("name", d#name, root),
          start = { x = JsonCodec.intOr("startX", d#start#x, root),
                    y = JsonCodec.intOr("startY", d#start#y, root) },
          facing = dirOr("facing", d#facing, root),
          cuts = Map.get("cuts", root)
              |> Option.flatMap(JsonCodec.decodeList(guardedFromJson))
              |> Option.getWithDefault(d#cuts) }

    /// 守衛（only / unless）を添えてカットを読む。守衛はどのカットにも書ける添え鍵。
    def guardedFromJson(json: Json): Option[Guarded] =
        let guard = JsonCodec.expectObject(json) |> Option.getWithDefault(Map.empty());
        cutFromJson(json) |> Option.map(cut ->
            { only = JsonCodec.stringOr("only", "", guard),
              unless = JsonCodec.stringOr("unless", "", guard),
              cut = cut })

    /// カット 1 つの読み取り。JSON は Map になった時点で書き順が失われるので、
    /// **固定の優先順**（wait → walkTo → backTo → face → say → talk → wispTo →
    /// wispAppear → wispVanish → flash → shake → fade）で最初に見つかった鍵の種類になる。
    /// only / unless / noWait / run / secs は種類を決めない添え鍵。
    /// 常に Some を返し、読めないカットは Some(Broken) — decodeList は 1 要素の失敗で
    /// 列ごと倒れるので、**壊れた 1 カットは印に変えて残りは演じる**ためにこの形にする。
    def cutFromJson(json: Json): Option[Cut] =
        Some(JsonCodec.expectObject(json) |> Option.flatMap(obj ->
            if (Map.memberOf("wait", obj))
                Some(Cut.Wait(JsonCodec.floatOr("wait", 0.0, obj)))
            else if (Map.memberOf("walkTo", obj))
                cellIn("walkTo", obj) |> Option.map(cell -> Cut.WalkTo(
                    { cell = cell, dash = JsonCodec.boolOr("run", false, obj), back = false,
                      waits = not JsonCodec.boolOr("noWait", false, obj) }))
            else if (Map.memberOf("backTo", obj))
                cellIn("backTo", obj) |> Option.map(cell -> Cut.WalkTo(
                    { cell = cell, dash = false, back = true,
                      waits = not JsonCodec.boolOr("noWait", false, obj) }))
            else if (Map.memberOf("face", obj))
                Some(Cut.Face(dirOr("face", Dir4.Down, obj)))
            else if (Map.memberOf("say", obj))
                Some(Cut.Say(linesIn("say", obj)))
            else if (Map.memberOf("talk", obj))
                Some(Cut.Talk(dirOr("talk", Dir4.Up, obj)))
            else if (Map.memberOf("wispTo", obj))
                cellIn("wispTo", obj) |> Option.map(cell -> Cut.WispTo(
                    { cell = cell, waits = not JsonCodec.boolOr("noWait", false, obj) }))
            else if (Map.memberOf("wispAppear", obj))
                cellIn("wispAppear", obj) |> Option.map(Cut.WispAppear)
            else if (Map.memberOf("wispVanish", obj))
                Some(Cut.WispVanish)
            else if (Map.memberOf("flash", obj))
                Some(Cut.Flash(JsonCodec.floatOr("flash", 0.2, obj)))
            else if (Map.memberOf("shake", obj))
                Some(Cut.Shake(JsonCodec.floatOr("shake", 0.5, obj)))
            else if (Map.memberOf("fade", obj))
                Some(Cut.Fade({ dark = JsonCodec.stringOr("fade", "out", obj) != "in",
                                secs = JsonCodec.floatOr("secs", 0.8, obj) }))
            else
                None)
            |> Option.getWithDefault(Cut.Broken))

    /// 鍵の中のマス（{"x": .., "y": ..}）。形が違えば None（そのカットは Broken へ —
    /// 座標の無い行き先を 0,0 に倒すと、意図しない場所へ歩き出して脚本の誤りが隠れる）。
    def cellIn(key: String, obj: Map[String, Json]): Option[Grid.Cell] =
        Map.get(key, obj)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(cell -> { x = JsonCodec.intOr("x", 0, cell),
                                    y = JsonCodec.intOr("y", 0, cell) })

    /// 鍵の中の言葉の列。形が違えば空（言葉の無い Say は演じる側が即座に済ませる）。
    def linesIn(key: String, obj: Map[String, Json]): List[String] =
        Map.get(key, obj)
            |> Option.flatMap(JsonCodec.decodeList(JsonCodec.expectString))
            |> Option.getWithDefault(Nil)

    /// 向きの読み取り。知らない綴りは既定へ倒す（打ち間違えても遊びは止まらない）。
    def dirOr(key: String, fallback: Dir4.Dir4, obj: Map[String, Json]): Dir4.Dir4 =
        match JsonCodec.stringOr(key, "", obj) {
            case "up"    => Dir4.Up
            case "down"  => Dir4.Down
            case "left"  => Dir4.Left
            case "right" => Dir4.Right
            case _       => fallback
        }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
