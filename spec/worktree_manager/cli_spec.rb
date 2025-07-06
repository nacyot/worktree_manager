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