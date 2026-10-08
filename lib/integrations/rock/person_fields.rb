module Integrations
  module Rock
    module PersonFields
      BASE_COLUMNS = %w[Id Guid PrimaryCampusId RecordTypeValueId IsDeceased
        CreatedDateTime ModifiedDateTime].freeze
      COLUMNS = {
        "birth_date" => %w[BirthDay BirthMonth BirthYear],
        "connection_status" => %w[ConnectionStatusValueId
          ConnectionStatusValue/Id ConnectionStatusValue/Value],
        "first_name" => %w[FirstName],
        "home_address" => %w[PrimaryFamilyId],
        "household" => %w[PrimaryFamilyId],
        "last_name" => %w[LastName],
        "marital_status" => %w[MaritalStatusValueId MaritalStatusValue/Id MaritalStatusValue/Value],
        "nick_name" => %w[NickName],
        "photo" => %w[PhotoId],
        "primary_campus" => %w[PrimaryCampusId]
      }.transform_values(&:freeze).freeze

      def self.columns(fields)
        validate!(fields)
        (BASE_COLUMNS + fields.flat_map { |field| COLUMNS.fetch(field) }).uniq
      end

      def self.expansions(fields)
        validate!(fields)
        values = []
        values << "ConnectionStatusValue" if fields.include?("connection_status")
        values << "MaritalStatusValue" if fields.include?("marital_status")
        values
      end

      def self.validate!(fields)
        unless fields.is_a?(Array) && (fields - COLUMNS.keys).empty?
          raise ArgumentError, "Unsupported person fields"
        end
      end
    end
  end
end
