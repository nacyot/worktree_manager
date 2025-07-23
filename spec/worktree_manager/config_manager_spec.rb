require 'spec_helper'
require 'worktree_manager/config_manager'
require 'tmpdir'
require 'fileutils'

RSpec.describe WorktreeManager::ConfigManager do
  let(:test_dir) { Dir.mktmpdir }
  let(:config_manager) { described_class.new(test_dir) }

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe '#worktrees_dir' do
    context 'when no config file exists' do
      it 'returns the default value' do
        expect(config_manager.worktrees_dir).to eq('../')
      end
    end

    context 'when config file exists with worktrees_dir' do
      before do
        config_content = { 'worktrees_dir' => '../../custom-worktrees' }
        File.write(File.join(test_dir, '.worktree.yml'), config_content.to_yaml)
      end

      it 'returns the configured value' do
        expect(config_manager.worktrees_dir).to eq('../../custom-worktrees')
      end
    end

    context 'when config file exists in .git directory' do
      before do
        FileUtils.mkdir_p(File.join(test_dir, '.git'))
        config_content = { 'worktrees_dir' => '../worktrees' }
        File.write(File.join(test_dir, '.git/.worktree.yml'), config_content.to_yaml)
      end

      it 'returns the configured value' do
        expect(config_manager.worktrees_dir).to eq('../worktrees')
      end
    end

    context 'when both config files exist' do
      before do
        FileUtils.mkdir_p(File.join(test_dir, '.git'))
        config_content1 = { 'worktrees_dir' => '../priority' }
        config_content2 = { 'worktrees_dir' => '../secondary' }
        File.write(File.join(test_dir, '.worktree.yml'), config_content1.to_yaml)
        File.write(File.join(test_dir, '.git/.worktree.yml'), config_content2.to_yaml)
      end

      it 'prioritizes .worktree.yml over .git/.worktree.yml' do
        expect(config_manager.worktrees_dir).to eq('../priority')
      end
    end
  end

  describe '#hooks' do
    context 'when config file has hooks' do
      before do
        config_content = {
          'worktrees_dir' => '../',
          'hooks' => {
            'pre_add' => "echo 'pre add hook'",
            'post_add' => "echo 'post add hook'"
          }
        }
        File.write(File.join(test_dir, '.worktree.yml'), config_content.to_yaml)
      end

      it 'returns the hooks configuration' do
        hooks = config_manager.hooks
        expect(hooks).to be_a(Hash)
        expect(hooks['pre_add']).to eq("echo 'pre add hook'")
        expect(hooks['post_add']).to eq("echo 'post add hook'")
      end
    end

    context 'when no hooks are configured' do
      it 'returns an empty hash' do
        expect(config_manager.hooks).to eq({})
      end
    end
  end

  describe '#main_branch_name' do
    context 'when no config file exists' do
      it 'returns the default value' do
        expect(config_manager.main_branch_name).to eq('main')
      end
    end

    context 'when config file exists with main_branch_name' do
      before do
        config_content = { 'main_branch_name' => 'master' }
        File.write(File.join(test_dir, '.worktree.yml'), config_content.to_yaml)
      end

      it 'returns the configured value' do
        expect(config_manager.main_branch_name).to eq('master')
      end
    end

    context 'when config file exists with custom main_branch_name' do
      before do
        config_content = { 'main_branch_name' => 'development' }
        File.write(File.join(test_dir, '.worktree.yml'), config_content.to_yaml)
      end

      it 'returns the configured custom value' do
        expect(config_manager.main_branch_name).to eq('development')
      end
    end
  end

  describe '#resolve_worktree_path' do
    before do
      config_content = { 'worktrees_dir' => '../worktrees' }
      File.write(File.join(test_dir, '.worktree.yml'), config_content.to_yaml)
    end

    context 'with an absolute path' do
      it 'returns the path as is' do
        absolute_path = '/absolute/path/to/worktree'
        expect(config_manager.resolve_worktree_path(absolute_path)).to eq(absolute_path)
      end
    end

    context 'with a relative path containing /' do
      it 'resolves relative to repository path' do
        relative_path = '../custom/worktree'
        expected = File.expand_path(relative_path, test_dir)
        expect(config_manager.resolve_worktree_path(relative_path)).to eq(expected)
      end
    end

    context 'with a simple name' do
      it 'resolves relative to worktrees_dir' do
        name = 'feature-branch'
        expected = File.expand_path('../worktrees/feature-branch', test_dir)
        expect(config_manager.resolve_worktree_path(name)).to eq(expected)
      end
    end

    context 'when worktrees_dir is not configured' do
      before do
        FileUtils.rm(File.join(test_dir, '.worktree.yml'))
      end

      it 'uses default worktrees_dir' do
        name = 'my-worktree'
        expected = File.expand_path('../my-worktree', test_dir)
        expect(config_manager.resolve_worktree_path(name)).to eq(expected)
      end
    end
  end

  describe 'error handling' do
    context 'when config file has invalid YAML' do
      before do
        File.write(File.join(test_dir, '.worktree.yml'), 'invalid: yaml: content:')
      end

      it 'returns default values and prints warning' do
        expect { config_manager }.to output(/Warning: Failed to load config file/).to_stdout
        expect(config_manager.worktrees_dir).to eq('../')
        expect(config_manager.hooks).to eq({})
      end
    end
  end
end
