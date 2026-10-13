# frozen_string_literal: true
module BlackroomLearning
  class LearningController < ::ApplicationController
    requires_plugin 'blackroom-learning'
    requires_login
    before_action :check_configuration
    before_action :disable_caching

    rescue_from RuleError do |error|
      status = error.code == 'request_conflict' ? 409 : 422
      messages = error.is_a?(SubmissionError) ? error.messages : [I18n.t("blackroom_learning.errors.#{error.code}", default: I18n.t('blackroom_learning.errors.invalid_request'))]
      render json: { errors: messages }, status: status
    end

    def index
      if request.format.html?
        render 'default/empty'
      else
        page = params[:page].to_i.clamp(0, 1000)
        data = presenter.index(page: page, username: params[:username].presence, goal_id: params[:goal_id].presence)
        render json: data
      end
    end

    def create_goal
      RateLimiter.new(current_user, 'blackroom-learning-goal', 5, 1.minute).performed!
      attributes = params.permit(:name, :commitment, :starts_on, :ends_on, :target_days).to_h
      receipt = Submissions.goal(user: current_user, guardian: guardian, attributes: attributes, request_key: params[:request_key], timing: posting_timing)
      render_submission(receipt)
    end

    def create_checkin
      RateLimiter.new(current_user, 'blackroom-learning-checkin', 10, 1.minute).performed!
      allowed = params.permit(:goal_id, :title, :raw, :request_key).to_h.symbolize_keys
      receipt = Submissions.checkin(user: current_user, guardian: guardian, timing: posting_timing, **allowed)
      render_submission(receipt)
    end

    def cancel
      RateLimiter.new(current_user, 'blackroom-learning-cancel', 5, 1.minute).performed!
      Submissions.cancel(user: current_user, guardian: guardian, goal_id: params[:id])
      render json: { success: true }
    end

    private

    def posting_timing
      params.permit(:typing_duration_msecs, :composer_open_duration_msecs).to_h
    end

    def presenter
      Presenter.new(guardian: guardian, current_user: current_user)
    end

    def check_configuration
      Access.configuration!(guardian)
    end

    def disable_caching
      response.headers['Cache-Control'] = 'private, no-store'
    end

    def render_submission(receipt)
      render json: { goal: presenter.card(receipt.goal), state: receipt.state,
        post_url: receipt.state == 'published' && receipt.post && guardian.can_see?(receipt.post) ? receipt.post.url : nil },
        status: receipt.state == 'queued' ? 202 : 201
    end
  end
end
