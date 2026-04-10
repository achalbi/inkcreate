require "test_helper"
require "capybara/rails"
require "selenium/webdriver"

Capybara.register_driver :headless_chromium do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.binary = ENV.fetch("CHROME_BIN", "/usr/bin/chromium")
  %w[
    --headless=new
    --disable-gpu
    --no-sandbox
    --window-size=1400,1400
  ].each { |argument| options.add_argument(argument) }

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include ActiveJob::TestHelper

  driven_by :headless_chromium

  private

  def set_datetime_local_field(element, value)
    execute_script(<<~JS, element.native, value)
      arguments[0].value = arguments[1];
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
      arguments[0].dispatchEvent(new Event("change", { bubbles: true }));
    JS
  end

  def sign_in_as(user, password: "Password123!")
    visit browser_sign_in_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Sign in"
    assert_current_path dashboard_path, wait: 10
  end
end
