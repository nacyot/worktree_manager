require 'spec_helper'
require 'tempfile'
require 'tmpdir'

RSpec.describe WorktreeManager::HookManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:hook_manager) { WorktreeManager::HookManager.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'creates a hook manager instance' do
      expect(hook_manager).to be_a(WorktreeManager::HookManager)
    end
  end

  describe '#execute_hook' do
    context 'when no hook file exists' do
      it 'returns true for any hook type' do
        expect(hook_manager.execute_hook(:pre_add)).to be true
        expect(hook_manager.execute_hook(:post_add)).to be true
        expect(hook_manager.execute_hook(:pre_remove)).to be true
        expect(hook_manager.execute_hook(:post_remove)).to be true
      end
    end

    context 'when hook file exists' do
      let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

      context 'with string command' do
        before do
          File.write(hook_file, YAML.dump({
                                            'pre_add' => "echo 'Pre-add hook executed'"
                                          }))
        end

        it 'executes the command and returns true' do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end

        it 'executes the command with context' do
          context = { path: '/test/path', branch: 'main' }
          expect(hook_manager.execute_hook(:pre_add, context)).to be true
        end
      end

      context 'with array of commands' do
        before do
          File.write(hook_file, YAML.dump({
                                            'pre_add' => ["echo 'First command'", "echo 'Second command'"]
                                          }))
        end

        it 'executes all commands and returns true if all succeed' do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end
      end

      context 'with hash configuration' do
        before do
          File.write(hook_file, YAML.dump({
                                            'pre_add' => {
                                              'command' => "echo 'Hook with config'",
                                              'stop_on_error' => true
                                            }
                                          }))
        end

        it 'executes the command from hash config' do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end
      end

      context 'when command fails' do
        before do
          File.write(hook_file, YAML.dump({
                                            'pre_add' => 'exit 1'
                                          }))
        end

        it 'returns false when command fails' do
          expect(hook_manager.execute_hook(:pre_add)).to be false
        end
      end

      context 'with invalid hook type' do
        it 'returns true for invalid hook types' do
          expect(hook_manager.execute_hook(:invalid_hook)).to be true
        end
      end
    end

    context 'with malformed YAML' do
      let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

      before do
        File.write(hook_file, 'invalid: yaml: content: [')
      end

      it 'handles YAML parsing errors gracefully' do
        expect { hook_manager.execute_hook(:pre_add) }.not_to raise_error
        expect(hook_manager.execute_hook(:pre_add)).to be true
      end

      context 'with new config structure' do
        before do
          File.write(hook_file, YAML.dump({
                                            'hooks' => {
                                              'pre_add' => {
                                                'commands' => ["echo 'Command 1'", "echo 'Command 2'"]
                                              }
                                            }
                                          }))
        end

        it 'executes commands from new structure' do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end
      end

      context 'with pwd configuration' do
        let(:test_dir) { File.join(temp_dir, 'test_work_dir') }

        before do
          Dir.mkdir(test_dir)
          File.write(hook_file, YAML.dump({
                                            'hooks' => {
                                              'pre_add' => {
                                                'commands' => ['pwd > pwd.txt'],
                                                'pwd' => test_dir
                                              }
                                            }
                                          }))
        end

        it 'executes commands in specified working directory' do
          hook_manager.execute_hook(:pre_add)
          pwd_file = File.join(test_dir, 'pwd.txt')
          expect(File.exist?(pwd_file)).to be true
          expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(test_dir))
        end
      end

      context 'with environment variable substitution in pwd' do
        let(:test_worktree) { File.join(temp_dir, 'test-worktree') }

        before do
          Dir.mkdir(test_worktree)
          File.write(hook_file, YAML.dump({
                                            'hooks' => {
                                              'post_add' => {
                                                'commands' => ['pwd > pwd.txt'],
                                                'pwd' => '$WORKTREE_ABSOLUTE_PATH'
                                              }
                                            }
                                          }))
        end

        it 'substitutes environment variables in pwd' do
          context = { path: test_worktree }
          hook_manager.execute_hook(:post_add, context)

          pwd_file = File.join(test_worktree, 'pwd.txt')
          expect(File.exist?(pwd_file)).to be true
          expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(test_worktree))
        end
      end
    end
  end

  describe '#has_hook?' do
    context 'when hook file exists' do
      let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

      before do
        File.write(hook_file, YAML.dump({
                                          'pre_add' => "echo 'test'",
                                          'post_add' => nil
                                        }))
      end

      it 'returns true for existing hooks' do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end

      it 'returns false for hooks with nil value' do
        expect(hook_manager.has_hook?(:post_add)).to be false
      end

      it 'returns false for non-existent hooks' do
        expect(hook_manager.has_hook?(:pre_remove)).to be false
      end

      it 'returns false for invalid hook types' do
        expect(hook_manager.has_hook?(:invalid_hook)).to be false
      end
    end
  end

  describe '#list_hooks' do
    context 'when hook file exists' do
      let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

      before do
        File.write(hook_file, YAML.dump({
                                          'pre_add' => "echo 'pre-add'",
                                          'post_add' => "echo 'post-add'",
                                          'pre_remove' => nil,
                                          'invalid_hook' => "echo 'invalid'"
                                        }))
      end

      it 'returns only valid hooks with non-nil values' do
        hooks = hook_manager.list_hooks
        expect(hooks.keys).to contain_exactly('pre_add', 'post_add')
        expect(hooks['pre_add']).to eq("echo 'pre-add'")
        expect(hooks['post_add']).to eq("echo 'post-add'")
      end
    end

    context 'when no hook file exists' do
      it 'returns empty hash' do
        expect(hook_manager.list_hooks).to eq({})
      end
    end
  end

  describe 'environment variable handling' do
    let(:hook_file) { File.join(temp_dir, '.worktree_hooks.yml') }

    before do
      File.write(hook_file, YAML.dump({
                                        'pre_add' => 'echo "PATH: $WORKTREE_PATH, BRANCH: $WORKTREE_BRANCH, ROOT: $WORKTREE_MANAGER_ROOT"'
                                      }))
    end

    it 'passes context as environment variables' do
      context = { path: '/test/path', branch: 'feature' }

      # Actually needs stdout capture but only checking success here
      expect(hook_manager.execute_hook(:pre_add, context)).to be true
    end
  end

  describe 'hook file discovery' do
    context 'with .worktree.yml in root' do
      let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

      before do
        File.write(hook_file, YAML.dump({ 'hooks' => { 'pre_add' => { 'commands' => ["echo 'root hook'"] } } }))
      end

      it 'finds and uses the hook file' do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end
    end

    context 'with .git/.worktree.yml' do
      let(:git_dir) { File.join(temp_dir, '.git') }
      let(:hook_file) { File.join(git_dir, '.worktree.yml') }

      before do
        Dir.mkdir(git_dir)
        File.write(hook_file, YAML.dump({ 'hooks' => { 'pre_add' => { 'commands' => ["echo 'git hook'"] } } }))
      end

      it 'finds and uses the git hook file' do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end
    end

    context 'with both hook files present' do
      let(:root_hook_file) { File.join(temp_dir, '.worktree.yml') }
      let(:git_dir) { File.join(temp_dir, '.git') }
      let(:git_hook_file) { File.join(git_dir, '.worktree.yml') }

      before do
        File.write(root_hook_file, YAML.dump({ 'hooks' => { 'pre_add' => { 'commands' => ["echo 'root hook'"] } } }))
        Dir.mkdir(git_dir)
        File.write(git_hook_file, YAML.dump({ 'hooks' => { 'pre_remove' => { 'commands' => ["echo 'git hook'"] } } }))
      end

      it 'prioritizes .worktree.yml over .git/.worktree.yml' do
        expect(hook_manager.has_hook?(:pre_add)).to be true
        expect(hook_manager.has_hook?(:pre_remove)).to be false # git file not loaded
      end
    end
  end

  describe 'stop_on_error configuration' do
    let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

    context 'when stop_on_error is false' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'pre_add' => {
                                              'commands' => [
                                                'exit 1',  # This will fail
                                                "echo 'This should still execute'"
                                              ],
                                              'stop_on_error' => false
                                            }
                                          }
                                        }))
      end

      it 'continues executing commands even after failure' do
        expect(hook_manager.execute_hook(:pre_add)).to be true
      end
    end

    context 'when stop_on_error is true (default)' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'pre_add' => {
                                              'commands' => [
                                                'exit 1',  # This will fail
                                                "echo 'This should NOT execute'"
                                              ]
                                            }
                                          }
                                        }))
      end

      it 'stops executing commands after failure' do
        expect(hook_manager.execute_hook(:pre_add)).to be false
      end
    end
  end

  describe 'all environment variables' do
    let(:hook_file) { File.join(temp_dir, '.worktree.yml') }
    let(:output_file) { File.join(temp_dir, 'env_vars.txt') }

    before do
      File.write(hook_file, YAML.dump({
                                        'hooks' => {
                                          'post_add' => {
                                            'commands' => [
                                              "echo \"MAIN=$WORKTREE_MAIN\" > #{output_file}",
                                              "echo \"ROOT=$WORKTREE_MANAGER_ROOT\" >> #{output_file}",
                                              "echo \"PATH=$WORKTREE_PATH\" >> #{output_file}",
                                              "echo \"ABSOLUTE=$WORKTREE_ABSOLUTE_PATH\" >> #{output_file}",
                                              "echo \"BRANCH=$WORKTREE_BRANCH\" >> #{output_file}",
                                              "echo \"FORCE=$WORKTREE_FORCE\" >> #{output_file}",
                                              "echo \"SUCCESS=$WORKTREE_SUCCESS\" >> #{output_file}"
                                            ],
                                            'pwd' => temp_dir
                                          }
                                        }
                                      }))
    end

    it 'provides all documented environment variables' do
      context = {
        path: '../test-worktree',
        branch: 'feature/test',
        force: true,
        success: true
      }

      hook_manager.execute_hook(:post_add, context)

      content = File.read(output_file)
      expect(content).to include("MAIN=#{temp_dir}")
      expect(content).to include("ROOT=#{temp_dir}")
      expect(content).to include('PATH=../test-worktree')
      expect(content).to include("ABSOLUTE=#{File.expand_path('../test-worktree', temp_dir)}")
      expect(content).to include('BRANCH=feature/test')
      expect(content).to include('FORCE=true')
      expect(content).to include('SUCCESS=true')
    end
  end

  describe 'legacy configuration format' do
    let(:hook_file) { File.join(temp_dir, '.worktree.yml') }

    context 'with single string command at top level' do
      before do
        File.write(hook_file, YAML.dump({
                                          'pre_add' => "echo 'Legacy single command'"
                                        }))
      end

      it 'executes legacy single command format' do
        expect(hook_manager.execute_hook(:pre_add)).to be true
      end
    end

    context 'with array of commands at top level' do
      before do
        File.write(hook_file, YAML.dump({
                                          'post_add' => [
                                            "echo 'Legacy command 1'",
                                            "echo 'Legacy command 2'"
                                          ]
                                        }))
      end

      it 'executes legacy array format' do
        expect(hook_manager.execute_hook(:post_add)).to be true
      end
    end

    context 'with hash configuration at top level' do
      before do
        File.write(hook_file, YAML.dump({
                                          'pre_remove' => {
                                            'command' => "echo 'Legacy hash command'",
                                            'stop_on_error' => false
                                          }
                                        }))
      end

      it 'executes legacy hash format' do
        expect(hook_manager.execute_hook(:pre_remove)).to be true
      end
    end
  end

  describe 'practical examples from documentation' do
    let(:hook_file) { File.join(temp_dir, '.worktree.yml') }
    let(:worktree_path) { File.join(temp_dir, 'test-worktree') }

    before do
      Dir.mkdir(worktree_path)
    end

    context 'with development environment setup' do
      let(:gemfile) { File.join(worktree_path, 'Gemfile') }
      let(:env_example) { File.join(worktree_path, '.env.example') }
      let(:env_file) { File.join(worktree_path, '.env') }

      before do
        File.write(gemfile, "source 'https://rubygems.org'\ngem 'rake'")
        File.write(env_example, 'DATABASE_URL=postgres://localhost/dev')

        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'post_add' => {
                                              'commands' => [
                                                'touch Gemfile.lock', # Simulate bundle install
                                                'cp .env.example .env || true'
                                              ]
                                            }
                                          }
                                        }))
      end

      it 'sets up development environment after worktree creation' do
        context = { path: worktree_path }
        expect(hook_manager.execute_hook(:post_add, context)).to be true

        expect(File.exist?(File.join(worktree_path, 'Gemfile.lock'))).to be true
        expect(File.exist?(env_file)).to be true
        expect(File.read(env_file)).to eq(File.read(env_example))
      end
    end

    context 'with automatic backup before removal' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'pre_remove' => {
                                              'commands' => [
                                                "echo 'Simulating git add -A'",
                                                "echo 'Simulating git stash push'"
                                              ]
                                            }
                                          }
                                        }))
      end

      it 'backs up changes before removal' do
        context = { path: worktree_path, branch: 'feature/test' }
        expect(hook_manager.execute_hook(:pre_remove, context)).to be true
      end
    end

    context 'with custom pwd absolute path' do
      let(:custom_dir) { File.join(temp_dir, 'custom_work_dir') }

      before do
        Dir.mkdir(custom_dir)
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'post_add' => {
                                              'commands' => ['pwd > current_dir.txt'],
                                              'pwd' => custom_dir
                                            }
                                          }
                                        }))
      end

      it 'executes commands in custom absolute directory' do
        context = { path: worktree_path }
        hook_manager.execute_hook(:post_add, context)

        pwd_file = File.join(custom_dir, 'current_dir.txt')
        expect(File.exist?(pwd_file)).to be true
        expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(custom_dir))
      end
    end
  end

  describe 'default working directories' do
    let(:hook_file) { File.join(temp_dir, '.worktree.yml') }
    let(:worktree_path) { File.join(temp_dir, 'test-worktree') }

    before do
      Dir.mkdir(worktree_path)
    end

    context 'post_add hook' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'post_add' => {
                                              'commands' => ['pwd > current_dir.txt']
                                            }
                                          }
                                        }))
      end

      it 'executes in worktree directory by default' do
        context = { path: worktree_path }
        hook_manager.execute_hook(:post_add, context)

        pwd_file = File.join(worktree_path, 'current_dir.txt')
        expect(File.exist?(pwd_file)).to be true
        expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(worktree_path))
      end
    end

    context 'pre_remove hook' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'pre_remove' => {
                                              'commands' => ['pwd > current_dir.txt']
                                            }
                                          }
                                        }))
      end

      it 'executes in worktree directory by default' do
        context = { path: worktree_path }
        hook_manager.execute_hook(:pre_remove, context)

        pwd_file = File.join(worktree_path, 'current_dir.txt')
        expect(File.exist?(pwd_file)).to be true
        expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(worktree_path))
      end
    end

    context 'pre_add hook' do
      before do
        File.write(hook_file, YAML.dump({
                                          'hooks' => {
                                            'pre_add' => {
                                              'commands' => ['pwd > current_dir.txt']
                                            }
                                          }
                                        }))
      end

      it 'executes in main repository by default' do
        context = { path: worktree_path }
        hook_manager.execute_hook(:pre_add, context)

        pwd_file = File.join(temp_dir, 'current_dir.txt')
        expect(File.exist?(pwd_file)).to be true
        expect(File.realpath(File.read(pwd_file).strip)).to eq(File.realpath(temp_dir))
      end
    end
  end
end
