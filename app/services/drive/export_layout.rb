module Drive
  class ExportLayout
    class << self
      def folder_segments(record)
        case record
        when Page
          [
            "Notebooks",
            notebook_segment(record.notebook),
            chapter_segment(record.chapter),
            record_folder_name(record)
          ]
        when NotepadEntry
          entry_date = record.entry_date || Date.current
          [
            "Notepad",
            entry_date.strftime("%Y"),
            entry_date.iso8601,
            record_folder_name(record)
          ]
        else
          [record.class.name, record_folder_name(record)]
        end
      end

      def folder_path_signature(record)
        folder_segments(record).join(" / ")
      end

      def record_folder_name(record)
        base =
          case record
          when Page, NotepadEntry
            record.display_title
          else
            record.respond_to?(:title) ? record.title.to_s : record.class.name
          end

        "#{base.to_s.truncate(90, omission: "").strip} (#{record.id.to_s.first(8)})"
      end

      def notebook_segment(notebook)
        titled_segment(notebook.title, notebook.id)
      end

      def chapter_segment(chapter)
        titled_segment(chapter.title, chapter.id)
      end

      def chapter_segment_from(title:, id:)
        titled_segment(title, id)
      end

      def titled_segment(title, id)
        "#{title.to_s.truncate(72, omission: "").strip.presence || "Untitled"} (#{id.to_s.first(8)})"
      end
    end
  end
end
