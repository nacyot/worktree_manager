require "thor"
require "open3"
require_relative "version"
require_relative "manager"
require_relative "hook_manager"

module WorktreeManager
  class CLI < Thor
    class_option :verbose, aliases: "-v", type: :boolean, desc: "Enable verbose output for debugging"

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

    desc "add PATH [BRANCH]", "Create a new worktree"
    method_option :branch, aliases: "-b", desc: "Create a new branch for the worktree"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force creation even if directory exists"
    def add(path, branch = nil)
      validate_main_repository!
      
      # 입력값 검증
      if path.nil? || path.strip.empty?
        puts "Error: Path cannot be empty"
        exit(1)
      end
      
      # 옵션에서 브랜치명 가져오기 (인수보다 옵션 우선)
      target_branch = options[:branch] || branch
      
      # 브랜치명 검증
      if target_branch && !valid_branch_name?(target_branch)
        puts "Error: Invalid branch name '#{target_branch}'. Branch names cannot contain spaces or special characters."
        exit(1)
      end
      
      # 기존 워크트리와의 충돌 확인
      validate_no_conflicts!(path, target_branch)
      
      manager = Manager.new
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      # Pre-add hook 실행
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
        # Worktree 생성
        if target_branch
          if options[:branch]
            # 새 브랜치 생성
            result = manager.add_with_new_branch(path, target_branch, force: options[:force])
          else
            # 기존 브랜치 사용
            result = manager.add(path, target_branch, force: options[:force])
          end
        else
          result = manager.add(path, force: options[:force])
        end
        
        puts "Worktree created: #{result.path} (#{result.branch || 'detached'})"
        
        # Post-add hook 실행
        context[:success] = true
        hook_manager.execute_hook(:post_add, context)
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # 실패 시 post-add hook을 에러 컨텍스트로 실행
        context[:success] = false
        context[:error] = e.message
        hook_manager.execute_hook(:post_add, context)
        
        exit(1)
      end
    end

    desc "remove PATH", "Remove an existing worktree"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force removal even if worktree has changes"
    def remove(path)
      validate_main_repository!
      
      # 입력값 검증
      if path.nil? || path.strip.empty?
        puts "Error: Path cannot be empty"
        exit(1)
      end
      
      # 메인 저장소 삭제 방지
      if File.expand_path(path) == File.expand_path(".")
        puts "Error: Cannot remove the main repository itself"
        exit(1)
      end
      
      manager = Manager.new
      hook_manager = HookManager.new(".", verbose: options[:verbose])
      
      # 경로 정규화
      normalized_path = File.expand_path(path)
      
      # 삭제할 worktree 정보 조회
      worktrees = manager.list
      target_worktree = worktrees.find { |wt| File.expand_path(wt.path) == normalized_path }
      
      unless target_worktree
        puts "Error: Worktree not found at path: #{path}"
        exit(1)
      end
      
      # Pre-remove hook 실행
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
        # Worktree 삭제
        manager.remove(path, force: options[:force])
        
        puts "Worktree removed: #{target_worktree.path}"
        
        # Post-remove hook 실행
        context[:success] = true
        hook_manager.execute_hook(:post_remove, context)
        
      rescue WorktreeManager::Error => e
        puts "Error: #{e.message}"
        
        # 실패 시 post-remove hook을 에러 컨텍스트로 실행
        context[:success] = false
        context[:error] = e.message
        hook_manager.execute_hook(:post_remove, context)
        
        exit(1)
      end
    end

    private

    def validate_main_repository!
      unless main_repository?
        puts "Error: This command can only be run from the main Git repository (not from a worktree)."
        exit(1)
      end
    end

    def validate_no_conflicts!(path, branch_name)
      manager = Manager.new
      
      # 경로 충돌 확인
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
      
      # 브랜치 충돌 확인 (새 브랜치 생성 시가 아닌 경우)
      if branch_name && !options[:branch]
        existing_branch = existing_worktrees.find { |wt| wt.branch == branch_name }
        if existing_branch
          puts "Error: Branch '#{branch_name}' is already checked out in another worktree"
          puts "  Existing worktree: #{existing_branch.path} (#{existing_branch.branch})"
          puts "  Use a different branch name or -b option to create a new branch"
          exit(1)
        end
      end
      
      # 새 브랜치 생성 시 브랜치명 중복 확인
      if options[:branch]
        output, status = Open3.capture2e("git", "branch", "--list", branch_name)
        if status.success? && !output.strip.empty?
          puts "Error: Branch '#{branch_name}' already exists"
          puts "  Use a different branch name or checkout the existing branch"
          exit(1)
        end
      end
      
      # 디렉터리 존재 확인 (force 옵션이 없는 경우)
      if !options[:force] && Dir.exist?(normalized_path) && !Dir.empty?(normalized_path)
        puts "Error: Directory '#{path}' already exists and is not empty"
        puts "  Use --force to override or choose a different path"
        exit(1)
      end
    end

    def valid_branch_name?(branch_name)
      return false if branch_name.nil? || branch_name.strip.empty?
      
      # 기본적인 Git 브랜치명 규칙 확인
      invalid_patterns = [
        /\s/,           # 공백 포함
        /\.\./,         # 연속된 점
        /^[\.\-]/,      # 점이나 대시로 시작
        /[\.\-]$/,      # 점이나 대시로 끝남
        /[~^:?*\[\]\\]/ # 특수 문자
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
  end
end