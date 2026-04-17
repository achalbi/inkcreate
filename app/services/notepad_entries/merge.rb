module NotepadEntries
  class Merge
    attr_reader :primary_entry, :secondary_entry

    def initialize(primary_entry:, secondary_entry:)
      @primary_entry = primary_entry
      @secondary_entry = secondary_entry
    end

    def call
      validate_entries!

      with_locked_entries do
        ActiveRecord::Base.transaction do
          merge_notes!
          merge_photos!
          merge_voice_notes!
          merge_todo_lists!
          merge_scanned_documents!
          secondary_entry.destroy!
        end
      end

      primary_entry
    end

    private

    def validate_entries!
      raise ArgumentError, "Choose two different notepad entries to merge." if primary_entry.id == secondary_entry.id
      raise ArgumentError, "Both entries must belong to the same user." if primary_entry.user_id != secondary_entry.user_id
    end

    def with_locked_entries
      first_entry, second_entry = [primary_entry, secondary_entry].sort_by(&:id)

      first_entry.with_lock do
        second_entry.with_lock do
          primary_entry.reload
          secondary_entry.reload
          yield
        end
      end
    end

    def merge_notes!
      secondary_notes = secondary_entry.notes.to_s.strip
      return if secondary_notes.blank?

      merged_notes =
        if primary_entry.notes.to_s.strip.blank?
          secondary_notes
        else
          [primary_entry.notes.to_s, merged_notes_header_html, secondary_notes].join("\n")
        end

      primary_entry.update!(notes: merged_notes)
    end

    def merged_notes_header_html
      label = "Merged from #{secondary_entry.display_title} (#{secondary_entry.entry_date.strftime("%b %-d, %Y")})"
      "<div><strong>#{ERB::Util.html_escape(label)}</strong></div>"
    end

    def merge_photos!
      secondary_entry.photos.attachments.order(:created_at).each do |attachment|
        primary_entry.photos.attach(attachment.blob)
      end
    end

    def merge_voice_notes!
      return unless VoiceNote.notepad_entries_supported?

      secondary_entry.voice_notes.update_all(notepad_entry_id: primary_entry.id, updated_at: Time.current)
    end

    def merge_todo_lists!
      return unless TodoList.schema_ready? && TodoItem.schema_ready?

      source_list = secondary_entry.todo_list
      return unless source_list.present?
      return unless source_list.enabled? || source_list.todo_items.exists?

      target_list = primary_entry.todo_list

      if target_list.blank?
        source_list.update!(notepad_entry: primary_entry)
        return
      end

      append_todo_items!(target_list, source_list)
      merge_todo_list_settings!(target_list, source_list)
      source_list.destroy!
    end

    def append_todo_items!(target_list, source_list)
      next_position = target_list.todo_items.maximum(:position).to_i + 1

      source_list.display_todo_items.each do |todo_item|
        todo_item.update!(todo_list: target_list, position: next_position)
        next_position += 1
      end
    end

    def merge_todo_list_settings!(target_list, source_list)
      updates = {
        enabled: target_list.enabled? || source_list.enabled?,
        hide_completed: target_list.hide_completed? || source_list.hide_completed?
      }

      if target_list.has_attribute?(:manually_reordered) && source_list.has_attribute?(:manually_reordered)
        updates[:manually_reordered] = target_list.manually_reordered || source_list.manually_reordered
      end

      target_list.update!(updates) if updates.any? { |key, value| target_list.public_send(key) != value }
    end

    def merge_scanned_documents!
      secondary_entry.scanned_documents.update_all(notepad_entry_id: primary_entry.id, updated_at: Time.current)
    end
  end
end
