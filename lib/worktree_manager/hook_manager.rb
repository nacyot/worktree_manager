require "yaml"
require "open3"

module WorktreeManager
  class HookManager
    HOOK_TYPES = %w[pre_add post_add pre_remove post_remove].freeze
    DEFAULT_HOOK_FILES = [
      ".worktree_hooks.yml",
      ".git/worktree_hooks.yml"
    ].freeze

    def initialize(repository_path = ".", verbose: false)
      @repository_path = File.expand_path(repository_path)
      @verbose = verbose
      @hooks = load_hooks
    end

    def execute_hook(hook_type, context = {})
      log_debug("🪝 Hook 실행 시작: #{hook_type}")
      
      return true unless HOOK_TYPES.include?(hook_type.to_s)
      return true unless @hooks.key?(hook_type.to_s)

      hook_config = @hooks[hook_type.to_s]
      return true if hook_config.nil? || hook_config.empty?

      log_debug("📋 Hook 설정: #{hook_config.inspect}")
      log_debug("🔧 컨텍스트: #{context.inspect}")

      result = case hook_config
      when String
        execute_command(hook_config, context)
      when Array
        hook_config.all? { |command| execute_command(command, context) }
      when Hash
        execute_hook_hash(hook_config, context)
      else
        true
      end

      log_debug("✅ Hook 실행 완료: #{hook_type} (결과: #{result})")
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
        YAML.load_file(hook_file) || {}
      rescue => e
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

    def execute_command(command, context)
      log_debug("🚀 명령어 실행: #{command}")
      
      env = build_env_vars(context)
      log_debug("🌍 환경 변수: #{env.select { |k, _| k.start_with?('WORKTREE_') }}")
      
      start_time = Time.now
      stdout, stderr, status = Open3.capture3(env, command, chdir: @repository_path)
      duration = Time.now - start_time
      
      log_debug("⏱️ 실행 시간: #{(duration * 1000).round(2)}ms")
      log_debug("📤 출력: #{stdout.strip}") unless stdout.strip.empty?
      log_debug("⚠️ 에러: #{stderr.strip}") unless stderr.strip.empty?
      
      unless status.success?
        puts "Hook failed: #{command}"
        puts "Error: #{stderr}" unless stderr.empty?
        log_debug("❌ 명령어 실행 실패: exit code #{status.exitstatus}")
        return false
      end
      
      puts stdout unless stdout.empty?
      log_debug("✅ 명령어 실행 성공")
      true
    end

    def execute_hook_hash(hook_config, context)
      command = hook_config["command"] || hook_config[:command]
      return true unless command

      stop_on_error = hook_config.fetch("stop_on_error", true)
      result = execute_command(command, context)
      
      if !result && stop_on_error
        return false
      end
      
      true
    end

    def build_env_vars(context)
      env = ENV.to_h
      
      # 기본 환경 변수
      env["WORKTREE_MANAGER_ROOT"] = @repository_path
      
      # 컨텍스트 기반 환경 변수
      context.each do |key, value|
        env_key = "WORKTREE_#{key.to_s.upcase}"
        env[env_key] = value.to_s
      end
      
      env
    end

    def log_debug(message)
      return unless @verbose
      timestamp = Time.now.strftime("%H:%M:%S.%3N")
      puts "[#{timestamp}] [DEBUG] #{message}"
    end
  end
end