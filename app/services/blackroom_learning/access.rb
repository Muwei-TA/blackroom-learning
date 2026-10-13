# frozen_string_literal: true
module BlackroomLearning
  module Access
    module_function

    def member_allowed?(user)
      return false unless user && user.id.to_i.positive? && !user.anonymous? && !user.staged?
      excluded = SiteSetting.blackroom_learning_excluded_usernames.to_s.split('|').map(&:downcase)
      !excluded.include?(user.username.to_s.downcase)
    end

    def member!(user)
      raise Discourse::InvalidAccess unless member_allowed?(user)
    end

    def configuration!(guardian)
      raise Discourse::NotFound unless SiteSetting.blackroom_learning_enabled
      category = Category.find_by(id: SiteSetting.blackroom_learning_category_id)
      topic = Topic.find_by(id: SiteSetting.blackroom_learning_flag_topic_id)
      unless category && topic && topic.category_id == category.id && topic.archetype == Archetype.default && topic.visible
        raise RuleError, :not_configured
      end
      raise Discourse::InvalidAccess unless guardian.can_see?(category) && guardian.can_see?(topic)
      { category: category, topic: topic }
    end

    def goal!(id, user, guardian)
      goal = Goal.find_by(id: id, user_id: user.id)
      raise Discourse::NotFound unless goal
      topic = Topic.find_by(id: goal.flag_topic_id)
      category = Category.find_by(id: goal.category_id)
      unless topic && category && topic.category_id == category.id && guardian.can_see?(topic) && guardian.can_see?(category)
        raise Discourse::InvalidAccess
      end
      goal
    end
  end
end
