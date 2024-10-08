const std = @import("std");
const net = std.net;
const log = std.log;

const os = std.os;
const linux = os.linux;
const io_allocator = std.heap.page_allocator;
const assert = std.debug.assert;

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
    defer {
        const close_result = linux.close(casted_server_handle);
        if (close_result != 0) {
            log.err("Unable to close socket. handle={}; result={}", .{ casted_server_handle, close_result });
        }
    }
    log.info("main: server_handle={}", .{casted_server_handle});

    const port = 6680;
    var addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var addr_len = addr.getOsSockLen();

    const setsockopt_bytes = std.mem.toBytes(@as(c_int, 1));
    const setsockopt_result = linux.setsockopt(casted_server_handle, linux.SOL.SOCKET, linux.SO.REUSEADDR, &setsockopt_bytes, setsockopt_bytes.len);
    if (setsockopt_result != 0) {
        log.err("Could not set socket options. result={}", .{setsockopt_result});
        // TODO: improve exit code handling
        std.process.exit(1);
    }
    const bind_result = linux.bind(casted_server_handle, &addr.any, addr_len);
    if (bind_result != 0) {
        log.err("Could not bind socket. result={}", .{bind_result});
        std.process.exit(@intCast(bind_result));
    }
    const backlog = 128;
    const listen_result = linux.listen(casted_server_handle, backlog);
    if (listen_result != 0) {
        log.err("Could not listen on socket. result={}", .{listen_result});
        std.process.exit(@intCast(listen_result));
    }

    server.state = .accept;

    try chat(&ring, server, &addr, &addr_len);
}

fn echoServer(ring: *linux.IoUring, server: Socket, addr: *net.Address, addr_len: *u32) !void {
    const casted_server_handle: i32 = @intCast(server.handle);

    log.info("Beginning loop", .{});
    while (true) {
        log.info("main loop: accept", .{});
        _ = try ring.accept(@intFromPtr(&server), casted_server_handle, &addr.any, addr_len, 0);

        log.info("Waiting...", .{});
        _ = try ring.submit_and_wait(1);
        log.info("Go", .{});

        while (ring.cq_ready() > 0) {
            log.info("You ready?", .{});
            const cqe = try ring.copy_cqe();
            const user_data_addr: usize = @intCast(cqe.user_data);
            var client: *Socket = @ptrFromInt(user_data_addr);

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
                    client = try io_allocator.create(Socket);
                    client.handle = @intCast(cqe.res);
                    client.state = .recv;
                    const casted_client_handle: i32 = @intCast(client.handle);
                    log.info("accept: client_handle={}", .{casted_client_handle});
                    _ = try ring.recv(@intFromPtr(client), casted_client_handle, .{ .buffer = &client.buffer }, 0);
                },
                .recv => {
                    log.info("recv", .{});
                    const read: usize = @intCast(cqe.res);
                    client.state = .send;
                    const msg = client.buffer[0..read];
                    log.info("recv: {s}", .{msg});
                    const casted_client_handle: i32 = @intCast(client.handle);
                    _ = try ring.send(@intFromPtr(client), casted_client_handle, msg, 0);
                },
                .send => {
                    log.info("send", .{});
                    const casted_client_handle: i32 = @intCast(client.handle);
                    const close_result = linux.close(casted_client_handle);
                    if (close_result != 0) {
                        std.log.warn("Could not close client connection. handle={}; result={}", .{ casted_client_handle, close_result });
                    }
                    io_allocator.destroy(client);
                    log.info("send: Client shutdown. client_handle={}", .{casted_client_handle});
                },
            }
        }
    }
}

fn chat(ring: *linux.IoUring, server: Socket, addr: *net.Address, addr_len: *u32) !void {
    const casted_server_handle: i32 = @intCast(server.handle);

    var clients = std.AutoHashMap(usize, *Socket).init(io_allocator);
    defer clients.deinit();

    const max_clients = 3;
    try clients.ensureTotalCapacity(max_clients);

    while (true) {
        log.info("accept. handle={}", .{server.handle});
        _ = try ring.accept(server.handle, casted_server_handle, &addr.any, addr_len, 0);

        log.info("submit_and_wait", .{});
        _ = try ring.submit_and_wait(1);

        while (ring.cq_ready() > 0) {
            const cqe = try ring.copy_cqe();
            const user_data_addr: usize = @intCast(cqe.user_data);
            var client: *Socket = undefined;
            if (user_data_addr == server.handle) {
                if (cqe.res == 0) {
                    log.info("NOP, close event", .{});
                    continue;
                }
                // TODO: "statically" allocate every client at server startup. This will require reusing memory and different data structures
                client = try io_allocator.create(Socket);
                client.handle = @intCast(cqe.res);
                client.state = .accept;
                clients.putAssumeCapacity(client.handle, client);
                log.info("Client connected. handle={}", .{client.handle});
            } else {
                const client_ptr = clients.get(user_data_addr);
                if (client_ptr == null) {
                    log.info("NOP, client already disconnected. handle={}", .{user_data_addr});
                    continue;
                }
                client = client_ptr.?;
            }

            if (cqe.res < 0) {
                std.debug.panic("{}({}): {}", .{
                    client.state,
                    client.handle,
                    @as(linux.E, @enumFromInt(-cqe.res)),
                });
            }

            switch (client.state) {
                .accept => {
                    client.state = .recv;
                    const casted_client_handle: i32 = @intCast(client.handle);
                    _ = try ring.recv(client.handle, casted_client_handle, .{ .buffer = &client.buffer }, 0);
                    log.info("recv: client_handle={}", .{casted_client_handle});
                },
                .recv => {
                    const read: usize = @intCast(cqe.res);
                    const casted_client_handle: i32 = @intCast(client.handle);
                    if (read == 0) {
                        const handle = client.handle;
                        assert(clients.remove(handle));
                        io_allocator.destroy(client);
                        _ = try ring.close(server.handle, casted_client_handle);
                        log.info("Client disconnected. handle={}", .{handle});
                        continue;
                    }
                    const msg = client.buffer[0..read];
                    log.info("recv: msg={s}; read={};", .{ msg, read });
                    var client_iterator = clients.valueIterator();
                    while (client_iterator.next()) |client_it| {
                        if (client.handle == client_it.*.handle) {
                            continue;
                        }
                        client_it.*.state = .send;
                        log.info("recv: Sending message. from={}; to={}; msg={s}", .{ client.handle, client_it.*.handle, msg });
                        const casted_client_it_handle: i32 = @intCast(client_it.*.handle);
                        _ = try ring.send(client_it.*.handle, casted_client_it_handle, msg, 0);
                    }

                    _ = try ring.recv(client.handle, casted_client_handle, .{ .buffer = &client.buffer }, 0);
                },
                .send => {
                    log.info("send: Sent. to={}", .{client.handle});
                    client.state = .recv;
                    const casted_client_handle: i32 = @intCast(client.handle);
                    _ = try ring.recv(client.handle, casted_client_handle, .{ .buffer = &client.buffer }, 0);
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
