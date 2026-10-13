# frozen_string_literal: true
class CreateBlackroomLearning < ActiveRecord::Migration[7.2]
  def change
    create_table :blackroom_learning_goals do |t|
      t.integer :user_id, null: false
      t.integer :category_id, null: false
      t.integer :flag_topic_id, null: false
      t.string :name, limit: 120, null: false
      t.text :commitment, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :target_days, null: false
      t.string :timezone, null: false, default: 'Asia/Shanghai'
      t.integer :rule_version, null: false, default: 1
      t.datetime :cancelled_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :blackroom_learning_goals, [:user_id, :ends_on], name: 'bl_goals_user_window'
    add_index :blackroom_learning_goals, [:category_id, :flag_topic_id, :id], name: 'bl_goals_scope'
    add_foreign_key :blackroom_learning_goals, :users, on_delete: :cascade
    add_check_constraint :blackroom_learning_goals,
      'target_days BETWEEN 1 AND 366 AND ends_on >= starts_on AND ends_on - starts_on + 1 <= 366 AND target_days <= ends_on - starts_on + 1',
      name: 'bl_goals_valid_window'
    add_check_constraint :blackroom_learning_goals, "timezone = 'Asia/Shanghai' AND rule_version = 1", name: 'bl_goals_rules'

    create_table :blackroom_learning_receipts do |t|
      t.bigint :goal_id, null: false
      t.integer :user_id, null: false
      t.string :kind, null: false
      t.string :request_key, limit: 36, null: false
      t.string :request_digest, limit: 64, null: false
      t.datetime :submitted_at, null: false
      t.integer :post_id
      t.integer :original_topic_id
      t.bigint :reviewable_id
      t.string :state, null: false, default: 'submitting'
      t.timestamps
    end
    add_foreign_key :blackroom_learning_receipts, :blackroom_learning_goals, column: :goal_id, on_delete: :cascade
    add_foreign_key :blackroom_learning_receipts, :users, on_delete: :cascade
    add_index :blackroom_learning_receipts, [:user_id, :request_key], unique: true, name: 'bl_receipts_request'
    add_index :blackroom_learning_receipts, :goal_id, name: 'bl_receipts_goal'
    add_index :blackroom_learning_receipts, :goal_id, unique: true, where: "kind = 'flag'", name: 'bl_one_flag'
    add_index :blackroom_learning_receipts, :post_id, unique: true, where: 'post_id IS NOT NULL', name: 'bl_receipts_post'
    add_index :blackroom_learning_receipts, :reviewable_id, unique: true, where: 'reviewable_id IS NOT NULL', name: 'bl_receipts_review'
    add_index :blackroom_learning_receipts, :original_topic_id, name: 'bl_receipts_topic'
    add_check_constraint :blackroom_learning_receipts, "kind IN ('flag', 'checkin')", name: 'bl_receipts_kind'
    add_check_constraint :blackroom_learning_receipts, "state IN ('submitting', 'published', 'queued', 'rejected', 'unavailable')", name: 'bl_receipts_state'

    create_table :blackroom_learning_checkin_days do |t|
      t.bigint :goal_id, null: false
      t.integer :user_id, null: false
      t.date :local_date, null: false
      t.boolean :valid_day, null: false, default: true
      t.timestamps
    end
    add_foreign_key :blackroom_learning_checkin_days, :blackroom_learning_goals, column: :goal_id, on_delete: :cascade
    add_foreign_key :blackroom_learning_checkin_days, :users, on_delete: :cascade
    add_index :blackroom_learning_checkin_days, [:goal_id, :local_date], unique: true, name: 'bl_days_goal_date'
    add_index :blackroom_learning_checkin_days, [:user_id, :valid_day, :local_date], name: 'bl_days_user_date'

    create_table :blackroom_learning_xp_entries do |t|
      t.integer :user_id, null: false
      t.date :local_date, null: false
      t.integer :revision, null: false
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :created_at, null: false
    end
    add_foreign_key :blackroom_learning_xp_entries, :users, on_delete: :cascade
    add_index :blackroom_learning_xp_entries, [:user_id, :local_date, :revision], unique: true, name: 'bl_xp_event_revision'
    add_check_constraint :blackroom_learning_xp_entries, 'revision > 0 AND amount <> 0 AND amount % 10 = 0', name: 'bl_xp_valid_delta'

    create_table :blackroom_learning_native_awards do |t|
      t.integer :user_id, null: false
      t.string :code, null: false
      t.integer :badge_id, null: false
      t.bigint :user_badge_id, null: false
      t.timestamps
    end
    add_foreign_key :blackroom_learning_native_awards, :users, on_delete: :cascade
    add_index :blackroom_learning_native_awards, [:user_id, :code], unique: true, name: 'bl_awards_user_code'
  end
end
