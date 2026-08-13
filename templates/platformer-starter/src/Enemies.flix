// Enemies — 敵 3 種(歩く a / 飛ぶ b / 撃つ z)と弾。すべて純粋。
// 倒し方は踏みつけだけ(このゲームに武器は無い)。
//   歩く: 巡回。壁に当たるか、次の一歩の足元が崖なら向きを変える。
//   飛ぶ: 湧き場所を中心に上下へ揺れる(時刻の純関数 — 状態を持たない)。
//   撃つ: 主役が同じ高さ帯で射程内に入ると、向きを合わせて一定間隔で弾を出す。
mod Enemies {

    pub type alias Enemy = {
        kind = String,        // walker / flyer / shooter
        home = Vec2.Vec2,     // 湧き場所(飛ぶ敵の中心・撃つ敵の座)
        pos = Vec2.Vec2,
        vy = Float64,         // 歩く敵の落下速度
        dir = Float64,        // 向き(+1 右 / -1 左)
        cool = Float64        // 撃つ敵の残り待ち秒
    }

    pub type alias Shot = { pos = Vec2.Vec2, vel = Vec2.Vec2, ttl = Float64 }

    /// 当たり箱の大きさ(px)。種類ごとに固定(絵と揃える)。
    pub def sizeOf(kind: String): Vec2.Vec2 =
        if (kind == "walker") { x = 14.0, y = 11.0 }
        else if (kind == "flyer") { x = 13.0, y = 10.0 }
        else { x = 13.0, y = 15.0 }

    pub def make(kind: String, cell: Stage.Cell): Enemy =
        let ts = Physics.tileSize();
        let size = sizeOf(kind);
        // 足元をマスの下端に合わせる(飛ぶ敵はマス中心)。
        let cx = (Int32.toFloat64(cell#x) + 0.5) * ts;
        let pos = if (kind == "flyer") Stage.centerOf(cell)
                  else { x = cx, y = Int32.toFloat64(cell#y + 1) * ts - size#y * 0.5 };
        { kind = kind, home = pos, pos = pos, vy = 0.0, dir = -1.0, cool = 0.0 }

    /// 1 tick。player は撃つ敵の索敵にだけ使う。返りは (敵, 新しく出た弾)。
    pub def step(t: Physics.Terrain, doc: EnemyDoc.Doc, dt: Float64, time: Float64,
                 player: Vec2.Vec2, e: Enemy): (Enemy, List[Shot]) =
        if (e#kind == "walker") (walk(t, doc, dt, e), Nil)
        else if (e#kind == "flyer") (fly(doc, time, e), Nil)
        else shoot(doc, dt, player, e)

    def walk(t: Physics.Terrain, doc: EnemyDoc.Doc, dt: Float64, e: Enemy): Enemy =
        let size = sizeOf(e#kind);
        let vy = Float64.min(e#vy + 900.0 * dt, 480.0);
        let slid = Physics.slideBox(t, size, dt, false, 0.0,
                                    e#pos, { x = e#dir * doc#walkSpeed, y = vy });
        let turned = slid#hitX or (slid#onGround and cliffAhead(t, size, e#dir, slid#pos));
        { pos = slid#pos, vy = slid#vel#y,
          dir = if (turned) -e#dir else e#dir | e }

    /// 次の一歩の足元(進行方向の縁の 1 つ先・半タイル下)が空なら崖。
    def cliffAhead(t: Physics.Terrain, size: Vec2.Vec2, dir: Float64, pos: Vec2.Vec2): Bool =
        let probeX = pos#x + dir * (size#x * 0.5 + 2.0);
        let probeY = pos#y + size#y * 0.5 + 2.0;
        let cx = Physics.tileOf(probeX);
        let cy = Physics.tileOf(probeY);
        not (t#solid(cx, cy) or t#oneWay(cx, cy))

    /// 上下の揺れは時刻の純関数(巻き戻し・描き出しと相性が良い)。
    def fly(doc: EnemyDoc.Doc, time: Float64, e: Enemy): Enemy =
        let amp = doc#flyAmpTiles * Physics.tileSize();
        let phase = 2.0 * 3.14159265 * time / doc#flyPeriod;
        { pos = { x = e#home#x, y = e#home#y + amp * Vec2.sin(phase) } | e }

    def shoot(doc: EnemyDoc.Doc, dt: Float64, player: Vec2.Vec2, e: Enemy):
             (Enemy, List[Shot]) =
        let dx = player#x - e#pos#x;
        let dy = player#y - e#pos#y;
        let inRange = Float64.abs(dx) <= doc#shotRangeTiles * Physics.tileSize()
                      and Float64.abs(dy) <= Physics.tileSize() * 2.5;
        let dir = if (dx < 0.0) -1.0 else 1.0;
        let cool = Float64.max(0.0, e#cool - dt);
        if (inRange and cool <= 0.0)
            ({ dir = dir, cool = doc#shotCooldown | e },
             { pos = { x = e#pos#x + dir * 10.0, y = e#pos#y - 2.0 },
               vel = { x = dir * doc#shotSpeed, y = 0.0 }, ttl = 3.0 } :: Nil)
        else ({ dir = if (inRange) dir else e#dir, cool = cool | e }, Nil)

    /// 弾を進める。壁に刺さるか寿命で消える(None)。
    pub def stepShot(t: Physics.Terrain, dt: Float64, s: Shot): Option[Shot] =
        let np = Vec2.add(s#pos, Vec2.mul(s#vel, dt));
        let cx = Physics.tileOf(np#x);
        let cy = Physics.tileOf(np#y);
        let ttl = s#ttl - dt;
        if (ttl <= 0.0 or t#solid(cx, cy)) None
        else Some({ pos = np, ttl = ttl | s })

    pub def rectOf(e: Enemy): Rect2.Rect2 =
        let half = Vec2.mul(sizeOf(e#kind), 0.5);
        { position = Vec2.sub(e#pos, half), size = sizeOf(e#kind) }

    pub def shotRect(s: Shot): Rect2.Rect2 =
        { position = Vec2.sub(s#pos, { x = 3.0, y = 3.0 }), size = { x = 6.0, y = 6.0 } }
}
