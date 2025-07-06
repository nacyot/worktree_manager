module WorktreeManager
  class Worktree
    attr_reader :path, :branch, :head, :detached, :bare

    def initialize(attributes = {})
      case attributes
      when Hash
        @path = attributes[:path]
        @branch = attributes[:branch]
        @head = attributes[:head]
        @detached = attributes[:detached] || false
        @bare = attributes[:bare] || false
      when String
        @path = attributes
        @branch = nil
        @head = nil
        @detached = false
        @bare = false
      end
    end

    def detached?
      @detached
    end

    def bare?
      @bare
    end

    def main?
      @branch == "main" || @branch == "master"
    end

    def exists?
      File.directory?(@path)
    end

    def to_s
      if @branch
        "#{@path} (#{@branch})"
      else
        "#{@path} (#{@head})"
      end
    end

    def to_h
      {
        path: @path,
        branch: @branch,
        head: @head,
        detached: @detached,
        bare: @bare
      }
    end
  end
end