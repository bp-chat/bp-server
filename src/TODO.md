# TODO

- [ ] Define and implement the communication abstraction
- [ ] Clean up -test files.
- [ ] fix client not being able to reconnect
- [ ] io_uring: proper disconnet handling
- [ ] secure connection with SSL or whatever is appropriate (more secure)
- [ ] implement raw sockets and io_uring abstraction

# DONE

- [x] do not ignore Linux socket connection errors and the like
- [x] Understand what the hell is going on, improve naive implementation
- [x] Relay dummy message
- [x] Read dummy message
- [x] Pass address to the client via args
- [x] Pass listening port to the server via args
- [x] Add test-client to the build
- [x] Remove root.zig from build
