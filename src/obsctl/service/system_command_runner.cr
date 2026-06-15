module Obsctl
  module Service
    class SystemCommandRunner
      def run(command : String, args : Array(String)) : Process::Status
        Process.run(command, args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end
    end
  end
end
