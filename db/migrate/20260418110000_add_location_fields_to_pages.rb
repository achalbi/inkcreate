class AddLocationFieldsToPages < ActiveRecord::Migration[8.1]
  def change
    change_table :pages, bulk: true do |t|
      t.string :location_name
      t.text :location_address
      t.decimal :location_latitude, precision: 10, scale: 6
      t.decimal :location_longitude, precision: 10, scale: 6
      t.string :location_source
    end
  end
end
