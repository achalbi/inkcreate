require "test_helper"

class TodoListTest < ActiveSupport::TestCase
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
    chapter.pages.create!(title: "Launch tasks", notes: "Checklist")
  end

  test "new items are stored newest first by position" do
    page = build_page(email: "todo-list-order@example.com")
    todo_list = page.create_todo_list!(enabled: true)

    todo_list.todo_items.create!(content: "Confirm venue")
    todo_list.todo_items.create!(content: "Email recap")
    todo_list.todo_items.create!(content: "Pack microphones")

    assert_equal ["Pack microphones", "Email recap", "Confirm venue"], todo_list.todo_items.ordered.pluck(:content)
    assert_equal [1, 2, 3], todo_list.todo_items.ordered.pluck(:position)
  end

  test "display_todo_items follows persisted position order" do
    page = build_page(email: "todo-list-display@example.com")
    todo_list = page.create_todo_list!(enabled: true)
    first_item = todo_list.todo_items.create!(content: "Confirm venue")
    second_item = todo_list.todo_items.create!(content: "Email recap")
    third_item = todo_list.todo_items.create!(content: "Pack microphones")

    first_item.reload
    second_item.reload
    third_item.reload

    first_item.update!(position: 1)
    third_item.update!(position: 2)
    second_item.update!(position: 3)

    assert_equal ["Confirm venue", "Pack microphones", "Email recap"], todo_list.display_todo_items.pluck(:content)
  end
end
