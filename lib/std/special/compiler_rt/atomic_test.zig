const std = @import("std");
const atomic = @import("atomic.zig");

const all_ints = [_]type{ u8, u16, u32, u64, u128 };

test "makeCompareExchange" {
    inline for (all_ints) |T| {
        const old: T = 128;
        const other: T = 5;
        const new: T = 42;

        const func = atomic.makeAtomicCompareExchange(T);
        {
            var dst = old;
            var src = old;
            std.testing.expectEqual(@as(usize, 1), func(&dst, &src, new, 1, 1));
            std.testing.expectEqual(new, dst);
            std.testing.expectEqual(old, src);
        }

        {
            var dst = old;
            var src = other;
            std.testing.expectEqual(@as(usize, 0), func(&dst, &src, new, 1, 1));
            std.testing.expectEqual(old, dst);
            std.testing.expectEqual(old, src);
        }
    }
}

test "makeAtomicRmw" {
    inline for (all_ints) |T| {
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
