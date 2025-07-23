require 'bundler/setup'
require 'worktree_manager'
require 'worktree_manager/cli'
require 'worktree_manager/hook_manager'
require 'worktree_manager/manager'
require 'worktree_manager/worktree'
require 'worktree_manager/config_manager'
require 'tty-prompt'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# SystemExit handling in tests
#
# This project's tests often involve CLI commands that call exit.
# There are two approaches to handle this:
#
# 1. Integration tests (spec/integration/)
#    - Stub the exit method on CLI instance: `allow(cli).to receive(:exit)`
#    - This prevents exit from doing anything, allowing continued execution
#    - Useful for testing complete workflows
#
# 2. Unit tests (spec/worktree_manager/)
#    - Individually stub in tests that expect SystemExit
#    - Example: stub_exit helper method in cli_spec.rb
#    - `allow(cli).to receive(:exit) { |code| raise SystemExit.new(code) }`
#    - This enables `expect { }.to raise_error(SystemExit)` tests
#
# Important notes:
# - Don't stub exit globally (tests may terminate early)
# - Choose the appropriate method based on test purpose
