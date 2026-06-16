// EffectComposerPanel — 効果 DSL を日本語のドロップダウンで“組み立てる”合成エディタ。
//
// ResourcePanel.rebuildPropertyPanel から appendComposer が呼ばれ、weapons/consumables/
// rings/staves の sub-entry を表示中のとき、効果ルールを
//   「いつ（trigger）/ 誰に（target）/ 何を（op）/ 量（amount）/ 継続（for）」
// の日本語ドロップダウン＋数値で組み立てる UI を Property パネルに足す。値を変えるたびに
// 日本語1文プレビューが更新され、`effectRule` オブジェクトとして JSON に保存される。
// ＝ 当初構想の「日本語でDSLを組み立てる」エディタ。内部値（英字）は EffectRule の語彙に対応。
mod EffectComposerPanel {

    import javafx.collections.ObservableList
    import javafx.scene.Node
    import javafx.scene.control.Label
    import javafx.scene.control.CheckBox
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.{Object => JObject}
    import java.lang.Integer
    import java.lang.Boolean

    use Util.Json.Json

    // ── 各軸の (内部値, 日本語ラベル) ─────────────────────────
    def whenOpts(): List[(String, String)] =
        ("onUse", "使ったとき") :: ("onAttack", "攻撃したとき") :: ("onHit", "命中したとき") ::
        ("onKill", "敵を倒したとき") :: ("onTurnStart", "ターン開始ごと") ::
        ("onDeath", "HPが0になったとき") :: ("onEquip", "装備しているあいだ") ::
        ("onCast", "唱えたとき") :: ("onDamaged", "ダメージを受けたとき") ::
        ("onEnemyTurn", "敵のターンに") :: Nil

    def toOpts(): List[(String, String)] =
        ("self", "自分") :: ("target", "当たった相手") :: ("enemy", "敵") ::
        ("ally", "味方") :: ("attacker", "攻撃した自分") :: Nil

    def opOpts(): List[(String, String)] =
        ("healFlat", "HPを回復する") :: ("healFull", "HPを全回復する") ::
        ("damageFlat", "固定ダメージを与える") :: ("atkUp", "攻撃を上げる") ::
        ("spdUp", "速さを上げる") :: ("spdDown", "速さを下げる") ::
        ("defUp", "守備を上げる") :: ("defDown", "守備を下げる") ::
        ("hitDown", "命中を下げる") :: ("immobilize", "完全に動けなくする") ::
        ("maxHpUp", "最大HPを上げる") :: ("reviveCharge", "全回復してよみがえる") ::
        ("lifesteal", "与えたダメージ分回復する") ::
        // 盤面副作用系（杖で結線済み = StaffCastScene.customStaffEffect）。量は使わない。
        ("swapPos", "位置を入れ替える") :: ("knockback", "押し流す") ::
        ("warpToStairs", "止めて階段へ飛ばす") :: ("dropItem", "アイテムを落とさせる") ::
        ("ringify", "持ち物を指輪に変える") :: Nil

    def forOpts(): List[(String, String)] =
        ("instant", "すぐに（1回）") :: ("turns", "Nターン続く") :: ("permanent", "永続") ::
        ("whileEquipped", "装備しているあいだ") :: ("untilHit", "攻撃を受けるまで") :: Nil

    // 効果の種類。do=通常（do[] に撒く）/ replaceAttack=攻撃差し替え（敵ターンの特殊行動。隣接条件を
    // 暗黙付与し flow:replaceAttack へ展開）。followUp は敵ターン未配線のため出さない。
    def kindOpts(): List[(String, String)] =
        ("do", "通常の効果") :: ("replaceAttack", "攻撃を差し替える") :: Nil

    // 効果音（AudioStreamPlayer の音名）。"" は鳴らさない。
    def sfxOpts(): List[(String, String)] =
        ("", "なし") :: ("cure", "回復音") :: ("damage", "ダメージ音") :: ("magic", "魔法音") ::
        ("critical", "会心音") :: ("guard", "ガード音") :: ("get_item", "入手音") :: Nil

    // 視覚エフェクト。"" は出さない。
    def vfxOpts(): List[(String, String)] =
        ("", "なし") :: ("explosion", "爆発") :: ("explosionBig", "大爆発") :: Nil

    // ── (内部値 ⇄ ラベル) 変換 ───────────────────────────────
    def labelOf(value: String, opts: List[(String, String)]): String =
        List.find(p -> fst(p) == value, opts) |> Option.map(snd)
            |> Option.getWithDefault(List.head(opts) |> Option.map(snd) |> Option.getWithDefault(value))

    def valueOf(label: String, opts: List[(String, String)]): String =
        List.find(p -> snd(p) == label, opts) |> Option.map(fst)
            |> Option.getWithDefault(List.head(opts) |> Option.map(fst) |> Option.getWithDefault(label))

    def labelsOf(opts: List[(String, String)]): List[String] = List.map(snd, opts)

    // ── record から現在の effectRule を読む（無ければ既定値）──
    def effectRuleMap(record: Json): Map[String, Json] = match record {
        case Json.JObject(m) => match Map.get("effectRule", m) {
            case Some(Json.JObject(er)) => er
            case _                      => Map.empty()
        }
        case _ => Map.empty()
    }
    def erStr(er: Map[String, Json], key: String, dflt: String): String =
        match Map.get(key, er) {
            case Some(Json.JString(s)) => s
            case _                     => dflt
        }
    def erInt(er: Map[String, Json], key: String, dflt: Int32): Int32 =
        NodeInspector.jsonToInt(Map.get(key, er) |> Option.getWithDefault(Json.JNull))
            |> Option.getWithDefault(dflt)

    /// 効果の種類（簡易form の `kind`。欠落は "do"＝従来の通常効果＝後方互換）。
    def flowKindOf(er: Map[String, Json]): String = erStr(er, "kind", "do")

    /// 簡易form エディタが扱えない完全form（手書きの `flow`/`if` キーを含む）か。
    def isFullForm(er: Map[String, Json]): Bool =
        Map.memberOf("flow", er) or Map.memberOf("if", er)

    /// 効果合成エディタを Property パネルに足す。effect を持つカタログのときだけ。
    /// `mkCommit` は keyPath を渡すと「その場所へ JSON を書き戻すクロージャ」を返す。
    /// 組み立て結果は `effectRule`（構造化ルール）と `description`（ゲームが表示する効果文＝
    /// 生成した日本語1文）の両方へ書き込む。
    pub def appendComposer(children: ObservableList[Node], basePath: List[String],
                           record: Json, mkCommit: List[String] -> (Json -> Unit \ IO)): Unit \ IO =
        let cat = List.head(basePath);
        if (cat != Some("consumables") and cat != Some("weapons")
            and cat != Some("rings") and cat != Some("staves")
            and cat != Some("enemies")) ()
        else if (isFullForm(effectRuleMap(record)))
            // flow/if を含む完全form（手書き JSON）は簡易form エディタが誤読して上書き破壊するため、
            // 編集不可にして commit させない（開いて閉じただけで healFlat に化けるのを防ぐ）。
            appendUneditableNotice(children)
        else {
            let er = effectRuleMap(record);
            let hasRule = not Map.isEmpty(er);
            let commitRule = mkCommit(List.append(basePath, "effectRule" :: Nil));

            // 効果を設定するか（OFF なら effectRule を持たず、効果なしのアイテムになる）。
            let enableChk = new CheckBox("この効果を設定する");
            enableChk.setSelected(hasRule);

            // 各 widget を手動生成（listener は recompute 定義後に付ける）。
            let whenCombo = mkCombo(whenOpts(), erStr(er, "when", "onUse"));
            let toCombo   = mkCombo(toOpts(),   erStr(er, "to", "self"));
            let opCombo   = mkCombo(opOpts(),   erStr(er, "op", "healFlat"));
            let forCombo  = mkCombo(forOpts(),  erStr(er, "for", "instant"));
            let sfxCombo  = mkCombo(sfxOpts(),  erStr(er, "sfx", ""));
            let vfxCombo  = mkCombo(vfxOpts(),  erStr(er, "vfx", ""));
            let amountSpinner = mkSpinner(erInt(er, "amount", 10));
            let forTurnsSpinner = mkSpinner(erInt(er, "forTurns", 3));
            let chanceSpinner = mkChanceSpinner(erInt(er, "chance", 100));
            let kindCombo = mkCombo(kindOpts(), flowKindOf(er));

            let initText = if (hasRule)
                sentenceOf(flowKindOf(er), erStr(er, "when", "onUse"), erStr(er, "to", "self"),
                           erStr(er, "op", "healFlat"), erInt(er, "amount", 10), erStr(er, "for", "instant"),
                           erInt(er, "forTurns", 3), erStr(er, "sfx", ""), erStr(er, "vfx", ""),
                           erInt(er, "chance", 100))
                else "（効果なし）";
            let preview = new Label(initText);
            preview.setWrapText(true);
            preview.setStyle("-fx-text-fill: #1a6e1a; -fx-font-weight: bold;");

            // チェックの ON/OFF で各 widget の有効/無効を切り替える。
            let setEnabled = en -> {
                whenCombo.setDisable(not en); toCombo.setDisable(not en); opCombo.setDisable(not en);
                forCombo.setDisable(not en); sfxCombo.setDisable(not en); vfxCombo.setDisable(not en);
                amountSpinner.setDisable(not en); forTurnsSpinner.setDisable(not en);
                chanceSpinner.setDisable(not en); kindCombo.setDisable(not en)
            };
            setEnabled(hasRule);

            // 全選択を読んで effectRule(+演出) JSON を組み立て、effectRule + description を保存。
            // OFF のときは effectRule を null にして「効果なし」にする。
            let recompute = () -> {
                let on = enableChk.isSelected();
                setEnabled(on);
                if (on) {
                    let w   = valueOf(whenCombo.getValue(), whenOpts());
                    let t   = valueOf(toCombo.getValue(), toOpts());
                    let o   = valueOf(opCombo.getValue(), opOpts());
                    let f   = valueOf(forCombo.getValue(), forOpts());
                    let sfx = valueOf(sfxCombo.getValue(), sfxOpts());
                    let vfx = valueOf(vfxCombo.getValue(), vfxOpts());
                    let a   = amountSpinner.getValue().intValue();
                    let ft  = forTurnsSpinner.getValue().intValue();
                    let c   = chanceSpinner.getValue().intValue();
                    let k   = valueOf(kindCombo.getValue(), kindOpts());
                    let ruleJson = Json.JObject(Map#{
                        "when" => Json.JString(w),
                        "to" => Json.JString(t),
                        "op" => Json.JString(o),
                        "amount" => NodeInspector.intToJson(a),
                        "for" => Json.JString(f),
                        "forTurns" => NodeInspector.intToJson(ft),
                        "chance" => NodeInspector.intToJson(c),
                        "kind" => Json.JString(k),
                        "sfx" => Json.JString(sfx),
                        "vfx" => Json.JString(vfx)
                    });
                    let sentence = sentenceOf(k, w, t, o, a, f, ft, sfx, vfx, c);
                    // description（フレーバーテキスト）は上書きしない。effectRule だけ保存し、
                    // 効果文は表示側が effectRule から自動生成する。
                    commitRule(ruleJson);
                    preview.setText(sentence)
                } else {
                    commitRule(Json.JNull);
                    preview.setText("（効果なし）")
                }
            };

            attachCheckbox(enableChk, recompute);
            attachCombo(kindCombo, recompute);
            attachCombo(whenCombo, recompute);
            attachCombo(toCombo, recompute);
            attachCombo(opCombo, recompute);
            attachCombo(forCombo, recompute);
            attachCombo(sfxCombo, recompute);
            attachCombo(vfxCombo, recompute);
            attachSpinner(amountSpinner, recompute);
            attachSpinner(forTurnsSpinner, recompute);
            attachSpinner(chanceSpinner, recompute);

            PropertyWidgets.addPropertyRow(children, "効果:", checked_cast(enableChk));
            PropertyWidgets.addPropertyRow(children, "▼ 効果（プレビュー）", checked_cast(preview));
            PropertyWidgets.addPropertyRow(children, "効果の種類:", checked_cast(kindCombo));
            PropertyWidgets.addPropertyRow(children, "いつ:", checked_cast(whenCombo));
            PropertyWidgets.addPropertyRow(children, "誰に:", checked_cast(toCombo));
            PropertyWidgets.addPropertyRow(children, "何を:", checked_cast(opCombo));
            // do=発火確率 / replaceAttack=差し替え確率 で意味が違うため中立ラベル。
            PropertyWidgets.addPropertyRow(children, "確率(%):", checked_cast(chanceSpinner));
            PropertyWidgets.addPropertyRow(children, "量:", checked_cast(amountSpinner));
            PropertyWidgets.addPropertyRow(children, "継続:", checked_cast(forCombo));
            PropertyWidgets.addPropertyRow(children, "ターン数:", checked_cast(forTurnsSpinner));
            PropertyWidgets.addPropertyRow(children, "効果音:", checked_cast(sfxCombo));
            PropertyWidgets.addPropertyRow(children, "エフェクト:", checked_cast(vfxCombo))
        }

    /// 完全form（flow/if 入り手書き JSON）のときの編集不可表示。commit は一切させない。
    def appendUneditableNotice(children: ObservableList[Node]): Unit \ IO =
        let lbl = new Label("このルールは高度な形式（flow/条件付き）のため、ここでは編集できません。JSON を直接編集してください。");
        lbl.setWrapText(true);
        lbl.setStyle("-fx-text-fill: #999999;");
        PropertyWidgets.addPropertyRow(children, "効果:", checked_cast(lbl))

    // ── widget 生成 ────────────────────────────────────────
    def mkCombo(opts: List[(String, String)], currentValue: String): ComboBox[String] \ IO = {
        let combo: ComboBox[String] = new ComboBox();
        let items = combo.getItems();
        List.forEach(lbl -> discard items.add(lbl), labelsOf(opts));
        combo.setValue(labelOf(currentValue, opts));
        combo.setPrefWidth(200.0);
        combo
    }

    def mkSpinner(current: Int32): Spinner[Integer] \ IO = {
        // 負値も許す（さびた指輪 -1、デバフ等）。
        let spinner: Spinner[Integer] = new Spinner(-99i32, 999i32, current);
        spinner.setEditable(true);
        spinner.setPrefWidth(90.0);
        spinner
    }

    // 発動確率（0〜100%）。100=必ず発動。範囲が違うので mkSpinner と別に用意する。
    def mkChanceSpinner(current: Int32): Spinner[Integer] \ IO = {
        let spinner: Spinner[Integer] = new Spinner(0i32, 100i32, current);
        spinner.setEditable(true);
        spinner.setPrefWidth(90.0);
        spinner
    }

    def attachCombo(combo: ComboBox[String], recompute: Unit -> Unit \ IO): Unit \ IO =
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_t: ChangeListener[String], _o: ObservableValue[JObject],
                         _old: String, _new: String): Unit \ IO = recompute()
        })

    def attachSpinner(spinner: Spinner[Integer], recompute: Unit -> Unit \ IO): Unit \ IO =
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_t: ChangeListener[Integer], _o: ObservableValue[JObject],
                         _old: Integer, _new: Integer): Unit \ IO = recompute()
        })

    def attachCheckbox(chk: CheckBox, recompute: Unit -> Unit \ IO): Unit \ IO =
        chk.selectedProperty().addListener(new ChangeListener[Boolean] {
            def changed(_t: ChangeListener[Boolean], _o: ObservableValue[JObject],
                         _old: Boolean, _new: Boolean): Unit \ IO = recompute()
        })

    // ── 日本語1文の組み立て ─────────────────────────────────
    /// kind で文を出し分ける。do=通常効果、replaceAttack=攻撃差し替え。
    def sentenceOf(kind: String, whenV: String, toV: String, opV: String, amt: Int32,
                   forV: String, forTurns: Int32, sfx: String, vfx: String, chance: Int32): String =
        match kind {
            case "replaceAttack" => replaceSentence(whenV, toV, opV, amt, chance)
            case _               => doSentence(whenV, toV, opV, amt, forV, forTurns, sfx, vfx, chance)
        }

    /// 通常効果の1文。chance<100 なら確率を前置。
    def doSentence(whenV: String, toV: String, opV: String, amt: Int32,
                   forV: String, forTurns: Int32, sfx: String, vfx: String, chance: Int32): String =
        let whenJa = labelOf(whenV, whenOpts());
        let toJa = labelOf(toV, toOpts());
        let chanceJa = if (chance < 100) "${chance}% の確率で、" else "";
        "${whenJa}、${chanceJa}${opClause(opV, toJa, amt)}${forSuffix(forV, forTurns)}。${fxSuffix(sfx, vfx)}"

    /// 攻撃差し替えの1文（隣接条件と差し替え確率を明示）。
    def replaceSentence(whenV: String, toV: String, opV: String, amt: Int32, chance: Int32): String =
        let whenJa = labelOf(whenV, whenOpts());
        let toJa = labelOf(toV, toOpts());
        "${whenJa}、隣接していると ${chance}% で攻撃の代わりに ${opClause(opV, toJa, amt)}。"

    /// 演出（エフェクト／効果音）の注記。両方なしなら空。
    def fxSuffix(sfx: String, vfx: String): String =
        let vfxPart = if (vfx == "") Nil else labelOf(vfx, vfxOpts()) :: Nil;
        let sfxPart = if (sfx == "") Nil else labelOf(sfx, sfxOpts()) :: Nil;
        let parts = List.append(vfxPart, sfxPart);
        if (List.isEmpty(parts)) "" else "（演出: ${String.intercalate("＋", parts)}）"

    def opClause(op: String, toJa: String, amt: Int32): String = match op {
        case "healFlat"     => "${toJa}の HP を ${amt} 回復する"
        case "healFull"     => "${toJa}の HP を全回復する"
        case "damageFlat"   => "${toJa}に ${amt} の固定ダメージを与える"
        case "atkUp"        => "${toJa}の攻撃力を ${amt} 上げる"
        case "spdUp"        => "${toJa}の速さを ${amt} 上げる"
        case "spdDown"      => "${toJa}の速さを ${amt} 下げる"
        case "defUp"        => "${toJa}の守備を ${amt} 上げる"
        case "defDown"      => "${toJa}の守備を ${amt} 下げる"
        case "hitDown"      => "${toJa}の命中を ${amt}% 下げる"
        case "immobilize"   => "${toJa}を 完全に動けなくする（攻撃を受けると解除）"
        case "maxHpUp"      => "${toJa}の 最大 HP を ${amt} 上げる"
        case "reviveCharge" => "${toJa}を 全回復してよみがえらせる"
        case "lifesteal"    => "${toJa}は 与えたダメージの ${amt}% を回復する"
        case "swapPos"      => "${toJa}と 位置を入れ替える"
        case "knockback"    => "${toJa}を 押し流す"
        case "warpToStairs" => "${toJa}を 止めて 階段マスへ飛ばす"
        case "dropItem"     => "${toJa}に アイテムを落とさせる"
        case "ringify"      => "${toJa}の 持ち物を指輪に変える"
        case _              => "${toJa}に 効果を与える"
    }

    def forSuffix(forV: String, forTurns: Int32): String = match forV {
        case "turns"         => "（${forTurns} ターン）"
        case "permanent"     => "（永続）"
        case "whileEquipped" => "（装備中ずっと）"
        case "untilHit"      => "（攻撃を受けるまで）"
        case _               => ""
    }

    def fst(p: (a, b)): a = let (x, _) = p; x
    def snd(p: (a, b)): b = let (_, y) = p; y
}
