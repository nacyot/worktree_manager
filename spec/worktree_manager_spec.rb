require "spec_helper"

RSpec.describe WorktreeManager do
  it "has a version number" do
    expect(WorktreeManager::VERSION).not_to be nil
  end

  describe ".new" do
    it "creates a new manager instance" do
      manager = WorktreeManager.new
      expect(manager).to be_a(WorktreeManager::Manager)
    end
  end
end