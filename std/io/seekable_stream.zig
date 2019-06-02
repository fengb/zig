const std = @import("../std.zig");
const InStream = std.io.InStream;
const assert = std.debug.assert;

pub const SeekableStream = struct {
    const Self = @This();
    pub const Iface = std.Interface();

    pub const GetSeekPosError = error{
        SystemResources,
        Unseekable,
        Unexpected,
    };

    pub const SeekError = error{
        Overflow,
        Unseekable,
        Unexpected,
        EndOfStream,
    };

    iface: ?Iface,

    seekToFn: fn (self: Self, pos: u64) SeekError!void,
    seekForwardFn: fn (self: Self, pos: i64) SeekError!void,

    getPosFn: fn (self: Self) GetSeekPosError!u64,
    getEndPosFn: fn (self: Self) GetSeekPosError!u64,

    pub fn seekTo(self: Self, pos: u64) !void {
        return self.seekToFn(self, pos);
    }

    pub fn seekForward(self: Self, amt: i64) !void {
        return self.seekForwardFn(self, amt);
    }

    pub fn getEndPos(self: Self) !u64 {
        return self.getEndPosFn(self);
    }

    pub fn getPos(self: Self) !u64 {
        return self.getPosFn(self);
    }
};

pub const SliceSeekableInStream = struct {
    const Self = @This();

    pos: usize,
    slice: []const u8,

    pub fn init(slice: []const u8) Self {
        return Self{
            .slice = slice,
            .pos = 0,
        };
    }

    fn readFn(in_stream: InStream, dest: []u8) InStream.Error!usize {
        const self = in_stream.iface.?.implCast(SliceSeekableInStream);
        const size = std.math.min(dest.len, self.slice.len - self.pos);
        const end = self.pos + size;

        std.mem.copy(u8, dest[0..size], self.slice[self.pos..end]);
        self.pos = end;

        return size;
    }

    fn seekToFn(in_stream: SeekableStream, pos: u64) SeekableStream.SeekError!void {
        const self = in_stream.iface.?.implCast(SliceSeekableInStream);
        const usize_pos = @intCast(usize, pos);
        if (usize_pos >= self.slice.len) return error.EndOfStream;
        self.pos = usize_pos;
    }

    fn seekForwardFn(in_stream: SeekableStream, amt: i64) SeekableStream.SeekError!void {
        const self = in_stream.iface.?.implCast(SliceSeekableInStream);

        if (amt < 0) {
            const abs_amt = @intCast(usize, -amt);
            if (abs_amt > self.pos) return error.EndOfStream;
            self.pos -= abs_amt;
        } else {
            const usize_amt = @intCast(usize, amt);
            if (self.pos + usize_amt >= self.slice.len) return error.EndOfStream;
            self.pos += usize_amt;
        }
    }

    fn getEndPosFn(in_stream: SeekableStream) SeekableStream.GetSeekPosError!u64 {
        const self = in_stream.iface.?.implCast(SliceSeekableInStream);
        return @intCast(u64, self.slice.len);
    }

    fn getPosFn(in_stream: SeekableStream) SeekableStream.GetSeekPosError!u64 {
        const self = in_stream.iface.?.implCast(SliceSeekableInStream);
        return @intCast(u64, self.pos);
    }

    pub fn inStream(self: *Self) InStream {
        return InStream{
            .iface = InStream.Iface.init(self),
            .readFn = readFn,
        };
    }

    pub fn seekableStream(self: *Self) SeekableStream {
        return SeekableStream{
            .iface = SeekableStream.Iface.init(self),
            .seekToFn = seekToFn,
            .seekForwardFn = seekForwardFn,
            .getPosFn = getPosFn,
            .getEndPosFn = getEndPosFn,
        };
    }
};
