require 'spec_helper'

RSpec.describe WorktreeManager::Worktree do
  describe '#initialize' do
    it 'accepts a hash of attributes' do
      worktree = described_class.new(path: '/path/to/worktree', branch: 'main')
      expect(worktree.path).to eq('/path/to/worktree')
      expect(worktree.branch).to eq('main')
    end

    it 'accepts a string path' do
      worktree = described_class.new('/path/to/worktree')
      expect(worktree.path).to eq('/path/to/worktree')
    end
  end

  describe '#detached?' do
    it 'returns false by default' do
      worktree = described_class.new(path: '/path')
      expect(worktree.detached?).to be false
    end

    it 'returns true when detached' do
      worktree = described_class.new(path: '/path', detached: true)
      expect(worktree.detached?).to be true
    end
  end

  describe '#bare?' do
    it 'returns false by default' do
      worktree = described_class.new(path: '/path')
      expect(worktree.bare?).to be false
    end

    it 'returns true when bare' do
      worktree = described_class.new(path: '/path', bare: true)
      expect(worktree.bare?).to be true
    end
  end

  describe '#main?' do
    it 'returns true for main branch' do
      worktree = described_class.new(path: '/path', branch: 'main')
      expect(worktree.main?).to be true
    end

    it 'returns true for master branch' do
      worktree = described_class.new(path: '/path', branch: 'master')
      expect(worktree.main?).to be true
    end

    it 'returns false for other branches' do
      worktree = described_class.new(path: '/path', branch: 'develop')
      expect(worktree.main?).to be false
    end
  end

  describe '#to_s' do
    it 'includes branch name when available' do
      worktree = described_class.new(path: '/path', branch: 'main')
      expect(worktree.to_s).to eq('/path (main)')
    end

    it 'includes head when branch is not available' do
      worktree = described_class.new(path: '/path', head: 'abc123')
      expect(worktree.to_s).to eq('/path (abc123)')
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      worktree = described_class.new(path: '/path', branch: 'main')
      expected = {
        path: '/path',
        branch: 'main',
        head: nil,
        detached: false,
        bare: false
      }
      expect(worktree.to_h).to eq(expected)
    end
  end
end
