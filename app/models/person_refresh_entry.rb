class PersonRefreshEntry < ApplicationRecord
  belongs_to :run, class_name: "PersonRefreshRun"
end
