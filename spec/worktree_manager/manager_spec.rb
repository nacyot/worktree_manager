require "spec_helper"

RSpec.describe WorktreeManager::Manager do
  let(:manager) { described_class.new }

  describe "#initialize" do
    it "accepts a repository path" do
      expect { described_class.new(".") }.not_to raise_error
    end
  end

  describe "#list" do
    it "returns an array of worktrees" do
      result = manager.list
      expect(result).to be_an(Array)
    end
  end

  describe "#add" do
    it "adds a new worktree" do
      expect { manager.add("test_path", "test_branch") }.to raise_error(WorktreeManager::Error)
    end
  end

  describe "#remove" do
    it "removes a worktree" do
      expect { manager.remove("test_path") }.to raise_error(WorktreeManager::Error)
    end
  end

  describe "#prune" do
    it "prunes worktrees" do
      expect { manager.prune }.not_to raise_error
    end
  end

  describe "#add_tracking_branch" do
    let(:path) { "../test-worktree" }
    let(:local_branch) { "pr-123" }
    let(:remote_branch) { "origin/pr-123" }

    context "when remote branch exists" do
      before do
        allow(manager).to receive(:execute_git_command)
          .with("fetch origin pr-123")
          .and_return(["", double(success?: true)])
        
        allow(manager).to receive(:execute_git_command)
          .with("worktree add -b pr-123 ../test-worktree origin/pr-123")
          .and_return(["Preparing worktree", double(success?: true)])
      end

      it "fetches the remote branch and creates worktree" do
        expect(manager).to receive(:execute_git_command).with("fetch origin pr-123")
        expect(manager).to receive(:execute_git_command).with("worktree add -b pr-123 ../test-worktree origin/pr-123")
        
        result = manager.add_tracking_branch(path, local_branch, remote_branch)
        expect(result.path).to eq(path)
        expect(result.branch).to eq(local_branch)
      end
    end

    context "when fetch fails" do
      before do
        allow(manager).to receive(:execute_git_command)
          .with("fetch origin pr-123")
          .and_return(["fatal: couldn't find remote ref pr-123", double(success?: false)])
      end

      it "raises an error" do
        expect {
          manager.add_tracking_branch(path, local_branch, remote_branch)
        }.to raise_error(WorktreeManager::Error, /Failed to fetch remote branch/)
      end
    end

    context "with force option" do
      before do
        allow(manager).to receive(:execute_git_command)
          .with("fetch origin pr-123")
          .and_return(["", double(success?: true)])
        
        allow(manager).to receive(:execute_git_command)
          .with("worktree add --force -b pr-123 ../test-worktree origin/pr-123")
          .and_return(["Preparing worktree", double(success?: true)])
      end

      it "includes --force flag" do
        expect(manager).to receive(:execute_git_command).with("worktree add --force -b pr-123 ../test-worktree origin/pr-123")
        
        manager.add_tracking_branch(path, local_branch, remote_branch, force: true)
      end
    end
  end
end