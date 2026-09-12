require "base64"
require "openssl/digest"

module Obsctl
  module OBS
    # Implements the obs-websocket 5.x challenge authentication hash.
    module Auth
      # Returns the authentication response for the given password, salt, and
      # challenge. Callers must not log the returned value.
      def self.authentication(password : String, salt : String, challenge : String) : String
        secret = sha256_base64(password, salt)
        sha256_base64(secret, challenge)
      end

      private def self.sha256_base64(left : String, right : String) : String
        digest = OpenSSL::Digest.new("SHA256")
        digest.update(left)
        digest.update(right)
        Base64.strict_encode(digest.final)
      end
    end
  end
end
