const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Endian = std.builtin.Endian;
const allocator = std.testing.allocator;

const CURRENT_VERSION = 1;

const Header = struct {
    version: u16,
    commandRefId: u8,
    commandId: u16,
};

pub const Command = struct {
    //TODO move to a better place with the rest of the env configs
    pub const maxLength = 4096;

    header: Header,
    body: []u8,

    pub fn encode(self: Command, buffer: []u8) void {
        std.mem.writeInt(u16, buffer[0..2], self.header.version, Endian.big);
        buffer[2] = self.header.commandRefId;
        std.mem.writeInt(u16, buffer[3..5], self.header.commandId, Endian.big);
        std.mem.copyForwards(u8, buffer[5..], self.body);
    }

    fn decode_header(data: []u8) Header {
        assert(data.len >= 5);
        return Header{
            .version = std.mem.readInt(u16, data[0..2], Endian.big),
            .commandRefId = data[2],
            .commandId = std.mem.readInt(u16, data[3..5], Endian.big),
        };
    }

    //TODO consider accepting a fixed length array
    pub fn decode(data: []u8) Command {
        assert(data.len <= maxLength);
        return Command{
            .header = decode_header(data[0..5]),
            .body = data[5..],
        };
    }
};

pub const MessageCommand = struct {
    pub const length = 1040;
    pub const commandId = 2;

    buffer: *[length]u8,
    recipient: *[16]u8,
    message: *[1024]u8,

    fn parse(data: *[length]u8) MessageCommand {
        return MessageCommand{
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

pub const RegisterKeysCommand = struct {
    pub const length = 176;
    pub const commandId = 3;

    buffer: *[length]u8,
    user: [16]u8,
    idKey: [32]u8,
    signedKey: [32]u8,
    signature: [64]u8,
    ephemeralKey: [32]u8,

    pub fn parse(data: *[length]u8) RegisterKeysCommand {
        return RegisterKeysCommand{
            .buffer = data,
            .user = data[0..16],
            .idKey = data[16..48],
            .signedKey = data[48..80],
            .signature = data[80..144],
            .ephemeralKey = data[144..length],
        };
    }

    pub fn asCommand(self: RegisterKeysCommand) Command {
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

const SimpleTestCommand = struct {
    const length = 5;
    const commandId = 99;

    buffer: *[length]u8,
    fake: *[2]u8,

    fn parse(data: *[length]u8) SimpleTestCommand {
        return SimpleTestCommand{
            .buffer = data,
            .fake = data[0..2],
        };
    }

    fn asCommand(self: SimpleTestCommand) Command {
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

test "should enconde command" {
    var buffer = try allocator.alloc(u8, Command.maxLength);
    defer allocator.free(buffer);
    var cmdBody = try allocator.alloc(u8, 4091);
    defer allocator.free(cmdBody);
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
        .body = cmdBody[0..4091],
    };
    cmd.encode(buffer[0..Command.maxLength]);
    try testing.expectEqual(0, buffer[0]);
    try testing.expectEqual(1, buffer[1]);
    try testing.expectEqual(2, buffer[2]);
    try testing.expectEqual(8, buffer[9]);
}

test "should decode simple command" {
    var inputBuffer = try allocator.alloc(u8, Command.maxLength);
    defer allocator.free(inputBuffer);
    const input = [_]u8{
        0x00,
        0x01,
        0x02,
        0x00,
        0x03,
        0xf0,
        0xf1,
        0xf2,
        0xf3,
        0xf4,
    };
    //there must be a better way...
    for (input, 0..) |byte, i| {
        inputBuffer[i] = byte;
    }
    var cmd = Command.decode(inputBuffer);
    try testing.expectEqual(0x01, cmd.header.version);
    try testing.expectEqual(0x02, cmd.header.commandRefId);
    try testing.expectEqual(0x03, cmd.header.commandId);

    const actual = SimpleTestCommand.parse(cmd.body[0..SimpleTestCommand.length]);
    try testing.expectEqual(0xf0, actual.fake[0]);
}

test "should encode simple command" {
    var input = [_]u8{
        0x00,
        0x01,
        0x02,
        0x00,
        0x03,
        0xf0,
        0xf1,
        0xf2,
        0xf3,
        0xf4,
    };
    const sut = SimpleTestCommand{
        .buffer = input[5..],
        .fake = input[5..7],
    };
    const actual = sut.asCommand();
    try testing.expectEqual(SimpleTestCommand.commandId, actual.header.commandId);
    try testing.expectEqual(0xf0, actual.body[0]);
}
