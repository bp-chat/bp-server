const std = @import("std");
const Stream = std.Stream;
const testing = std.testing;
const test_allocator = std.testing.allocator;

const FictionalCommand = struct { version: u16, command_ref_id: u8, command_id: u16 };

//TUDO add \n chars and write the rest of the u16 data
fn encode(command: FictionalCommand) std.mem.Allocator.Error![]u8 {
    var res = std.ArrayList(u8).init(test_allocator);
    defer res.deinit();
    try res.append(@truncate(command.version));
    try res.append(command.command_ref_id);
    try res.append(@truncate(command.command_id));
    return res.items;
}

test "should encode" {
    const cmd = FictionalCommand{ .version = 1, .command_ref_id = 2, .command_id = 3 };
    const actual = try encode(cmd);
    //TUDO test the actual written bytes
    try testing.expect(actual.len == 3);
}
