require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'pathname'

RSpec.describe 'Worktree Integration Tests' do
  let(:original_dir) { Dir.pwd }
  let(:test_id) { Time.now.to_i }
  let(:test_dir) { Dir.mktmpdir("worktree_integration_#{test_id}") }
  let(:main_repo_path) { File.join(test_dir, 'main-repo') }
  let(:worktree_path) { File.join(test_dir, 'test-worktree') }
  let(:branch_name) { "test/branch-#{test_id}" }
  let(:hook_file) { File.join(main_repo_path, '.worktree.yml') }

  around do |example|
    # Save original directory
    Dir.chdir(original_dir) do
      # Create test Git repository
      Dir.chdir(test_dir) do
        `git init main-repo`
        Dir.chdir('main-repo') do
          `git config user.name "Test User"`
          `git config user.email "test@example.com"`
          File.write('README.md', '# Test Repository')
          `git add README.md`
          `git commit -m "Initial commit"`
        end
      end

      # Create hook file
      hook_config = <<~YAML
        hooks:
          pre_add:
            commands:
              - "echo \\"Test Hook: Starting worktree creation $WORKTREE_PATH\\""
          post_add:
            commands:
              - "echo \\"Test Hook: Worktree creation completed $WORKTREE_PATH\\""
              - "echo \\"Branch: $WORKTREE_BRANCH\\""
          pre_remove:
            commands:
              - "echo \\"Test Hook: Starting worktree removal $WORKTREE_PATH\\""
          post_remove:
            commands:
              - "echo \\"Test Hook: Worktree removal completed $WORKTREE_PATH\\""
      YAML
      File.write(hook_file, hook_config)

      # Run example in main repository
      Dir.chdir(main_repo_path) do
        example.run
      end
    end
  ensure
    # Clean up test directory
    FileUtils.rm_rf(test_dir) if Dir.exist?(test_dir)
  end

  describe 'Complete workflow tests' do
    it 'works correctly from worktree creation to removal' do
      manager = WorktreeManager::Manager.new(main_repo_path)
      hook_manager = WorktreeManager::HookManager.new(main_repo_path)

      # 1. Check initial state (main repository is also included as a worktree)
      initial_worktrees = manager.list
      initial_count = initial_worktrees.size

      # 2. Create worktree with new branch
      expect(hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)).to be true

      worktree = manager.add_with_new_branch(worktree_path, branch_name)
      expect(worktree).not_to be_nil
      expect(worktree.path).to eq(worktree_path)
      expect(worktree.branch).to eq(branch_name)

      expect(hook_manager.execute_hook(:post_add, path: worktree_path, branch: branch_name)).to be true

      # 3. Verify created worktree
      worktrees = manager.list
      expect(worktrees.size).to eq(initial_count + 1)

      new_worktree = worktrees.find do |w|
        File.realpath(w.path) == File.realpath(worktree_path)
      end
      expect(new_worktree).not_to be_nil
      expect(new_worktree.branch).to eq("refs/heads/#{branch_name}")

      # 4. Verify worktree directory in file system
      expect(Dir.exist?(worktree_path)).to be true
      expect(File.exist?(File.join(worktree_path, '.git'))).to be true

      # 5. Remove worktree with hooks
      expect(hook_manager.execute_hook(:pre_remove, path: worktree_path, branch: branch_name)).to be true

      expect(manager.remove(worktree_path)).to be true

      expect(hook_manager.execute_hook(:post_remove, path: worktree_path, branch: branch_name)).to be true

      # 6. Verify removal
      expect(manager.list.size).to eq(initial_count)
      expect(Dir.exist?(worktree_path)).to be false
    end

    it 'raises error when creating multiple times at the same path' do
      manager = WorktreeManager::Manager.new(main_repo_path)

      # First creation
      worktree1 = manager.add_with_new_branch(worktree_path, branch_name)
      expect(worktree1).not_to be_nil

      # Try to create again at the same path
      expect do
        manager.add_with_new_branch(worktree_path, "#{branch_name}-2")
      end.to raise_error(WorktreeManager::Error, /already exists/)

      # Cleanup
      manager.remove(worktree_path)
    end

    it 'raises error when removing non-existent worktree' do
      manager = WorktreeManager::Manager.new(main_repo_path)

      expect do
        manager.remove('/non/existent/path')
      end.to raise_error(WorktreeManager::Error, /is not a working tree/)
    end
  end

  describe 'Hook system integration tests' do
    it 'handles errors during hook execution properly' do
      # Set up hook that causes error
      error_hook_file = File.join(main_repo_path, '.worktree.yml')
      error_hook_config = <<~YAML
        hooks:
          pre_add:
            commands:
              - "exit 1"
            stop_on_error: true
      YAML
      File.write(error_hook_file, error_hook_config)

      hook_manager = WorktreeManager::HookManager.new(main_repo_path)

      # Hook execution returns false
      expect(hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)).to be false
    end

    it 'passes environment variables correctly to hooks' do
      # Set up hook that outputs environment variables
      env_hook_file = File.join(main_repo_path, '.worktree.yml')
      env_hook_config = <<~YAML
        hooks:
          pre_add:
            commands:
              - "echo \\"PATH=$WORKTREE_PATH BRANCH=$WORKTREE_BRANCH ROOT=$WORKTREE_MAIN\\""
      YAML
      File.write(env_hook_file, env_hook_config)

      hook_manager = WorktreeManager::HookManager.new(main_repo_path)

      # Verify environment variables during hook execution
      expect do
        hook_manager.execute_hook(:pre_add, path: worktree_path, branch: branch_name)
      end.to output(%r{PATH=.*test-worktree.*BRANCH=.*test/branch.*ROOT=.*main-repo}).to_stdout
    end
  end

  describe 'CLI integration tests' do
    it 'complete workflow works correctly through CLI' do
      cli = WorktreeManager::CLI.new

      # Set up CLI environment
      allow(cli).to receive(:main_repository?).and_return(true)
      # Stub exit to prevent actual process termination
      allow(cli).to receive(:exit)

      # Execute add command
      expect do
        cli.invoke(:add, [worktree_path], { branch: branch_name })
      end.to output(/Worktree created:.*test-worktree/).to_stdout

      # Execute list command
      expect do
        cli.list
      end.to output(/test-worktree/).to_stdout

      # Execute remove command
      # Git stores relative paths, so remove using relative path
      relative_path = Pathname.new(worktree_path).relative_path_from(Pathname.new(main_repo_path)).to_s
      expect do
        cli.remove(relative_path)
      end.to output(/Worktree removed:.*test-worktree/).to_stdout
    end
  end

  describe 'worktrees_dir feature integration tests' do
    let(:worktrees_dir) { '../worktrees' }
    let(:worktree_name) { "feature-branch-#{test_id}" }
    let(:expected_path) { File.expand_path(File.join(worktrees_dir, worktree_name), main_repo_path) }

    before do
      # Add worktrees_dir configuration
      config_with_dir = <<~YAML
        worktrees_dir: "#{worktrees_dir}"
        hooks:
          post_add:
            commands:
              - "echo 'Worktree created at $WORKTREE_ABSOLUTE_PATH'"
      YAML
      File.write(hook_file, config_with_dir)
    end

    it 'creates worktree according to worktrees_dir setting' do
      cli = WorktreeManager::CLI.new
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(cli).to receive(:exit)

      # Add worktree with name only
      expect do
        cli.invoke(:add, [worktree_name], { branch: worktree_name })
      end.to output(/Worktree created:.*#{worktree_name}/).to_stdout

      # Verify created at correct location
      expect(Dir.exist?(expected_path)).to be true

      # Cleanup
      manager = WorktreeManager::Manager.new(main_repo_path)
      manager.remove(expected_path)
    end

    it 'removes worktree using worktrees_dir setting' do
      # Create worktree first
      manager = WorktreeManager::Manager.new(main_repo_path)
      FileUtils.mkdir_p(File.dirname(expected_path))
      manager.add_with_new_branch(expected_path, worktree_name)

      cli = WorktreeManager::CLI.new
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(cli).to receive(:exit)

      # Remove worktree with name only
      expect do
        cli.remove(worktree_name)
      end.to output(/Worktree removed:.*#{worktree_name}/).to_stdout

      expect(Dir.exist?(expected_path)).to be false
    end

    it 'processes relative path based on repository' do
      cli = WorktreeManager::CLI.new
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(cli).to receive(:exit)

      relative_path = '../custom/worktree'
      expected_custom_path = File.expand_path(relative_path, main_repo_path)

      # Add worktree with relative path
      expect do
        cli.invoke(:add, [relative_path], { branch: 'custom-branch' })
      end.to output(%r{Worktree created:.*custom/worktree}).to_stdout

      expect(Dir.exist?(expected_custom_path)).to be true

      # Cleanup
      manager = WorktreeManager::Manager.new(main_repo_path)
      manager.remove(expected_custom_path)
    end

    it 'uses absolute path as is when provided' do
      cli = WorktreeManager::CLI.new
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(cli).to receive(:exit)

      absolute_path = File.join(test_dir, 'absolute-worktree')

      # Add worktree with absolute path
      expect do
        cli.invoke(:add, [absolute_path], { branch: 'absolute-branch' })
      end.to output(/Worktree created:.*absolute-worktree/).to_stdout

      expect(Dir.exist?(absolute_path)).to be true

      # Cleanup
      manager = WorktreeManager::Manager.new(main_repo_path)
      manager.remove(absolute_path)
    end
  end
end
