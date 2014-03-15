require 'bundler/setup'

# specifically for Mocha
require 'parser/ruby18'
Parser::CurrentRuby = Parser::Ruby18

require 'method_log/repository'
require 'method_log/method_finder'
require 'method_log/source_file'

def unindent(code)
  lines = code.split($/)
  indent = lines.reject { |l| l.strip.length == 0 }.map { |l| l[/^ */].length }.min
  lines.map { |l| l.sub(Regexp.new(' ' * indent), '') }.join($/)
end

new_repository_path = File.expand_path('.git/methods.git')
Rugged::Repository.init_at(new_repository_path, :bare)
new_repository = MethodLog::Repository.new(new_repository_path)

repository_path = File.expand_path('~/Code/freerange/mocha')
repository = MethodLog::Repository.new(repository_path)
repository.commits(sorting: Rugged::SORT_TOPO | Rugged::SORT_REVERSE).each do |commit|
  puts commit.sha
  new_commit = new_repository.build_commit
  commit.source_files.each do |source_file|
    next if source_file.path[%r{^(vendor|test)}]
    begin
      method_finder = MethodLog::MethodFinder.new(source_file)
      method_finder.methods.each do |method_signature, method_definition|
        _, namespace, name = method_signature.match(/^(.*)([#.].*)$/).to_a
        path = namespace.split('::').push(name).join(File::SEPARATOR) + '.rb'
        new_commit.add(MethodLog::SourceFile.new(path: path, source: unindent(method_definition.source) + $/))
      end
    rescue Parser::SyntaxError => e
      p e
    end
  end
  new_commit.apply(user: commit.author, message: commit.message)
end
