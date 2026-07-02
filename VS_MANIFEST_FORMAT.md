<!-- VS マニフェスト形式 設計検討（2026-06-30）。fe_rogue から逆算せず engine survey＋フォーマット理論で汎用検討。
GENERIC_SIM_DEBUGGER.md / VISUAL_SCRIPTING_TIER1.md と対。:NNN は調査時点スナップショット。 -->

# ビジュアルスクリプティング マニフェスト形式 設計検討 v4

> 種別: 研究＋設計（プラン文書）。コードは書かない。
> 方針: 実ゲームエンジンの実態 survey ＋ フォーマット理論で**汎用的に**検討する。`fe_rogue` の現状から結論を逆算しない。`engine`/`engine_ecs`/`ide` の既存直列化（Persistence・EcsCodec・JsonCodec・SceneLoader・SceneSerializer）は「この engine に既にある足場」として Read 済み、事実として参照する。
> engine 事実の根拠行は本文中に `path:def` で示す（v4 で全件 Read 再裏取り済み）。実エンジンの主張は末尾 Sources の一次/二次資料に紐づく。
>
> **読者への労力配分の前置き（v4・depth allocation の正直化）**: 本文書で最も精緻な分析（§3.3 の EDN/Dhall vs JSON+Schema のカタログ「正本」比較・76 vs 64）は、**案 Y（手書きカタログ正本）に倒した世界でのみ効く**。だが案 Y は §6.1 のトリガ（手書き entry 50 件超 等）に gate され、その手書き需要は §0.1 の発火条件が「当面起きない」としている。**ゆえに load-bearing な推奨（案 X＝コード正本＋JSON export）は、本文書で最も豪華な分析にほぼ依存しない**。読者は §6.1 の推奨だけ要れば実装に着手でき、§3.3 の正本ロール採点は「将来手書きに倒すなら EDN/Dhall」という保険の精密化として読めばよい。
>
> **v4 改訂点（3 巡目レビュー全反映）**:
> - **survey 訂正（事実反転の修正）**: Unity の text YAML を「Force Text は opt-in」から「**近年は Force Text が既定**（歴史的に Force Binary→Force Text へ変更）／Force Binary・Mixed も選べる／`LightingData.asset`・NavMesh データ等はモード非依存で**常にバイナリ**」へ訂正（§2.2・survey 表・§1.3）。Flecs の `ecs_type_info_to_json` の過剰ヘッジを解消し「**reflection データが無い型には `"0"` を返す**」と公式 json addon ドキュメントに基づき断定（§2.6）。
> - **§6.5 typechecker の健全性穴を修正（format-rigor blocking）**: union ポートの単一化を「候補のいずれかが unify すれば成功」とした v3 は **Robinson unification ではなく不健全（順序依存・複数解）**。これを (a) **コア単一化は rank-1 HM（TCon/TVar のみ）に限定＝健全・決定的**、(b) **union/overload ポートは単一化から分離した決定的 overload-resolution パス（一意解のみ accept、多義は reject）** に再設計。あわせて **D-moot 論を条件付きに後退**: 「外部 checker が型整合を担保するから D は moot」は**単相＋rank-1 let 多相＋一意 overload に限り成立**し、**真の union 部分型/rank-N 多相が要求されたら D-moot は崩れ IDL(D=5)/EDN が優位を取り戻す**と明記（§1.1・§3.0・§3.3・§6.5・§7.4）。
> - **採点の尺度を正直化（format-rigor）**: 1–5 rubric × 1/2/3 重みの積和は**序数×序数**ゆえ、76/68/64… の基数差に量的意味を負わせない。総合点を「**順位の頑健性チェック**」に格下げし基数差を語らない方針を明記（§3.3）。**軸 I（既存足場整合＝移行コスト）を外した intrinsic-only ランキングを併記**し、EDN/Dhall の純粋優位と JSON の運用優位を無偏に切り分け（§3.3）。
> - **候補集合の欠落を補充**: **CUE**（unification/constraint で schema と data を統一＝§6.5 テーマに最近接）をカタログ正本ロールの対抗馬として、**RON**（Rust binding 路線）、**protobuf `Any`/`google.protobuf.Struct`**（d4 の JSON 代替）を 1 行 pin（§3.3・§6.5）。**d4 を手組みする規約層コスト**ゆえ JSON+Schema の**実効 D は採点の 3 より低い**旨を採点側に注記（§3.0・§5）。
> - **nonmanifest の transport 過大評価を修正（blocking）**: §0 に**サーバ基盤は存在しない**（grep 確認済み）。`Persistence.save` は `Fs.FileWrite` のみ。共有できるのは `Saveable.toJson`（pure 値→Json）**だけ**。§6.2 の「単一機構」は「**値直列化だけ等価・transport 非等価**」へ格下げし、「(b) ライブ同期(HTTP)」は **§0 に無いサーバ新設が前提**と明記（§4.3・§6.2・§7.7）。Flecs 等価も transport 非等価に限定。
> - **案 X の (2b) correctness ホールを §6.1 へ格上げ（blocking）**: 「手書き registry のポート型がノード実装の実入出力とずれ、CI 再生成 diff では捕まらない」緩和策（**ノード実装↔registry 整合テスト**）を、案 X 採用パッケージの**必須構成要素**として §6.1 に格上げ（§7.2b と接続）。
> - **§4.3 を LSP 風 capability endpoint として first-class 展開**（reflection 不能を補う最自然な適合）。**自己記述グラフ(§4.5)を (2a) 鮮度緩和オプションとして §6/§7 に接続**。**export ロールに ±1 感度分析を実施**し、決定が数値の僅差で駆動されないことを明示（§3.3）。

---

## 0. この engine の足場（Read 済みの事実・v4 再裏取り）

設計の前提として、この engine が「マニフェスト＋グラフ」をどう扱える素地を持つかを確定する。推測ではなく Read した実態である。

- **永続化の最小契約は「Json 双方向変換できればディスクに書ける」**。`Saveable[a]` trait は `toJson: a -> Util.Json.Json`（全域・失敗なし）／`fromJson: Util.Json.Json -> Option[a]` だけを要求し、I/O とエンコーディングを完全分離する（`engine/src/Persistence.flix:16-25`）。`Persistence.save` は `Saveable.toJson` → `Util.Json.toPrettyString(2, …)` で **pretty JSON** を作り、**`Fs.WriteFile.write({str=pretty}, path)` で path に書く**（効果は `\ Fs.FileWrite`、`:33-42`）。`Persistence.load` は `Fs.ReadFile.read`→`JsonCompat.parse`→`Saveable.fromJson` で復元（`:46-54`）。trait に default は置かず**実装側が手で書く**前提（`:14`）。**この trait は「メモリ上の値 → JSON ファイル」を codegen ツール無しに行える**点が後述 §4.4/§6.1 で load-bearing。
   - **重要な限定（v4・nonmanifest blocking の根拠）**: `save` が持つ効果は **`Fs.FileWrite`（ファイルへの書き込み）だけ**である。**HTTP/REST/socket/IPC サーバのモジュールは `engine/`・`engine_ecs/`・`ide/` のどこにも存在しない**（grep で確認）。すなわち「値→JSON」は再利用できるが「**JSON を別プロセスへ配る transport**」は**この engine に未実装**。この事実が §4.3/§6.2 の「ライブ内省」評価を強く制約する。
- **decode は完全 pure（`Json -> Option[T]`）、encode の数値変換だけ `unsafe IO` で BigDecimal 化して pure シグネチャに戻す**（`engine/src/JsonCodec.flix`、`expectObject/expectString/expectInt/expectFloat/expectBool` は `:22-56`、`floatToBd/intToBd` の `unsafe IO {}` 隠蔽は `:65-77`、`encodeList`(`:113`)/`decodeList`(`:117`、要素 1 つでも失敗なら全体 None）は `:113-128`）。「Json 値 ↔ 型付き値」「List ↔ JSON 配列」の往復ヘルパは既に揃っている（ファイルは全 **164 行**）。
- **ECS World は不変値ゆえ直列化が本質的に楽**。`EcsCodec.encodeStore/decodeStore` が component store を `[{id, v}]` JSON 配列に往復する（`engine_ecs/src/EcsCodec.flix:14-32`、全 51 行）。1 要素でも decode 失敗なら全体 None（全か無か）。**任意の「ID 付き値の集合 → JSON 配列」はこの 1 パターンで書ける**——後述するグラフ＝ID 参照ノード集合に直結。
- **SceneLoader は「engine が知る構造ノード型」と「game が知る不透明タグ」を分離している**。`"type"` 文字列を engine 内蔵のビルダー群（`CanvasLayer/Sprite2D/Area2D/…` 計 **21 種**）にディスパッチし（`buildPureNodeType`, `SceneLoader.flix:347-374`）、`"tag"` 文字列は game が渡す `tagParser` で game 固有型へ変換する（`parseTagField`, `:399-404`）。**engine はタグの中身を知らない**（`:7-8` の明示コメント）。**`buildByType`/`buildPureNodeType` は `tagParser` を 21 builder 全てに引き回す**（`:340-374`、21 の `parseTagField` 呼び出し点を確認）——この構造は §6.4 の churn 見積りで効く。
- **現機構は「文字列 TypeTag」止まりで「構造化 opaque payload」は未実装**。`parseTagField` の実シグネチャは `tagParser: Option[String] -> Result[Util.Json.JsonError, t]`（`:399-404`）。すなわち運べるのは「`"tag"` キーの単一文字列（無ければ `None`）」だけで、**ノード固有のネスト JSON payload（例: `SpawnUnit` の `unitKind` ＋ `schemaRef`）は運べない**。後述 §3 の型要件 d4（構造化 opaque payload）は**この engine では未実装で、新規の構造化 payload デコーダ（`Json -> Result[JsonError, payload]` を game が供給）が必要**。
- **エディタは「別プロセス・同言語(JVM 上の Flix)」で、scene.json をフルシリアライズせず再パース＋当該フィールドだけ書き戻す**。`SceneSerializer` は「全 Scene を JSON 化し直すのではなく、ファイルから再パースし NodePath を辿って該当フィールドだけ書き換えて書き戻す」方針（`ide/src/SceneSerializer.flix`、全 494 行）。HotReload watcher が変更を拾い次フレーム再構築。
- **IDE は engine に依存する単独プロジェクト**（`ide/flix.toml`: `name = "flix_game_engine_ide"`、`flix = "0.73.0"`、`dependencies` に `github:ababup1192/flix_game_engine`）。「**per-project 拡張ではなく、engine 型（SceneLoader/Scene/GameEngine）に依存する汎用 standalone IDE**」。同言語(Flix)・別プロセスで稼働する。
- **Flix は静的型・ADT・trait dispatch で、runtime reflection（RTTI）を持たない**。導出は組込 trait（`Eq/Order/ToString/Hash/Sendable` 等）に限られ、**ユーザー定義 derivation・マクロ・コンパイラプラグインは無い**。「リフレクション自動発見」がこの engine で**原理的に使えない**根拠はここ。

この足場から導かれる中立な観察: **この engine の現実装は「カタログ＝コード（builder/tagParser）」「インスタンス＝pretty JSON」というハイブリッドを既に採用している**。さらに **`Saveable`/`EcsCodec` により「メモリ上の任意の値 → JSON ファイル」は既に可能**だが、**それを別プロセスへ配る transport は無い**（ファイル経由のみ）。マニフェスト形式の再検討は「ゼロからの選定」ではなく「この分担を visual scripting に拡張するとき何が最適か、かつ既存の値→JSON 直列化（ファイル出力まで）をどこまで再利用できるか」である。

## 0.1 そもそも着手すべきか（発火条件）

研究方針として `fe_rogue` の現状から逆算しないが、決定文書としては「いつ本実装に着手するか」の発火条件を置く（さもなくば全設計が宙に浮く）。**以下のいずれかが満たされるまで本実装に着手しない**:

- **(F1)** 非プログラマ（デザイナ/プランナ）がゲームロジックそのものを組む必要が出る（＝コード編集の代替としての visual scripting 需要が顕在化）。
- **(F2)** `scene.json` 手編集 or 既存 `XxxScene.flix` でのロジック記述が、分岐/イベント配線の規模で限界に達する（条件分岐ノードを「線で繋ぐ」要求が出る）。
- **(F3)** 複数プロジェクト/別言語エディタからロジック定義を共有する要件が出る（§6.3 のクロス言語接点が必要になる）。

いずれも未発火なら、本文書は「発火時に即着手できる設計の凍結」に留め、足場（§0）の再利用方針だけ確定しておく。**前置きで述べた通り、§3.3 の手書き正本ロール精密採点が実体化するのは主に (F1) 発火後**であり、未発火下の load-bearing 推奨は案 X＋JSON export に集約される。

---

## 1. 問題の再フレーム（深い洞察）

### 1.1 グラフは AST／プログラムである

ビジュアルスクリプティングの「ノードグラフ」は、見た目はボックスと線だが、**意味論的には型付き式木（typed AST）＋データフロー/制御フローのグラフ**である。ノード＝演算子適用、ポート＝型付き引数/結果、エッジ＝束縛（let/データ依存）。したがって「マニフェスト形式をどう選ぶか」は、実体としては次の二問に分解される。

1. **型カタログ（ノード定義集合）をどう直列化するか** = 言語の「標準ライブラリ署名＋型クラス」を書き下す問題。
2. **型付き AST（グラフインスタンス）をどう直列化するか** = プログラムの構文木を書き下す問題。

この再フレームから、各形式は次の「地図」に並ぶ:

| 形式族 | AST に対する立ち位置 |
|---|---|
| **S 式 / EDN（homoiconic）** | コード＝データ。**木としての** AST をそのまま書ける。最も自然。 |
| **スキーマ IDL（FlatBuffers/Cap'n Proto/protobuf）** | 型を**強制**する。スキーマ＝型契約＝カタログそのもの。 |
| **JSON** | 構造の**最小公倍数**。AST を「ad-hoc な object のネスト」で**模倣**する（タグ付き union を手で約束する）。 |
| **typed config-as-language（Dhall/CUE）** | **型付き・全域・import 可**の設定言語。CUE は値と型を unification で統一（§6.5 テーマに最近接）。 |
| **document-tree DSL（KDL）** | ノード＝文書木。「グラフは node tree」再フレームに構文が直対応。 |
| **ホスト言語（Flix）** | AST を**ネイティブ ADT**で持つ。直列化せず値として扱える（同プロセス時）。 |

「JSON が最適か」という当初の問いは、この地図上では「**最小公倍数で AST を模倣するコストは、homoiconic/IDL/typed-config の表現力・型強制と引き合うか**」に翻訳される。

**重要な限定 1（共有参照）**: homoiconic 形式が「そのまま書ける」のは **木**であって、**複数エッジが 1 ノードに合流する共有参照グラフ（DAG）ではない**。共有参照は EDN でも JSON でも結局 **ID 参照規約**（§2.2 Unity の教訓）を要する。したがって「AST だから s 式が自然」は**カタログ（木構造の型定義）で強く効き、グラフ（共有参照 DAG）では効果が薄れる**。この非対称は §3 の採点でロール別に扱う。

**重要な限定 2（多相と型保証の限界・v4 で明確化）**: AST である以上、ジェネリックノード（例: `Identity: T -> T`、`Branch: (Bool, T, T) -> T`）と和型ポート（例: 数値ポートが `Int|Float`）は**ほぼ確実に要る**。だが「どの直列化形式も形式単体ではエッジ型互換を保証しない」ため検証は外部 typechecker に委ねる——**そしてその外部 typechecker でさえ、union ポートの一般的な部分型単一化は決定性・健全性を保証できない**（§6.5）。ゆえに後述の D-moot 論（グラフ層で型表現力差が消える）は**単相＋rank-1 let 多相＋一意 overload の範囲に限って成立し、真の union 部分型/rank-N 多相が要求されると崩れる**。この限界は §3.0/§3.3 の採点土台にも波及するため、最初に宣言しておく。

### 1.2 カタログ（manifest）とグラフ（instance）は要件が異なる＝別形式でよい

両者を 1 形式に縛る理由はない。要件が直交する（この表が §3.3 の重み導出の根拠になる）:

| 軸 | カタログ（ノード定義） | グラフ（インスタンス） |
|---|---|---|
| 主な書き手 | 人間（エンジン/プラグイン作者）or 生成 | ツール（エディタが生成） |
| 主な読み手 | 人間＋エディタ＋codegen | ランタイム＋エディタ |
| 規模 | 数十〜数百エントリ・低頻度更新 | 数百〜数万ノード・高頻度更新 |
| 最重要 | 型表現力・可読性・diff・バージョニング | ロード性能・ツール生成容易・diff |
| 手書き頻度 | 中〜高（**正本が手書きの場合**） | 低（生成物） |
| 構造 | 主に**木**（定義の集合） | 主に**共有参照 DAG** |

結論の方向性（§6 で確定）: **カタログは「読む/diff/型リッチ」に最適な形式、グラフは「生成/大規模/ロード」に最適な形式を、別々に選んでよい**。両者を同一にする要請があるのは「homoiconic で統一して reader を 1 つに」したい場合のみ。

**カタログ内部の二分（前面化）**: カタログには更に「**正本（source of truth）**」と「**export（派生・生成物）**」の二層がある。手書き優位（コメント・diff・簡潔さ）が効くのは**正本が手書きのとき**だけで、**正本がコードで export が生成物**なら手書き優位は moot になる（§6.1 案 X／§3.3 で数値化）。この区別を曖昧にすると「カタログは EDN が上」という主張が推奨と矛盾する（§3.3・§5 で解消）。

### 1.3 「同プロセス editor か別 editor か」が形式を二分する

これが最上位の分岐である。

- **同プロセス／同言語 editor**（エディタがゲーム/エンジンを埋め込む。Unreal/Unity 型）→ カタログは**ファイルである必要がない**。reflection もしくは in-binary registry を直接読める。manifest は内部表現の export か、まったく不要。
- **別 editor／別言語**（汎用 IDE・Web エディタ・別プロジェクト）→ カタログを**外部に出さねば**エディタは型を知り得ない。export 必須＝JSON/EDN/IDL のいずれか。

**「同プロセスなのにスキーマを出す」例は 1 つではない（非過大化）**: Godot は同プロセス（エディタが ClassDB を直接読む）なのに `extension_api.json` を出力するが、**その宛先は Godot 自身のエディタではなく別言語バインディング（C#/Rust/…）**。同様の隣接例として **Flecs は同一バイナリの reflection を REST で別プロセスの Explorer へ export**（§2.6）、**Blender は同プロセスだが `.blend` に SDNA スキーマを埋め込む（自己記述）**（§2.7）。3 例とも「同プロセス editor は**自分用の**カタログファイルを要しない／**別言語・別プロセス・将来再現の消費者**がいるならスキーマを外部化/同梱する」という §1.3 の二分を**保つ**（破らない）。

**「同プロセス＝バイナリも残る」具体補強（v4）**: Unity は近年 **Force Text が既定**だが、**`LightingData.asset`・NavMesh ベイク結果など一部資産はシリアライズモードに関わらず常にバイナリ**である。これは「同プロセス editor でもバイナリは残り得る」という二分の補強具体例で、「同プロセス＝必ずテキスト/必ずバイナリ」のどちらでもないことを示す。

この engine は **§0 の通り「別プロセス・同言語(JVM 上の Flix)」という中間**にいる。同言語ゆえ「IDE がゲームの registry module を**コンパイル時ソース依存**する」道があり（runtime 値共有ではない、§4.2 で訂正）、別プロセスゆえ「実行中の値の受け渡しは結局ファイル/IPC を介す」——**しかも現状その IPC 機構すら無く、ファイル経由のみ**（§0）。この二面性が形式選定の最大の制約になるため §6 で重点的に扱う。

---

## 2. 実エンジン survey（実態の正確な引用）

各エンジンが「ノード/型カタログ」をどう実体化し、グラフをどう保存するかを、reflection か manifest か、テキストかバイナリか、で整理する。

### 2.1 Unreal Engine — UHT reflection ＋ generated code ＋ binary .uasset
- **カタログ＝C++ class に reflection を後付けする codegen**。`UnrealHeaderTool` が `UCLASS()/UPROPERTY()/UFUNCTION()` マクロを解析し、`*.generated.h` / `*.gen.cpp` を生成する。マクロは C++ 側では実質「何もしない（メタデータ）」で、UHT が reflection・serialization の boilerplate を生む。
- **型階層**: UObject 系のメタ型は `UField/UStruct/UClass/UScriptStruct/UFunction/UEnum`。**プロパティは UE 4.25（2020）以降 `UProperty` から `FProperty`（基底 `FField`）へ移行し、もはや `UObject`/`UField` ではない**（`UProperty` は deprecated・「FProperty に改名」警告）。`new` で確保され UObject オーバーヘッドを外した別系統。
- **editor 配置の精密化**: editor は**同プロセス**だが、**カタログ源（C++/UHT が生む reflection）と、Blueprint ビジュアルスクリプティングが走る VM は別言語**である。すなわち「同プロセス・同 reflection 基盤・別言語 VM（Blueprint bytecode）」。Blueprint のノードはこの C++ reflection から自動露出する。**＝「マニフェストを使わない（codegen された in-binary reflection）」型**。
- **グラフ保存＝binary `.uasset`**。**これは UHT 生成の C++ reflection メタデータとは別系統の cooked/binary 表現**で、1 ファイルが両方を運ぶわけではない（reflection メタ＝コードに焼かれる、Blueprint グラフ＝アセットに焼かれる）。diff 不可・手書き不可。
- 教訓: 「**注釈付きホスト言語コード → codegen で reflection**」という双方向 codegen の最大級の実例。カタログは「コードが単一源」。

### 2.2 Unity — 独自シリアライザ ＋ reflection は Inspector/Visual Scripting 層 ＋ YAML/Shader Graph JSON
- **ランタイム直列化**: Unity の runtime シリアライザは**汎用 C# reflection ではなく、独自の「フィールド規則」シリアライザ**（プロパティでなくフィールドを直列化、`[SerializeField]` 等の規則・深さ制限あり）。一方 **Inspector や Visual Scripting（旧 Bolt）のノードライブラリは reflection＋attribute スキャンで型を発見する**。「reflection で型発見」はこの**インスペクタ/ビジュアルスクリプティング層に限った**主張であり、ランタイム直列化機構そのものではない。manifest ファイルは持たない。
- **シーン/プレハブの直列化形式は複数モード（v4 訂正・事実反転を修正）**: Unity はアセット直列化に**バイナリと text YAML の両方**を持つ。**近年は "Asset Serialization = Force Text" が既定**（歴史的には Force Binary が既定だったが Force Text へ変更された）で、**Force Binary・Mixed も選べる**。**さらにモード設定に関わらず常にバイナリな資産が存在する**（`LightingData.asset`、NavMesh ベイク結果等）。**v3 の「Force Text は opt-in」は既定の取り違えで誤り**——正しくは「**近年 Force Text が既定／バイナリ・Mixed も選択可／一部資産はモード非依存で常にバイナリ**」。
- **Shader Graph（ノードグラフの実例）は JSON**。新フォーマットは「**1 ファイルに複数 JSON オブジェクトを格納し相互参照**」。各オブジェクトは基底 `JsonObject` を継承し `objectId`(string) を持つ。参照は所有を表す `JsonData<T>` と非所有の `JsonRef<T>` を使い分ける。**ノードは多態ゆえネスト JSON、かつ「1 ノード＝1 行」**（行単位 diff/マージのため）。
- 教訓: ノードグラフを JSON で本気でやると、**(a) ID による参照グラフ化**（木でなくグラフ）、**(b) 所有/参照の区別**、**(c) diff のための行整形規約**——を自前で足すことになる。素の JSON は AST/グラフを表現しきれず「規約の層」を載せる必要がある、という生きた証拠。**この (a) 共有参照は EDN でも同様に必要**（§1.1 の非対称）。

### 2.3 Godot — ClassDB reflection ＋ extension_api.json（dump）＋ .tscn テキスト
- **カタログ＝`ClassDB`（C++ の reflection レジストリ）**。プラグイン（GDExtension）で登録したクラスはコア型と区別不能になり、エディタのノード追加 UI に自動で並ぶ。
- **`extension_api.json`**: `godot --dump-extension-api` で生成。**ClassDB 登録クラスだけでなく、コア定数・グローバル enum・builtin クラス・グローバル関数まで含む**「Godot の公開 API 全体の dump」。外部言語バインディングがこれから wrapper を生成する。**＝「reflection/内蔵 API を単一源とし、JSON manifest はそこから生成される派生物」**。
- **同プロセスなのに manifest を出す理由**: §1.3 の通り、**宛先は Godot 自身のエディタではなく別言語バインディング**。同プロセス editor 用ではない（Flecs/Blender と並ぶ隣接例）。
- **シーン＝`.tscn` テキストリソース**（`[node ...]` セクション形式・diff/マージ前提）。この engine の `scene.json` が思想的に属する「テキスト資源」陣営。
- 教訓: **manifest（extension_api.json）と reflection（ClassDB）は対立しない**。reflection が source of truth、JSON は「別言語/別ツール向けの export」。この engine が reflection を持てない（Flix）ことが、ここを反転させる（§4.1）。

### 2.4 Node-RED — HTML+JS ペアでノード登録 ＋ flows.json
- **カタログ＝各ノードが `.js`（runtime）＋`.html`（エディタ用メタ＋編集ダイアログ＋ヘルプ）のペア**。**`RED.nodes.registerType(type, …)` は 2 形**: **runtime 側 `.js` ではノードの「コンストラクタ関数」を登録し**、**editor 側 `.html` では `category/defaults/credentials/inputs/outputs` を持つ「definition オブジェクト」を登録する**。`.html` は唯一の登録点ではなく、実行コードは `.js` 側にある。palette はインストール済みノードを npm 経由で管理。
- **グラフ＝`flows.json`**（JSON 配列、ノードと wire の平坦リスト）。
- 教訓: **カタログ（registerType の definition）とグラフ（flows.json）が別形式・別レイヤ**という §1.2 の生例。さらにカタログは「実行コード(.js)とエディタ定義(.html)が別ファイル」＝「カタログは別言語/別形式に分割してよい」も実証。

### 2.5 Max/MSP・PureData — patcher JSON / テキスト
- **Max `.maxpat` は JSON**（`boxes`/`lines` 配列＝ノードと接続）。オブジェクトの種類は文字列（`maxclass`/`text`）で、定義本体はホスト（Max）内の C オブジェクト。**カタログはランタイム内蔵、パッチは JSON**。
- **Pure Data `.pd` は独自テキスト**（`#X obj …;` 行指向）。
- 教訓: 商用ビジュアル DSL でも「グラフ＝テキスト/JSON、ノード定義＝ホスト内蔵」の分離が標準。

### 2.6 Flecs（ECS の live introspection 実例）
- **REST module で実行中アプリを introspection**。JSON/meta addon が**型の reflection スキーマを JSON 化する `ecs_type_info_to_json`**（実在シンボル、`include/flecs/addons/json.h`）、エンティティ→JSON の `ecs_entity_to_json`、クエリ結果→JSON の `ecs_iter_to_json` 等を提供する。Explorer（Web UI）が remote mode で稼働中アプリに接続し、エンティティ/クエリ/性能を閲覧。**コンポーネント値は reflection framework に記述された型しか直列化できない**（公式記述「Component values can only be serialized if described in the reflection framework」）。**reflection データが無い型に対しては `"0"` を返す**（公式 json addon ドキュメント、v4 で過剰ヘッジを解消し断定）。すなわち reflection は meta addon への**手動登録が前提**。
- 教訓: **「静的 manifest ファイルなし・常に実機と同期」**の live 内省プロトコル（§4.3）の実在例。ただし「reflection を手で登録する」コストは C 側にあり、Flix では reflection 自体が無い点が効く。**この engine では `Persistence.save`（§0）の「値→JSON」部分が `ecs_*_to_json` 群に相当する——が、Flecs にある REST transport に相当する機構は無い**（後述 §4.3/§6.2 でこの「値直列化は等価・transport 非等価」が核になる）。

### 2.7 Blender — SDNA self-describing binary（自己記述の実例）
- **`.blend` はバイナリだが「自己記述」**。ファイル末尾近くに **`DNA1` ブロック＝そのファイルが使う全 struct の機械可読スキーマ（Structure DNA / SDNA）**を埋め込む。コンパイル時に `makesdna` がヘッダの struct 定義を解析して SDNA を生成（**codegen の一種**）、保存時にバイナリデータと一緒に SDNA を書き込む。
- **前方/後方互換**: ロード時、ファイルの SDNA と現バイナリの SDNA を突き合わせ、未知フィールドは無視・欠落はデフォルト初期化・version code が逐次変換を適用する。数十年前のファイルも開け、（制限付きで）新しいファイルを古い Blender でも開ける。
- 教訓: **「バイナリ＋スキーマ」でも、スキーマをファイルに同梱すれば自己記述化でき、IDL の前方後方互換（§3 #3）と自己記述グラフ（§4.5）の中間解になる**。ただし依然 **非 diff・非手書き**。§4.5 の本格的実例として利点（再現性・互換）と欠点（バイナリ・定義重複）の両面を示す。

### survey 総括表

| エンジン | カタログの源 | カタログ形式 | グラフ形式 | editor 配置 |
|---|---|---|---|---|
| Unreal | C++＋UHT codegen | in-binary reflection（`FProperty`/`FField`） | binary `.uasset`（reflection とは別系統） | 同プロセス（源=C++/UHT・VM=Blueprint 別言語） |
| Unity | 独自シリアライザ＋（Inspector/Bolt は reflection＋attr） | in-binary reflection | **Force Text が既定の YAML / Binary・Mixed 選択可 / 一部資産は常にバイナリ** / Shader Graph=JSON(ID参照) | 同プロセス/同言語 |
| Godot | ClassDB reflection | **extension_api.json（公開 API 全体の dump）** | `.tscn` テキスト | 同プロセス（export 先は別言語 binding） |
| Node-RED | js(constructor)＋html(definition) ペア | **html/js registerType の 2 形** | `flows.json` | 別プロセス（Web） |
| Max/PD | ホスト内蔵 C obj | 内蔵 | `.maxpat`(JSON)/`.pd`(text) | 同プロセス |
| Flecs | C++ reflection（meta addon に手動登録・未登録は `"0"`） | **REST live JSON（`ecs_type_info_to_json` 等）** | scene/query JSON | 別プロセス（Web Explorer） |
| Blender | C struct＋`makesdna` codegen | **SDNA（`.blend` に同梱・自己記述）** | binary `.blend`（定義同梱） | 同プロセス |
| **この engine** | **Flix builder＋tagParser（手書きコード）** | （現状 manifest 無し・コードが源） | **`scene.json` pretty JSON** | **別プロセス・同言語(JVM/Flix)・transport 無** |

**重要な観察**: 同プロセス系（Unreal/Unity/Godot/Max/Blender）は reflection または内蔵定義でカタログを持ち、外部に出すとしてもそれは**派生 export または自己記述同梱**。別プロセス系（Node-RED/Flecs）はカタログを**明示的に外部化**（html+js/REST）。この engine は「別プロセスだが reflection 不能」という、survey 中で最も manifest を必要とする象限にいる——ただし **`Persistence.save` という「値→JSON（ファイル出力まで）」機構を既に持つ**ため、その manifest を「reflection 無しでも runtime 直列化で出せる」点が他の reflection 不能ケースと異なる。**ただし Flecs のような REST transport は無く、配布はファイル経由のみ**（§4.3）。

---

## 3. 形式比較（評価軸で採点）

### 3.0 各軸の rubric（1–5、5 が良い。再現性のため意味を固定）

- **A. diff/可読性**: 5=行指向で意味的 diff が綺麗・コメント可。3=可読だが冗長/規約依存。1=バイナリで diff 不能。
- **B. パース・ツールコストの低さ**: 5=主要言語に標準 parser・LSP/補完容易。3=parser はあるが追加層/schema が要る。1=専用コンパイラ・生成が必須。
- **C. スキーマ進化・バージョニング**: 5=フィールド番号/SDNA 等で前方後方互換が形式に内在。3=規約で運用可。1=壊れやすい。
- **D. 型表現力（TypeTag＋opaque payload＋多相）**: 5=和型・タグ付き union・型変数・opaque 型名を一級表現。3=文字列タグ＋外部 schema で近似。1=文字列/数値のみ。
- **E. クロス言語**: 5=どの言語にも parser。4=JVM＋主要言語にあるが一部は要追加。1=ホスト言語ロックイン。
- **F. ロード性能**: 5=zero-copy/mmap。3=要 parse だが実用。1=大規模で重い。**※ F は実測ベンチに基づかない armchair 推定。FlatBuffers の mmap zero-copy=5 のみ機構上確度が高く、JSON/EDN/Dhall/protobuf の相対順は推定。再現性を主張する他軸と区別する（§7.10 にリスク明記）。**
- **G. 手書き可否**: 5=人間が快適に手書き（コメント・簡潔）。3=可能だが冗長/規約注意。1=実質不可。**※ G は「正本が手書きのときだけ意味を持つ」軸。生成物ロールでは重み 0（§3.3）。**
- **H. codegen 往復適性**: 5=スキーマ↔コード生成が定石。3=可能だが手当て要。1=困難。
- **I. 既存 scene.json/Persistence 足場との整合**: 5=`Persistence`/`JsonCodec`/`SceneSerializer` をそのまま再利用。3=一部再利用。1=新規経路が必要。**※ I は形式の内在品質ではなく「この engine への移行コスト（switching cost）」。incumbent(JSON) を構造的に持ち上げる軸ゆえ、§3.3 で I を除いた intrinsic-only ランキングを併記する。**

**D について（核心・v4 で限界を明示）**: **どの直列化形式も「グラフのエッジ型互換（`a:Float → b:Float`）」を形式単体では保証しない**。型の正しさは結局**外部 typechecker**（§6.5 で設計）が担う。ゆえに **D の形式差はカタログ層（型定義の表現力）では大きいが、グラフ層では概ね moot**——**ただしこの「moot」は単相＋rank-1 let 多相＋一意 overload の範囲に限る**。§6.5 で示す通り外部 typechecker は**真の union 部分型/rank-N 多相を健全に解けない**ので、そうした強い多相がノード設計に要求されると **D-moot は崩れ、D=5 の IDL/EDN がグラフ層でも優位を取り戻す**。採点はこの条件付き moot を踏まえる。具体要件: **(d1) ノード種 ID、(d2) 入出力ポートの型タグ（`Int/Float/EntityRef/SimEvent/…`＝TypeTag）、(d3) ジェネリック/和型ポート（多相）、(d4) ノード固有の不透明設定 payload（構造化・engine が構造を知らない game 値）**。§0 の通り、この engine の現機構は **d2（文字列タグ）止まり**で、d4 は未実装。

**JSON+Schema の実効 D に関する注（v4・format-rigor improvement）**: 採点表では JSON+Schema を D=3 とするが、**d4（構造化 opaque payload）を JSON で扱うには「game 供給の新規デコーダ ＋ `schemaRef` 規約 ＋ §6.5 の意味検証」の 3 機構に分割実装する**（§6.1-2）。EDN の tagged literal が inline 1 トークンで済ませる所を 3 機構で手組みするコストゆえ、**JSON+Schema の実効 D は採点の 3 よりも実運用上は低い**（規約層の保守コストが乗る）。採点の 3 は「形式＋Schema の到達可能上限」であり、d4 を多用するなら EDN(D=5) との差は数値以上に開く。

### 3.1 形式別サンプル（textual shape が load-bearing なので最小例を併記）

同一カタログ断片「`Add` ノード: 入力 a,b:Float、出力 out:Float」と、構造化 payload を持つ `SpawnUnit` ノード。

**JSON（＋Schema）**
```json
{ "node": "Add", "in": [["a","Float"],["b","Float"]], "out": [["out","Float"]] }
{ "node": "SpawnUnit", "in": [["at","EntityRef"]], "out": [["spawned","EntityRef"]],
  "payload": { "kind": "opaque", "tag": "UnitTag", "schemaRef": "units.schema.json" } }
```
**EDN / s 式**
```clojure
{:node Add  :in [[a Float] [b Float]]  :out [[out Float]]}
{:node SpawnUnit :in [[at EntityRef]] :out [[spawned EntityRef]]
 :payload {:unit-kind #unit/tag "Knight"}}   ; tagged literal = opaque 型を型名付きで持てる
```
**FlatBuffers / Cap'n Proto IDL（スキーマ自体がカタログ）**
```
enum TypeTag : byte { Int, Float, EntityRef, SimEvent }
table Port  { name:string; ty:TypeTag; }
table Node  { kind:string; ins:[Port]; outs:[Port]; payload:[ubyte]; }  // payload=opaque blob
```
**Dhall（型付き config-as-language）**
```dhall
let TypeTag = < Int | Float | EntityRef | SimEvent >
let Port = { name : Text, ty : TypeTag }
let Node = { kind : Text, ins : List Port, outs : List Port }
in  [ { kind = "Add", ins = [...], outs = [...] } ]  -- 型検査・import・コメント可
```
**ホスト言語（Flix）**
```flix
enum TypeTag { case TInt, case TFloat, case TEntityRef, case TSimEvent }
type alias Port = { name = String, ty = TypeTag }
enum NodeDef { case Add(...), case SpawnUnit(...) }   // ADT がカタログそのもの
```

### 3.2 採点表（ロール非依存の素点）

> IDL は性能/diff/codegen 特性が大きく違うため **protobuf** と **Cap'n Proto/FlatBuffers** に分割。`JSON+Schema` を独立行として追加。CUE/RON は §3.3 で 1 行 pin（主表には載せず候補欠落のみ補充）。

| 形式 | A diff | B ツール | C 進化 | D 型 | E 言語横断 | F ロード | G 手書 | H codegen | I 既存整合 |
|---|---|---|---|---|---|---|---|---|---|
| **1 JSON（素）** | 3 | 5 | 3 | **2** | **5** | 3 | 3 | 4 | **5** |
| **1b JSON+Schema** | 3 | 5 | 3 | **3** | **5** | 3 | 3 | 4 | **5** |
| **2 EDN/s式** | **5**¹ | 3² | 4 | **5**¹ | 3² | 3 | **5** | 4 | 2 |
| **3a protobuf** | 3³ | 3 | **5** | **5** | 4 | 3³ | 2 | **5** | 2 |
| **3b Cap'nProto/FlatBuffers** | 1 | 3 | **5** | **5** | 4 | **5** | 1 | **5** | 2 |
| **4 ホスト言語(Flix)** | 4 | 2 | 4 | **5** | **1** | 5 | 4 | 3(源) | 2 |
| **5 Dhall** | 4 | 2 | 4 | **5** | 3 | 2 | 4 | 3 | 2 |
| **6 KDL** | **5** | 3 | 3 | 3 | 3 | 3 | **5** | 3 | 2 |
| **7 TOML/YAML** | 4 | 4 | 3 | 2 | 4 | 3 | 4 | 3 | 3 |

注:
- ¹ **EDN の A=5/D=5 はカタログ（木構造の型定義）に対する評価**。**グラフ（共有参照 DAG）では A≈3・D≈3 に下がる**（複数エッジ→1 ノードは EDN でも ID 参照規約が必要で、JSON と同条件、§1.1/§2.2）。§3.3 のグラフロールでこの調整値を使う。
- ² **EDN の B/E は保守値 3 に据える**。「JVM の `edn-java`/`clojure.edn` を Flix interop で呼べる」を理由に B/E を 4 へ上げる案は**未検証の interop 仮定**: EDN パーサが返すのは **Java/Clojure のオブジェクトグラフ**で、そこから **Flix ADT への手動マーシャリング**が別途要り、mvn/jar の transitive 取り込みと Flix interop の人間工学コストも非自明。**未検証の仮定で結論を動かさない**ため B/E を 3 に据える。プロトタイプで往復が確認できれば B/E→4 に上げてよいが、その効果は「**手書き正本(案 Y)ロールで EDN を更に強める**」だけで、**export 既定（案 X）を JSON+Schema から動かすものではない**（§3.3 感度分析で明示）。
- ³ **protobuf**: zero-copy ではなく parse/decode を要するので F=3（Cap'n Proto/FlatBuffers の mmap zero-copy=5 と区別）。`textproto` を持つため A も 1 ではなく 3。

### 3.3 ロール別重み付き集計（推奨を数値から辿れるようにする）

> **尺度に関する重大な注意（v4・format-rigor）**: 以下の「重み付き合計」は **1–5 の序数 rubric × 1/2/3 の序数重み**の積和であり、**区間尺度ではない**。したがって「76 vs 68 ＝ 差 8」のような**基数差に量的意味を負わせない**。本節の数値は**「順位の頑健性チェック（どの形式が上位 tier か・±1 摂動で順位が入れ替わるか）」としてのみ**用い、最終判断は数値の僅差ではなく散文の運用論（ゼロ新ツールチェーン等）で下す。これを破ると序数の基数化という方法論的誤りに陥る。

採点表が装飾に留まらないよう、§1.2 の要件差を**機械的に**重みへ写す。手順を固定する（再現性）:

> **重み導出規則**: §1.2 の各ロール列で、その軸が「最重要/明示優先」なら high=3、「副次的に関与」なら mid=2、「ほぼ無関係」なら low=1、「該当しない」なら 0。各高重みの根拠 §1.2 行を併記する。

**ロール 1: カタログ正本＝手書き（案 Y）** — §1.2「型リッチ・可読・diff・バージョニング」最重要、手書き中〜高、ロード性能は無関係:
`A3(diff行)・B1(低頻度更新で tooling 副次)・C3(バージョニング行)・D3(型リッチ＝最重要行)・E2(別言語 editor 関与)・F0(ロードはグラフの軸)・G3(手書き中〜高行)・H2(読み手に codegen)・I1(新層)`

**ロール 2: カタログ export＝生成物（案 X、推奨既定）** — 正本はコード、**手書きは moot ゆえ G=0**、消費者は別言語 binding/editor/codegen ゆえ E・I・B が支配、進化は**再生成で吸収されるため C=mid**:
`A2(生成物の diff レビューは副次)・B2(消費側 tooling)・C2(再生成で吸収＝形式内蔵進化は副次)・D3(消費者の型表現＝最重要)・E3(別言語 binding が export の主目的)・F0・G0(生成物ゆえ手書き無関係)・H2・I2(Persistence 足場再利用)`

**ロール 3: グラフ＝生成物** — ロード・ツール・整合が支配、**D は外部検証前提で moot ゆえ低、G=0**:
`A1・B2・C1・D1・E2・F3(ロード最重要行)・G0・H1・I3(scene.json/SceneSerializer 整合最重要行)`

素点 × 重みの合計（EDN は注¹に従いグラフロールで A/D を 3 に調整。**順位読み取り専用**）:

| 候補 | カタログ正本(案Y) | カタログ export(案X・推奨既定) | グラフ |
|---|---|---|---|
| **JSON+Schema** | 64 | **64** | **57** |
| **EDN** | **76** | 60（B/E 昇格時 65） | 41 |
| protobuf | 68 | 63 | 47 |
| Cap'nProto/FlatBuffers | —⁴ | —⁴ | 51 |
| Dhall | 67 | —⁵ | —⁵ |
| KDL | 65 | —⁶ | —⁶ |
| Flix host | 63 | （生成元＝正本ゆえ別軸） | （別プロセスで値共有不可・§4.2） |
| TOML/YAML | 58 | —⁷ | —⁷ |

落選候補の明示（残留選択バイアス回避）:
- ⁴ **Cap'nProto/FlatBuffers** は手書き不可(G=1)ゆえカタログ正本に不適、export も人間/別言語消費の可読性で JSON に劣る。**グラフの出荷最適化層**でのみ採点（F=5 が活きる）。
- ⁵ **Dhall** はカタログ正本では 67 と EDN(76)・protobuf(68) に次ぐが、parser 遍在性(E=3)・ツール(B=2)・ロード(F=2)が弱く **export/グラフ生成には不適**。正本ロールの**有力対抗馬**として残す（§6.1 昇格先候補）。
- ⁶ **KDL** はカタログ正本で 65（A=5/G=5 が効く）だが **EDN/Dhall に型強制で負ける（D=3 < 5）・エコシステム新興(E=3)**。落選。
- ⁷ **TOML/YAML** は正本 58 と下位。深いネスト/和型に弱く(D=2)、YAML はインデント依存で機械生成/diff 不安定。単独採用の積極理由なし。

**候補欠落の補充（v4・format-rigor improvement、1 行 pin）**:
- **CUE**: schema と data を **unification/constraint で統一**する設定言語で、**§6.5 の unification ベース typechecker テーマに Dhall より近い**。カタログ正本ロールの**有力対抗馬**（Dhall と同 tier の D=5 級・制約合成が強い）。ただし parser ユビキティ(E≈3)・JVM interop 未検証は Dhall と同様で、**export/グラフには不適・正本ロール限定**。EDN/Dhall を案 Y で昇格検討する際、CUE も同列の候補に含めること。
- **RON (Rust Object Notation)**: Godot の Rust binding 路線（§2.3）を採る別言語 editor を想定するなら候補だが、**Rust エコシステム外でのユビキティが低く(E≈2)**、この engine（JVM/Flix）からは EDN 同様の interop 未検証コストを負う。**汎用性目標(クロス言語)で JSON に劣る**ため落選、Rust 単一エディタ前提でのみ再検討。
- **protobuf `Any` / `google.protobuf.Struct`**: **d4（構造化 opaque payload）の JSON 代替**。`Any` は型 URL ＋ シリアライズ済み bytes で「engine が構造を知らない payload」を型名付きで運べ、`Struct` は動的 JSON 様データを protobuf に埋める。**d4 を IDL 経路で扱うなら手組みの schemaRef 規約より素直**だが、protobuf 本採用（別コンパイラ・別ビルド）が前提ゆえ、グラフを IDL export する段(§6.1)で初めて意味を持つ。JSON 既定では採らない。

**intrinsic-only ランキング（v4・軸 I を除外して移行コストと内在品質を分離）**: 軸 I は switching cost（incumbent 持ち上げ）ゆえ、**I を集計から外した「形式の内在品質のみ」の順位**を併記する。正本ロール（I の重み 1 ゆえ影響小）では順位ほぼ不変だが、**export ロール（I=2 weight）・グラフロール（I=3 weight）では JSON の見かけ優位が縮む**:
- **export ロール intrinsic-only**: I(=5×2=10) を JSON+Schema から引くと 64→54、protobuf は I(=2×2=4) を引いて 63→59、EDN は 60→56。**intrinsic では protobuf(59)＞EDN(56)＞JSON+Schema(54) と逆転する**。すなわち **JSON の export 優位は「内在品質」ではなく「既存足場再利用＝移行コストの低さ」に由来する**ことが定量的に露出する。
- **グラフロール intrinsic-only**: I(=5×3=15) を引くと JSON+Schema 57→42、FlatBuffers は I(=2×3=6) を引いて 51→45。**intrinsic では FlatBuffers(45)＞JSON+Schema(42)** と逆転。**グラフで JSON を選ぶ理由も内在優位ではなく switching cost＋クロス言語ユビキティ**である。
- **含意**: EDN/Dhall/protobuf/FlatBuffers の**純粋優位**と JSON の**運用優位（足場再利用）**は明確に別物。本推奨が JSON を既定にするのは**後者（運用優位）の意図的選択**であり、「JSON が内在的に最良」とは主張しない——この切り分けを intrinsic-only 併記で無偏に固定する。

**読み取り（中心結論の整合・順位ベース）**:
- **カタログ「正本（手書き案 Y）」ロールでは EDN が上位 tier**（次いで protobuf・Dhall・CUE・KDL・JSON+Schema・Flix）。**手書き正本を採るなら EDN/Dhall/CUE が JSON+Schema より上位**——これは G=3（手書き優位）が効く前提。
- **カタログ「export（生成案 X）」ロールでは JSON+Schema・protobuf・EDN が**僅差の同 tier**で、運用論で JSON+Schema を採る（後述）。ここでは G=0 ゆえ EDN の手書き優位が消え、EDN は正本ロールから大きく沈む（グラフロールで G を 0 にしたのと同一論理）。
- **グラフロールでは JSON+Schema が上位 tier**（Cap'nProto/FlatBuffers が出荷最速 export 層、EDN は整合で沈む）。**ただし intrinsic-only では FlatBuffers が上位**——JSON 既定は switching cost ＋ ユビキティ由来。

**したがって中心結論は自壊しない**: 「カタログは EDN が技術的に上」は**手書き正本ロールに限定された真**であり、**推奨の既定（§6.1 案 X＝正本はコード・export は生成物）では手書き優位が moot になるため、export ロールで JSON+Schema が同 tier 上位を占める**。EDN の優位が実体化するのは**手書き正本(案 Y)に倒したときだけ**。**「scoring の上位(EDN)」と「推奨の既定(JSON+Schema)」はロールが違うだけで矛盾しない**。

**重み感度分析（v4・決定が宿る export ロールにも実施）**:
- **正本ロール（案 Y 世界・決定は宿らない）**: EDN が上位で、JSON+Schema 未満へ逆転させるには I≥4 かつ E≥3 を要し、これは「カタログは integration/load を de-emphasize する」§1.2 に正面から反する。**±1 摂動に robust**だが、前置きの通り**この分岐は §0.1 未発火下では実体化しない**。
- **export ロール（案 X 世界・決定が宿る・v3 で欠けていた感度分析）**: JSON+Schema・protobuf・EDN は**順位が僅差で重なる tier**にあり、**±1 摂動で容易に入れ替わる**。例えば export の C を mid→high（進化を重視）に上げると protobuf(C=5) が JSON+Schema を上回り得る（§7.8 で flag 済み）。intrinsic-only では既に protobuf＞EDN＞JSON+Schema（上記）。**ゆえに export ロールの順位は数値的に robust でなく、ここで数値に決定を負わせてはならない**。**export 既定が JSON+Schema である決め手は順位ではなく運用論**: (i) **ゼロ新ツールチェーン**（§4.4(ii) の `Persistence.save` でそのまま出る・protobuf の別コンパイラも EDN の未検証 interop も不要）、(ii) **クロス言語ユビキティ**(E=5)、(iii) **既存足場再利用**(I=5)。**この 3 点は序数採点の外にある運用事実であり、数値の僅差に依存しない**。EDN の B/E を昇格(→4)しても export は同 tier 内で並ぶだけで、運用論のタイブレークは動かない（昇格の効果は正本ロールに局在）。
- **結論**: **決定が宿る唯一の分岐（export 既定）で、数値は順位を決められない。決定は運用論が下す**——この正直化を v4 で明示する。

**重み出自の明示（reverse-engineering 疑義の封じ）**: 上記重みは全て「§1.2 の該当行 → high/mid/low → 3/2/1」で機械導出した（各高重みに §1.2 行を併記済み）。**結論から逆算した magnitude ではなく、§1.2 の要件差を離散化した結果**である。グラフの D=1 と export の D=3 の差は「グラフは外部検証で D が（条件付きで）moot／カタログは型表現が消費者に直結」という §3.0 の D 論から来る。**ただし high/mid/low の分類自体に判断は残る**（§7.8 に残留リスクとして明記）。

### 3.4 各形式の長所/短所/適性（散文・補足のみ）

**1/1b JSON・JSON+Schema**: ubiquity(E=5)・既存整合(I=5)が圧倒的でグラフ役・export 役で**運用上**勝つ（intrinsic では負ける、§3.3）。だが**素 JSON は AST/TypeTag を「`{"node": …}` タグ規約」で模倣**し validator で縛る層が要る（D=2）。JSON Schema を足しても **D は 3 が上限**（理由は §5 で防御）、かつ **d4 は 3 機構手組みで実効 D はさらに低い**（§3.0 注）。コメント不可はカタログ正本で痛い。

**2 EDN/s 式**: **AST 木をそのまま書け**、tagged literal が opaque 型を「型名付きで」一級表現（正本 D=5・A=5・G=5）。**カタログ正本に最適**だが、**生成 export/グラフでは手書き優位(G)が moot になり JSON に逆転される**。弱点は既存 JSON 足場との整合(I=2) と、JVM interop の未検証コスト（注²）。

**3a protobuf / 3b Cap'n Proto・FlatBuffers**: スキーマ＝型契約（D=5, C=5）。**Cap'n Proto/FlatBuffers は mmap zero-copy でロード最速(F=5)**、**protobuf は parse 要(F=3)・textproto あり(A=3)**。`Any`/`Struct` で d4 を素直に運べる（§3.3 pin）。非手書き・別ビルド経路。**巨大グラフの出荷時最適化層**に後付け適。

**4 ホスト言語(Flix)**: ADT がカタログそのもの（D=5）、型検査器がコンパイル時保証。**別言語クロス壊滅(E=1)**、**別プロセスでは live ADT 値を共有できない**（§4.2）。同言語ケースでは「IDE が registry module をコンパイル時ソース依存」で活きる＝**案 X の正本そのもの**。

**5 Dhall（＋CUE）**: **静的型・全域・import・コメント**を持つ config-as-language で、**「型リッチな手書きカタログ単一源」要件にドンピシャ**（D=5）。**CUE は更に unification/constraint で値と型を統一**し §6.5 テーマに最近接。parser が JSON ほど遍在せず(E=3)・ロード/ツール弱く、**グラフ生成には不向き**。**EDN のライバルとしてカタログ正本ロールの有力対抗馬**。

**6 KDL**: **node/document tree がそのまま構文**で「グラフは node tree」再フレームに直対応・diff/手書き良好（A=5,G=5）。型注釈は限定的(D=3)・エコシステム新興(E=3)。**型強制が EDN/Dhall に劣るため落選**（§3.3 注⁶）。

**7 TOML/YAML**: 補助的。TOML は深いネスト/和型に弱い(D=2)。YAML はアンカーで参照グラフを書けるが**インデント依存で機械生成/diff 不安定**・パーサ差・タグ実体化の歴史的地雷。単独採用の積極理由は薄い（§3.3 注⁷）。

---

## 4. 非マニフェスト／別形アプローチの評価

### 4.1 リフレクション（自動発見）— **Flix では原理的に不可**
Unreal/Unity/Godot のカタログは reflection（実行時または UHT/ClassDB が用意するメタ型）で**自動発見**される。だが **Flix には runtime reflection／RTTI が無く**、ADT のコンストラクタや関数シグネチャを実行時に列挙できない。導出は組込 trait のみで**ユーザー定義 derivation・マクロ・コンパイラプラグインが無い**（§0）。したがって「ノード定義を**ノード実装コードから自動で導出**する」には**コンパイル時の外部処理（ソース解析ツール）**が要る。**この 1 点が、この engine を Unreal/Unity/Godot の reflection 路線から切り離す決定的制約**である。

### 4.2 同プロセス／ホスト言語 registry 直結
**同言語 ≠ 同プロセス**で、§0 の通り IDE は**別プロセス**である。**プロセス境界を越えて live な ADT 値は共有できない**。同言語が与えるのは「**IDE プロジェクトがゲームの registry module を**コンパイル時にソース依存（リンク）できる」ことだけで、**実行中のゲームが構築した値**を IDE プロセスが覗くことではない。
- **同言語の利得**: IDE が registry module（`NodeDef` 定義の集合）をコンパイル時に取り込めば、**カタログを型安全に共有でき、同言語ケースでは codegen JSON すら不要**にできる。ただし「静的な型定義」の共有に限る（動的状態ではない）。
- **別プロセスの制約**: 動的な値を渡すには結局**ファイル/IPC を介す**（§4.4 の runtime 直列化）——**しかも現状 IPC は無く、`Persistence.save` のファイル出力のみ**（§0）。
- **別言語の制約**: Web/VS Code/別言語 IDE からはコードを実行/解析できず、export 経路（§4.4）が要る。

### 4.3 ライブ内省プロトコル（IPC/REST/**LSP 風**）— v4 で first-class 展開
Flecs Explorer 型。**稼働中ゲームへ問い合わせてカタログ/状態を得る＝静的ファイル無し・常に同期**。

**LSP 風 capability endpoint としての位置づけ（v4 新）**: この engine の象限——**別プロセス・同言語・型を知るホスト**——は、まさに **LSP（Language Server Protocol）が想定する「別プロセスの型認識サーバに editor が問い合わせる」形そのもの**である。LSP では language server（型を知る側）が editor の `textDocument/completion`・`hover`・`signatureHelp` に応答する。これを visual scripting に写すと、**ゲーム（型＝registry を知る側）が「利用可能ノード一覧」「ポート型署名」「あるエッジが型整合か」を別プロセスの editor に capability として応答するサーバ**になる。**reflection 不能（§4.1）を、LSP 風 capability endpoint で動的に補う**——これが Flecs-REST と並ぶ、この engine に**最も自然に適合する非マニフェスト候補**である。`signatureHelp`≈ノードのポート署名、`completion`≈配置可能ノード列挙、`diagnostics`≈§6.5 typechecker のエッジ型エラー、と対応が綺麗に付く。

- 利点: カタログとランタイムが**乖離しない**。エディタは言語非依存（プロトコルが JSON-RPC 等なら）。HotReload watcher（§0）と思想が近い。
- **この engine での実体と限界（v4・transport 過大評価の修正）**: 「内省エンドポイントが返す中身」＝「**registry 値を runtime 直列化した JSON**」は **`Persistence.save`／`Saveable.toJson`（§0）で生成可能**で、reflection を必要としない。**しかし `Persistence.save` が持つのは `Fs.FileWrite`（ファイル出力）だけで、HTTP/REST/socket サーバはこの engine に存在しない**（§0、grep 確認済み）。すなわち **Flecs と等価なのは「値直列化」部分のみで、「REST transport」部分は等価でない**。LSP 風/REST 風エンドポイントを実現するには **§0 に無いサーバ基盤を新設する必要がある**（JSON-RPC over stdio／socket／HTTP のいずれか）。これは設計選択肢であって既存足場ではない、と明確に区別する。
- 難点: **(a)** カタログは結局コード内の registry に「手で登録」されている必要がある。**(b)** ゲーム起動前提でオフライン編集/CI/差分レビュー不可。**(c)** ユーザーが描いたグラフの永続化は別途必要。**(d)** transport 基盤が未実装（上記）。
- 適性: **カタログ配信路として有望だが transport 新設が前提**。静的 manifest を置換するのではなく**補完**。サーバ新設まではファイル経由の export（§4.4 (ii)）が現実解。

### 4.4 双方向 codegen — **2 つの別問題に分離せよ**
独立な 2 機構であり、推奨の核は重い方を必要としない。

- **(i) レジストリ自動導出（ノード実装コード → registry entry）**: 「ノードの実装関数/型から、ポート型などのカタログ entry を**自動生成**する」。Flix はマクロ/RTTI/ユーザー derivation を欠くため、**外部ソース解析ツールが要る＝これが真のコストで唯一の重いリスク**（§7.1）。ただし**必須ではない**——registry を**手書き**すれば回避できる。**ただし手書き回避には (2b) のドリフトという別コストが付く（§6.1/§7.2b）**。
- **(ii) レジストリ値の runtime 直列化（registry 値 → カタログ JSON）**: 手書き or 導出済みの `NodeDef` ADT 値を JSON に落とす。**これは §0 の `Saveable`/`Persistence.save`・`EcsCodec.encodeStore` で codegen ツール無しに既に可能**。「稼働中ゲームが registry を `Persistence.save` する」だけでカタログ manifest が**ファイルに**出る（transport は別問題、§4.3）。

**帰結**: **推奨アーキテクチャの核（カタログ manifest 生成）は (ii) だけで成立**し、(i) のコンパイル時 codegen パイプラインは**任意の最適化**。実態のリスクは **(i) を採るかどうか**と、**(i) を採らない場合の (2b) ドリフト**に局在する。

### 4.4b manifest-as-source（反転案）— 対称に評価する
codegen の「方向」を UHT 流（コード→manifest）に固定せず、逆も主要案として並べる。
- **案 X（コード正本）**: registry を Flix コードで持ち、(ii) でカタログ JSON を**生成**（生成物は手編集禁止）。型検査がカタログ整合をコンパイル時保証。**鮮度問題は 2 層（(2a) 生成物 vs registry／(2b) registry vs 実装コード）**を抱える（§6.1/§7.2）。**§3.3 で「カタログ export ロール」を採点したのはこの案**。
- **案 Y（manifest 正本）**: カタログを **EDN/Dhall/CUE で手書きし、それを正本**とする。薄い Flix loader が**ロード時に検証**（型整合は実行時チェックに降格＝コンパイル時保証は失うが、**codegen ツール (i) が一切不要**）。**§3.3 で「カタログ正本ロール」を採点したのはこの案**で、ここでは EDN/Dhall/CUE が JSON+Schema を上回る。
- **トレードオフ**: 案 X は型安全・自動同期だが (i) or 鮮度運用が要る。案 Y は手書きの一次性・diff・コメント・**EDN/Dhall/CUE の型表現**を得るが型保証を実行時に落とす。**この engine では §4.4(ii) が安価ゆえ案 X が既定有利**だが、手書きカタログ比率が上がるなら案 Y（＋EDN/Dhall/CUE）が昇格（§6.1）。

### 4.5 自己記述グラフ（グラフがノード定義を内包）
グラフファイル自身に使用ノードの定義を**同梱**する。別カタログ不要・自己完結・バージョン固定。
- 利点: 単一ファイルで配布・再現可能。**Blender SDNA（§2.7）がバイナリでこれを徹底**（前方後方互換まで実現）、Unity Shader Graph が「1 ファイルに複数 JSON」で部分的に実施。
- **鮮度問題の構造的緩和（v4・(2a) と接続）**: グラフが**オーサリング時点のカタログ snapshot を同梱**すれば、「グラフが想定するノード署名」がファイル内に固定される。これは **§7.2 の (2a)（生成カタログ vs registry のズレ）を構造的に緩和**しうる——グラフは自分が依存した署名を持ち歩くので、後で registry が動いても「このグラフはこの署名で作られた」が自明になり、ロード時に現 registry と snapshot を**差分照合**できる（Blender の SDNA 突き合わせと同型）。既存 JSON スタック上で「`*.graph.json` に使用ノードの署名サブセットを埋める」だけで実装可能。
- 難点: **定義の重複**、更新の伝播困難、ファイル肥大。カタログの「単一源・進化」要件(§1.2)と逆行。
- 適性: **オーサリングの source of truth には不適**だが、**(a) エクスポート/凍結スナップショット、(b) 上記 (2a) 鮮度照合のためのオプション**として §6.1/§7.2 に接続する（採点は §3.3 のロールに独立計上せず、出荷時/照合オプションに留める）。

---

## 5. 「JSON は本当に良いか」の正面評価

当初案 JSON を、贔屓も全否定もせず採点する。

**JSON が本当に良い点（過小評価しない・ただし運用優位と内在優位を区別）**
- **ubiquity(E=5)**: Flix/JS/Python/Rust すべてに parser。汎用性目標に直撃。
- **既存足場との整合(I=5)＝switching cost の低さ**: `Persistence`/`JsonCodec`/`SceneLoader`/`SceneSerializer` が**全部 JSON**。`SceneSerializer` の部分書き戻しを**再利用**できる。**ただしこれは「形式の内在優位」ではなく「この engine での移行コストの低さ」**（§3.3 intrinsic-only で露出）。
- **ツール/LSP/Web(B=5, H=4)**: スキーマ補完・validation・既存エディタ統合が容易。
- **ゼロ新ツールチェーン**: §4.4(ii) の `Persistence.save` でそのまま**ファイルに**出る（protobuf の別コンパイラ・EDN の未検証 interop と対照）。

**JSON が本当に苦手な点（安易に流さない）**
- **AST/グラフ表現が苦手（§1.1/§2.2）**: タグ付き union・参照グラフを object 規約で模倣。Unity Shader Graph が ID 参照・所有/参照・1 行整形を**自前実装した実例**がコスト証拠。**ただしこのコストは共有参照グラフ層の話で、EDN でも同様に発生**（JSON 固有の減点ではない、§1.1）。
- **型が貧弱（D=2、Schema 併用でも 3 が上限）— この上限を防御する**: JSON Schema は素朴な構造制約だけではなく、**`if/then/else`・`dependentSchemas`・`$ref` 合成・`const`/`enum`・`oneOf/anyOf`** といった**条件付き・合成的な表現力**を持つ。これらで「`kind` が `opaque` なら `schemaRef` 必須」程度の**スキーマ内クロスフィールド制約**は書ける。**だが書けないのは「インスタンス間の relational 制約」**——「**エッジ `e` の出力ポート型と入力ポート型が一致する**（しかも型変数の単一化を伴う）」のような、**別ノード・別インスタンスの値同士を突き合わせ、かつ型変数を解く**制約である。JSON Schema の条件式は「**同一ドキュメント内の固定パスのスキーマ分岐**」までで、「**任意 2 ノード間のポート型一致＋単一化**」は表現範囲外。ゆえに **D=3 は「条件式表現力を認めた上での上限」**であり、relational なエッジ型互換は §6.5 の外部 typechecker に委ねるしかない。
- **d4 の手組みコスト（§3.0 注）**: 構造化 opaque payload を「新規デコーダ＋schemaRef 規約＋意味検証」の 3 機構で組むため、**実効 D は 3 より低い**。
- **コメント不可**: 手書きカタログ正本で致命的に不便（案 Y で EDN/Dhall/CUE に負ける主因）。
- **冗長**: 大規模グラフが膨らむ（F は中・armchair、§3.0/§7.10）。

**結論（正面）**: JSON は**グラフ（インスタンス）の interchange/保存形式として運用上妥当**（§3.3 グラフ役上位 tier）、かつ**カタログ export（生成物）としても運用上妥当**（export 役上位 tier）。**だがこの優位は内在品質ではなく switching cost＋ユビキティ由来**で、intrinsic-only では FlatBuffers/protobuf に劣る（§3.3）。**カタログを手書き正本にするなら**「最小公倍数ゆえの妥協」で、§3.3 正本役では JSON+Schema は EDN・protobuf・Dhall・CUE に**順位で劣る**。「JSON だから一択」は §1.2 を無視した安易さであり、正しくは「**グラフと export では（運用優位で）JSON、手書き正本に倒すなら EDN/Dhall/CUE**」——カタログ正本を JSON にする積極理由は無く、JSON が勝つのは生成物ロールでの運用優位に限る、が本検討の核。

---

## 6. 推奨（この engine への適用）

### 6.1 形式の役割分担（推奨アーキテクチャ）

§3.3 の順位と §0 の足場（別プロセス・同言語・reflection 無し・JSON 全面・`Persistence.save` 既存・**transport 無**）から、**3 層ハイブリッド**を推奨する。

1. **カタログ正本＝Flix コード（手書き registry／案 X）**。ノード定義を Flix の ADT/レコードで持つ（§4.2）。型検査器がカタログ整合をコンパイル時保証。**「ノード実装からの自動導出 (i)」は採らず、registry は手書き**——これで §4.4 の重い codegen リスクを回避する。**正本は EDN でも JSON でもなく Flix コードである**（同言語 IDE はこれをコンパイル時ソース依存できる、§6.3）。
   - **【必須構成要素・v4 で格上げ】ノード実装↔registry 整合テスト**: 手書き registry を採る代償として、**(2b) 「手書き registry のポート型がノード実装関数の実入出力とずれ、CI の再生成 diff では捕まらない」correctness ホール**が生じる（§7.2b）。**これは案 X 採用パッケージの必須構成要素として、ノード実装関数のシグネチャと registry entry のポート型を突き合わせる整合テストを同梱する**こと（手書きでよいが、各ノードにつき「実装の入出力＝registry の ins/outs」を assert するテストを 1 本書く運用を強制）。**このテスト無しに案 X を凍結してはならない**——「既定で採る道に既知の検出不能バグ経路がある」状態を放置しないため。可能なら将来 (i) の自動導出で機械化する。
2. **カタログ manifest（export）＝ §4.4(ii) の runtime 直列化で生成する JSON（＋JSON Schema）**。**`Saveable`/`Persistence.save` で registry 値を JSON 化（ファイル出力）するだけ**（外部 codegen 不要）。**JSON を選ぶ理由は §3.3 export ロールの運用優位**——生成物ゆえ手書き優位(G)が moot になり、整合(I=5)・クロス言語(E=5)・ゼロ新ツールチェーンが効く（**順位の僅差ではなく運用論で決める**、§3.3 感度分析）。型表現の貧しさ(D)は JSON Schema で構造を縛り（D=3 上限、relational は §6.5 へ）、TypeTag は enum 文字列、**構造化 opaque payload は `{"kind":"opaque","tag":<TypeTagName>,"schemaRef":<resources/*.schema.json>}` という新規規約**で表す。game 供給の **構造化 payload デコーダ `Json -> Result[JsonError, payload]` を新設**する（§0 の単一文字列 `tagParser` では不足）。
   - **payload 検証の責務分割（自己矛盾解消）**: §5 の通り JSON Schema は relational 制約を表せない。ゆえに **`schemaRef` が担うのは payload の「構造 well-formedness」のみ**（必須キー・型・enum 等）。**payload の意味検証（ポート型との整合・参照先 entity の型など relational なもの）は §6.5 の外部 typechecker に集約**する。
   - **EDN/Dhall/CUE への昇格条件（案 Y へ倒すトリガ）**: カタログを「人間が手書き正本にし頻繁に diff レビューし opaque 型を一級に持ちたい」なら、§3.3 正本ロールで EDN/Dhall/CUE が JSON+Schema を上回る。**ただしこの優位は手書き正本(案 Y)を採る決定とセットでのみ実体化する**（生成 export のままでは G が moot で優位は消える）。具体トリガ: **(a) 手書きカタログ entry が概ね 50 件超**、**(b) カタログ diff レビューが月 4 回超**、**(c) 案 Y（manifest 正本）に倒す決定**——のいずれかで **カタログのみ EDN（型重視なら Dhall、制約 unification 重視なら CUE）へ昇格**。グラフは JSON 据え置き。**EDN/CUE 採用前に注²の JVM interop 往復をプロトタイプ検証する**こと。**前置きの通り、このトリガは §0.1 未発火下では当面起きない**。
3. **グラフインスタンス ＝ JSON（scene.json と同居・`*.graph.json` 別系統）**。`Persistence.save`/`JsonCodec`/`SceneSerializer`/HotReload watcher を**そのまま再利用**（§3.3 グラフ役・運用優位）。**共有参照は ID 参照規約**（§2.2 Unity 流: `objectId` ＋所有/非所有参照）で表し、TypeTag は `"node"` 文字列、構造化 payload は §6.1-2 の新規デコーダで解く。**エッジ型互換は形式では保証されない**ので §6.5 の外部 typechecker を必ず通す。
   - **多相ポート(d3)の最小規約と健全性の限定（v4）**: ポート `ty` に「具体型タグ」だけでなく**型変数 ID**（例 `{"var":"T"}`）と和型（例 `{"oneOf":["Int","Float"]}`）を許す最小エンコードを定義する。**ただし §6.5 の通り、検証器が健全に解けるのは型変数（rank-1 let 多相）までで、`oneOf`（union ポート）は単一化ではなく決定的 overload-resolution で「一意解のみ accept・多義は reject」とする**。**真の union 部分型/rank-N 多相がノード設計に要求されたら、グラフ層でも D-moot は崩れる**ので、その時は **(a) ノード設計を rank-1＋一意 overload に制約する**か、**(b) カタログ/グラフを D=5 の IDL/EDN へ倒す**かを §6.5 残課題として判断する。
   - **自己記述スナップショット option（v4・§4.5 接続）**: 長期保存/出荷や (2a) 鮮度照合が要るグラフは、**オーサリング時のノード署名サブセットを `*.graph.json` に同梱**してよい（Blender SDNA 流）。これでロード時に現 registry と snapshot を差分照合でき、生成カタログのズレを検知できる。既存 JSON スタックで実装可能。
   - **将来の出荷最適化層**: 巨大グラフのロードが問題化したら、グラフのみ **Cap'n Proto/FlatBuffers に export**（§3b、F=5・mmap zero-copy・intrinsic では JSON 超）。**protobuf は parse 要(F=3)なので「ロード最速」目的では選ばない**が、d4 を `Any`/`Struct` で運ぶなら候補。オーサリングは JSON、配布はバイナリの二段。

### 6.2 非マニフェスト要素の組み込み（v4・transport の正直化）
- **ライブ内省(§4.3)は「値直列化だけ」収斂・transport は非等価**: §4.4(ii) と §4.3 が共有できるのは **`Saveable.toJson`（pure 値→Json）だけ**である。これにより **(a) オフライン生成（CI で `Persistence.save` がファイルに書く）は今日そのまま可能**だが、**(b) ライブ同期（HTTP/REST/LSP 風）は §0 に存在しないサーバ基盤の新設が前提**（grep 確認済み・`Persistence.save` は `Fs.FileWrite` のみ）。**(c) 鮮度照合（実機 JSON とリポジトリ JSON を diff）は (a) のファイル出力で可能**。すなわち **「生成と照合（ファイル経路）は単一の値直列化機構で today 成立、ライブ同期（transport 経路）はサーバ新設が要る」**——v3 の「3 つが単一機構に統合」は transport を過大評価していたので訂正。Flecs 等価は**値直列化に限り、REST transport は非等価**。これにより §7.2 の (2a) 鮮度リスクは**ファイル経路では縮小する**（生成も照合も同じ `Persistence.save`）が、(2b) は別問題で残る（§6.1 必須テスト）。
- **reflection(§4.1)は採れない**ことを明記し、その穴を **§4.4(ii) の runtime 直列化（reflection 不要・`Persistence` 既存）＋将来の LSP 風 endpoint（transport 新設時）で埋める**——(i) のソース解析 codegen は採らない、と設計意図を文書化する。

### 6.3 editor 配置への適用（§1.3 の二分にこの engine を置く）
この engine の IDE は **別プロセス・同言語(JVM 上の Flix)**（`ide/flix.toml`、engine 依存の standalone）。これは:
- **同言語ゆえ**: IDE が**ゲームの registry module をコンパイル時ソース依存**（§4.2 の正しい意味＝静的型定義の共有、live 値共有ではない）でき、**同言語ケースではカタログ JSON すら不要**にできる。カタログ JSON は**「Web/別言語 IDE 用の export」に限定**できる（Godot の extension_api.json と同位置＝§2.3）。
- **別プロセスゆえ**: 実行中の動的値を渡すなら**生成 JSON ファイルを介す**のが最単純（`Persistence.save` した JSON を `SceneSerializer`/`JsonCodec` 資産で扱う）。**IPC/LSP 風の動的経路を採るならサーバ新設が要る**（§4.3/§6.2）。
- **将来 Web/別言語 IDE を許すなら**: §4.4(ii) の JSON カタログ（または §4.3 の LSP 風 endpoint）が**唯一のクロス言語接点**。ここで EDN/Flix-only に倒すと汎用性目標を毀損する。→ **カタログ「export」形式に JSON を選ぶ判断は engine の汎用性要件と最整合**（カタログ「正本」を EDN/Dhall/CUE に昇格しても export を JSON にすれば両立）。

> 注: 「per-project IdeExtension で `examples/<proj>/ide` が組む」構成は**現リポジトリには存在しない**（`examples/fe_rogue/ide` は無し、IDE は単独 standalone）。本推奨は「同言語ゆえ registry module をコンパイル時依存できる」一般原理に基づき、現状の standalone IDE でも将来の per-project 化でも成立する形にしている。

### 6.4 移行の現実（tagParser の扱いを確定）
- **既存 `scene.json`/`SceneLoader`/`SceneSerializer`/`Persistence` は触らない**。ノードグラフ用に「`"node"`＋ports＋payload」の新スキーマを **`*.graph.json` の別系統・別 loader（greenfield）として追加**する。
- **tagParser の扱いを 1 つに確定**: **既存 21 builder（`buildByType`/`buildPureNodeType`, `SceneLoader.flix:340-374`）の `tagParser: Option[String] -> Result[Util.Json.JsonError, t]` は不変**とする。構造化 payload デコーダ `Json -> Result[JsonError, payload]` は**新グラフ loader 側に新設**し、`parseTagField`（`:399-404`）は**コピー元の雛形**として参照するだけで**その場で一般化しない**。
   - **churn 見積り**: 仮に既存 builder 群に payload デコーダを引き回す設計を採ると、**`tagParser` と同様に 21 builder 全てのシグネチャに第 2 デコーダ引数が波及**する（`buildByType`→`buildPureNodeType`→各 `buildXxx` の連鎖、`:340-374` ＋21 の `parseTagField` 呼び出し点）。これを避けるため**新 loader を分離**し、既存 scene 経路への churn を **0** に抑える。これが「別系統で新設」を選ぶ実利上の根拠。
- カタログ JSON は**生成物**（§4.4(ii)）なので手で編集させない運用。**CI で「registry から再生成 → diff 無し」を強制**（§6.2 のファイル経路と同一機構で照合）。ただしこの CI が捕まえるのは「**生成物 vs registry**」のズレ (2a) のみで、**(2b)「registry vs 実装コード」は §6.1 の整合テストが別途必要**（§7.2 の限界に注意）。
- JSON Schema は既存 `resources/*.schema.json` 運用に揃える。

### 6.5 型検証器（external typechecker）の設計スケッチ（v4・健全性穴を修正）

§3.0 の「形式単体ではエッジ型互換を保証できず外部 typechecker が担う」は設計の生命線ゆえ、未設計のまま放置しない。**かつ v3 の union 単一化は不健全だったので修正する**。

**(a) 中間表現（IR）— カタログ JSON のポート型から検証器が読む形**
```
PortType = TCon(String)              // 具体型タグ "Int"/"Float"/"EntityRef"/...
         | TVar(Int)                 // 型変数 {"var":"T"} を内部 ID 化（rank-1 let 多相）
         | TOneOf(List[TCon])        // overload 集合 {"oneOf":[...]}（※単一化対象にしない・下記）
NodeSig  = { kind: String, ins: List[(PortName, PortType)], outs: List[(PortName, PortType)] }
Catalog  = Map[String, NodeSig]      // node kind -> 署名
Edge     = { from: (NodeId, PortName), to: (NodeId, PortName) }
Graph    = { nodes: Map[NodeId, kind:String], edges: List[Edge] }
```
PortType の JSON ↔ ADT 往復は **§0 の `JsonCodec.expectString`/`decodeList` の純粋デコーダパターンをそのまま流用**（`{"var":..}`/`{"oneOf":..}`/文字列の 3 分岐）。`Catalog` は §4.4(ii) で生成した manifest JSON を読む。

**(b) アルゴリズム — 健全性を保つ 2 層分離（v3 の不健全 union 単一化を修正）**

v3 は `TOneOf` の単一化を「候補のいずれかが unify できれば成功」とした。**これは Robinson unification ではなく、union 型の単一化は複数解・順序依存で決定性も健全性も失う**（エッジ検査順で well-typed を reject／ill-typed を accept しうる）。**この穴が「D は外部 checker が担保するから moot」という load-bearing な前提を、多相ケースで崩していた**。v4 では 2 層に分離して健全性を回復する:

- **層 1: コア単一化＝rank-1 Hindley–Milner（TCon/TVar のみ・健全かつ決定的）**。置換 `Subst = Map[Int, PortType]` を畳み込みで蓄積する純粋関数 `unify: (PortType, PortType, Subst) -> Result[TypeError, Subst]`。`TCon` 同士は一致判定、`TVar` は **occurs-check 付き**束縛。**TOneOf はこの層に渡さない**。これは標準の Robinson unification そのもので、**健全・決定的・最汎単一化子の一意性が保証される**。型変数（ジェネリックノード `T->T` 等）はここで解く。同一 `TVar` が複数ポートに跨る場合は同じ `Subst` を共有してスコープを表現する（let 多相のインスタンス化はノード単位）。
- **層 2: overload 解決＝単一化と分離した決定的 resolution パス（union ポート用）**。`TOneOf(cands)` を含むエッジは単一化に混ぜず、**「相手の確定型（層 1 で解けた具体型）が `cands` の正確に 1 つと一致するか」を判定する overload resolution** とする。**一意一致なら accept・0 一致なら型エラー・2 つ以上一致なら "ambiguous overload" として reject**（accept しない）。これは単一化と違い**決定的**で、「いずれか unify で成功」の非決定性・不健全性を避ける。相手がまだ `TVar`（未確定）なら resolution を保留し、グラフ全体の層 1 確定後に再評価する（2 パス）。
- **健全性の限界の明示（D-moot の条件化）**: この設計が健全に扱えるのは **(1) 単相、(2) rank-1 let 多相（TVar）、(3) 相手型が確定したときの一意 overload** までである。**扱えないのは (4) 真の union 部分型（`Int <: Int|Float` のような subtyping）、(5) rank-N 多相、(6) 相互に未確定な overload どうしの結合**。これらがノード設計に要求されると **§3.0/§3.3 の「グラフ層で D は moot」は崩れ**、健全な静的保証を望むなら **D=5 の IDL（スキーマで型契約を強制）または EDN（tagged literal で型名を一級化）へ倒す**べき、と判断を仰ぐ（§7.4）。**＝D-moot は無条件ではなく、上記 (1)–(3) の範囲に限った条件付き命題である**。

**(c) 適用点**
- **適用点 1: エディタ配線時（incremental）**: ユーザーがエッジを 1 本引くたびに層 1 `unify`（＋相手が確定済みなら層 2 overload resolution）。成功なら確定、失敗なら即フィードバック（下記 UX）。
- **適用点 2: ロード時（whole-graph・2 パス）**: `*.graph.json` ロード後、**パス 1 で全 `edges` の層 1 単一化を畳み込み**（`EcsCodec.decodeStore` の畳み込みと同型だが型エラーは収集）、**パス 2 で TOneOf エッジの overload resolution を確定型に対して実施**。`Saveable.fromJson`／JsonCodec decode（構造デコード）が成功した**後段**に挟む純粋パス。
- **構造デコードと型検証の段階分離**: §0 の decode は「構造が JSON schema 通りか」を見る（well-formedness）。型検証はその後段で「配線の型整合」を見る。両者を分けることで、構造は OK だが型不整合なグラフでも**エディタ上は読み込めて該当エッジだけ赤くする**（編集続行可能）運用ができる。

**(d) 失敗 UX（どのエッジを赤くするか）**
```
TypeError = { edge: Edge, expected: PortType, actual: PortType,
              reason: <Mismatch | OccursCheck | OverloadNoMatch | OverloadAmbiguous> }
```
- 検証器は**短絡せず全エッジを検査して `List[TypeError]` を集約**（バッチ表示のため）。各 `TypeError` は違反 `Edge`（＝`(NodeId, PortName)` 対）を保持するので、**エディタはその 1 本の wire を赤く描き、tooltip に `expected vs actual`（overload なら候補集合と一致数）を出す**。
- ロード時は `Result[List[TypeError], TypedGraph]`：エラーがあっても構造は保持し、編集モードでは赤エッジ付きで開き、実行モードでは拒否する。
- **既存 pure 層への乗り方**: `unify`／overload resolution／検証器本体は**全て pure（IO なし）**で、§0 の「decode は完全 pure・encode の数値変換だけ unsafe IO」という JsonCodec の規律にそのまま整合する。検証器は `Catalog`（生成 manifest）と `Graph`（`*.graph.json`）の 2 純粋値を受け取り `Result` を返すだけなので、ロード経路（`Fs.FileRead` → decode → **typecheck** → 実行）に純粋ステージとして挿入できる。

**残課題（§7.4 と接続）**: 層 2 の「相互に未確定な overload どうし」の決定性（2 パスで収束しないケースの扱い）、rank-N 多相の要否、真の union 部分型が要るなら IDL/EDN へ倒す判断基準は、実グラフで要検証。**最小規約（rank-1＋一意 overload）で足りるかは実需要次第で、足りなければ D-moot 撤回 → IDL/EDN**（§3.0）。

---

## 7. リスク・未確定・正直な限界

1. **真のリスクは「レジストリ自動導出 (i)」と「(i) を避けた場合の (2b)」**。§4.4 の分離により、推奨の核（カタログ生成）は (ii) runtime 直列化＝`Persistence.save` で codegen ツール無しに成立する。残る重いリスクは「ノード実装コードからポート型を**自動導出**したい場合」(i) と、それを**手書き registry で回避した代償の (2b) ドリフト**（下記 2b）。
2. **案 X の鮮度問題は 2 層あり、CI が捕まえるのは片方だけ（正直に書き分け）**:
   - **(2a) 生成物 vs registry**: 生成カタログ JSON が registry コードとずれるリスク。**§6.2 のファイル経路単一機構（生成・照合が同一 `Persistence.save`）＋ CI「再生成→diff 無し」＋ §6.1 の自己記述スナップショット照合(§4.5)で構造的に縮小**。
   - **(2b) registry vs 実装コード（§6.1 へ格上げ済み）**: registry を**手書き**する以上、**手書き registry のポート型がノード実装関数の実際の入出力とずれる**ことがある。**これは CI の再生成 diff では捕まらない**（registry 自身が正本なので再生成しても registry と一致するだけ）。**§6.1 で「ノード実装↔registry 整合テスト」を案 X の必須構成要素に格上げした**のはこのため。捕まえる代替は (i) の自動導出。**(i) を採らない判断の本当のコストは (2b) にある**。**案 Y（manifest 正本）に倒すと (2a) は消える**が (2b) は残る（正本がコードでないだけ、実装との乖離はなお手書き整合に依存）。
3. **EDN/Dhall/CUE 採用判断の保留**。カタログ**手書き正本ロール**では EDN/Dhall/CUE が JSON+Schema を上回る。**ただし「EDN reader interop で B/E=4」は未検証ゆえ保守採点に据え**（注²）、結論を動かさない。JSON+Schema 既定は**生成 export ロールでの運用優位（手書き G が moot・整合 I=5・ゼロ新ツールチェーン）**であって、**手書き正本に倒すなら EDN/Dhall/CUE が上**。EDN/CUE 採用前に **JVM interop 往復のプロトタイプ検証が前提**。**前置きの通り、この分岐は §0.1 未発火下では当面実体化しない**。
4. **多相表現(d3)と typechecker の健全性限界（v4 で核心化）**。§6.5 で IR・rank-1 単一化・overload resolution・適用点・失敗 UX まで設計したが、**(a) 層 2 の相互未確定 overload の収束、(b) rank-N 多相の要否、(c) 真の union 部分型が要る場合は D-moot が崩れ IDL(D=5)/EDN へ倒す必要、は未確定**。**「外部 checker が型を担保するから D は moot」は単相＋rank-1＋一意 overload に限った条件付き命題**であり、強い多相を要求するなら IDL/EDN が依然有利。最小規約で足りるかは実グラフで要検証。
5. **survey の一次資料確度**。Unreal `FProperty/FField`（4.25+）・Blender `SDNA/DNA1`・Flecs `ecs_type_info_to_json`/`"0"` 戻り・Unity の **Force Text 既定/常時バイナリ資産**・Shader Graph JSON・Node-RED の js+html 2 形は一次/公式資料で裏取り済み（Sources）。Unreal `.uasset` のグラフ内部表現、Max `.maxpat` の厳密スキーマ、Cap'n Proto vs FlatBuffers の細部は二次資料ベースで、IDL を**本採用**する際は一次仕様で要再確認。
6. **「グラフ＝JSON で十分か」はロード規模に依存**。fe_rogue から推測しない方針ゆえ規模未知（§0.1 の発火条件で着手判断）。数万ノード級になれば §6.1 の **Cap'n Proto/FlatBuffers export 層**（protobuf ではない＝parse 要・ただし d4 を `Any`/`Struct` で運ぶなら候補）が必要になり、その時点で「グラフ形式は JSON 一択」は崩れる（**intrinsic-only では既に FlatBuffers＞JSON**、§3.3）。
7. **ライブ内省の transport 未実装・オフライン制約（v4 で正直化）**。§4.3 はゲーム起動前提、かつ **REST/LSP 風 transport は §0 に存在せずサーバ新設が前提**（`Persistence.save` は `Fs.FileWrite` のみ）。§6.2 で「生成・照合（ファイル経路）」は今日成立するが「ライブ同期（HTTP/LSP）」はサーバ新設が要る、と切り分けた。**Flecs 等価は値直列化のみ・transport 非等価**。単独でオフライン要件を満たさないのは内省**transport** を使う場合に限る（ファイル経路はオフライン可）。
8. **重み付けの恣意性と尺度の限界（残留・v4 で強化）**。§3.3 の重みは §1.2 から high/mid/low→3/2/1 で機械導出し ±1 感度（正本・**export 両ロール**）で頑健性を検査したが、**(a) high/mid/low の分類自体に判断が残る**（特に export ロールの C=mid を high にすると protobuf が JSON+Schema を抜き得る）、**(b) 1–5×1/2/3 は序数×序数ゆえ積和の基数差に量的意味は無い**（§3.3 冒頭）。**ゆえに総合点は「順位の頑健性チェック」に格下げ済みで、決定が宿る export 既定の最終決め手は数値ではなくゼロ新ツールチェーン＋既存足場再利用の運用優位**である点を再確認する。**intrinsic-only ランキング（§3.3）が示す通り、JSON の export/グラフ優位は内在品質ではなく switching cost 由来**であることも明記しておく。
9. **CUE/RON/protobuf-Any の評価は 1 行 pin に留まる**。§3.3 で候補欠落を補充したが主表採点はしていない。**CUE はカタログ正本ロールで EDN/Dhall と同 tier の有力対抗馬**として、案 Y 昇格判断時に EDN/Dhall と並べて再評価すべき（§6.5 unification テーマに最近接）。
10. **F 軸 armchair が唯一 weight=3 で結論に効く箇所（v4 追記）**。F は実測ベンチ無し（§3.0 注）にもかかわらず**グラフロールで F=3（高重み）**であり、グラフ勝者 JSON+Schema vs FlatBuffers の相対は load 軸が効く。**ゆえにグラフロールの順位は他ロールより F の armchair 性ゆえ確度が低い**——「大規模化したら F=5 の FlatBuffers へ」(§6.1)へ frame する現方針は妥当だが、**グラフ形式の最終確定には実測ロードベンチが要る**（規模未知の §0.1 と合わせ、着手時に計測する）。

---

### Critical Files for Implementation
- /Users/abab/Desktop/flix_game_engine/engine/src/SceneLoader.flix （`"type"` 構造ディスパッチ＋`parseTagField`＝`tagParser: Option[String] -> Result[Util.Json.JsonError,t]`〔`:399-404`〕。**文字列 TypeTag の既存解＝新グラフ loader の payload デコーダの雛形（コピー元）。既存 21 builder〔`:340-374`〕は不変、ここを in-place 一般化しない**）
- /Users/abab/Desktop/flix_game_engine/engine/src/Persistence.flix （`Saveable` trait＝「値→pretty JSON」最小契約〔trait `:16-25`・save `:33-42`〕。**§4.4(ii) のカタログ runtime 直列化＝鮮度照合のファイル経路を担う単一機構**の基盤。**ただし効果は `Fs.FileWrite` のみで HTTP/IPC transport は無く、ライブ内省にはサーバ新設が要る**）
- /Users/abab/Desktop/flix_game_engine/engine/src/JsonCodec.flix （pure decode／unsafe-IO encode の往復ヘルパ〔expect* `:22-56`・floatToBd/intToBd `:65-77`・encodeList/decodeList `:113-128`〕、全 164 行。**新スキーマ（node/ports/payload・多相 ty）の codec と §6.5 PortType の純粋デコーダ・rank-1 unification を載せる場所**）
- /Users/abab/Desktop/flix_game_engine/engine_ecs/src/EcsCodec.flix （不変 store ↔ `[{id,v}]` JSON〔`:14-32`〕。**グラフ＝ID 参照付きノード集合**の直列化パターン、および §6.5 ロード時 typecheck パス 1 の「全エッジ畳み込み」の同型参照）
- /Users/abab/Desktop/flix_game_engine/ide/src/SceneSerializer.flix （別プロセス editor が JSON を部分書き戻しする実装、全 494 行＝§1.3/§6.3 の editor 配置とグラフ編集 I/O の正本。グラフ用 `FieldValue` 拡張の起点）

Sources:
- Godot: [extension_api.json / ClassDB（DeepWiki）](https://deepwiki.com/godotengine/godot/15.1-gdextension-api), [GDExtension 紹介（Godot 公式）](https://godotengine.org/article/introducing-gd-extensions/), [ClassDB Internals](https://vorlac.github.io/gdextension-docs/type_system/classdb-internals/)
- Unity: [Shader Graph 新シリアライズ形式 PR #222](https://github.com/Unity-Technologies/Graphics/pull/222), [JsonObject / objectId（Unity docs）](https://docs.unity3d.com/Packages/com.unity.shadergraph@10.2/api/UnityEditor.ShaderGraph.Serialization.JsonObject.html), [Asset Serialization が Force Binary→Force Text 既定へ（Unity Discussions）](https://discussions.unity.com/t/why-has-the-default-mode-of-asset-serialization-changed-from-force-binary-to-force-text-in-project-settings/336981), [Asset serialization mode（JetBrains resharper-unity wiki・常時バイナリ資産含む）](https://github.com/JetBrains/resharper-unity/wiki/Asset-serialization-mode)
- Unreal: [Unreal Header Tool（Epic 公式）](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-header-tool-for-unreal-engine), [Unreal Property System / Reflection](https://www.unrealengine.com/en-US/blog/unreal-property-system-reflection), [UProperty→FProperty (4.25)](https://ayumax.net/entry/2020/03/22/144226/), [FField（UE API docs）](https://docs.unrealengine.com/en-US/API/Runtime/CoreUObject/UObject/FField/index.html)
- Node-RED: [HTML File（editor registerType/definition）](https://nodered.org/docs/creating-nodes/node-html), [JavaScript File（runtime registerType/constructor）](https://nodered.org/docs/creating-nodes/node-js), [Concepts（flows JSON）](https://nodered.org/docs/user-guide/concepts)
- Flecs: [Remote API（REST/reflection JSON）](https://www.flecs.dev/flecs/md_docs_2FlecsRemoteApi.html), [JSON addon group（reflection 無し型は `"0"`／Component values は reflection framework 記述時のみ直列化）](https://www.flecs.dev/flecs/group__c__addons__json.html), [json.h](https://github.com/SanderMertens/flecs/blob/master/include/flecs/addons/json.h)
- Blender: [DNA – Blender Developer Docs](https://developer.blender.org/docs/features/core/dna/), [Blend File Compatibility](https://developer.blender.org/docs/handbook/guidelines/compatibility_handling_for_blend_files/), [The .blend file format explained](https://fossies.org/linux/blender/doc/blender_file_format/mystery_of_the_blend.html)
- typed config/DSL: [Dhall（typed config language）](https://dhall-lang.org/), [CUE（unification-based config/constraint language）](https://cuelang.org/docs/concept/the-logic-of-cue/), [KDL document language](https://kdl.dev/), [RON (Rust Object Notation)](https://github.com/ron-rs/ron)
- JSON Schema 表現力: [JSON Schema: conditional (if/then/else, dependentSchemas)](https://json-schema.org/understanding-json-schema/reference/conditionals)
- protobuf d4 代替: [google.protobuf.Any](https://protobuf.dev/programming-guides/proto3/#any), [google.protobuf.Struct](https://protobuf.dev/reference/protobuf/google.protobuf/#struct)
- EDN on JVM（未検証 interop の対象）: [edn-java（純 Java EDN parser）](https://github.com/bpsm/edn-java), [clojure.edn](https://clojure.github.io/clojure/clojure.edn-api.html)
- 型理論: [Robinson unification / Hindley–Milner（健全な単一化の標準アルゴリズム）](https://en.wikipedia.org/wiki/Unification_(computer_science)), [overload resolution は単一化と分離する設計理由](https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system)