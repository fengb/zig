const std = @import("std");
const atomic = @import("atomic.zig");

test "makeAtomicRmw" {
    inline for ([_]type{ u8, u16, u32, u64, u128 }) |T| {
        inline for ([_]std.builtin.AtomicRmwOp{ .Xchg, .Add, .Sub, .And, .Or, .Xor }) |op| {
            const old: T = 128;
            const new: T = 42;
            var expected = old;
            _ = @atomicRmw(T, &expected, op, new, .Monotonic);

            const func = atomic.makeAtomicRmw(T, op);
            var actual = old;
            std.testing.expectEqual(old, func(&actual, new, 1));
            std.testing.expectEqual(expected, actual);
        }
    }
}
