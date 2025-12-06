access(all) contract FlowCreditMarketMath {

    access(all) let one: UFix128
    access(all) let zero: UFix128
    access(self) let ufix64Step: UFix128
    access(self) let ufix64HalfStep: UFix128

    access(all) let decimals: UInt8
    access(all) let ufix64Decimals: UInt8

    access(all) enum RoundingMode: UInt8 {
        access(all) case RoundDown
        access(all) case RoundUp
        access(all) case RoundHalfUp
        access(all) case RoundEven
    }

    /// Fast exponentiation for UFix128 with a non-negative integer exponent (seconds)
    /// Uses exponentiation-by-squaring with truncation at each multiply (fixed-point semantics)
    access(all) view fun powUFix128(_ base: UFix128, _ expSeconds: UFix64): UFix128 {
        if expSeconds == 0.0 { return self.one }
        if base == self.one { return self.one }
        var result: UFix128 = self.one
        var b: UFix128 = base
        var e: UFix64 = expSeconds
        // Floor the seconds to an integer count
        var remaining: UInt64 = UInt64(e)
        while remaining > 0 {
            if remaining % UInt64(2) == UInt64(1) {
                result = result * b
            }
            b = b * b
            remaining = remaining / UInt64(2)
        }
        return result
    }


    access(all) view fun div(_ x: UFix128, _ y: UFix128): UFix128 {
        pre {
            y > 0.0 as UFix128: "Division by zero"
        }
        return x / y
    }

    access(all) view fun toUFix128(_ value: UFix64): UFix128 {
        return UFix128(value)
    }

    access(all) view fun toUFix64(_ value: UFix128, rounding: RoundingMode): UFix64 {
        let truncated: UFix64 = UFix64(value)
        let truncatedAs128: UFix128 = UFix128(truncated)
        let remainder: UFix128 = value - truncatedAs128

        if remainder == 0.0 as UFix128 {
            return truncated
        }

        switch rounding {
        case self.RoundingMode.RoundDown:
            return truncated
        case self.RoundingMode.RoundUp:
            return self.roundUp(truncated)
        case self.RoundingMode.RoundHalfUp:
            return remainder >= self.ufix64HalfStep ? self.roundUp(truncated) : truncated
        case self.RoundingMode.RoundEven:
            return self.roundHalfToEven(truncated, remainder)
        }
        return truncated
    }

    access(all) view fun toUFix64Round(_ value: UFix128): UFix64 {
        return self.toUFix64(value, rounding: self.RoundingMode.RoundHalfUp)
    }

    access(all) view fun toUFix64RoundDown(_ value: UFix128): UFix64 {
        return self.toUFix64(value, rounding: self.RoundingMode.RoundDown)
    }

    access(all) view fun toUFix64RoundUp(_ value: UFix128): UFix64 {
        return self.toUFix64(value, rounding: self.RoundingMode.RoundUp)
    }

    access(self) view fun roundUp(_ base: UFix64): UFix64 {
        let increment: UFix64 = 0.00000001
        return base >= UFix64.max - increment ? UFix64.max : base + increment
    }

    access(self) view fun roundHalfToEven(_ base: UFix64, _ remainder: UFix128): UFix64 {
        if remainder < self.ufix64HalfStep {
            return base
        }
        if remainder > self.ufix64HalfStep {
            return self.roundUp(base)
        }
        let scaled: UFix64 = base * 100_000_000.0
        let scaledInt: UInt64 = UInt64(scaled)
        return scaledInt % UInt64(2) == UInt64(1) ? self.roundUp(base) : base
    }

    // ========== Adaptive Curve IRM Math Functions ==========

    /// Struct to represent signed fixed-point numbers (since UFix128 is unsigned)
    /// Stores magnitude as UFix128 and sign as Bool
    access(all) struct SignedUFix128 {
        access(all) let value: UFix128
        access(all) let isNegative: Bool

        init(value: UFix128, isNegative: Bool) {
            self.value = value
            self.isNegative = isNegative
        }
    }

    /// Constants for exponential function
    /// ln(2) = 0.693147180559945309
    access(all) let LN_2: UFix128

    /// ln(1e-18) for UFix128 (lower bound for exp)
    /// ln(1e-18) = -41.446531673892822312
    /// Matches Solidity: LN_WEI_INT
    access(all) let LN_MIN: UFix128

    /// Upper bound for wExp to avoid overflow
    /// ln(type(int256).max / 1e36) = 93.859467695000404319 (Solidity bound)
    /// Using a conservative bound to match Solidity behavior
    access(all) let WEXP_UPPER_BOUND: UFix128

    /// The value of wExp(WEXP_UPPER_BOUND)
    /// Matches Solidity: WEXP_UPPER_VALUE
    access(all) let WEXP_UPPER_VALUE: UFix128

    /// Returns an approximation of exp(x) for signed x
    /// Uses 2nd-order Taylor series approximation
    /// For negative x, computes 1/exp(|x|) for better accuracy
    access(all) fun wExp(_ x: SignedUFix128): UFix128 {
        // If x < ln(1e-24), exp(x) ≈ 0
        if x.isNegative && x.value >= self.LN_MIN {
            return self.zero
        }

        // Clip to upper bound to avoid overflow
        if !x.isNegative && x.value >= self.WEXP_UPPER_BOUND {
            return self.WEXP_UPPER_VALUE
        }

        // For negative x, compute 1/exp(|x|) to avoid sign issues
        if x.isNegative {
            let positiveX = SignedUFix128(value: x.value, isNegative: false)
            let expPositive = self.wExp(positiveX)

            // Return 1/exp(|x|)
            if expPositive > 0.0 {
                return self.one / expPositive
            } else {
                return self.WEXP_UPPER_VALUE
            }
        }

        // Positive x path: Decompose x as x = q * ln(2) + r
        // where q is an integer and -ln(2)/2 <= r <= ln(2)/2
        let halfLn2 = self.LN_2 / 2.0
        let xValue = x.value

        // Calculate q (number of factors of 2)
        let qRaw = (xValue + halfLn2) / self.LN_2
        let q = Int64(UFix64(qRaw))
        let qTimesLn2 = UFix128(UInt64(q)) * self.LN_2

        // Calculate remainder r
        var rValue: UFix128 = 0.0
        var rIsNegative: Bool = false

        if qTimesLn2 <= xValue {
            rValue = xValue - qTimesLn2
            rIsNegative = false
        } else {
            rValue = qTimesLn2 - xValue
            rIsNegative = true
        }

        // Compute e^r with 2nd-order Taylor polynomial
        var expR = self.one

        if !rIsNegative {
            // For positive r: e^r ≈ 1 + r + r²/2
            expR = expR + rValue
            expR = expR + (rValue * rValue / 2.0)
        } else {
            // For negative r: e^(-r) ≈ 1 - r + r²/2
            // Rearrange to avoid underflow: 1 + r²/2 - r
            let rSquaredDiv2 = rValue * rValue / 2.0
            if rValue <= self.one + rSquaredDiv2 {
                expR = self.one + rSquaredDiv2 - rValue
            } else {
                // Result would be very small, return near zero
                return 0.00000001
            }
        }

        // Return e^x = 2^q * e^r
        // Multiply by 2^q
        let shift = UInt64(q)
        var result = expR
        var i: UInt64 = 0
        while i < shift {
            result = result * 2.0
            if result >= UFix128.max / 2.0 {
                return self.WEXP_UPPER_VALUE
            }
            i = i + 1
        }
        return result
    }

    /// Bounds a value between low and high
    access(all) view fun bound(_ x: UFix128, _ low: UFix128, _ high: UFix128): UFix128 {
        if x < low {
            return low
        }
        if x > high {
            return high
        }
        return x
    }

    /// Safe multiplication for SignedUFix128
    access(all) fun signedMul(_ a: SignedUFix128, _ b: SignedUFix128): SignedUFix128 {
        let resultValue = a.value * b.value
        // XOR of signs: negative if signs differ
        let resultIsNegative = a.isNegative != b.isNegative
        return SignedUFix128(value: resultValue, isNegative: resultIsNegative)
    }

    /// Safe division for SignedUFix128
    access(all) fun signedDiv(_ a: SignedUFix128, _ b: SignedUFix128): SignedUFix128 {
        assert(b.value > 0.0, message: "Division by zero")
        let resultValue = a.value / b.value
        let resultIsNegative = a.isNegative != b.isNegative
        return SignedUFix128(value: resultValue, isNegative: resultIsNegative)
    }

    init() {
        self.one = 1.0 as UFix128
        self.zero = 0.0 as UFix128
        self.ufix64Step = 0.00000001 as UFix128
        self.ufix64HalfStep = self.ufix64Step / 2.0 as UFix128
        self.decimals = 24
        self.ufix64Decimals = 8

        // Initialize exponential function constants
        self.LN_2 = 0.693147180559945309
        // ln(1e-18) to match Solidity's LN_WEI_INT
        self.LN_MIN = 41.446531673892822312
        // Match Solidity's WEXP_UPPER_BOUND
        self.WEXP_UPPER_BOUND = 93.859467695000404319
        // Solidity's WEXP_UPPER_VALUE is ~5.77e37, which exceeds Cadence UFix128 literal limits
        // We use a large value that serves as an effective upper bound for adaptive IRM
        // e^93.86 is astronomically large; for practical IRM use (linearAdaptation < 10),
        // e^10 ~= 22026, so 1 billion provides ample headroom
        self.WEXP_UPPER_VALUE = 1000000000.0  // 1.0e9
    }
}
