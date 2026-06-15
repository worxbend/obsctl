module Obsctl
  module Service
    # Thin wrapper around `Process.run` for system command dependency injection.
    class SystemCommandRunner
      # Runs a system command while inheriting stdout and stderr.
      def run(command : String, args : Array(String)) : Process::Status
        Process.run(command, args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end
    end
  end
end
