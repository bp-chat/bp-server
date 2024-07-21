const std = @import("std");
const net = std.net;
const log = std.log;

const os = std.os;
const linux = os.linux;
const io_allocator = std.heap.page_allocator;
const server = std.net.Server;

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
    // var user: UserData = undefined;
    while (true) {
        const byte_count = try conn.stream.read(buffer);
        const message = buffer[0..byte_count];
        // const cmd = try serde.decode_sized(message, allocator.*);
        const cmd = 0;
        // defer cmd.args.deinit();
        switch (cmd) {
            0 => std.debug.print("ignore unknown for now", .{}),
            1 => std.debug.print("ignore connect for now", .{}),
            2 => {
                std.debug.print("sendig message\n", .{});
                for (all.items) |other_conn| {
                    if (conn.address.eql(other_conn.address)) {
                        continue;
                    }
                    _ = try other_conn.stream.write(message);
                }
            },
            3 => {
                std.debug.print("saving keys\n", .{});
                // for (cmd.args.items, 0..) |d, i| {
                //     std.debug.print("{} - {x}\n", .{ i, d });
                // }
                // user = UserData{ .name = cmd.args.items[0], .idk = cmd.args.items[1], .spk = cmd.args.items[2], .sig = cmd.args.items[3], .epk = cmd.args.items[4] };
            },
            4 => {
                //broadcast this connection keys for now...
                std.debug.print("broadcasting keys\n", .{});
                // var args = std.ArrayList([]u8).init(allocator.*);
                // _ = try args.append(user.name);
                // _ = try args.append(user.idk);
                // _ = try args.append(user.spk);
                // _ = try args.append(user.sig);
                // _ = try args.append(user.epk);
                // defer args.deinit();
                // const out_cmd = serde.FictionalCommand{ .version = 0, .command_ref_id = 8, .command_id = 4, .args = args };
                // const out_msg = try serde.encode_size(out_cmd, allocator.*);
                // std.debug.print("sending:\n{X}\n", .{out_msg});
                // for (all.items) |other| {
                // if (other.address.eql(conn.address)) {
                // continue;
                // }
                // _ = try other.stream.write(out_msg);
                // }
            },
            else => std.debug.print("ignore unknowkn for now", .{}),
        }
    }
}
