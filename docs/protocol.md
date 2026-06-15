# obs-websocket Protocol Notes

The client follows obs-websocket 5.x ordering:

1. Connect WebSocket.
2. Read `Hello` opcode `0`.
3. Send `Identify` opcode `1`.
4. Wait for `Identified` opcode `2`.
5. Send `Request` opcode `6`.
6. Match `RequestResponse` opcode `7` by `requestId`.
7. Consume `Event` opcode `5` for realtime updates.

Authentication uses `password + salt`, SHA256, Base64, then `base64_secret + challenge`, SHA256, Base64. Passwords and generated authentication strings must not be logged.
