require "test_helper"

class TodoItemTest < ActiveSupport::TestCase
  def build_page(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = user.notebooks.create!(title: "Ops", description: "Tasks", status: :active)
    chapter = notebook.chapters.create!(title: "Week 1")
    page = chapter.pages.new(title: "", notes: "Checklist")
    page.save!
    page
  end

  test "sets completed_at when toggled complete and clears it when reopened" do
    page = build_page(email: "todo-item@example.com")
    todo_list = page.create_todo_list!
    todo_item = todo_list.todo_items.create!(content: "Review checklist")

    todo_item.toggle_completion!
    assert todo_item.completed?
    assert_not_nil todo_item.completed_at

    todo_item.toggle_completion!
    assert_not todo_item.completed?
    assert_nil todo_item.completed_at
  end
end
