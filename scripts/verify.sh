#!/usr/bin/env bash
# Offline checks only. This script never invokes Rails, touches a server, or downloads dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
printf '\n== Runtime ==\n'
ruby --version
node --version
printf '\n== Ruby behavior and source-contract tests (NOT Rails/RSpec) ==\n'
ruby -E UTF-8 -Itest -e 'Dir["test/unit/*_test.rb"].sort.each { |path| require_relative path }'
printf '\n== Ruby syntax (including unexecuted host specs) ==\n'
count=0
while IFS= read -r path; do
  ruby -E UTF-8 -c "$path"
  count=$((count + 1))
done < <(find app lib db spec test/unit -type f -name '*.rb' | sort)
ruby -E UTF-8 -c plugin.rb
ruby -E UTF-8 -c config/routes.rb
printf 'Ruby syntax checked: %s files\n' "$((count + 2))"
printf '\n== Standalone JavaScript helper tests (NOT Ember/GJS) ==\n'
npm test
printf '\n== Configuration YAML ==\n'
ruby -E UTF-8 -ryaml -e 'Dir["config/**/*.yml"].sort.each { |p| YAML.safe_load(File.read(p, encoding: "UTF-8")); puts "YAML OK: #{p}" }'
printf '\n== Repository whitespace checks ==\n'
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
  git diff --cached --check
else
  printf 'Git metadata not present; whitespace diff check skipped for source archives.\n'
fi
printf '\nOffline verification passed. Rails, PostgreSQL, Ember and browser acceptance are NOT covered.\n'
