/// LDTK プロジェクトファイル（.ldtk）から auto-rule 定義を読み込み、
/// マージ後の merged intGrid に対して runtime で再適用するモジュール。
///
/// 役割:
///   - `defs.layers[].autoRuleGroups[].rules[]` をパースして AutoRuleSet を返す
///   - 与えられた intGrid に対し、ルールを順に評価して TileData リストを生成する
///
/// LDTK auto-rule のパターン値（pattern[i] ∈ {0, 1, -1}）:
///   - 0  : 何でも OK
///   - 1  : intGrid 値が 1 (= wall) でなければならない
///   - -1 : intGrid 値が 1 (= wall) では ない（= 床 or out-of-bounds-as-not-1）
///
/// flipX / flipY が true のルールは、パターンを左右 / 上下反転したミラー版でも
/// 試行し、マッチしたタイルに flip フラグを付けて生成する。
mod LDTKRules {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber, JsonString, JsonBool}

    /// 1 個の auto-rule。LDTK の rule をフラット化したもの。
    pub type alias AutoRule = {
        size           = Int32,            // 3 or 1
        pattern        = Vector[Int32],    // 長さ size*size、0/1/-1
        tileId         = Int32,            // tileRectsIds[0][0]
        flipX          = Bool,
        flipY          = Bool,
        outOfBoundsVal = Int32,
        breakOnMatch   = Bool
    }

    /// auto-rule のセット（1 layer 分）。
    pub type alias AutoRuleSet = {
        rules    = List[AutoRule],
        tileSize = Int32
    }

    // ════════════════════════════════════════════════════════
    // 公開 API
    // ════════════════════════════════════════════════════════

    /// `.ldtk` プロジェクトファイルから "Walls" intGrid layer の auto-rule をロードする。
    /// `autoRuleGroups[0].rules` を採用する（プロジェクトに 1 group 前提）。
    pub def loadRules(path: String): AutoRuleSet \ Fs.FileRead =
        let text = match run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead {
            case Ok(t)  => t
            case Err(e) => bug!("LDTKRules: failed to read ${path}: ${e}")
        };
        let json = match Json.Parse.parse(String.trim(text)) {
            case Some(j) => j
            case None    => bug!("LDTKRules: failed to parse JSON: ${path}")
        };
        let root = getObj(json);
        let defs = getObj(getField("defs", root));
        let layers = getArr(getField("layers", defs));
        // autoRuleGroups が空でない layer を採用
        let layer = match List.find(l -> {
            let layerObj = getObj(l);
            match Map.get("autoRuleGroups", layerObj) {
                case Some(JsonArray(arr)) => Vector.length(arr) > 0
                case _                    => false
            }
        }, layers) {
            case Some(l) => getObj(l)
            case None    => bug!("LDTKRules: no layer with autoRuleGroups in ${path}")
        };
        let tileSize = getInt(getField("gridSize", layer));
        let groups = getArr(getField("autoRuleGroups", layer));
        let firstGroup = match List.head(groups) {
            case Some(g) => getObj(g)
            case None    => bug!("LDTKRules: autoRuleGroups is empty")
        };
        let rulesArr = getArr(getField("rules", firstGroup));
        let rules = List.map(parseRule, rulesArr);
        { rules = rules, tileSize = tileSize }

    /// merged intGrid に対して全ルールを適用してタイルリストを生成する。
    /// `intGrid(x, y)` は `(x, y)` cell の値を返す（壁=1、床=0）。
    /// out-of-bounds は内部で rule#outOfBoundsVal を返す。
    ///
    /// LDTK の `breakOnMatch=false` セマンティクス: 各 cell について全ルール
    /// （flipX/flipY 含むバリアント）を試し、マッチした全タイルを stack する。
    /// 結果として「size=1 の wall fill ルール (tile 31) が壁の下地として常時敷かれ、
    /// 上に specific な装飾タイルが重ね描きされる」LDTK 編集時と同じ挙動になる。
    pub def applyRules(ruleSet: AutoRuleSet,
                        intGrid: (Int32, Int32) -> Int32,
                        gridSize: Vec2.Vec2i,
                        texSize: { width = Float64, height = Float64 }): List[TileData] =
        let tileSize = ruleSet#tileSize;
        let cells: List[(Int32, Int32)] =
            List.range(0, gridSize#y) |> List.flatMap(y ->
                List.range(0, gridSize#x) |> List.map(x -> (x, y)));
        List.flatMap(c -> {
            let (cx, cy) = c;
            let matches = applyRulesToCell(ruleSet#rules, intGrid, gridSize, cx, cy);
            List.map(m -> {
                let (rule, flipH, flipV) = m;
                makeTileData(rule#tileId, cx, cy, tileSize, flipH, flipV, texSize)
            }, matches)
        }, cells)

    // ════════════════════════════════════════════════════════
    // 内部: ルール適用ロジック
    // ════════════════════════════════════════════════════════

    /// 1 cell に対し全ルールを試し、マッチした (rule, flipH, flipV) を全て返す。
    /// flipX / flipY が true のルールはバリアントも試行し、両方マッチすれば両方 stack。
    /// **重要**: ルールを **逆順** で処理する。LDTK は配列の先頭が最高優先度で、
    /// 出力 autoLayerTiles では「低優先度が先（下地）→ 高優先度が後（上に重ね描き）」
    /// になっている。リストの先頭タイルが先に描画される（＝下地）ので、
    /// 配列を逆順で flatMap すると低優先度（末尾の fallback rule 651）が先に
    /// 出力に入って下地となり、specific な edge / shadow タイルが上から被さる。
    def applyRulesToCell(rules: List[AutoRule],
                          intGrid: (Int32, Int32) -> Int32,
                          gridSize: Vec2.Vec2i,
                          cx: Int32, cy: Int32): List[(AutoRule, Bool, Bool)] =
        List.reverse(rules)
            |> List.flatMap(rule -> tryAllVariants(rule, intGrid, gridSize, cx, cy))

    /// 1 ルールについて、元パターン + flipX / flipY / 両方反転 のバリアントを
    /// それぞれ試行し、マッチしたものを全て返す。
    def tryAllVariants(rule: AutoRule,
                        intGrid: (Int32, Int32) -> Int32,
                        gridSize: Vec2.Vec2i,
                        cx: Int32, cy: Int32): List[(AutoRule, Bool, Bool)] =
        let acc1 = if (matchPattern(rule, rule#pattern, intGrid, gridSize, cx, cy))
                       (rule, false, false) :: Nil
                   else Nil;
        let acc2 = if (rule#flipX and
                       matchPattern(rule, flipPatternX(rule#pattern, rule#size), intGrid, gridSize, cx, cy))
                       (rule, true, false) :: acc1
                   else acc1;
        let acc3 = if (rule#flipY and
                       matchPattern(rule, flipPatternY(rule#pattern, rule#size), intGrid, gridSize, cx, cy))
                       (rule, false, true) :: acc2
                   else acc2;
        let acc4 = if (rule#flipX and rule#flipY and
                       matchPattern(rule, flipPatternXY(rule#pattern, rule#size), intGrid, gridSize, cx, cy))
                       (rule, true, true) :: acc3
                   else acc3;
        acc4

    /// パターンと cell の neighborhood を照合する。
    /// 中心セル `(cx, cy)` を起点に、`size × size` の範囲を読み取り
    /// パターン値と比較する。範囲外は rule#outOfBoundsVal を採用する。
    def matchPattern(rule: AutoRule,
                      pattern: Vector[Int32],
                      intGrid: (Int32, Int32) -> Int32,
                      gridSize: Vec2.Vec2i,
                      cx: Int32, cy: Int32): Bool =
        let size = rule#size;
        let half = size / 2;
        let oob = rule#outOfBoundsVal;
        let indices = List.range(0, size * size);
        List.forAll(i -> {
            let py = i / size;
            let px = i - py * size;
            let p = match Vector.nth(i, pattern) {
                case Some(v) => v
                case None    => 0i32
            };
            let wx = cx - half + px;
            let wy = cy - half + py;
            let v = intGridAt(intGrid, gridSize, wx, wy, oob);
            patternMatchOne(p, v)
        }, indices)

    /// cell value を読む。範囲外なら oob を返す。
    def intGridAt(intGrid: (Int32, Int32) -> Int32,
                   gridSize: Vec2.Vec2i,
                   x: Int32, y: Int32,
                   oob: Int32): Int32 =
        if (x < 0i32 or x >= gridSize#x or y < 0i32 or y >= gridSize#y) oob
        else intGrid(x, y)

    /// 1 セルのパターン値と実際値を比較する。
    /// 0=any, 1=must wall, -1=must not wall。
    def patternMatchOne(p: Int32, v: Int32): Bool =
        if (p == 0i32)       true
        else if (p == 1i32)  v == 1i32
        else if (p == -1i32) v != 1i32
        else                 false   // 想定外（2 以上の intGrid 値はここでは扱わない）

    /// パターンを X 軸で反転する（同じ row 内で左右ミラー）。
    def flipPatternX(pattern: Vector[Int32], size: Int32): Vector[Int32] =
        Vector.range(0, size * size)
            |> Vector.map(i -> {
                let py = i / size;
                let px = i - py * size;
                let mirroredPx = size - 1 - px;
                let mirroredIdx = py * size + mirroredPx;
                match Vector.nth(mirroredIdx, pattern) {
                    case Some(v) => v
                    case None    => 0i32
                }
            })

    /// パターンを Y 軸で反転する（同じ col 内で上下ミラー）。
    def flipPatternY(pattern: Vector[Int32], size: Int32): Vector[Int32] =
        Vector.range(0, size * size)
            |> Vector.map(i -> {
                let py = i / size;
                let px = i - py * size;
                let mirroredPy = size - 1 - py;
                let mirroredIdx = mirroredPy * size + px;
                match Vector.nth(mirroredIdx, pattern) {
                    case Some(v) => v
                    case None    => 0i32
                }
            })

    def flipPatternXY(pattern: Vector[Int32], size: Int32): Vector[Int32] =
        flipPatternX(flipPatternY(pattern, size), size)

    /// LDTK tileId から atlas 上の (srcX, srcY) を計算し、TileData を構築する。
    /// atlas の幅から 1 行のタイル数を決定する。
    def makeTileData(tileId: Int32, cx: Int32, cy: Int32, tileSize: Int32,
                      flipH: Bool, flipV: Bool,
                      texSize: { width = Float64, height = Float64 }): TileData =
        let cols = Float64.tryToInt32(Float64.floor(texSize#width / Int32.toFloat64(tileSize)))
                   |> Option.getWithDefault(20i32);
        let srcCol = Int32.remainder(tileId, cols);
        let srcRow = tileId / cols;
        {
            px    = ({x = Int32.toFloat64(cx * tileSize),
                       y = Int32.toFloat64(cy * tileSize)}: Vec2.Vec2),
            srcX  = Int32.toFloat64(srcCol * tileSize),
            srcY  = Int32.toFloat64(srcRow * tileSize),
            flipH = flipH,
            flipV = flipV,
            alpha = 1.0f32
        }

    // ════════════════════════════════════════════════════════
    // 内部: JSON パースヘルパー
    // ════════════════════════════════════════════════════════

    def parseRule(el: Json.JsonElement): AutoRule =
        let obj = getObj(el);
        let size = getInt(getField("size", obj));
        let patternList = getArr(getField("pattern", obj))
            |> List.map(getInt);
        let pattern = List.toVector(patternList);
        let tileRectsIds = getArr(getField("tileRectsIds", obj));
        let firstRow = match List.head(tileRectsIds) {
            case Some(r) => getArr(r)
            case None    => bug!("LDTKRules: empty tileRectsIds")
        };
        let tileId = match List.head(firstRow) {
            case Some(t) => getInt(t)
            case None    => bug!("LDTKRules: empty tileRectsIds[0]")
        };
        let flipX = getBool(getField("flipX", obj));
        let flipY = getBool(getField("flipY", obj));
        let oob = getInt(getField("outOfBoundsValue", obj));
        let breakOnMatch = getBool(getField("breakOnMatch", obj));
        {
            size           = size,
            pattern        = pattern,
            tileId         = tileId,
            flipX          = flipX,
            flipY          = flipY,
            outOfBoundsVal = oob,
            breakOnMatch   = breakOnMatch
        }

    def getFloat(el: Json.JsonElement): Float64 = match el {
        case JsonNumber(bd) => bd.doubleValue()
        case _              => bug!("LDTKRules: expected JSON number")
    }

    def getInt(el: Json.JsonElement): Int32 =
        Float64.truncateToInt32(getFloat(el))

    def getBool(el: Json.JsonElement): Bool = match el {
        case JsonBool(b) => b
        case _           => bug!("LDTKRules: expected JSON bool")
    }

    def getObj(el: Json.JsonElement): Map[String, Json.JsonElement] = match el {
        case JsonObject(m) => m
        case _             => bug!("LDTKRules: expected JSON object")
    }

    def getArr(el: Json.JsonElement): List[Json.JsonElement] = match el {
        case JsonArray(v) => Vector.toList(v)
        case _            => bug!("LDTKRules: expected JSON array")
    }

    def getField(key: String, obj: Map[String, Json.JsonElement]): Json.JsonElement =
        match Map.get(key, obj) {
            case Some(v) => v
            case None    => bug!("LDTKRules: missing field '${key}'")
        }
}
