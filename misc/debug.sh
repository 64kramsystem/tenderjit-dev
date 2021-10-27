#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

c_libraries=(fiddle fisk worf odinflex)
c_help="Usage: $(basename "$0") [-h|--help] <test_file>

Args:

- 'test_file': test suite file; if no '/' is in the param, then the file is searched
  as 'test/*/\${test_file}_test.rb'; in this case, only one file must be found
"

v_test_file=

function decode_cmdline_args {
  local params
  params=$(getopt --options h --long help --name "$(basename "$0")" -- "$@")

  eval set -- "$params"

  while true; do
    case $1 in
      -h|--help)
        echo "$c_help"
        exit 0 ;;
      --)
        shift
        break ;;
    esac
  done

  if [[ $# -ne 1 ]]; then
    echo "$c_help"
    exit 1
  fi

  v_test_file=$1
}

function expand_test_file {
  if [[ $v_test_file != */* ]]; then
    local files_found
    files_found=$(find test -wholename "test/*/$v_test_file"_test.rb)

    # Impossible as of Oct/2021, but better check in case in the future tests with
    # the same name are added.
    #
    if [[ $(wc -l <<< "$files_found") != 1 ]]; then
      >&2 echo "Unexpected number of files found (1 expected): $files_found"
    fi

    v_test_file=$files_found
  fi
}

function run_debugger {
  local all_library_dirs=(lib test)

  for library in "${c_libraries[@]}"; do
    all_library_dirs+=("$(bundle exec ruby -e "print Gem::Specification.find_by_name('$library').gem_dir")/lib")
  done

  lldb -o run ruby -- -d -v -I "$(IFS=:; echo "${all_library_dirs[*]}")" "$v_test_file"
}

decode_cmdline_args "$@"
expand_test_file
run_debugger
