require "spec"

# Pins every spec -- and every subprocess a spec spawns -- to a config path that
# deliberately does not exist, so the suite reads the developer's real
# ~/.config/obsctl/config.yml never and behaves exactly as it does on CI, where
# no config file is present. Without this, `spec/obsctl/tui/cli_pty_spec.cr`
# shells out to `crystal run src/obsctl.cr -- tui`, which inherits the
# environment and loads whatever the developer happens to have on disk: a
# single unrecognised key there fails a spec that has nothing to do with it.
#
# A missing path rather than a fixture file, because "no config" is the state
# CI runs in: lenient loads fall back to `Config.default` and strict loads raise
# `ConfigNotFound`, which is what the specs that care already expect. Specs
# needing a config of their own still pass `--config` or set `OBSCTL_CONFIG`
# around themselves.
ENV["OBSCTL_CONFIG"] = File.join(Dir.tempdir, "obsctl-spec-absent-config.yml")

require "../src/obsctl/config/config"
require "../src/obsctl/config/config_schema"
require "../src/obsctl/config/config_dump"
require "../src/obsctl/domain/command_parser"
require "../src/obsctl/domain/aliases"
require "../src/obsctl/obs/auth"
require "../src/obsctl/obs/protocol/request"
require "../src/obsctl/obs/protocol/response"
