#!/usr/bin/env bash

## Put test fixtures locally

fixtures() {
    current_dir=`basename "$PWD"`
    with_underscores_current_dir=$(echo "$current_dir" | sed 's/[[:alnum:]]/&_/') 
    cp test/command_mock.sh jira_mock
    cp test/command_mock.sh editor_mock
    cp test/command_mock.sh git_mock
    echo "TEST-1234,proj1" >> .quarter
    echo "TEST-1235,proj2" >> .quarter
    echo "TEST-1236,$current_dir" >> .quarter
    echo "TEST-1236,$with_underscores_current_dir" >> .quarter
    echo "TEST-1237,with_underscores" >> .quarter
    echo "1,idea 1" >> .scratch
    echo "2,idea 2" >> .scratch
    
    # Kanban transitions
    echo "start,start1,start 2" >> .transitions
    echo "complete,Complete 1,Complete 2" >> .transitions
    echo "pause,pause1,pause2" >> .transitions
    echo "cancel,killitwithfire" >> .transitions

    touch .last_jira_mock_args
    touch .last_editor_mock_args
    touch .last_git_mock_args
}

clean_fixtures() {
    rm -f ./jira_mock
    rm -f ./editor_mock
    rm -f ./git_mock
    rm -f ./.quarter
    rm -f ./.transitions
    rm -f ./.scratch
    rm -f ./.last_jira_mock_args
    rm -f ./.last_git_mock_args
    rm -f ./.last_editor_mock_args
}


assert_cmd_called_with() {
    cat ./.last_"$1"_args | grep -q "$2"
    grep_result=$?
    if [ $grep_result -ne 0 ]; then
        echo "************************************"
        echo "Expected $1 to be called with '$2'"
        actual_output=`cat ./.last_$1_args`
        echo "But got '$actual_output'"
        return 1
    fi
}

assert_jira_called_with() {
    assert_cmd_called_with "jira_mock" "$1"
}

assert_editor_called_with() {
    assert_cmd_called_with "editor_mock" "$1"
}

assert_git_called_with() {
    assert_cmd_called_with "git_mock" "$1"
}



test_just_bugs_echos_quarter() {
    quarter_file=`cat .quarter`
    bugs_output=`./bugs.sh` > /dev/null
    # Ensure all of quarter_file within stdout
    echo "$bugs_output" | grep -q "$quarter_file"
    return $?
}

#####
# Scratch tests

test_scratch_add() {
    ./bugs.sh scratch add "idea 3"
    cat .scratch | grep -q "3,idea 3"
    return $?
}

test_bare_scratch_add() {
    ./bugs.sh scratch "idea 3"
    cat .scratch | grep -q "3,idea 3"
    return $?
}

test_scratch_list() {
    scratch_file=`cat .scratch`
    scratch_output=`./bugs.sh scratch list`
    echo "$scratch_output" | grep -q "$scratch_file"
}

test_scratch_bare_list() {
    scratch_file=`cat .scratch`
    scratch_output=`./bugs.sh scratch`
    echo "$scratch_output" | grep -q "$scratch_file"
}

test_scratch_edit() {
    scratch_file=`cat .scratch`
    scratch_output=`./bugs.sh scratch list`
    echo "$scratch_output" | grep -q "$scratch_file"
}

test_rm_scratch() {
    ./bugs.sh scratch rm 1
    cat .scratch | grep -q "2,idea 2"
    grep_result=$?
    if [ $grep_result -ne 0 ]; then
        return 1
    fi
    cat .scratch | grep -q "1,idea 1"
    grep_result=$?
    if [ $grep_result -eq 0 ]; then
        return 1
    fi
}

test_rm_scratch_not_aligned_to_line-nos() {
    rm .scratch
    echo "1,idea 1" >> .scratch
    echo "3,idea 3" >> .scratch
    echo "5,idea 5" >> .scratch

    ./bugs.sh scratch rm 3
    # We should still have 1 and 5
    cat .scratch | grep -q "1,idea 1"
    grep_result=$?
    if [ $grep_result -ne 0 ]; then
        return 1
    fi
    cat .scratch | grep -q "5,idea 5"
    grep_result=$?
    if [ $grep_result -ne 0 ]; then
        return 1
    fi
    cat .scratch | grep -q "3,idea 3"
    grep_result=$?
    if [ $grep_result -eq 0 ]; then
        return 1
    fi
}

#### 
# Git tests
test_branch() {
    ./bugs.sh branch "TEST-111" foo > /dev/null
    assert_git_called_with "^checkout -b TEST-111/foo"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    assert_git_called_with "status"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    return $?
}

test_branch_whitespace() {
    ./bugs.sh branch "TEST-111" "foo bar" > /dev/null
    assert_git_called_with "^checkout -b TEST-111/foo-bar"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    assert_git_called_with "status"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    return $?
}


test_branch_no_message() {
    ./bugs.sh branch "TEST-111" > /dev/null
    assert_git_called_with "^checkout -b TEST-111$"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    assert_git_called_with "status"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    return $?
}


test_branch_fails_for_epic() {
    ./bugs.sh branch "TEST-1234" foo > /dev/null
    num_git_commands=`wc -l < ./.last_git_mock_args | tr -d ' '`
    if [[ "$num_git_commands" != "0" ]]; then
        return 1
    fi
}

#### 
# Jira tests

test_view_epic() {
  ./bugs.sh TEST-1234 > /dev/null
  assert_jira_called_with "^epic list TEST-1234"
  return $?
}

test_view_epic_shortcut() {
  ./bugs.sh proj1 > /dev/null
  assert_jira_called_with "^epic list TEST-1234"
  return $?
}

test_view_epic_local_dir() {
  ./bugs.sh . > /dev/null

  assert_jira_called_with "^epic list TEST-1236"
  return $?
}

test_view_epic_local_dir_git_branch() {
  rev_parse_response='if [[ "$1" == "rev-parse" ]]; then
    echo "TEST-9999/foo"
  fi'
  echo "$rev_parse_response" >> ./git_mock
  ./bugs.sh . 
  assert_jira_called_with "^open TEST-9999"
  return $?
}

test_explicit_epic_in_git_branch_prefers_folder_name() {
  rev_parse_response='if [[ "$@" == "rev-parse --abbrev-ref HEAD" ]]; then
    echo "TEST-9999/foo"
  fi'
  echo "$rev_parse_response" >> ./git_mock
  ./bugs.sh epic . > /dev/null
  assert_jira_called_with "^epic list TEST-1236"
  return $?
}

test_view_epic_local_dir_git_branch_no_path() {
  rev_parse_response='if [[ "$@" == "rev-parse --abbrev-ref HEAD" ]]; then
    echo "TEST-9999"
  fi'
  echo "$rev_parse_response" >> ./git_mock
  ./bugs.sh . > /dev/null
  assert_jira_called_with "^open TEST-9999"
  return $?
}

test_view_epic_local_dir_git_branch_no_path() {
  rev_parse_response='if [[ "$@" == "rev-parse --abbrev-ref HEAD" ]]; then
    echo "not-a-jira-ticket/foo/bar"
  fi'
  echo "$rev_parse_response" >> ./git_mock
  ./bugs.sh . > /dev/null
  assert_jira_called_with "^epic list TEST-1236"
  return $?
}

test_view_non_epic() {
  ./bugs.sh TEST-5678 > /dev/null
  assert_jira_called_with "^open TEST-5678"
  return $?
}

test_open_epic() {
  ./bugs.sh open TEST-1234 > /dev/null
  assert_jira_called_with "^open TEST-1234"
  return $?
}

test_open_non_epic() {
  ./bugs.sh open TEST-5678 > /dev/null
  assert_jira_called_with "^open TEST-5678"
  return $?
}


test_open_epic_shortcut() {
  ./bugs.sh open proj1 > /dev/null
  assert_jira_called_with "^open TEST-1234"
  return $?
}

test_open_epic_shortcut_has_underscores() {
  ./bugs.sh open with_underscores > /dev/null
  assert_jira_called_with "^open TEST-1237"
  return $?
}

test_open_epic_local_dir() {
  ./bugs.sh open . >  /dev/null 
  assert_jira_called_with "^open TEST-1236"
  return $?
}

test_make_new_bug() {
  ./bugs.sh proj1 "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --parent TEST-1234 --summary Do the thing'
  return $?
}

# Kanban transitions

test_kanban_start() {
  ./bugs.sh start TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'
  assert_jira_called_with '^issue move TEST-1234 start 2'
  return $?
}

test_kanban_cancel() {
  ./bugs.sh cancel TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 killitwithfire'
  return $?
}

test_kanban_pause() {
  ./bugs.sh pause TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 pause1'
  assert_jira_called_with '^issue move TEST-1234 pause2'
  return $?
}

test_kanban_complete() {
  ./bugs.sh complete TEST-1234
  assert_jira_called_with '^issue move TEST-1234 Complete 1'
  assert_jira_called_with '^issue move TEST-1234 Complete 2'
  return $?
}

test_no_kanban_transitions() {
  rm .transitions
  ./bugs.sh complete TEST-1234 > /dev/null
}


###########################################
# Run all functions that start with "test_"
functions=$(declare -F | grep "^declare -f test_")
TESTS=()
while read -r line; do
    function_name=${line#"declare -f "}
    TESTS+=("$function_name")
done <<< "$functions"

if [ $# -gt 0 ]; then
  TESTS=("$@")
fi

for test in ${TESTS[@]}; do
  fixtures
  $test
  success=$?
  clean_fixtures
  if [ $success -ne 0 ]; then
    echo "$test failed"
    echo "❌ $test"
    echo "DONE... cleaning up"
    exit 1
  fi
  echo "✅ $test"
done
