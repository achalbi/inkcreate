ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "nokogiri"

class ActiveSupport::TestCase
end

class ActionDispatch::IntegrationTest
  private

  def authenticity_token_for(action_path)
    document = Nokogiri::HTML.parse(response.body)
    form = document.css("form").find do |node|
      URI.parse(node["action"]).path == action_path
    end

    raise "No form found for #{action_path}" unless form

    form.at_css("input[name='authenticity_token']")["value"]
  end

  def sign_in_browser_user(user, password: "Password123!")
    get browser_sign_in_path

    post "/auth/sign-in", params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: user.email, password: password }
    }
  end
end
