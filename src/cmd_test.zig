const std = @import("std");
const net = std.net;
const log = std.log;

const os = std.os;
const linux = os.linux;
const io_allocator = std.heap.page_allocator;
const server = std.net.Server;

const serde = @import("encode-test.zig");

const UserData = struct { name: []u8, idk: []u8, spk: []u8, sig: []u8, epk: []u8, esg: []u8 };

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

    var connections = try std.ArrayList(server.Connection).initCapacity(allocator, 8);
    defer connections.deinit();

    var threads = try std.ArrayList(std.Thread).initCapacity(allocator, 8);
    defer threads.deinit();

    while (true) {
        std.log.info("Waiting for connection...", .{});
        const conn = try listener.accept();
        std.log.info("Connected! {any}", .{conn.address});

        try connections.append(conn);
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

fn handleConnection(allocator: *const std.mem.Allocator, conn: server.Connection, all: *std.ArrayList(server.Connection)) !void {
    const buffer = try allocator.alloc(u8, 4048);
    defer allocator.free(buffer);
    var user: UserData = undefined;
    while (true) {
        const byte_count = try conn.stream.read(buffer);
        const message = buffer[0..byte_count];
        const cmd = try serde.decode_sized(message, allocator.*);
        defer cmd.args.deinit();
        switch (cmd.command_id) {
            0 => std.debug.print("ignore unknown for now", .{}),
            1 => std.debug.print("ignore connect for now", .{}),
            2 => {
                for (all.items) |other_conn| {
                    if (conn.address.eql(other_conn.address)) {
                        continue;
                    }
                    _ = try other_conn.stream.write(message);
                }
            },
            3 => {
                for (cmd.args.items, 0..) |d, i| {
                    std.debug.print("{} - {x}\n", .{ i, d });
                }
                user = UserData{ .name = cmd.args.items[0], .idk = cmd.args.items[1], .spk = cmd.args.items[2], .sig = cmd.args.items[3], .epk = cmd.args.items[4], .esg = cmd.args.items[5] };
            },
            4 => {
                //broadcast this connection keys for now...
                for (all.items) |other| {
                    if (other.address.eql(conn.address)) {
                        continue;
                    }
                    _ = try other.stream.write(user.name);
                    _ = try other.stream.write(user.idk);
                    _ = try other.stream.write(user.spk);
                    _ = try other.stream.write(user.sig);
                    _ = try other.stream.write(user.epk);
                    _ = try other.stream.write(user.esg);
                }
            },
            else => std.debug.print("ignore unknowkn for now", .{}),
        }
    }
}
