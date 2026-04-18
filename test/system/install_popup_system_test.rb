require "application_system_test_case"

class InstallPopupSystemTest < ApplicationSystemTestCase
  POPUP_SELECTOR = ".install-popup-backdrop".freeze

  test "mobile browsers show the popup on landing and accepted install stops future prompts" do
    visit root_path

    configure_install_popup(mobile: true, standalone: false, prompt_outcome: "accepted")

    assert_popup_visible

    within POPUP_SELECTOR do
      click_button "Install app"
    end

    assert_popup_hidden
    assert_equal "true", evaluate_script("window.localStorage.getItem('inkcreate.installPrompt.installed')")

    reschedule_install_popup

    assert_popup_hidden
  end

  test "dismissed popup stays hidden until the session quiet window expires" do
    visit root_path

    configure_install_popup(mobile: true, standalone: false, prompt_outcome: "dismissed")

    assert_popup_visible

    within POPUP_SELECTOR do
      click_button "Not now"
    end

    assert_popup_hidden
    assert_popup_dismissed_at_present

    force_install_popup_reprompt_window_to_expire

    assert_popup_visible
  end

  test "desktop browsers never show the popup" do
    visit root_path

    configure_install_popup(mobile: false, standalone: false, prompt_outcome: "accepted")

    assert_popup_hidden
  end

  test "standalone launches never show the popup" do
    visit root_path

    configure_install_popup(mobile: true, standalone: true, prompt_outcome: "accepted")

    assert_popup_hidden
  end

  test "logged in workspace pages show the popup for eligible mobile browsers" do
    user = build_user(email: "install-popup-workspace@example.com")

    sign_in_as(user)

    configure_install_popup(mobile: true, standalone: false, prompt_outcome: "dismissed")

    assert_popup_visible
  end

  private

  def build_user(email:)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end

  def configure_install_popup(mobile:, standalone:, prompt_outcome:, ios_safari: false)
    execute_script(<<~JS, mobile, standalone, prompt_outcome, ios_safari)
      const [mobile, standalone, promptOutcome, iosSafari] = arguments;
      const controllerElement = document.querySelector('[data-controller~="install-popup"]');
      if (!controllerElement || !controllerElement.installPopupController) {
        throw new Error("install-popup controller not available");
      }

      const controller = controllerElement.installPopupController;

      window.localStorage.removeItem("inkcreate.installPrompt.installed");
      window.sessionStorage.removeItem("inkcreate.installPopup.dismissedAt");
      window.__inkcreateDeferredInstallPrompt = null;

      controller.cancelTimers();
      controller.hidePopup();
      controller.installed = false;
      controller.isMobileBrowser = () => mobile;
      controller.isStandalone = () => standalone;
      controller.isIosSafari = () => iosSafari;
      controller.initialShowDelayMs = () => 0;
      controller.repromptIntervalMs = () => 5 * 60 * 1000;

      if (promptOutcome) {
        const deferredPrompt = {
          prompt() {},
          userChoice: Promise.resolve({ outcome: promptOutcome })
        };

        controller.deferredPrompt = deferredPrompt;
        window.__inkcreateDeferredInstallPrompt = deferredPrompt;
      } else {
        controller.deferredPrompt = null;
      }

      controller.scheduleNextShow();
    JS
  end

  def force_install_popup_reprompt_window_to_expire
    execute_script(<<~JS)
      const controller = document.querySelector('[data-controller~="install-popup"]').installPopupController;
      controller.cancelTimers();
      controller.writeDismissedAt(Date.now() - controller.repromptIntervalMs() - 1000);
      controller.scheduleNextShow();
    JS
  end

  def reschedule_install_popup
    execute_script(<<~JS)
      const controller = document.querySelector('[data-controller~="install-popup"]').installPopupController;
      controller.cancelTimers();
      controller.scheduleNextShow();
    JS
  end

  def assert_popup_visible
    assert_selector "#{POPUP_SELECTOR}:not([hidden])", wait: 10
    assert_selector "body.install-popup-open", wait: 10
  end

  def assert_popup_hidden
    assert_selector "#{POPUP_SELECTOR}[hidden]", visible: :all, wait: 10
    assert_no_selector "body.install-popup-open", wait: 10
  end

  def assert_popup_dismissed_at_present
    assert evaluate_script("window.sessionStorage.getItem('inkcreate.installPopup.dismissedAt')").present?
  end
end
