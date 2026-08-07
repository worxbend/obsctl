require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Logs
        extend self

        enum ResourceKind
          Scene
          Audio
          Profile
          Collection
        end

        DANGER_KEYWORDS  = %w[error failed failure disconnected unavailable denied invalid malformed timeout dropped closed fatal]
        WARNING_KEYWORDS = %w[warning warn retry reconnect reconnecting muted stopped shutdown stale]
        SUCCESS_KEYWORDS = %w[connected ready started active switched reloaded success enabled unmuted streaming recording complete]
        SUBJECT_KEYWORDS = %w[obs scene profile collection audio input source stream record config daemon server command websocket]

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          visible = {area.height - 2, 0}.max
          entries = model.logs.last(visible)
          resources = known_resources(model)
          items = entries.map do |entry|
            color, marker = level_appearance(entry.level, model)
            spans = [
              CryTUI::Span.new(" #{marker} ", CryTUI::Style.new(foreground: color)),
              CryTUI::Span.new(entry.timestamp.to_s("%H:%M:%S"), CryTUI::Style.new(foreground: model.theme.muted)),
              CryTUI::Span.new(" #{entry.level.to_s.upcase.ljust(5)} ", CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold)),
              CryTUI::Span.new(entry.code ? "#{entry.code}  " : "", CryTUI::Style.new(foreground: model.theme.accent_alt)),
            ]
            spans.concat(highlight_message(entry.message, model, resources))
            CryTUI::Widgets::ListItem.new([CryTUI::Line.new(spans)])
          end
          block = Chrome.panel(feed_icon(model), "Logs // Event Stream", "live daemon feed", model.logs.size, false, model)
          CryTUI::Widgets::List.new(items, block: block).render(area, buffer, CryTUI::Widgets::ListState.new)
        end

        def highlight_message(message : String, model : Model, resources = known_resources(model)) : Array(CryTUI::Span)
          spans = [] of CryTUI::Span
          cursor = 0
          while cursor < message.bytesize
            rest = message.byte_slice(cursor, message.bytesize - cursor)
            if resource = resources.find { |name, _| resource_matches?(rest, name) }
              name, kind = resource
              matched = rest.byte_slice(0, name.bytesize)
              spans << CryTUI::Span.new(matched, resource_style(kind, model))
              cursor += matched.bytesize
              next
            end

            char = rest.each_char.first
            if {'\'', '"', '`'}.includes?(char)
              closing = rest.index(char, 1)
              quoted = closing ? rest[0..closing] : rest
              inner = closing ? quoted[1...-1] : nil
              kind = inner.try { |value| exact_resource_kind(value, resources) }
              style = kind ? resource_style(kind, model) : CryTUI::Style.new(foreground: model.theme.accent_alt, modifiers: CryTUI::Modifier::Italic)
              spans << CryTUI::Span.new(quoted, style)
              cursor += quoted.bytesize
              next
            end

            if rest.starts_with?("->") || rest.starts_with?("=>")
              spans << CryTUI::Span.new(rest.byte_slice(0, 2), CryTUI::Style.new(foreground: model.theme.accent, modifiers: CryTUI::Modifier::Bold))
              cursor += 2
              next
            end

            if token_char?(char)
              token = rest.each_char.take_while { |candidate| token_char?(candidate) }.join
              spans << CryTUI::Span.new(token, token_style(token, model))
              cursor += token.bytesize
              next
            end

            spans << CryTUI::Span.new(char.to_s, CryTUI::Style.new(foreground: model.theme.foreground))
            cursor += char.bytesize
          end
          spans
        end

        def known_resources(model : Model) : Array(Tuple(String, ResourceKind))
          resources = [] of Tuple(String, ResourceKind)
          model.snapshot.try do |snapshot|
            snapshot.scenes.each do |scene|
              resources << {scene.name, ResourceKind::Scene}
              if alias_name = scene.alias
                resources << {alias_name, ResourceKind::Scene}
              end
            end
            snapshot.audio_inputs.each do |input|
              resources << {input.name, ResourceKind::Audio}
              if alias_name = input.alias
                resources << {alias_name, ResourceKind::Audio}
              end
            end
          end
          model.profiles.each { |name| resources << {name, ResourceKind::Profile} }
          model.scene_collections.each { |name| resources << {name, ResourceKind::Collection} }
          resources.reject! { |name, _| name.empty? }
          resources.sort_by! { |name, _| -name.bytesize }
          resources.uniq! { |name, _| name.downcase }
          resources
        end

        # The dish turns while the daemon is feeding the panel, and stops when
        # there is nothing coming through.
        private def feed_icon(model : Model) : String
          return model.symbol("📡", "L") unless model.advanced_ui && model.connected_to_daemon

          CryTUI::Widgets::FluxSpinner.new(
            model.anim.frame,
            frames: CryTUI::Widgets::FluxFrames::MOON,
            ticks_per_step: 3_u64
          ).glyph
        end

        private def level_appearance(level : Runtime::LogLevel, model : Model) : Tuple(CryTUI::Color, String)
          case level
          when .info?  then {model.theme.info, model.symbol("●", "i")}
          when .warn?  then {model.theme.warning, model.symbol("▲", "!")}
          when .error? then {model.theme.danger, model.symbol("◆", "x")}
          else              {model.theme.muted, model.symbol("◦", ".")}
          end
        end

        private def resource_matches?(candidate : String, name : String) : Bool
          return false if candidate.bytesize < name.bytesize
          return false unless candidate.byte_slice(0, name.bytesize).compare(name, case_insensitive: true) == 0
          suffix = candidate.byte_slice(name.bytesize, candidate.bytesize - name.bytesize)
          next_char = suffix.each_char.first?
          next_char.nil? || !boundary_word_char?(next_char)
        end

        private def exact_resource_kind(candidate : String, resources) : ResourceKind?
          resources.find { |name, _| name.compare(candidate, case_insensitive: true) == 0 }.try(&.[1])
        end

        private def boundary_word_char?(char : Char) : Bool
          char.alphanumeric? || char == '_'
        end

        private def token_char?(char : Char) : Bool
          char.alphanumeric? || {'_', '-', '/', ':', '.', '%', '#'}.includes?(char)
        end

        private def resource_style(kind : ResourceKind, model : Model) : CryTUI::Style
          color = case kind
                  when .scene?      then model.theme.accent
                  when .audio?      then model.theme.info
                  when .profile?    then model.theme.warning
                  when .collection? then model.theme.accent_alt
                  else                   model.theme.foreground
                  end
          CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold)
        end

        private def token_style(token : String, model : Model) : CryTUI::Style
          normalized = token.strip(".:/").downcase
          color = if token.starts_with?("/")
                    model.theme.accent
                  elsif DANGER_KEYWORDS.includes?(normalized)
                    model.theme.danger
                  elsif WARNING_KEYWORDS.includes?(normalized)
                    model.theme.warning
                  elsif SUCCESS_KEYWORDS.includes?(normalized)
                    model.theme.success
                  elsif SUBJECT_KEYWORDS.includes?(normalized)
                    model.theme.accent_alt
                  elsif token.each_char.any?(&.ascii_number?)
                    model.theme.info
                  end
          CryTUI::Style.new(foreground: color || model.theme.foreground, modifiers: color ? CryTUI::Modifier::Bold : CryTUI::Modifier::None)
        end
      end
    end
  end
end
