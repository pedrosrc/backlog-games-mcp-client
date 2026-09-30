module BacklogHelper
  STATUS_BADGES = {
    "pending" => "bg-orange-100 text-orange-800",
    "playing" => "bg-yellow-100 text-yellow-800",
    "completed" => "bg-green-100 text-green-800"
  }.freeze

  def status_badge_classes(status)
    STATUS_BADGES.fetch(status, "bg-slate-100 text-slate-700")
  end

  def format_rating(rating)
    rating.to_f.round(1).to_s.delete_suffix(".0")
  end
end
