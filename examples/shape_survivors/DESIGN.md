# Shape Survivors — 設計書

Flix（関数型プログラミング・代数的エフェクト）を**ゲームエンジンを題材に学ぶ**ブログ記事シリーズの **第一弾**。
ゲームは学習の「乗り物」であり、最終目的は読者が Flix の FP/Effect を使いこなせるようになること。

対象読者：他言語（JS/Python/Java 等）の経験はあるが、関数型プログラミングは初めて。

---

## なぜ「オートシューター」なのか

Vampire Survivors 風オートシューターは、面白さの密度が高いのに、**構造が FP 教材として理想的**：

- 敵の大群 ＝ **リスト**（`List[Enemy]`）
- 1 フレーム ＝ 前フレームの**純粋関数**（`step(world): World`）
- 画像アセット不要 — 図形（円・三角・矩形）＋ SDF フォントだけで成立しうる

「動くだけで敵が溶けていく」快感を、命令型なら可変配列＋for ループ＋手動削除でやるところを、
FP では `List.map` / `List.filter` / `List.foldLeft` の純粋変換で書く。それを**数百体の敵で視覚的に**体感させられる。

---

## 1. コアループ（削り切った理想系）

> **動く → 勝手に敵が溶ける → XP を拾う → レベルアップで3択 → 強くなる → もっと湧く → さらに生き延びる**

死守する面白さ ＝〈**オート攻撃 × 大群 × レベルアップの雪だるま**〉。これ以外は全部削る。

### 仕様
| 要素 | 内容 |
|---|---|
| 自機 | 図形 1 つ。WASD/矢印で移動。**攻撃ボタンなし**。最大 HP（初期 3〜5） |
| 武器 | 1 種・**自動発射**。一定間隔で**最も近い敵**へ撃つ（敵ゼロなら撃たない） |
| 敵 | 1 種。画面端からスポーン → 自機へ追尾。被弾で死亡＋XP ジェムをドロップ。自機接触でこちらが被弾（短い無敵） |
| XP/レベル | ジェム取得で XP 加算。満タンで**一時停止 → 3 択の強化** |
| 強化 | `Damage / FireRate / MultiShot / MoveSpeed / MaxHp` の 5 種から毎回ランダム 3 提示 |
| 激化 | 時間経過で**スポーン間隔**を下げる（湧きが濃くなる） |
| 決着 | HP0 でゲームオーバー。**生存時間＝スコア**。リスタートで別ビルドを試す（ラン制） |

### 削ったもの（初回プレイの面白さに影響しないと判断）
多彩な武器・武器進化／敵種の多様性（数と速度で代替）／マップ・地形（固定 1 画面）／
スクロールカメラ／永続強化（メタ進行）／パッシブアイテム。

---

## 2. ここで教える Flix（FP）＝作る順

第一弾は **不変性・リスト・純粋関数** で完結。effect / trait は第二弾以降に温存。
唯一 `\ Math.Random`（ランダムな湧き）だけ「型に副作用が出る最初の一例」として**読むだけ**で見せる。

| 概念 | ゲーム内の登場箇所 |
|---|---|
| Record と不変更新 `{f = v \| p}` | 自機の位置・HP・XP を「書き換えず作り直す」 |
| **List ＋ 高階関数（本丸）** | 大群 `List[Enemy]`：湧き = `Cons`、移動 = `List.map`、死亡/画面外 = `List.filter` |
| 純粋な `step(world): World` | 下記パイプ全体。シグネチャに `\` が無い＝副作用なしを型で確認 |
| Option | 最近敵 `List.minimumBy`／`None` なら撃たない |
| fold | 被弾解決・XP 合算・ダメージ集計を `foldLeft` |
| ADT ＋ パターンマッチ | `enum Upgrade` を `match` で適用（レベルアップ画面が教材） |

```
step(world) =
    world
      |> spawnEnemies     // 端に湧かす（ここだけ \ Math.Random）
      |> moveEnemies      // enemies |> List.map(寄せる)
      |> autoFire         // 最近敵 = minimumBy → Option、Some なら撃つ
      |> moveProjectiles  // List.map
      |> resolveHits      // 命中した敵を filter で消す、XP は foldLeft
      |> collectXp
      |> cullDead         // List.filter(alive)
```

---

## 3. アーキテクチャ：MVU（純粋 World + view）

- 純粋な `World`（`List[Enemy]` 等のただのレコード）を状態に持ち、`view: World -> Scene[NodeTag]` で
  毎フレーム図形を組み立てる。`update: World -> Input -> World` は純粋。
- **理由**：FP 教材として最も綺麗（純粋モデル・純粋更新・view 関数の 3 分割）。
  ノードに状態を散らさないので、レベルアップやリスタートが「World を差し替えるだけ」になる。
- **検証フラグ**：このエンジンは「状態をノードに埋める」node 中心。MVU 構成がエンジンの粒度・
  描画性能（毎フレーム数百図形）と噛み合うかを小さく実機検証してから本実装に入る。
  噛み合わなければ「engine ノード中心（NodeTag に状態）」へフォールバック。
  → `src/scenes/Game.flix` の hello world はこの確認も兼ねる。

---

## 4. ビルド進行（記事ミニシリーズ4本想定）

各回 ＝「明確な楽しさの追加」＝「明確な FP 概念の追加」。

| 回 | 追加される楽しさ | 主に学ぶ FP |
|---|---|---|
| 1 | 自機が動き、敵が湧いて**追ってくる**（“生きてる”感） | Record 更新／`List.map`／湧きで `\ Math.Random` を読む |
| 2 | **勝手に敵が溶ける**（オート攻撃が刺さる瞬間） | `Option`（最近敵）／弾の `List`／`List.filter`（命中） |
| 3 | 被弾・HP・**ゲームオーバー＋生存タイマー** | 純粋 `step` 完成／`foldLeft`／`enum Phase` ＋ match |
| 4 | XP・**レベルアップ3択でビルドが育つ**（中毒ループ完成） | `enum Upgrade` ＋ パターンマッチ／不変な強化適用 |

---

## 5. 現在の状態（hello world）

`src/scenes/Game.flix` は最小起動雛形。ウィンドウを開き、背景の上に
自機を表す円（Arc2D 円盤）とタイトル文字（Label2D / SDF）を静止表示するだけ。ゲームロジックは未実装。

### 動かし方
```sh
# リポジトリルートで一度だけ（エンジンを lib/ に配布）
make sync

# ゲームディレクトリで
cd examples/shape_survivors
java -jar ../../bin/flix.jar build   # 型チェック
java -jar ../../bin/flix.jar run     # ウィンドウ起動
java -jar ../../bin/flix.jar test    # テスト
# devbox 環境なら: devbox run -- java -jar ../../bin/flix.jar run
```

開発は main から切った worktree（ブランチ `shape-survivors`）で行う。
