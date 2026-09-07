require 'open3'

# Optional dependency: only used for the coloured success message at the end of
# runTests. It is not always installed in a bare Ruby environment (for example
# when the unit tests require this file), so a missing gem must not break the
# load.
begin
  require 'colored'
rescue LoadError
  # 'colored' is unavailable - String#green is simply not defined.
end

def get_env_variable(key)
  return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

def env_has_key(key)
  value = get_env_variable(key)
  return value unless value.nil? || value.empty?

  abort("Input #{key} is missing.")
end

$exit_status_code = 0
def run_command(command, skip_abort)
    puts "@@[command] #{command}"
    status = nil
    stdout_str = nil
    stderr_str = nil

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
        stdout.each_line do |line|
            puts line
        end
        stdout_str = stdout.read
        stderr_str = stderr.read
        status = wait_thr.value
    end

    unless status.success?
        puts stderr_str
        unless skip_abort
            exit 1
        end
        $exit_status_code = 1
    end
end

def runTests
  
  yarn_or_npm = File.file?("#{$repo_path}/yarn.lock") ? "yarn" : "npm"
  
  report_command = "jest --coverage --coverageDirectory='coverage' --coverageReporters='lcov' #{$jest_params}"

  run_command("cd #{$repo_path} && #{yarn_or_npm} #{report_command}", true)
  run_command("cp #{$repo_path}/test-reports/*-report.xml #{$output_path}", false)
  run_command("cp -r #{$repo_path}/coverage #{$output_path}", false)

  File.open(ENV['AC_ENV_FILE_PATH'], 'a') do |f|
    f.puts "AC_TEST_RESULT_PATH=#{$output_path}"
    f.puts "AC_COVERAGE_RESULT_PATH=#{$output_path}/coverage"
  end

  puts 'Tests completed successfully.'.green
end

if __FILE__ == $PROGRAM_NAME

$output_path = env_has_key("AC_OUTPUT_DIR")
$repo_path = env_has_key("AC_REPOSITORY_DIR")
$jest_params = get_env_variable("AC_RN_TEST_COMMAND_ARGS")

runTests()
exit $exit_status_code

end # if __FILE__ == $PROGRAM_NAME