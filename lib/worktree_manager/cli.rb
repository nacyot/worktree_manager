require "thor"
require "open3"
require "tty-prompt"
require_relative "version"
require_relative "manager"
require_relative "hook_manager"
require_relative "config_manager"

module WorktreeManager
  class CLI < Thor
    class_option :verbose, aliases: "-v", type: :boolean, desc: "Enable verbose output for debugging"

    desc "version", "Show version"
    def version
      puts VERSION
    end

    desc "list", "List all worktrees"
    def list
      # list command can be used from worktree
      main_repo_path = find_main_repository_path
      if main_repo_path.nil?
        puts "Error: Not in a Git repository."
        exit(1)
      end
      
      # Show main repository path if running from a worktree
      unless main_repository?
        puts "Running from worktree. Main repository: #{main_repo_path}"
        puts "To enter the main repository, run:"
        puts "  cd #{main_repo_path}"
        puts
      end
      
      manager = Manager.new(main_repo_path)
      worktrees = manager.list
      
      if worktrees.empty?
        puts "No worktrees found."
      else
        worktrees.each do |worktree|
          puts worktree.to_s
        end
      end
    end

    desc "add NAME_OR_PATH [BRANCH]", "Create a new worktree"
    method_option :branch, aliases: "-b", desc: "Create a new branch for the worktree"
    method_option :track, aliases: "-t", desc: "Track a remote branch"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force creation even if directory exists"
    def add(name_or_path, branch = nil)
      validate_main_repository!
      
      # Validate input
      if name_or_path.nil? || name_or_path.strip.empty?
        puts "Error: Name or path cannot be empty"
        exit(1)
      end
      
      # Load configuration and resolve path
      config_manager = ConfigManager.new
      path = config_manager.resolve_worktree_path(name_or_path)
      
      # Get branch name from options (options take precedence over arguments)
      target_branch = options[:branch] || branch
      
      # Handle remote branch tracking
      remote_branch = nil
      if options[:track]
        remote_branch = options[:track]
        # If --track is used without specifying remote branch, use branch argument
        remote_branch = branch if remote_branch == true && branch
        
        # If target_branch is not set, derive it from remote branch
        if !target_branch && remote_branch
          # Extract branch name from remote (e.g., origin/feature -> feature)
          target_branch = remote_branch.split('/', 2).last
        end
      elsif branch && branch.include?('/')
        # Auto-detect remote branch (e.g., origin/feature)
        remote_branch = branch
        # Override target_branch for auto-detected remote branches
        target_branch = branch.split('/', 2).last
      end
      
      # Validate branch name
      if target_branch && !valid_branch_name?(target_branch)
        puts "Error: Invalid branch name '#{target_branch}'. Branch names cannot contain spaces or special characters."
        exit(1)
      end
      
      # Check for conflicts with existing worktrees
      validate_no_conflicts!(path, target_branch)
      
      manager = Manager.new
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      # Execute pre-add hook
      context = {
        path: path,
        branch: target_branch,
        force: options[:force]
      }
      
      unless hook_manager.execute_hook(:pre_add, context)
        puts "Error: pre_add hook failed. Aborting worktree creation."
        exit(1)
      end
      
      begin
        # Create worktree
        if remote_branch
          # Track remote branch
          result = manager.add_tracking_branch(path, target_branch, remote_branch, force: options[:force])
        elsif target_branch
          if options[:branch]
            # Create new branch
            result = manager.add_with_new_branch(path, target_branch, force: options[:force])
          else
            # Use existing branch
            result = manager.add(path, target_branch, force: options[:force])
          end
        else
          result = manager.add(path, force: options[:force])
        end
        
        puts "Worktree created: #{result.path} (#{result.branch || 'detached'})"
        puts "\nTo enter the worktree, run:"
        puts "  cd #{result.path}"
        
        # Execute post-add hook
        context[:success] = true
        context[:worktree_path] = result.path
        hook_manager.execute_hook(:post_add, context)
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # Execute post-add hook with error context on failure
        context[:success] = false
        context[:error] = e.message
        hook_manager.execute_hook(:post_add, context)
        
        exit(1)
      end
    end

    desc "move [WORKTREE]", "Navigate to a worktree directory"
    def move(worktree_name = nil)
      main_repo_path = find_main_repository_path
      if main_repo_path.nil?
        $stderr.puts "Error: Not in a Git repository."
        exit(1)
      end
      
      manager = Manager.new(main_repo_path)
      worktrees = manager.list
      
      if worktrees.empty?
        $stderr.puts "Error: No worktrees found."
        exit(1)
      end
      
      # If no argument provided, show interactive selection
      if worktree_name.nil?
        target = select_worktree_interactive(worktrees)
      else
        # Find worktree by name or path
        target = worktrees.find do |w|
          w.path.include?(worktree_name) || 
          (w.branch && w.branch.include?(worktree_name)) ||
          File.basename(w.path) == worktree_name
        end
        
        if target.nil?
          $stderr.puts "Error: Worktree '#{worktree_name}' not found."
          $stderr.puts "\nAvailable worktrees:"
          worktrees.each do |w|
            $stderr.puts "  - #{File.basename(w.path)} (#{w.branch || 'detached'})"
          end
          exit(1)
        end
      end
      
      # Output only the path to stdout for cd command
      puts target.path
    end

    desc "remove NAME_OR_PATH", "Remove an existing worktree"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force removal even if worktree has changes"
    def remove(name_or_path)
      validate_main_repository!
      
      # Validate input
      if name_or_path.nil? || name_or_path.strip.empty?
        puts "Error: Name or path cannot be empty"
        exit(1)
      end
      
      # Load configuration and resolve path
      config_manager = ConfigManager.new
      path = config_manager.resolve_worktree_path(name_or_path)
      
      # Prevent deletion of main repository
      if File.expand_path(path) == File.expand_path(".")
        puts "Error: Cannot remove the main repository itself"
        exit(1)
      end
      
      manager = Manager.new
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      # Normalize path
      normalized_path = File.expand_path(path)
      
      # Find worktree information to remove
      worktrees = manager.list
      target_worktree = worktrees.find { |wt| File.expand_path(wt.path) == normalized_path }
      
      unless target_worktree
        puts "Error: Worktree not found at path: #{path}"
        exit(1)
        return  # Prevent further execution in test environment
      end
      
      # Execute pre-remove hook
      context = {
        path: target_worktree.path,
        branch: target_worktree.branch,
        force: options[:force]
      }
      
      unless hook_manager.execute_hook(:pre_remove, context)
        puts "Error: pre_remove hook failed. Aborting worktree removal."
        exit(1)
      end
      
      begin
        # Remove worktree
        manager.remove(path, force: options[:force])
        
        puts "Worktree removed: #{target_worktree.path}"
        
        # Execute post-remove hook
        context[:success] = true
        hook_manager.execute_hook(:post_remove, context)
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # Execute post-remove hook with error context on failure
        context[:success] = false
        context[:error] = e.message
        hook_manager.execute_hook(:post_remove, context)
        
        exit(1)
      end
    end

    private

    def validate_main_repository!
      unless main_repository?
        main_repo_path = find_main_repository_path
        puts "Error: This command can only be run from the main Git repository (not from a worktree)."
        if main_repo_path
          puts "To enter the main repository, run:"
          puts "  cd #{main_repo_path}"
        end
        exit(1)
      end
    end

    def validate_no_conflicts!(path, branch_name)
      manager = Manager.new
      
      # Check for path conflicts
      normalized_path = File.expand_path(path)
      existing_worktrees = manager.list
      
      existing_worktrees.each do |worktree|
        if File.expand_path(worktree.path) == normalized_path
          puts "Error: A worktree already exists at path '#{path}'"
          puts "  Existing worktree: #{worktree.path} (#{worktree.branch})"
          puts "  Use --force to override or choose a different path"
          exit(1)
        end
      end
      
      # Check for branch conflicts (when not creating a new branch)
      if branch_name && !options[:branch]
        existing_branch = existing_worktrees.find { |wt| wt.branch == branch_name }
        if existing_branch
          puts "Error: Branch '#{branch_name}' is already checked out in another worktree"
          puts "  Existing worktree: #{existing_branch.path} (#{existing_branch.branch})"
          puts "  Use a different branch name or -b option to create a new branch"
          exit(1)
        end
      end
      
      # Check for branch name duplication when creating new branch
      if options[:branch]
        output, status = Open3.capture2e("git", "branch", "--list", branch_name)
        if status.success? && !output.strip.empty?
          puts "Error: Branch '#{branch_name}' already exists"
          puts "  Use a different branch name or checkout the existing branch"
          exit(1)
        end
      end
      
      # Check directory existence (when force option is not used)
      if !options[:force] && Dir.exist?(normalized_path) && !Dir.empty?(normalized_path)
        puts "Error: Directory '#{path}' already exists and is not empty"
        puts "  Use --force to override or choose a different path"
        exit(1)
      end
    end

    def valid_branch_name?(branch_name)
      return false if branch_name.nil? || branch_name.strip.empty?
      
      # Check basic Git branch name rules
      invalid_patterns = [
        /\s/,           # Contains spaces
        /\.\./,         # Consecutive dots
        /^[\.\-]/,      # Starts with dot or dash
        /[\.\-]$/,      # Ends with dot or dash
        /[~^:?*\[\]\\]/ # Special characters
      ]
      
      invalid_patterns.none? { |pattern| branch_name.match?(pattern) }
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
    
    def select_worktree_interactive(worktrees)
      # Check if running in interactive mode
      unless interactive_mode_available?
        $stderr.puts "Error: Interactive mode requires a TTY. Please specify a worktree name."
        exit(1)
      end
      
      prompt = TTY::Prompt.new(output: $stderr)
      
      # Get current directory to highlight current worktree
      current_path = Dir.pwd
      
      # Build choices for prompt
      choices = worktrees.map do |worktree|
        is_current = File.expand_path(current_path).start_with?(File.expand_path(worktree.path))
        branch_info = worktree.branch || "detached"
        name = File.basename(worktree.path)
        label = "#{name} - #{branch_info}"
        label += " (current)" if is_current
        
        {
          name: label,
          value: worktree,
          hint: worktree.path
        }
      end
      
      # Show selection prompt
      begin
        prompt.select("Select a worktree:", choices, per_page: 10)
      rescue TTY::Reader::InputInterrupt
        $stderr.puts "\nCancelled."
        exit(0)
      end
    end
    
    def interactive_mode_available?
      $stdin.tty? && $stderr.tty?
    end
    
    def find_main_repository_path
      # Try to find the main repository path using git command
      output, _, status = Open3.capture3("git rev-parse --path-format=absolute --git-common-dir")
      
      if status.success?
        git_common_dir = output.strip
        return nil if git_common_dir.empty?
        
        # If it ends with .git, get parent directory
        if git_common_dir.end_with?("/.git")
          return File.dirname(git_common_dir)
        else
          # In some cases, git-common-dir might return the directory itself
          # Check if this is the main repository
          test_dir = git_common_dir.end_with?(".git") ? File.dirname(git_common_dir) : git_common_dir
          git_file = File.join(test_dir, ".git")
          
          if File.exist?(git_file) && File.directory?(git_file)
            return test_dir
          end
        end
      end
      
      # Fallback: try to get worktree list from current directory
      output, _, status = Open3.capture3("git worktree list --porcelain")
      return nil unless status.success?
      
      # First line should be the main worktree
      first_line = output.lines.first
      if first_line && first_line.start_with?("worktree ")
        first_line.sub("worktree ", "").strip
      else
        nil
      end
    end
  end
end