///
/// Shape Survivors — Update（1 フレームの世界の進行：中央集権の純粋関数）
///
/// `step` は World 全体を 1 つの純粋関数で進める ── これは MVU の update そのもの（中央集権）。
/// 群れロジックは「薙ぎ＝矩形内の全敵を削る」「最大数＝総数」など 1 体では閉じない横断的計算なので、
/// per-node dispatch（敵 1 体＝1 ノードの process）にせず、ここに中央集権でまとめている。
///
/// エンジン非依存（Model と Vec2 だけに依存）。だから test/ で値だけでテストできる。
///
mod Update {

    /// 純粋な更新関数。1 フレーム分ゲームを進める。各段は World を受け取り World を返す純粋関数。
    pub def step(dt: Float64, direction: Vec2.Vec2, spawnCandidate: Vec2.Vec2,
                 spawnKind: Model.EnemyKind, world: Model.World): Model.World =
        world
            |> movePlayerStage(dt, direction)    // 自機を動かし、向き（左右）を更新
            |> moveEnemiesStage(dt)              // 全敵を自機へ寄せる
            |> spawnStage(dt, spawnCandidate, spawnKind)
            |> moveGemsStage(dt)                 // 近いジェムを吸い寄せる
            |> fireWhipStage(dt)                 // クールダウンで薙ぐ：矩形内の敵 hp を削り、閃きを足す
            |> cullDeadEnemiesStage              // hp<=0 を除去・ジェムをドロップ・kills 加算
            |> collectGemsStage                  // 触れたジェムを回収して xp に
            |> levelUpStage                      // xp が閾値を超えたらレベルアップ
            |> tickSlashesStage(dt)              // 閃きの寿命を減らし、消えたものを除去
            |> takeContactDamageStage(dt)        // 接触で HP-1、無敵を付与
            |> advanceClockStage(dt)             // 生存時間を進める

    /// 自機を入力方向へ動かし、向き（左右）も更新する段。水平入力が無ければ向きは前のまま。
    def movePlayerStage(dt: Float64, direction: Vec2.Vec2, world: Model.World): Model.World =
        { player = movePlayer(dt, direction, world#moveSpeed, world#player),
          facingRight = faceFrom(direction, world#facingRight) | world }

    /// 全ての敵を自機へ寄せる段（List.map で全要素を作り直す）。
    def moveEnemiesStage(dt: Float64, world: Model.World): Model.World =
        { enemies = world#enemies |> List.map(enemy -> chaseEnemy(dt, world#player, enemy)) | world }

    /// 一定間隔で画面端に敵（種類は外から渡る）を 1 体湧かす段。間隔は生存時間とともに短くなる（激化）。
    def spawnStage(dt: Float64, spawnCandidate: Vec2.Vec2, spawnKind: Model.EnemyKind,
                   world: Model.World): Model.World =
        let sinceSpawn = world#sinceSpawn + dt;
        let interval = Model.spawnIntervalAt(world#elapsed);
        if (sinceSpawn >= interval and List.length(world#enemies) < Model.maxEnemies())
            let newEnemy = {pos = spawnCandidate, kind = spawnKind, hp = Model.enemyHpFor(spawnKind)};
            { enemies = newEnemy :: world#enemies, sinceSpawn = 0.0 | world }
        else
            { sinceSpawn = sinceSpawn | world }

    /// 落ちているジェムのうち、自機に近いものを自機へ吸い寄せる段（List.map）。
    def moveGemsStage(dt: Float64, world: Model.World): Model.World =
        { gems = world#gems |> List.map(gem -> magnetGem(dt, world#player, gem)) | world }

    /// 薙ぎ（Whip）の段。クールダウンが満ちたら、向いた側（multiShot>=2 なら両側）の矩形内の敵 HP を
    /// 威力(damage)ぶん削り、閃き(Slash)を足す。ダメージはこの瞬間に即時適用（弾は飛ばさない）。
    def fireWhipStage(dt: Float64, world: Model.World): Model.World =
        let sinceFire = world#sinceFire + dt;
        if (sinceFire < world#fireInterval)
            { sinceFire = sinceFire | world }
        else {
            let sides = whipSides(world#facingRight, world#multiShot);  // 薙ぐ向きの List[Bool]
            let damaged = world#enemies |> List.map(enemy ->
                if (sides |> List.exists(right -> enemyInWhip(world#player, right, enemy)))
                    { hp = enemy#hp - world#damage | enemy }
                else
                    enemy);
            let newSlashes = sides |> List.map(right ->
                { pos = world#player, right = right, ttl = Model.slashTtl() });
            { enemies = damaged, slashes = newSlashes ::: world#slashes, sinceFire = 0.0 | world }
        }

    /// 薙ぐ向き。multiShot が 2 以上なら両側（右と左）、それ以外は向いている側だけ。
    def whipSides(facingRight: Bool, multiShot: Int32): List[Bool] =
        if (multiShot >= 2) true :: false :: Nil
        else facingRight :: Nil

    /// HP が尽きた敵を取り除く段。倒した敵は種類に応じた数のジェムを落とし、kills を加算する。
    /// 盤面のジェムが上限を超えたぶんは描画コスト対策として即 XP に変換する（落とさない）。
    def cullDeadEnemiesStage(world: Model.World): Model.World =
        let survivingEnemies = world#enemies |> List.filter(enemy -> enemy#hp > 0);
        let deadEnemies      = world#enemies |> List.filter(enemy -> enemy#hp <= 0);
        let allGems = (deadEnemies |> List.flatMap(gemsForEnemy)) ::: world#gems;
        let keptGems = allGems |> List.take(Model.maxGems());
        let overflow = Int32.max(0, List.length(allGems) - Model.maxGems());
        { enemies = survivingEnemies,
          gems = keptGems,
          xp = world#xp + overflow * Model.xpPerGem(),
          kills = world#kills + List.length(deadEnemies) | world }

    /// 倒した敵 1 体が落とすジェム（種類で数が変わる。全部その敵の位置に出す）。
    def gemsForEnemy(enemy: Model.Enemy): List[Model.Gem] =
        List.repeat(Model.gemsDroppedFor(enemy#kind), { pos = enemy#pos })

    /// 触れたジェムを回収して xp に足す段（filter で「拾った／残った」に二分）。
    def collectGemsStage(world: Model.World): Model.World =
        let collected = world#gems |> List.filter(gem -> gemPicked(world#player, gem));
        let remaining = world#gems |> List.filter(gem -> not gemPicked(world#player, gem));
        { gems = remaining,
          xp = world#xp + List.length(collected) * Model.xpPerGem() | world }

    /// レベルアップの段。xp が次レベルに必要な量に達したら level+1・xp を消費する（純粋）。
    def levelUpStage(world: Model.World): Model.World =
        let need = Model.xpThreshold(world#level);
        if (world#xp >= need)
            { level = world#level + 1, xp = world#xp - need | world }
        else
            world

    /// 閃き（Slash）の寿命を減らし、0 以下になったものを取り除く段（filterMap）。
    def tickSlashesStage(dt: Float64, world: Model.World): Model.World =
        let alive = world#slashes |> List.filterMap(slash ->
            let ttl = slash#ttl - dt;
            if (ttl > 0.0) Some({ ttl = ttl | slash }) else None);
        { slashes = alive | world }

    /// 接触ダメージの段。無敵が切れている時に敵と触れていたら HP-1 ＆ 無敵を付与。
    def takeContactDamageStage(dt: Float64, world: Model.World): Model.World =
        let invulnLeft = Float64.max(0.0, world#invulnLeft - dt);
        let touched = world#enemies |> List.exists(enemy -> playerTouches(world#player, enemy));
        if (touched and invulnLeft <= 0.0)
            { hp = world#hp - 1, invulnLeft = Model.invulnDuration() | world }
        else
            { invulnLeft = invulnLeft | world }

    /// 時計を進める段。生存時間（スコア）を足すだけ。死亡判定は presentation 側が hp を見て行う。
    def advanceClockStage(dt: Float64, world: Model.World): Model.World =
        { elapsed = world#elapsed + dt | world }

    // --- step の部品（純粋な計算） ---

    /// 自機を入力方向へ、与えられた速度で動かし、画面内に収める。
    pub def movePlayer(dt: Float64, direction: Vec2.Vec2, speed: Float64, position: Vec2.Vec2): Vec2.Vec2 =
        let velocity =
            if (Vec2.length(direction) > 0.0)
                Vec2.mul(Vec2.normalized(direction), speed * dt)  // 斜めでも速さ一定
            else
                Vec2.zero();
        clampToScreen(Vec2.add(position, velocity))

    /// 敵 1 体を、その種類の速度で自機へ近づける（kind/hp はそのまま保つ）。
    pub def chaseEnemy(dt: Float64, target: Vec2.Vec2, enemy: Model.Enemy): Model.Enemy =
        let toTarget = Vec2.sub(target, enemy#pos);
        let velocity =
            if (Vec2.length(toTarget) > 0.0)
                Vec2.mul(Vec2.normalized(toTarget), Model.enemySpeedFor(enemy#kind) * dt)
            else
                Vec2.zero();
        { pos = Vec2.add(enemy#pos, velocity) | enemy }

    /// 水平入力から「左右の向き」を更新する。右入力なら右、左入力なら左、水平入力が無ければ前のまま。
    pub def faceFrom(direction: Vec2.Vec2, currentRight: Bool): Bool =
        if (direction#x > 0.0) true
        else if (direction#x < 0.0) false
        else currentRight

    /// 敵が、向いた側の薙ぎの矩形内にいるか（純粋・軸並行ボックス判定）。
    /// `right` が true なら右側、false なら左側。自機の少し後ろ(whipBackMargin)から
    /// whipReach まで、上下は whipHalfHeight まで。
    pub def enemyInWhip(player: Vec2.Vec2, right: Bool, enemy: Model.Enemy): Bool =
        let dx = enemy#pos#x - player#x;
        let dy = enemy#pos#y - player#y;
        let signed = if (right) dx else 0.0 - dx;  // 向いた側を正にした横距離
        signed >= 0.0 - Model.whipBackMargin() and
        signed <= Model.whipReach() and
        Float64.abs(dy) <= Model.whipHalfHeight()

    /// ジェム 1 個を、自機が吸引半径内にいれば自機へ寄せる（外なら動かない）。
    pub def magnetGem(dt: Float64, player: Vec2.Vec2, gem: Model.Gem): Model.Gem =
        let toPlayer = Vec2.sub(player, gem#pos);
        let magnet = Model.gemMagnetRadius();
        if (Vec2.distanceSquaredTo(player, gem#pos) < magnet * magnet and Vec2.length(toPlayer) > 0.0)
            { pos = Vec2.add(gem#pos, Vec2.mul(Vec2.normalized(toPlayer), Model.gemSpeed() * dt)) }
        else
            gem

    /// ジェムを回収できる距離か（二乗距離で比較）。
    pub def gemPicked(player: Vec2.Vec2, gem: Model.Gem): Bool =
        Vec2.distanceSquaredTo(player, gem#pos) < Model.gemPickupRadius() * Model.gemPickupRadius()

    /// 自機と敵が触れているか（二乗距離で比較）。
    def playerTouches(player: Vec2.Vec2, enemy: Model.Enemy): Bool =
        let reach = Model.playerRadius() + Model.enemyRadius();
        Vec2.distanceSquaredTo(player, enemy#pos) < reach * reach

    /// 自機が画面の外に出ないよう、半径ぶん内側に収める。
    def clampToScreen(position: Vec2.Vec2): Vec2.Vec2 =
        let radius = Model.playerRadius();
        let maxX = Int32.toFloat64(Model.designWi()) - radius;
        let maxY = Int32.toFloat64(Model.designHi()) - radius;
        {x = Float64.max(radius, Float64.min(maxX, position#x)),
         y = Float64.max(radius, Float64.min(maxY, position#y))}
}
