require "application_system_test_case"

class RemindersSystemTest < ApplicationSystemTestCase
  setup do
    @original_vapid_env = {
      "VAPID_PUBLIC_KEY" => ENV["VAPID_PUBLIC_KEY"],
      "VAPID_PRIVATE_KEY" => ENV["VAPID_PRIVATE_KEY"],
      "VAPID_SUBJECT" => ENV["VAPID_SUBJECT"]
    }

    ENV["VAPID_PUBLIC_KEY"] = "BEl6w2j7_ExamplePublicKeyValue1234567890abcd"
    ENV["VAPID_PRIVATE_KEY"] = "example-private-key"
    ENV["VAPID_SUBJECT"] = "mailto:test@example.com"
  end

  teardown do
    @original_vapid_env.each do |key, value|
      ENV[key] = value
    end

    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "user can enable push on this device and dispatch a standalone reminder" do
    user = build_user(email: "reminders-system@example.com")
    deliveries = []
    fire_at = 5.minutes.from_now.change(sec: 0)

    sign_in_as(user)
    visit settings_path

    click_button "Enable on this device"

    assert_text "Push notifications are enabled on this device."
    assert_text "Push enabled"
    assert_equal 1, user.reload.enabled_devices_for_push.count

    visit dashboard_path
    click_button "+ New reminder"

    assert_difference -> { user.reminders.count }, 1 do
      within "#new-reminder-modal" do
        fill_in "Title", with: "Send summary"
        set_datetime_local_field(find("input[name='reminder[fire_at_local]']"), fire_at.strftime("%Y-%m-%dT%H:%M"))
        fill_in "Note", with: "Share notes with the team."
        click_button "Create reminder"
      end

      assert_text "Reminder created.", wait: 10
    end

    reminder = user.reminders.order(:created_at).last
    assert_current_path reminders_path
    assert_in_delta fire_at.to_i, reminder.fire_at.to_i, 60

    clear_enqueued_jobs

    travel_to(reminder.fire_at + 1.minute) do
      WebPushDeliverer.stub(:configured?, true) do
        WebPushDeliverer.stub(:deliver, ->(device:, payload:) { deliveries << { device: device, payload: payload } }) do
          perform_enqueued_jobs do
            DispatchDueRemindersJob.perform_now(reminder.id)
          end
        end
      end
    end

    assert_equal 1, deliveries.size
    assert_equal reminder.title, deliveries.first[:payload][:title]
    assert_equal edit_reminder_path(reminder), deliveries.first[:payload][:url]
    assert_equal "Standalone", deliveries.first[:payload][:source]
  end

  test "user confirms reminder dismissal through the modal" do
    user = build_user(email: "dismiss-reminder-system@example.com")
    reminder = user.reminders.create!(title: "Pay rent", fire_at: 2.hours.from_now.change(sec: 0))

    sign_in_as(user)
    visit reminders_path

    click_button "Dismiss"

    within "#reminderDismissConfirmModal" do
      assert_text "Dismiss reminder?"
      assert_text "\"Pay rent\" will move to reminder history and stop sending notifications."
      click_button "Dismiss reminder"
    end

    assert_text "Reminder dismissed.", wait: 10
    assert_text "Reminder history"
    assert_equal "dismissed", reminder.reload.status
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
end
