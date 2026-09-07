# frozen_string_literal: true

# ─── Coverage ─────────────────────────────────────────────────────────────────
COVERAGE_ENABLED = begin
  require 'coverage'
  Coverage.start
  true
rescue LoadError, StandardError
  false
end

# ─── Dependencies ─────────────────────────────────────────────────────────────
require 'rspec'
require 'rspec/core/formatters/base_formatter'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'stringio'
require 'rbconfig'
require 'English'

MAIN_RB      = File.expand_path('../main.rb', __dir__)
PROJECT_ROOT = File.dirname(MAIN_RB)

require_relative '../main.rb'

# The 'colored' gem is optional in a bare test environment. main.rb calls
# String#green on its success message, so define the colour helpers only when
# the gem is absent, keeping the suite deterministic either way.
class String
  %i[green red blue yellow cyan].each do |color|
    define_method(color) { self } unless method_defined?(color)
  end
end

# ─── Custom Formatter ─────────────────────────────────────────────────────────
class ReadableFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register(
    self,
    :example_group_started,
    :example_group_finished,
    :example_passed,
    :example_failed,
    :example_pending,
    :dump_summary
  )

  PASS  = "\e[32;1m[ PASS ]\e[0m"
  FAIL  = "\e[31;1m[ FAIL ]\e[0m"
  ERROR = "\e[31;1m[ERROR ]\e[0m"
  SKIP  = "\e[33;1m[ SKIP ]\e[0m"

  DIVIDER     = "\e[90m#{'─' * 72}\e[0m"
  DIVIDER_FAT = "\e[90m#{'═' * 72}\e[0m"

  GROUP_COLORS = [
    "\e[34;1m",  # bold blue
    "\e[35;1m",  # bold magenta
    "\e[36;1m",  # bold cyan
    "\e[33;1m"   # bold yellow
  ].freeze

  def initialize(output)
    super
    @depth    = 0
    @failures = []
    @counts   = { passed: 0, failed: 0, pending: 0 }
  end

  def example_group_started(notification)
    group = notification.group
    if group.parent_groups.size <= 1
      output.puts if @depth.zero?
      color = GROUP_COLORS[@depth % GROUP_COLORS.size]
      output.puts "  #{color}#{group.description}\e[0m"
    else
      output.puts "    #{'  ' * (@depth - 1)}\e[90m▸ \e[0m\e[37m#{group.description}\e[0m"
    end
    @depth += 1
  end

  def example_group_finished(_notification)
    @depth -= 1 if @depth.positive?
  end

  def example_passed(notification)
    @counts[:passed] += 1
    print_example(PASS, notification.example)
  end

  def example_failed(notification)
    @counts[:failed] += 1
    ex    = notification.example
    exc   = ex.execution_result.exception
    badge = exc.is_a?(RSpec::Expectations::ExpectationNotMetError) ? FAIL : ERROR
    print_example(badge, ex)
    @failures << notification
  end

  def example_pending(notification)
    @counts[:pending] += 1
    ex = notification.example
    output.puts "    #{'  ' * [0, @depth - 1].max}#{SKIP}  #{ex.description}"
  end

  def dump_summary(notification)
    output.puts
    output.puts DIVIDER_FAT

    unless @failures.empty?
      output.puts "\n  \e[1;31mFailures:\e[0m\n"
      @failures.each_with_index do |n, i|
        ex  = n.example
        exc = ex.execution_result.exception
        output.puts "  \e[1m#{i + 1}) #{ex.full_description}\e[0m"
        exc.message.lines.first(6).each do |line|
          output.puts "     \e[31m#{line.rstrip}\e[0m"
        end
        output.puts "     \e[90m# #{ex.location}\e[0m"
        output.puts
      end
      output.puts DIVIDER
    end

    t   = notification.examples.size
    p   = @counts[:passed]
    f   = @counts[:failed]
    s   = @counts[:pending]
    sec = format('%.3fs', notification.duration)

    parts = ["\e[32m#{p} passed\e[0m"]
    parts << "\e[31m#{f} failed\e[0m"  if f.positive?
    parts << "\e[33m#{s} pending\e[0m" if s.positive?

    overall = f.zero? ? "\e[32;1m✔  All #{t} tests passed\e[0m" : "\e[31;1m✖  #{f} of #{t} tests failed\e[0m"
    output.puts "\n  #{overall}"
    output.puts "  #{parts.join('  |  ')}  \e[90m(#{sec})\e[0m"
    output.puts DIVIDER_FAT
  end

  private

  def print_example(badge, example)
    indent = '  ' * [0, @depth - 1].max
    time   = format('%.3fs', example.execution_result.run_time)
    output.puts "    #{indent}#{badge}  #{example.description}  \e[90m(#{time})\e[0m"
  end
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Capture everything the block writes to stdout.
def capture_stdout
  original = $stdout
  $stdout  = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original
end

# Set an env var for the duration of the block, then restore it.
def with_env(key, value)
  had_key = ENV.key?(key)
  old     = ENV[key]
  value.nil? ? ENV.delete(key) : ENV[key] = value
  yield
ensure
  had_key ? ENV[key] = old : ENV.delete(key)
end

# Run main.rb in a subprocess with a clean environment.
# Keys left as nil are unset in the child process.
def run_main(env = {})
  clean_env = {
    'AC_OUTPUT_DIR'           => nil,
    'AC_REPOSITORY_DIR'       => nil,
    'AC_RN_TEST_COMMAND_ARGS' => nil,
    'AC_ENV_FILE_PATH'        => nil
  }.merge(env)
  Open3.capture3(clean_env, RbConfig.ruby, MAIN_RB)
end

def print_coverage_report
  return unless COVERAGE_ENABLED

  result = Coverage.result
  lines  = result[MAIN_RB] || result[File.realpath(MAIN_RB)]
  if lines.nil?
    puts "\n  Coverage: main.rb was not tracked"
    return
  end

  executable = lines.compact
  covered    = executable.count { |hits| hits.positive? }
  total      = executable.size
  percent    = total.zero? ? 0.0 : (covered * 100.0 / total)
  puts format("\n  Coverage: %d/%d executable lines in main.rb (%.1f%%)", covered, total, percent)
rescue StandardError => e
  puts "\n  Coverage: unavailable (#{e.class})"
end

# ─── Tests ────────────────────────────────────────────────────────────────────

RSpec.describe 'Required libraries' do
  %w[open3 English].each do |lib|
    it "loads '#{lib}'" do
      expect { require lib }.not_to raise_error
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#get_env_variable' do
  context 'positive paths' do
    it 'returns the value when the key is set' do
      with_env('_TEST_VAR', 'hello') { expect(get_env_variable('_TEST_VAR')).to eq('hello') }
    end

    it 'returns a whitespace-only value as-is (only "" counts as empty)' do
      with_env('_TEST_VAR', '  ') { expect(get_env_variable('_TEST_VAR')).to eq('  ') }
    end

    it 'returns a numeric-looking value as a String' do
      with_env('_TEST_VAR', '7') { expect(get_env_variable('_TEST_VAR')).to eq('7') }
    end
  end

  context 'negative paths' do
    it 'returns nil when the key is missing' do
      with_env('_TEST_VAR', nil) { expect(get_env_variable('_TEST_VAR')).to be_nil }
    end

    it 'returns nil when the value is an empty string' do
      with_env('_TEST_VAR', '') { expect(get_env_variable('_TEST_VAR')).to be_nil }
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#env_has_key' do
  context 'positive paths' do
    it 'returns the value when the key is set' do
      with_env('_TEST_VAR', '/tmp/out') { expect(env_has_key('_TEST_VAR')).to eq('/tmp/out') }
    end

    it 'returns a whitespace-only value without aborting' do
      with_env('_TEST_VAR', ' ') { expect(env_has_key('_TEST_VAR')).to eq(' ') }
    end
  end

  context 'negative paths' do
    it 'aborts when the key is missing' do
      with_env('_TEST_VAR', nil) { expect { env_has_key('_TEST_VAR') }.to raise_error(SystemExit) }
    end

    it 'aborts when the value is an empty string' do
      with_env('_TEST_VAR', '') { expect { env_has_key('_TEST_VAR') }.to raise_error(SystemExit) }
    end

    it 'exits with status 1' do
      with_env('_TEST_VAR', nil) do
        expect { env_has_key('_TEST_VAR') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end

    it 'names the missing input on stderr' do
      with_env('_TEST_VAR', nil) do
        expect { env_has_key('_TEST_VAR') }.to output(/Input _TEST_VAR is missing\./).to_stderr
      end
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#run_command' do
  # Open3.popen3 is stubbed throughout: no process is ever spawned and no
  # npm / yarn / jest binary is required to run this suite.
  let(:captured) { [] }

  def stub_popen3(success:, stderr_text: '', stdout_lines: [])
    status = double('status', success?: success)
    stdout = double('stdout')
    allow(stdout).to receive(:each_line) { |&block| stdout_lines.each { |line| block.call(line) } }
    allow(stdout).to receive(:read).and_return(stdout_lines.join)
    stderr = double('stderr', read: stderr_text)
    wait_thr = double('wait_thr', value: status)

    allow(Open3).to receive(:popen3) do |command, &block|
      captured << command
      block.call(nil, stdout, stderr, wait_thr)
    end
  end

  around do |example|
    old = $exit_status_code
    example.run
    $exit_status_code = old
  end

  context 'positive paths' do
    before { stub_popen3(success: true) }

    it 'echoes the command with the @@[command] marker' do
      expect(capture_stdout { run_command('npm test', false) }).to include('@@[command] npm test')
    end

    it 'passes the command to Open3.popen3 verbatim' do
      capture_stdout { run_command('cd /repo && yarn jest --coverage', false) }
      expect(captured).to eq(['cd /repo && yarn jest --coverage'])
    end

    it 'prints each stdout line of the child process' do
      stub_popen3(success: true, stdout_lines: ["first\n", "second\n"])
      output = capture_stdout { run_command('npm test', false) }
      expect(output).to include('first')
      expect(output).to include('second')
    end

    it 'leaves $exit_status_code untouched on success' do
      $exit_status_code = 0
      capture_stdout { run_command('npm test', false) }
      expect($exit_status_code).to eq(0)
    end

    it 'does not raise when the command succeeds and skip_abort is true' do
      expect { capture_stdout { run_command('npm test', true) } }.not_to raise_error
    end

    it 'handles an empty command string without raising' do
      expect(capture_stdout { run_command('', false) }).to include('@@[command] ')
    end
  end

  context 'negative paths' do
    before { stub_popen3(success: false, stderr_text: "jest: command not found\n") }

    it 'exits when the command fails and skip_abort is false' do
      expect { capture_stdout { run_command('npm test', false) } }.to raise_error(SystemExit)
    end

    it 'exits with status 1' do
      expect { capture_stdout { run_command('npm test', false) } }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    it 'does not exit when skip_abort is true' do
      expect { capture_stdout { run_command('npm test', true) } }.not_to raise_error
    end

    it 'sets $exit_status_code to 1 when skip_abort is true' do
      $exit_status_code = 0
      capture_stdout { run_command('npm test', true) }
      expect($exit_status_code).to eq(1)
    end

    it 'prints the captured stderr of the child process' do
      expect(capture_stdout { run_command('npm test', true) }).to include('jest: command not found')
    end

    it 'still echoes the command before failing' do
      output = ''
      begin
        output = capture_stdout { run_command('npm test', false) }
      rescue SystemExit
        nil
      end
      expect(output).to include('@@[command] npm test')
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#runTests' do
  # run_command is stubbed: the composed command strings are asserted, never
  # executed, so no npm / yarn / jest runs and nothing leaves the tmpdir.
  let(:tmpdir)   { Dir.mktmpdir('rn_unit_test') }
  let(:repo)     { File.join(tmpdir, 'repo') }
  let(:output)   { File.join(tmpdir, 'output') }
  let(:env_file) { File.join(tmpdir, 'env_file') }
  let(:commands) { [] }

  before do
    FileUtils.mkdir_p(repo)
    FileUtils.mkdir_p(output)
    allow(self).to receive(:run_command) { |command, _skip| commands << command }
    $repo_path   = repo
    $output_path = output
    $jest_params = nil
    ENV['AC_ENV_FILE_PATH'] = env_file
  end

  after do
    ENV.delete('AC_ENV_FILE_PATH')
    $repo_path = $output_path = $jest_params = nil
    FileUtils.rm_rf(tmpdir)
  end

  context 'positive paths' do
    it 'runs three commands' do
      capture_stdout { runTests }
      expect(commands.size).to eq(3)
    end

    it 'uses npm when the repository has no yarn.lock' do
      capture_stdout { runTests }
      expect(commands.first).to include("cd #{repo} && npm jest --coverage")
    end

    it 'uses yarn when the repository has a yarn.lock' do
      FileUtils.touch(File.join(repo, 'yarn.lock'))
      capture_stdout { runTests }
      expect(commands.first).to include("cd #{repo} && yarn jest --coverage")
    end

    it 'requests the lcov coverage reporter in the coverage directory' do
      capture_stdout { runTests }
      expect(commands.first).to include("--coverageDirectory='coverage'")
      expect(commands.first).to include("--coverageReporters='lcov'")
    end

    it 'appends the extra jest parameters when they are set' do
      $jest_params = '--ci --silent'
      capture_stdout { runTests }
      expect(commands.first).to end_with('--ci --silent')
    end

    it 'copies the test report xml files into the output directory' do
      capture_stdout { runTests }
      expect(commands[1]).to eq("cp #{repo}/test-reports/*-report.xml #{output}")
    end

    it 'copies the coverage directory into the output directory' do
      capture_stdout { runTests }
      expect(commands[2]).to eq("cp -r #{repo}/coverage #{output}")
    end

    it 'exports AC_TEST_RESULT_PATH to the env file' do
      capture_stdout { runTests }
      expect(File.read(env_file)).to include("AC_TEST_RESULT_PATH=#{output}")
    end

    it 'exports AC_COVERAGE_RESULT_PATH to the env file' do
      capture_stdout { runTests }
      expect(File.read(env_file)).to include("AC_COVERAGE_RESULT_PATH=#{output}/coverage")
    end

    it 'appends to an existing env file instead of truncating it' do
      File.write(env_file, "EXISTING=1\n")
      capture_stdout { runTests }
      expect(File.read(env_file)).to include('EXISTING=1')
    end

    it 'reports success on stdout' do
      expect(capture_stdout { runTests }).to include('Tests completed successfully.')
    end

    it 'allows the jest run to fail without aborting (skip_abort is true)' do
      skips = []
      allow(self).to receive(:run_command) { |command, skip| commands << command; skips << skip }
      capture_stdout { runTests }
      expect(skips).to eq([true, false, false])
    end
  end

  context 'negative paths' do
    it 'raises TypeError when AC_ENV_FILE_PATH is unset' do
      ENV.delete('AC_ENV_FILE_PATH')
      expect { capture_stdout { runTests } }.to raise_error(TypeError)
    end

    it 'raises Errno::ENOENT when AC_ENV_FILE_PATH is an empty string' do
      ENV['AC_ENV_FILE_PATH'] = ''
      expect { capture_stdout { runTests } }.to raise_error(Errno::ENOENT)
    end

    it 'raises Errno::ENOENT when AC_ENV_FILE_PATH points into a missing directory' do
      ENV['AC_ENV_FILE_PATH'] = File.join(tmpdir, 'missing', 'env_file')
      expect { capture_stdout { runTests } }.to raise_error(Errno::ENOENT)
    end

    it 'still composes the three commands before touching the env file' do
      ENV['AC_ENV_FILE_PATH'] = ''
      begin
        capture_stdout { runTests }
      rescue Errno::ENOENT
        nil
      end
      expect(commands.size).to eq(3)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe 'main.rb as a script' do
  describe 'required environment variables' do
    context 'when AC_OUTPUT_DIR is missing' do
      it 'exits with status 1' do
        _out, _err, status = run_main('AC_REPOSITORY_DIR' => '/tmp')
        expect(status.exitstatus).to eq(1)
      end

      it 'names the missing input on stderr' do
        _out, err, _status = run_main('AC_REPOSITORY_DIR' => '/tmp')
        expect(err).to include('Input AC_OUTPUT_DIR is missing.')
      end
    end

    context 'when AC_OUTPUT_DIR is empty' do
      it 'exits with status 1' do
        _out, _err, status = run_main('AC_OUTPUT_DIR' => '', 'AC_REPOSITORY_DIR' => '/tmp')
        expect(status.exitstatus).to eq(1)
      end

      it 'names the missing input on stderr' do
        _out, err, _status = run_main('AC_OUTPUT_DIR' => '', 'AC_REPOSITORY_DIR' => '/tmp')
        expect(err).to include('Input AC_OUTPUT_DIR is missing.')
      end
    end

    context 'when AC_REPOSITORY_DIR is missing' do
      it 'exits with status 1' do
        _out, _err, status = run_main('AC_OUTPUT_DIR' => '/tmp/out')
        expect(status.exitstatus).to eq(1)
      end

      it 'names the missing input on stderr' do
        _out, err, _status = run_main('AC_OUTPUT_DIR' => '/tmp/out')
        expect(err).to include('Input AC_REPOSITORY_DIR is missing.')
      end
    end

    context 'when AC_REPOSITORY_DIR is empty' do
      it 'exits with status 1' do
        _out, _err, status = run_main('AC_OUTPUT_DIR' => '/tmp/out', 'AC_REPOSITORY_DIR' => '')
        expect(status.exitstatus).to eq(1)
      end

      it 'names the missing input on stderr' do
        _out, err, _status = run_main('AC_OUTPUT_DIR' => '/tmp/out', 'AC_REPOSITORY_DIR' => '')
        expect(err).to include('Input AC_REPOSITORY_DIR is missing.')
      end
    end

    it 'validates AC_OUTPUT_DIR before AC_REPOSITORY_DIR' do
      _out, err, _status = run_main
      expect(err).to include('Input AC_OUTPUT_DIR is missing.')
      expect(err).not_to include('Input AC_REPOSITORY_DIR is missing.')
    end

    it 'never reaches the jest command while a required input is missing' do
      out, _err, _status = run_main
      expect(out).not_to include('@@[command]')
    end
  end

  describe 'loading main.rb as a library' do
    it 'does not execute the script body when required' do
      out, _err, status = Open3.capture3(
        { 'AC_OUTPUT_DIR' => nil, 'AC_REPOSITORY_DIR' => nil },
        RbConfig.ruby, '-e', "require '#{MAIN_RB}'; puts 'loaded'"
      )
      expect(status.exitstatus).to eq(0)
      expect(out).to include('loaded')
    end

    it 'does not run any command when required' do
      out, _err, _status = Open3.capture3(
        { 'AC_OUTPUT_DIR' => nil, 'AC_REPOSITORY_DIR' => nil },
        RbConfig.ruby, '-e', "require '#{MAIN_RB}'; puts 'loaded'"
      )
      expect(out).not_to include('@@[command]')
    end

    it 'defines the helper functions when required' do
      out, _err, _status = Open3.capture3(
        RbConfig.ruby, '-e',
        "require '#{MAIN_RB}'; puts %w[get_env_variable env_has_key run_command runTests].all? { |m| respond_to?(m, true) }"
      )
      expect(out).to include('true')
    end
  end
end

# ─── Runner ───────────────────────────────────────────────────────────────────
if __FILE__ == $PROGRAM_NAME
  RSpec.configure do |config|
    config.add_formatter ReadableFormatter
    config.color = true
    config.order = :defined
    config.mock_with :rspec do |mocks|
      mocks.verify_partial_doubles = false
    end
  end

  status = RSpec::Core::Runner.run(['--order', 'defined'])
  print_coverage_report
  exit status
end
