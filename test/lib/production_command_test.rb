require "test_helper"
require "open3"

class ProductionCommandTest < ActiveSupport::TestCase
  test "production helpers pass hermetic SSH regressions" do
    output, error, status = Open3.capture3("ruby", "tests/prodhelpers/helpers_test.rb")
    assert status.success?, output + error
  end
end
