// Random — 乱数の合成層（第一級の Generator と、種を書かない Rng エフェクト）。
mod Random {

    /// 乱数の出どころ。同じ Seed からは常に同じ列が出るので、結果を再現できる。
    pub enum Seed(Int64)

    /// 整数から Seed を作る。再現可能な乱数列が欲しいときの出発点。
    /// 例: `Random.initialSeed(42i64)`
    pub def initialSeed(s: Int64): Seed = Seed.Seed(s)

    // splitmix64 の仕上げ混合。`>>>` は符号拡張で上位が 1 埋めになるので使わず、
    // ゼロ埋め保証の logicalRightShift を使う。定数は
    // 0xBF58476D1CE4E5B9 / 0x94D049BB133111EB を signed Int64 で表したもの。
    def mix(z0: Int64): Int64 =
        let z1 = Int64.bitwiseXor(z0, Int64.logicalRightShift(dist = 30, z0)) * -4658895280553007687i64;
        let z2 = Int64.bitwiseXor(z1, Int64.logicalRightShift(dist = 27, z1)) * -7723592293110705685i64;
        Int64.bitwiseXor(z2, Int64.logicalRightShift(dist = 31, z2))

    // gamma 0x9E3779B97F4A7C15 を signed Int64 で表したもの。
    def next64(st: Seed): (Int64, Seed) =
        let Seed.Seed(s) = st;
        let s1 = s + -7046029254386353131i64;
        (mix(s1), Seed.Seed(s1))

    def nextUnit(st: Seed): (Float64, Seed) =
        let (z, st1) = next64(st);
        let top53 = Int64.logicalRightShift(dist = 11, z);
        (Int64.toFloat64(top53) / 9007199254740992.0, st1)

    // ── 値層: 第一級の Generator ──

    // stdlib の Functor/Monad（forM が使える）は実装できない: 包む関数を純粋 {} 固定にして
    // いるため、トレイトが要求するエフェクト多相の map（f: a -> b \ ef）を通せない（E5252 で実測）。
    // do 記法が欲しい合成は、下の Rng エフェクトの直書きが代わりを務める。
    /// 乱数の作り方を表す値。`Generator[Int32]` なら整数の引き方、`Generator[String]` なら文字列の引き方。
    /// `step` / `sample` に渡して初めて実際の値になる。
    pub enum Generator[a](Seed -> (a, Seed))

    /// Generator に Seed を与えて 1 回引く。(引いた値, 次の Seed) を返す。
    /// 例: `let (n, next) = Random.step(Random.int(lo = 0, hi = 6), seed)`
    pub def step(gen: Generator[a], st: Seed): (a, Seed) =
        let Generator.Generator(fn) = gen;
        fn(st)

    /// 毎回同じ値を返す Generator。`andThen` と組み合わせて分岐の終端に使うと便利。
    /// 例: `Random.constant(0)`
    pub def constant(x: a): Generator[a] =
        Generator.Generator(st -> (x, st))

    /// Generator が作る値を関数で変換する。
    /// 例: `Random.map(n -> n * 2, Random.int(lo = 0, hi = 6))`
    pub def map(f: a -> b, gen: Generator[a]): Generator[b] =
        Generator.Generator(st -> {
            let (a, st1) = step(gen, st);
            (f(a), st1)
        })

    /// 2 つの Generator を組み合わせて 1 つにする（ga → gb の順に引く）。
    /// 例: `Random.map2(x -> y -> (x, y), Random.int(lo = 0, hi = 10), Random.int(lo = 0, hi = 10))`
    pub def map2(f: a -> b -> c, ga: Generator[a], gb: Generator[b]): Generator[c] =
        Generator.Generator(st -> {
            let (a, st1) = step(ga, st);
            let (b, st2) = step(gb, st1);
            (f(a)(b), st2)
        })

    /// 3 つの Generator を組み合わせる（ga → gb → gc の順に引く）。
    pub def map3(f: a -> b -> c -> d, ga: Generator[a], gb: Generator[b], gc: Generator[c]): Generator[d] =
        Generator.Generator(st -> {
            let (a, st1) = step(ga, st);
            let (b, st2) = step(gb, st1);
            let (c, st3) = step(gc, st2);
            (f(a)(b)(c), st3)
        })

    /// 引いた値を見て、次に使う Generator を決める（前の結果に依存する乱数）。
    /// 例: `Random.int(lo = 1, hi = 5) |> Random.andThen(n -> Random.list(n, Random.int(lo = 0, hi = 100)))`
    pub def andThen(f: a -> Generator[b], gen: Generator[a]): Generator[b] =
        Generator.Generator(st -> {
            let (a, st1) = step(gen, st);
            step(f(a), st1)
        })

    /// [lo, hi) の一様な整数。hi は含まない（排他）。
    /// 例: `Random.int(lo = 0, hi = 6)`  // 0〜5 のどれか
    pub def int(lo: {lo = Int32}, hi: {hi = Int32}): Generator[Int32] =
        Generator.Generator(st -> {
            let (u, st1) = nextUnit(st);
            let span = hi#hi - lo#lo;
            // 空区間（hi<=lo）で lo を返すのは、oneOf 経由で空リストを引いても破綻させないため。
            if (span <= 0)
                (lo#lo, st1)
            else
                (lo#lo + Float64.truncateToInt32(Float64.floor(u * Int32.toFloat64(span))), st1)
        })

    /// 候補から等確率で 1 つ選ぶ。first と rest に分けているので、必ず 1 つは選べる（空にならない）。
    /// 例: `Random.uniform("赤", "青" :: "緑" :: Nil)`
    pub def uniform(first: a, rest: List[a]): Generator[a] =
        let all = first :: rest;
        map(i -> List.nth(i, all) |> Option.getWithDefault(first), int(lo = 0, hi = List.length(all)))

    /// リストから等確率で 1 つ選ぶ。空リストなら None。
    /// 例: `Random.oneOf(candidates)`  // Generator[Option[a]]
    pub def oneOf(xs: List[a]): Generator[Option[a]] =
        // 空でも種を 1 つ進めるのは、空のとき引かない分岐にすると呼び側の draw 位置がズレるため。
        map(i -> List.nth(i, xs), int(lo = 0, hi = List.length(xs)))

    /// 同じ Generator を n 回引いてリストにする。
    /// 例: `Random.list(5, Random.int(lo = 0, hi = 6))`  // 6 面ダイス 5 個
    pub def list(n: Int32, gen: Generator[a]): Generator[List[a]] =
        Generator.Generator(st -> stepN(n, gen, st, Nil))

    // prepend して最後に反転するのは、append の O(n^2) を避けつつ引いた順を保つため。
    def stepN(n: Int32, gen: Generator[a], st: Seed, acc: List[a]): (List[a], Seed) =
        if (n <= 0)
            (List.reverse(acc), st)
        else {
            let (x, st1) = step(gen, st);
            stepN(n - 1, gen, st1, x :: acc)
        }

    // ── エフェクト層: 種を書かない直書き ──

    // op を種の get/put だけにしたのは、実ドローを sample に集約して値層と同じ種で必ず一致させるため。
    /// 種を手で持ち回さずに乱数を引くためのエフェクト。`sample` で引き、`withSeed` で走らせる。
    pub eff Rng {
        def get(): Seed
        def put(next: Seed): Unit
    }

    /// Generator を効果の中で 1 回引く（種は handler が裏で進める）。
    /// 例: `let n = Random.sample(Random.int(lo = 0, hi = 6))`
    pub def sample(gen: Generator[a]): a \ Rng =
        let (x, st1) = step(gen, Rng.get());
        Rng.put(st1);
        x

    /// Rng エフェクトの handler。開始 Seed を与えて効果コードを走らせ、
    /// (結果, 最終 Seed) を返す。返ってきた最終 Seed を次の withSeed に渡せば続きを引ける。
    /// with 記法で handler として使う:
    /// ```
    /// let (total, next) = run {
    ///     let a = Random.sample(Random.int(lo = 1, hi = 7));  // サイコロを 1 回
    ///     let b = Random.sample(Random.int(lo = 1, hi = 7));  // もう 1 回
    ///     a + b                                               // 2 個の合計
    /// } with Random.withSeed(Random.initialSeed(42i64));
    /// ```
    /// total = 2 個ぶんの合計、next = 続きを引くための Seed。
    pub def withSeed(seed: Seed, thunk: Unit -> a \ ef): (a, Seed) \ (ef - Rng) =
        // region で Ref を閉じるのは、+ r を残さず (a, Seed) を純粋に返し、呼び側が最終種を受け取って再現できるようにするため。
        region rc {
            let stRef = Ref.fresh(rc, seed);
            let result = run {
                thunk()
            } with handler Rng {
                def get(k) = k(Ref.get(stRef))
                def put(next, k) = {
                    Ref.put(next, stRef);
                    k()
                }
            };
            (result, Ref.get(stRef))
        }

    /// 効果で平らに書いた組み立てを、再利用できる Generator 値にする（sample の逆向き）。
    /// 例: `Random.toGen(() -> { let n = Random.sample(Random.int(lo = 1, hi = 5)); ... })`
    pub def toGen(thunk: Unit -> a \ Rng): Generator[a] =
        Generator.Generator(st -> withSeed(st, thunk))

}
