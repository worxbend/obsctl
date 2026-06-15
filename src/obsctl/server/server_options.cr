module Obsctl
  module Server
    # CLI-derived options for starting the server runtime.
    record ServerOptions,
      headless : Bool = false
  end
end
