module Integrations
  module Rock
    PersonRecord = Data.define(:rock_id, :rock_guid, :campus, :names, :display_name,
      :birth_date, :age, :connection_status, :marital_status, :photo_id,
      :home_address, :household, :attributes, :source_created_at, :source_modified_at, :issues) do
      def inspect
        "#<#{self.class.name} normalized=true>"
      end
    end
  end
end
