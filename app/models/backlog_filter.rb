# Filters the items returned by the `list_backlog` tool by status and rating.
#
# Items are Hashes with "status" and "rating" (nil when the user has not rated the game).
class BacklogFilter
  STATUSES = %w[pending playing completed].freeze
  # Value => [label, predicate over an item's rating]
  RATINGS = {
    "unrated" => [ "Unrated", ->(rating) { rating.nil? } ],
    "5" => [ "5 or more", ->(rating) { rating && rating >= 5 } ],
    "7" => [ "7 or more", ->(rating) { rating && rating >= 7 } ],
    "9" => [ "9 or more", ->(rating) { rating && rating >= 9 } ]
  }.freeze

  attr_reader :status, :rating

  def initialize(params)
    @status = params[:status].presence_in(STATUSES)
    @rating = params[:rating].presence_in(RATINGS.keys)
  end

  def active? = status.present? || rating.present?

  def apply(items)
    items.select do |item|
      (status.nil? || item["status"] == status) &&
        (rating.nil? || RATINGS.fetch(rating).last.call(item["rating"]))
    end
  end

  def self.rating_options = RATINGS.map { |value, (label, _)| [ label, value ] }
end
