mod RandomUtil {
    use Math.Random

    pub def pick(l: List[a]): Option[a] \ Math.Random =
        let len = List.length(l);
        if (len == 0) None
        else
            let r = Math.Random.randomFloat64();
            let idx = Float64.truncateToInt32(Float64.floor(r * Int32.toFloat64(len)));
            List.nth(idx, l)

    /// min 以上 max 未満のランダムな Float64 を返す
    pub def randomRange(min: Float64, max: Float64): Float64 \ Math.Random =
        min + Math.Random.randomFloat64() * (max - min)
}
