# このゲーム固有の設計原則

見下ろしレースのテンプレート。原始的なレースに、読んで学べる最小限を足した骨格 —
ハンドル（steerSpeed）・はみ出し減速（offRoadSlow）・ライバルの追い抜き（順位と得点）・
周回とゴール・追い抜きの控えめな閃光演出・文字格子で表すコース。

- **規則はコード、数値・色・コースは Doc**（エッセンス）。走る・曲がる・はみ出す・抜く・
  周回する の規則は `src/World.flix`（純粋）にある。JSON に if 文を書き始めたら境界を越えた合図。
  調整する数値は `assets/race.rules.json`、色は `assets/race.theme.json`、
  コースの形は `assets/race.course.json`。
- **コースは文字格子（rows）**: コース全体 = 1 枚の文字格子（`CourseDoc`）。1 行 = コースを縦に
  切った 1 段（上ほど先、下ほど手前）。'#' = 路面、'.'/空白 = 草（rpg のマップ rows と同じ発想）。
  「その文字が路面か」の判断は `CourseDoc.isRoad` 1 か所だけ。'#' の帯を左右にずらせばカーブになる。
  コースは下から上へ無限に流れる（`CourseDoc.rowAt` が余りで巻き戻す = 周回）。
- **前進は距離、周回は割り算**: 自機は横（playerX）にしか動かず、前進は `distance` を伸ばすだけ。
  周回数は `distance / lapLength` の整数部、順位は「自機より前にいるライバルの数 + 1」で素直に出す
  （空間分割や物理は持ち込まない）。
- **はみ出し減速はルール**: 自機の足元（いまの距離の行・playerX の列）が草なら前進速度に
  `offRoadSlow` を掛ける（`World.advance`）。足元が路面かは `World.onRoad` 1 か所で決める。ここはテストする。
- **追い抜きはルール**: 自機の `distance` がライバルの `progress` を越えたら 1 台抜く。二重加点を
  防ぐため各ライバルに `passed` の掛け金を持たせる（総当たりでなく状態で持つ）。抜くと `scorePerPass`。
- **周回とゴールはルール**: `totalLaps` 周ぶんの距離に達したら FINISH（WIN）で `finishBonus`。
  負け条件は置かず「順位で競う」素直な骨格にしている（クラッシュ即終了や時間切れは足さない）。
- **足さないもの**: クラッシュ／リタイア・ライバルの横移動や AI・ドリフト物理・ニトロ・
  タイヤ/ダメージ・複数コース。この骨格に亜種の決め打ちを足さない（足すなら別テンプレ）。
- **プレイヤーは詰まない・壊れない**: 壊れた Doc でも fail-open で必ず起動し、
  Finish から Space で必ず Title へ戻れる。View もライバルが空・Doc 既定で必ず何か描く。
- 描画はエンジンの `Render`（`box`/`boxAt`/`textTinted`/`fade`/`glowAt`）を使い、
  幾何・文字折り・パーティクルを自前で書かない。追い抜きの閃光は `Render.glowAt`
  （閉形式で安全）に任せ、粒子系を手書きしない。

## テストの当てどころ（ルールだけ）

- ハンドル（←→ で playerX が steerSpeed ぶん動く・画面の縁で止まる）。
- はみ出し減速（路面なら forwardSpeed のまま・草なら forwardSpeed * offRoadSlow）。
- 追い抜き（distance がライバルの progress を越えると抜く・加点・順位が上がる / 一度抜いたら二重加点しない）。
- 周回とゴール（distance / lapLength で lap が進む・totalLaps 周で FINISH・ボーナスは `finishBonus`）。
- 順位の計算（自機より前にいるライバルの数 + 1）・場面の決定（Title→Racing・Finish→Title）。
- コース読み（'#' が路面・'.'/空白が草 = `CourseDoc.isRoad`）。
- 閃光・スクロールの見た目・車の箱の形はテストしない（golden / 目視の担当）。
