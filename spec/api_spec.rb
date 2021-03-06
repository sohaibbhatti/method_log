require 'spec_helper'

require 'method_log/api'
require 'method_log/source_file'
require 'method_log/repository'
require 'method_log/commit'
require 'method_log/method_definition'
require 'method_log/method_commit'

module MethodLog
  describe API do
    let(:repository_path) { File.expand_path('../repository.git', __FILE__) }

    before do
      FileUtils.mkdir_p(repository_path)
      Rugged::Repository.init_at(repository_path, :bare)
    end

    after do
      FileUtils.rm_rf(repository_path)
    end

    it 'finds class instance method in repository with two commits with single source file' do
      repository = Repository.new(repository_path)
      commit_1 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar
            # implementation 1
          end
        end
      }))
      commit_2 = repository.commit(source(path: 'foo.rb', source: %{
        # move method definition down one line
        class Foo
          def bar
            # implementation 2
          end
        end
      }))

      method_commits, method_diffs = commits_and_diffs_for('Foo#bar')

      expect(method_commits.first.sha).to eq(commit_2.sha)
      expect(method_diffs.first.to_s.chomp).to eq(unindent(%{
           def bar
        -    # implementation 1
        +    # implementation 2
           end
      }))
    end

    it 'finds significant commits for definition of method' do
      repository = Repository.new(repository_path)
      commit_1 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
        end
      }))
      commit_2 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
        end
      }))
      commit_3 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))
      commit_4 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))
      commit_5 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar
            # implementation
          end
        end
      }))

      method_commits, method_diffs = commits_and_diffs_for('Foo#bar')

      expect(method_commits.map(&:sha)).to eq([commit_5.sha, commit_3.sha])
    end

    it 'continues past lastest introduction of method if required' do
      repository = Repository.new(repository_path)
      commit_1 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))
      commit_2 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
        end
      }))
      commit_3 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))

      method_commits, method_diffs = commits_and_diffs_for('Foo#bar', stop_at_latest_introduction_of_method: false)

      expect(method_commits.map(&:sha)).to eq([commit_3.sha, commit_2.sha])
    end

    it 'continues past lastest introduction of method if required even if method not defined in latest commit' do
      repository = Repository.new(repository_path)
      commit_1 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))
      commit_2 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
        end
      }))
      commit_3 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
          def bar; end
        end
      }))
      commit_4 = repository.commit(source(path: 'foo.rb', source: %{
        class Foo
        end
      }))

      method_commits, method_diffs = commits_and_diffs_for('Foo#bar', stop_at_latest_introduction_of_method: false)

      expect(method_commits.map(&:sha)).to eq([commit_4.sha, commit_3.sha, commit_2.sha])
    end

    private

    def commits_and_diffs_for(method_identifier, options = {})
      api = API.new(Repository.new(repository_path))
      commits_and_diffs = api.diffs(method_identifier, options)
      method_commits = commits_and_diffs.map(&:first)
      method_diffs = commits_and_diffs.map(&:last)
      [method_commits, method_diffs]
    end
  end
end