require "thor"
require "open3"
require "tty-prompt"
require "fileutils"
require_relative "version"
require_relative "manager"
require_relative "hook_manager"
require_relative "config_manager"

module WorktreeManager
  class CLI < Thor
    class_option :verbose, aliases: "-v", type: :boolean, desc: "Enable verbose output for debugging"
    
    HELP_ALIASES = %w[--help -h -? --usage].freeze
    
    # Override Thor's start method to handle help requests properly
    def self.start(given_args = ARGV, config = {})
      # Intercept "wm command --help" style requests
      if given_args.size >= 2 && (flag = given_args.detect { |a| HELP_ALIASES.include?(a) })
        # Extract the command (first argument)
        command = given_args.first
        # Replace the entire args with just "help command" to avoid Thor validation issues
        given_args = ["help", command]
      end
      
      super(given_args, config)
    end

    desc "version", "Show version"
    def version
      puts VERSION
    end

    desc "init", "Initialize worktree configuration file"
    long_desc <<-LONGDESC
    `wm init` creates a .worktree.yml configuration file in your repository.

    This command copies the example configuration file to your current directory,
    allowing you to customize worktree settings and hooks.

    Examples:
      wm init         # Create .worktree.yml from example
      wm init --force # Overwrite existing .worktree.yml
    LONGDESC
    method_option :force, aliases: "-f", type: :boolean, desc: "Force overwrite existing .worktree.yml"
    def init
      validate_main_repository!
      
      # Check if .worktree.yml already exists
      config_file = ".worktree.yml"
      if File.exist?(config_file) && !options[:force]
        puts "Error: #{config_file} already exists. Use --force to overwrite."
        exit(1)
      end
      
      # Find example file
      example_file = find_example_file
      unless example_file
        puts "Error: Could not find .worktree.yml.example file."
        exit(1)
      end
      
      # Copy example file
      begin
        FileUtils.cp(example_file, config_file)
        puts "Created #{config_file} from example."
        puts "Edit this file to customize your worktree configuration."
      rescue => e
        puts "Error: Failed to create configuration file: #{e.message}"
        exit(1)
      end
    end

    desc "list", "List all worktrees"
    long_desc <<-LONGDESC
    `wm list` displays all git worktrees in the current repository.

    This command can be run from either the main repository or any worktree.
    When run from a worktree, it shows the path to the main repository.

    Example:
      wm list  # List all worktrees
    LONGDESC
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
    long_desc <<-LONGDESC
    `wm add` creates a new git worktree at the specified location.

    The NAME_OR_PATH can be:
      - A simple name (e.g., 'feature'): Creates in configured worktrees_dir
      - A relative path (e.g., '../projects/feature'): Creates at that path
      - An absolute path: Creates at the exact location

    Options:
      -b, --branch: Create a new branch for the worktree
      -t, --track: Create a branch tracking a remote branch
      -f, --force: Force creation even if directory exists
      --no-hooks: Skip pre_add and post_add hooks

    Examples:
      wm add feature          # Create worktree at ../feature using existing branch
      wm add feature main     # Create worktree using 'main' branch
      wm add feature -b new   # Create worktree with new branch 'new'
      wm add feature -t origin/develop  # Track remote branch
      wm add ../custom/path   # Create at specific path
    LONGDESC
    method_option :branch, aliases: "-b", desc: "Create a new branch for the worktree"
    method_option :track, aliases: "-t", desc: "Track a remote branch"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force creation even if directory exists"
    method_option :no_hooks, type: :boolean, desc: "Skip hook execution"
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
      
      unless options[:no_hooks]
        unless hook_manager.execute_hook(:pre_add, context)
          puts "Error: pre_add hook failed. Aborting worktree creation."
          exit(1)
        end
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
        unless options[:no_hooks]
          context[:success] = true
          context[:worktree_path] = result.path
          hook_manager.execute_hook(:post_add, context)
        end
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # Execute post-add hook with error context on failure
        unless options[:no_hooks]
          context[:success] = false
          context[:error] = e.message
          hook_manager.execute_hook(:post_add, context)
        end
        
        exit(1)
      end
    end

    desc "jump [WORKTREE]", "Navigate to a worktree directory"
    def jump(worktree_name = nil)
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

    desc "reset", "Reset current worktree branch to origin/main"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force reset even if there are uncommitted changes"
    def reset
      # Check if we're in a worktree (not main repository)
      if main_repository?
        puts "Error: Cannot run reset from the main repository. This command must be run from a worktree."
        exit(1)
      end
      
      # Get current branch name
      current_branch_output, status = Open3.capture2("git symbolic-ref --short HEAD")
      unless status.success?
        puts "Error: Could not determine current branch."
        exit(1)
      end
      
      current_branch = current_branch_output.strip
      
      # Check if we're on the main branch
      config_manager = ConfigManager.new
      main_branch_name = config_manager.main_branch_name
      
      if current_branch == main_branch_name
        puts "Error: Cannot reset the main branch '#{main_branch_name}'."
        exit(1)
      end
      
      # Check for uncommitted changes if not forcing
      unless options[:force]
        status_output, status = Open3.capture2("git status --porcelain")
        if status.success? && !status_output.strip.empty?
          puts "Error: You have uncommitted changes. Use --force to discard them."
          exit(1)
        end
      end
      
      puts "Resetting branch '#{current_branch}' to origin/#{main_branch_name}..."
      
      # Fetch origin/main
      fetch_output, fetch_status = Open3.capture2e("git fetch origin #{main_branch_name}")
      unless fetch_status.success?
        puts "Error: Failed to fetch origin/#{main_branch_name}: #{fetch_output}"
        exit(1)
      end
      
      # Reset current branch to origin/main
      reset_command = options[:force] ? "git reset --hard origin/#{main_branch_name}" : "git reset origin/#{main_branch_name}"
      reset_output, reset_status = Open3.capture2e(reset_command)
      
      if reset_status.success?
        puts "Successfully reset '#{current_branch}' to origin/#{main_branch_name}"
      else
        puts "Error: Failed to reset: #{reset_output}"
        exit(1)
      end
    end

    desc "remove [NAME_OR_PATH]", "Remove an existing worktree"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force removal even if worktree has changes"
    method_option :all, type: :boolean, desc: "Remove all worktrees at once"
    method_option :no_hooks, type: :boolean, desc: "Skip hook execution"
    def remove(name_or_path = nil)
      validate_main_repository!
      
      manager = Manager.new
      
      # Handle --all option
      if options[:all]
        if name_or_path
          puts "Error: Cannot specify both --all and a specific worktree"
          exit(1)
        end
        
        worktrees = manager.list
        if worktrees.empty?
          puts "Error: No worktrees found."
          exit(1)
        end
        
        remove_all_worktrees(worktrees)
        return
      end
      
      # If no argument provided, show interactive selection
      if name_or_path.nil?
        worktrees = manager.list
        
        # Filter out main repository
        removable_worktrees = worktrees.reject { |worktree| is_main_repository?(worktree.path) }
        
        if removable_worktrees.empty?
          puts "Error: No removable worktrees found (only main repository exists)."
          exit(1)
        end
        
        target_worktree = select_worktree_interactive(removable_worktrees)
        path = target_worktree.path
      else
        # Load configuration and resolve path
        config_manager = ConfigManager.new
        path = config_manager.resolve_worktree_path(name_or_path)
      end
      
      # Prevent deletion of main repository
      if is_main_repository?(path)
        puts "Error: Cannot remove the main repository"
        exit(1)
      end
      
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      # Normalize path
      normalized_path = File.expand_path(path)
      
      # Find worktree information to remove if not already selected
      if name_or_path.nil?
        # We already have target_worktree from interactive selection
      else
        worktrees = manager.list
        target_worktree = worktrees.find { |wt| File.expand_path(wt.path) == normalized_path }
        
        unless target_worktree
          puts "Error: Worktree not found at path: #{path}"
          exit(1)
          return  # Prevent further execution in test environment
        end
      end
      
      # Execute pre-remove hook
      context = {
        path: target_worktree.path,
        branch: target_worktree.branch,
        force: options[:force]
      }
      
      unless options[:no_hooks]
        unless hook_manager.execute_hook(:pre_remove, context)
          puts "Error: pre_remove hook failed. Aborting worktree removal."
          exit(1)
        end
      end
      
      begin
        # Remove worktree
        manager.remove(path, force: options[:force])
        
        puts "Worktree removed: #{target_worktree.path}"
        
        # Execute post-remove hook
        unless options[:no_hooks]
          context[:success] = true
          hook_manager.execute_hook(:post_remove, context)
        end
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # Check if error is due to modified/untracked files and offer force removal
        if e.message.include?("contains modified or untracked files") && 
           !options[:force] && 
           interactive_mode_available?
          
          prompt = TTY::Prompt.new
          if prompt.yes?("\nWould you like to force remove the worktree? This will delete all uncommitted changes.", default: false)
            begin
              # Retry with force option
              manager.remove(path, force: true)
              puts "Worktree removed: #{target_worktree.path}"
              
              # Execute post-remove hook with success
              unless options[:no_hooks]
                context[:success] = true
                hook_manager.execute_hook(:post_remove, context)
              end
              
              return # Successfully removed with force
            rescue WorktreeManager::Error => force_error
              puts "Error: #{force_error.message}"
              # Fall through to regular error handling
            end
          else
            puts "Removal cancelled."
          end
        end
        
        # Execute post-remove hook with error context on failure
        unless options[:no_hooks]
          context[:success] = false
          context[:error] = e.message
          hook_manager.execute_hook(:post_remove, context)
        end
        
        exit(1)
      end
    end

    private

    def find_example_file
      # First check in the current project (for development)
      local_example = File.expand_path(".worktree.yml.example", File.dirname(__FILE__) + "/../..")
      return local_example if File.exist?(local_example)
      
      # Then check in the gem installation path
      gem_spec = Gem::Specification.find_by_name("worktree_manager") rescue nil
      if gem_spec
        gem_example = File.join(gem_spec.gem_dir, ".worktree.yml.example")
        return gem_example if File.exist?(gem_example)
      end
      
      nil
    end

    def is_main_repository?(path)
      # Main repository has .git as a directory, worktrees have .git as a file
      git_path = File.join(path, ".git")
      File.exist?(git_path) && File.directory?(git_path)
    end

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
    
    def remove_all_worktrees(worktrees)
      # Filter out the main repository
      removable_worktrees = worktrees.reject { |worktree| is_main_repository?(worktree.path) }
      
      if removable_worktrees.empty?
        puts "No worktrees to remove (only main repository found)."
        exit(0)
      end
      
      # Show confirmation prompt
      if interactive_mode_available?
        prompt = TTY::Prompt.new
        
        puts "The following worktrees will be removed:"
        removable_worktrees.each do |worktree|
          puts "  - #{worktree.path} (#{worktree.branch || 'detached'})"
        end
        puts
        
        unless prompt.yes?("Are you sure you want to remove all #{removable_worktrees.size} worktrees?", default: false)
          puts "Cancelled."
          exit(0)
        end
      else
        # In non-interactive mode, require --force for safety
        unless options[:force]
          puts "Error: Removing all worktrees requires confirmation."
          puts "Use --force to remove all worktrees without confirmation."
          exit(1)
        end
      end
      
      manager = Manager.new
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      removed_count = 0
      failed_count = 0
      failed_worktrees = []
      force_removable_worktrees = []
      
      removable_worktrees.each do |worktree|
        puts "\nRemoving worktree: #{worktree.path}"
        
        # Execute pre-remove hook
        context = {
          path: worktree.path,
          branch: worktree.branch,
          force: options[:force]
        }
        
        unless options[:no_hooks]
          unless hook_manager.execute_hook(:pre_remove, context)
            puts "  Error: pre_remove hook failed. Skipping this worktree."
            failed_count += 1
            next
          end
        end
        
        begin
          # Remove worktree
          manager.remove(worktree.path, force: options[:force])
          
          puts "  Worktree removed: #{worktree.path}"
          removed_count += 1
          
          # Execute post-remove hook
          unless options[:no_hooks]
            context[:success] = true
            hook_manager.execute_hook(:post_remove, context)
          end
          
        rescue WorktreeManager::Error => e
          puts "  Error: #{e.message}"
          failed_count += 1
          failed_worktrees << worktree
          
          # Track worktrees that can be force removed
          if e.message.include?("contains modified or untracked files")
            force_removable_worktrees << worktree
          end
          
          # Execute post-remove hook with error context on failure
          unless options[:no_hooks]
            context[:success] = false
            context[:error] = e.message
            hook_manager.execute_hook(:post_remove, context)
          end
        end
      end
      
      puts "\nSummary:"
      puts "  Removed: #{removed_count} worktrees"
      puts "  Failed: #{failed_count} worktrees" if failed_count > 0
      
      # Offer force removal for worktrees with uncommitted changes
      if force_removable_worktrees.any? && !options[:force] && interactive_mode_available?
        puts "\nThe following worktrees contain uncommitted changes:"
        force_removable_worktrees.each do |worktree|
          puts "  - #{worktree.path} (#{worktree.branch || 'detached'})"
        end
        
        prompt = TTY::Prompt.new
        if prompt.yes?("\nWould you like to force remove these worktrees? This will delete all uncommitted changes.", default: false)
          puts "\nForce removing worktrees with uncommitted changes..."
          
          force_removable_worktrees.each do |worktree|
            puts "\nRemoving worktree: #{worktree.path}"
            
            begin
              # Remove with force
              manager.remove(worktree.path, force: true)
              
              puts "  Worktree removed: #{worktree.path}"
              removed_count += 1
              failed_count -= 1
              
              # Execute post-remove hook
              unless options[:no_hooks]
                context = {
                  path: worktree.path,
                  branch: worktree.branch,
                  force: true,
                  success: true
                }
                hook_manager.execute_hook(:post_remove, context)
              end
              
            rescue WorktreeManager::Error => e
              puts "  Error: #{e.message}"
            end
          end
          
          puts "\nUpdated Summary:"
          puts "  Removed: #{removed_count} worktrees"
          puts "  Failed: #{failed_count} worktrees" if failed_count > 0
        end
      end
      
      exit(failed_count > 0 ? 1 : 0)
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