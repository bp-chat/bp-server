# TODO

- [ ] Define and implement the communication abstraction
- [ ] Clean up -test files.
- [ ] secure connection with SSL or whatever is appropriate (more secure)
- [ ] implement raw sockets and io_uring abstraction

## Implementation outlines

- secure connection with SSL or whatever is appropriate (more secure)
    - research: most secure way to...secure a TCP connection
    - research: what Zig supports to secure a TCP connection
    - research: how to implement a secure TCP connection in Zig

# DONE

- [x] fix disconnect bug with more than one client connected
- [x] io_uring: proper disconnet handling
- [x] fix client not being able to reconnect
- [x] do not ignore Linux socket connection errors and the like
- [x] Understand what the hell is going on, improve naive implementation
- [x] Relay dummy message
- [x] Read dummy message
- [x] Pass address to the client via args
- [x] Pass listening port to the server via args
- [x] Add test-client to the build
- [x] Remove root.zig from build
