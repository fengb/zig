const std = @import("std");
const io = std.io;
const mem = std.mem;
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const Buffer = std.Buffer;
const ArrayList = std.ArrayList;
const maxInt = std.math.maxInt;

const Token = union(enum) {
    Word: []const u8,
    OpenBrace,
    CloseBrace,
    Comma,
    Eof,
};

var global_allocator: *mem.Allocator = undefined;

fn tokenize(input: []const u8) !ArrayList(Token) {
    const State = enum {
        Start,
        Word,
    };

    var token_list = ArrayList(Token).init(global_allocator);
    var tok_begin: usize = undefined;
    var state = State.Start;

    for (input) |b, i| {
        switch (state) {
            State.Start => switch (b) {
                'a'...'z', 'A'...'Z' => {
                    state = State.Word;
                    tok_begin = i;
                },
                '{' => try token_list.append(Token.OpenBrace),
                '}' => try token_list.append(Token.CloseBrace),
                ',' => try token_list.append(Token.Comma),
                else => return error.InvalidInput,
            },
            State.Word => switch (b) {
                'a'...'z', 'A'...'Z' => {},
                '{', '}', ',' => {
                    try token_list.append(Token{ .Word = input[tok_begin..i] });
                    switch (b) {
                        '{' => try token_list.append(Token.OpenBrace),
                        '}' => try token_list.append(Token.CloseBrace),
                        ',' => try token_list.append(Token.Comma),
                        else => unreachable,
                    }
                    state = State.Start;
                },
                else => return error.InvalidInput,
            },
        }
    }
    switch (state) {
        State.Start => {},
        State.Word => try token_list.append(Token{ .Word = input[tok_begin..] }),
    }
    try token_list.append(Token.Eof);
    return token_list;
}

const Node = union(enum) {
    Scalar: []const u8,
    List: ArrayList(Node),
    Combine: []Node,
};

const ParseError = error{
    InvalidInput,
    OutOfMemory,
};

fn parse(tokens: *const ArrayList(Token), token_index: *usize) ParseError!Node {
    const first_token = tokens.items[token_index.*];
    token_index.* += 1;

    const result_node = switch (first_token) {
        Token.Word => |word| Node{ .Scalar = word },
        Token.OpenBrace => blk: {
            var list = ArrayList(Node).init(global_allocator);
            while (true) {
                try list.append(try parse(tokens, token_index));

                const token = tokens.items[token_index.*];
                token_index.* += 1;

                switch (token) {
                    Token.CloseBrace => break,
                    Token.Comma => continue,
                    else => return error.InvalidInput,
                }
            }
            break :blk Node{ .List = list };
        },
        else => return error.InvalidInput,
    };

    switch (tokens.items[token_index.*]) {
        Token.Word, Token.OpenBrace => {
            const pair = try global_allocator.alloc(Node, 2);
            pair[0] = result_node;
            pair[1] = try parse(tokens, token_index);
            return Node{ .Combine = pair };
        },
        else => return result_node,
    }
}

fn expandString(input: []const u8, output: *Buffer) !void {
    const tokens = try tokenize(input);
    if (tokens.len == 1) {
        return output.resize(0);
    }

    var token_index: usize = 0;
    const root = try parse(&tokens, &token_index);
    const last_token = tokens.items[token_index];
    switch (last_token) {
        Token.Eof => {},
        else => return error.InvalidInput,
    }

    var result_list = ArrayList(Buffer).init(global_allocator);
    defer result_list.deinit();

    try expandNode(root, &result_list);

    try output.resize(0);
    for (result_list.toSliceConst()) |buf, i| {
        if (i != 0) {
            try output.appendByte(' ');
        }
        try output.append(buf.toSliceConst());
    }
}

const ExpandNodeError = error{OutOfMemory};

fn expandNode(node: Node, output: *ArrayList(Buffer)) ExpandNodeError!void {
    assert(output.len == 0);
    switch (node) {
        Node.Scalar => |scalar| {
            try output.append(try Buffer.init(global_allocator, scalar));
        },
        Node.Combine => |pair| {
            const a_node = pair[0];
            const b_node = pair[1];

            var child_list_a = ArrayList(Buffer).init(global_allocator);
            try expandNode(a_node, &child_list_a);

            var child_list_b = ArrayList(Buffer).init(global_allocator);
            try expandNode(b_node, &child_list_b);

            for (child_list_a.toSliceConst()) |buf_a| {
                for (child_list_b.toSliceConst()) |buf_b| {
                    var combined_buf = try Buffer.initFromBuffer(buf_a);
                    try combined_buf.append(buf_b.toSliceConst());
                    try output.append(combined_buf);
                }
            }
        },
        Node.List => |list| {
            for (list.toSliceConst()) |child_node| {
                var child_list = ArrayList(Buffer).init(global_allocator);
                try expandNode(child_node, &child_list);

                for (child_list.toSliceConst()) |buf| {
                    try output.append(buf);
                }
            }
        },
    }
}

pub fn main() !void {
    var stdin_file = try io.getStdIn();
    var stdout_file = try io.getStdOut();

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = std.heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    global_allocator = &arena.allocator;

    var stdin_buf = try Buffer.initSize(global_allocator, 0);
    defer stdin_buf.deinit();

    var stdin_adapter = stdin_file.inStream();
    try stdin_adapter.stream.readAllBuffer(&stdin_buf, maxInt(usize));

    var result_buf = try Buffer.initSize(global_allocator, 0);
    defer result_buf.deinit();

    try expandString(stdin_buf.toSlice(), &result_buf);
    try stdout_file.write(result_buf.toSliceConst());
}

test "invalid inputs" {
    global_allocator = std.debug.global_allocator;

    expectError("}ABC", error.InvalidInput);
    expectError("{ABC", error.InvalidInput);
    expectError("}{", error.InvalidInput);
    expectError("{}", error.InvalidInput);
    expectError("A,B,C", error.InvalidInput);
    expectError("{A{B,C}", error.InvalidInput);
    expectError("{A,}", error.InvalidInput);

    expectError("\n", error.InvalidInput);
}

fn expectError(test_input: []const u8, expected_err: anyerror) void {
    var output_buf = Buffer.initSize(global_allocator, 0) catch unreachable;
    defer output_buf.deinit();

    testing.expectError(expected_err, expandString(test_input, &output_buf));
}

test "valid inputs" {
    global_allocator = std.debug.global_allocator;

    expectExpansion("{x,y,z}", "x y z");
    expectExpansion("{A,B}{x,y}", "Ax Ay Bx By");
    expectExpansion("{A,B{x,y}}", "A Bx By");

    expectExpansion("{ABC}", "ABC");
    expectExpansion("{A,B,C}", "A B C");
    expectExpansion("ABC", "ABC");

    expectExpansion("", "");
    expectExpansion("{A,B}{C,{x,y}}{g,h}", "ACg ACh Axg Axh Ayg Ayh BCg BCh Bxg Bxh Byg Byh");
    expectExpansion("{A,B}{C,C{x,y}}{g,h}", "ACg ACh ACxg ACxh ACyg ACyh BCg BCh BCxg BCxh BCyg BCyh");
    expectExpansion("{A,B}a", "Aa Ba");
    expectExpansion("{C,{x,y}}", "C x y");
    expectExpansion("z{C,{x,y}}", "zC zx zy");
    expectExpansion("a{b,c{d,e{f,g}}}", "ab acd acef aceg");
    expectExpansion("a{x,y}b", "axb ayb");
    expectExpansion("z{{a,b}}", "za zb");
    expectExpansion("a{b}", "ab");
}

fn expectExpansion(test_input: []const u8, expected_result: []const u8) void {
    var result = Buffer.initSize(global_allocator, 0) catch unreachable;
    defer result.deinit();

    expandString(test_input, &result) catch unreachable;

    testing.expectEqualSlices(u8, expected_result, result.toSlice());
}
