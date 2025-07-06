require "thor"
require_relative "version"
require_relative "manager"

module WorktreeManager
  class CLI < Thor
    desc "version", "Show version"
    def version
      puts VERSION
    end

    desc "list", "List all worktrees"
    def list
      validate_main_repository!
      
      manager = Manager.new
      worktrees = manager.list
      
      if worktrees.empty?
        puts "No worktrees found."
      else
        worktrees.each do |worktree|
          puts worktree.to_s
        end
      end
    end

    private

    def validate_main_repository!
      unless main_repository?
        puts "Error: This command can only be run from the main Git repository (not from a worktree)."
        exit(1)
      end
    end

    def main_repository?
      git_dir = File.join(Dir.pwd, ".git")
      return false unless File.exist?(git_dir)
      
      if File.directory?(git_dir)
        true
      elsif File.file?(git_dir)
        git_content = File.read(git_dir).strip
        !git_content.start_with?("gitdir:")
      else
        false
      end
    end
  end
end