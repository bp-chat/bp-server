# TODO

- [ ] Define and implement the communication abstraction
- [ ] Clean up -test files.
- [ ] secure connection with SSL or whatever is appropriate (more secure)
- [ ] implement raw sockets and io_uring abstraction

## Implementation outlines

- secure connection with SSL or whatever is appropriate (more secure)
    - research: most secure way to...secure a TCP connection
        - **answer**: after some small research TLS 1.3 seems to be the way to go. Check the TLS OWASP cheatsheet in one of the links below.
        - links:
            - https://security.stackexchange.com/questions/5126/whats-the-difference-between-ssl-tls-and-https
            - https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html
            - https://security.stackexchange.com/questions/241493/is-there-any-solution-beside-tls-for-data-in-transit-protection
            - https://softwareengineering.stackexchange.com/questions/271366/tls-alternatives-that-do-not-require-a-central-authority
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
