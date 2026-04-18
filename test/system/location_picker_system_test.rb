require "application_system_test_case"

class LocationPickerSystemTest < ApplicationSystemTestCase
  test "selecting a search result saves the location on the page show screen" do
    user = build_user(email: "location-system@example.com")
    notebook = user.notebooks.create!(title: "Travel notes", status: :active)
    chapter = notebook.chapters.create!(title: "Client visits", description: "Field notes")
    page = chapter.pages.create!(title: "Visit notes - Page 1", notes: "Initial notes", captured_on: Date.current)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page)
    stub_location_search_results([
      {
        name: "Client office",
        display_name: "Client office, MG Road, Bengaluru, Karnataka, India",
        lat: "12.975300",
        lon: "77.605000"
      }
    ])

    within "##{ActionView::RecordIdentifier.dom_id(page, :location_section)}" do
      fill_in "Search or add a place", with: "Client office"
      assert_selector "button.location-picker__result", text: "Client office", wait: 10
      find("button.location-picker__result", text: "Client office").click
      assert_text "Location saved.", wait: 10
    end

    visit current_path

    within "##{ActionView::RecordIdentifier.dom_id(page, :location_section)}" do
      assert_text "1 location saved"
      assert_text "Client office"
    end

    assert_equal 1, page.reload.location_count
    assert_equal "Client office", page.location_label
  end

  test "notepad quick actions location button focuses the location search input" do
    user = build_user(email: "notepad-location-actions@example.com")
    entry = user.notepad_entries.create!(
      title: "Daily notes - Page 1",
      notes: "Initial notes",
      entry_date: Date.current
    )
    location_section_id = ActionView::RecordIdentifier.dom_id(entry, :location_section)
    location_input_id = ActionView::RecordIdentifier.dom_id(entry, :location_search_input)

    sign_in_as(user)
    visit notepad_entry_path(entry)

    click_button "Open quick actions"
    click_button "Add location"

    assert_equal "##{location_section_id}", page.evaluate_script("window.location.hash")
    assert_section_near_top(location_section_id)
    wait_for_active_element(location_input_id)
  end

  test "notebook page quick actions location button focuses the location search input" do
    user = build_user(email: "page-location-actions@example.com")
    notebook = user.notebooks.create!(title: "Travel notes", status: :active)
    chapter = notebook.chapters.create!(title: "Client visits", description: "Field notes")
    page_record = chapter.pages.create!(title: "Visit notes - Page 1", notes: "Initial notes", captured_on: Date.current)
    location_section_id = ActionView::RecordIdentifier.dom_id(page_record, :location_section)
    location_input_id = ActionView::RecordIdentifier.dom_id(page_record, :location_search_input)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page_record)

    click_button "Open quick actions"
    click_button "Add location"

    assert_equal "##{location_section_id}", page.evaluate_script("window.location.hash")
    assert_section_near_top(location_section_id)
    wait_for_active_element(location_input_id)
  end

  test "page show contact section saves a contact and can reopen the modal" do
    user = build_user(email: "contact-system@example.com")
    notebook = user.notebooks.create!(title: "Travel notes", status: :active)
    chapter = notebook.chapters.create!(title: "Client visits", description: "Field notes")
    page_record = chapter.pages.create!(title: "Visit notes - Page 1", notes: "Initial notes", captured_on: Date.current)
    section_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_section)
    modal_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_modal)
    name_input_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_name_input)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page_record)

    within "##{section_id}" do
      click_button "Add contact"
    end

    assert_selector "##{modal_id}.show", wait: 10

    within "##{modal_id}" do
      fill_in "Name", with: "Ada Lovelace"
      fill_in "Primary phone", with: "+1 555 010 2000"
      fill_in "Secondary phone", with: "+1 555 010 3000"
      fill_in "Email", with: "ada@example.com"
      fill_in "Website", with: "example.com"
      assert_selector "##{name_input_id}", wait: 10
      assert_selector "[data-contact-cards-target='saveButton']", wait: 10
      click_button "Save contact"
    end

    within "##{section_id}" do
      assert_text "Contact saved.", wait: 10
      assert_text "Ada Lovelace"
      assert_text "+1 555 010 2000"
    end

    visit current_path

    within "##{section_id}" do
      assert_text "1 contact saved"
      assert_text "Ada Lovelace"
      click_button "Add contact"
    end

    assert_selector "##{modal_id}.show", wait: 10
    within "##{modal_id}" do
      assert_field "Name", with: ""
    end
  end

  test "page show contact modal can close and reopen from the add contact button" do
    user = build_user(email: "contact-close-system@example.com")
    notebook = user.notebooks.create!(title: "Travel notes", status: :active)
    chapter = notebook.chapters.create!(title: "Client visits", description: "Field notes")
    page_record = chapter.pages.create!(title: "Visit notes - Page 1", notes: "Initial notes", captured_on: Date.current)
    section_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_section)
    modal_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_modal)
    name_input_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_name_input)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page_record)

    within "##{section_id}" do
      click_button "Add contact"
    end

    assert_selector "##{modal_id}.show", wait: 10

    within "##{modal_id}" do
      fill_in "Name", with: "Grace Hopper"
      click_button "Cancel"
    end

    assert_no_selector "##{modal_id}.show", wait: 10

    within "##{section_id}" do
      click_button "Add contact"
    end

    assert_selector "##{modal_id}.show", wait: 10
    within "##{modal_id}" do
      assert_field "Name", with: ""
      assert_selector "##{name_input_id}", wait: 10
    end
  end

  test "notepad quick actions contact button opens the contact modal" do
    user = build_user(email: "notepad-contact-actions@example.com")
    entry = user.notepad_entries.create!(
      title: "Daily notes - Page 1",
      notes: "Initial notes",
      entry_date: Date.current
    )
    section_id = ActionView::RecordIdentifier.dom_id(entry, :contact_section)
    modal_id = ActionView::RecordIdentifier.dom_id(entry, :contact_modal)
    name_input_id = ActionView::RecordIdentifier.dom_id(entry, :contact_name_input)

    sign_in_as(user)
    visit notepad_entry_path(entry)

    click_button "Open quick actions"
    find("button[data-action='click->notepad-quick-actions#openContact']", visible: :all).click

    assert_equal "##{section_id}", page.evaluate_script("window.location.hash")
    assert_section_near_top(section_id)
    assert_selector "##{modal_id}.show", wait: 10
    assert_selector "##{name_input_id}", wait: 10
  end

  test "notebook page quick actions contact button opens the contact modal" do
    user = build_user(email: "page-contact-actions@example.com")
    notebook = user.notebooks.create!(title: "Travel notes", status: :active)
    chapter = notebook.chapters.create!(title: "Client visits", description: "Field notes")
    page_record = chapter.pages.create!(title: "Visit notes - Page 1", notes: "Initial notes", captured_on: Date.current)
    section_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_section)
    modal_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_modal)
    name_input_id = ActionView::RecordIdentifier.dom_id(page_record, :contact_name_input)

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page_record)

    click_button "Open quick actions"
    find("button[data-action='click->notepad-quick-actions#openContact']", visible: :all).click

    assert_equal "##{section_id}", page.evaluate_script("window.location.hash")
    assert_section_near_top(section_id)
    assert_selector "##{modal_id}.show", wait: 10
    assert_selector "##{name_input_id}", wait: 10
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

  def stub_location_search_results(results)
    execute_script(<<~JS, results.to_json)
      window.__locationPickerSearchResults = JSON.parse(arguments[0]);
      window.__locationPickerOriginalFetch = window.__locationPickerOriginalFetch || window.fetch.bind(window);

      window.fetch = (input, init = {}) => {
        const url = typeof input === "string" ? input : input?.url;

        if (url && url.includes("nominatim.openstreetmap.org/search")) {
          return Promise.resolve(new Response(JSON.stringify(window.__locationPickerSearchResults), {
            status: 200,
            headers: { "Content-Type": "application/json" }
          }));
        }

        return window.__locationPickerOriginalFetch(input, init);
      };
    JS
  end

  def wait_for_active_element(expected_id, timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      active_element_id = page.evaluate_script("document.activeElement && document.activeElement.id")
      if active_element_id == expected_id
        assert_equal expected_id, active_element_id
        return
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise Minitest::Assertion, "Expected active element ##{expected_id}, got ##{active_element_id.presence || 'none'}"
      end

      sleep 0.05
    end
  end

  def assert_section_near_top(section_id, timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      top = page.evaluate_script(<<~JS, section_id)
        (() => {
          const element = document.getElementById(arguments[0]);
          if (!element) return null;
          return element.getBoundingClientRect().top;
        })()
      JS

      if top && top >= 0 && top <= 120
        assert_operator top, :>=, 0
        assert_operator top, :<=, 120
        return
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise Minitest::Assertion, "Expected section ##{section_id} near the top, got top=#{top.inspect}"
      end

      sleep 0.05
    end
  end
end
