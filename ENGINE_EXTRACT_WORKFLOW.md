# ENGINE_EXTRACT_WORKFLOW.md — fe_rogue 定型処理の engine 抽出ワークフロー（道標・living document）

新セッションはまず **§E 進捗** で現在フェーズと次の一手を確認してから着手する。

fe_rogue の ECS ハイブリッド移行（`ECS_WORKFLOW.md`）で確立した定型処理を、engine 側の**公式パーツ**として抽出する。ゲーム開発者が「World 構築 helper」と「UI コンポーネント」を使って ECS World を構築・書き換えできるようにするのがゴール。

検証: `cd examples/fe_rogue && java -XstartOnFirstThread -jar ../../bin/flix.jar test`（各ステップで green 維持）。engine_ecs を触ったら `make sync-engine-ecs`、engine を触ったら `make sync-engine` を**同一コミットに含める**（fpkg/source skew 防止）。

---

## §0 前提（決定事項と技術制約）

### ユーザー決定事項（2026-07-02）

1. **engine_ecs は ECS 汎用層として「Godot 対応物のみ」制約の対象外**（Bevy 等を参考にしてよい）。engine 本体は従来通り Godot 準拠を維持。
2. **実施は ECS_WORKFLOW.md の P2/P6 残タスク完了後**（*Legacy・golden oracle・DIFF assert 撤去後）。oracle 撤去で World.flix の refactor 面積が減ってから着手する。
3. **dodge_the_creeps_ecs も移行**し、第二消費者として汎用 API を検証する。
4. **E1（World 構築 helper）先行、E2（UI コンポーネント）後続**。

### 技術制約（調査で確定・設計を縛る事実）

- **Flix 0.71 は polymorphic effect 未サポート**（公式 doc 明記: "The Flix type and effect system does not yet support polymorphic effects"）。`eff Command[c]` のような型パラメータ付き effect は書けない → **effect 宣言（Command/WorldQuery/State）はゲーム側残置が確定**。抽出できるのは handler の中身（純関数＋Ref 操作）だけ。
- HKT なし・enum closed → trait ベース store 抽象は「component ごとに newtype＋instance」の trait 地獄になるため却下。**lens（getter/setter 関数ペアの record）＋関数コンビネータ**で解く。
- `EntityId = Int32` の透明 alias（`engine_ecs/src/EntityId.flix`）なので、fe_rogue の cell-key store（chests: `Map[Int32,_]`）や seq-key store（popupFx）も同じ Map 抽象に乗る。
- fe_rogue の `enum Cmd` は CLOSED 集合（golden trace の比較通貨・`cmdKey`）。**Cmd 列を変えない抽出**だけが安全。
- dodge_the_creeps_ecs には Cmd/Command が無い（直接 `World -> World`）→ dodge は **store 抽象（E1-1〜E1-2）の検証専用**。

### ボイラープレートの現況（抽出前ベースライン・実測）

| 定型 | 場所 | 規模 |
|---|---|---|
| `let World.World(w) = world` unwrap | `examples/fe_rogue/src/ecs/World.flix` | **118 回** |
| applyCmd の「unwrap→1 store insert→rewrap」3行 arm | `World.flix:750-1020` | 約 55 arm |
| accessor `xxxOf`（Map.get ラッパ） | `World.flix`（例 posOf `:1224`） | 約 55 個 |
| despawnUid の全 store remove 列挙 | `World.flix:705-748` | 34 store |
| Cmd.ClearUnits の全 store empty 列挙 | `World.flix:952-968` | 36 field |
| spawn funnel（Spawn＋Set系 Cmd 連発 emit） | `PlayerScene.flix:314-387`（18連）/ `EnemyScene.flix:232-287` | emit 計 91 |
| **1 component 追加のコスト** | Cmd enum / applyCmd / accessor / empty / ClearUnits / despawnUid | **6 箇所編集** |
| tagParser 定型（9行 match のコピペ） | GameOver/Suspend/ActionMenu/ItemMenu/WeaponSelect/TradeMenu | ×6 ファイル |
| モーダル開閉定型 | `GameOverMenuScene.flix:64-95` ≒ `SuspendConfirmScene.flix:61-90` | 2 画面同型 |
| コマンドウィンドウ定型（fit/可視/隣接） | ActionMenu/ItemMenu/WeaponSelect/Trade | 4 画面酷似 |

---

## §A ゴールと非ゴール

### ゴール

- **engine_ecs（flix_engine_ecs）= ECS 汎用層**: `Store.flix`（lens store 抽象）・`CmdRun.flix`（Cmd handler 雛形）・`Render.gauge`（ノードレスゲージ）を新設。
- **engine/src/ui/ = UI コンポジット層**: `Modal.flix`・`CommandWindow.flix`・`Theme.flix` を新設（**新 EngineNode 型・SceneLoader 新 case は作らない** — 既存 Godot 準拠ノードの組み合わせを操作する純関数）。
- fe_rogue と dodge_the_creeps_ecs が消費者になり、「component 追加 = 6 箇所編集」が「Cmd enum + applyCmd 1行 + 登録リスト 1行」まで縮む。

### 非ゴール（明示的見送り — 再燃条件は「消費者 2 つ目の出現」）

| 見送り | 理由 |
|---|---|
| EntityRef / enemyUidBase の一般化 | faction 2 系統は fe_rogue のドメイン事実。dodge は名前空間不要。消費者 1 の一般化はしない |
| `eff State + withState` 雛形の抽出 | polymorphic effect 不可で `StateOf[a]` が書けず、共通化余地が実質ゼロ（get/put 各 1 行）。engine-guide / scene-editor スキルに「公式パターン」として明文化する |
| `SpawnBundle` 新 Cmd | Cmd は golden の CLOSED 比較通貨。cmdKey・golden literal 全更新が必要になる |
| `KeyedLens[w,k,v]` 一般化 | EntityId=Int32 で chests/popupFx も乗る。特殊 store は bespoke StoreOps で逃がせる |
| buildRows（`ItemMenuScene.flix:308-340`）の engine 昇格 | 消費者 1 画面。fe_rogue `util/MenuRows.flix` 集約止まり |
| ItemList のノードレス化（メニュー描画 = resource→RenderItem 純関数） | ECS_WORKFLOW.md P4(b) 本体。E2 完了後に UiKit 内部の差し替えとして実施すると波及が最小（§B E2-3 参照） |

---

## §B フェーズ別ワークフロー

各フェーズの型: **狙い・価値 → 対象（path:line）→ サンプル（before/after）→ ステップ → 効果確認**。
「ちょっとずつ試す」原則: 1 フェーズ = 独立に revert 可能な単位。各フェーズ末に効果測定（削減行数・unwrap 残数・テスト数）を §E に記録してから次へ進む。

---

## E1 — World 構築 helper（engine_ecs）

### E1-1: `engine_ecs/src/Store.flix` 新設（lens ベース store 抽象）

**狙い・価値**: 「unwrap → Map 操作 → rewrap」3行定型（×118）と「全 store 列挙」関数（despawnUid/ClearUnits）を汎用コンビネータに封じ込める**基盤**。fe_rogue を一切触らないので、安全に「試す」第一歩。この時点でコード削減はゼロ（基盤のみ）— 効果が出るのは E1-2 以降。

**対象**: `engine_ecs/src/Store.flix`（新規）、`engine_ecs/test/TestStore.flix`（新規）。

**API（フルコード）**:

```flix
///
/// Store — ゲーム定義の World に対する component store（Map[EntityId, _] / Set[EntityId]）の汎用操作。
/// World の形は知らず、getter/setter（lens）を関数値で受け取る（Bevy の Lens の no-reflection 版）。
///
mod Store {

    /// Map store への lens。get は World から store を取り出し、set は store を World へ書き戻す。
    pub type alias StoreLens[w, v] = { get = w -> Map[EntityId, v], set = Map[EntityId, v] -> w -> w }

    /// Set[EntityId]（タグ）store への lens。
    pub type alias TagLens[w] = { get = w -> Set[EntityId], set = Set[EntityId] -> w -> w }

    pub def getAt(id: EntityId, lens: StoreLens[w, v], world: w): Option[v] =
        Map.get(id, lens#get(world))

    pub def getOr(id: EntityId, default: v, lens: StoreLens[w, v], world: w): v =
        Map.getWithDefault(id, default, lens#get(world))

    pub def insertAt(id: EntityId, value: v, lens: StoreLens[w, v], world: w): w =
        lens#set(Map.insert(id, value, lens#get(world)))(world)

    pub def removeAt(id: EntityId, lens: StoreLens[w, v], world: w): w =
        lens#set(Map.remove(id, lens#get(world)))(world)

    /// 現値（無ければ default）に f を適用して書き戻す。
    pub def updateAt(id: EntityId, default: v, f: v -> v, lens: StoreLens[w, v], world: w): w =
        insertAt(id, f(getOr(id, default, lens, world)), lens, world)

    pub def clearAt(lens: StoreLens[w, v], world: w): w =
        lens#set(Map.empty())(world)

    pub def tagHas(id: EntityId, lens: TagLens[w], world: w): Bool =
        Set.memberOf(id, lens#get(world))

    pub def tagAdd(id: EntityId, lens: TagLens[w], world: w): w =
        lens#set(Set.insert(id, lens#get(world)))(world)

    pub def tagRemove(id: EntityId, lens: TagLens[w], world: w): w =
        lens#set(Set.remove(id, lens#get(world)))(world)

    /// Bool で insert/remove を選ぶ（SetHidden 型の分岐を畳む）。
    pub def tagSet(id: EntityId, b: Bool, lens: TagLens[w], world: w): w =
        if (b) tagAdd(id, lens, world) else tagRemove(id, lens, world)

    pub def tagClear(lens: TagLens[w], world: w): w =
        lens#set(Set.empty())(world)

    /// per-entity store の「消し方/空にし方」の登録単位。型が異なる store を
    /// 1 本のリストに並べるための uniform record（despawn/clearAll の単一登録点）。
    pub type alias StoreOps[w] = { erase = EntityId -> w -> w, clear = w -> w }

    pub def ops(lens: StoreLens[w, v]): StoreOps[w] =
        { erase = id -> world -> removeAt(id, lens, world), clear = world -> clearAt(lens, world) }

    pub def tagOps(lens: TagLens[w]): StoreOps[w] =
        { erase = id -> world -> tagRemove(id, lens, world), clear = world -> tagClear(lens, world) }

    /// 登録済み全 store から id を消す（despawn の一般形）。
    pub def despawnAll(stores: List[StoreOps[w]], id: EntityId, world: w): w =
        List.foldLeft((acc, s) -> s#erase(id)(acc), world, stores)

    /// 登録済み全 store を空にする（ClearUnits の一般形）。
    pub def clearAll(stores: List[StoreOps[w]], world: w): w =
        List.foldLeft((acc, s) -> s#clear(acc), world, stores)
}
```

**ステップ**:
1. Store.flix 追加 → TestStore.flix（ダミー 2-store World record で insert/remove/update/clear/tagSet/despawnAll/clearAll を具体値 pin）
2. `make sync-engine-ecs`
3. 両 example（fe_rogue / dodge）がコンパイル不変であることを確認

**効果確認**: engine_ecs test green。削減ゼロ（基盤）と §E に記録。

---

### E1-2: dodge_the_creeps_ecs を lens 化（API 人間工学の試走）

**狙い・価値**: **243 行の小さい消費者で API の使い勝手を先に検証**する。書き味が悪ければここで Store API を直す — fe_rogue（2211 行）への波及ゼロの段階で設計ミスを吸収するのがこのフェーズの存在意義。

**対象**: `examples/dodge_the_creeps_ecs/src/ecs/World.flix` — `addMob(:190)` / `spawnPlayer(:205)` / `removeEntity(:219)`。

**サンプル**:

```flix
// before: removeEntity（unwrap → Map.remove ×n → rewrap の 10 行）
// after:
def unitStores(): List[Store.StoreOps[World]] =
    Store.ops(positionsL()) :: Store.ops(velocitiesL()) :: Store.ops(spritesL()) :: ... :: Nil

pub def removeEntity(id: EntityId, world: World): World =
    Store.despawnAll(unitStores(), id, world)

// addMob / spawnPlayer は insertAt のパイプに:
world |> Store.insertAt(id, pos, positionsL())
      |> Store.insertAt(id, vel, velocitiesL())
      |> ...
```

**効果確認**: dodge test green + 実機起動 1 回。行数削減を測って §E に記録。**API に手触りの問題があればここで修正して E1-1 に反映**（このフェーズが門番）。

---

### E1-3: fe_rogue lens カタログ + accessor / 単純 applyCmd arm の flip

**狙い・価値**: unwrap 118 回の大半を lens 約 35 個（×3 行）に封じ込める。**Cmd 列・適用意味論とも不変の等価置換**なので、既存テスト全体（golden 由来の決定論テスト含む）がそのまま回帰網になる — 「ちょっとずつ試す」の本体。store 群ごとにコミットを分けて bisect 可能にする。

**対象**: `examples/fe_rogue/src/ecs/World.flix` — applyCmd（`:750-1020`）・accessor 群（`:1180-1300` 付近）。コミット分割: ① unit 系 store（hp/pos/weapons/…）② 配置物系（chests/groundItems/stairsPos）③ fx 系（popupFx/explosionFx/tweens）。

**サンプル**:

```flix
// lens 定義（component 1 個 = 3 行、mod World 内。型注釈は必ず明示 — 推論がこじれたら締める）
def hpL(): Store.StoreLens[World, Int32] =
    { get = wl -> { let World.World(w) = wl; w#hp },
      set = m -> wl -> { let World.World(w) = wl; World.World({hp = m | w}) } }

// applyCmd arm: before（World.flix:778-781）
case Cmd.SetHp(ref, hpVal) =>
    let World.World(w) = world;
    World.World({hp = Map.insert(toUid(ref), hpVal, w#hp) | w})
// after（1 行）
case Cmd.SetHp(ref, hpVal) => Store.insertAt(toUid(ref), hpVal, hpL(), world)

// player-only no-op arm: before（SetStaves 等の 6 行 match）→ after（2 行）
case Cmd.SetStaves(ref, xs) => match ref {
    case EntityRef.Player(id) => Store.insertAt(id, xs, stavesL(), world)
    case EntityRef.Enemy(_)   => world
}

// accessor: before（2 行）→ after（1 行）
pub def hpOf(ref: EntityRef, world: World): Option[Int32] = Store.getAt(toUid(ref), hpL(), world)
```

「前値を見て決める」arm（SetAnim の play 意味論等）は `Store.updateAt` か `getAt`＋`insertAt` の 2 行で書く。

**効果確認**: 各コミットで全テスト green。フェーズ末に `grep -c "let World.World(w) = world" examples/fe_rogue/src/ecs/World.flix` で unwrap 残数を測り §E に記録（118 → 目標 ~40。残りは lens 定義自身と特殊 arm）。

---

### E1-4: despawnUid / ClearUnits → `unitStores()` 登録リスト化

**狙い・価値**: despawn と clear の store 列挙が**同一の 1 リスト**になる。「Despawn には足したが ClearUnits に入れ忘れた」型の漏れが構造的に消える — P6-2c で学んだ「除去漏れを DIFF でなくレビューで見える 1 行にする」の延長。**component 追加 = 6 箇所編集 → 3 箇所（Cmd enum / applyCmd 1 行 / unitStores 1 行）が完成する**。

**対象**: `World.flix` — despawnUid（`:705-748`、34 store 列挙）・Cmd.ClearUnits（`:952-968`、36 field）・empty は現状維持（record literal 必須のため）。

**サンプル**:

```flix
/// 全 per-entity store の登録リスト（component 追加時はここに 1 行足す＝単一登録点）。
def unitStores(): List[Store.StoreOps[World]] =
       Store.ops(hpL()) :: Store.ops(posL()) :: Store.ops(weaponsL()) :: ...   // 約 30 個
    :: Store.tagOps(hiddenL()) :: Store.tagOps(dyingL())
    // tweens は複合キー (EntityId, Channel) ゆえ bespoke StoreOps で逃がす
    :: ({ erase = uid -> wl -> { let World.World(w) = wl;
              World.World({tweens = Map.filterWithKey((key, _) -> fst(key) != uid, w#tweens) | w}) },
          clear = wl -> { let World.World(w) = wl; World.World({tweens = Map.empty() | w}) } })
    :: Nil

def despawnUid(ref: EntityRef, world: World): World =
    // playerIds/enemyIds は original-id keyed の特殊 2 store ＝ 従来どおり手書きで残置
    let cleaned = ...;
    Store.despawnAll(unitStores(), toUid(ref), cleaned)
// Cmd.ClearUnits arm も Store.clearAll(unitStores(), ...) + playerIds/enemyIds の empty
```

**効果確認**: 全テスト green + 完備性テストを 1 本追加（全 store を seed → Despawn → 期待 World と等値）。despawnUid/ClearUnits の削減行数を §E に記録。

---

### E1-5: `engine_ecs/src/CmdRun.flix`（Cmd handler 本体の雛形）

**狙い・価値**: effect 宣言はゲーム残置が確定している中で、**抽出できる唯一の部分（handler の中身）を公式型にする**。コード削減は小さい（1〜2 行 × 約 20 箇所）と正直に明記 — 主目的は「公式の型」の宣言的価値と、dodge が将来 Cmd を導入する際の雛形。優先度低・スキップ可。

**対象**: `engine_ecs/src/CmdRun.flix`（新規）、`examples/fe_rogue/src/game/Game.flix:834`（live handler）、テスト 16 ファイルの同型 handler。

**API**:

```flix
mod CmdRun {
    /// Cmd 列を World へ順に畳む純 replay（golden trace の apply 側・decode 後の再生）。
    pub def applyAll(apply: (c, w) -> w, cmds: List[c], world: w): w =
        List.foldLeft((acc, cmd) -> apply(cmd, acc), world, cmds)

    /// live handler の本体: Ref 上の world に 1 Cmd を即時適用。
    pub def applyToRef(apply: (c, w) -> w, cmd: c, worldRef: Ref[w, r]): Unit \ r =
        Ref.put(apply(cmd, Ref.get(worldRef)), worldRef)

    /// trace handler の本体: Cmd を記録しつつ適用（record+apply）。
    pub def recordAndApply(apply: (c, w) -> w, cmd: c, worldRef: Ref[w, r], log: Ref[List[c], r]): Unit \ r =
        { Ref.put(cmd :: Ref.get(log), log); applyToRef(apply, cmd, worldRef) }
}
```

```flix
// Game.flix:834 — before の中身そのまま helper 呼びに
with handler World.Command { def emit(c, k) = { CmdRun.applyToRef(World.applyCmd, c, worldRef); k() } }
```

**効果確認**: 挙動同一（等価置換）。全テスト green。

---

### E1-6: spawn bundle（`List[Cmd]` を返す純関数 + `World.emitAll`）

**狙い・価値**: 18 連 emit を **handler なしで unit test できる純粋値**にする。PlayerScene / EnemyScene で spawn 雛形を共有。**E1 で唯一 emit 順序リスクがあるフェーズ**なので単独スライスにする — golden/決定論テストが Cmd 列 byte-identical を凍結する検出網。

**対象**: `PlayerScene.flix:314-387`（addOnePlayer）、`EnemyScene.flix:232-287`（addOneEnemy）、`World.flix`（emitAll 2 行追加）。

**サンプル**:

```flix
// World.flix に追加（Command effect はこのモジュールの物なので engine_ecs には置けない）
pub def emitAll(cmds: List[Cmd]): Unit \ Command =
    List.forEach(Command.emit, cmds)
```

```flix
// PlayerScene.flix — 純粋 builder。順序は従来の emit 順と厳密一致（golden の凍結対象）
def playerSpawnCmds(sp: Spawn, data: Data): List[World.Cmd] =
    let ref = World.EntityRef.Player(sp#id);
       World.Cmd.Move(ref, sp#gridPos)
    :: World.Cmd.SetHp(ref, sp#resource#hp)
    :: ...                                    // 従来 :317-339 の順のまま
    :: World.Cmd.Spawn(ref)
    :: ...
    :: (match sp#resource#spriteFrames {
        case Some(_) => World.Cmd.SetAnim(ref, idleAnimName()) :: Nil
        case None    => Nil })

pub def addOnePlayer(sp: Spawn, scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
    let data: Data = ...;                     // data 構築を先頭へ（emit は world を読まないため安全）
    World.emitAll(playerSpawnCmds(sp, data));
    scene |> Scene.addChildAt(...)
```

注: 現行は emit の途中（`:339` 以降）に data 構築が挟まるが、emit は一方向書き込みで world を読まないため、先に出しても Cmd 列は byte-identical。

**効果確認**: golden/spawn 系テスト green + **実機 run 1 回（E1 全体の実機確認を兼ねる）**。spawn Cmd 列の unit test（`playerSpawnCmds` の具体値 pin）を追加。

---

## E2 — 公式 UI コンポーネント（engine/src/ui/ + engine_ecs）

**E2 全体の設計方針**（各フェーズ共通の前提）:
- **新 EngineNode 型・SceneLoader 新 case は作らない**。既存 Godot 準拠ノード（Panel/ItemList/Label2D）の上の「コンポジットビルダー + コントローラ純関数（Scene→Scene）」で組む → SceneLoader・エディタ・EngineNode enum 無改修。
- well-known 子名規約 `panel` / `headerBg` / `headerBgFill` / `header` / `menu` は**現行 fe_rogue scene.json と同名**なので、既存 scene.json は無変更で乗る。
- Godot 整合はコンポーネント概念レベルで担保: Modal = ConfirmationDialog 相当、CommandWindow = PopupMenu 相当、Theme = Theme/StyleBoxFlat 相当、gauge = TextureProgressBar 系。
- ゲームタグ（NodeTag）は closed enum のため、engine コンポーネントは常にタグを注入引数で受ける（MenuEvent/PackedScene で実証済みの型パラメータ `t` 伝播）。
- ItemList への setItems / 文脈分岐（buildItems）等の**画面固有ロジックはゲーム側に残す** — コンポーネントは「箱の形・可視性・カーソル規律」だけ請け負う。

### E2-1: `SceneLoader.tagParserFromMap`（tagParser 定型×6 の解消）

**狙い・価値**: 最小・挙動不変の 1 関数で「UI 定型を engine に上げる」流れを試す先頭スライス。9 行 match × 6 ファイル → 3 行呼び出し。

**対象**: `engine/src/SceneLoader.flix`（`constTagParser :116` の隣に追加）→ `make sync-engine` → fe_rogue 6 ファイル（GameOverMenu `:43-51` / SuspendConfirm `:44-52` / ActionMenu `:57-65` / ItemMenu / WeaponSelect `:62-70` / TradeMenu の各 tagParser）。

**サンプル**:

```flix
// engine 側（SceneLoader.flix）
/// scene.json の "tag" 文字列 → ゲームタグ変換の定型を畳む。
/// None / "NoTag" は noTag、map にあれば Ok、無ければ JsonError（sceneName 込み）。
pub def tagParserFromMap(sceneName: String, noTag: t,
                         m: Map[String, t]): Option[String] -> Result[Util.Json.JsonError, t] = ...

// fe_rogue 側 before（GameOverMenuScene.flix:43-51 の 9 行 match）→ after
def tagParser(): Option[String] -> Result[Util.Json.JsonError, NodeTag] =
    SceneLoader.tagParserFromMap("GameOverMenuScene", NodeTag.NoTag,
        Map#{"GameOverPanel" => NodeTag.GameOverPanel, "GameOverMenu" => NodeTag.GameOverMenu})
```

**効果確認**: engine test 1 本（Ok/Err/NoTag の 3 分岐 pin）+ fe_rogue 全テスト green（挙動不変。Err メッセージ文言 pin があれば確認）。

---

### E2-2: `Ui.Theme`（色 + 構造スタイル層）

**狙い・価値**: UITheme（色のみ 78 行）を「パネル / 見出し帯 / 行」の**構造スタイル**へ拡張し、**scene.json の色を真理点から「エディタプレビュー用初期値」に格下げ**する — UITheme.flix コメントにある「scene.json と test pin で二重管理」の解消。ノードレス描画（Render.gauge / renderPopups 系）と同じテーマ値を共有できる接続点（toBoxStyle）も作る。

**対象**: `engine/src/ui/Theme.flix`（新規、`mod Ui.Theme`）、`examples/fe_rogue/src/util/UITheme.flix`（`commandMenuTheme()` を 1 個追加）、各メニュー Scene の `add` 直後に apply 呼び。

**API**:

```flix
mod Ui.Theme {
    /// Godot StyleBoxFlat 相当（GameEngine.BoxStyle は Drawable 用低レベル、こちらはノード適用用）
    pub type alias PanelStyle  = { bg = Color, bgAlpha = Float32, border = Color,
                                   borderWidth = Float64, cornerRadius = Float64 }
    pub type alias HeaderStyle = { band = Color, text = Color }
    pub type alias MenuTheme   = { panel = PanelStyle, header = HeaderStyle,
                                   row = SelectedHighlight, selected = SelectedHighlight,  // ItemList 既存型を再利用
                                   text = Color, subtext = Color, disabled = Color }

    /// ロード済みサブツリーへテーマを一括適用（scene.json の色を真理点でなくす）
    pub def applyToCommandWindow(theme: MenuTheme, root: NodePath, scene: Scene[t]): Scene[t]
    pub def applyToModal(theme: MenuTheme, root: NodePath, scene: Scene[t]): Scene[t]
    pub def toBoxStyle(p: PanelStyle): GameEngine.BoxStyle
}
```

fe_rogue 側は `UITheme.commandMenuTheme(): Ui.Theme.MenuTheme` に既存の panel()/panelBorder()/headerText()/labelText()/allyBlue()/selectBg()/rowBg()/rowBorder()/faint() を詰めるだけ。

**効果確認**: 色 pin テストを「scene.json 同期 pin」から「applyToCommandWindow 適用後の値 pin」へ張り替え。scene.json とのドリフト検知 pin は 1 本だけ残す。全テスト green + 実機で見た目不変を確認。

---

### E2-3: `Ui.Modal` → GameOver → Suspend の順に適用

**狙い・価値**: 完全同型 2 画面（`GameOverMenuScene.flix:64-95` ≒ `SuspendConfirmScene.flix:61-90`）の重複を 1 コンポーネントへ。**「新ノードを作らないコンポジット純関数」方式が実画面で成立することを最初に実証する**フェーズ。API は選択状態を scene 引数に閉じ NodePath 直叩きを露出させない — 将来の P4(b)（選択状態の resource 化）が「Modal 内部の実装差し替え」に局所化される布石。

**対象**: `engine/src/ui/Modal.flix`（新規）、GameOverMenuScene → 1 コミット → SuspendConfirmScene → 1 コミット。

**API とサンプル**:

```flix
mod Ui.Modal {
    /// well-known 子名（scene.json 側もこの名前で書く規約）: panel / title(任意) / menu
    pub def panelPath(root: NodePath): NodePath = root ::: "panel" :: Nil
    pub def menuPath(root: NodePath): NodePath  = root ::: "panel" :: "menu" :: Nil
    pub def titlePath(root: NodePath): NodePath = root ::: "panel" :: "title" :: Nil

    /// 表示 + フォーカス + 項目セット + カーソル先頭（freezeAndShow / show の共通部）
    pub def open(root: NodePath, items: List[ItemEntry], scene: Scene[t]): Scene[t]

    /// phase 連動の毎フレーム可視同期（refreshItems の共通部）。
    /// 非表示時は focus を捨てカーソルを 0 に戻す（誤確定防止の現行イディオムを規約化）。
    pub def sync(root: NodePath, visible: Bool, items: List[ItemEntry], scene: Scene[t]): Scene[t]

    /// 確定対象の取得（confirmCurrentSelection の共通部）
    pub def selected(root: NodePath, scene: Scene[t]): Option[ItemEntry]
}
```

```flix
// fe_rogue before（GameOverMenuScene.freezeAndShow 末尾 7 行: Panel.mapAt + ItemList.mapAt 4 連パイプ）
// after（1 行）
scene |> Ui.Modal.open(rootPath(), menuItems())

// refreshItems（:80-95）after: phase 判定はゲーム側に残す（薄い Scene mod 維持）
let visible = World.PhaseQuery.phase() == SimPhase.GameOver;
Ui.Modal.sync(rootPath(), visible, menuItems(), scene)
```

**効果確認**: 1 画面ずつ適用 → 全テスト green → **実機でモーダル 2 画面**（全滅 → GameOver メニュー、中断確認）を確認。削減行数を §E に記録。

---

### E2-4: `Ui.CommandWindow` → ActionMenu のみ適用

**狙い・価値**: 4 画面酷似の中核（見出し帯 + ItemList + 内容フィット + 隣接配置）を 1 コンポーネントへ。**メトリクス真理点（itemHeight=8 / padding=4 / headerPadding=9 / inset=1 / sideMargin=2 / labelSidePad=4）を scene.json から engine コード（defaultMetrics）へ移す**。まず ActionMenu 1 画面だけで型を確立し、横展開（E2-5）と分離して試す。

**対象**: `engine/src/ui/CommandWindow.flix`（新規）、`ActionMenuScene.flix`（contentWidth `:216-222`・fitMenuToItems `:227-252`・applyVisibility `:100-121` を置換）。

**API**:

```flix
mod Ui.CommandWindow {
    /// メトリクス（現行 fe_rogue 値をデフォルトに。scene.json 一致 pin の真理点をここへ移す）
    pub type alias Metrics = { itemHeight = Float64, bottomPad = Float64, headerPad = Float64,
                               headerInset = Float64, sideMargin = Float64, labelSidePad = Float64 }
    pub def defaultMetrics(): Metrics

    /// well-known 子名: panel / headerBg / headerBgFill / header / menu（現行 scene.json と同名）
    pub def panelPath(root: NodePath): NodePath   // 5 子名ぶん

    /// items の最長ラベル幅から内容幅を出す（ActionMenuScene.contentWidth の一般化）
    pub def contentWidth(m: Metrics, root: NodePath, items: List[ItemEntry], scene: Scene[t]): Float64

    /// 行数・内容幅に合わせて menu/panel/headerBg/headerBgFill/header を一括フィット
    pub def fitToItems(m: Metrics, root: NodePath, count: Int32, contentW: Float64, scene: Scene[t]): Scene[t]

    /// 5 ノード一括の可視/フォーカス切替（focused=false 時は setHighlightWhenUnfocused(true) が既定）
    pub def applyVisibility(root: NodePath, visible: Bool, focused: Bool, scene: Scene[t]): Scene[t]

    /// 隣接配置（anchor の右端 - overlap に自分の panel を置く。positionBesideActionMenu の一般化）
    pub def positionBeside(anchorRoot: NodePath, selfRoot: NodePath, overlapPx: Float64, scene: Scene[t]): Scene[t]

    pub def setHeader(root: NodePath, text: String, color: Color, scene: Scene[t]): Scene[t]
}
```

**効果確認**: メトリクス pin テスト（testMenuOriginMatchesHeaderPadding 等）を defaultMetrics 参照へ書き換え。全テスト green + 実機で ActionMenu の開閉・フィット・見出し帯を確認。

---

### E2-5: WeaponSelect → ItemMenu → TradeMenu 横展開（1 画面 1 コミット）

**狙い・価値**: E2-4 で確立した型の水平展開 — **engine 変更なし・fe_rogue のみ**なのでリスク最小。型に乗らない独自部分（TradeMenu の headerBg 幅操作 `TradeMenuScene.flix:335-338` 等）は**無理に畳まず残置してよい**と明記 — 「共通部だけ畳む」規律の実地訓練。

**対象**: `WeaponSelectScene.flix`（positionBesideActionMenu `:197` 等）→ `ItemMenuScene.flix`（`:373-381` 等）→ `TradeMenuScene.flix`。

**効果確認**: 1 画面ごとにテスト green + 実機。4 画面合計の削減行数を §E に記録。

---

### E2-6: `Render.gauge`（engine_ecs・ノードレスゲージ）

**狙い・価値**: **World 直描き UI（ECS スタイル）の公式部品第一号**。ColorRect 3 枚手組み（`UnitHPBarScene.flix:134-186`: track/fill/予報ストライプ）を GaugeSpec 1 呼びへ。ProgressBar ノードとは統合せず**分業を明文化**（ツリー HUD = ProgressBar ノード / World 直描き = Render.gauge）— 統合はノード API・SceneLoader・エディタまで波及するわりに利用者 1 箇所で過剰。

**対象**: `engine_ecs/src/Render.flix`（`solidBox` の隣に追加。RenderItem.Box の style 拡張のみで RenderItem 型自体は不変）、`UnitHPBarScene.flix`（barDrawables 置換）。

**API**:

```flix
pub type alias GaugeOverlay = { fromValue = Float64, toValue = Float64, color = Color,
                                stripeColor = Color, stripeAlpha = Float32,
                                stripeWidth = Float64, stripePeriod = Float64 }
pub type alias GaugeSpec = { size = Vec2.Vec2, value = Float64, maxValue = Float64,
                             fillColor = Color, trackColor = Color, borderPx = Float64,
                             trackCornerRadius = Float64, fillCornerRadius = Float64,
                             zIndex = Int32, overlay = Option[GaugeOverlay] }

/// トラック + フィル + （任意）減少分ストライプの (offset, RenderItem) 列。
/// 呼び側が pos を足して Render.draw / applyCameraScale に流す。
pub def gauge(spec: GaugeSpec): List[(Vec2.Vec2, RenderItem)]
```

**効果確認**: fillWidth/hpRatio pin を engine_ecs test へ昇格。全テスト green + **実機で HP バー・攻撃予報ストライプの見た目回帰**を確認。

---

### E2-7: `Label2D.fitText` + fe_rogue `util/MenuRows.flix`

**狙い・価値**: 小物の回収。fitText は Godot の text_overrun_behavior 相当（＝engine 本体の Godot 準拠制約内）で純関数・テスト容易。buildRows は engine に**上げない**（消費者 1 画面）— fe_rogue util 集約で「2 画面目 / 2 ゲーム目の需要が出たら昇格」の前例を作る。

**対象**: `engine/src/scene/Label2D.flix`（`measure` の隣に `fitText(text, atlas, fontSize, maxWidth): String` — `UnitCardScene.flix:311-321` を移植）、`examples/fe_rogue/src/util/MenuRows.flix`（新規 — `ItemMenuScene.flix:308-340` の buildRows/rowIcons を集約）。

**効果確認**: fitText の境界テスト（収まる/あふれる/空文字）を engine test に。全テスト green。

---

### E2-8（任意・最後）: `Ui.Modal.add` / `Ui.CommandWindow.add`（scene.json レス構築）

**狙い・価値**: 新規ゲームが scene.json を書かずにモーダル / コマンドウィンドウを組める経路。SceneLoader **既存語彙**の JSON を内部生成 → `PackedScene.fromJString` → instantiate — 生成物は通常の scene tree なのでエディタで開ける（scene.json-first の精神を維持）。**fe_rogue は移行しない**（現行 scene.json で足りる・消費者なし）ため後回し可。

**対象**: `engine/src/ui/Modal.flix` / `CommandWindow.flix` に `add(spec, theme, atlas, scene): Scene[t] \ {GameEngine.Game, Fs.FileRead}` を追加。

**効果確認**: engine test（生成 JSON のロード → well-known 子の存在 pin）。dodge か新規 example で 1 回使ってみるのが理想。

---

## §C 横断ルール

1. **同期**: engine 変更 = `make sync-engine`、engine_ecs 変更 = `make sync-engine-ecs` を同一コミットに含める。
2. **純粋性**: Store/UiKit の関数はすべて純粋（`w -> w` / `Scene[t] -> Scene[t]`）に保つ — FrameAef/効果行の伝播（ECS_WORKFLOW.md:163 の連鎖コスト）を発生させない。add 系のみ `\ {GameEngine.Game, Fs.FileRead}`（既存 add と同じ）。
3. **BBCode 罠**: Modal/CommandWindow の well-known 子は Label2D 固定（RichTextLabel を含めない — `[xxx]` がタグ解釈される）。
4. **型推論**: lens の record 内 lambda がこじれたら `StoreLens[World, Int32]` の明示注釈で締める（「単一ケース enum で推論を締める」流儀と同じ発想）。
5. **効果測定**: 各フェーズ末に §E へ記録 — 削減行数 / unwrap 残数（grep）/ 「component 追加時の編集箇所数」の変化 / テスト数。
6. **一括置換は置換件数を assert**（P6-2b の教訓: silent miss が実バグ直結）。
7. **過剰抽象の再燃条件**: §A 非ゴール表の項目は「消費者 2 つ目の出現」まで再検討しない。

## §D 検証

- **fe_rogue 回帰**: `cd examples/fe_rogue && java -XstartOnFirstThread -jar ../../bin/flix.jar test` を各ステップで green 維持（P6 完了後の baseline を §E に記録して引き継ぐ）。
- **engine/engine_ecs 単体テスト必須**（TestLayout の前例に倣う）: TestStore（insert/remove/update/despawnAll/clearAll）、TestCmdRun、fitToItems の矩形計算、Modal.sync の可視状態遷移、gauge の Drawable 数と幅、tagParserFromMap の 3 分岐、fitText の境界。
- **実機 run 必須ポイント**: E1-2（dodge 起動）、E1-6（spawn＝E1 総仕上げ）、E2-3（モーダル 2 画面）、E2-5（各画面）、E2-6（HP バー + 予報ストライプ）。
- **dodge**: E1-2 で test green + 実機起動 1 回。

---

## §E 進捗（living — 更新はここだけで良い）

**現在フェーズ: 未着手（前提ゲート待ち）**

前提ゲート:
- [ ] ECS_WORKFLOW.md P2 完了（在庫 writer flip・field 削除）
- [ ] ECS_WORKFLOW.md P6 手順 5/6 完了（*Legacy・golden oracle・DIFF assert 撤去、doc final 化）
- [ ] fe_rogue テスト baseline を記録: ____ 件（P6 完了時点）

フェーズ進捗:
- [ ] E1-1 Store.flix 新設
- [ ] ~~E1-2 dodge lens 化（API 試走）~~ 対象消滅（2026-07-07 dodge_the_creeps_ecs 削除）。API 試走が必要なら値ベースの小型消費者（sokoban/breakout）で代替するか、E1-3 冒頭の小 store 群を試走に充てる
- [ ] E1-3 fe_rogue lens カタログ + arm/accessor flip
- [ ] E1-4 despawnUid/ClearUnits 登録リスト化
- [ ] E1-5 CmdRun.flix（優先度低・スキップ可）
- [ ] E1-6 spawn bundle
- [ ] E2-1 tagParserFromMap
- [ ] E2-2 Ui.Theme
- [ ] E2-3 Ui.Modal（GameOver → Suspend）
- [ ] E2-4 Ui.CommandWindow（ActionMenu）
- [ ] E2-5 横展開（WeaponSelect → ItemMenu → TradeMenu）
- [ ] E2-6 Render.gauge
- [ ] E2-7 fitText + MenuRows
- [ ] E2-8 add 系（任意）

効果測定ログ（フェーズ末に追記）:
| フェーズ | 削減行数 | unwrap 残数 | テスト数 | メモ |
|---|---|---|---|---|
| （baseline） | — | 118 | | component 追加 = 6 箇所編集 |

- 履歴:
  - 2026-07-02: 本 doc 作成（調査 3 本 + 設計 2 本の結果を統合。決定事項: engine_ecs は Godot 制約対象外 / 実施は P2/P6 完了後 / dodge も移行 / E1 先行）
  - 2026-07-07: examples 棚卸しで dodge_the_creeps_ecs を削除 → E1-2（dodge 試走）は対象消滅。第二消費者検証は残存 example で代替する
