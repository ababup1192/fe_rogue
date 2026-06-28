# fe_rogue ファイル taxonomy — 「目視で変える構造(UI=Scene)」と「純粋ロジック(ECS)」の分離

## 原則（ユーザー言明）
- **UI = Scene を維持**（目視で変更されるべき構造・IDE 編集可・retained tree）。
- **sim = 純粋 ECS**（Entity / Component / System）。Scene は OOP 由来ゆえ sim から撲滅。
- **新規 sim ファイルは「XxxScene」を作らず、下記の役割ディレクトリに置く。** 既存は段階的に分離/移送。

## 役割カテゴリ（E/C/S だけでは足りない・現実の全分類）
| 役割 | 定義 | 置き場所(目標) |
|---|---|---|
| **Component** | entity の data（`Map[EntityId,T]` ストア） | `src/ecs/`（World.flix に集約 or 型別） |
| **System** | `World→World` の純粋ロジック | `src/ecs/systems/` |
| **Entity(spawn)** | component の合成・生成 | `src/ecs/spawn/` |
| **Resource** | 単一値の sim 状態（singleton） | World フィールド / `src/ecs/` |
| **Catalog/Data** | 静的コンテンツ（JSON 由来の定義） | `src/catalog/` |
| **View(=Scene)** | **目視で変える UI 構造**（menu/HUD/popup/cursor/camera） | `src/scenes/`（維持） |
| **Render** | World→drawables 投影（sim 描画・将来） | `src/render/` |
| **Lib** | faction/sim 非依存の純ユーティリティ | `src/lib/` |
| **Loop/Framework** | main loop・effect handler 配線 | ルート（Game/Main） |
| **Bridge(過渡)** | 移行中の足場（Scene が drain されると消える） | 暫定 |

## 分類（要点・sim と view の境界）

### View = Scene 維持（目視 UI・IDE 編集・撲滅しない）
TopBar / ActionMenu / WeaponSelect / ItemMenu / TradeMenu / GameOverMenu / SuspendConfirm / TitleMenu / BattlePanel / UnitCard / EnemyCard / UnitInfoPopup / LevelUpPanel / UnitHPBar / DamagePopup / Explosion / ItemPickupPopup / Log / Minimap / Fog(view) / TurnEndHold / Cursor / ArrowCursor / RangeScenes / Camera / Bgm / WeaponIcon / WeaponGlyph / Stairs(node) / CharacterSelect。
→ これらは input/event/render 反応（Plan B gate で残置可と確定済）。**Scene のまま。**

### System（→ `src/ecs/systems/`・純粋ロジック）— **単一 home 確定（A0-1）**
新規 System/rule は `src/ecs/systems/` に置く。`src/sim/` は deprecated（drain 中）。
- **relocate 済（A0-2 batch1・code-Scene=0 を検証して移送）**: `Combat`・`EnemyAI`・`CounterAttackRules`・`LevelSystem`・`StatusSystem`・`Board`・`Encounter`・`MoveDraft`・`Encumbrance` → `src/ecs/systems/`。`UnitView`（派生 component）→ `src/ecs/`。910 tests green 維持。
- **⚠ 純粋ラベル誤り（据置）**: `TurnFlow`(実コード Scene 参照 11)・`PhaseTransitions`(同 90) は **scene 結合ありで純粋でない**。relocate せず split 対象に再分類。
- **未分類で sim/ 残置**: `Weapon`(catalog 寄り)・`AnimEvent`(catalog)・`BoardSnapshot`(lib)・`EncounterBuilder`(bridge)・`effects/*`(system/catalog 混在) は別カテゴリ移送で対応。
- **Scene 内にロジックが埋まっている（System へ抽出が必要＝split 対象）**: `CombatScene`(戦闘解決)・`EnemyTurnDriverScene`(敵ターン driver・既に step() System)・`StairsExitScene`(階段順次・既に step())・`PlayerMovementScene`(移動)・`StaffCastScene`/`ItemScene`(アイテム使用ロジック部分)。

### Component（→ `src/ecs/`）
- `World.flix`（統一 component ストア＝ECS コア・**完成済**）。
- `UnitView`（faction-blind の派生ビュー＝derived component）。
- **decompose 対象**: `PlayerData`/`EnemyData`（OOP の per-entity record → 個別 component へ分解されるべき。weapons list vs weapon option 等の非対称もここ）。

### Entity(spawn)（→ `src/ecs/spawn/`）
- `addOnePlayer`/`addOneEnemy`（PlayerScene/EnemyScene 内の spawn funnel → component bundle 合成へ）。

### Resource
`TurnPhase`・`Pacing`・`SelectedPlayer`・`GatherResume`・`FloorProgress`・`PartySelection`・`InitialSpawns`・`FloorSnapshot`・`EnemyTurn`(queue)・(将来 `ActionQueue`/`Rng`)。

### Catalog/Data（→ `src/catalog/`）
`UnitCatalog`・`EnemyCatalog`・`FloorCatalog`・`ChestCatalog`・`WeaponCatalog`・`Consumable`・`Ring`・`Staff`・`ItemData`・`UnitBase`・`Sprite`・`CatalogId`・`AnimEvent`・`EffectRule`/`EffectBridge`/`EffectDsl`/`EffectRuleCodec`。

### Lib（→ `src/lib/`）
`lib/dungeon/*`・`lib/map/*`・`AssetPath`・`UITheme`・`MapSnapshot`・`BoardSnapshot`。

### Loop/Framework
`Main`・`Game`・`GameLifecycle`・`FrameAef`・`CustomEffects`。

### Bridge（過渡的・Scene drain で消える）
`EntityScene`（faction-blind scene accessor）・dual-write の World mirror・`EncounterBuilder`（scene→UnitView 組立）。

## ⚠ 「分離」の難所 = 混在ファイルの split
`CombatScene`/`PlayerScene`/`EnemyScene`/`MapScene` は **View と sim-logic が同居**。これらは「移動」でなく「**split（logic を System へ抽出・view を Scene に残す）**」が要る＝「構造変更によって分かれていく」部分。一括でなく per-file・per-機能で段階抽出。

## 移行の進め方（推奨・低リスク順）
1. **convention 確定（即）**: 新規 sim ファイルは `src/ecs/systems/`・`src/ecs/spawn/` に。`XxxScene` は View のみ。
2. **既に純粋な System body を `src/ecs/systems/` へ relocate**（Combat/EnemyAI/StatusSystem/LevelSystem/CounterAttackRules…）。Flix は namespace ベースゆえ移動は低リスク（build 確認のみ）。
3. **Catalog/Lib を `src/catalog/`・`src/lib/` へ整理**（純データ・低リスク）。
4. **混在 Scene を split**（CombatScene→CombatSystem＋combat view 等）＝大・段階的。
5. **最終形**: sim は ecs/{components,systems,spawn} + render、UI は scenes/(View)。dodge_the_creeps_ecs と同じ骨格。

## 結論
- E/C/S ＋ Resource/Catalog/View/Lib/Loop の**役割ディレクトリ**で「目視構造(Scene) vs 純粋ロジック(ECS)」を物理的に分離する。
- **新規は役割ディレクトリへ**（Scene を増やさない）。**既存は relocate（純粋なもの）→ split（混在）**で段階移行。
