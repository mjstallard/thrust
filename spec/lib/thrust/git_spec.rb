require 'spec_helper'

describe Thrust::Git do
  let(:out) { StringIO.new }
  let(:thrust_executor) { Thrust::Executor.new }

  subject { Thrust::Git.new(out, thrust_executor) }

  describe '#ensure_clean' do
    it 'makes sure that the working directory is clean' do
      expect(thrust_executor).to receive(:system_or_exit).with('git diff-index --quiet HEAD')
      subject.ensure_clean
    end

    context 'when IGNORE GIT is set' do
      before { ENV['IGNORE_GIT'] = 'yep' }
      after { ENV.delete('IGNORE_GIT') }

      it 'prints a warning message' do
        subject.ensure_clean
        expect(out.string).to include 'WARNING NOT CHECKING FOR CLEAN WORKING DIRECTORY'
      end

      it "doesn't check if the working directory is clean" do
        expect(thrust_executor).to_not receive(:system_or_exit).with('git diff-index --quiet HEAD')
        subject.ensure_clean
      end
    end
  end

  describe '#checkout_tag' do
    it 'should checkout the latest commit that has the tag' do
      expect(thrust_executor).to receive(:capture_output_from_system).with('autotag list ci').and_return("7342334 ref/blah\nlatest_ci_tag ref/blahblah")
      expect(thrust_executor).to receive(:system_or_exit).with('git checkout latest_ci_tag')

      subject.checkout_tag('ci')
    end
  end

  describe '#commit_summary_for_last_deploy' do
    context 'when the target has been deployed previously' do
      it 'uses the commit message from that commit' do
        expect(thrust_executor).to receive(:capture_output_from_system).with('autotag list staging').and_return("7342334 ref/blah\nlatest_deployed_commit ref/blahblah")
        expect(thrust_executor).to receive(:capture_output_from_system).with("git log --oneline -n 1 latest_deployed_commit").and_return('summary')

        summary = subject.commit_summary_for_last_deploy('staging')
        expect(summary).to include('summary')
      end
    end

    context 'when the target has not been deployed' do
      it 'says that the target has not been deployed' do
        expect(thrust_executor).to receive(:capture_output_from_system).with('autotag list staging').and_return("\n")
        summary = subject.commit_summary_for_last_deploy('staging')
        expect(summary).to include('Never deployed')
      end
    end
  end

  describe '#generate_notes_for_deployment' do
    let(:temp_file) { File.new('notes', 'w+') }

    before do
      allow(Tempfile).to receive(:new).and_return(temp_file)
    end

    it 'generates deployment notes from the commit log history' do
      expect(thrust_executor).to receive(:capture_output_from_system).with('git rev-parse HEAD').and_return("latest_commit\n")
      expect(thrust_executor).to receive(:capture_output_from_system).with('autotag list staging').and_return("7342334 ref/blah\nlatest_deployed_commit")
      expect(thrust_executor).to receive(:system_or_exit).with('git log --oneline latest_deployed_commit...latest_commit', temp_file.path)

      notes = subject.generate_notes_for_deployment('staging')
      expect(notes).to eq(temp_file.path)
    end

    context 'when there are no previously deployed commits' do
      it 'returns the commit message of just the latest commit' do
        expect(thrust_executor).to receive(:capture_output_from_system).with('git rev-parse HEAD').and_return("latest_commit\n")
        expect(thrust_executor).to receive(:capture_output_from_system).with('autotag list staging').and_return("\n")
        expect(thrust_executor).to receive(:capture_output_from_system).with("git log --oneline -n 1 latest_commit").and_return('summary')

        notes = subject.generate_notes_for_deployment('staging')
        expect(notes).to eq(temp_file.path)

        file = File.open(temp_file.path)
        expect(file.read).to include('summary')
      end
    end
  end
end
