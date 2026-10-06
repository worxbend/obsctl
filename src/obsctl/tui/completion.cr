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

        # A typed opening quote is punctuation, not part of the name being
        # filtered: `:scene "C` is still completing `C`.
        filter = argument_prefix.starts_with?('"') || argument_prefix.starts_with?('\'') ? argument_prefix[1..] : argument_prefix
        prefix = filter.downcase
        sorted(candidates.select(&.downcase.starts_with?(prefix)), filter)
          .map { |candidate| "#{command} #{quote_argument(candidate)}" }
      end

      # A candidate replaces the input line verbatim when cycled to, so a name
      # containing a space or a quote has to arrive quoted: `:scene Cam 1`
      # parses as two arguments and fails, while `:scene "Cam 1"` names the
      # scene. Inner quotes and backslashes are escaped the way the parser's
      # tokenizer reads them back.
      private def quote_argument(name : String) : String
        return name unless name.each_char.any? { |char| char.whitespace? || char == '"' || char == '\'' || char == '\\' }

        %("#{name.gsub('\\', "\\\\").gsub('"', "\\\"")}")
      end

      # Argument candidates for a command, driven by the kind its spec declares.
      #
      # Exhaustive (`in`, not `when`) over `ArgumentKind`, so a kind added to
      # the registry stops the build here instead of leaving the palette
      # silently completing nothing for it -- the same guarantee
      # `ArgumentKind#placeholder` carries on the help side. `None` and
      # `Percent` answer nil deliberately: neither names anything the dashboard
      # could list, so there is nothing to offer.
      private def candidates_for(command : String, model : Model) : Array(String)?
        spec = Domain::CommandRegistry[command]?
        return unless spec

        kind = spec.arguments.first?
        return unless kind

        case kind
        in .none?             then nil
        in .scene?            then model.scenes.flat_map { |scene| [scene.name, scene.alias].compact }
        in .profile?          then model.profiles
        in .scene_profile?    then model.scene_profiles.profiles.map(&.name)
        in .scene_collection? then model.scene_collections
        in .audio_input?      then model.audio_inputs.flat_map { |input_state| [input_state.name, input_state.alias].compact }
        in .percent?          then nil
        in .record_action?    then RECORD_ACTIONS
        end
      end

      private def sorted(candidates : Enumerable(String), exact : String) : Array(String)
        exact_lower = exact.downcase
        candidates.to_a.sort_by { |candidate| {candidate.downcase == exact_lower ? 0 : 1, candidate.downcase, candidate} }.uniq!
      end
    end
  end
end
