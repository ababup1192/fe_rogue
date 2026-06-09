# fe_rogue を ROG Xbox Ally（Windows）で遊ぶ

`fe_rogue` は Flix → JVM バイトコードのゲームで、ウィンドウ/描画/音声は LWJGL
（GLFW + OpenGL 3.3 + OpenAL）で動く純 JVM アプリ。ROG Xbox Ally は Windows 11 / x86_64 の
ハンドヘルド PC なので、**JRE 21** と **Windows 用 LWJGL ネイティブ** さえあれば動く。
コントローラ操作はエンジン（`engine/src/LwjglLayer.flix`）が GLFW gamepad API で対応済み。

配布形態は2通り:

| 形態 | 中身 | 配布先での前提 | 作り方 |
|---|---|---|---|
| **ネイティブパッケージ**（`.dmg` / `.exe`）| JRE 同梱・ダブルクリック起動 | 何も要らない | `package-macos-dmg.sh` / `package-windows-exe.bat` |
| **jar + ランチャ** | fatjar + ネイティブ + アセット | JRE 21 を別途インストール | `package-dist.sh` |

> どちらも CWD 非依存。`Main.flix` は `AssetPath.root()`（= `-DprojectPath` か "."）を起点に
> アセットを解決する（`src/util/AssetPath.flix`）。ランチャ/jpackage が起動時に絶対ルートを渡す。

---

## A. ネイティブパッケージ（`.dmg` / `.exe`）— 推奨

JDK の `jpackage` で **JRE を同梱**したパッケージを作る。配布先に Java を入れる必要がない。

> **重要**: `jpackage` は**ターゲット OS 上でしか作れない**。`.exe` は Windows 機（Ally など）で、
> `.dmg` は mac で作る。Mac から Windows `.exe` のクロスビルドは不可。

### macOS `.dmg`（mac で実行）

```bash
cd examples/fe_rogue
bash scripts/package-macos-dmg.sh     # → dist/fe_rogue-1.0.0.dmg
```

`.dmg` を開いて `fe_rogue.app` を Applications にドラッグ → ダブルクリックで起動。
（未署名なので初回は「右クリック→開く」で Gatekeeper を回避。）

### Windows `.exe` をビルドする — 2通り

**(a) Mac だけで作る（クロスビルド・推奨）**

`jpackage` は使えないが、jpackage と同じ app-image を Mac 上で手組みできる:
self-contained jar ＋ Windows ランタイム（wine 経由の `jlink.exe` で生成）＋ jpackage の
launcher exe（`jpackageapplauncherw.exe` を jmod から取り出し）＋ `.cfg` を組み合わせる。

```bash
cd examples/fe_rogue
bash scripts/package-windows-exe-on-mac.sh          # → dist-win/fe_rogue/ と dist-win/fe_rogue-win.zip
# 任意: wine で起動確認  →  bash scripts/package-windows-exe-on-mac.sh --test
```

前提: `wine64`（`brew install --cask wine-stable`）, JDK 21+, ネット接続（初回に Windows JDK を DL）。
`dist-win/fe_rogue-win.zip` を Ally に展開して `fe_rogue.exe` を実行。**JRE 同梱・Java 不要**。
（生成物の最終確認は Windows 実機で。Mac では wine による起動確認まで。）

**(b) Windows 機（Ally など）で `jpackage` を使う**

リポジトリ一式と JDK 21 を Windows に用意し:

```bat
cd examples\fe_rogue
scripts\package-windows-exe.bat        REM → dist\fe_rogue\fe_rogue.exe (portable)
```

`dist\fe_rogue\` フォルダごと置いて `fe_rogue.exe` を実行。
単一インストーラ（`.exe`/`.msi`）が必要なら `.bat` 内の `--type app-image` を `exe`/`msi` に変更
（[WiX Toolset](https://wixtoolset.org/) のインストールが必要）。

---

## B. jar + ランチャ（JRE を別途入れる方式）

### 必要なもの

1. **JRE/JDK 21**（Ally 上）— [Temurin 21](https://adoptium.net/) など。
   自己完結配布にするなら開発機で `jlink` した最小 JRE を同梱してもよい。
2. **配布フォルダ** — fatjar + ネイティブ + アセット一式（下記スクリプトで生成）。
3. **Xbox 互換コントローラ** — Ally 内蔵コントローラは GLFW の内蔵マッピングで認識される。

## 配布フォルダの作り方（開発機）

```bash
cd examples/fe_rogue
bash scripts/package-dist.sh
```

`examples/fe_rogue/dist/fe_rogue/` が生成される。構成:

```
dist/fe_rogue/
├─ fe_rogue.jar          build-fatjar 成果物（クラス + JVM 依存）
├─ natives/              LWJGL ネイティブ jar（macOS arm64 + Windows x86_64）
├─ project.json          ウィンドウ/アセット定義（CWD から読まれる）
├─ assets/               sprites / audio / fonts / maps / materials
├─ resources/            units/enemies/weapons/... の JSON カタログ
├─ src/scenes/*.scene.json   各シーンのレイアウト（"src/scenes/..." の相対パスで参照）
├─ run.bat              Windows 用ランチャ
└─ run-macos.sh         macOS 動作確認用ランチャ
```

> **なぜ natives/ が別なのか**: `build-fatjar` はコンパイル済みクラスと JVM 依存ライブラリは
> 取り込むが、`[jar-dependencies]` の **ネイティブ .dll/.dylib は fatjar に含まれない**。
> そのため classpath にネイティブ jar を並べて LWJGL に拾わせる（ランチャがやる）。
>
> **なぜアセットを同梱するのか**: `Main.flix` は `LwjglLayer.withProject(".")` で起動時の
> **カレントディレクトリ**から `project.json` / `assets/` / `resources/` / `src/scenes/*.scene.json`
> を読む。fatjar 単体では動かないので、上記構造を保ったまま配置する。ランチャは起動前に
> 自身のフォルダへ `cd` する。

## Ally での実行

1. `dist/fe_rogue/` フォルダごと Ally にコピー。
2. JRE 21 を入れる（`java -version` が 21 を返すこと）。
3. `run.bat` を実行。

`run.bat` の実体:

```bat
cd /d "%~dp0"
java -cp "fe_rogue.jar;natives\*" Main
```

Windows では macOS 固有の `-XstartOnFirstThread` は **不要**（`GameEngine.ensureMainThread()` が
OS を見て macOS のときだけ自己再起動するため、Windows では何もせず直接起動する）。

## コントローラ操作（Xbox レイアウト）

`engine/src/LwjglLayer.flix` でゲームパッド入力を `isKeyPressed` に OR している。
**1 ボタン = 1 キー**を厳守する（1 ボタンを複数キーに割り当てると `onKeyPressed` が
同フレームで複数回発火し、決定の多重実行などの誤作動になる）。

| 操作 | ゲームパッド | 物理キー |
|---|---|---|
| カーソル移動 | D-pad ＋ 左スティック | 矢印キー |
| 決定（移動確定・攻撃・メニュー選択） | **A** | Z |
| メニュー確定（A の別系統） | **Start** | Enter |
| キャンセル / 戻る | **B** | X |
| ミニマップ | **Y** | M |
| 危険範囲トグル | **LB** | Left Shift |

> **Esc / View(Back) はパッドに割り当てない**：Escape はマップ上でゲーム終了を誘発するため。
> キャンセル・メニュー戻りは B(=X) だけで全サブメニューを処理できる（`dispatchMenuKey` の Cancel）。
> 割当を変えたい場合は `LwjglLayer.flix` の `padPressed` を編集する。
> 左スティックのデッドゾーンは 0.5（同ファイル内の `padUp/padDown/padLeft/padRight`）。

## ローカル動作確認（macOS）

配布物そのものを開発機で試せる:

```bash
cd examples/fe_rogue/dist/fe_rogue
./run-macos.sh
```

macOS では GLFW を main スレッドで動かすため `-XstartOnFirstThread` を付け、
配布物には `bin/flix.jar` が無いので自動再起動を `-Dgame.relaunched=true` で抑止している
（`run-macos.sh` が両方を渡す）。

## トラブルシュート

- **`UnsatisfiedLinkError` / ネイティブが見つからない** → `natives/` に対象 OS の jar があるか、
  classpath が `natives\*`（Windows）/ `natives/*`（macOS）になっているか確認。
- **`project.json` が読めない** → ランチャ経由で起動しているか（CWD が配布フォルダ直下になる）。
- **コントローラが効かない** → GLFW が gamepad として認識しているか。非標準パッドは
  SDL の `gamecontrollerdb.txt` を `glfwUpdateGamepadMappings` で読ませる拡張が必要（未実装）。
- **画面が小さい** → `project.json` の `windowWidth/windowHeight`（既定 832×624）を編集。
