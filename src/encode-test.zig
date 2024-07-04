const std = @import("std");
const Stream = std.Stream;
const testing = std.testing;
const test_allocator = std.testing.allocator;

const FictionalCommand = struct { version: u16, command_ref_id: u8, command_id: u16, args: std.ArrayList([]u8) };

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

pub fn decode(data: []u8) std.mem.Allocator.Error!FictionalCommand {
    const version = (@as(u16, data[0]) << 8) | @as(u16, data[1]);
    const sync_id = data[3];
    const cmd_id = (@as(u16, data[5]) << 8) | @as(u16, data[6]);
    var args = std.ArrayList([]u8).init(test_allocator);
    var start: usize = 8;
    for (data[start..], start..) |bit, i| {
        // std.debug.print("{}  {}-{x}\n", .{ start, i, bit });
        if (bit == 0x0a) {
            const ta = data[start..i];
            try args.append(ta);
            start = i + 1;
            // std.debug.print("appended {x} rly?\n", .{ta});
        }
    }
    return FictionalCommand{ .version = version, .command_ref_id = sync_id, .command_id = cmd_id, .args = args };
}

test "should decode" {
    var input = [_]u8{ 0xF0, 0x0F, 0x0a, 0x03, 0x0a, 0x1f, 0xf1, 0x0a, 0x01, 0x04, 0x05, 0x0a, 0x02, 0x03, 0x0a };
    var actual = try decode(&input);
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
    //TODO do actual implement init and deinit
}
