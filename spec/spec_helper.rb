require "bundler/setup"
require "worktree_manager"
require "worktree_manager/cli"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end