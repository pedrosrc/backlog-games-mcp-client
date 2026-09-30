require "test_helper"

class BacklogHelperTest < ActionView::TestCase
  test "status badges use orange, yellow and green" do
    assert_includes status_badge_classes("pending"), "orange"
    assert_includes status_badge_classes("playing"), "yellow"
    assert_includes status_badge_classes("completed"), "green"
  end

  test "unknown statuses get a neutral badge" do
    assert_includes status_badge_classes("unknown"), "slate"
  end

  test "format_rating drops a trailing .0" do
    assert_equal "8", format_rating(8.0)
    assert_equal "8.5", format_rating(8.5)
    assert_equal "0", format_rating(0)
  end
end
