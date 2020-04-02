const std = @import("std");

const SPINLOCK_COUNT = 1 << 10;
const SPINLOCK_MASK = SPINLOCK_COUNT - 1;

fn isLockFreeSize(size: usize) bool {
    return switch (size) {
        1 => isLockFree(u8),
        2 => isLockFree(u16),
        4 => isLockFree(u32),
        8 => isLockFree(u64),
        16 => isLockFree(u128),
        else => false,
    };
}

fn isLockFree(comptime T: type) bool {
    return false;
}

// TODO: port over FreeBSD and Apple specific spinlocks
// https://github.com/llvm-mirror/compiler-rt/blob/master/lib/builtins/atomic.c
const Lock = enum {
    Unlocked,
    Locked,

    /// This is a release operation.
    fn unlock(l: *Lock) void {
        @atomicStore(Lock, l, .Unlocked, .Release);
    }

    /// In the current implementation, this is potentially unbounded in the contended case.
    fn lock(l: *Lock) void {
        while (@cmpxchgWeak(Lock, l, .Unlocked, .Locked, .Acquire, .Relaxed) != null) {}
    }

    var locks = [_]Lock{.Unlocked} ** SPINLOCK_COUNT;

    fn forPtr(comptime T: type, ptr: *T) *Lock {
        var hash = @ptrToInt(ptr);
        // Disregard the lowest 4 bits.  We want all values that may be part of the
        // same memory operation to hash to the same value and therefore use the same
        // lock.
        hash >>= 4;
        // Use the next bits as the basis for the hash
        const low = hash & SPINLOCK_MASK;
        // Now use the high(er) set of bits to perturb the hash, so that we don't
        // get collisions from atomic fields in a single object
        hash >>= 16;
        hash ^= low;
        // Return a pointer to the word to use
        return locks[hash & SPINLOCK_MASK];
    }
};

pub fn atomicLoadN(comptime T: type, ptr: *T, order: std.builtin.AtomicOrder) T {
    if (isLockFree(T)) {
        return @atomicLoad(T, ptr, order);
    }

    const l = Lock.forPtr(ptr);
    l.lock();
    defer l.unlock();

    return ptr.*;
}

pub fn atomicStoreN(comptime T: type, ptr: *T, val: T, order: std.builtin.AtomicOrder) void {
    if (isLockFree(T)) {
        return @atomicStore(T, ptr, val, order);
    }

    const l = Lock.forPtr(ptr);
    l.lock();
    defer l.unlock();

    ptr.* = val;
}

pub fn atomicCompareExchangeN(comptime T: type, ptr: *T, expected: *T, new: T, success: std.builtin.AtomicOrder, fail: std.builtin.AtomicOrder) usize {
    if (isLockFree(T)) {
        return @cmpxchgStrong(T, ptr, expected.*, new, success, fail);
    }

    const l = Lock.forPtr(ptr);
    l.lock();
    defer l.unlock();

    if (ptr.* == expected.*) {
        ptr.* = new;
        return 1;
    }
    expected.* = ptr.*;
    return 0;
}

pub fn atomicRmwN(comptime T: type, comptime op: std.builtin.AtomicRmwOp, ptr: *T, val: T, order: std.builtin.AtomicOrder) T {
    if (isLockFree(T)) {
        return @atomicRmw(T, ptr, op, val, order);
    }

    const l = Lock.forPtr(ptr);
    l.lock();
    defer l.unlock();

    const prev = ptr.*;
    ptr.* = switch (op) {
        .Xchg => val,
        .Add => prev + val,
        .Sub => prev - val,
        .And => prev & val,
        .Or => prev | val,
        .Xor => prev ^ val,
        else => @compileError("atomicRmwN op " ++ @tagName(op) ++ " not defined"),
    };
    return prev;
}
