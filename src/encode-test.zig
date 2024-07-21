const std = @import("std");
const Stream = std.Stream;
const testing = std.testing;
const test_allocator = std.testing.allocator;
const assert = std.debug.assert;
const Endian = std.builtin.Endian;

pub const FictionalCommand = struct { version: u16, command_ref_id: u8, command_id: u16, args: std.ArrayList([]u8) };

fn encode(command: FictionalCommand) []u8 {
    var res: [7]u8 = undefined;
    res[0] = @truncate(command.version >> 8);
    res[1] = @truncate(command.version);
    res[2] = 0x0A;
    res[3] = command.command_ref_id;
    res[4] = 0x0A;
    res[5] = @truncate(command.command_id >> 8);
    res[6] = @truncate(command.command_id);
    return &res;
}

pub fn encode_size(command: FictionalCommand, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var builder = std.ArrayList(u8).init(allocator);
    defer builder.deinit();
    try builder.append(@truncate(command.version >> 8));
    try builder.append(@truncate(command.version));
    try builder.append(command.command_ref_id);
    try builder.append(@truncate(command.command_id >> 8));
    try builder.append(@truncate(command.command_id));
    for (command.args.items) |a| {
        try builder.append(@truncate(a.len >> 24));
        try builder.append(@truncate(a.len >> 16));
        try builder.append(@truncate(a.len >> 8));
        try builder.append(@truncate(a.len));
        for (a) |b| {
            try builder.append(b);
        }
    }
    const final: []u8 = try allocator.alloc(u8, builder.items.len);
    std.mem.copyForwards(u8, final, builder.items);
    return final;
}

test "should encode" {
    var a1 = [_]u8{ 0x04, 0x05, 0x06 };
    var a2 = [_]u8{ 0x01, 2, 3 };
    var mtx = std.ArrayList([]u8).init(test_allocator);
    defer (mtx.deinit());
    try mtx.append(&a1);
    try mtx.append(&a2);
    const cmd = FictionalCommand{ .version = 0xF00F, .command_ref_id = 2, .command_id = 0x0FF0, .args = mtx };
    const actual = encode(cmd);
    try testing.expect(actual.len == 7);
    try testing.expect(actual[0] == 0xF0);
    try testing.expect(actual[1] == 0x0F);
    try testing.expect(actual[2] == 0x0A);
    try testing.expect(actual[3] == 2);
    try testing.expect(actual[4] == 0x0A);
    try testing.expect(actual[5] == 0x0F);
    try testing.expect(actual[6] == 0xF0);
}

test "should encode without newline" {
    var a1 = [_]u8{ 0x04, 0x05, 0x06 };
    var a2 = [_]u8{ 0x01, 2, 3 };
    var mtx = std.ArrayList([]u8).init(test_allocator);
    defer (mtx.deinit());
    try mtx.append(&a1);
    try mtx.append(&a2);
    const cmd = FictionalCommand{ .version = 0xF00F, .command_ref_id = 2, .command_id = 0x0FF0, .args = mtx };
    const actual = try encode_size(cmd, test_allocator);
    defer test_allocator.free(actual);
    try testing.expect(actual.len == 19);
    try testing.expect(actual[0] == 0xF0);
    try testing.expect(actual[1] == 0x0F);
    try testing.expect(actual[2] == 2);
    try testing.expect(actual[3] == 0x0F);
    try testing.expect(actual[5] == 0x00);
    try testing.expect(actual[8] == 0x03);
    try testing.expect(actual[10] == 0x05);
    try testing.expect(actual[17] == 0x02);
}

pub fn decode(data: []u8, allocator: std.mem.Allocator) std.mem.Allocator.Error!FictionalCommand {
    const version = (@as(u16, data[0]) << 8) | @as(u16, data[1]);
    const sync_id = data[3];
    const cmd_id = (@as(u16, data[5]) << 8) | @as(u16, data[6]);
    var args = std.ArrayList([]u8).init(allocator);
    var start: usize = 8;
    for (data[start..], start..) |bit, i| {
        if (bit == 0x0a) {
            const ta = data[start..i];
            try args.append(ta);
            start = i + 1;
        }
    }
    return FictionalCommand{ .version = version, .command_ref_id = sync_id, .command_id = cmd_id, .args = args };
}

pub fn decode_sized(data: []u8, allocator: std.mem.Allocator) std.mem.Allocator.Error!FictionalCommand {
    const version = (@as(u16, data[0]) << 8) | @as(u16, data[1]);
    const sync_id = data[2];
    const cmd_id = (@as(u16, data[3]) << 8) | @as(u16, data[4]);
    var args = std.ArrayList([]u8).init(allocator);
    var start: usize = 5;
    while (start < data.len) {
        const value_idx = start + 4;
        const arg_size: u32 = std.mem.readInt(u32, data[start..value_idx][0..4], std.builtin.Endian.big);
        const arg_value = data[value_idx .. value_idx + arg_size];
        try args.append(arg_value);
        start += 4 + arg_size;
    }
    return FictionalCommand{ .version = version, .command_ref_id = sync_id, .command_id = cmd_id, .args = args };
}

test "should decode" {
    var input = [_]u8{ 0xF0, 0x0F, 0x0a, 0x03, 0x0a, 0x1f, 0xf1, 0x0a, 0x01, 0x04, 0x05, 0x0a, 0x02, 0x03, 0x0a };
    // const t = std.mem.bytesAsValue(FictionalCommand, input);
    var actual = try decode(&input, test_allocator);
    defer actual.args.deinit();
    try testing.expect(actual.version == 0xf00f);
    try testing.expect(actual.command_ref_id == 3);
    try testing.expect(actual.command_id == 0x1ff1);
    try testing.expect(actual.args.items.len == 2);
    try testing.expect(actual.args.items[0].len == 3);
    try testing.expect(actual.args.items[1].len == 2);
    try testing.expect(actual.args.items[0][0] == 1);
    try testing.expect(actual.args.items[0][1] == 4);
    try testing.expect(actual.args.items[0][2] == 5);
    try testing.expect(actual.args.items[1][0] == 2);
    try testing.expect(actual.args.items[1][1] == 3);
}

const Header = struct { version: u16, command_ref_id: u8, command_id: u16 };
const GenericCommand = struct { header: Header, body: []u8 };

fn decode_header(data: []u8) Header {
    assert(data.len >= 5);
    return Header{ .version = std.mem.readInt(u16, data[0..2], Endian.big), .command_ref_id = data[2], .command_id = std.mem.readInt(u16, data[3..5], Endian.big) };
}

fn decode_new(data: []u8) GenericCommand {
    assert(data.len >= 5);
    //TODO ASSERT MAX LEN
    return GenericCommand{ .header = decode_header(data[0..5]), .body = data[5..] };
}

test "should decode header" {
    var input = [_]u8{
        0x00,
        0x01,
        0x02,
        0x00,
        0x03,
        0xff,
        0xff,
        0xff,
        0xff,
        0xff,
    };
    const actual = decode_header(&input);
    std.debug.print("\ndecoded {}\n", .{actual});
    try testing.expectEqual(0x01, actual.version);
    try testing.expectEqual(0x02, actual.command_ref_id);
    try testing.expectEqual(0x03, actual.command_id);
}
