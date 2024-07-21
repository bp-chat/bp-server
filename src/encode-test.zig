const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Endian = std.builtin.Endian;

const Header = struct {
    version: u16,
    command_ref_id: u8,
    command_id: u16,
};
const Command = struct {
    header: Header,
    body: []u8,
};

const MessageCommand = struct {
    recipient: [16]u8,
    message: [1024]u8,

    fn parse(data: [1040]u8) MessageCommand {
        return MessageCommand{
            .recipient = data[0..16],
            .message = data[16..1040],
        };
    }
};

fn decode_header(data: []u8) Header {
    assert(data.len >= 5);
    return Header{
        .version = std.mem.readInt(u16, data[0..2], Endian.big),
        .command_ref_id = data[2],
        .command_id = std.mem.readInt(u16, data[3..5], Endian.big),
    };
}

fn decode(data: []u8) Command {
    assert(data.len >= 5);
    //TODO ASSERT MAX LEN
    // For some reason the asBytes and bytesAsValues funtions does not layout
    // the bytes of the struct in the way that I expected
    // field by field in the order that was declared, maybe we should rethink the struct
    // because the llvm is optmizing the struct?
    return Command{ .header = decode_header(data[0..5]), .body = data[5..] };
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
