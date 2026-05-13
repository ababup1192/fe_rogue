// JsonOrdered — JSON のキー出現順と配列スタイル (inline / block) を保持したまま
// パース・再シリアライズする軽量モジュール
//
// なぜ自前で実装するか:
//   Flix 標準ライブラリの Json.Parse は Map ベースで返すためキー順が失われる。
//   Json.Write.toPrettyString はアルファベット順に並べ替えて出力する。
//   この組み合わせで SceneSerializer の書き戻し diff が「全行変更」扱いとなり
//   レビューが地獄になる。元 JSON のキー順を維持できれば diff は実質変更行のみになる。
//
// 仕様:
//   - object: List[(String, OrderedJson)] でキー順を保持
//   - array: 「inline ([0, 0])」か「block (改行展開)」を ArrayStyle で記録
//   - number: BigDecimal ではなく **String そのもの** を保持（"0" → "0.0" にならないように）
//   - string: 元のエスケープ表現は復元しないので、書き戻し時に再エスケープ
//   - 末尾改行を必ず付与

mod JsonOrdered {

    /// JSON 値のキー順保持版
    pub enum OrderedJson {
        case OObject(List[(String, OrderedJson)])
        case OArray(List[OrderedJson], ArrayStyle)
        case OString(String)
        case ONumber(String)     // raw text を保持
        case OBool(Bool)
        case ONull
    }

    /// 配列の表示スタイル
    pub enum ArrayStyle {
        case Inline      // [0, 0] のように 1 行
        case Block       // 改行で展開
    }

    // ========================================================================
    // パーサ
    // ========================================================================

    /// JSON テキストをパースして OrderedJson を返す。失敗時は Err(理由)。
    pub def parse(text: String): Result[String, OrderedJson] =
        let n = String.length(text);
        let pos = skipWs(text, n, 0);
        match parseValue(text, n, pos) {
            case Err(e) => Err(e)
            case Ok((value, after)) =>
                let trailing = skipWs(text, n, after);
                if (trailing == n) Ok(value)
                else Err("trailing garbage at offset ${trailing}")
        }

    /// 位置 pos からの 1 つの JSON 値をパースして (値, 次の位置) を返す
    def parseValue(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        if (pos >= n) Err("unexpected end of input")
        else {
            let c = String.charAt(pos, text);
            if (c == '{') parseObject(text, n, pos + 1)
            else if (c == '[') parseArray(text, n, pos + 1)
            else if (c == '"') parseString(text, n, pos + 1) |> Result.map(match (s, p) -> (OrderedJson.OString(s), p))
            else if (c == 't' or c == 'f') parseBool(text, n, pos)
            else if (c == 'n') parseNull(text, n, pos)
            else if (isNumberStart(c)) parseNumber(text, n, pos)
            else Err("unexpected char '${c}' at offset ${pos}")
        }

    def isNumberStart(c: Char): Bool =
        c == '-' or (c >= '0' and c <= '9')

    def isDigit(c: Char): Bool =
        c >= '0' and c <= '9'

    /// 空白 (space, tab, newline, CR) を読み飛ばす
    def skipWs(text: String, n: Int32, pos: Int32): Int32 =
        if (pos >= n) pos
        else {
            let c = String.charAt(pos, text);
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r')
                skipWs(text, n, pos + 1)
            else pos
        }

    /// object をパース。開始 `{` の **次の位置** を pos で受け取る
    def parseObject(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        let p0 = skipWs(text, n, pos);
        if (p0 >= n) Err("unexpected end of input inside object")
        else if (String.charAt(p0, text) == '}')
            Ok((OrderedJson.OObject(Nil), p0 + 1))
        else parseObjectEntries(text, n, p0, Nil)

    def parseObjectEntries(text: String, n: Int32, pos: Int32,
                            acc: List[(String, OrderedJson)]):
            Result[String, (OrderedJson, Int32)] =
        if (pos >= n) Err("unexpected end of input inside object")
        else if (String.charAt(pos, text) != '"')
            Err("expected string key at offset ${pos}")
        else match parseString(text, n, pos + 1) {
            case Err(e) => Err(e)
            case Ok((key, afterKey)) =>
                let afterColon = skipWs(text, n, afterKey);
                if (afterColon >= n or String.charAt(afterColon, text) != ':')
                    Err("expected ':' after key at offset ${afterColon}")
                else {
                    let valStart = skipWs(text, n, afterColon + 1);
                    match parseValue(text, n, valStart) {
                        case Err(e) => Err(e)
                        case Ok((value, afterVal)) =>
                            let newAcc = (key, value) :: acc;
                            let afterSep = skipWs(text, n, afterVal);
                            if (afterSep >= n)
                                Err("unexpected end of input after value")
                            else {
                                let sep = String.charAt(afterSep, text);
                                if (sep == ',') {
                                    let next = skipWs(text, n, afterSep + 1);
                                    parseObjectEntries(text, n, next, newAcc)
                                }
                                else if (sep == '}')
                                    Ok((OrderedJson.OObject(List.reverse(newAcc)),
                                        afterSep + 1))
                                else Err("expected ',' or '}' at offset ${afterSep}")
                            }
                    }
                }
        }

    /// array をパース。開始 `[` の **次の位置** を pos で受け取る
    def parseArray(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        // `[` から `]` までの間に改行が含まれていれば block、無ければ inline と判定
        let p0 = skipWs(text, n, pos);
        if (p0 >= n) Err("unexpected end of input inside array")
        else if (String.charAt(p0, text) == ']') {
            let hasNewline = containsNewline(text, pos, p0);
            let style = if (hasNewline) ArrayStyle.Block else ArrayStyle.Inline;
            Ok((OrderedJson.OArray(Nil, style), p0 + 1))
        } else parseArrayElements(text, n, pos, p0, Nil)

    def parseArrayElements(text: String, n: Int32, openPos: Int32, pos: Int32,
                            acc: List[OrderedJson]):
            Result[String, (OrderedJson, Int32)] =
        match parseValue(text, n, pos) {
            case Err(e) => Err(e)
            case Ok((value, afterVal)) =>
                let newAcc = value :: acc;
                let afterSep = skipWs(text, n, afterVal);
                if (afterSep >= n)
                    Err("unexpected end of input after array element")
                else {
                    let sep = String.charAt(afterSep, text);
                    if (sep == ',') {
                        let next = skipWs(text, n, afterSep + 1);
                        parseArrayElements(text, n, openPos, next, newAcc)
                    }
                    else if (sep == ']') {
                        let hasNewline = containsNewline(text, openPos, afterSep);
                        let style = if (hasNewline) ArrayStyle.Block else ArrayStyle.Inline;
                        Ok((OrderedJson.OArray(List.reverse(newAcc), style),
                            afterSep + 1))
                    }
                    else Err("expected ',' or ']' at offset ${afterSep}")
                }
        }

    /// 範囲 [start, end) に '\n' が含まれるか
    def containsNewline(text: String, start: Int32, endPos: Int32): Bool =
        if (start >= endPos) false
        else if (String.charAt(start, text) == '\n') true
        else containsNewline(text, start + 1, endPos)

    /// string をパース。開始 `"` の **次の位置** を pos で受け取る。
    /// JSON エスケープ (\n \t \" \\ \uXXXX 等) を解釈して unescape した文字列を返す
    def parseString(text: String, n: Int32, pos: Int32):
            Result[String, (String, Int32)] =
        parseStringInner(text, n, pos, "")

    def parseStringInner(text: String, n: Int32, pos: Int32, acc: String):
            Result[String, (String, Int32)] =
        if (pos >= n) Err("unterminated string")
        else {
            let c = String.charAt(pos, text);
            if (c == '"') Ok((acc, pos + 1))
            else if (c == '\\') {
                if (pos + 1 >= n) Err("unterminated escape")
                else {
                    let e = String.charAt(pos + 1, text);
                    let (decoded, advance) =
                        if (e == '"')      ("\"", 2)
                        else if (e == '\\') ("\\", 2)
                        else if (e == '/')  ("/", 2)
                        else if (e == 'n')  ("\n", 2)
                        else if (e == 't')  ("\t", 2)
                        else if (e == 'r')  ("\r", 2)
                        else (Char.toString(e), 2);
                    parseStringInner(text, n, pos + advance, "${acc}${decoded}")
                }
            }
            else parseStringInner(text, n, pos + 1, "${acc}${c}")
        }

    /// number を**生文字列**としてパースする（フォーマット保持のため）
    def parseNumber(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        let endPos = scanNumberEnd(text, n, pos);
        if (endPos == pos) Err("expected number at offset ${pos}")
        else {
            let raw = String.slice(start = pos, end = endPos, text);
            Ok((OrderedJson.ONumber(raw), endPos))
        }

    /// 数値リテラルの終端を見つける（最初の数値以外の文字、または EOF）
    def scanNumberEnd(text: String, n: Int32, pos: Int32): Int32 =
        if (pos >= n) pos
        else {
            let c = String.charAt(pos, text);
            if (isDigit(c) or c == '.' or c == '-' or c == '+'
                or c == 'e' or c == 'E')
                scanNumberEnd(text, n, pos + 1)
            else pos
        }

    /// true / false をパース
    def parseBool(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        if (pos + 4 <= n and String.slice(start = pos, end = pos + 4, text) == "true")
            Ok((OrderedJson.OBool(true), pos + 4))
        else if (pos + 5 <= n and String.slice(start = pos, end = pos + 5, text) == "false")
            Ok((OrderedJson.OBool(false), pos + 5))
        else Err("expected true/false at offset ${pos}")

    /// null をパース
    def parseNull(text: String, n: Int32, pos: Int32):
            Result[String, (OrderedJson, Int32)] =
        if (pos + 4 <= n and String.slice(start = pos, end = pos + 4, text) == "null")
            Ok((OrderedJson.ONull, pos + 4))
        else Err("expected null at offset ${pos}")

    // ========================================================================
    // ライター
    // ========================================================================

    /// OrderedJson を整形済み JSON 文字列に書き出す。
    /// indent は半角空白何個でインデントするか（通常 2）。
    /// 末尾には必ず '\n' を付ける。
    pub def writePretty(indent: Int32, json: OrderedJson): String =
        let body = writeValue(indent, 0, json);
        "${body}\n"

    /// depth はネスト深さ（0 = ルート）
    def writeValue(indent: Int32, depth: Int32, json: OrderedJson): String =
        match json {
            case OrderedJson.OObject(entries) => writeObject(indent, depth, entries)
            case OrderedJson.OArray(items, style) => writeArray(indent, depth, items, style)
            case OrderedJson.OString(s) => "\"${escapeString(s)}\""
            case OrderedJson.ONumber(raw) => raw
            case OrderedJson.OBool(b) => if (b) "true" else "false"
            case OrderedJson.ONull => "null"
        }

    def writeObject(indent: Int32, depth: Int32,
                     entries: List[(String, OrderedJson)]): String =
        match entries {
            case Nil => "{}"
            case _ =>
                let inner = depth + 1;
                let innerPad = padOf(indent, inner);
                let closePad = padOf(indent, depth);
                let body = entries
                    |> List.map(match (k, v) ->
                        "${innerPad}\"${escapeString(k)}\": ${writeValue(indent, inner, v)}")
                    |> String.intercalate(",\n");
                "{\n${body}\n${closePad}}"
        }

    def writeArray(indent: Int32, depth: Int32,
                    items: List[OrderedJson], style: ArrayStyle): String =
        match items {
            case Nil => "[]"
            case _ => match style {
                case ArrayStyle.Inline =>
                    let body = items
                        |> List.map(v -> writeValue(indent, depth, v))
                        |> String.intercalate(", ");
                    "[${body}]"
                case ArrayStyle.Block =>
                    let inner = depth + 1;
                    let innerPad = padOf(indent, inner);
                    let closePad = padOf(indent, depth);
                    let body = items
                        |> List.map(v -> "${innerPad}${writeValue(indent, inner, v)}")
                        |> String.intercalate(",\n");
                    "[\n${body}\n${closePad}]"
            }
        }

    /// indent * depth 個の空白を返す
    def padOf(indent: Int32, depth: Int32): String =
        String.repeat(indent * depth, " ")

    /// 文字列を JSON エスケープする（"\\, \", \n, \t, \r, 制御文字, /は素のまま）
    def escapeString(s: String): String =
        String.toList(s)
            |> List.map(escapeChar)
            |> List.foldLeft((a, b) -> "${a}${b}", "")

    def escapeChar(c: Char): String =
        if (c == '"') "\\\""
        else if (c == '\\') "\\\\"
        else if (c == '\n') "\\n"
        else if (c == '\r') "\\r"
        else if (c == '\t') "\\t"
        else Char.toString(c)
}
