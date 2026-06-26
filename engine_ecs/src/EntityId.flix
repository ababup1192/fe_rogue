// EntityId — entity を識別する番号（共有 ECS lib のトップレベル型）
//
// 透明な Int32 alias にしてある。不透明 newtype にすると型安全は上がるが、Map のキー・
// 採番（id + 1）・順序比較（id < other）に raw Int32 を使うゲーム側コードに churn が大きく、
// サンプルでは見返りが小さいと判断した。将来必要なら newtype へ格上げ可能。
pub type alias EntityId = Int32
