require "test_helper"

class BacklogFilterTest < ActiveSupport::TestCase
  ITEMS = [
    { "name" => "A", "status" => "pending", "rating" => nil },
    { "name" => "B", "status" => "playing", "rating" => 6.0 },
    { "name" => "C", "status" => "completed", "rating" => 9.5 },
    { "name" => "D", "status" => "completed", "rating" => 4.0 }
  ].freeze

  def names(params) = BacklogFilter.new(ActionController::Parameters.new(params)).apply(ITEMS).map { |i| i["name"] }

  test "without filters returns everything" do
    assert_equal %w[A B C D], names({})
    assert_not BacklogFilter.new(ActionController::Parameters.new({})).active?
  end

  test "filters by status" do
    assert_equal %w[C D], names(status: "completed")
    assert_equal %w[A], names(status: "pending")
  end

  test "filters by minimum rating" do
    assert_equal %w[B C], names(rating: "5")
    assert_equal %w[C], names(rating: "9")
  end

  test "filters unrated games" do
    assert_equal %w[A], names(rating: "unrated")
  end

  test "combines status and rating" do
    assert_equal %w[C], names(status: "completed", rating: "7")
  end

  test "ignores unknown values" do
    assert_equal %w[A B C D], names(status: "bogus", rating: "bogus")
  end
end
