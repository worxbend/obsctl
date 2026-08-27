module Obsctl
  module Runtime
    # Single source of truth for scrubbing secret-shaped text out of anything
    # that leaves the process: log lines, IPC error messages, and config dumps
    # all pull their rules from here. The ruleset used to live twice — in
    # `Runtime::Logger` and in `IPC::ErrorPayload` — and a new secret-shaped
    # key added to one copy but not the other would silently leak credentials
    # on the forgotten path.
    #
    # Deliberately requires nothing project-internal: the IPC layer must be
    # able to load this without dragging in config or runtime plumbing.
    module SecretRedaction
      SENSITIVE_KEY_PATTERN   = "(?:password|authentication(?:[ _-]?string)?|auth(?:[ _-]?string)?|token|secret)"
      SENSITIVE_VALUE_PATTERN = "(?:\"[^\"]*\"|'[^']*'|\\S+)"

      # The shapes a credential can take in a human-readable message, one rule
      # per shape: `password=hunter2`, `password: hunter2`, `password "hunter2"`,
      # and the copula form `password is hunter2`.
      #
      # These are compiled once at load rather than per call because
      # redaction runs on every failed IPC command and every log line, on both
      # the daemon and the client side. Keeping them as a named table also
      # makes the security-relevant ruleset readable as a list.
      private ASSIGNMENT_RULE = {Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s*=\\s*#{SENSITIVE_VALUE_PATTERN}"), "\\1=[redacted]"}
      private COLON_RULE      = {Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s*:\\s*#{SENSITIVE_VALUE_PATTERN}"), "\\1: [redacted]"}
      private QUOTED_RULE     = {Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s+(\"[^\"]*\"|'[^']*')"), "\\1 [redacted]"}
      private COPULA_RULE     = {Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s+(is|was|equals|set to|configured as|provided as)\\s+#{SENSITIVE_VALUE_PATTERN}"), "\\1 \\2 [redacted]"}

      # Order matters: each rule is applied to the output of the previous one.
      private REDACTION_RULES = [ASSIGNMENT_RULE, COLON_RULE, QUOTED_RULE, COPULA_RULE]

      # Redacts secret-like values from a human-readable message.
      def self.redact(message : String) : String
        REDACTION_RULES.reduce(message) do |text, (pattern, replacement)|
          text.gsub(pattern, replacement)
        end
      end
    end
  end
end
