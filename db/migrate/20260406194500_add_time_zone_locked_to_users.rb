class AddTimeZoneLockedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :time_zone_locked, :boolean, null: false, default: false
  end
end
