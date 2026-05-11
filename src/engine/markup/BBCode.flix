/// BBCode 風マークアップの汎用トークナイザ。
///
/// Yarn Spinner 側でも RichTextLabel 側でも `[name]` `[name=value]`
/// `[name attr=v ...]` `[/name]` といったタグ表記を扱うため、
/// 文字列 → トークン列へ変換する純粋関数を提供する。
///
/// このモジュールは「色」など個別の解釈を持たず、構造だけを取り出す。
/// 各利用側（描画・整形・変換）が `OpenTag` / `CloseTag` の名前と属性を
/// 見て自前の意味づけを行う。
mod Markup.BBCode {

    /// `[name]` `[name=value]` `[/name]` の name 部分。
    pub type alias TagName = String

    /// `[name a=1 b=2]` の属性 Map。
    /// `[name=value]` 形式では、タグ名と同じキーで値が入る。
    pub type alias Attributes = Map[String, String]

    /// 1 つのマークアップ片。
    /// - `Text` … タグ以外の生テキスト
    /// - `OpenTag` … `[name]` `[name=value]` `[name a=1 b=2]` 等の開始タグ
    /// - `CloseTag` … `[/name]` の終了タグ
    pub enum Token with Eq, ToString {
        case Text(String)
        case OpenTag(TagName, Attributes)
        case CloseTag(TagName)
    }

    /// BBCode 風文字列をトークン列に分解する。
    ///
    /// パース不能な箇所（未閉じ `[`、空タグ `[]`、不正属性など）は
    /// `[` ごと再構成して `Text` として保持する（情報を捨てない）。
    pub def parse(text: String): List[Token] =
        let chars = String.toList(text);
        loop(chars, Nil, Nil) |> List.reverse

    /// トークン列を BBCode 文字列に戻す（`parse` の逆）。
    ///
    /// 属性順は `Map` の走査順に依存するため、入力と完全一致する保証はない。
    /// 「parse で構造を取り出して同じ列を再構築する」用途で使う。
    pub def render(tokens: List[Token]): String =
        List.foldLeft((acc, token) -> acc + tokenToString(token), "", tokens)

    /// 可視文字数（`Text` トークンの中身の文字数合計）を返す。
    /// `[color=red]` などタグそのものは 0 として扱う。
    /// typewriter の進捗（`revealProgress`）でタグを字数に算入させないために使う。
    pub def visibleLength(text: String): Int32 =
        parse(text)
            |> List.foldLeft((acc, token) -> match token {
                case Token.Text(s) => acc + String.length(s)
                case _             => acc
            }, 0)

    /// 先頭から `n` 個の可視文字までを切り出して BBCode 文字列として返す。
    ///
    /// 仕様:
    ///   - タグ自体は文字数 0（`[color=red]` を露出しても可視文字消費はない）
    ///   - `Text` トークンの途中で切れる場合は `String.take` で頭から
    ///   - 切り出し時点で開いていた `OpenTag` は末尾に対応する `CloseTag` を生成して閉じる
    ///     （typewriter 中でも入れ子の色が正しく見えるようにするため）
    ///
    /// 入力が壊れた BBCode（未閉じ等）でも、`parse` が `Text` 化するので動作は安定。
    pub def sliceVisible(text: String, n: Int32): String =
        let cleanN = Int32.max(0, n);
        let result = sliceLoop(parse(text), cleanN, Nil, Nil);
        let closing = List.map(name -> Token.CloseTag(name), result#openStack);
        let body = List.reverse(result#output);
        render(List.append(body, closing))

    /// `sliceVisible` の本体ループ。
    /// `openStack` は「現在開いている色タグ名」の LIFO（先頭が最新）。
    /// `output` は逆順の出力 token 列（最後に reverse する）。
    def sliceLoop(tokens: List[Token], remaining: Int32,
                   openStack: List[String], output: List[Token]):
                   { openStack = List[String], output = List[Token] } =
        if (remaining <= 0)
            { openStack = openStack, output = output }
        else match tokens {
            case Nil =>
                { openStack = openStack, output = output }
            case Token.Text(s) :: rest =>
                let len = String.length(s);
                if (len <= remaining)
                    sliceLoop(rest, remaining - len, openStack, Token.Text(s) :: output)
                else {
                    let head = String.take(remaining, s);
                    { openStack = openStack, output = Token.Text(head) :: output }
                }
            case Token.OpenTag(name, attrs) :: rest =>
                sliceLoop(rest, remaining, name :: openStack,
                           Token.OpenTag(name, attrs) :: output)
            case Token.CloseTag(name) :: rest =>
                sliceLoop(rest, remaining, popMatching(name, openStack),
                           Token.CloseTag(name) :: output)
        }

    /// `openStack` の先頭が `name` と一致するなら 1 つ pop する。
    /// 不一致なら据え置き（壊れた入れ子に対する堅牢化）。
    def popMatching(name: String, stack: List[String]): List[String] =
        match stack {
            case Nil          => Nil
            case head :: rest => if (head == name) rest else stack
        }

    /// 1 トークンを BBCode 文字列に直す。
    pub def tokenToString(token: Token): String = match token {
        case Token.Text(text)            => text
        case Token.OpenTag(name, attrs)  => renderOpenTag(name, attrs)
        case Token.CloseTag(name)        => "[/${name}]"
    }

    /// `OpenTag` を `[name]` / `[name=value]` / `[name a=v b=w]` の形に書き出す。
    /// 値ショートハンド（`name=value`）はタグ名と同名キーの属性として保持されている前提。
    pub def renderOpenTag(name: String, attrs: Map[String, String]): String =
        let valueShorthand = Map.get(name, attrs);
        let otherAttrs = Map.remove(name, attrs);
        let head = match valueShorthand {
            case Some(value) => "${name}=${value}"
            case None        => name
        };
        let tail = Map.foldLeftWithKey((acc, key, value) -> "${acc} ${key}=${value}", "", otherAttrs);
        "[${head}${tail}]"

    /// パーサ本体。
    ///
    /// - `chars` … まだ読んでいない入力（先頭が次の文字）
    /// - `pendingText` … 直近の Text バッファ（逆順、最新の文字が先頭）
    /// - `acc` … これまで確定したトークン（逆順、最新が先頭）
    def loop(chars: List[Char], pendingText: List[Char], acc: List[Token]): List[Token] =
        match chars {
            case Nil =>
                flushPendingText(pendingText, acc)
            case '[' :: rest =>
                match takeUntilCloseBracket(rest) {
                    case Some((tagBody, after)) =>
                        match interpretTag(tagBody) {
                            case Some(token) =>
                                let flushed = flushPendingText(pendingText, acc);
                                loop(after, Nil, token :: flushed)
                            case None =>
                                // タグとして解釈不能 → '[' + tagBody + ']' を生テキスト扱い
                                let recon = '[' :: List.append(String.toList(tagBody), ']' :: Nil);
                                let nextPending = appendInOrder(recon, pendingText);
                                loop(after, nextPending, acc)
                        }
                    case None =>
                        // 閉じ括弧が見つからない → '[' をそのまま生テキスト扱いして次へ
                        loop(rest, '[' :: pendingText, acc)
                }
            case ch :: rest =>
                loop(rest, ch :: pendingText, acc)
        }

    /// 逆順 Text バッファを Token.Text として確定し、acc に積む。空ならそのまま返す。
    def flushPendingText(pendingText: List[Char], acc: List[Token]): List[Token] =
        if (List.isEmpty(pendingText)) acc
        else Token.Text(charsToString(List.reverse(pendingText))) :: acc

    /// 入力 `chars`（順序通り）を逆順バッファ `buf` の末尾に積む。
    /// `buf` は逆順なので、各文字を順に cons するだけで「末尾追加」になる。
    def appendInOrder(chars: List[Char], buf: List[Char]): List[Char] =
        List.foldLeft((acc, ch) -> ch :: acc, buf, chars)

    /// `[` 直後の入力から最初の `]` までを取り出す。
    /// 見つからなければ `None`（呼び出し側で `[` をリテラル化する）。
    def takeUntilCloseBracket(chars: List[Char]): Option[(String, List[Char])] =
        let result = List.foldLeft((acc, ch) -> {
            if (acc#found) {body = acc#body, rest = ch :: acc#rest, found = true}
            else if (ch == ']') {body = acc#body, rest = acc#rest, found = true}
            else {body = ch :: acc#body, rest = acc#rest, found = false}
        }, {body = (Nil: List[Char]), rest = (Nil: List[Char]), found = false}, chars);
        if (result#found)
            Some((charsToString(List.reverse(result#body)), List.reverse(result#rest)))
        else
            None

    /// タグ本体（`[` と `]` の間）を解釈し、対応する Token を返す。
    /// 解釈できなければ `None`（呼び出し側でリテラル化）。
    def interpretTag(rawBody: String): Option[Token] =
        let body = String.trim(rawBody);
        if (String.isEmpty(body)) None
        else if (String.startsWith(prefix = "/", body)) interpretCloseTag(body)
        else interpretOpenTag(body)

    /// `/name` 形式の終了タグを解釈する。
    /// 名前が空、または名前部に空白を含む（例: `/color extra`）場合は不正。
    def interpretCloseTag(body: String): Option[Token] =
        let name = String.drop(1, body) |> String.trim;
        if (String.isEmpty(name) or hasWhiteSpace(name)) None
        else Some(Token.CloseTag(name))

    /// `name` / `name=value` / `name a=1 b=2` / `name=v a=1` 形式の開始タグを解釈する。
    def interpretOpenTag(body: String): Option[Token] =
        match splitOnSpaces(body) {
            case Nil => None
            case head :: rest =>
                let (name, headValue) = splitOnFirstEquals(head);
                if (String.isEmpty(name)) None
                else match collectAttrs(rest, Map.empty()) {
                    case None       => None
                    case Some(attrs) =>
                        let merged = match headValue {
                            case Some(value) => Map.insert(name, value, attrs)
                            case None        => attrs
                        };
                        Some(Token.OpenTag(name, merged))
                }
        }

    /// 残り属性ピースをすべて `key=value` で解釈し、Map に集める。
    /// 1 つでも `=` を含まないピースがあれば `None`（不正タグ）。
    def collectAttrs(pieces: List[String], acc: Map[String, String]): Option[Map[String, String]] =
        match pieces {
            case Nil => Some(acc)
            case piece :: rest =>
                let (key, valueOpt) = splitOnFirstEquals(piece);
                match valueOpt {
                    case None => None
                    case Some(value) =>
                        if (String.isEmpty(key)) None
                        else collectAttrs(rest, Map.insert(key, value, acc))
                }
        }

    /// 文字列を空白文字（半角空白・タブ・改行）で区切る。連続空白は 1 区切り扱い。
    /// 先頭末尾の空白は無視される。
    def splitOnSpaces(text: String): List[String] =
        let result = List.foldLeft((acc, ch) -> {
            if (isWhiteSpaceChar(ch))
                if (List.isEmpty(acc#current)) acc
                else {pieces = charsToString(List.reverse(acc#current)) :: acc#pieces, current = (Nil: List[Char])}
            else
                {pieces = acc#pieces, current = ch :: acc#current}
        }, {pieces = (Nil: List[String]), current = (Nil: List[Char])}, String.toList(text));
        let finalPieces =
            if (List.isEmpty(result#current)) result#pieces
            else charsToString(List.reverse(result#current)) :: result#pieces;
        List.reverse(finalPieces)

    /// 文字列を最初の `=` で 2 分割する。`=` がなければ `(全体, None)`。
    /// 値側に `=` が含まれていても以降は 1 つの値として保持する（例: URL 値）。
    def splitOnFirstEquals(text: String): (String, Option[String]) =
        let result = List.foldLeft((acc, ch) -> {
            if (acc#found)
                {left = acc#left, right = ch :: acc#right, found = true}
            else if (ch == '=')
                {left = acc#left, right = acc#right, found = true}
            else
                {left = ch :: acc#left, right = acc#right, found = false}
        }, {left = (Nil: List[Char]), right = (Nil: List[Char]), found = false}, String.toList(text));
        let leftStr = charsToString(List.reverse(result#left));
        if (result#found)
            (leftStr, Some(charsToString(List.reverse(result#right))))
        else
            (leftStr, None)

    /// 文字列に空白文字が 1 文字でも含まれるか
    def hasWhiteSpace(text: String): Bool =
        String.toList(text) |> List.exists(isWhiteSpaceChar)

    /// 半角空白・タブ・改行のいずれか
    def isWhiteSpaceChar(ch: Char): Bool =
        ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r'

    /// `List[Char]` を `String` に連結する。
    def charsToString(chars: List[Char]): String =
        List.foldLeft((acc, ch) -> acc + Char.toString(ch), "", chars)
}
