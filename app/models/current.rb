class Current < ActiveSupport::CurrentAttributes
  attribute :request_id, :user, :device, :suppress_drive_record_export_callbacks
end
