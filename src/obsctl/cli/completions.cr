require "../domain/command_registry"
require "../domain/local_commands"
require "../domain/errors"

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

      GLOBAL_FLAGS = ["--config", "--log-level", "--color", "--timeout", "--force", "--json", "--quiet", "--version", "--help"]

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
          query = case spec.arguments.first?
                  when Domain::ArgumentKind::Scene           then "scenes"
                  when Domain::ArgumentKind::Profile         then "profiles"
                  when Domain::ArgumentKind::SceneCollection then "collections"
                  when Domain::ArgumentKind::AudioInput      then "audio"
                  end
          next unless query

          spec.spellings.each { |spelling| groups[query] << spelling }
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
      CANDIDATE_KINDS = ["scenes", "profiles", "collections", "audio"]

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

        case kind
        when "scenes"   then names_at(snapshot, "scenes")
        when "audio"    then names_at(snapshot, "audio_inputs")
        when "profiles" then strings_at(snapshot, "profiles")
        else                 strings_at(snapshot, "scene_collections")
        end
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
          io << "    --color) COMPREPLY=( $(compgen -W 'auto always never' -- \"$cur\") ); return ;;\n"
          io << "    --log-level) COMPREPLY=( $(compgen -W 'debug info warn error' -- \"$cur\") ); return ;;\n"
          io << "    --config) COMPREPLY=( $(compgen -f -- \"$cur\") ); return ;;\n"
          io << "    --timeout) return ;;\n"

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
          Domain::CommandRegistry.for_surface(Domain::CommandSurface::Cli).each do |spec|
            io << "    '" << spec.name << ":" << zsh_escape(spec.summary) << "'\n"
          end
          LOCAL_COMMANDS.each { |name| io << "    '" << name << ":local command'\n" }
          io << "  )\n\n"
          io << "  _arguments -C \\\n"
          io << "    '--config[Path to config.yml]:file:_files' \\\n"
          io << "    '--log-level[Log verbosity]:level:(debug info warn error)' \\\n"
          io << "    '--color[When to colorize]:when:(auto always never)' \\\n"
          io << "    '--timeout[Request timeout in seconds]:seconds:' \\\n"
          io << "    '--force[Overwrite files]' \\\n"
          io << "    '--json[Emit a JSON envelope]' \\\n"
          io << "    '(-q --quiet)'{-q,--quiet}'[Suppress human output]' \\\n"
          io << "    '(-V --version)'{-V,--version}'[Show the version]' \\\n"
          io << "    '(-h --help)'{-h,--help}'[Show help]' \\\n"
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
          io << "complete -c obsctl -l config -r -F -d 'Path to config.yml'\n"
          io << "complete -c obsctl -l log-level -x -a 'debug info warn error' -d 'Log verbosity'\n"
          io << "complete -c obsctl -l color -x -a 'auto always never' -d 'When to colorize'\n"
          io << "complete -c obsctl -l timeout -x -d 'Request timeout in seconds'\n"
          io << "complete -c obsctl -l force -d 'Overwrite files'\n"
          io << "complete -c obsctl -l json -d 'Emit a JSON envelope'\n"
          io << "complete -c obsctl -s q -l quiet -d 'Suppress human output'\n"
          io << "complete -c obsctl -s V -l version -d 'Show the version'\n"
          io << "complete -c obsctl -s h -l help -d 'Show help'\n\n"

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

      private def zsh_escape(text : String) : String
        text.gsub("'", %q('\'')).gsub(':', "\\:")
      end

      private def fish_escape(text : String) : String
        text.gsub("'", %q(\'))
      end
    end
  end
end
