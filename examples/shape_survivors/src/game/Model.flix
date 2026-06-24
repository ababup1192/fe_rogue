///
/// Shape Survivors — Model（ゲームの状態と定数）
///
/// この mod は「純粋なゲームのデータ」だけを持つ。エンジン（Scene / GameEngine）には
/// 一切依存せず、依存するのは Vec2（純粋な座標計算）のみ。
/// ＝ ゲームの本体は描画エンジンを知らない、というのが MVU の肝。
///
mod Model {

    /// 敵の種類。Grunt は弱い雑魚、Tank は HP が高く遅く大きい。
    /// 「種類が増えてもノードは増やさず、フィールドを 1 つ足すだけ」＝純粋 List 設計の効き目。
    pub enum EnemyKind with Eq, ToString {
        case Grunt
        case Tank
    }

    /// 敵 1 体。位置・種類・残り HP を持つ。
    pub type alias Enemy = {
        pos  = Vec2.Vec2,
        kind = EnemyKind,
        hp   = Int32
    }

    /// 薙ぎ（Whip）の一閃。ダメージは生成した瞬間に矩形内へ即時適用済みで、これは
    /// 「一瞬の閃き」の見た目だけを持つ（ttl が 0 になったら消える）。
    pub type alias Slash = {
        pos   = Vec2.Vec2,   // 発生時の自機位置
        right = Bool,        // 右向きの薙ぎか（false は左）
        ttl   = Float64      // 残り表示時間（秒）
    }

    /// 経験値ジェム。敵を倒すと落ち、自機が近づくと吸い寄せられ、触れると XP になる。
    pub type alias Gem = {
        pos = Vec2.Vec2
    }

    /// ゲームの状態（Model）。1 フレーム＝この値 1 つ。
    /// 自機のステータス（moveSpeed/fireInterval/maxHp/multiShot）は**定数ではなく World に持つ**。
    /// レベルアップの強化で 1 ラン中に育つ＝強化適用が「World を作り直す」純粋関数になる。
    pub type alias World = {
        player      = Vec2.Vec2,
        facingRight = Bool,        // 自機が左右どちらを向いているか（薙ぐ方向。水平入力で更新）
        enemies     = List[Enemy],
        slashes     = List[Slash], // 表示中の薙ぎの閃き（ダメージは生成時に適用済み）
        gems        = List[Gem],   // 落ちている経験値ジェム
        sinceSpawn  = Float64,    // 前回スポーンからの「経過」秒（増えていき、閾値で発火）
        sinceFire   = Float64,    // 前回発射からの「経過」秒（増えていき、閾値で発火）
        invulnLeft  = Float64,    // 被弾後の無敵の「残り」秒（減っていき、0 で再被弾可）
        kills       = Int32,      // 倒した数（手応えの表示用）
        hp          = Int32,      // 残り HP（0 になったら presentation 側が GameOver へ）
        elapsed     = Float64,    // 生存時間（秒）＝スコア
        xp          = Int32,      // 現在レベルでの累積 XP
        level       = Int32,      // 現在レベル
        moveSpeed   = Float64,    // 自機の移動速度（MoveSpeed 強化で増える）
        fireInterval = Float64,   // 発射間隔（FireRate 強化で短くなる）
        maxHp       = Int32,      // 最大 HP（MaxHp 強化で増える）
        multiShot   = Int32,      // 薙ぎの本数（1=向いた側のみ、2 以上で両側）
        damage      = Int32       // 薙ぎ 1 回の威力（Damage 強化で増える＝Tank を速く倒せる）
    }

    // --- 固定定数（ラン中に変わらないもの。presentation からも参照するので pub） ---

    pub def designWi(): Int32 = 480
    pub def designHi(): Int32 = 270

    pub def playerRadius(): Float64 = 12.0

    pub def enemyRadius(): Float64 = 7.0     // 当たり判定の半径（種類によらず共通）
    pub def maxEnemies(): Int32 = 80         // 画面上の敵の上限（多すぎると毎フレームの再構築が重い）

    // --- 敵の種類ごとのパラメータ（パターンマッチで分ける） ---
    /// 移動速度。Tank は遅い（どちらも自機より遅く、引き撃ちで避けられる）。
    pub def enemySpeedFor(kind: EnemyKind): Float64 =
        match kind {
            case EnemyKind.Grunt => 55.0
            case EnemyKind.Tank  => 32.0
        }
    /// 初期 HP。Grunt は 1 発、Tank は固い。
    pub def enemyHpFor(kind: EnemyKind): Int32 =
        match kind {
            case EnemyKind.Grunt => 1
            case EnemyKind.Tank  => 4
        }
    /// 見た目の大きさ（半径）。当たり判定とは別で、Tank は大きく見せる。
    pub def enemyVisualRadiusFor(kind: EnemyKind): Float64 =
        match kind {
            case EnemyKind.Grunt => 7.0
            case EnemyKind.Tank  => 12.0
        }
    /// 倒したときに落とすジェムの数。Tank は多い（撃破の見返り）。
    pub def gemsDroppedFor(kind: EnemyKind): Int32 =
        match kind {
            case EnemyKind.Grunt => 1
            case EnemyKind.Tank  => 4
        }
    /// スポーン時に Tank になる確率（0..1）。残りは Grunt。
    pub def tankSpawnChance(): Float64 = 0.18

    // 激化：スポーン間隔は生存時間とともに短くなり（湧きが濃くなる）、下限で頭打ち。
    def baseSpawnInterval(): Float64 = 0.8   // 開始時の間隔（秒）
    def minSpawnInterval(): Float64 = 0.15   // 下限（これ以上は速くならない）
    def spawnDecayPerSec(): Float64 = 0.01   // 1 秒ごとに間隔がどれだけ縮むか
    /// 生存 elapsed 秒時点でのスポーン間隔（純粋・時間の関数）。
    pub def spawnIntervalAt(elapsed: Float64): Float64 =
        Float64.max(minSpawnInterval(), baseSpawnInterval() - spawnDecayPerSec() * elapsed)

    // --- Whip（薙ぎ）---
    pub def whipReach(): Float64 = 78.0       // 向いた側へ届く横の距離
    pub def whipHalfHeight(): Float64 = 24.0  // 薙ぎの縦の半幅（上下の当たる範囲）
    pub def whipBackMargin(): Float64 = 10.0  // 自機の少し後ろも巻き込む
    pub def slashTtl(): Float64 = 0.09        // 閃きの表示時間（秒）。短いほどチカつかない

    pub def invulnDuration(): Float64 = 1.0  // 被弾後 1 秒は無敵

    // --- ジェム（経験値）---
    pub def gemRadius(): Float64 = 3.0
    pub def gemMagnetRadius(): Float64 = 75.0   // この距離内のジェムは自機へ吸い寄せられる（広めに＝早く回収）
    pub def gemPickupRadius(): Float64 = 16.0   // この距離内で回収＝XP になる
    pub def gemSpeed(): Float64 = 180.0         // 吸い寄せ速度
    pub def maxGems(): Int32 = 50               // 盤面のジェム上限。超えた分は即 XP に変換（重さ対策）

    // --- レベルアップ関連 ---

    pub def xpPerGem(): Int32 = 1
    /// 次のレベルに必要な XP。レベルが上がるほど増える。
    pub def xpThreshold(level: Int32): Int32 = 4 + (level - 1) * 3

    // --- ステータスの初期値（initialWorld でだけ使う。強化で World 側が育つ） ---

    def initialMoveSpeed(): Float64 = 110.0
    def initialFireInterval(): Float64 = 0.35
    def initialMaxHp(): Int32 = 5

    /// ゲーム開始時の World。再挑戦でもこれに戻る。
    pub def initialWorld(): World =
        { player = {x = Int32.toFloat64(designWi()) / 2.0,
                    y = Int32.toFloat64(designHi()) / 2.0},
          facingRight = true,  // 最初は右向き
          enemies = Nil,
          slashes = Nil,
          gems = Nil,
          sinceSpawn = 0.0,
          sinceFire = 0.0,
          invulnLeft = 0.0,
          kills = 0,
          hp = initialMaxHp(),
          elapsed = 0.0,
          xp = 0,
          level = 1,
          moveSpeed = initialMoveSpeed(),
          fireInterval = initialFireInterval(),
          maxHp = initialMaxHp(),
          multiShot = 1,
          damage = 1 }
}
