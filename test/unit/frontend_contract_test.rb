# frozen_string_literal: true
require 'minitest/autorun'
require 'yaml'

# Source/translation checks only. These do not compile Ember or render a browser.
class FrontendContractTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def tree(kind, locale)
    file = File.join(ROOT, "config/locales/#{kind}.#{locale}.yml")
    assert File.file?(file), "Missing translation file: #{file}"
    YAML.safe_load(File.read(file)).fetch(locale)
  end

  def leaves(hash, prefix = '')
    hash.each_with_object({}) do |(key, value), all|
      full = prefix.empty? ? key : "#{prefix}.#{key}"
      value.is_a?(Hash) ? all.merge!(leaves(value, full)) : all[full] = value
    end
  end

  def test_submission_token_errors_are_caught_without_leaving_the_form_busy
    %w[learning-goal-form learning-checkin-form].each do |name|
      source = File.read(File.join(ROOT, "assets/javascripts/discourse/components/#{name}.gjs"), encoding: 'UTF-8')
      assert_operator source.index('try {'), :<, source.index('this.requestKey ??= requestToken()')
    end
  end

  def test_route_template_uses_verified_controller_model_contract
    source = File.read(File.join(ROOT, 'assets/javascripts/discourse/templates/learning.gjs'))
    assert_includes source, '@model={{@controller.model}}'
  end

  def test_locales_have_identical_keys_and_interpolation_parameters
    %w[server client].each do |kind|
      english, chinese = %w[en zh_CN].map { |locale| leaves(tree(kind, locale)) }
      assert_equal english.keys.sort, chinese.keys.sort
      english.each do |key, text|
        refute_empty chinese.fetch(key).to_s
        assert_equal text.scan(/%\{\w+\}/).sort, chinese.fetch(key).scan(/%\{\w+\}/).sort, key
      end
    end
  end

  def test_all_literal_client_keys_and_dynamic_enums_are_translated
    strings = leaves(tree('client', 'en').fetch('js'))
    source = Dir[File.join(ROOT, 'assets/javascripts/**/*.{js,gjs}')].map { |p| File.read(p, encoding: 'UTF-8') }.join("\n")
    keys = source.scan(/["'](blackroom_learning\.[a-z_\.]+)["']/).flatten.uniq
    keys += %w[active scheduled completed ended cancelled awaiting_approval rejected unavailable].map { |v| "blackroom_learning.status.#{v}" }
    keys += %w[first_checkin streak_7 total_30 goal_complete].map { |v| "blackroom_learning.achievements.#{v}" }
    keys += %w[complete open future].map { |v| "blackroom_learning.calendar.#{v}" }
    keys.each { |key| assert strings.key?(key), "Missing key #{key}" }
  end

  def test_error_codes_and_setting_descriptions_are_translated
    strings = leaves(tree('server', 'en'))
    source = Dir[File.join(ROOT, '{app,lib}/**/*.rb')].map { |p| File.read(p, encoding: 'UTF-8') }.join("\n")
    codes = source.scan(/(?:raise RuleError,|super\()\s*:(\w+)/).flatten
    (codes + %w[invalid_request post_rejected]).uniq.each do |code|
      assert strings.key?("blackroom_learning.errors.#{code}"), "Missing error #{code}"
    end
    settings = YAML.safe_load(File.read(File.join(ROOT, 'config/settings.yml'))).fetch('plugins')
    settings.each_key { |key| assert strings.key?("site_settings.#{key}"), "Missing setting #{key}" }
  end
end
