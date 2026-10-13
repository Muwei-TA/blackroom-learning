# frozen_string_literal: true
require 'rails_helper'

# Run inside the PINNED Discourse checkout; not executed by the offline unit suite.
RSpec.describe 'BlackRoom learning workflow', type: :request do
  fab!(:member) { Fabricate(:user, trust_level: 2) }
  fab!(:other) { Fabricate(:user, trust_level: 2) }
  fab!(:category) { Fabricate(:category) }
  fab!(:flag_topic) { Fabricate(:topic, category: category) }
  fab!(:flag_first_post) { Fabricate(:post, topic: flag_topic, post_number: 1) }

  before do
    SiteSetting.blackroom_learning_enabled = true
    SiteSetting.blackroom_learning_category_id = category.id
    SiteSetting.blackroom_learning_flag_topic_id = flag_topic.id
    sign_in(member)
  end

  def goal_params
    today = BlackroomLearning::Policy.local_date(Time.current)
    { name: '绘画训练计划', commitment: '每天完成一张练习并写下一个问题', starts_on: today.iso8601,
      ends_on: (today + 29).iso8601, target_days: 30, request_key: SecureRandom.uuid }
  end

  def create_goal
    post '/learning/goals.json', params: goal_params
    expect(response.status).to eq(201)
    BlackroomLearning::Goal.last
  end

  def checkin_params(goal, key: SecureRandom.uuid)
    { goal_id: goal.id, title: '今日练习记录与学习收获', raw: '今天完成透视练习，记录了消失点与地平线的关系。', request_key: key }
  end

  it 'is disabled unless explicitly enabled' do
    SiteSetting.blackroom_learning_enabled = false
    get '/learning/data.json'
    expect(response.status).to eq(404)
  end

  it 'requires authentication' do
    sign_out
    post '/learning/goals.json', params: goal_params
    expect([302, 403]).to include(response.status)
    expect(BlackroomLearning::Goal.count).to eq(0)
  end

  it 'creates the Flag reply as the member, never as the administrator' do
    goal = create_goal
    receipt = goal.receipts.find_by!(kind: 'flag')
    expect(receipt.post.user_id).to eq(member.id)
    expect(receipt.post.topic_id).to eq(flag_topic.id)
    expect(receipt.post.post_number).to be > 1
  end

  it 'deduplicates an identical goal submission' do
    data = goal_params
    2.times { post '/learning/goals.json', params: data }
    expect(BlackroomLearning::Goal.count).to eq(1)
    expect(BlackroomLearning::Receipt.where(kind: 'flag').count).to eq(1)
  end

  it 'rejects an idempotency key reused with different content' do
    data = goal_params
    post '/learning/goals.json', params: data
    post '/learning/goals.json', params: data.merge(name: '另一项学习目标')
    expect(response.status).to eq(409)
  end

  it 'counts multiple same-day topics once, credits 10 XP once' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal)
    expect(response.status).to eq(201)
    second = checkin_params(goal).merge(title: '今天的第二份练习记录', raw: '补充分析另一个场景，把刚才理解的透视规律应用到画面。')
    post '/learning/checkins.json', params: second
    expect(response.status).to eq(201)
    expect(BlackroomLearning::CheckinDay.where(goal_id: goal.id, valid_day: true).count).to eq(1)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(10)
  end

  it 'does not let another user attach a topic to this goal' do
    goal = create_goal
    sign_in(other)
    post '/learning/checkins.json', params: checkin_params(goal)
    expect([403, 404]).to include(response.status)
  end

  it 'ignores client-supplied dates and reward amounts' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal).merge(submitted_at: '2000-01-01', amount: 10000)
    expect(response.status).to eq(201)
    receipt = goal.receipts.find_by!(kind: 'checkin')
    expect(receipt.submitted_at).to be_within(5.seconds).of(Time.current)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(10)
  end

  it 'preserves the submission day when approval is delayed' do
    goal = create_goal
    SiteSetting.approve_post_count = 100
    member.update!(trust_level: 0)
    submitted = Time.zone.parse("#{goal.starts_on} 23:59:00 +0800")
    freeze_time(submitted)
    post '/learning/checkins.json', params: checkin_params(goal)
    expect(response.status).to eq(202)
    receipt = goal.receipts.find_by!(kind: 'checkin')
    expect(BlackroomLearning::CheckinDay.where(valid_day: true).count).to eq(0)
    freeze_time(submitted + 2.hours)
    Reviewable.find(receipt.reviewable_id).perform(Fabricate(:admin), :approve_post)
    BlackroomLearning::ReconcileUser.call(member.id)
    expect(BlackroomLearning::CheckinDay.find_by!(valid_day: true).local_date).to eq(goal.starts_on)
  end

  it 'reverses and restores XP without deleting ledger history' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal)
    receipt = goal.receipts.find_by!(kind: 'checkin')
    receipt.post.update_columns(hidden: true)
    BlackroomLearning::ReconcileUser.call(member.id)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(0)
    receipt.post.update_columns(hidden: false)
    2.times { BlackroomLearning::ReconcileUser.call(member.id) }
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(10)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).order(:id).pluck(:amount)).to eq([10, -10, 10])
  end
  it 'rejects missing goal input with a validation response instead of a server error' do
    post '/learning/goals.json', params: { request_key: SecureRandom.uuid }
    expect(response.status).to eq(422)
    expect(BlackroomLearning::Goal.count).to eq(0)
  end

  it 'rejects missing check-in input with a validation response' do
    post '/learning/checkins.json', params: { request_key: SecureRandom.uuid }
    expect([404, 422]).to include(response.status)
    expect(BlackroomLearning::Receipt.where(kind: 'checkin').count).to eq(0)
  end

  it 'deduplicates a retried check-in without creating another topic' do
    goal = create_goal
    data = checkin_params(goal)
    2.times { post '/learning/checkins.json', params: data }
    expect(response.status).to eq(201)
    expect(goal.receipts.where(kind: 'checkin').count).to eq(1)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(10)
  end

  it 'refuses another overlapping goal' do
    create_goal
    post '/learning/goals.json', params: goal_params.merge(name: '第二个同时进行的目标')
    expect(response.status).to eq(422)
    expect(BlackroomLearning::Goal.count).to eq(1)
  end

  it 'keeps past effort when the member ends a goal' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal)
    post "/learning/goals/#{goal.id}/cancel.json"
    expect(response.status).to eq(200)
    expect(goal.reload.cancelled_at).not_to be_nil
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(10)
    expect(goal.receipts.where(kind: 'checkin').count).to eq(1)
  end

  it 'hides a moderated Flag and its aggregate from other members' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal)
    goal.receipts.find_by!(kind: 'flag').post.update_columns(hidden: true)
    sign_in(other)
    get '/learning/data.json', params: { username: member.username }
    expect(response.status).to eq(200)
    body = response.parsed_body
    expect(body['goals']).to eq([])
    expect(body['summary']['learning_days']).to eq(0)
    expect(body['summary']['xp']).to eq(0)
  end

  it 'refuses access after the learning category becomes restricted' do
    create_goal
    CategoryGroup.where(category_id: category.id).delete_all
    category.update!(read_restricted: true)
    get '/learning/data.json', params: { username: member.username }
    expect([403, 404]).to include(response.status)
  end

  it 'stops counting a source topic moved out of the learning category' do
    goal = create_goal
    post '/learning/checkins.json', params: checkin_params(goal)
    goal.receipts.find_by!(kind: 'checkin').post.topic.update!(category_id: Fabricate(:category).id)
    BlackroomLearning::ReconcileUser.call(member.id)
    expect(BlackroomLearning::XpEntry.where(user_id: member.id).sum(:amount)).to eq(0)
  end

  it 'does not reopen a finished goal when a check-in is hidden after another goal starts' do
    post '/learning/goals.json', params: goal_params.merge(target_days: 1)
    expect(response.status).to eq(201)
    old_goal = BlackroomLearning::Goal.last
    post '/learning/checkins.json', params: checkin_params(old_goal)
    expect(old_goal.reload.completed_at).not_to be_nil
    # Simulate a missing completion projection; new-goal creation must seal its predecessor too.
    old_goal.update_column(:completed_at, nil)
    new_goal = create_goal
    expect(old_goal.reload.completed_at).not_to be_nil
    old_goal.receipts.find_by!(kind: 'checkin').post.update_columns(hidden: true)
    BlackroomLearning::ReconcileUser.call(member.id)
    expect(BlackroomLearning::Snapshot.new(old_goal).status).to eq('ended')
    expect(BlackroomLearning::Snapshot.new(new_goal).status).to eq('active')
  end

end
