require_relative "worktree_manager/version"
require_relative "worktree_manager/manager"
require_relative "worktree_manager/worktree"

module WorktreeManager
  class Error < StandardError; end
  
  def self.new(repository_path = ".")
    Manager.new(repository_path)
  end
end