require "./obsctl/ipc/protocol"
require "./obsctl/cli/main"

exit Obsctl::CLI::Main.run(ARGV)
