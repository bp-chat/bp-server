const std = @import("std");
const Stream = std.Stream;
const testing = std.testing;
const test_allocator = std.testing.allocator;

const FictionalCommand = struct { version: u16, command_ref_id: u8, command_id: u16 };

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
    const cmd = FictionalCommand{ .version = 0xF00F, .command_ref_id = 2, .command_id = 0x0FF0 };
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

pub fn decode(data: []u8) FictionalCommand {
    return FictionalCommand{ .version = (@as(u16, data[0]) << 8) | @as(u16, data[1]), .command_ref_id = data[3], .command_id = (@as(u16, data[5]) << 8) | @as(u16, data[6]) };
}

test "should decode" {
    var input = [7]u8{ 0xF0, 0x0F, 0x0a, 0x03, 0x0a, 0x1f, 0xf1 };
    const actual = decode(&input);
    try testing.expect(actual.version == 0xf00f);
    try testing.expect(actual.command_ref_id == 3);
    try testing.expect(actual.command_id == 0x1ff1);
}
