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
end