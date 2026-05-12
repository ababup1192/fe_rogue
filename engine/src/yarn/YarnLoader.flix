/// Yarn Spinner が出力した output.json 形式の文字列を `YarnProject` に変換する。
///
/// 内部では `mlutze/flix-json` の `Json.Parse.parse` で `JsonElement` AST に
/// 落としたあと、自前のデコーダで構造をたどって型付け済みデータに組み立てる。
/// `Json.Parse.parse` は pure（effect なし）なので、本モジュールも pure。
///
/// 命令の JSON は `{"<opcode>": { ...operands }}` の単一キーオブジェクト。
/// このキー文字列で `Instruction` バリアントへ振り分ける。
///
/// 値の JSON は `{"boolValue": ...}` / `{"floatValue": ...}` / `{"stringValue": ...}`
/// の単一キー判別。
mod Yarn.Loader {
    use Yarn.Types.{Value, Instruction, Header, YarnNode, Program, YarnProject, LineRef}
    use Json.JsonElement.{JsonObject, JsonArray, JsonString, JsonNumber, JsonBool, JsonNull}

    /// ローダの失敗。位置情報は `where` に文字列で残し、原因は `message`。
    pub enum YarnLoadError with Eq, ToString {
        case JsonParseError(String)
        case MissingField(String)
        case UnknownInstruction(String)
        case BadValueShape(String)
        case BadType(String)
    }

    /// JSON 文字列から `YarnProject` を組み立てる入口。
    pub def parseProject(jsonText: String): Result[YarnLoadError, YarnProject] =
        match Json.Parse.parse(jsonText) {
            case None        => Err(YarnLoadError.JsonParseError("invalid JSON"))
            case Some(root)  => decodeRoot(root)
        }

    /// ルート: `{"program": ..., "strings": ..., "diagnostics": [...]}`
    def decodeRoot(element: Json.JsonElement): Result[YarnLoadError, YarnProject] =
        forM (
            object       <- expectObject(element, "<root>");
            programJson  <- requireKey("program", object);
            stringsJson  <- requireKey("strings", object);
            program      <- decodeProgram(programJson);
            strings      <- decodeStrings(stringsJson)
        ) yield {
            { program = program, strings = strings }
        }

    /// `strings` セクション: `{ lineRef: { "text": "..." } }`
    def decodeStrings(element: Json.JsonElement): Result[YarnLoadError, Map[LineRef, String]] =
        forM (
            object  <- expectObject(element, "strings");
            entries <- traverseMap(decodeStringEntry, object)
        ) yield entries

    def decodeStringEntry(element: Json.JsonElement): Result[YarnLoadError, String] =
        forM (
            object   <- expectObject(element, "strings[*]");
            textJson <- requireKey("text", object);
            text     <- expectString(textJson, "strings[*].text")
        ) yield text

    /// `program` セクション。
    def decodeProgram(element: Json.JsonElement): Result[YarnLoadError, Program] =
        forM (
            object              <- expectObject(element, "program");
            nameJson            <- requireKey("name", object);
            name                <- expectString(nameJson, "program.name");
            nodesJson           <- requireKey("nodes", object);
            nodes               <- decodeNodes(nodesJson);
            initialValuesJson   <- requireKey("initialValues", object);
            initialValues       <- decodeInitialValues(initialValuesJson);
            languageVersionJson <- requireKey("languageVersion", object);
            languageVersion     <- expectInt32(languageVersionJson, "program.languageVersion")
        ) yield {
            {
                name            = name,
                nodes           = nodes,
                initialValues   = initialValues,
                languageVersion = languageVersion
            }
        }

    def decodeNodes(element: Json.JsonElement): Result[YarnLoadError, Map[String, YarnNode]] =
        forM (
            object  <- expectObject(element, "program.nodes");
            entries <- traverseMap(decodeNode, object)
        ) yield entries

    def decodeNode(element: Json.JsonElement): Result[YarnLoadError, YarnNode] =
        forM (
            object           <- expectObject(element, "node");
            nameJson         <- requireKey("name", object);
            name             <- expectString(nameJson, "node.name");
            headersJson      <- requireKey("headers", object);
            headers          <- decodeHeaders(headersJson);
            instructionsJson <- requireKey("instructions", object);
            instructions     <- decodeInstructions(instructionsJson)
        ) yield {
            { name = name, headers = headers, instructions = instructions }
        }

    def decodeHeaders(element: Json.JsonElement): Result[YarnLoadError, List[Header]] =
        forM (
            elements <- expectArray(element, "node.headers");
            headers  <- traverseVector(decodeHeader, elements)
        ) yield Vector.toList(headers)

    def decodeHeader(element: Json.JsonElement): Result[YarnLoadError, Header] =
        forM (
            object    <- expectObject(element, "header");
            keyJson   <- requireKey("key", object);
            keyValue  <- expectString(keyJson, "header.key");
            valueJson <- requireKey("value", object);
            valueText <- expectString(valueJson, "header.value")
        ) yield {
            { key = keyValue, value = valueText }
        }

    def decodeInstructions(element: Json.JsonElement): Result[YarnLoadError, Vector[Instruction]] =
        forM (
            elements     <- expectArray(element, "node.instructions");
            instructions <- traverseVector(decodeInstruction, elements)
        ) yield instructions

    /// 命令: `{"<opcode>": { ...operands }}` の単一キーオブジェクト。
    def decodeInstruction(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "instruction");
            single   <- expectSingleEntry(object, "instruction");
            (opcode, operands) = single;
            decoded  <- decodeOperands(opcode, operands)
        ) yield decoded

    def decodeOperands(opcode: String, operands: Json.JsonElement):
                        Result[YarnLoadError, Instruction] =
        match opcode {
            case "runLine"        => decodeRunLine(operands)
            case "addOption"      => decodeAddChoice(operands)
            case "showOptions"    => Ok(Instruction.ShowChoices)
            case "jumpIfFalse"    => decodeJumpIfFalse(operands)
            case "jumpTo"         => decodeJumpTo(operands)
            case "peekAndJump"    => Ok(Instruction.PeekAndJump)
            case "pop"            => Ok(Instruction.Pop)
            case "return"         => Ok(Instruction.Return)
            case "stop"           => Ok(Instruction.Stop)
            case "pushString"     => decodePushString(operands)
            case "pushFloat"      => decodePushFloat(operands)
            case "pushBool"       => decodePushBool(operands)
            case "pushVariable"   => decodePushVariable(operands)
            case "storeVariable"  => decodeStoreVariable(operands)
            case "callFunc"       => decodeCallFunc(operands)
            case "runCommand"     => decodeRunCommand(operands)
            case "runNode"        => decodeRunNode(operands)
            case "detourToNode"   => decodeDetourToNode(operands)
            case _                => Err(YarnLoadError.UnknownInstruction(opcode))
        }

    def decodeRunLine(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object               <- expectObject(element, "runLine");
            lineIdJson           <- requireKey("lineID", object);
            lineRef              <- expectString(lineIdJson, "runLine.lineID");
            substitutionCountJson <- requireKey("substitutionCount", object);
            substitutionCount    <- expectInt32(substitutionCountJson, "runLine.substitutionCount")
        ) yield Instruction.RunLine(lineRef, substitutionCount)

    /// JSON 上のキーは `"addOption"` (Yarn Spinner 仕様) だが、Flix 側型は `AddChoice`。
    def decodeAddChoice(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object               <- expectObject(element, "addOption");
            lineIdJson           <- requireKey("lineID", object);
            lineRef              <- expectString(lineIdJson, "addOption.lineID");
            destinationJson      <- requireKey("destination", object);
            destination          <- expectInt32(destinationJson, "addOption.destination");
            substitutionCountJson <- requireKey("substitutionCount", object);
            substitutionCount    <- expectInt32(substitutionCountJson, "addOption.substitutionCount");
            hasConditionJson     <- requireKey("hasCondition", object);
            hasCondition         <- expectBool(hasConditionJson, "addOption.hasCondition")
        ) yield Instruction.AddChoice(lineRef, destination, substitutionCount, hasCondition)

    def decodeJumpIfFalse(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object          <- expectObject(element, "jumpIfFalse");
            destinationJson <- requireKey("destination", object);
            destination     <- expectInt32(destinationJson, "jumpIfFalse.destination")
        ) yield Instruction.JumpIfFalse(destination)

    def decodeJumpTo(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object          <- expectObject(element, "jumpTo");
            destinationJson <- requireKey("destination", object);
            destination     <- expectInt32(destinationJson, "jumpTo.destination")
        ) yield Instruction.JumpTo(destination)

    def decodePushString(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "pushString");
            valueJson <- requireKey("value", object);
            value    <- expectString(valueJson, "pushString.value")
        ) yield Instruction.PushString(value)

    def decodePushFloat(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "pushFloat");
            valueJson <- requireKey("value", object);
            value    <- expectFloat64(valueJson, "pushFloat.value")
        ) yield Instruction.PushFloat(value)

    def decodePushBool(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "pushBool");
            valueJson <- requireKey("value", object);
            value    <- expectBool(valueJson, "pushBool.value")
        ) yield Instruction.PushBool(value)

    def decodePushVariable(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object       <- expectObject(element, "pushVariable");
            nameJson     <- requireKey("variableName", object);
            variableName <- expectString(nameJson, "pushVariable.variableName")
        ) yield Instruction.PushVariable(variableName)

    def decodeStoreVariable(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object       <- expectObject(element, "storeVariable");
            nameJson     <- requireKey("variableName", object);
            variableName <- expectString(nameJson, "storeVariable.variableName")
        ) yield Instruction.StoreVariable(variableName)

    def decodeCallFunc(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object       <- expectObject(element, "callFunc");
            nameJson     <- requireKey("functionName", object);
            functionName <- expectString(nameJson, "callFunc.functionName")
        ) yield Instruction.CallFunc(functionName)

    def decodeRunCommand(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object               <- expectObject(element, "runCommand");
            commandTextJson      <- requireKey("commandText", object);
            commandText          <- expectString(commandTextJson, "runCommand.commandText");
            substitutionCountJson <- requireKey("substitutionCount", object);
            substitutionCount    <- expectInt32(substitutionCountJson, "runCommand.substitutionCount")
        ) yield Instruction.RunCommand(commandText, substitutionCount)

    def decodeRunNode(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "runNode");
            nameJson <- requireKey("nodeName", object);
            nodeName <- expectString(nameJson, "runNode.nodeName")
        ) yield Instruction.RunNode(nodeName)

    /// `<<detour Foo>>` 由来。`Instruction.Detour` にデコード（`RunNode` とは
    /// 異なり callStack に戻りフレームを積む VM 側の実装に対応）。
    def decodeDetourToNode(element: Json.JsonElement): Result[YarnLoadError, Instruction] =
        forM (
            object   <- expectObject(element, "detourToNode");
            nameJson <- requireKey("nodeName", object);
            nodeName <- expectString(nameJson, "detourToNode.nodeName")
        ) yield Instruction.Detour(nodeName)

    /// `initialValues`: `{ "$var": { boolValue/floatValue/stringValue: ... } }`
    def decodeInitialValues(element: Json.JsonElement):
                              Result[YarnLoadError, Map[String, Value]] =
        forM (
            object  <- expectObject(element, "initialValues");
            entries <- traverseMap(decodeValue, object)
        ) yield entries

    /// `Value` の単一キー判別（boolValue / floatValue / stringValue）。
    pub def decodeValue(element: Json.JsonElement): Result[YarnLoadError, Value] =
        forM (
            object <- expectObject(element, "value");
            single <- expectSingleEntry(object, "value");
            (kind, payload) = single;
            v      <- decodeValueByKind(kind, payload)
        ) yield v

    def decodeValueByKind(kind: String, payload: Json.JsonElement):
                           Result[YarnLoadError, Value] =
        match kind {
            case "boolValue"   => Result.map(Value.BoolV, expectBool(payload, "boolValue"))
            case "floatValue"  => Result.map(Value.FloatV, expectFloat64(payload, "floatValue"))
            case "stringValue" => Result.map(Value.StringV, expectString(payload, "stringValue"))
            case _             => Err(YarnLoadError.BadValueShape("unknown value kind: ${kind}"))
        }

    // ════════════════════════════════════════════════════════════════════════
    // 汎用ヘルパー
    // ════════════════════════════════════════════════════════════════════════

    def expectObject(element: Json.JsonElement, path: String):
                       Result[YarnLoadError, Map[String, Json.JsonElement]] =
        match element {
            case JsonObject(map) => Ok(map)
            case _               => Err(YarnLoadError.BadType("${path}:expected object"))
        }

    def expectArray(element: Json.JsonElement, path: String):
                      Result[YarnLoadError, Vector[Json.JsonElement]] =
        match element {
            case JsonArray(elements) => Ok(elements)
            case _                   => Err(YarnLoadError.BadType("${path}:expected array"))
        }

    def expectString(element: Json.JsonElement, path: String):
                       Result[YarnLoadError, String] =
        match element {
            case JsonString(text) => Ok(text)
            case _                => Err(YarnLoadError.BadType("${path}:expected string"))
        }

    def expectBool(element: Json.JsonElement, path: String):
                     Result[YarnLoadError, Bool] =
        match element {
            case JsonBool(b) => Ok(b)
            case _           => Err(YarnLoadError.BadType("${path}:expected bool"))
        }

    def expectFloat64(element: Json.JsonElement, path: String):
                        Result[YarnLoadError, Float64] =
        match element {
            case JsonNumber(big) => Ok(BigDecimal.tryToFloat64(big) |> Option.getWithDefault(0.0))
            case _               => Err(YarnLoadError.BadType("${path}:expected number"))
        }

    def expectInt32(element: Json.JsonElement, path: String):
                      Result[YarnLoadError, Int32] =
        match element {
            case JsonNumber(big) =>
                Ok(Float64.tryToInt32(BigDecimal.tryToFloat64(big) |> Option.getWithDefault(0.0))
                    |> Option.getWithDefault(0))
            case _ => Err(YarnLoadError.BadType("${path}:expected integer"))
        }

    def requireKey(key: String, object: Map[String, Json.JsonElement]):
                     Result[YarnLoadError, Json.JsonElement] =
        match Map.get(key, object) {
            case Some(v) => Ok(v)
            case None    => Err(YarnLoadError.MissingField(key))
        }

    /// オブジェクトが「ちょうど 1 エントリ」であることを確かめてキーと値を返す。
    /// 命令や Value の単一キー判別に使う。
    def expectSingleEntry(object: Map[String, Json.JsonElement], path: String):
                            Result[YarnLoadError, (String, Json.JsonElement)] =
        let entries = Map.toList(object);
        match entries {
            case (key, value) :: Nil => Ok((key, value))
            case _                   =>
                Err(YarnLoadError.BadValueShape(
                    "${path}:expected single-key object, got ${List.length(entries)} keys"))
        }

    /// `Map[String, JsonElement]` の各値を decoder で変換して `Map[String, b]` を返す。
    /// 1 つでも失敗したら最初のエラーを返す。
    def traverseMap(decoder: Json.JsonElement -> Result[YarnLoadError, b],
                     object: Map[String, Json.JsonElement]):
                     Result[YarnLoadError, Map[String, b]] =
        Map.toList(object)
            |> Result.traverse(entry -> {
                let (k, v) = entry;
                Result.map(decoded -> (k, decoded), decoder(v))
            })
            |> Result.map(List.toMap)

    /// `Vector[JsonElement]` の各要素を decoder で変換。
    def traverseVector(decoder: Json.JsonElement -> Result[YarnLoadError, b],
                        elements: Vector[Json.JsonElement]):
                        Result[YarnLoadError, Vector[b]] =
        Vector.toList(elements)
            |> Result.traverse(decoder)
            |> Result.map(List.toVector)
}
