require "yaml"

module Obsctl
  module Config
    # Reads a YAML scalar as a string whatever its implied type.
    #
    # `shortcut: 1` and `shortcut: "1"` mean the same thing to a user, and YAML
    # would otherwise hand back an Int for the first.
    module ScalarStringConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : String
        node.raise "Expected scalar, not #{node.class}" unless node.is_a?(YAML::Nodes::Scalar)

        node.value
      end

      def self.to_yaml(value : String, yaml : YAML::Nodes::Builder) : Nil
        yaml.scalar(value)
      end
    end

    # The same leniency for optional fields, where a bare `key:` means absent.
    module OptionalScalarStringConverter
      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : String?
        node.raise "Expected scalar, not #{node.class}" unless node.is_a?(YAML::Nodes::Scalar)
        return nil if node.value.empty? && !quoted?(node)

        node.value
      end

      def self.to_yaml(value : String?, yaml : YAML::Nodes::Builder) : Nil
        value ? yaml.scalar(value) : yaml.scalar("")
      end

      # `key: ""` is a deliberate empty value; `key:` is an omission.
      private def self.quoted?(node : YAML::Nodes::Scalar) : Bool
        node.style.double_quoted? || node.style.single_quoted?
      end
    end
  end
end

# Declares a config value type from a single field list.
#
# One declaration produces the getters, the YAML mapping, and the ordinary
# Crystal initializer, so adding a setting is one line rather than an edit in
# three parallel places. String fields get the lenient scalar converters
# automatically: every string in this schema is a user-facing name, alias, or
# path, where YAML's type inference is unhelpful.
#
# Defined at the top level for the same reason `record` is: it is called from
# inside the type body it describes.
macro config_value(*fields)
  include YAML::Serializable

  {% for field in fields %}
    {% if field.type.stringify == "String" %}
      @[YAML::Field(key: {{field.var.stringify}}, converter: Obsctl::Config::ScalarStringConverter)]
    {% elsif field.type.stringify == "String?" %}
      @[YAML::Field(key: {{field.var.stringify}}, converter: Obsctl::Config::OptionalScalarStringConverter)]
    {% else %}
      @[YAML::Field(key: {{field.var.stringify}})]
    {% end %}
    getter {{field.var.id}} : {{field.type}}{% unless field.value.is_a?(Nop) %} = {{field.value}}{% end %}
  {% end %}

  def initialize(
    {% for field in fields %}
      @{{field.var.id}} : {{field.type}}{% unless field.value.is_a?(Nop) %} = {{field.value}}{% end %},
    {% end %}
  )
  end
end
