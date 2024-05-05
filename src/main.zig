const std = @import("std");
const net = std.net;

pub fn main() !void {
    const address = try net.Address.parseIp("127.0.0.1", 5501);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    std.log.info("Server listening at {any}\n", .{address});

    while (true) {
        std.log.info("Waiting for connection...", .{});
        const conn = try listener.accept();
        defer conn.stream.close();
        std.log.info("Connected! {any}", .{conn.address});
    }
}
