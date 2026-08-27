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
        return if node.value.empty? && !quoted?(node)

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

  # Every field this type declares, in declaration order.
  #
  # `Config#to_yaml` is written by hand rather than derived from these
  # declarations, because the on-disk format has key-order and omit-when-unset
  # rules that a generated serializer would not follow. That leaves a gap: a
  # field added here is loaded correctly but can be silently dropped on write,
  # which loses the setting the next time `obsctl config migrate` rewrites the
  # file. Exposing the names gives `config_to_yaml_coverage_spec.cr` something
  # mechanical to check the writers against.
  FIELD_NAMES = [
    {% for field in fields %}
      {{ field.var.stringify }},
    {% end %}
  ] of String

  {% for field in fields %}
    {% if field.type.stringify == "String" %}
      @[YAML::Field(key: {{ field.var.stringify }}, converter: Obsctl::Config::ScalarStringConverter)]
    {% elsif field.type.stringify == "String?" %}
      @[YAML::Field(key: {{ field.var.stringify }}, converter: Obsctl::Config::OptionalScalarStringConverter)]
    {% else %}
      @[YAML::Field(key: {{ field.var.stringify }})]
    {% end %}
    getter {{ field.var.id }} : {{ field.type }}{% unless field.value.is_a?(Nop) %} = {{ field.value }}{% end %}
  {% end %}

  def initialize(
    {% for field in fields %}
      @{{ field.var.id }} : {{ field.type }}{% unless field.value.is_a?(Nop) %} = {{ field.value }}{% end %},
    {% end %}
  )
  end

  # Returns a copy of this config with only the named settings changed.
  #
  # `config_value` emits `getter`, not `property`, so changing one setting
  # means rebuilding the whole struct. Callers that do that (the dashboard
  # persists a theme change back to the config file) would each have to list
  # every field, and a field left out of any one of those lists writes its
  # default over a value the user set, with no error anywhere. Generating the
  # method from the same field list as everything else means adding a setting
  # cannot leave it behind.
  #
  # Each parameter's external name is the field name so call sites read
  # naturally, but the internal name is prefixed: a field may be named after
  # a keyword (`alias`), which Crystal accepts as an argument label but not
  # as a plain parameter name.
  def copy_with(
    {% for field in fields %}
      {{ field.var.id }} __{{ field.var.id }} : {{ field.type }} = @{{ field.var.id }},
    {% end %}
  ) : self
    self.class.new(
      {% for field in fields %}
        {{ field.var.id }}: __{{ field.var.id }},
      {% end %}
    )
  end
end
