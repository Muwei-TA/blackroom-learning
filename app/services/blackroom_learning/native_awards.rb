# frozen_string_literal: true
module BlackroomLearning
  module NativeAwards
    CODES = %w[first_checkin streak_7 total_30 goal_complete].freeze
    module_function

    def sync(user, earned:, goals:)
      ids = CODES.to_h { |code| [code, SiteSetting.public_send("blackroom_learning_#{code}_badge_id").to_i] }
      categories = Category.where(id: goals.map(&:category_id).uniq).to_a
      # Native badges are globally visible on profiles. Never expose a restricted learning area.
      public_scope = !goals.empty? && categories.length == goals.map(&:category_id).uniq.length && categories.none?(&:read_restricted)
      eligible = public_scope && SiteSetting.enable_badges ? earned : []
      NativeAward.where(user_id: user.id).each do |claim|
        next if eligible.include?(claim.code) && ids[claim.code] == claim.badge_id
        badge = UserBadge.find_by(id: claim.user_badge_id, user_id: user.id, badge_id: claim.badge_id)
        BadgeGranter.revoke(badge) if badge
        claim.destroy!
      end
      eligible.each do |code|
        id = ids[code]
        next unless id&.positive?
        next if NativeAward.exists?(user_id: user.id, code: code)
        badge = Badge.find_by(id: id)
        # Use dedicated, non-title, manually granted badges. Never claim an existing award.
        next unless badge && badge.enabled? && !badge.multiple_grant? && !badge.allow_title && badge.query.blank?
        next if UserBadge.exists?(user_id: user.id, badge_id: id)
        awarded = BadgeGranter.grant(badge, user, suppress_notification: true)
        NativeAward.create!(user_id: user.id, code: code, badge_id: id, user_badge_id: awarded.id) if awarded
      end
    end
  end
end
