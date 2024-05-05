const std = @import("std");
const net = std.net;

pub fn main() !void {
    const address = try net.Address.parseIp("127.0.0.1", 5501);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();
    std.log.info("Connected!", .{});
}
