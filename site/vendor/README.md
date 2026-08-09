# Vendored assets

Third-party files served by the microsite, committed rather than pulled from a CDN so
the site stays self-contained and has no third-party runtime dependency.

| File | Source | Version | License |
|---|---|---|---|
| `asciinema-player.min.js` | [asciinema/asciinema-player](https://github.com/asciinema/asciinema-player) | 3.17.0 | Apache-2.0 |
| `asciinema-player.css` | same | 3.17.0 | Apache-2.0 |

To refresh:

```sh
V=3.17.0
curl -sSLO "https://cdn.jsdelivr.net/npm/asciinema-player@$V/dist/bundle/asciinema-player.min.js"
curl -sSLO "https://cdn.jsdelivr.net/npm/asciinema-player@$V/dist/bundle/asciinema-player.css"
```

The player must keep supporting **asciicast v3** — that is the format `asciinema rec`
writes today, and the format `docs/demo/obsctl.cast` is recorded in.

The cast itself is not committed under `site/`. The Pages workflow copies
`docs/demo/obsctl.cast` into `site/demo/` at deploy time, the same way it copies
`install.sh`, so there is only ever one copy of the recording in the repository.
