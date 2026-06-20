module Obsctl
  module SpecSupport
    module OptionalObsctlRsCompat
      def self.sibling_repo : String
        File.expand_path("../../../obsctl-rs", __DIR__)
      end

      def self.sibling_present? : Bool
        File.directory?(sibling_repo)
      end

      def self.fixture_root : String?
        [
          File.join(sibling_repo, "spec/fixtures/contracts"),
          File.join(sibling_repo, "tests/fixtures/contracts"),
          File.join(sibling_repo, "fixtures/contracts"),
        ].find { |path| File.directory?(path) }
      end

      def self.local_fixture_paths(root : String) : Array(String)
        prefix_size = root.size + 1
        Dir.glob(File.join(root, "**", "*"))
          .select { |path| File.file?(path) }
          .map { |path| path[prefix_size..] }
          .sort
      end
    end
  end
end
