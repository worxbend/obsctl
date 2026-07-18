require "./model"

module Obsctl
  module TUI
    module Completion
      extend self

      ALL_COMMANDS = [
        "/help", "/themes", "/scene", "/profile", "/collection",
        "/mute", "/unmute", "/toggle-mute", "/vol", "/stream", "/rec",
        "/status", "/obs-status", "/server-status", "/reload-config",
        "/dump-config", "/validate-config", "/reconnect", "/quit",
      ]

      def compute(input : String, model : Model) : Array(String)
        unless input.includes?(' ')
          prefix = input.downcase
          return sorted(ALL_COMMANDS.select(&.starts_with?(prefix)), input)
        end

        command, raw_prefix = input.split(' ', 2)
        argument_prefix = raw_prefix.lstrip
        candidates = case command.downcase
                     when "/scene", "/set-scene"
                       model.scenes.flat_map { |scene| [scene.name, scene.alias].compact }
                     when "/profile", "/set-profile"
                       model.profiles
                     when "/collection", "/set-collection", "/scene-collection"
                       model.scene_collections
                     when "/mute", "/unmute", "/toggle-mute", "/vol", "/volume"
                       model.audio_inputs.flat_map { |input_state| [input_state.name, input_state.alias].compact }
                     else
                       return [] of String
                     end
        prefix = argument_prefix.downcase
        sorted(candidates.select { |candidate| candidate.downcase.starts_with?(prefix) }, argument_prefix)
          .map { |candidate| "#{command} #{candidate}" }
      end

      private def sorted(candidates : Enumerable(String), exact : String) : Array(String)
        exact_lower = exact.downcase
        candidates.to_a.sort_by { |candidate| {candidate.downcase == exact_lower ? 0 : 1, candidate.downcase, candidate} }.uniq
      end
    end
  end
end
