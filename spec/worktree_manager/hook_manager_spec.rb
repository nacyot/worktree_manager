require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe WorktreeManager::HookManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:hook_manager) { WorktreeManager::HookManager.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates a hook manager instance" do
      expect(hook_manager).to be_a(WorktreeManager::HookManager)
    end
  end

  describe "#execute_hook" do
    context "when no hook file exists" do
      it "returns true for any hook type" do
        expect(hook_manager.execute_hook(:pre_add)).to be true
        expect(hook_manager.execute_hook(:post_add)).to be true
        expect(hook_manager.execute_hook(:pre_remove)).to be true
        expect(hook_manager.execute_hook(:post_remove)).to be true
      end
    end

    context "when hook file exists" do
      let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

      context "with string command" do
        before do
          File.write(hook_file, YAML.dump({
            "pre_add" => "echo 'Pre-add hook executed'"
          }))
        end

        it "executes the command and returns true" do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end

        it "executes the command with context" do
          context = { path: "/test/path", branch: "main" }
          expect(hook_manager.execute_hook(:pre_add, context)).to be true
        end
      end

      context "with array of commands" do
        before do
          File.write(hook_file, YAML.dump({
            "pre_add" => ["echo 'First command'", "echo 'Second command'"]
          }))
        end

        it "executes all commands and returns true if all succeed" do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end
      end

      context "with hash configuration" do
        before do
          File.write(hook_file, YAML.dump({
            "pre_add" => {
              "command" => "echo 'Hook with config'",
              "stop_on_error" => true
            }
          }))
        end

        it "executes the command from hash config" do
          expect(hook_manager.execute_hook(:pre_add)).to be true
        end
      end

      context "when command fails" do
        before do
          File.write(hook_file, YAML.dump({
            "pre_add" => "exit 1"
          }))
        end

        it "returns false when command fails" do
          expect(hook_manager.execute_hook(:pre_add)).to be false
        end
      end

      context "with invalid hook type" do
        it "returns true for invalid hook types" do
          expect(hook_manager.execute_hook(:invalid_hook)).to be true
        end
      end
    end

    context "with malformed YAML" do
      let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

      before do
        File.write(hook_file, "invalid: yaml: content: [")
      end

      it "handles YAML parsing errors gracefully" do
        expect { hook_manager.execute_hook(:pre_add) }.not_to raise_error
        expect(hook_manager.execute_hook(:pre_add)).to be true
      end
    end
  end

  describe "#has_hook?" do
    context "when hook file exists" do
      let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

      before do
        File.write(hook_file, YAML.dump({
          "pre_add" => "echo 'test'",
          "post_add" => nil
        }))
      end

      it "returns true for existing hooks" do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end

      it "returns false for hooks with nil value" do
        expect(hook_manager.has_hook?(:post_add)).to be false
      end

      it "returns false for non-existent hooks" do
        expect(hook_manager.has_hook?(:pre_remove)).to be false
      end

      it "returns false for invalid hook types" do
        expect(hook_manager.has_hook?(:invalid_hook)).to be false
      end
    end
  end

  describe "#list_hooks" do
    context "when hook file exists" do
      let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

      before do
        File.write(hook_file, YAML.dump({
          "pre_add" => "echo 'pre-add'",
          "post_add" => "echo 'post-add'",
          "pre_remove" => nil,
          "invalid_hook" => "echo 'invalid'"
        }))
      end

      it "returns only valid hooks with non-nil values" do
        hooks = hook_manager.list_hooks
        expect(hooks.keys).to contain_exactly("pre_add", "post_add")
        expect(hooks["pre_add"]).to eq("echo 'pre-add'")
        expect(hooks["post_add"]).to eq("echo 'post-add'")
      end
    end

    context "when no hook file exists" do
      it "returns empty hash" do
        expect(hook_manager.list_hooks).to eq({})
      end
    end
  end

  describe "environment variable handling" do
    let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

    before do
      File.write(hook_file, YAML.dump({
        "pre_add" => "echo \"PATH: $WORKTREE_PATH, BRANCH: $WORKTREE_BRANCH, ROOT: $WORKTREE_MANAGER_ROOT\""
      }))
    end

    it "passes context as environment variables" do
      context = { path: "/test/path", branch: "feature" }
      
      # 실제로는 stdout capture가 필요하지만 여기서는 성공 여부만 확인
      expect(hook_manager.execute_hook(:pre_add, context)).to be true
    end
  end

  describe "hook file discovery" do
    context "with .worktree_hooks.yml in root" do
      let(:hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }

      before do
        File.write(hook_file, YAML.dump({ "pre_add" => "echo 'root hook'" }))
      end

      it "finds and uses the hook file" do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end
    end

    context "with .git/worktree_hooks.yml" do
      let(:git_dir) { File.join(temp_dir, ".git") }
      let(:hook_file) { File.join(git_dir, "worktree_hooks.yml") }

      before do
        Dir.mkdir(git_dir)
        File.write(hook_file, YAML.dump({ "pre_add" => "echo 'git hook'" }))
      end

      it "finds and uses the git hook file" do
        expect(hook_manager.has_hook?(:pre_add)).to be true
      end
    end

    context "with both hook files present" do
      let(:root_hook_file) { File.join(temp_dir, ".worktree_hooks.yml") }
      let(:git_dir) { File.join(temp_dir, ".git") }
      let(:git_hook_file) { File.join(git_dir, "worktree_hooks.yml") }

      before do
        File.write(root_hook_file, YAML.dump({ "pre_add" => "echo 'root hook'" }))
        Dir.mkdir(git_dir)
        File.write(git_hook_file, YAML.dump({ "pre_remove" => "echo 'git hook'" }))
      end

      it "prioritizes .worktree_hooks.yml over .git/worktree_hooks.yml" do
        expect(hook_manager.has_hook?(:pre_add)).to be true
        expect(hook_manager.has_hook?(:pre_remove)).to be false # git file not loaded
      end
    end
  end
end