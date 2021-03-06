const std = @import("../../std.zig");
const testing = std.testing;
const math = std.math;
const cmath = math.complex;
const Complex = cmath.Complex;

pub fn log(z: var) Complex(@typeOf(z.re)) {
    const T = @typeOf(z.re);
    const r = cmath.abs(z);
    const phi = cmath.arg(z);

    return Complex(T).new(math.ln(r), phi);
}

const epsilon = 0.0001;

test "complex.clog" {
    const a = Complex(f32).new(5, 3);
    const c = log(a);

    testing.expect(math.approxEq(f32, c.re, 1.763180, epsilon));
    testing.expect(math.approxEq(f32, c.im, 0.540419, epsilon));
}
