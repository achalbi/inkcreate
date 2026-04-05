module Settings
  class PrivacyController < BrowserController
    before_action :require_authenticated_user!

    def show
      @app_setting = current_user.ensure_app_setting!
    end

    def update
      current_user.ensure_app_setting!.update!(
        privacy_options: parsed_json(params.require(:app_setting).fetch(:privacy_options, "{}"))
      )
      redirect_to settings_privacy_path, notice: "Privacy settings updated."
    end

    private

    def parsed_json(value)
      JSON.parse(value.presence || "{}")
    rescue JSON::ParserError
      raise ArgumentError, "Privacy options must be valid JSON"
    end
  end
end
