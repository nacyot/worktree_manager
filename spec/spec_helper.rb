require "bundler/setup"
require "worktree_manager"
require "worktree_manager/cli"
require "worktree_manager/hook_manager"
require "tty-prompt"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end