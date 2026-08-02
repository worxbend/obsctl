require "../domain/command_registry"
require "./model"

module Obsctl
  module TUI
    module Completion
      extend self

      # Every palette spelling the parser accepts, plus the dashboard-only
      # settings view. Generated so completion cannot drift from the parser.
      ALL_COMMANDS = (Domain::CommandRegistry.palette_names + ["/themes"]).sort!

      # Bare `/rec` still toggles; these are the explicit actions.
      RECORD_ACTIONS = Domain::CommandRegistry::RECORD_ACTIONS.keys

      # Commands are registered with the `/` spelling, so a line opened with a
      # different leader -- `:` for a vim command line, or a configured prefix
      # -- is matched as its `/` equivalent and handed back wearing the leader
      # the user actually typed.
      def compute(input : String, model : Model) : Array(String)
        leader = input[0]?
        if leader && leader != '/' && (leader == ':' || model.command_palette_prefix.includes?(leader))
          return compute("/#{input[1..]}", model).map { |candidate| "#{leader}#{candidate[1..]}" }
        end

        unless input.includes?(' ')
          prefix = input.downcase
          return sorted(ALL_COMMANDS.select(&.starts_with?(prefix)), input)
        end

        command, raw_prefix = input.split(' ', 2)
        argument_prefix = raw_prefix.lstrip
        candidates = candidates_for(command, model)
        return [] of String unless candidates

        prefix = argument_prefix.downcase
        sorted(candidates.select(&.downcase.starts_with?(prefix)), argument_prefix)
          .map { |candidate| "#{command} #{candidate}" }
      end

      # Argument candidates for a command, driven by the kind its spec declares.
      private def candidates_for(command : String, model : Model) : Array(String)?
        spec = Domain::CommandRegistry[command]?
        return unless spec

        case spec.arguments.first?
        when Domain::ArgumentKind::Scene
          model.scenes.flat_map { |scene| [scene.name, scene.alias].compact }
        when Domain::ArgumentKind::Profile
          model.profiles
        when Domain::ArgumentKind::SceneCollection
          model.scene_collections
        when Domain::ArgumentKind::AudioInput
          model.audio_inputs.flat_map { |input_state| [input_state.name, input_state.alias].compact }
        when Domain::ArgumentKind::RecordAction
          RECORD_ACTIONS
        end
      end

      private def sorted(candidates : Enumerable(String), exact : String) : Array(String)
        exact_lower = exact.downcase
        candidates.to_a.sort_by { |candidate| {candidate.downcase == exact_lower ? 0 : 1, candidate.downcase, candidate} }.uniq!
      end
    end
  end
end
