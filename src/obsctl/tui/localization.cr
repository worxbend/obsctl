module Obsctl
  module TUI
    # Small TUI-localized vocabulary matching the Rust header/connection
    # surface. Other dashboard copy is intentionally language-neutral there.
    module Localization
      extend self

      SUPPORTED = {"en", "uk"}

      EN = {
        :daemon_connected => "daemon: connected", :daemon_disconnected => "daemon: disconnected",
        :obs_connected => "OBS: connected (v%{value})", :obs_disconnected => "OBS: disconnected",
        :scene => "  scene: %{value}", :profile => "  profile: %{value}",
        :daemon_not_running => "obsctl server is not running", :could_not_connect => "Could not connect to obsctl daemon.",
        :start_daemon => "Start the daemon with:", :install_service => "Or install the service:",
        :retry => "Press R to retry, q to quit.", :not_connected => "Not connected to obsctl daemon.",
        :obs_state_connected => "OBS: connected", :obs_state_disconnected => "OBS: disconnected",
        :last_error => "last error: %{value}", :waiting => "Waiting for state...",
        :connection_title => " Connection ", :unavailable_title => " obsctl — daemon unavailable ",
      }

      UK = {
        :daemon_connected => "демон: з'єднано", :daemon_disconnected => "демон: не з'єднано",
        :obs_connected => "OBS: з'єднано (v%{value})", :obs_disconnected => "OBS: не з'єднано",
        :scene => "  сцена: %{value}", :profile => "  профіль: %{value}",
        :daemon_not_running => "сервер obsctl не запущено", :could_not_connect => "Не вдалося з'єднатися з демоном obsctl.",
        :start_daemon => "Запустіть демон командою:", :install_service => "Або встановіть службу:",
        :retry => "Натисніть R, щоб повторити, q — для виходу.", :not_connected => "Немає з'єднання з демоном obsctl.",
        :obs_state_connected => "OBS: з'єднано", :obs_state_disconnected => "OBS: не з'єднано",
        :last_error => "остання помилка: %{value}", :waiting => "Очікування стану...",
        :connection_title => " З'єднання ", :unavailable_title => " obsctl — демон недоступний ",
      }

      def resolve(configured : String?, environment : String? = ENV["OBSCTL_LOCALE"]?) : String
        environment = environment.try(&.strip)
        candidate = environment && !environment.empty? ? environment : (configured || "en")
        normalized = candidate.downcase
        SUPPORTED.includes?(normalized) ? normalized : "en"
      end

      def text(locale : String, key : Symbol, value : String? = nil) : String
        template = (locale == "uk" ? UK : EN)[key]? || key.to_s
        template.gsub("%{value}", value || "?")
      end
    end
  end
end
