require "yaml"

module WorktreeManager
  class ConfigManager
    DEFAULT_CONFIG_FILES = [
      ".worktree.yml",
      ".git/.worktree.yml"
    ].freeze

    DEFAULT_WORKTREES_DIR = "../"

    def initialize(repository_path = ".")
      @repository_path = File.expand_path(repository_path)
      @config = load_config
    end

    def worktrees_dir
      @config["worktrees_dir"] || DEFAULT_WORKTREES_DIR
    end

    def hooks
      @config["hooks"] || {}
    end

    def resolve_worktree_path(name_or_path)
      # If it's an absolute path, return as is
      return name_or_path if name_or_path.start_with?("/")
      
      # If it contains a path separator, treat it as a relative path
      if name_or_path.include?("/")
        return File.expand_path(name_or_path, @repository_path)
      end
      
      # Otherwise, use worktrees_dir as the base
      base_dir = File.expand_path(worktrees_dir, @repository_path)
      File.join(base_dir, name_or_path)
    end

    private

    def load_config
      config_file = find_config_file
      return {} unless config_file

      begin
        YAML.load_file(config_file) || {}
      rescue => e
        puts "Warning: Failed to load config file #{config_file}: #{e.message}"
        {}
      end
    end

    def find_config_file
      DEFAULT_CONFIG_FILES.each do |file|
        path = File.join(@repository_path, file)
        return path if File.exist?(path)
      end
      nil
    end
  end
end