const std = @import("std");
const net = std.net;
const log = std.log;

const os = std.os;
const linux = os.linux;
const io_allocator = std.heap.page_allocator;

const serde = @import("encode-test.zig");

const NamedConn = struct { name: []u8, cnn: std.net.Server.Connection };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const port = try getPort(&args);
    const address = try net.Address.parseIp("127.0.0.1", port);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    std.log.info("Server listening at {any}\n", .{address});

    const buffer = try allocator.alloc(u8, 64);
    defer allocator.free(buffer);

    var connections = try std.ArrayList(NamedConn).initCapacity(allocator, 8);
    defer connections.deinit();

    var threads = try std.ArrayList(std.Thread).initCapacity(allocator, 8);
    defer threads.deinit();

    while (true) {
        std.log.info("Waiting for connection...", .{});
        const conn = try listener.accept();
        std.log.info("Connected! {any}", .{conn.address});

        try connections.append(NamedConn{ .name = &[_]u8{}, .cnn = conn });
        const thread = try std.Thread.spawn(.{}, handleConnection, .{ &allocator, conn, &connections });
        try threads.append(thread);
    }
}

fn getPort(args: *std.process.ArgIterator) !u16 {
    const param_name_candidate = args.next();
    if (param_name_candidate != null and
        (std.mem.eql(u8, param_name_candidate.?, "-p") or std.mem.eql(u8, param_name_candidate.?, "--port")))
    {
        const port_candidate = args.next();
        if (port_candidate != null) {
            return std.fmt.parseInt(u16, port_candidate.?, 10);
        }
    }
    const default_port: u16 = 6680;
    std.log.info("No custom port provided, using default: {}", .{default_port});
    return default_port;
}

fn handleConnection(allocator: *const std.mem.Allocator, conn: std.net.Server.Connection, all: *std.ArrayList(NamedConn)) !void {
    const buffer = try allocator.alloc(u8, 2048);
    defer allocator.free(buffer);
    while (true) {
        const byte_count = try conn.stream.read(buffer);
        const message = buffer[0..byte_count];
        std.log.info("{} msg: {x}", .{ conn.address, message });
        printCmdName(message);
        for (all.items) |conn_wrapper| {
            var other_conn = &conn_wrapper.cnn;
            if (conn.address.eql(other_conn.address)) {
                continue;
            }
            _ = try other_conn.stream.write(message);
        }
    }
}

//sry I'm lazy :(
fn printCmdName(message: []u8) void {
    const cmd = serde.decode(message);
    std.log.info("version {}\nsync {}\n id {}", .{ cmd.version, cmd.command_ref_id, cmd.command_id });
}
