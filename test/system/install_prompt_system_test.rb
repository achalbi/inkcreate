require "application_system_test_case"

class InstallPromptSystemTest < ApplicationSystemTestCase
  test "landing install CTA appears only when the browser exposes an install prompt and downgrades after dismissal" do
    visit root_path
    reset_install_prompt_state

    inject_install_prompt

    assert_selector "button[data-install-prompt-target='promptButton']:not([hidden])", visible: :all
    dismiss_install_prompt

    assert_selector "button[data-install-prompt-target='promptButton'][hidden]", visible: :all
    assert_text "Install dismissed for now. Use the install guide when you want to add Inkcreate later."
  end

  test "landing install CTA downgrades into post-install setup after acceptance" do
    visit root_path
    reset_install_prompt_state

    inject_install_prompt

    assert_selector "button[data-install-prompt-target='promptButton']:not([hidden])", visible: :all
    dispatch_app_installed

    assert_selector "button[data-install-prompt-target='promptButton'][hidden]", visible: :all
    assert_text "Inkcreate is already installed on this device. Open it from your home screen or app shelf when you want the app shell."
    assert_text "Notifications are enabled for this device. Background sync updates can now appear after install."
  end

  test "install route recovers from a stale installed flag once install becomes available again" do
    visit install_path
    reset_install_prompt_state

    execute_script(<<~JS)
      window.localStorage.setItem("inkcreate.installPrompt.installed", "true");
    JS

    inject_install_prompt
    click_button "Install on this device"

    assert_text "Enable background sync updates"
  end

  private

  def reset_install_prompt_state
    execute_script(<<~JS)
      window.localStorage.removeItem("inkcreate.installPrompt.collapsed");
      window.localStorage.removeItem("inkcreate.installPrompt.dismissed");
      window.localStorage.removeItem("inkcreate.installPrompt.installed");
      window.__inkcreateDeferredInstallPrompt = null;
      window.dispatchEvent(new CustomEvent("inkcreate:install-available"));
    JS
  end

  def inject_install_prompt
    execute_script(<<~JS)
      window.__inkcreateDeferredInstallPrompt = {
        prompt() {},
        userChoice: Promise.resolve({ outcome: "accepted" })
      };
      window.dispatchEvent(new CustomEvent("inkcreate:install-available"));
    JS
  end

  def dismiss_install_prompt
    execute_script(<<~JS)
      window.localStorage.setItem("inkcreate.installPrompt.dismissed", "true");
      window.__inkcreateDeferredInstallPrompt = null;
      window.dispatchEvent(new CustomEvent("inkcreate:install-available"));
    JS
  end

  def dispatch_app_installed
    execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent("inkcreate:app-installed"));
    JS
  end
end
