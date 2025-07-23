require 'spec_helper'

RSpec.describe WorktreeManager::CLI do
  describe 'help functionality' do
    let(:help_output) { capture_stdout { WorktreeManager::CLI.start(args) } }

    context "when using 'wm help add'" do
      let(:args) { %w[help add] }

      it 'displays help for the add command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
        expect(help_output).to include('Description:')
        expect(help_output).to include('creates a new git worktree')
        expect(help_output).to include('--branch')
        expect(help_output).to include('--track')
        expect(help_output).to include('--force')
      end
    end

    context "when using 'wm add --help'" do
      let(:args) { ['add', '--help'] }

      it 'displays help for the add command instead of treating --help as an argument' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
        expect(help_output).to include('Description:')
        expect(help_output).to include('creates a new git worktree')
        expect(help_output).not_to include('Error')
        expect(help_output).not_to include('invalid reference: --help')
      end
    end

    context "when using 'wm add -h'" do
      let(:args) { ['add', '-h'] }

      it 'displays help for the add command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
      end
    end

    context "when using 'wm add -?'" do
      let(:args) { ['add', '-?'] }

      it 'displays help for the add command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
      end
    end

    context "when using 'wm add --usage'" do
      let(:args) { ['add', '--usage'] }

      it 'displays help for the add command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
      end
    end

    context "when using 'wm remove --help'" do
      let(:args) { ['remove', '--help'] }

      it 'displays help for the remove command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('remove [NAME_OR_PATH]')
        expect(help_output).to include('Remove an existing worktree')
      end
    end

    context "when using 'wm list --help'" do
      let(:args) { ['list', '--help'] }

      it 'displays help for the list command' do
        expect(help_output).to include('Usage:')
        expect(help_output).to include('list')
        expect(help_output).to include('List all worktrees')
      end
    end

    context "when using just 'wm help'" do
      let(:args) { ['help'] }

      it 'displays general help with all commands' do
        expect(help_output).to include('Commands:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
        expect(help_output).to include('remove [NAME_OR_PATH]')
        expect(help_output).to include('list')
        expect(help_output).to include('version')
      end
    end

    context "when using just 'wm --help'" do
      let(:args) { ['--help'] }

      it 'displays general help with all commands' do
        expect(help_output).to include('Commands:')
        expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
        expect(help_output).to include('remove [NAME_OR_PATH]')
      end
    end

    # Edge case tests as recommended by o3
    context 'edge cases' do
      context 'when help flag is at the end with other options' do
        let(:args) { ['add', 'foo', '--no-hooks', '-h'] }

        it 'displays help for the add command' do
          expect(help_output).to include('Usage:')
          expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
          expect(help_output).not_to include('Error')
        end
      end

      context 'when using help with unknown command' do
        let(:args) { ['foo', '--help'] }

        it 'shows error for unknown command' do
          expect { help_output }.to output(/Could not find command "foo"/).to_stderr
        end
      end

      context 'when using help command with unknown command' do
        let(:args) { %w[help foo] }

        it 'shows error for unknown command' do
          expect { help_output }.to output(/Could not find command "foo"/).to_stderr
        end
      end

      context 'when multiple help flags are provided' do
        let(:args) { ['add', '--help', '-h', '-?'] }

        it 'displays help for the add command only once' do
          expect(help_output).to include('Usage:')
          expect(help_output).to include('add NAME_OR_PATH [BRANCH]')
          # Ensure help is not duplicated
          expect(help_output.scan('Usage:').count).to eq(1)
        end
      end
    end

    private

    def capture_stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original_stdout
    end
  end
end
