# Appcircle React Native Unit Test Component

Run React Native unit tests with Jest.

## Required Input Variables

- `$AC_REPOSITORY_DIR`: Specifies the cloned repository directory.
- `$AC_OUTPUT_DIR`: Specify the output directory for test results.

## Optional Input Variables

- `$AC_RN_TEST_COMMAND_ARGS`: Specify additional arguments for running the Jest command. These arguments will be added to the end of the command `jest --coverage --coverageDirectory=coverage --coverageReporters=lcov` which will be used by default. You can add extra arguments, such as `--debug --colors`, without affecting the default ones. For more information, see the Jest [CLI options](https://jestjs.io/docs/cli#options).

## Output Variables

- `$AC_TEST_RESULT_PATH`: Path to the test result file.
- `$AC_COVERAGE_RESULT_PATH`: Path to the coverage result file.

## Running tests

Requires [RSpec](https://rspec.info) gem and Ruby standard library. No Gemfile or Bundler needed.

```bash
ruby test/test_main.rb
```

A pass/fail summary and a coverage report are printed at the end of each run.
