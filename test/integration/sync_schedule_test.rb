require "test_helper"

class SyncScheduleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "only administrators can configure a daily GMT refresh time" do
    sign_in users(:staff)
    get admin_sync_schedule_path
    assert_response :forbidden
    sign_in users(:administrator)
    get admin_sync_schedule_path
    assert_response :success
    assert_select "input[name='sync_schedule[scheduled_at]'][type='time']"
    assert_select "input[name='sync_schedule[enabled]'][type='checkbox']:not([checked])"
    assert_difference "SyncSchedule.count", 1 do
      patch admin_sync_schedule_path, params: {sync_schedule: {revision: "0", enabled: "1", scheduled_at: "06:30"}}
    end
    assert_redirected_to admin_sync_schedule_path
    schedule = SyncSchedule.current
    assert schedule.enabled?
    assert_equal users(:administrator).id, schedule.administrator_id
    assert_equal [6, 30], [schedule.scheduled_at.hour, schedule.scheduled_at.min]
    patch admin_sync_schedule_path, params: {sync_schedule: {
      revision: "0", enabled: "1", scheduled_at: "18:45"
    }}
    assert_redirected_to admin_sync_schedule_path
    patch admin_sync_schedule_path, params: {sync_schedule: {
      revision: "0", enabled: "0", scheduled_at: "18:45"
    }}
    assert_response :conflict
    assert SyncSchedule.current.enabled?
  end

  test "an invalid GMT refresh time renders a validation error" do
    sign_in users(:administrator)

    patch admin_sync_schedule_path, params: {sync_schedule: {
      revision: "0", enabled: "1", scheduled_at: "not-a-time"
    }}

    assert_response :unprocessable_content
    assert_select "[role='alert']", /Scheduled at can't be blank/
  end
end
