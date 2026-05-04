// Vec2 — 2D vector operations module (Godot Vector2 inspired)

mod Vec2 {
    import java.lang.Math

    pub type alias Vec2 = {x = Float64, y = Float64}

    // ========================================================================
    // Math Helpers
    // ========================================================================

    /// 平方根（pure キャスト）
    pub def sqrt(v: Float64): Float64 =
        unchecked_cast(Math.sqrt(v) as _ \ {})

    /// 円周率
    pub def pi(): Float64 = 3.14159265358979

    /// sin（pure キャスト）
    pub def sin(x: Float64): Float64 =
        unchecked_cast(Math.sin(x) as _ \ {})

    /// cos（pure キャスト）
    pub def cos(x: Float64): Float64 =
        unchecked_cast(Math.cos(x) as _ \ {})

    /// atan2（pure キャスト）
    pub def atan2(y: Float64, x: Float64): Float64 =
        unchecked_cast(Math.atan2(y, x) as _ \ {})


    // ========================================================================
    // Constants
    // ========================================================================

    pub def zero(): Vec2 = {x = 0.0, y = 0.0}

    pub def one(): Vec2 = {x = 1.0, y = 1.0}

    pub def up(): Vec2 = {x = 0.0, y = -1.0}

    pub def down(): Vec2 = {x = 0.0, y = 1.0}

    pub def left(): Vec2 = {x = -1.0, y = 0.0}

    pub def right(): Vec2 = {x = 1.0, y = 0.0}

    // ========================================================================
    // Arithmetic
    // ========================================================================

    pub def add(a: Vec2, b: Vec2): Vec2 =
        {x = a#x + b#x, y = a#y + b#y}

    pub def sub(a: Vec2, b: Vec2): Vec2 =
        {x = a#x - b#x, y = a#y - b#y}

    pub def mul(v: Vec2, s: Float64): Vec2 =
        {x = v#x * s, y = v#y * s}

    pub def div(v: Vec2, s: Float64): Vec2 =
        {x = v#x / s, y = v#y / s}

    pub def neg(v: Vec2): Vec2 =
        {x = -1.0 * v#x, y = -1.0 * v#y}

    // ========================================================================
    // Length & Distance
    // ========================================================================

    pub def lengthSquared(v: Vec2): Float64 =
        v#x * v#x + v#y * v#y

    pub def length(v: Vec2): Float64 =
        sqrt(lengthSquared(v))

    pub def distanceSquaredTo(a: Vec2, b: Vec2): Float64 =
        lengthSquared(sub(a, b))

    pub def distanceTo(a: Vec2, b: Vec2): Float64 =
        length(sub(a, b))

    // ========================================================================
    // Normalization & Dot/Cross
    // ========================================================================

    pub def normalized(v: Vec2): Vec2 =
        let len = length(v);
        if (len > 0.0) div(v, len) else zero()

    pub def dot(a: Vec2, b: Vec2): Float64 =
        a#x * b#x + a#y * b#y

    pub def cross(a: Vec2, b: Vec2): Float64 =
        a#x * b#y - a#y * b#x

    // ========================================================================
    // Reflect & Bounce
    // ========================================================================

    /// Reflect v off a surface with normal n: v - 2 * dot(v, n) * n
    pub def reflect(v: Vec2, n: Vec2): Vec2 =
        let d = dot(v, n);
        sub(v, mul(n, 2.0 * d))

    /// Bounce v off a surface with normal n: -reflect(v, n)
    pub def bounce(v: Vec2, n: Vec2): Vec2 =
        neg(reflect(v, n))

    // ========================================================================
    // Angle & Rotation
    // ========================================================================

    pub def angle(v: Vec2): Float64 =
        atan2(v#y, v#x)

    pub def angleTo(a: Vec2, b: Vec2): Float64 =
        atan2(cross(a, b), dot(a, b))

    pub def rotated(v: Vec2, phi: Float64): Vec2 =
        let c = cos(phi);
        let s = sin(phi);
        {x = v#x * c - v#y * s, y = v#x * s + v#y * c}

    pub def directionTo(a: Vec2, b: Vec2): Vec2 =
        normalized(sub(b, a))

    // ========================================================================
    // Clamp & Interpolation
    // ========================================================================

    pub def clamp(v: Vec2, minV: Vec2, maxV: Vec2): Vec2 =
        {x = Float64.max(minV#x, Float64.min(maxV#x, v#x)),
         y = Float64.max(minV#y, Float64.min(maxV#y, v#y))}

    pub def clampSymmetric(v: Vec2, halfExtents: Vec2): Vec2 =
        clamp(v, neg(halfExtents), halfExtents)

    pub def moveToward(origin: Vec2, target: Vec2, delta: Float64): Vec2 =
        let diff = sub(target, origin);
        let dist = length(diff);
        if (dist <= delta or dist <= 0.0) target
        else add(origin, mul(div(diff, dist), delta))

    pub def lerp(a: Vec2, b: Vec2, t: Float64): Vec2 =
        {x = a#x + (b#x - a#x) * t, y = a#y + (b#y - a#y) * t}

    // ========================================================================
    // Component Operations
    // ========================================================================

    pub def abs(v: Vec2): Vec2 =
        {x = Float64.abs(v#x), y = Float64.abs(v#y)}

    pub def sign(v: Vec2): Vec2 =
        let sx = if (v#x > 0.0) 1.0 else if (v#x < 0.0) -1.0 else 0.0;
        let sy = if (v#y > 0.0) 1.0 else if (v#y < 0.0) -1.0 else 0.0;
        {x = sx, y = sy}

    pub def min(a: Vec2, b: Vec2): Vec2 =
        {x = Float64.min(a#x, b#x), y = Float64.min(a#y, b#y)}

    pub def max(a: Vec2, b: Vec2): Vec2 =
        {x = Float64.max(a#x, b#x), y = Float64.max(a#y, b#y)}

    pub def floor(v: Vec2): Vec2 =
        {x = Math.floor(v#x), y = Math.floor(v#y)}

    pub def ceil(v: Vec2): Vec2 =
        {x = Math.ceil(v#x), y = Math.ceil(v#y)}

    pub def round(v: Vec2): Vec2 =
        {x = Math.rint(v#x), y = Math.rint(v#y)}

    // ========================================================================
    // Utility
    // ========================================================================

    pub def isNormalized(v: Vec2): Bool =
        let lsq = lengthSquared(v);
        Float64.abs(lsq - 1.0) < 0.0001

    pub def isZeroApprox(v: Vec2): Bool =
        Float64.abs(v#x) < 0.0001 and Float64.abs(v#y) < 0.0001

    pub def limitLength(v: Vec2, maxLen: Float64): Vec2 =
        let lsq = lengthSquared(v);
        if (lsq > maxLen * maxLen)
            mul(normalized(v), maxLen)
        else v

    pub def projected(v: Vec2, onto: Vec2): Vec2 =
        let d = dot(onto, onto);
        if (d > 0.0) mul(onto, dot(v, onto) / d) else zero()

    pub def slide(v: Vec2, n: Vec2): Vec2 =
        sub(v, mul(n, dot(v, n)))
}
