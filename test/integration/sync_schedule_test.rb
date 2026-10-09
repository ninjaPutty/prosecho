require "test_helper"

class SyncScheduleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "only administrators can configure an editable 24-hour default schedule" do
    sign_in users(:staff)
    get admin_sync_schedule_path
    assert_response :forbidden
    sign_in users(:administrator)
    get admin_sync_schedule_path
    assert_response :success
    assert_select "input[name='sync_schedule[interval_hours]'][value='24']"
    assert_select "input[name='sync_schedule[enabled]'][type='checkbox']:not([checked])"
    assert_difference "SyncSchedule.count", 1 do
      patch admin_sync_schedule_path, params: {sync_schedule: {revision: "0", enabled: "1", interval_hours: "24"}}
    end
    assert_redirected_to admin_sync_schedule_path
    schedule = SyncSchedule.current
    assert schedule.enabled?
    assert_equal users(:administrator).id, schedule.administrator_id
    patch admin_sync_schedule_path, params: {sync_schedule: {
      revision: "0", enabled: "1", interval_hours: "12"
    }}
    assert_redirected_to admin_sync_schedule_path
    patch admin_sync_schedule_path, params: {sync_schedule: {
      revision: "0", enabled: "0", interval_hours: "12"
    }}
    assert_response :conflict
    assert SyncSchedule.current.enabled?
  end
end
