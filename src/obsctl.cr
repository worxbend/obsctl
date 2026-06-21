require "./obsctl/ipc/protocol"
require "./obsctl/server/best_effort_log_broadcast"
require "./obsctl/cli/main"

exit Obsctl::CLI::Main.run(ARGV)
