## ECS ハイブリッド移行

fe_rogue を段階的に ECS ハイブリッド化する作業は、ルートの **`ECS_WORKFLOW.md`**（道標・living document）に従う。
新セッションは同 doc の「§G 進捗」で現在ステップと次の一手を確認してから着手する。

## スキル一覧

| スキル | 用途 |
|--------|------|
| `/compile-fix` | Flixコンパイルエラーを診断し、既知の落とし穴と照合して修正を提案する |
| `/flix-docs` | Flixの公式ドキュメントとプロジェクト固有のスタイル確認（パイプスタイル・エフェクト構文・テスト・0.71.0固有の注意点） |
| `/engine-guide` | `Main.flix` / `Game.flix` の書き方・XxxScene との連携方法のガイド |
| `/game-loop` | `Game.flix` の `start` と `gameLoop` の書き方ガイド（起動時ハンドラ・フレームパイプライン・Scene委譲） |
| `/scene-editor` | `XxxScene.flix` を新規作成・編集するときの設計パターン |
| `/quality-assurance` | テスト設計指針（Scene・モジュール新規作成時、ゲームロジック編集時） |
