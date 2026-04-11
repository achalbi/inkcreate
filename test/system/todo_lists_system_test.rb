require "application_system_test_case"

class TodoListsSystemTest < ApplicationSystemTestCase
  test "user can manage checklist items and attach a reminder to one item" do
    user = build_user(email: "todo-system@example.com")
    notebook = user.notebooks.create!(title: "Launch board", status: :active)
    chapter = notebook.chapters.create!(title: "Prep", description: "Checklist")
    work_page = chapter.pages.create!(title: "Event prep - Page 1", notes: "Checklist host", captured_on: Date.current)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, work_page)

    click_button "Enable to-do list"

    add_todo_item("Pack microphones")
    add_todo_item("Confirm venue")
    add_todo_item("Email recap")

    assert_no_text "3 / 3 done"
    assert_text "0 / 3 done"
    assert_no_button "Disable list"

    find("button[aria-label='Mark complete']", match: :first).click

    assert_text "1 / 3 done"

    click_button "Active"
    within ".todo-list-items" do
      assert_no_text "Pack microphones"
      assert_text "Confirm venue"
      assert_text "Email recap"
    end

    click_button "All"
    within ".todo-list-items" do
      assert_text "Pack microphones"
      assert_text "Confirm venue"
      assert_text "Email recap"
    end

    within all(".todo-list-item").last do
      click_button "Add reminder"
    end

    fire_at = 2.hours.from_now.change(sec: 0)

    within ".todo-item-reminder-modal.show" do
      fill_in "Title", with: "Email recap reminder"
      set_datetime_local_field(find("input[name='reminder[fire_at_local]']"), fire_at.strftime("%Y-%m-%dT%H:%M"))
      fill_in "Note", with: "Send the summary while the meeting is fresh."
      click_button "Create reminder"
    end

    assert_current_path notebook_chapter_page_path(notebook, chapter, work_page)
    assert_text "Reminder created."
    assert_text "Edit reminder"

    work_page.reload

    assert_equal "1 / 3 done", work_page.todo_list.progress_label
    todo_item = work_page.todo_list.todo_items.find_by!(content: "Email recap")
    assert_equal todo_item, Reminder.order(:created_at).last.target
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

  def add_todo_item(content)
    within ".todo-list-composer" do
      find("textarea[name='todo_item[content]']").set(content)
      find("button[aria-label='Add to-do item']").click
    end

    within ".todo-list-items" do
      assert_text content
    end
  end
end
