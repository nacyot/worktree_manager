require "spec_helper"

RSpec.describe WorktreeManager::CLI do
  let(:cli) { WorktreeManager::CLI.new }

  describe "#version" do
    it "displays the version" do
      expect { cli.version }.to output("#{WorktreeManager::VERSION}\n").to_stdout
    end
  end

  describe "#list" do
    context "when not in a main repository" do
      before do
        allow(cli).to receive(:main_repository?).and_return(false)
      end

      it "exits with error message" do
        expect { cli.list }.to output(/Error: This command can only be run from the main Git repository/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when in a main repository" do
      let(:manager) { instance_double(WorktreeManager::Manager) }
      let(:worktree) { instance_double(WorktreeManager::Worktree, to_s: "/path/to/worktree main abcd123") }

      before do
        allow(cli).to receive(:main_repository?).and_return(true)
        allow(WorktreeManager::Manager).to receive(:new).and_return(manager)
      end

      context "when there are worktrees" do
        before do
          allow(manager).to receive(:list).and_return([worktree])
        end

        it "displays the worktree list" do
          expect { cli.list }.to output("/path/to/worktree main abcd123\n").to_stdout
        end
      end

      context "when there are no worktrees" do
        before do
          allow(manager).to receive(:list).and_return([])
        end

        it "displays no worktrees message" do
          expect { cli.list }.to output("No worktrees found.\n").to_stdout
        end
      end
    end
  end

  describe "#add" do
    let(:manager) { instance_double(WorktreeManager::Manager) }
    let(:hook_manager) { instance_double(WorktreeManager::HookManager) }
    let(:worktree) { instance_double(WorktreeManager::Worktree, path: "/test/path", branch: "main") }

    before do
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(WorktreeManager::Manager).to receive(:new).and_return(manager)
      allow(WorktreeManager::HookManager).to receive(:new).and_return(hook_manager)
    end

    context "when hooks succeed" do
      before do
        allow(hook_manager).to receive(:execute_hook).and_return(true)
        allow(manager).to receive(:add).and_return(worktree)
        allow(manager).to receive(:list).and_return([])
        allow(File).to receive(:expand_path).and_call_original
        allow(Dir).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: true)])
      end

      it "creates a worktree successfully" do
        expect { cli.add("/test/path") }.to output(/Worktree created: \/test\/path \(main\)/).to_stdout
      end

      it "executes pre_add and post_add hooks" do
        expect(hook_manager).to receive(:execute_hook).with(:pre_add, anything)
        expect(hook_manager).to receive(:execute_hook).with(:post_add, anything)
        cli.add("/test/path")
      end
    end

    context "when pre_add hook fails" do
      before do
        allow(hook_manager).to receive(:execute_hook).with(:pre_add, anything).and_return(false)
        allow(manager).to receive(:list).and_return([])
        allow(File).to receive(:expand_path).and_call_original
        allow(Dir).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: true)])
      end

      it "exits with error message" do
        expect { cli.add("/test/path") }.to output(/Error: pre_add hook failed/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when worktree creation fails" do
      before do
        allow(hook_manager).to receive(:execute_hook).and_return(true)
        allow(manager).to receive(:add).and_raise(WorktreeManager::Error, "Creation failed")
        allow(manager).to receive(:list).and_return([])
        allow(File).to receive(:expand_path).and_call_original
        allow(Dir).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: true)])
      end

      it "executes post_add hook with error context" do
        expect(hook_manager).to receive(:execute_hook).with(:post_add, hash_including(success: false, error: "Creation failed"))
        expect { cli.add("/test/path") }.to raise_error(SystemExit)
      end
    end

    context "with branch option" do
      before do
        allow(hook_manager).to receive(:execute_hook).and_return(true)
        allow(manager).to receive(:add_with_new_branch).and_return(worktree)
        allow(manager).to receive(:list).and_return([])
        allow(File).to receive(:expand_path).and_call_original
        allow(Dir).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: true)])
      end

      it "creates worktree with new branch" do
        cli.invoke(:add, ["/test/path"], { branch: "feature" })
        expect(manager).to have_received(:add_with_new_branch).with("/test/path", "feature", force: nil)
      end
    end
  end

  describe "#remove" do
    let(:manager) { instance_double(WorktreeManager::Manager) }
    let(:hook_manager) { instance_double(WorktreeManager::HookManager) }
    let(:worktree) { instance_double(WorktreeManager::Worktree, path: "/test/path", branch: "feature") }

    before do
      allow(cli).to receive(:main_repository?).and_return(true)
      allow(WorktreeManager::Manager).to receive(:new).and_return(manager)
      allow(WorktreeManager::HookManager).to receive(:new).and_return(hook_manager)
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with("/test/path").and_return("/test/path")
      allow(File).to receive(:expand_path).with(".").and_return("/current/dir")
    end

    context "when worktree exists and hooks succeed" do
      before do
        allow(manager).to receive(:list).and_return([worktree])
        allow(hook_manager).to receive(:execute_hook).and_return(true)
        allow(manager).to receive(:remove).and_return(true)
      end

      it "removes worktree successfully" do
        expect { cli.remove("/test/path") }.to output(/Worktree removed: \/test\/path/).to_stdout
      end

      it "executes pre_remove and post_remove hooks" do
        expect(hook_manager).to receive(:execute_hook).with(:pre_remove, anything)
        expect(hook_manager).to receive(:execute_hook).with(:post_remove, anything)
        cli.remove("/test/path")
      end
    end

    context "when worktree does not exist" do
      before do
        allow(manager).to receive(:list).and_return([])
      end

      it "exits with error message" do
        expect { cli.remove("/test/path") }.to output(/Error: Worktree not found at path/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when pre_remove hook fails" do
      before do
        allow(manager).to receive(:list).and_return([worktree])
        allow(hook_manager).to receive(:execute_hook).with(:pre_remove, anything).and_return(false)
      end

      it "exits with error message" do
        expect { cli.remove("/test/path") }.to output(/Error: pre_remove hook failed/).to_stdout
          .and raise_error(SystemExit)
      end
    end
  end

  describe "#main_repository?" do
    subject { cli.send(:main_repository?) }

    context "when .git is a directory" do
      before do
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".git")).and_return(true)
        allow(File).to receive(:directory?).with(File.join(Dir.pwd, ".git")).and_return(true)
      end

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "when .git is a file with gitdir content" do
      before do
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".git")).and_return(true)
        allow(File).to receive(:directory?).with(File.join(Dir.pwd, ".git")).and_return(false)
        allow(File).to receive(:file?).with(File.join(Dir.pwd, ".git")).and_return(true)
        allow(File).to receive(:read).with(File.join(Dir.pwd, ".git")).and_return("gitdir: /path/to/main/.git/worktrees/branch")
      end

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "when .git is a file without gitdir content" do
      before do
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".git")).and_return(true)
        allow(File).to receive(:directory?).with(File.join(Dir.pwd, ".git")).and_return(false)
        allow(File).to receive(:file?).with(File.join(Dir.pwd, ".git")).and_return(true)
        allow(File).to receive(:read).with(File.join(Dir.pwd, ".git")).and_return("some other content")
      end

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "when .git does not exist" do
      before do
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".git")).and_return(false)
      end

      it "returns false" do
        expect(subject).to be false
      end
    end
  end
end