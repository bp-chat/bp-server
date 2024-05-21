const std = @import("std");
const net = std.net;

pub fn main() !void {
    // 'B' = 66, 'P' = 80
    const default_port: u16 = 6680;
    const address = try net.Address.parseIp("127.0.0.1", default_port);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();
    std.log.info("Connected!", .{});
}
