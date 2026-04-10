require "test_helper"

class HomeInformationArchitectureTest < ActionDispatch::IntegrationTest
  test "signed in user sees notebook and notepad home cards" do
    user = User.create!(
      email: "home@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    user.notebooks.create!(title: "Client delivery", description: "Project work")
    user.notepad_entries.create!(title: "Today", notes: "Daily capture", entry_date: Date.current)

    sign_in_browser_user(user)
    follow_redirect!

    assert_response :success
    assert_select "h5", text: "Notebook"
    assert_select "h5", text: "Notepad"
    assert_select "a[href='#{notebooks_path}']", text: "Open notebooks"
    assert_select "a[href='#{notepad_entries_path}']", text: "Open notepad"
    assert_select "h5", text: "Upcoming reminders"
    assert_select "input[name='reminder[fire_at_local]']"
    assert_select ".home-reminder-list-content .notebook-list-card--reminder", count: 0
  end

  test "home shows max two upcoming reminders nearest first with view all link" do
    user = User.create!(
      email: "home-reminders@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    user.reminders.create!(title: "Later reminder", fire_at: 2.days.from_now)
    user.reminders.create!(title: "Sooner reminder", fire_at: 2.hours.from_now)
    user.reminders.create!(title: "Soonest reminder", fire_at: 30.minutes.from_now)
    user.reminders.create!(title: "Past reminder", fire_at: 15.minutes.ago)

    sign_in_browser_user(user)
    follow_redirect!

    assert_response :success
    assert_select ".home-reminder-list-content .notebook-list-card--reminder", count: 2
    assert_select "a[href='#{reminders_path}']", text: "View all"
    assert_includes response.body, "Soonest reminder"
    assert_includes response.body, "Sooner reminder"
    assert_not_includes response.body, "Later reminder"
    assert_not_includes response.body, "Past reminder"
    assert_operator response.body.index("Soonest reminder"), :<, response.body.index("Sooner reminder")
  end

  test "signed in user can still load home when reminder and device tables are unavailable" do
    user = User.create!(
      email: "home-fallback@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)

    Device.stub(:schema_ready?, false) do
      Reminder.stub(:schema_ready?, false) do
        Reminder.stub(:new, ->(*) { raise "Reminder.new should not be called when the schema is unavailable" }) do
          follow_redirect!

          assert_response :success
          assert_select "h5", text: "Upcoming reminders"
          assert_match "Run the latest database migrations", response.body
        end
      end
    end
  end
end
