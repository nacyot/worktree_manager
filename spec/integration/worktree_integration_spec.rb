require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Worktree Integration Tests" do
  let(:test_id) { Time.now.to_i }
  let(:test_dir) { Dir.mktmpdir("worktree_integration_#{test_id}") }
  let(:main_repo_path) { File.join(test_dir, "main-repo") }
  let(:worktree_path) { File.join(test_dir, "test-worktree") }
  let(:branch_name) { "test/branch-#{test_id}" }
  let(:hook_file) { File.join(main_repo_path, ".worktree_hooks.yml") }

  before do
    # 테스트용 Git 저장소 생성
    Dir.chdir(test_dir) do
      `git init main-repo`
      Dir.chdir("main-repo") do
        `git config user.name "Test User"`
        `git config user.email "test@example.com"`
        File.write("README.md", "# Test Repository")
        `git add README.md`
        `git commit -m "Initial commit"`
      end
    end

    # Hook 파일 생성
    hook_config = <<~YAML
      pre_add:
        command: "echo \"테스트 Hook: Worktree 생성 시작 $WORKTREE_PATH\""
      post_add:
        - "echo \"테스트 Hook: Worktree 생성 완료 $WORKTREE_PATH\""
        - "echo \"브랜치: $WORKTREE_BRANCH\""
      pre_remove:
        command: "echo \"테스트 Hook: Worktree 삭제 시작 $WORKTREE_PATH\""
      post_remove:
        - "echo \"테스트 Hook: Worktree 삭제 완료 $WORKTREE_PATH\""
    YAML
    File.write(hook_file, hook_config)

    # 작업 디렉터리를 메인 저장소로 변경
    Dir.chdir(main_repo_path)
  end

  after do
    # 테스트 디렉터리 정리
    FileUtils.rm_rf(test_dir) if Dir.exist?(test_dir)
  end

  describe "완전한 워크플로우 테스트" do
    it "worktree 생성부터 삭제까지 전체 플로우가 정상 동작한다" do
      manager = WorktreeManager::Manager.new(main_repo_path)
      hook_manager = WorktreeManager::HookManager.new(main_repo_path)

      # 1. 초기 상태 확인
      expect(manager.list).to be_empty

      # 2. 새 브랜치로 worktree 생성
      expect(hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)).to be true
      
      worktree = manager.add_with_new_branch(worktree_path, branch_name)
      expect(worktree).not_to be_nil
      expect(worktree.path).to eq(worktree_path)
      expect(worktree.branch).to eq(branch_name)
      
      expect(hook_manager.execute_hook(:post_add, path: worktree_path, branch: branch_name)).to be true

      # 3. 생성된 worktree 확인
      worktrees = manager.list
      expect(worktrees.size).to eq(1)
      expect(worktrees.first.path).to eq(worktree_path)
      expect(worktrees.first.branch).to eq(branch_name)

      # 4. 파일 시스템에서 worktree 디렉터리 확인
      expect(Dir.exist?(worktree_path)).to be true
      expect(File.exist?(File.join(worktree_path, ".git"))).to be true

      # 5. Hook과 함께 worktree 삭제
      expect(hook_manager.execute_hook(:pre_remove, path: worktree_path, branch: branch_name)).to be true
      
      expect(manager.remove(worktree_path)).to be true
      
      expect(hook_manager.execute_hook(:post_remove, path: worktree_path, branch: branch_name)).to be true

      # 6. 삭제 확인
      expect(manager.list).to be_empty
      expect(Dir.exist?(worktree_path)).to be false
    end

    it "동일한 경로에 여러 번 생성하면 에러가 발생한다" do
      manager = WorktreeManager::Manager.new(main_repo_path)
      
      # 첫 번째 생성
      worktree1 = manager.add_with_new_branch(worktree_path, branch_name)
      expect(worktree1).not_to be_nil

      # 동일한 경로에 다시 생성 시도
      expect {
        manager.add_with_new_branch(worktree_path, "#{branch_name}-2")
      }.to raise_error(WorktreeManager::Error, /already exists/)

      # 정리
      manager.remove(worktree_path)
    end

    it "존재하지 않는 worktree 삭제 시 에러가 발생한다" do
      manager = WorktreeManager::Manager.new(main_repo_path)
      
      expect {
        manager.remove("/non/existent/path")
      }.to raise_error(WorktreeManager::Error, /not found/)
    end
  end

  describe "Hook 시스템 통합 테스트" do
    it "Hook 실행 중 에러가 발생하면 적절히 처리한다" do
      # 에러가 발생하는 Hook 설정
      error_hook_file = File.join(main_repo_path, ".worktree_hooks.yml")
      error_hook_config = <<~YAML
        pre_add:
          command: "exit 1"
          stop_on_error: true
      YAML
      File.write(error_hook_file, error_hook_config)

      hook_manager = WorktreeManager::HookManager.new(main_repo_path)
      
      # Hook 실행 시 false 반환
      expect(hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)).to be false
    end

    it "Hook에서 환경 변수가 올바르게 전달된다" do
      # 환경 변수 출력 Hook 설정
      env_hook_file = File.join(main_repo_path, ".worktree_hooks.yml")
      env_hook_config = <<~YAML
        pre_add:
          command: "echo \"PATH=$WORKTREE_PATH BRANCH=$WORKTREE_BRANCH ROOT=$WORKTREE_MANAGER_ROOT\""
      YAML
      File.write(env_hook_file, env_hook_config)

      hook_manager = WorktreeManager::HookManager.new(main_repo_path)
      
      # Hook 실행 시 환경 변수 확인
      expect {
        hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)
      }.to output(/PATH=.*test-worktree.*BRANCH=.*test\/branch.*ROOT=.*main-repo/).to_stdout
    end
  end

  describe "CLI 통합 테스트" do
    it "CLI를 통한 전체 워크플로우가 정상 동작한다" do
      cli = WorktreeManager::CLI.new

      # CLI 환경 설정
      allow(cli).to receive(:main_repository?).and_return(true)

      # add 명령 실행
      expect {
        cli.invoke(:add, [worktree_path], { branch: branch_name })
      }.to output(/Worktree created:.*test-worktree/).to_stdout

      # list 명령 실행
      expect {
        cli.list
      }.to output(/test-worktree/).to_stdout

      # remove 명령 실행
      expect {
        cli.remove(worktree_path)
      }.to output(/Worktree removed:.*test-worktree/).to_stdout
    end
  end
end