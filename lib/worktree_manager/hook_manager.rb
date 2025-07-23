require 'yaml'
require 'open3'

module WorktreeManager
  class HookManager
    HOOK_TYPES = %w[pre_add post_add pre_remove post_remove].freeze
    DEFAULT_HOOK_FILES = [
      '.worktree.yml',
      '.git/.worktree.yml'
    ].freeze

    def initialize(repository_path = '.', verbose: false)
      @repository_path = File.expand_path(repository_path)
      @verbose = verbose
      @hooks = load_hooks
    end

    def execute_hook(hook_type, context = {})
      log_debug("🪝 Starting hook execution: #{hook_type}")

      return true unless HOOK_TYPES.include?(hook_type.to_s)
      return true unless @hooks.key?(hook_type.to_s)

      hook_config = @hooks[hook_type.to_s]
      return true if hook_config.nil? || hook_config.empty?

      log_debug("📋 Hook configuration: #{hook_config.inspect}")
      log_debug("🔧 Context: #{context.inspect}")

      result = case hook_config
               when String
                 execute_command(hook_config, context, hook_type)
               when Array
                 hook_config.all? { |command| execute_command(command, context, hook_type) }
               when Hash
                 execute_hook_hash(hook_config, context, hook_type)
               else
                 true
               end

      log_debug("✅ Hook execution completed: #{hook_type} (result: #{result})")
      result
    end

    def has_hook?(hook_type)
      HOOK_TYPES.include?(hook_type.to_s) &&
        @hooks.key?(hook_type.to_s) &&
        !@hooks[hook_type.to_s].nil?
    end

    def list_hooks
      @hooks.select { |type, config| HOOK_TYPES.include?(type) && !config.nil? }
    end

    private

    def load_hooks
      hook_file = find_hook_file
      return {} unless hook_file

      begin
        config = YAML.load_file(hook_file) || {}
        # Support new structure: read configuration under hooks key
        if config.key?('hooks')
          config['hooks']
        else
          # Support top-level keys for backward compatibility
          config
        end
      rescue StandardError => e
        puts "Warning: Failed to load hook file #{hook_file}: #{e.message}"
        {}
      end
    end

    def find_hook_file
      DEFAULT_HOOK_FILES.each do |file|
        path = File.join(@repository_path, file)
        return path if File.exist?(path)
      end
      nil
    end

    def execute_command(command, context, hook_type = nil, working_dir = nil)
      log_debug("🚀 Executing command: #{command}")

      env = build_env_vars(context)
      log_debug("🌍 Environment variables: #{env.select { |k, _| k.start_with?('WORKTREE_') }}")

      # Determine working directory
      chdir = working_dir || default_working_directory(hook_type, context)
      log_debug("📂 Working directory: #{chdir}")

      start_time = Time.now
      status = nil

      # Execute command with environment variables and stream output
      begin
        if env && !env.empty?
          # Verify environment variable is a Hash
          log_debug("🔍 Environment variable type: #{env.class}")
          log_debug("🔍 Environment variable sample: #{env.first(3).to_h}")

          # Use popen3 for streaming output
          Open3.popen3(env, 'sh', '-c', command, chdir: chdir) do |stdin, stdout, stderr, wait_thr|
            stdin.close

            # Create threads to read both stdout and stderr concurrently
            threads = []

            threads << Thread.new do
              stdout.each_line do |line|
                print line
                STDOUT.flush
              end
            end

            threads << Thread.new do
              stderr.each_line do |line|
                STDERR.print line
                STDERR.flush
              end
            end

            # Wait for all threads to complete
            threads.each(&:join)

            # Wait for the process to complete
            status = wait_thr.value
          end
        else
          Open3.popen3(command, chdir: chdir) do |stdin, stdout, stderr, wait_thr|
            stdin.close

            # Create threads to read both stdout and stderr concurrently
            threads = []

            threads << Thread.new do
              stdout.each_line do |line|
                print line
                STDOUT.flush
              end
            end

            threads << Thread.new do
              stderr.each_line do |line|
                STDERR.print line
                STDERR.flush
              end
            end

            # Wait for all threads to complete
            threads.each(&:join)

            # Wait for the process to complete
            status = wait_thr.value
          end
        end
      rescue StandardError => e
        log_debug("❌ Open3.popen3 error: #{e.class} - #{e.message}")
        raise
      end

      duration = Time.now - start_time
      log_debug("⏱️ Execution time: #{(duration * 1000).round(2)}ms")

      unless status.success?
        puts "Hook failed: #{command}"
        log_debug("❌ Command execution failed: exit code #{status.exitstatus}")
        return false
      end

      log_debug('✅ Command executed successfully')
      true
    end

    def execute_hook_hash(hook_config, context, hook_type)
      # Support new structure
      commands = hook_config['commands'] || hook_config[:commands]
      single_command = hook_config['command'] || hook_config[:command]
      pwd = hook_config['pwd'] || hook_config[:pwd]
      stop_on_error = hook_config.fetch('stop_on_error', true)

      # Substitute environment variables if pwd is set
      if pwd
        pwd = pwd.gsub(/\$([A-Z_]+)/) do |match|
          var_name = ::Regexp.last_match(1)
          # First look for environment variables
          if var_name == 'WORKTREE_ABSOLUTE_PATH' && context[:path]
            path = context[:path]
            path.start_with?('/') ? path : File.expand_path(path, @repository_path)
          elsif %w[WORKTREE_MAIN WORKTREE_MANAGER_ROOT].include?(var_name)
            @repository_path
          elsif var_name.start_with?('WORKTREE_')
            context_key = var_name.sub('WORKTREE_', '').downcase.to_sym
            context[context_key]
          else
            ENV[var_name] || match
          end
        end
      end

      if commands && commands.is_a?(Array)
        # Process commands array
        commands.each do |cmd|
          result = execute_command(cmd, context, hook_type, pwd)
          return false if !result && stop_on_error
        end
        true
      elsif single_command
        # Process single command (backward compatibility)
        execute_command(single_command, context, hook_type, pwd)
      else
        true
      end
    end

    def build_env_vars(context)
      # Copy only necessary environment variables instead of ENV.to_h
      env = {}

      # Copy only basic environment variables (PATH, etc.)
      %w[PATH HOME USER SHELL].each do |key|
        env[key] = ENV[key] if ENV[key]
      end

      # Default environment variables
      env['WORKTREE_MANAGER_ROOT'] = @repository_path
      env['WORKTREE_MAIN'] = @repository_path # Main repository path

      # Context-based environment variables
      context.each do |key, value|
        env_key = "WORKTREE_#{key.to_s.upcase}"
        env[env_key] = value.to_s
      end

      # Add worktree absolute path
      if context[:path]
        path = context[:path]
        abs_path = path.start_with?('/') ? path : File.expand_path(path, @repository_path)
        env['WORKTREE_ABSOLUTE_PATH'] = abs_path
      end

      env
    end

    def default_working_directory(hook_type, context)
      # post_add and pre_remove run in worktree directory by default
      if %w[post_add pre_remove].include?(hook_type.to_s) && context[:path]
        # Convert relative path to absolute path
        path = context[:path]
        if path.start_with?('/')
          path
        else
          File.expand_path(path, @repository_path)
        end
      else
        @repository_path
      end
    end

    def log_debug(message)
      return unless @verbose

      timestamp = Time.now.strftime('%H:%M:%S.%3N')
      puts "[#{timestamp}] [DEBUG] #{message}"
    end
  end
end
