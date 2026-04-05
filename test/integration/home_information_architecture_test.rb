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
    assert_select "h2", text: "Notebook"
    assert_select "h2", text: "Notepad"
    assert_select "a[href='#{notebooks_path}']", text: "Open notebooks"
    assert_select "a[href='#{notepad_entries_path}']", text: "Open notepad"
  end
end
