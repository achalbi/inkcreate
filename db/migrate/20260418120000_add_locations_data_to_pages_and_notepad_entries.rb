class AddLocationsDataToPagesAndNotepadEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :locations_data, :jsonb, default: [], null: false
    add_column :notepad_entries, :locations_data, :jsonb, default: [], null: false

    backfill_locations_data(:pages)
    backfill_locations_data(:notepad_entries)
  end

  def down
    remove_column :pages, :locations_data
    remove_column :notepad_entries, :locations_data
  end

  private

  def backfill_locations_data(table_name)
    execute <<~SQL
      UPDATE #{table_name}
      SET locations_data = jsonb_build_array(
        jsonb_strip_nulls(
          jsonb_build_object(
            'name', NULLIF(location_name, ''),
            'address', NULLIF(location_address, ''),
            'latitude', location_latitude,
            'longitude', location_longitude,
            'source', NULLIF(location_source, '')
          )
        )
      )
      WHERE locations_data = '[]'::jsonb
        AND (
          NULLIF(location_name, '') IS NOT NULL OR
          NULLIF(location_address, '') IS NOT NULL OR
          location_latitude IS NOT NULL OR
          location_longitude IS NOT NULL OR
          NULLIF(location_source, '') IS NOT NULL
        )
    SQL
  end
end
