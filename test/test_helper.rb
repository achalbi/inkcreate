ENV["RAILS_ENV"] ||= "test"
ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||= "1" * 32
ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||= "2" * 32
ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||= "3" * 32
require_relative "../config/environment"
require "rails/test_help"
require "nokogiri"

unless Object.method_defined?(:stub)
  class Object
    def stub(method_name, implementation)
      eigenclass = class << self; self; end
      backup_method = :"__codex_stub_#{method_name}_#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
      had_original = eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

      eigenclass.alias_method backup_method, method_name if had_original

      eigenclass.define_method(method_name) do |*args, **kwargs, &block|
        if implementation.respond_to?(:call)
          implementation.call(*args, **kwargs, &block)
        else
          implementation
        end
      end

      yield
    ensure
      eigenclass.remove_method(method_name) if eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

      if had_original
        eigenclass.alias_method method_name, backup_method
        eigenclass.remove_method(backup_method)
      end
    end
  end
end

class ActiveSupport::TestCase
end

class ActionDispatch::IntegrationTest
  private

  def authenticity_token_for(action_path)
    document = Nokogiri::HTML.parse(response.body)
    meta_token = document.at_css("meta[name='csrf-token']")&.[]("content")
    return meta_token if meta_token.present?

    form = document.css("form").find do |node|
      URI.parse(node["action"]).path == action_path
    end

    return form.at_css("input[name='authenticity_token']")["value"] if form

    capture_node = document.css("[data-document-capture-post-url-value]").find do |node|
      node["data-document-capture-post-url-value"] == action_path
    end

    return capture_node["data-document-capture-csrf-value"] if capture_node

    if response.redirect?
      redirect_target = URI.parse(response.redirect_url).request_uri
      get redirect_target
      return authenticity_token_for(action_path)
    end

    raise "No form or document capture token found for #{action_path}"
  end

  def sign_in_browser_user(user, password: "Password123!")
    get browser_sign_in_path

    post "/auth/sign-in", params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: user.email, password: password }
    }
  end
end
