# Command Grammar

Palette commands start with `/`. Non-interactive CLI commands map to the same typed command parser.

Required commands:

- `obsctl server`
- `obsctl server --headless`
- `obsctl status`
- `obsctl server-status`
- `obsctl scene <alias|shortcut|obs-name>`
- `obsctl mute <audio-alias|shortcut|obs-name>`
- `obsctl unmute <audio-alias|shortcut|obs-name>`
- `obsctl toggle-mute <audio-alias|shortcut|obs-name>`
- `obsctl vol|volume <audio-alias|shortcut|obs-name> <0-100>`
- `obsctl dump-config`
- `obsctl reload-config`
- `/help`
- `/set-scene <alias|shortcut|obs-name>`
- `/scene <alias|shortcut|obs-name>`
- `/mute <audio-alias|shortcut|obs-name>`
- `/unmute <audio-alias|shortcut|obs-name>`
- `/toggle-mute <audio-alias|shortcut|obs-name>`
- `/vol <audio-alias|shortcut|obs-name> <0-100>`
- `/dump-config`
- `/reload-config`
- `/status`
- `/server-status`
- `/connect`
- `/disconnect`
- `/quit`

Quoted names are preserved: `/scene "Main Camera"`.

`obsctl server` starts the foreground local server and owns the OBS WebSocket connection. `obsctl server --headless` runs the same server without interactive UI and is intended for a future `systemd --user` service.

Non-interactive OBS control commands are IPC clients. They connect to the local Unix socket, send a typed command to the server, print the response, and exit. If the server is unavailable, they print startup/service instructions and exit `3`.
