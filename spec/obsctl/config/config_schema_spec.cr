require "../../spec_helper"

describe Obsctl::Config::ConfigSchema do
  it "rejects duplicate scene aliases" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      scenes: [
        Obsctl::Config::SceneConfig.new(name: "A", alias: "main"),
        Obsctl::Config::SceneConfig.new(name: "B", alias: "main"),
      ]
    )
    expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(config)
    end
  end
end
