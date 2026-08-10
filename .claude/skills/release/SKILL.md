---
name: release
description: "このリポジトリの検証とリリースの手順。作業中にどこまでテストを回すか、リリース前の全量ゲート、bake のバイト一致比較をいつやるか、版を上げて GitHub Release を作るまでを出す。make release / make bump を打つとき、版を上げるとき、「リリースしたい」「公開して」と言われたとき、全部のテストを回すか迷ったときに使う。"
allowed-tools: Read, Grep, Glob, Bash
---

# 検証とリリース

## 作業中のループ（毎回やる）

**テストは絞って速く回す。全量の検証はリリース直前の 1 回だけ。**

- 変更が波及したパッケージだけ `make test-<name>`
- それ以外は `flix check`（コンパイル通過）で足りる
- テストを持たないパッケージ（templates 等）は常に check のみ

## bake のバイト一致比較

**「挙動を変えていない」と主張するリファクタの時だけ**やる。機能追加リリースでは不要。

**`gallery/` は git 管理外なので `git status` では見えない。** 焼いた絵の一致は
`make bench` の SHA 突き合わせで見る。

1. `make bake-par`（不審なら逐次の `make bake`）
2. `git status` で assets/sfx の差分ゼロを確認（音や素材の退行はここに出る）
3. `for d in templates/*/; do make -C "$d" bench; done` で全テンプレの絵が基準と一致するか確認
4. examples 側は golden を持たないので、焼き直した `gallery/` を自分で目視する
   （`.claude/skills/critique-bake` の手順）

`python3 bin/lint-images.py` も併せて通す（焼いた絵が git に紛れ込んでいないか）。

## リリース手順

このチェックリストを回答にコピーし、埋めながら進める。

```
- [ ] 1. engine ソースが全てコミット済み（未コミットなら make release が中断する）
- [ ] 2. make bump FROM=x TO=y
- [ ] 3. コミット / push（push を忘れると gh が明示エラーを出す）
- [ ] 4. make release
- [ ] 5. lib/ を消したコピーで外部 fetch 検証
```

`make release` は sync → `test-par`（全量ゲート）→ `gl-parity` → build-pkg → `gh release create` を一括で回す。
tag は現在の HEAD SHA に固定される。

**全量ゲート**は `make test-par`（全パッケージ並列・壁時計 ≈ fe_rogue 1 本分・ログは `.test-logs/`）。
併せて `make gl-parity` を回して A 段全一致（全 scene 0 px）を確認する（GL と SoftRaster の絵の退行はテストに出ない）。
並列版に不審な挙動があれば逐次へフォールバックする（`make test` / `make release TEST=test`）。
