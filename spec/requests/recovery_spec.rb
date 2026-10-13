# frozen_string_literal: true
require 'rails_helper'

# Top-level commits/aborts are essential: a transactional fixture would test only a savepoint.
RSpec.describe 'Learning submission rollback recovery', type: :request do
  self.use_transactional_tests = false

  before do
    nonce = SecureRandom.hex(6)
    @member = Fabricate(:user, username: "lr_#{nonce}", email: "lr_#{nonce}@example.invalid", trust_level: 2)
    @category = Fabricate(:category, user: @member, name: "Recovery #{nonce}", slug: "recovery-#{nonce}")
    @flag = Fabricate(:topic, user: @member, category: @category, title: "Flag #{nonce}")
    Fabricate(:post, user: @member, topic: @flag, post_number: 1)
    SiteSetting.blackroom_learning_enabled = true
    SiteSetting.blackroom_learning_category_id = @category.id
    SiteSetting.blackroom_learning_flag_topic_id = @flag.id
    SiteSetting.unique_posts_mins = 5
    today = BlackroomLearning::Policy.local_date(Time.current)
    @goal = BlackroomLearning::Submissions.goal(user: @member, guardian: Guardian.new(@member),
      attributes: { name: "Recovery #{SecureRandom.hex(4)}", commitment: 'Record a synthetic lesson every day.',
        starts_on: today.iso8601, ends_on: (today + 2).iso8601, target_days: 3 }, request_key: SecureRandom.uuid).goal
    @title = "Synthetic recovery lesson #{SecureRandom.hex(6)}"
    @key = SecureRandom.uuid
    @raw = "Synthetic rollback recovery lesson #{SecureRandom.uuid}. This content is unique to this test."
  end

  after do
    BlackroomLearning::Goal.where(user_id: @member.id).destroy_all if @member
    BlackroomLearning::XpEntry.where(user_id: @member.id).delete_all if @member
    @cache_keys&.each { |key| Discourse.redis.del(key) }
    Discourse.redis.scan_each(match: "blackroom-learning:unique-post:#{@member.id}:*").each { |key| Discourse.redis.del(key) } if @member
  end

  def submit(key: @key, raw: @raw)
    BlackroomLearning::Submissions.checkin(user: @member, guardian: Guardian.new(@member),
      goal_id: @goal.id, title: @title, raw: raw, request_key: key)
  end

  def abort_submission
    ActiveRecord::Base.transaction do
      receipt = submit
      @aborted_id = receipt.post_id
      @cache_key = receipt.post.unique_post_key
      @cache_keys = [@cache_key]
      raise ActiveRecord::Rollback
    end
    expect(Post.unscoped.exists?(@aborted_id)).to eq(false)
    expect(BlackroomLearning::Receipt.exists?(user_id: @member.id, request_key: @key)).to eq(false)
    expect(BlackroomLearning::XpEntry.where(user_id: @member.id).sum(:amount)).to eq(0)
    expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
    expect(Discourse.redis.ttl(@cache_key)).to be_between(240, 300)
    @member.reload
  end

  it 'immediately retries an aborted top-level transaction exactly once' do
    abort_submission
    receipt = submit
    expect(submit.id).to eq(receipt.id)
    expect(@goal.receipts.where(kind: 'checkin').count).to eq(1)
    expect(BlackroomLearning::XpEntry.where(user_id: @member.id).sum(:amount)).to eq(10)
    expect(Discourse.redis.get(@cache_key)).to eq(receipt.post_id.to_s)
  end

  it 'keeps ordinary duplicate rejection for a different request UUID' do
    receipt = submit
    @cache_keys = [receipt.post.unique_post_key]
    expect { submit(key: SecureRandom.uuid) }.to raise_error(BlackroomLearning::SubmissionError)
    expect(@goal.receipts.where(kind: 'checkin').count).to eq(1)
  end

  def recovery
    BlackroomLearning::UniquePostRecovery
  end

  def evidence_context
    JSON.parse(Discourse.redis.get(marker)).symbolize_keys.slice(:user_id, :request_key, :kind, :request_digest, :input_hash)
  end

  def marker
    recovery.marker_key(@member.id, @key)
  end

  def change_evidence(changes)
    evidence = JSON.parse(Discourse.redis.get(marker)).merge(changes)
    Discourse.redis.setex(marker, 300, JSON.generate(evidence))
  end

  it 'recovers the actual normalized key while binding exact input bytes' do
    @raw += "\u0000\u00a0  \n"
    abort_submission
    receipt = submit
    expect(receipt.post.raw).not_to include("\u0000")
    expect(submit.id).to eq(receipt.id)
    expect(@goal.receipts.where(kind: 'checkin').count).to eq(1)
  end

  it 'does not delete another request or changed input provenance' do
    abort_submission
    context = evidence_context
    %i[request_key request_digest input_hash kind].each do |field|
      recovery.recover(context.merge(field => 'different'))
      expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
    end
    expect { submit(key: SecureRandom.uuid) }.to raise_error(BlackroomLearning::SubmissionError)
  end

  it 'does not delete another account cache even when its marker is copied' do
    abort_submission
    context = evidence_context.merge(user_id: @member.id + 100_000)
    foreign = recovery.marker_key(context[:user_id], @key)
    @cache_keys << foreign
    Discourse.redis.setex(foreign, 300, Discourse.redis.get(marker))
    recovery.recover(context)
    expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
    expect(Discourse.redis.get(foreign)).not_to be_nil
  end

  it 'keeps a committed cache even if the post is later hard deleted' do
    receipt = submit
    @cache_key = receipt.post.unique_post_key
    @cache_keys = [@cache_key]
    id = receipt.post_id
    context = evidence_context
    receipt.destroy!
    Post.unscoped.where(id: id).delete_all
    recovery.recover(context)
    expect(Discourse.redis.get(@cache_key)).to eq(id.to_s)
  end

  it 'keeps in-progress transaction provenance' do
    abort_submission
    context = evidence_context
    ActiveRecord::Base.transaction do
      xid = ActiveRecord::Base.connection.select_value('SELECT pg_current_xact_id()::text')
      change_evidence('xid' => xid)
      recovery.recover(context)
      expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
      raise ActiveRecord::Rollback
    end
  end

  it 'fails closed for malformed or out-of-range provenance' do
    abort_submission
    original = Discourse.redis.get(marker)
    context = evidence_context
    [ 'bad json', '[]', JSON.generate(JSON.parse(original).merge('xid' => '18446744073709551616')),
      JSON.generate(JSON.parse(original).merge('xid' => "1'); SELECT 1; --")),
      JSON.generate(JSON.parse(original).merge('generation' => nil)) ].each do |bytes|
      Discourse.redis.setex(marker, 300, bytes)
      recovery.recover(context)
      expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
    end
  end

  it 'does not remove a core cache replacement arriving after the SQL check' do
    abort_submission
    context = evidence_context
    replacement = Fabricate(:post, user: @member, topic: @flag, raw: "Replacement #{SecureRandom.uuid}")
    allow(recovery).to receive(:transaction_status).and_wrap_original do |method, xid|
      status = method.call(xid)
      Discourse.redis.setex(@cache_key, 300, replacement.id)
      status
    end
    recovery.recover(context)
    expect(Discourse.redis.get(@cache_key)).to eq(replacement.id.to_s)
    expect(Discourse.redis.get(marker)).not_to be_nil
  end

  it 'does not remove a marker replacement arriving after the SQL check' do
    abort_submission
    context = evidence_context
    replacement = JSON.parse(Discourse.redis.get(marker)).merge('generation' => SecureRandom.hex(16))
    bytes = JSON.generate(replacement)
    allow(recovery).to receive(:transaction_status).and_wrap_original do |method, xid|
      status = method.call(xid)
      Discourse.redis.setex(marker, 300, bytes)
      status
    end
    recovery.recover(context)
    expect(Discourse.redis.get(marker)).to eq(bytes)
    expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
  end

  it 'isolates a PostgreSQL status query failure and keeps duplicate validation' do
    abort_submission
    context = evidence_context
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:select_value).and_wrap_original do |method, sql, *args|
      method.call(sql.start_with?('SELECT pg_xact_status') ? 'SELECT nonexistent_learning_qa_function()' : sql, *args)
    end
    ActiveRecord::Base.transaction do
      recovery.recover(context)
      expect(connection.select_value('SELECT 1')).to eq(1)
      expect(Discourse.redis.get(@cache_key)).to eq(@aborted_id.to_s)
    end
  end

  it 'leaves ordinary core posts outside the learning request scope' do
    post = PostCreator.create!(@member, topic_id: @flag.id, raw: "Ordinary core post #{SecureRandom.uuid} with sufficient content.")
    @cache_keys = [post.unique_post_key]
    expect(Discourse.redis.get(post.unique_post_key)).to eq(post.id.to_s)
    expect(Discourse.redis.scan_each(match: "blackroom-learning:unique-post:#{@member.id}:*").size).to eq(1) # Flag only
  end


  it 'does not mark an auxiliary creator inside a learning submission context' do
    receipt = @goal.receipts.find_by!(kind: 'flag')
    intended = { topic_id: @flag.id, raw: "Intended #{SecureRandom.uuid} lesson." }
    recovery.with_submission(@member, receipt, intended) do
      auxiliary = PostCreator.create!(@member, topic_id: @flag.id, raw: "Auxiliary #{SecureRandom.uuid} ordinary callback content.")
      @cache_keys = [auxiliary.unique_post_key]
      expect(Discourse.redis.get(auxiliary.unique_post_key)).to eq(auxiliary.id.to_s)
      evidence = JSON.parse(Discourse.redis.get(recovery.marker_key(@member.id, receipt.request_key)))
      expect(evidence['post_id']).to eq(receipt.post_id)
    end
  end

  it 'preserves disabled core deduplication without writing a recovery marker' do
    SiteSetting.unique_posts_mins = 0
    receipt = submit
    @cache_keys = [receipt.post.unique_post_key]
    expect(Discourse.redis.get(receipt.post.unique_post_key)).to be_nil
    expect(Discourse.redis.get(marker)).to be_nil
  end

end
