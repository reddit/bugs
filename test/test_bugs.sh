#!/usr/bin/env bash

trim() {
    local var=$1
    var="${var#"${var%%[![:space:]]*}"}"   # Remove leading whitespace
    var="${var%"${var##*[![:space:]]}"}"   # Remove trailing whitespace
    echo -n "$var"
}

num_lines() {
  if [[ -f "$1" ]]; then
    file_wc=$(cat "$1" | wc -l)
    echo $(trim "$file_wc")
  else
    echo 0
  fi
}

fixtures() {
  ## Put test fixtures locally
    current_dir=`basename "$PWD"`
    with_underscores_current_dir=$(echo "$current_dir" | sed 's/[[:alnum:]]/&_/') 
    cp test/command_mock.sh jira_mock
    cp test/command_mock.sh editor_mock
    cp test/command_mock.sh git_mock
    cp test/command_mock.sh jq_mock
    cp test/command_mock.sh curl_mock

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
    echo "block,panic" >> .transitions

    # .netrc file
    echo "machine example.jira.com" >> .netrc
    echo "login bugs" >> .netrc
    echo "password bugs" >> .netrc
    
    # How epics are displayed
    echo "epic_display_fields=summary,description" >> .display
    echo "epic_display_columns=key,priority,summary" >> .display
    echo "epic_display_orderby=priority" >> .display


    touch .last_jira_mock_args
    touch .last_editor_mock_args
    touch .last_git_mock_args
}

clean_fixtures() {
    rm -f ./jira_mock
    rm -f ./editor_mock
    rm -f ./git_mock
    rm -f ./.netrc
    rm -f ./.quarter
    rm -f ./.transitions
    rm -f ./.scratch
    rm -f ./.display
    rm -f ./.last_jira_mock_args
    rm -f ./.last_git_mock_args
    rm -f ./.last_editor_mock_args
    rm -f ./.last_curl_mock_args
    rm -f ./.last_jq_mock_args
    rm -f ./test_in.txt 2> /dev/null
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

assert_curl_called_with() {
    assert_cmd_called_with "curl_mock" "$1"
}

assert_jq_called_with() {
    assert_cmd_called_with "jq_mock" "$1"
}

####
# Just auth
test_auth_setup() {
    rm ./.netrc
    echo "jira.hostname" >> test_in.txt
    echo "jira.user@jira.net" >> test_in.txt
    echo "password" >> test_in.txt
    ./bugs.sh < test_in.txt > /dev/null
    cat ./.netrc | grep -q "jira.hostname"
    return $?
}

####
# Just bugs / quearter

test_just_bugs_echos_quarter() {
    quarter_file=`cat .quarter`
    bugs_output=`./bugs.sh` > /dev/null
    # Ensure all of quarter_file within stdout
    echo "$bugs_output" | grep -q "$quarter_file"
    return $?
}

test_bugs_reset_quarter() {
    echo "TEST-1234" >> test_in.txt
    echo "proj1" >> test_in.txt
    echo "n" >> test_in.txt
    bugs_output=`./bugs.sh reset < test_in.txt`
    rm test_in.txt 2> /dev/null
    cat .quarter | grep -q "TEST-1234,proj1"
    return $?
}

test_bugs_reset_quarter_loop() {
    echo "TEST-1234" >> test_in.txt
    echo "proj1" >> test_in.txt
    echo "y" >> test_in.txt
    echo "TEST-1235" >> test_in.txt
    echo "proj2" >> test_in.txt
    echo "n" >> test_in.txt
    bugs_output=`./bugs.sh reset < test_in.txt`
    rm test_in.txt 2> /dev/null
    cat .quarter | grep -q "TEST-1234,proj1"
    success=$?
    if [ $success -ne 0 ]; then
        return $success
    fi
    cat .quarter | grep -q "TEST-1235,proj2"
    return $?
}

test_bugs_no_quarter_resets() {
    rm .quarter
    echo "TEST-1234" >> test_in.txt
    echo "proj1" >> test_in.txt
    echo "n" >> test_in.txt
    bugs_output=`./bugs.sh < test_in.txt`
    cat .quarter | grep -q "TEST-1234,proj1"
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


test_branch_slugify() {
    ./bugs.sh branch "TEST-111" "FOO. bar" > /dev/null
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
    success=$?
    if [ $success -eq 0 ]; then
        return 1
    fi
    return 0
}


test_branch_uses_an_epic() {
    ./bugs.sh branch "TEST-1234" foo > /dev/null
    assert_git_called_with "^checkout -b TEST-1234/foo"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    assert_git_called_with "status"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
}

test_branch_uses_epic_shortcut() {
    ./bugs.sh branch "proj1" foo > /dev/null
    assert_git_called_with "^checkout -b TEST-1234/foo"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
    assert_git_called_with "status"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
}


test_branch_prints_name() {
    ./bugs.sh branch "TEST-1234" foo > /dev/null
    assert_jira_called_with "issue view TEST-1234 --plain --comments 0"
    success=$?
    if [ $success -ne 0 ]; then
        return 1
    fi
}

test_git_branch_with_switch_assigns_short() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock
  ./bugs.sh branch "TEST-1234" -t > /dev/null
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
  return $success && $?
}

test_git_branch_with_switch_assigns_short_prepend() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock
  ./bugs.sh branch "-t" "TEST-1234" > /dev/null
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
  return $success && $?
}

test_git_branch_with_switch_assigns_long_prepend() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock
  ./bugs.sh branch --take "TEST-1234" > /dev/null
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
  return $success && $?
}


test_git_branch_with_switch_starts_short_prepend() {
  ./bugs.sh branch "-s" "TEST-1234" > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'; success=$?
  if [ $success -ne 0 ]; then
    return $success
  fi
  assert_jira_called_with '^issue move TEST-1234 start 2'; success=$?
  return $?
}

test_git_branch_with_switch_can_start_and_take() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock
  
  ./bugs.sh branch "-t -s" "TEST-1234" > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'; success=$?
  if [ $success -ne 0 ]; then
    return $success
  fi
  assert_jira_called_with '^issue move TEST-1234 start 2'; success=$?
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
}

test_git_branch_with_switch_can_start_and_take_duplicated() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock
  
  ./bugs.sh branch "-tst" "TEST-1234" > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'; success=$?
  if [ $success -ne 0 ]; then
    return $success
  fi
  assert_jira_called_with '^issue move TEST-1234 start 2'; success=$?
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
}

#### 
# Jira tests

test_view_epic() {
  ./bugs.sh TEST-1234 > /dev/null
  assert_jira_called_with "^epic list TEST-1234"
  return $?
}


test_view_epic_uses_configed_display_fields() {
  ./bugs.sh TEST-1234 > /dev/null
  assert_curl_called_with "^-s -u bugs:bugs -X GET -H Content-Type: application/json https://example.jira.com/rest/api/2/issue/TEST-1234?fields=summary,description"
  return $?
}

test_view_epic_uses_configed_columns() {
  ./bugs.sh TEST-1234 > /dev/null
  assert_jira_called_with "\-\-columns key,priority,summary"
  return $?
}

test_view_epic_uses_configed_orderby() {
  ./bugs.sh TEST-1234 > /dev/null
  assert_jira_called_with "\-\-order-by priority"
  return $?
}

test_view_epic_no_config() {
  rm .display
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
  ./bugs.sh . > /dev/null
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
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1234 --summary Do the thing'
  return $?
}

test_make_new_bug_explicit_command() {
  ./bugs.sh create proj1 "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1234 --summary Do the thing'
  return $?
}

test_make_new_bug_epic_shortcut() {
  ./bugs.sh . "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1236 --summary Do the thing'
  return $?
}

test_make_new_bug_explicit_command_epic_shortcut() {
  ./bugs.sh create . "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1236 --summary Do the thing'
  return $?
}

test_make_new_bug_uses_folder_shortcut_on_branch() {
  rev_parse_response='if [[ "$@" == "rev-parse --abbrev-ref HEAD" ]]; then
    echo "TEST-9999/foo"
  fi'
  echo "$rev_parse_response" >> ./git_mock
  ./bugs.sh . "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1236 --summary Do the thing'
  return $?
}

test_make_new_bug_empty_fails() {
  ./bugs.sh proj1 " " > /dev/null
  num_jira_commands=$(num_lines ./.last_jira_mock_args)
  if [ $num_jira_commands -ne 0 ]; then
    cat ./.last_jira_mock_args
    return 1
  fi
  return 0
}

test_make_new_bug_with_command_summary_fails() {
  ./bugs.sh proj1 "open" > /dev/null
  num_jira_commands=$(num_lines ./.last_jira_mock_args)
  if [ $num_jira_commands -ne 0 ]; then
    cat ./.last_jira_mock_args
    return 1
  fi
  return 0
}

test_make_new_bug_with_command_summary_start_ok() {
  ./bugs.sh proj1 "open the pod bay doors hal" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1234 --summary open the pod bay doors hal'
  return $?
}

test_make_new_bug_with_directory_shortcut() {
  ./bugs.sh . "Do the thing" > /dev/null
  assert_jira_called_with '^issue create -tTask --no-input --parent TEST-1236 --summary Do the thing'
  return $?
}

test_no_new_bug_created_with_unexpected_cmd() {
  ./bugs.sh foo "Do the thing" > /dev/null
  cat .last_jira_mock_args
  num_jira_commands=$(num_lines .last_jira_mock_args)
  if [ $num_jira_commands -ne 0 ]; then
    echo "Expected no jira commands to be called, received: $num_jira_commands cmds"
    return 1
  fi
}

# Kanban transitions

test_kanban_start() {
  ./bugs.sh start TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'; success=$?
  if [ $success -ne 0 ]; then
    return $success
  fi
  assert_jira_called_with '^issue move TEST-1234 start 2'; success=$?
  num_jira_commands=$(num_lines .last_jira_mock_args)
  if [ $num_jira_commands -ne 3 ]; then
    return 1
  fi
  return $success
}


test_kanban_start_views_issue() {
  ./bugs.sh start TEST-1234 > /dev/null
  assert_jira_called_with "^issue view TEST-1234 --plain --comments 0"
  return $?
}


test_kanban_start_with_comment() {
  ./bugs.sh start TEST-1234 "Started" > /dev/null
  assert_jira_called_with '^issue move TEST-1234 start1'
  assert_jira_called_with '^issue move TEST-1234 start 2'
  assert_jira_called_with '^issue comment add TEST-1234 Started'
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
  ./bugs.sh complete TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 Complete 1'
  assert_jira_called_with '^issue move TEST-1234 Complete 2'
  return $?
}

test_kanban_block() {
  ./bugs.sh block TEST-1234 > /dev/null
  assert_jira_called_with '^issue move TEST-1234 panic'
  return $?
}

test_no_kanban_transitions() {
  rm .transitions
  ./bugs.sh complete TEST-1234 > /dev/null
}

test_take() {
  jira_me_response='if [[ "$1" == "me" ]]; then
    echo "bill.gates@microsoft.com"
  fi'
  echo "$jira_me_response" >> ./jira_mock

  ./bugs.sh take TEST-1234 > /dev/null
  assert_jira_called_with '^me'; success=$?
  assert_jira_called_with '^issue assign TEST-1234 bill.gates@microsoft.com'
  return $success && $?
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
