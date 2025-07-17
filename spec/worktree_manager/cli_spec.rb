require "spec_helper"

RSpec.describe WorktreeManager::CLI do
  let(:cli) { WorktreeManager::CLI.new }

  describe "#version" do
    it "displays the version" do
      expect { cli.version }.to output("#{WorktreeManager::VERSION}\n").to_stdout
    end
  end

  describe "#list" do
    context "when not in a git repository" do
      before do
        allow(cli).to receive(:find_main_repository_path).and_return(nil)
      end

      it "exits with error message" do
        expect { cli.list }.to output(/Error: Not in a Git repository/).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when in a worktree" do
      let(:manager) { instance_double(WorktreeManager::Manager) }
      let(:worktree) { instance_double(WorktreeManager::Worktree, to_s: "/path/to/worktree main abcd123") }
      let(:main_repo_path) { "/path/to/main/repo" }

      before do
        allow(cli).to receive(:main_repository?).and_return(false)
        allow(cli).to receive(:find_main_repository_path).and_return(main_repo_path)
        allow(WorktreeManager::Manager).to receive(:new).with(main_repo_path).and_return(manager)
        allow(manager).to receive(:list).and_return([worktree])
      end

      it "displays main repository path and cd command" do
        expected_output = <<~OUTPUT
          Running from worktree. Main repository: #{main_repo_path}
          To enter the main repository, run:
            cd #{main_repo_path}

          /path/to/worktree main abcd123
        OUTPUT
        expect { cli.list }.to output(expected_output).to_stdout
      end
    end

    context "when in a main repository" do
      let(:manager) { instance_double(WorktreeManager::Manager) }
      let(:worktree) { instance_double(WorktreeManager::Worktree, to_s: "/path/to/worktree main abcd123") }
      let(:main_repo_path) { "/path/to/main/repo" }

      before do
        allow(cli).to receive(:main_repository?).and_return(true)
        allow(cli).to receive(:find_main_repository_path).and_return(main_repo_path)
        allow(WorktreeManager::Manager).to receive(:new).with(main_repo_path).and_return(manager)
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

    context "when running from a worktree" do
      let(:main_repo_path) { "/path/to/main/repo" }

      before do
        allow(cli).to receive(:main_repository?).and_return(false)
        allow(cli).to receive(:find_main_repository_path).and_return(main_repo_path)
      end

      it "exits with error message and shows cd command" do
        expected_output = <<~OUTPUT
          Error: This command can only be run from the main Git repository (not from a worktree).
          To enter the main repository, run:
            cd #{main_repo_path}
        OUTPUT
        expect { cli.add("/test/path") }.to output(expected_output).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when running from main repository" do
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
          expected_output = /Worktree created: \/test\/path \(main\)\n\nTo enter the worktree, run:\n  cd \/test\/path/
          expect { cli.add("/test/path") }.to output(expected_output).to_stdout
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
  end

  describe "#move" do
    let(:manager) { instance_double(WorktreeManager::Manager) }
    let(:worktree1) { instance_double(WorktreeManager::Worktree, path: "/path/to/main", branch: "main") }
    let(:worktree2) { instance_double(WorktreeManager::Worktree, path: "/path/to/feature", branch: "feature") }
    let(:main_repo_path) { "/path/to/main" }

    before do
      allow(cli).to receive(:find_main_repository_path).and_return(main_repo_path)
      allow(WorktreeManager::Manager).to receive(:new).with(main_repo_path).and_return(manager)
    end

    context "when not in a git repository" do
      before do
        allow(cli).to receive(:find_main_repository_path).and_return(nil)
      end

      it "exits with error message to stderr" do
        expect { cli.move }.to output("").to_stdout
          .and output(/Error: Not in a Git repository/).to_stderr
          .and raise_error(SystemExit)
      end
    end

    context "when no worktrees exist" do
      before do
        allow(manager).to receive(:list).and_return([])
      end

      it "exits with error message to stderr" do
        expect { cli.move }.to output("").to_stdout
          .and output(/Error: No worktrees found/).to_stderr
          .and raise_error(SystemExit)
      end
    end

    context "with worktree name argument" do
      before do
        allow(manager).to receive(:list).and_return([worktree1, worktree2])
      end

      it "outputs worktree path to stdout when found by name" do
        expect { cli.move("feature") }.to output("/path/to/feature\n").to_stdout
          .and output("").to_stderr
      end

      it "outputs worktree path to stdout when found by basename" do
        expect { cli.move("main") }.to output("/path/to/main\n").to_stdout
          .and output("").to_stderr
      end

      it "exits with error when worktree not found" do
        expect { cli.move("nonexistent") }.to output("").to_stdout
          .and output(/Error: Worktree 'nonexistent' not found/).to_stderr
          .and raise_error(SystemExit)
      end
    end

    context "without argument (interactive mode)" do
      let(:prompt) { instance_double(TTY::Prompt) }
      
      before do
        allow(manager).to receive(:list).and_return([worktree1, worktree2])
        allow(cli).to receive(:interactive_mode_available?).and_return(true)
        allow(Dir).to receive(:pwd).and_return("/path/to/feature")
        allow(TTY::Prompt).to receive(:new).and_return(prompt)
      end

      it "shows interactive selection and outputs selected path" do
        expected_choices = [
          { name: "main - main", value: worktree1, hint: "/path/to/main" },
          { name: "feature - feature (current)", value: worktree2, hint: "/path/to/feature" }
        ]
        
        allow(prompt).to receive(:select).with("Select a worktree:", expected_choices, per_page: 10).and_return(worktree2)
        
        expect { cli.move }.to output("/path/to/feature\n").to_stdout
      end

      it "exits when user cancels" do
        expected_choices = [
          { name: "main - main", value: worktree1, hint: "/path/to/main" },
          { name: "feature - feature (current)", value: worktree2, hint: "/path/to/feature" }
        ]
        
        allow(prompt).to receive(:select).with("Select a worktree:", expected_choices, per_page: 10).and_raise(TTY::Reader::InputInterrupt)
        
        expect { cli.move }.to output("").to_stdout
          .and output(/Cancelled/).to_stderr
          .and raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      context "when not in TTY" do
        before do
          allow(cli).to receive(:interactive_mode_available?).and_return(false)
        end

        it "exits with error message" do
          expect { cli.move }.to output("").to_stdout
            .and output(/Error: Interactive mode requires a TTY/).to_stderr
            .and raise_error(SystemExit)
        end
      end
    end
  end

  describe "#remove" do
    let(:manager) { instance_double(WorktreeManager::Manager) }
    let(:hook_manager) { instance_double(WorktreeManager::HookManager) }
    let(:worktree) { instance_double(WorktreeManager::Worktree, path: "/test/path", branch: "feature") }

    context "when running from a worktree" do
      let(:main_repo_path) { "/path/to/main/repo" }

      before do
        allow(cli).to receive(:main_repository?).and_return(false)
        allow(cli).to receive(:find_main_repository_path).and_return(main_repo_path)
      end

      it "exits with error message and shows cd command" do
        expected_output = <<~OUTPUT
          Error: This command can only be run from the main Git repository (not from a worktree).
          To enter the main repository, run:
            cd #{main_repo_path}
        OUTPUT
        expect { cli.remove("/test/path") }.to output(expected_output).to_stdout
          .and raise_error(SystemExit)
      end
    end

    context "when running from main repository" do
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

  describe "#find_main_repository_path" do
    subject { cli.send(:find_main_repository_path) }

    context "when git rev-parse returns a .git directory" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git rev-parse --path-format=absolute --git-common-dir")
          .and_return(["/path/to/repo/.git\n", "", double(success?: true)])
      end

      it "returns the parent directory" do
        expect(subject).to eq "/path/to/repo"
      end
    end

    context "when git rev-parse returns a directory without .git suffix" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git rev-parse --path-format=absolute --git-common-dir")
          .and_return(["/path/to/repo\n", "", double(success?: true)])
        allow(File).to receive(:exist?).with("/path/to/repo/.git").and_return(true)
        allow(File).to receive(:directory?).with("/path/to/repo/.git").and_return(true)
      end

      it "returns the directory itself" do
        expect(subject).to eq "/path/to/repo"
      end
    end

    context "when git commands fail but worktree list works" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git rev-parse --path-format=absolute --git-common-dir")
          .and_return(["", "error", double(success?: false)])
        allow(Open3).to receive(:capture3)
          .with("git worktree list --porcelain")
          .and_return(["worktree /path/to/main/repo\nHEAD abcd1234\n", "", double(success?: true)])
      end

      it "returns the main worktree path" do
        expect(subject).to eq "/path/to/main/repo"
      end
    end

    context "when not in a git repository" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git rev-parse --path-format=absolute --git-common-dir")
          .and_return(["", "fatal: not a git repository", double(success?: false)])
        allow(Open3).to receive(:capture3)
          .with("git worktree list --porcelain")
          .and_return(["", "fatal: not a git repository", double(success?: false)])
      end

      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end
end