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
- `obsctl service install`
- `obsctl service uninstall`
- `obsctl service status`
- `obsctl service start`
- `obsctl service stop`
- `obsctl service restart`
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

`obsctl server` starts the foreground local server and owns the OBS WebSocket connection. `obsctl server --headless` runs the same server without interactive UI and is intended for a `systemd --user` service.

`obsctl service install` writes `~/.config/systemd/user/obsctl.service` with an absolute `ExecStart=<obsctl> server --headless`, then runs `systemctl --user daemon-reload`. The other service subcommands wrap `systemctl --user start|stop|restart|status obsctl.service`; uninstall removes the unit file and reloads systemd.

Non-interactive OBS control commands are IPC clients. They connect to the local Unix socket, send a typed command to the server, print the response, and exit. If the server is unavailable, they print startup/service instructions and exit `3`.

`obsctl` and `obsctl tui` run the ANSI TUI as an IPC client in normal mode. The TUI subscribes to server state snapshots and forwards palette commands to the same server-owned command executor used by scriptable CLI commands.

TUI keyboard input:

- `/` or `:` opens the command palette with the configured command prefix.
- `Backspace` edits the current palette line.
- `Enter` submits the current palette command.
- `Esc` or `Ctrl-C` cancels palette editing.
- `q` exits from the dashboard.
- `r` sends `/reload-config` from the dashboard.
- `D` sends `/dump-config` from the dashboard.
