require "base64"
require "openssl/digest"

module Obsctl
  module OBS
    # Implements the obs-websocket 5.x challenge authentication hash.
    module Auth
      # Returns the authentication response for the given password, salt, and
      # challenge. Callers must not log the returned value.
      def self.authentication(password : String, salt : String, challenge : String) : String
        secret = Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(password + salt).final)
        Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(secret + challenge).final)
      end
    end
  end
end
