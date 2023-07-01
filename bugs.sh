#!/usr/bin/env bash

# Elmer Fudd once said -- "Be vewy vewy quiet, I'm hunting bugs"

# Test files occur in local directory
QUARTER_FILE=".quarter"
TRANSITIONS_FILE=".transitions"
SCRATCH_FILE=".scratch"

if [[ -f "jira_mock" ]]; then
  JIRA_COMMAND="./jira_mock"
  SCRATCH_EDITOR="./editor_mock"
  GIT_COMMAND="./git_mock"
else
  JIRA_URL="https://github.com/ankitpokhrel/jira-cli"
  which jira > /dev/null
  success=$?
  if [[ $success != 0 ]]; then
    echo "ERROR - jira cli not found, install jira from $JIRA_URL as below";
    echo ""
    echo "Run: "
    echo "     brew tap ankitpokhrel/jira-cli"
    echo "     brew install jira-cli"
    echo "     jira init"
    echo ""
    echo "     Follow the instructions from jira init"
    echo ""
    echo "     Thank you for choosing the self-destruct sequence, have a nice day"
    exit 1
  fi
  JIRA_COMMAND="jira"
  GIT_COMMAND="git"
  SCRATCH_EDITOR=${EDITOR:-nano}
fi

# Prod mode, we look in home dir
if [[ ! -f "$QUARTER_FILE" ]]; then
  QUARTER_FILE="$HOME/.quarter"
  SCRATCH_FILE="$HOME/.scratch"
  TRANSITIONS_FILE="$HOME/.transitions"
fi


# Parse comma separated into key lookup
# eg 
# SREL-1234,ltr
# SRER-5678,taco
issues=()
shortucts=()
scratch_lines=()
scratch_id=()
scratch_memo=()
transition_ids=()
transition_stages=()

squish_string() {
  # squish $1 without dashashes, spaces, and underscores 
  str=${1// /}
  str=${str//-/}
  str=${str//_/}
  echo "$str" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

# Read file line by line
while IFS=',' read -r col1 col2; do
    issues+=("$col1")
    shortcuts+=(`squish_string "$col2"`)
done < "$QUARTER_FILE"

# Create a .transitions file if it doesn't exist
if [ ! -f "$TRANSITIONS_FILE" ]; then
  touch "$TRANSITIONS_FILE"
fi

# Read transitions file
while IFS=',' read -r key values; do
  if [[ $key ]]; then
    # values=$(echo "$values" | awk '{$1=$1};1')

    transition_ids+=("$key")
    transition_stages+=("$values")
  fi
done < $TRANSITIONS_FILE



# Create a .scratch file if it doesn't exist
if [ ! -f "$SCRATCH_FILE" ]; then
  touch "$SCRATCH_FILE"
fi

# Read scratch file by number,comment
new_scratch_id=1
line_no=1
while IFS=',' read -r col1 col2; do
    scratch_line_no+=("$line_no")
    scratch_id+=("$col1")
    scratch_memo+=("$col2")
    new_scratch_id=$(($col1+1))
    line_no=$(($line_no+1))
done < "$SCRATCH_FILE"

looks_like_jira_issue() {
  # Uppercase $1
  maybe_jira_issue=`echo $1 | tr '[:lower:]' '[:upper:]'`
  if [[ $maybe_jira_issue =~ ^[A-Z]{2,}-[0-9]{1,}$ ]]; then
    return 0
  fi
  return 1
}


get_shortcut_index() {
  squished=`squish_string "$1"`
  for i in "${!shortcuts[@]}"; do
    if [[ "${shortcuts[$i]}" = "$squished" ]]; then
      return $i
    fi
  done
  return 255
}

epic_valid() {
  for i in "${!issues[@]}"; do
    if [[ "${issues[$i]}" = "$1" ]]; then
      return 0
    fi
  done
  return 1
}

epic_from_shortcut() {
  if [[ $1 == 'scratch' ]]; then
    echo $1
    return 0
  fi

  get_shortcut_index "$1"
  index=$?
  if [[ $index == 255 ]] ; then
    epic_valid "$1"
    if [[ $? != 0 ]]; then
      return 1
    fi
    echo "$1"
    return 0
  fi
  echo "${issues[$index]}"
}

bugs_bunny() {
cat << "EOF"
               , ,
                         /| |\
                        / | | \
                        | | | |     Neeaah, Whats up Doc !?!
                        \ | | /
                         \|w|/    /
                         /_ _\   /      ,
              /\       _:()_():_       /]
              ||_     : ._=Y=_  :     / /
             [)(_\,   ',__\W/ _,'    /  \
             [) \_/\    _/'='\      /-/\)
              [_| \ \  ///  \ '._  / /
              :;   \ \///   / |  '` /
              ;::   \ `|:   : |',_.'
              """    \_|:   : |
                       |:   : |'".
                       /`._.'  \/
                      /  /|   /
                     |  \ /  /
                      '. '. /
                        '. '
                        / \ \
                       / / \'=,
                 .----' /   \ (\__
            snd (((____/     \ \  )
                              '.\_)
EOF
}

quarter() {
  cat $QUARTER_FILE 
}

epic() {
  epic=`epic_from_shortcut "$1"`
  $JIRA_COMMAND epic list "$epic" --plain --columns key,status,summary --order-by status
  if [[ $? != 0 ]]; then
    echo "Epic '$1' not found"
  fi
}

remove_line_no() {
  if [[ `uname` == 'Darwin' ]]; then
    sed -i '' "$1d" $SCRATCH_FILE
  else
    sed -i "$1d" $SCRATCH_FILE
  fi
}

remove_scratch_with_id() {
  for i in "${!scratch_id[@]}"; do
    if [[ "${scratch_id[$i]}" = "$1" ]]; then
      remove_line_no "${scratch_line_no[$i]}"
      return 0
    fi
  done
}

scratch_commands() {
  if [[ $1 == "" ]]; then
    cat $SCRATCH_FILE
  elif [[ $1 == "rm" ]]; then
    remove_scratch_with_id $2
  elif [[ $1 == "list" ]]; then
    cat $SCRATCH_FILE
  elif [[ $1 == "open" ]]; then
    $SCRATCH_EDITOR $SCRATCH_FILE
  elif [[ $1 == "add" ]]; then
    echo "$new_scratch_id,$2" >> "$SCRATCH_FILE"
  else
    echo "$new_scratch_id,$1" >> "$SCRATCH_FILE"
  fi
}

looks_like_command() {
  maybe_cmd="$1"
  cmds=("open" "close" "start" "complete"
        "cancel" "pause" "scratch" "quarter"
        "epic" "branch")
  if [[ " ${cmds[*]} " =~ " $maybe_cmd " ]]; then
    return 1
  fi
  return 0
}


bug() {
  EPIC=`epic_from_shortcut "$1"`
  success=$?
  if [[ $success != 0 ]]; then
    echo "Epic '$1' not found in $QUARTER_FILE"
    return 1
  fi
  summary="$2"
  looks_like_command "$summary"
  is_cmd=$?
  if [[ $is_cmd != 0 ]]; then
    echo "You appear to be trying to execute a command on $EPIC"
    echo " bugs expects: bugs <cmd> <EPIC> "
    return 1
  fi
  if [[ "$summary" = *[![:space:]]* ]]; then
    echo "Create bug in $EPIC"
    $JIRA_COMMAND issue create -tTask --no-input --parent "$EPIC" --summary "$summary"
  else
    echo "Please provided a title for your task"
    return 1
  fi
}


open_epic() {
  issue=`epic_from_shortcut "$1"`
  success=$?
  if [[ $success == 0 ]]; then
    $JIRA_COMMAND open $issue
  else
    echo "Epic '$1' not found in $QUARTER_FILE"
    echo "Trying as issue..."
    looks_like_jira_issue "$1"
    if [[ $? == 0 ]]; then
      $JIRA_COMMAND open $1
    else
      echo "No issue found to open"
      echo "Usage: bugs open <jira-issue>"
      return 1
    fi
  fi
}

fuzzy_issue_open() {
    issue=`epic_from_shortcut "$1"`
    success=$?
    if [[ $success != 0 ]]; then
      echo "Epic '$1' not found in $QUARTER_FILE"
    fi
    if [[ $issue == "scratch" ]]; then
      scratch_commands "list"
      exit 0
    fi
    if [[ $success != 0 ]]; then
      echo "Maybe JIRA issue?"
      looks_like_jira_issue "$1"
      if [[ $? != 0 ]]; then
        echo "Hmm '$1' also doesn't look like a JIRA issue"
        echo "Giving up..."
        return 1
      fi
      $JIRA_COMMAND open $1
    else
      epic $issue
    fi
}

branch() {
  issue=`epic_from_shortcut "$1"`
  success=$?
  if [[ $success == 0 ]]; then
    echo "Using an epic, not a JIRA issue, for branch."
    echo "Totally cool, but if its a big work item, think about"
    echo "making your own issue"
  else
    looks_like_jira_issue "$1"
    if [[ $? == 0 ]]; then
      issue=$1
    else
      echo "Not a valid JIRA issue"
      return 1
    fi
  fi
  
  branch_name=$issue
  if [[ $2 == "" ]]; then
    echo "Please give a branch name"
    echo "Usage: bugs branch <jira-issue> <branch-name>"
    return 1
  else
    whitespace_replaced=`echo $2 | sed 's/ /-/g'`
    branch_name="$branch_name/$whitespace_replaced"
  fi
  $GIT_COMMAND checkout -b "$branch_name"
  $GIT_COMMAND status
}


transition_issue() {
  issue=$1
  IFS=',' read -ra transitions_array <<< "$2"
  comment=$3
  for transition in "${transitions_array[@]}"; do
    $JIRA_COMMAND issue move $issue "$transition"
    if [[ $? != 0 ]]; then
      return 1
    fi
  done <<< "$transitions"

  if [[ $comment == "" ]]; then
    return 0
  fi

  printf '\n' | $JIRA_COMMAND issue comment add $issue "$comment"
}


get_transitions_for() {
  for i in "${!transition_ids[@]}"; do
    if [[ "${transition_ids[$i]}" = "$1" ]]; then
      echo "${transition_stages[$i]}"
      return 0
    fi
  done
}


start_issue() {
  transitions=("Ready" "Started")
  transitions=$(get_transitions_for 'start')
  transition_issue $1 "$transitions" "$2"
}

pause_issue() {
  transitions=("Cancelled" "Restarted")
  transitions=$(get_transitions_for 'pause')
  transition_issue $1 "$transitions" "$2"
}


complete_issue() {
  transitions=("Cancelled" "Restarted")
  transitions=$(get_transitions_for 'complete')
  transition_issue $1 "$transitions" "$2"
}


cancel_issue() {
  transitions=("Cancelled")
  transitions=$(get_transitions_for 'cancel')
  transition_issue $1 "$transitions" "$2"
}


best_ticket_for_folder() {
  if [[ $1 != "epic" ]]; then
    branch_name=`$GIT_COMMAND rev-parse --abbrev-ref HEAD | cut -d '/' -f1`
    looks_like_jira_issue "$branch_name"
    if [[ $? == 0 ]]; then
      echo "$branch_name"
      return 0
    fi
  fi
  folder_name=$(basename "$PWD")
  folder_name=`squish_string "$folder_name"`
  echo "$folder_name"
}


print_help() {
  echo "bugs - smarmy rabbit that helps you with JIRA"
  echo "Usages: bugs <command> <issue|epic|shortcut>"
  echo ""
  echo "  commands:"
  echo "    open - open an issue or epic"
  echo "    epic - list issues in an epic"
  echo "    branch - create a branch for an issue"
  echo "    scratch - add, remove, or list scratch notes"
  echo "    quarter - list the current quarter's epics"
  echo "    bunny - :)"
  echo "    help - this help"
  echo ""
  echo "  command shortcuts:"
  echo "    bugs - same as quarter"
  echo "    bugs <issue> - open an issue"
  echo "    bugs <epic> - list epic"
  echo "    bugs <epic> - \"foo the bar\" - create an issue under epic"
  echo "    bugs <epic> <issue> - create a bug in an epic"
  echo "    scratch - open scratch notes"
  echo "    bugs . - epic for the current folder if the repo corresponds to an epic"
  echo ""
  echo "  getting started:"
  echo "    1. Create a file called .quarter in your home directory"
  echo "    2. Add the epics you're working on this quarter"
  echo "    3. Add shortcuts to your most used epics"
  echo "    Example .quarter file:"
  echo "      SREL-1234,refactor_something"
  echo "      SREL-1235,run_ltr_experiment"
  echo "    You can now use the shortcuts anyplace you would use the Epic's JIRA number"

}


# Patch . with the current directory as if its an epic
# So if you have the current directory "search-bench" and there's an epic with
# that shortcut, then it will use that epic when you do:
#  bugs .
if [[ $2 == "." ]]; then
  # and open the epic
  prefer_epic=""
  # User explicitly wants an epic, dont use branch name
  if [[ $1 == "epic" ]]; then
    prefer_epic="epic"
  fi
  set -- $1 `best_ticket_for_folder $prefer_epic`
elif [[ $1 == "." ]]; then
  # and open the epic
  set -- `best_ticket_for_folder` "$2"
fi


# Shitty argument parsing
#  I should use getopts but I'm lazy
if [[ $1 == "bunny" ]]; then
  bugs_bunny
# Kanbanish commands
elif [[ $1 == "start" ]]; then
  start_issue "$2" "$3"
elif [[ $1 == "complete" ]]; then
  complete_issue "$2" "$3"
elif [[ $1 == "cancel" ]]; then
  cancel_issue "$2" "$3"
elif [[ $1 == "pause" ]]; then
  pause_issue "$2" "$3"
elif [[ $1 == "open" ]]; then
  open_epic "$2" "$1" "$3"
# Scratch TODO
elif [[ $1 == "scratch" ]]; then
  scratch_commands "$2" "$3"
# Current quarters
elif [[ $1 == "quarter" ]]; then
  quarter
elif [[ $1 == "epic" ]]; then
  epic "$2"
elif [[ $1 == "bug" ]]; then
  bug "$2" "$3"
elif [[ $1 == "branch" ]]; then
  branch "$2" "$3"
elif [[ $1 == "help" ]]; then
  print_help
elif [[ $1 != "" ]]; then
  if [[ $2 == "" ]]; then
    fuzzy_issue_open "$1"
  else
    bug "$1" "$2"
  fi
elif [[ $1 == "" ]]; then
  quarter
fi
