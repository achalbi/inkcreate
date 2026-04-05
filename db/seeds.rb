[
  {
    key: "blank",
    name: "Blank",
    description: "Unstructured whiteboard or freeform notes."
  },
  {
    key: "single_line",
    name: "Single Line",
    description: "Ruled pages optimized for meeting notes."
  },
  {
    key: "checkered",
    name: "Checkered",
    description: "Grid pages optimized for diagrams and tables."
  },
  {
    key: "todo",
    name: "To-do",
    description: "Task lists with quick action capture in mind."
  },
  {
    key: "checklist",
    name: "Checklist / To-do",
    description: "Task-oriented pages with checkbox layout."
  },
  {
    key: "priority_severity",
    name: "Priority vs Severity",
    description: "Quadrant-style prioritization pages."
  }
].each do |attributes|
  PageTemplate.find_or_create_by!(key: attributes[:key]) do |page_template|
    page_template.assign_attributes(attributes)
  end
end

seed_admin_email = ENV["SEED_ADMIN_EMAIL"].to_s.strip
seed_admin_password = ENV["SEED_ADMIN_PASSWORD"].to_s

if seed_admin_email.present? || seed_admin_password.present?
  if seed_admin_email.blank? || seed_admin_password.blank?
    raise "Set both SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD to seed the bootstrap admin user."
  end

  seed_admin = User.find_or_initialize_by(email: seed_admin_email)
  seed_admin.assign_attributes(
    password: seed_admin_password,
    password_confirmation: seed_admin_password,
    role: :admin,
    time_zone: ENV.fetch("SEED_ADMIN_TIME_ZONE", "UTC"),
    locale: ENV.fetch("SEED_ADMIN_LOCALE", "en")
  )
  seed_admin.save!

  puts "Seeded admin user: #{seed_admin.email}"

  if ENV["SEED_SAMPLE_WORKSPACE"] == "true"
    notebook = seed_admin.notebooks.find_or_create_by!(title: "Sample notebook") do |record|
      record.description = "A sample project notebook with one chapter and one page."
      record.status = :active
    end

    chapter = notebook.chapters.find_or_create_by!(title: "Getting started") do |record|
      record.description = "Initial structure for a seeded workspace."
      record.position = 1
    end

    chapter.pages.find_or_create_by!(title: "Welcome page") do |record|
      record.notes = "Use this sample page to verify notebook, chapter, and page flows."
      record.captured_on = Date.current
      record.position = 1
    end

    seed_admin.notepad_entries.find_or_create_by!(entry_date: Date.current, title: "Sample daily entry") do |record|
      record.notes = "This sample entry helps verify the daily notepad flow after sign in."
    end

    puts "Seeded sample notebook and notepad content for: #{seed_admin.email}"
  end
end
