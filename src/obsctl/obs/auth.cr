require "base64"
require "openssl/digest"

module Obsctl
  module OBS
    module Auth
      def self.authentication(password : String, salt : String, challenge : String) : String
        secret = Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(password + salt).final)
        Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(secret + challenge).final)
      end
    end
  end
end
