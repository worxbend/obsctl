require "../domain/command_registry"
require "../domain/local_commands"
require "../domain/errors"
require "./options"

module Obsctl
  module CLI
    # Generates shell completion scripts from the command registry.
    #
    # Nothing here hardcodes a command name: the word lists come from
    # `Domain::CommandRegistry`, so a command added there completes everywhere
    # without a second edit. Argument values that only the daemon knows —
    # scene, profile, collection, and audio-input names — are completed by
    # shelling back out to `obsctl`, which keeps the suggestions live.
    module Completions
      extend self

      SHELLS = ["bash", "zsh", "fish"]

      # Both derived from `Domain::LocalCommands`, which declares the local
      # command surface once. `completions` is itself one of them, so a shell
      # script that offered a different set than `--help` documents would be
      # this file disagreeing with its own registry.
      LOCAL_SUBCOMMANDS = Domain::LocalCommands.subcommands

      LOCAL_COMMANDS = Domain::LocalCommands.completion_names

      # Derived from `OptionsParser::FLAGS`, the single declaration of the
      # global option surface, so a flag added there completes everywhere
      # without a per-shell edit — the same guarantee the command lists get
      # from `Domain::CommandRegistry`.
      GLOBAL_FLAGS = OptionsParser::FLAGS.map(&.long)

      # One row per live-completable argument kind: the word `obsctl
      # completions candidates` accepts, the state-snapshot key holding the
      # values, and whether the entries are `{"name": ...}` objects or bare
      # strings. Declared once so the kind list, the command grouping, and the
      # snapshot extraction cannot drift apart.
      private record CandidateSource, kind : String, snapshot_key : String, named : Bool

      SOURCES = {
        Domain::ArgumentKind::Scene           => CandidateSource.new("scenes", "scenes", named: true),
        Domain::ArgumentKind::Profile         => CandidateSource.new("profiles", "profiles", named: false),
        Domain::ArgumentKind::SceneCollection => CandidateSource.new("collections", "scene_collections", named: false),
        Domain::ArgumentKind::AudioInput      => CandidateSource.new("audio", "audio_inputs", named: true),
        Domain::ArgumentKind::SceneProfile    => CandidateSource.new("scene-profiles", "scene_profiles", named: true),
      }

      # Renders the completion script for one shell.
      def render(shell : String) : String
        case shell
        when "bash" then bash
        when "zsh"  then zsh
        when "fish" then fish
        else
          raise Domain::CommandParseError.new("unknown shell: #{shell}; expected #{SHELLS.join(", ")}")
        end
      end

      # Every word that can appear in the command position.
      def commands : Array(String)
        (Domain::CommandRegistry.cli_spellings + LOCAL_COMMANDS).uniq!.sort!
      end

      # Commands whose first argument names a live OBS resource, grouped by the
      # `obsctl` query that lists those names.
      def dynamic_argument_commands : Hash(String, Array(String))
        groups = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

        Domain::CommandRegistry.for_surface(Domain::CommandSurface::Cli).each do |spec|
          next unless kind = spec.arguments.first?
          next unless source = SOURCES[kind]?

          spec.spellings.each { |spelling| groups[source.kind] << spelling }
        end

        groups
      end

      # Commands whose first argument is a fixed word list.
      def static_argument_commands : Hash(String, Array(String))
        groups = {} of String => Array(String)

        Domain::CommandRegistry.for_surface(Domain::CommandSurface::Cli).each do |spec|
          next unless spec.arguments.first? == Domain::ArgumentKind::RecordAction

          spec.spellings.each do |spelling|
            groups[spelling] = Domain::CommandRegistry::RECORD_ACTIONS.keys
          end
        end

        LOCAL_SUBCOMMANDS.each { |name, values| groups[name] = values }
        groups["completions"] = SHELLS + ["candidates"]
        groups["candidates"] = CANDIDATE_KINDS
        groups
      end

      # Kinds of live name `obsctl completions candidates` can list.
      CANDIDATE_KINDS = SOURCES.values.map(&.kind)

      # The shell command that lists live names, one per line.
      #
      # obsctl does the JSON parsing itself rather than making each shell
      # dialect scrape the envelope: the names can contain spaces, quotes, and
      # commas, which no amount of sed gets right.
      private def names_query(kind : String) : String
        "obsctl completions candidates #{kind} 2>/dev/null"
      end

      # Lists live names for one kind, one per line.
      #
      # Completion runs on every Tab press, so an unreachable daemon or a
      # malformed reply yields no candidates instead of an error: a shell
      # completion that prints a diagnostic into the command line is worse than
      # one that suggests nothing.
      def candidates(kind : String, snapshot : JSON::Any?) : Array(String)
        # Validate before the snapshot check, so a typo is still reported when
        # no daemon is running.
        unless CANDIDATE_KINDS.includes?(kind)
          raise Domain::CommandParseError.new("unknown candidate kind: #{kind}; expected #{CANDIDATE_KINDS.join(", ")}")
        end
        return [] of String unless snapshot

        source = SOURCES.values.find! { |entry| entry.kind == kind }
        source.named ? names_at(snapshot, source.snapshot_key) : strings_at(snapshot, source.snapshot_key)
      end

      private def names_at(snapshot : JSON::Any, key : String) : Array(String)
        snapshot[key]?.try(&.as_a?).try(&.compact_map { |entry| entry["name"]?.try(&.as_s?) }) || [] of String
      end

      private def strings_at(snapshot : JSON::Any, key : String) : Array(String)
        snapshot[key]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def bash : String
        String.build do |io|
          io << "# obsctl bash completion. Install with:\n"
          io << "#   obsctl completions bash > /etc/bash_completion.d/obsctl\n"
          io << "#   # or: obsctl completions bash >> ~/.bashrc\n\n"
          io << "_obsctl() {\n"
          io << "  local cur prev words cword\n"
          io << "  cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
          io << "  prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n\n"
          io << "  case \"$prev\" in\n"
          OptionsParser::FLAGS.each do |flag|
            next unless flag.takes_value?

            if candidates = flag.candidates
              io << "    " << flag.long << ") COMPREPLY=( $(compgen -W '" << candidates.join(' ') << "' -- \"$cur\") ); return ;;\n"
            elsif flag.file_completion
              io << "    " << flag.long << ") COMPREPLY=( $(compgen -f -- \"$cur\") ); return ;;\n"
            else
              # A value with neither a word list nor file completion (a number
              # like --timeout): consume the word and suggest nothing.
              io << "    " << flag.long << ") return ;;\n"
            end
          end

          static_argument_commands.each do |name, values|
            io << "    " << name << ") COMPREPLY=( $(compgen -W '" << values.join(' ') << "' -- \"$cur\") ); return ;;\n"
          end
          dynamic_argument_commands.each do |kind, names|
            io << "    " << names.join('|') << ")\n"
            io << "      local IFS=$'\\n'\n"
            io << "      COMPREPLY=( $(compgen -W \"$(" << names_query(kind) << ")\" -- \"$cur\") ); return ;;\n"
          end

          io << "  esac\n\n"
          io << "  if [[ \"$cur\" == -* ]]; then\n"
          io << "    COMPREPLY=( $(compgen -W '" << GLOBAL_FLAGS.join(' ') << "' -- \"$cur\") )\n"
          io << "  else\n"
          io << "    COMPREPLY=( $(compgen -W '" << commands.join(' ') << "' -- \"$cur\") )\n"
          io << "  fi\n"
          io << "}\n"
          io << "complete -F _obsctl obsctl\n"
        end
      end

      private def zsh : String
        String.build do |io|
          io << "#compdef obsctl\n"
          io << "# obsctl zsh completion. Install with:\n"
          io << "#   obsctl completions zsh > \"${fpath[1]}/_obsctl\"\n\n"
          io << "_obsctl() {\n"
          io << "  local -a commands\n"
          io << "  commands=(\n"
          # Aliases are offered too, sharing the canonical command's summary.
          # Listing only canonical names left a spelling like
          # `scene-profile-clear` -- an alias on a command that takes no
          # argument, so it appears in no argument group either -- reachable
          # from the parser but suggested by nothing.
          Domain::CommandRegistry.for_surface(Domain::CommandSurface::Cli).each do |spec|
            spec.spellings.each do |spelling|
              io << "    '" << spelling << ":" << zsh_escape(spec.summary) << "'\n"
            end
          end
          LOCAL_COMMANDS.each { |name| io << "    '" << name << ":local command'\n" }
          io << "  )\n\n"
          io << "  _arguments -C \\\n"
          OptionsParser::FLAGS.each do |flag|
            io << "    " << zsh_flag_spec(flag) << " \\\n"
          end
          io << "    '1: :->command' \\\n"
          io << "    '*:: :->argument'\n\n"
          io << "  case \"$state\" in\n"
          io << "    command) _describe -t commands 'obsctl command' commands ;;\n"
          io << "    argument)\n"
          io << "      case \"$words[1]\" in\n"

          static_argument_commands.each do |name, values|
            io << "        " << name << ") _values '" << name << "' " << values.join(' ') << " ;;\n"
          end
          dynamic_argument_commands.each do |kind, names|
            io << "        " << names.join('|') << ")\n"
            io << "          local -a names\n"
            io << "          names=(${(f)\"$(" << names_query(kind) << ")\"})\n"
            io << "          _describe -t names '" << kind << "' names ;;\n"
          end

          io << "      esac ;;\n"
          io << "  esac\n"
          io << "}\n\n"
          io << "_obsctl \"$@\"\n"
        end
      end

      private def fish : String
        String.build do |io|
          io << "# obsctl fish completion. Install with:\n"
          io << "#   obsctl completions fish > ~/.config/fish/completions/obsctl.fish\n\n"
          io << "complete -c obsctl -f\n\n"
          OptionsParser::FLAGS.each do |flag|
            io << "complete -c obsctl"
            if short = flag.short
              io << " -s " << short.lchop('-')
            end
            io << " -l " << flag.long.lchop("--")
            if flag.takes_value?
              if flag.file_completion
                # -r keeps fish expecting a value; -F restores the file
                # completion that the blanket `complete -c obsctl -f` disabled.
                io << " -r -F"
              else
                io << " -x"
                if candidates = flag.candidates
                  io << " -a '" << candidates.join(' ') << "'"
                end
              end
            end
            io << " -d '" << flag.completion_description << "'\n"
          end
          io << "\n"

          Domain::CommandRegistry.for_surface(Domain::CommandSurface::Cli).each do |spec|
            spec.spellings.each do |spelling|
              io << "complete -c obsctl -n __fish_use_subcommand -a " << spelling
              io << " -d '" << fish_escape(spec.summary) << "'\n"
            end
          end
          LOCAL_COMMANDS.each do |name|
            io << "complete -c obsctl -n __fish_use_subcommand -a " << name << "\n"
          end

          io << "\n"
          static_argument_commands.each do |name, values|
            io << "complete -c obsctl -n \"__fish_seen_subcommand_from " << name << "\""
            io << " -a '" << values.join(' ') << "'\n"
          end
          dynamic_argument_commands.each do |kind, names|
            io << "complete -c obsctl -n \"__fish_seen_subcommand_from " << names.join(' ') << "\""
            io << " -a \"(" << names_query(kind) << ")\"\n"
          end
        end
      end

      # One `_arguments` spec for a global flag: mutual-exclusion group plus
      # brace expansion when a short form exists, and for value flags the
      # `:label:action` tail — a candidate list, `_files`, or an empty action
      # that accepts free text (e.g. `--timeout`'s number of seconds).
      private def zsh_flag_spec(flag : FlagSpec) : String
        String.build do |spec|
          if short = flag.short
            spec << "'(" << short << ' ' << flag.long << ")'{" << short << ',' << flag.long << "}'[" << flag.completion_description << "]'"
          else
            spec << '\'' << flag.long << '[' << flag.completion_description << ']'
            if flag.takes_value?
              spec << ':' << flag.value_label << ':'
              if candidates = flag.candidates
                spec << '(' << candidates.join(' ') << ')'
              elsif flag.file_completion
                spec << "_files"
              end
            end
            spec << '\''
          end
        end
      end

      private def zsh_escape(text : String) : String
        text.gsub("'", %q('\'')).gsub(':', "\\:")
      end

      private def fish_escape(text : String) : String
        text.gsub("'", %q(\'))
      end
    end
  end
end
