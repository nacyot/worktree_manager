require "open3"
require_relative "worktree"

module WorktreeManager
  class Manager
    attr_reader :repository_path

    def initialize(repository_path = ".")
      @repository_path = File.expand_path(repository_path)
      validate_git_repository!
    end

    def list
      output, status = execute_git_command("worktree list --porcelain")
      return [] unless status.success?

      parse_worktree_list(output)
    end

    def add(path, branch = nil, force: false)
      command = ["worktree", "add"]
      command << "--force" if force
      command << path
      command << branch if branch

      output, status = execute_git_command(command.join(" "))
      raise Error, output unless status.success?

      # 생성된 worktree 정보 반환
      worktree_info = { path: path }
      worktree_info[:branch] = branch if branch
      Worktree.new(worktree_info)
    end

    def add_with_new_branch(path, branch, force: false)
      command = ["worktree", "add"]
      command << "--force" if force
      command << "-b" << branch
      command << path

      output, status = execute_git_command(command.join(" "))
      raise Error, output unless status.success?

      # 생성된 worktree 정보 반환
      Worktree.new(path: path, branch: branch)
    end

    def remove(path, force: false)
      command = ["worktree", "remove"]
      command << "--force" if force
      command << path

      output, status = execute_git_command(command.join(" "))
      raise Error, output unless status.success?
      
      true
    end

    def prune
      output, status = execute_git_command("worktree prune")
      raise Error, output unless status.success?
      
      true
    end

    private

    def validate_git_repository!
      unless File.directory?(File.join(@repository_path, ".git"))
        raise Error, "Not a git repository: #{@repository_path}"
      end
    end

    def execute_git_command(command)
      full_command = "git -C #{@repository_path} #{command}"
      Open3.capture2e(full_command)
    end

    def parse_worktree_list(output)
      worktrees = []
      current_worktree = {}

      output.lines.each do |line|
        line.strip!
        next if line.empty?

        case line
        when /^worktree (.+)$/
          worktrees << Worktree.new(current_worktree) unless current_worktree.empty?
          current_worktree = { path: $1 }
        when /^HEAD (.+)$/
          current_worktree[:head] = $1
        when /^branch (.+)$/
          current_worktree[:branch] = $1
        when /^detached$/
          current_worktree[:detached] = true
        when /^bare$/
          current_worktree[:bare] = true
        end
      end

      worktrees << Worktree.new(current_worktree) unless current_worktree.empty?
      worktrees
    end
  end
end