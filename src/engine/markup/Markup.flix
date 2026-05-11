/// `Markup` 名前空間のファサード。
///
/// 配下に `Markup.BBCode`（BBCode 風タグの汎用トークナイザ）を持つ。
///
/// 注: Flix 0.72.0 では `mod Markup.BBCode { ... }` を作っただけだと
/// `Markup.BBCode.parse` の参照解決に失敗する。`Yarn.flix` も同様に
/// `mod Yarn { ... }` を 1 つ置いて `Yarn.*` 配下を成立させているため、
/// このファイルが `Markup` 名前空間そのものの宣言を担う。
mod Markup {}
