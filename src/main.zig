const std = @import("std");
const net = std.net;
const log = std.log;

const os = std.os;
const linux = os.linux;
const io_allocator = std.heap.page_allocator;

const State = enum { accept, recv, send };
const Socket = struct {
    handle: usize,
    buffer: [1024]u8,
    state: State,
};

// trying to implement example from https://tigerbeetle.com/blog/a-friendly-abstraction-over-iouring-and-kqueue
// TODO: WIP
pub fn main() !void {
    const entries = 32;
    const flags = 0;
    var ring = try linux.IoUring.init(entries, flags);
    defer ring.deinit();

    var server: Socket = undefined;
    server.handle = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);
    const casted_server_handle: i32 = @intCast(server.handle);
    defer _ = linux.close(casted_server_handle);

    const port = 6680;
    var addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var addr_len = addr.getOsSockLen();

    _ = linux.setsockopt(casted_server_handle, linux.SOL.SOCKET, linux.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)), 1);
    _ = linux.bind(casted_server_handle, &addr.any, addr_len);
    const backlog = 128;
    _ = linux.listen(casted_server_handle, backlog);

    server.state = .accept;
    _ = try ring.accept(@intFromPtr(&server), casted_server_handle, &addr.any, &addr_len, 0);

    log.info("Beginning loop", .{});
    while (true) {
        log.info("Waiting...", .{});
        _ = try ring.submit_and_wait(1);
        log.info("Got a connection!", .{});

        while (ring.cq_ready() > 0) {
            log.info("You ready?", .{});
            const cqe = try ring.copy_cqe();
            const user_data_addr: usize = @intCast(cqe.user_data);
            const client: *Socket = @ptrFromInt(user_data_addr);

            if (cqe.res < 0) {
                std.debug.panic("{}({}): {}", .{
                    client.state,
                    client.handle,
                    @as(linux.E, @enumFromInt(-cqe.res)),
                });
            }

            switch (client.state) {
                .accept => {
                    log.info("accept", .{});
                },
                .recv => {
                    log.info("recv", .{});
                },
                .send => {
                    log.info("send", .{});
                },
            }
        }
    }
}

pub fn mainOld() !void {
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

    var connections = try std.ArrayList(std.net.Server.Connection).initCapacity(allocator, 8);
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
    // 'B' = 66, 'P' = 80
    const default_port: u16 = 6680;
    std.log.info("No custom port provided, using default: {}", .{default_port});
    return default_port;
}

fn handleConnection(allocator: *const std.mem.Allocator, conn: std.net.Server.Connection, all: *std.ArrayList(std.net.Server.Connection)) !void {
    const buffer = try allocator.alloc(u8, 64);
    defer allocator.free(buffer);
    while (true) {
        const byte_count = try conn.stream.read(buffer);
        const message = buffer[0..byte_count];
        std.log.info("{} says: {s}", .{ conn.address, message });
        for (all.items) |other_conn| {
            if (conn.address.eql(other_conn.address)) {
                continue;
            }
            _ = try other_conn.stream.write(message);
        }
    }
}
