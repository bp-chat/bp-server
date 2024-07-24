const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Endian = std.builtin.Endian;

const CURRENT_VERSION = 1;

const Header = struct {
    version: u16,
    commandRefId: u8,
    commandId: u16,
};
const Command = struct {
    const maxLength = 4096;

    header: Header,
    body: [4091]u8,

    fn encode(self: Command, buffer: *[Command.maxLength]u8) void {
        std.mem.writeInt(u16, buffer[0..2], self.header.version, Endian.big);
        buffer[2] = self.header.commandRefId;
        std.mem.writeInt(u16, buffer[3..5], self.header.commandId, Endian.big);
        buffer[5..].* = self.body;
    }
};

const MessageCommand = struct {
    const length = 1040;
    const commandId = 1;

    //TODO replace fields for methods
    //TODO test if buffer could be a pointer
    recipient: [16]u8,
    message: [1024]u8,
    buffer: [length]u8,

    fn parse(data: [length]u8) MessageCommand {
        return MessageCommand{
            .buffer = data,
            .recipient = data[0..16],
            .message = data[16..1040],
        };
    }

    fn asCommand(self: MessageCommand) Command {
        return Command{
            .header = Header{
                .version = CURRENT_VERSION,
                .commandRefId = 0,
                .commandId = commandId,
            },
            .body = self.buffer,
        };
    }
};

fn decode_header(data: []u8) Header {
    assert(data.len >= 5);
    return Header{
        .version = std.mem.readInt(u16, data[0..2], Endian.big),
        .commandRefId = data[2],
        .commandId = std.mem.readInt(u16, data[3..5], Endian.big),
    };
}
//TODO consider moving to Command struct
//TODO consider accepting a fixed length array/slice
fn decode(data: []u8) Command {
    assert(data.len >= 5);
    assert(data.len <= Command.maxLength);
    // For some reason the asBytes and bytesAsValues funtions does not layout
    // the bytes of the struct in the way that I expected
    // field by field in the order that was declared, maybe we should rethink the struct
    // because the llvm is optmizing the struct?
    return Command{
        .header = decode_header(data[0..5]),
        .body = data[5..],
    };
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
    try testing.expectEqual(0x02, actual.commandRefId);
    try testing.expectEqual(0x03, actual.commandId);
}

test "should enconde command" {
    var buffer: [Command.maxLength]u8 = undefined;
    buffer[0] = 0;
    var cmdBody: [4091]u8 = undefined;
    cmdBody[0] = 4;
    cmdBody[1] = 5;
    cmdBody[2] = 6;
    cmdBody[3] = 7;
    cmdBody[4] = 8;
    cmdBody[5] = 9;
    const cmd = Command{
        .header = Header{
            .version = 1,
            .commandRefId = 2,
            .commandId = 3,
        },
        .body = cmdBody,
    };
    cmd.encode(&buffer);
    try testing.expectEqual(0, buffer[0]);
    try testing.expectEqual(1, buffer[1]);
    try testing.expectEqual(2, buffer[2]);
    try testing.expectEqual(8, buffer[9]);
}
