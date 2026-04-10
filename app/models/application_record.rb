class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.schema_ready?
    connection_pool.with_connection do |connection|
      connection.data_source_exists?(table_name)
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end
end
