/// Yarn Spinner の出力 JSON を Flix の型として表現する純粋データ定義。
///
/// このモジュールはエンジン層（`src/engine/` `src/scenes/` `src/game/`）に
/// 一切依存しない。ローダ・VM・ストレージなど Yarn 関連の他モジュールから
/// 参照される最下層。
///
/// JSON 構造との対応:
///   program.nodes[name]              -> YarnNode
///   program.nodes[name].instructions -> Vector[Instruction]
///   program.initialValues[var]       -> Value
///   strings[lineRef].text             -> Map[LineRef, String]
mod Yarn.Types {

    /// Yarn の値。スタック・変数・引数・戻り値で共通に使う。
    /// JSON の `boolValue` / `floatValue` / `stringValue` の 3 種に対応。
    pub enum Value with Eq, ToString {
        case BoolV(Bool)
        case FloatV(Float64)
        case StringV(String)
    }

    /// 行を識別する文字列（例: "line:9110649c"）。
    pub type alias LineRef = String

    /// Yarn 命令ストリーム上の絶対アドレス（VM のインストラクションポインタ）。
    /// `JumpIfFalse` / `JumpTo` / `AddChoice` の destination で使う。
    pub type alias InstructionPointer = Int32

    /// 行表示・選択肢・コマンドの引数置換に使う「スタックから pop する個数」。
    pub type alias SubstitutionCount = Int32

    /// `<<commandName arg1 arg2>>` のコマンドテキスト全体（コマンド名と引数を含む）。
    pub type alias CommandText = String

    /// ノードヘッダの 1 エントリ。`title` や `$Yarn.Internal.TrackingVariable` など。
    pub type alias Header = {
        key   = String,
        value = String
    }

    /// Yarn 仮想マシンの命令。16 種。
    /// 各バリアントが必要な引数だけを持つように整形してある。
    pub enum Instruction with Eq, ToString {
        /// 1 行表示。スタック上位 N 個を pop して置換に使う。
        case RunLine(LineRef, SubstitutionCount)
        /// 選択肢を蓄積する。最後の Bool は条件付きフラグ。
        /// (lineId, destination, substitutionCount, hasCondition)
        /// JSON 上は `"addOption"` キー (Yarn Spinner 仕様)。
        case AddChoice(LineRef, InstructionPointer, SubstitutionCount, Bool)
        /// 蓄積済みの選択肢を提示し、ユーザの選択結果をスタックに push する。
        /// JSON 上は `"showOptions"` キー (Yarn Spinner 仕様)。
        case ShowChoices
        /// スタック top を覗いて `false` ならジャンプ。pop しない。
        case JumpIfFalse(InstructionPointer)
        /// 無条件ジャンプ。
        case JumpTo(InstructionPointer)
        /// スタック top（数値）をジャンプ先として読み取る。pop しない。
        case PeekAndJump
        /// スタック top を捨てる。
        case Pop
        /// ノード終了。callStack を持つ場合は復帰、空なら対話完了。
        case Return
        /// 対話を強制終了。callStack を破棄して即 DialogueComplete に遷移する。
        /// `<<stop>>` 由来。GameOver や強制ジャンプ後の終端で使う。
        case Stop
        /// 文字列をスタックに積む。
        case PushString(String)
        /// 数値をスタックに積む。
        case PushFloat(Float64)
        /// 真偽値をスタックに積む（`<<set $x = true>>` のリテラル代入で出る）。
        case PushBool(Bool)
        /// 変数の値をスタックに積む。
        case PushVariable(String)
        /// スタック top を変数に書き込む（pop はしない）。
        case StoreVariable(String)
        /// 関数を呼ぶ。直前の `pushFloat` で push した数値が引数の個数。
        case CallFunc(String)
        /// カスタムコマンド実行。スタック上位 N 個を pop して置換に使う。
        case RunCommand(CommandText, SubstitutionCount)
        /// `<<jump X>>` 由来。currentNode を置き換えるだけで callStack には積まない。
        /// 飛び先で `Return` に達するとそのまま対話完了。
        case RunNode(String)
        /// `<<detour X>>` 由来。callStack に戻り先を積んでから移動する。
        /// 飛び先で `Return` に達したら呼び出し元に戻る。
        case Detour(String)
    }

    /// Yarn のノード（命令列とメタデータ）。
    pub type alias YarnNode = {
        name         = String,
        headers      = List[Header],
        instructions = Vector[Instruction]
    }

    /// プログラム全体。
    pub type alias Program = {
        name            = String,
        nodes           = Map[String, YarnNode],
        initialValues   = Map[String, Value],
        languageVersion = Int32
    }

    /// 出力 JSON 全体（プログラム + 文字列テーブル）。
    /// 診断情報 `diagnostics` は今のところ捨てている。
    pub type alias YarnProject = {
        program = Program,
        strings = Map[LineRef, String]
    }

    /// 蓄積された選択肢の 1 エントリ。`AddChoice` で追加され、`ShowChoices` で view に流れる。
    pub type alias ChoiceEntry = {
        lineId        = LineRef,
        substitutions = List[String],
        destination   = Int32,
        available     = Bool
    }

    /// `RunNode` 時に保存する戻り先情報。
    pub type alias CallFrame = {
        nodeName                 = String,
        returnInstructionPointer = Int32
    }
}
