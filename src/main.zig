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
            log.info("loop. user_data_addr={}, cqe.res={}", .{ user_data_addr, cqe.res });
            if (user_data_addr == 0) {
                log.info("loop, user data is zero", .{});
                continue;
            }
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
                    client = try io_allocator.create(Socket);
                    client.handle = @intCast(cqe.res);
                    client.state = .recv;
                    clients.putAssumeCapacity(client.handle, client);
                    const casted_client_handle: i32 = @intCast(client.handle);
                    log.info("accept: client_handle={}, client_ptr={}", .{ casted_client_handle, @intFromPtr(client) });
                    _ = try ring.recv(@intFromPtr(client), casted_client_handle, .{ .buffer = &client.buffer }, 0);
                },
                .recv => {
                    log.info("recv. client_ptr={}", .{@intFromPtr(client)});
                    const read: usize = @intCast(cqe.res);
                    const casted_client_handle: i32 = @intCast(client.handle);
                    if (read == 0) {
                        const handle = client.handle;
                        assert(clients.remove(handle));
                        // TODO: (michel) is this leaking memory? How to know?
                        // TODO: (michel) not sure if leaking memory, but it's broken. Simple scenario to replicate the bug:
                        // - open terminal A, connect with telnet
                        // - open terminal B, connect with telnet
                        // - send message with terminal A
                        // - quit telnet with terminal B
                        // - boom
                        // TODO: the problem was fixed, but changed. What seems to have caused it originally was that a different pointer was being used to destroy the memory.
                        // According to the `destroy` docs:
                        // > `ptr` should be the return value of `create`, or otherwise have the same address and alignment property.
                        // The pointer being passed to `destroy` was _not_ the return value of `create`, it was a pointer from the iterator, and according to log-debugging it _didn't_
                        // have the same address and the error maybe complained about alignment.
                        // To fix that the map was changed to store `*Socket` instead of `Socket`. In that way the pointer returned by `create` could be stored in the map and then
                        // destroyed. As mentioned, that fixed the original problem, but there's still problems.
                        // For a still unknown reason after processing the first `recv` with `cqe.res == 0` after the client disconnects and destroying the related memory,
                        // there's at least another completion event related to that client (with the same pointer) with `cqe.res == 0` that gets to the queue. This causes a segfault
                        // because the memory the pointer is pointing to was freed. There seems to be a couple of ways to approach this problem but arguably the more robust one
                        // involves not using a pointer for the event's `user_data`, because after _very_ light research there doesn't seem to be a way to figure out from a pointer
                        // if the pointed-to memory was already freed. In other words, you cannot avoid the segfault. Relying on the client map for knowing each client's status
                        // then becomes a more robust approach because the map will live for the entire application lifecycle. The map is keyed with the client connection's file
                        // descriptor, so that could be the event's `user_data`. [TBC]
                        io_allocator.destroy(client);
                        _ = try ring.close(0, casted_client_handle); // `user_data` is 0 because the "user" has disconnected.
                        log.info("Client disconnected. handle={}", .{handle});
                        continue;
                    }
                    const msg = client.buffer[0..read];
                    log.info("recv: msg={s}; read={}", .{ msg, read });
                    var client_iterator = clients.valueIterator();
                    while (client_iterator.next()) |client_it| {
                        if (client.handle == client_it.*.handle) {
                            continue;
                        }
                        client_it.*.state = .send;
                        log.info("recv: Sending message. from={}; to={}; msg={s}", .{ client.handle, client_it.*.handle, msg });
                        const casted_client_it_handle: i32 = @intCast(client_it.*.handle);
                        _ = try ring.send(@intFromPtr(client_it.*), casted_client_it_handle, msg, 0);
                    }

                    _ = try ring.recv(@intFromPtr(client), casted_client_handle, .{ .buffer = &client.buffer }, 0);
                },
                .send => {
                    log.info("send: Sent. to={}", .{client.handle});
                    client.state = .recv;
                    const casted_client_handle: i32 = @intCast(client.handle);
                    _ = try ring.recv(@intFromPtr(client), casted_client_handle, .{ .buffer = &client.buffer }, 0);
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
