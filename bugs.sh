#!/usr/bin/env bash

# Elmer Fudd once said -- "Be vewy vewy quiet, I'm hunting bugs"

# PART ONE SETUP
#   Setting up the environment, parsing the following files
#
# Test files occur in local directory
QUARTER_FILE=".quarter"
TRANSITIONS_FILE=".transitions"
SCRATCH_FILE=".scratch"
NET_RC_FILE=".netrc"
DISPLAY_CONFIG_FILE=".display"

if [[ -f "jira_mock" ]]; then
  JIRA_COMMAND="./jira_mock"
  SCRATCH_EDITOR="./editor_mock"
  GIT_COMMAND="./git_mock"
  JQ_COMMAND="./jq_mock"
  CURL_COMMAND="./curl_mock"
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
  JQ_COMMAND="jq"
  CURL_COMMAND="curl"
fi

# Prod mode, we look in home dir
if [[ ! -f "jira_mock" ]]; then
  QUARTER_FILE="$HOME/.bugs/quarter"
  SCRATCH_FILE="$HOME/.bugs/scratch"
  TRANSITIONS_FILE="$HOME/.bugs/transitions"
  DISPLAY_CONFIG_FILE="$HOME/.bugs/display"
  NET_RC_FILE="$HOME/.netrc"
fi

# No quarter file? Change to reset
if [[ ! -f "$QUARTER_FILE" ]]; then
  set -- "reset"
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
mkdir -p "$HOME/.bugs"
# Read file line by line

if [ -f "$QUARTER_FILE" ]; then
  while IFS=',' read -r col1 col2; do
      issues+=("$col1")
      shortcuts+=(`squish_string "$col2"`)
  done < "$QUARTER_FILE"
fi

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

JIRA_HOST=
JIRA_USER=
JIRA_PASS=

parse_net_rc() {
  # Parse the .netrc file
  if [[ ! -f "$NET_RC_FILE" ]]; then
    echo "Must be your first time..."
    echo "Lets setup your Jira credentials to use bugs"
    echo ""
    echo "Enter jira host (eg jira.example.com): "
    read JIRA_HOST
    echo "Enter jira username (eg bill.gates@microsoft.com): "
    read JIRA_USER
    echo "Enter jira api token: "
    echo "See: https://id.atlassian.com/manage-profile/security/api-tokens"
    read JIRA_PASS
    echo "machine $JIRA_HOST" > "$NET_RC_FILE"
    echo "  login $JIRA_USER" >> "$NET_RC_FILE"
    echo "  password $JIRA_PASS" >> "$NET_RC_FILE"
    chmod 600 "$NET_RC_FILE"
    return
  fi
  while read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^([[:space:]]*#.*)?$ ]]; then
      continue
    fi

    # Extract machine, login, and password properties
    if [[ "$line" =~ ^machine[[:space:]]+([^[:space:]]+) ]]; then
      machine="${BASH_REMATCH[1]}"
      JIRA_HOST=$machine
    elif [[ "$line" =~ ^login[[:space:]]+([^[:space:]]+) ]]; then
      login="${BASH_REMATCH[1]}"
      JIRA_USER=$login
    elif [[ "$line" =~ ^password[[:space:]]+([^[:space:]]+) ]]; then
      password="${BASH_REMATCH[1]}"
      JIRA_PASS=$password
    fi
  done < "$NET_RC_FILE"
}

parse_net_rc
if [[ -z "$JIRA_HOST" || -z "$JIRA_USER" || -z "$JIRA_PASS" ]]; then
  echo "No Jira credentials found in $NET_RC_FILE... failing"
  exit 1
fi

epic_display_fields="summary"
epic_display_columns="key,status,summary"
epic_display_orderby="status"

parse_display() {
  if [[ ! -f "$DISPLAY_CONFIG_FILE" ]]; then
    return
  fi
  while read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^([[:space:]]*#.*)?$ ]]; then
      continue
    fi

    # Extract epic_display_fields and epic_display_columns properties
    if [[ "$line" =~ ^epic_display_fields=(.*)$ ]]; then
      epic_display_fields="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^epic_display_columns=(.*)$ ]]; then
      epic_display_columns="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^epic_display_orderby=(.*)$ ]]; then
      epic_display_orderby="${BASH_REMATCH[1]}"
    fi
  done < "$DISPLAY_CONFIG_FILE"
}

parse_display

# PART TWO UTILS :)



slugify() {
  echo "$1" | iconv -t ascii//TRANSLIT | sed -r 's/[^a-zA-Z0-9]+/-/g' | sed -r 's/^-+\|-+$//g' | tr A-Z a-z
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


acting_on_issue() {
  issue=$1
  action=$2
  title=$($JIRA_COMMAND issue view "$issue" --plain --comments 0 | sed -n 4,4p)
  echo "🚀 $action $issue:"
  echo "$title"
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

# PART THREE :)

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

reset_quarter() {
  echo "--------------------------------------------------"
  echo "This seems to be the first time you've used bugs!"
  echo "or you're restarting"
  echo ""
  echo "Welcome!"
  echo ""
  echo "Please tell me about your epics, with a shorcut"
  epic=""
  mv $QUARTER_FILE $QUARTER_FILE.bak 2> /dev/null
  more="y"
  while [[ $more == "y" ]] ; do

    success=1
    while [[ $success != 0 ]] ; do
      echo "Enter a Jira number (ie TEST-1234):"
      read epic
      looks_like_jira_issue $epic
      success=$?
      if [ $success != 0 ]; then
        echo "That doesn't look like a Jira issue, try again"
      fi
    done

    echo "Now enter a shortcut for $epic (ie flux-proj):"
    read shortcut
    if [ -z "$shortcut" ]; then
      shortcut=`slugify "$epic"`
    fi
    echo "$epic,$shortcut" >> $QUARTER_FILE
    echo "Added $epic,$shortcut"
    echo "More (y/n)?"
    read more
    echo "Continue? $more"
  done
  echo "You can edit this file later: $QUARTER_FILE"
  echo "Or run 'bugs reset' to start over"
}

quarter() {
  cat $QUARTER_FILE 
}

epic() {
  epic=`epic_from_shortcut "$1"`

  issue_json=$(view_issue "$epic" "$epic_display_fields")
  echo "************"
  # For each field, comma separated
  for field in $(echo $epic_display_fields | sed "s/,/ /g"); do
    # Print the field name
    echo -n "$field: "
    # Print the field value
    echo "$issue_json" | jq -r ".[\"$field\"]"
  done
  echo "************"

  $JIRA_COMMAND epic list "$epic" --plain --columns $epic_display_columns --order-by $epic_display_orderby 
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
        "epic" "branch" "reset" "take" "block")
  if [[ " ${cmds[*]} " =~ " $maybe_cmd " ]]; then
    return 1
  fi
  return 0
}


view_issue() {
  issue=$1
  fields=$2
  $CURL_COMMAND -s \
    -u "$JIRA_USER:$JIRA_PASS" \
    -X GET \
    -H "Content-Type: application/json" \
    "https://$JIRA_HOST/rest/api/2/issue/$1?fields=$2" | $JQ_COMMAND .fields
}

bug() {
  # Always try to get an epic
  EPIC=$(epic_from_shortcut "$1")
  success=$?
  if [[ $success != 0 ]]; then
    echo "Epic '$1' not found in $QUARTER_FILE for $EPIC"
    EPIC=$(best_ticket_for_folder "epic")
    EPIC=$(epic_from_shortcut "$EPIC")
    success=$?
    if [[ $success != 0 ]]; then
      echo "No epic found in $QUARTER_FILE for $PWD"
      return 1
    fi
  fi
  summary="$2"
  looks_like_command "$summary"
  is_cmd=$?
  if [[ $is_cmd != 0 ]]; then
    echo "You appear to be trying to execute a command on $EPIC"
    echo " bugs expects: bugs <cmd> <EPIC> "
    return 1
  fi
  echo $summary
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

  switches="$3"
  if [[ $success == 0 ]]; then
    echo "Using an epic, not a JIRA issue, for branch."
    echo "Totally cool, but if its a big work item, think about"
    echo "making your own issue"
  else
    looks_like_jira_issue "$1"
    if [[ $? == 0 ]]; then
      issue=$1
    else
      echo "Not a valid JIRA issue - '$1'"
      return 1
    fi
  fi
  
  branch_name=$issue
  if [[ $2 == "" ]]; then
    echo "Please give a branch name"
    echo "Usage: bugs branch <jira-issue> <branch-name>"
    return 1
  else
    whitespace_replaced=`slugify "$2"`
    branch_name="$branch_name/$whitespace_replaced"
  fi
  acting_on_issue "$issue" "Branching"
  $GIT_COMMAND checkout -b "$branch_name"

  # Perform follow on actions in switches
  for (( i=0; i<${#switches}; i++ )); do
    this_switch="${switches:$i:1}"
    case $this_switch in
      "t")
        assign_to_me $issue
        ;;
      "s")
        start_issue $issue
        ;;
    esac
  done

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
  title=$($JIRA_COMMAND issues view SREL-1234 --plain --comments 0 | sed -n 4,4p)
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
  acting_on_issue $1 "Starting"
}

pause_issue() {
  acting_on_issue $1 "Pausing"
  transitions=$(get_transitions_for 'pause')
  transition_issue $1 "$transitions" "$2"
}


complete_issue() {
  acting_on_issue $1 "Completing"
  transitions=$(get_transitions_for 'complete')
  transition_issue $1 "$transitions" "$2"
}


cancel_issue() {
  acting_on_issue $1 "Canceling"
  transitions=$(get_transitions_for 'cancel')
  transition_issue $1 "$transitions" "$2"
}

block_issue() {
  acting_on_issue $1 "Block..."
  transitions=$(get_transitions_for 'block')
  transition_issue $1 "$transitions" "$2"
}

assign_to_me() {
  issue=$1
  user=$($JIRA_COMMAND me)
  echo "Assigning to $user"
  acting_on_issue $issue "Assigning to $user"
  $JIRA_COMMAND issue assign $issue $user
}


print_help() {
  echo "bugs - smarmy rabbit that helps you with JIRA"
  echo ""
  echo "Streamlined Jira usage that makes your stakeholders happy"
  echo ""
  echo "Usages: bugs <command> FOO-1234"
  echo ""
  echo "  Commands:"
  echo "  --------" 
  echo "    open - open an issue or epic in your browser"
  echo "    epic - list issues in an epic"
  echo "    branch - create a branch for an issue"
  echo "    take - assign an issue to me"
  echo "    scratch - add, remove, or list scratch notes"
  echo "    quarter - list the current quarter's epics"
  echo "    create - create an issue under an epic"
  echo "    start / pause / complete / cancel / block - transition an issue (see transitions)"
  echo "    help - this help"
  echo ""
  echo "  Examples:"
  echo "  --------" 
  echo ""
  echo "   List epics:"
  echo "    bugs - list epics"
  echo ""
  echo "   Open epic/issue in browser:"
  echo "    bugs TEST-1234"
  echo "    bugs open TEST-1234"
  echo "    bugs ."
  echo ""
  echo "   Create issue in epic:"
  echo "    bugs TEST-1234 \"foo the bar\""
  echo "    bugs fluxcapacitor \"attach lightning attractor to delorean\""
  echo "    bugs create TEST-1234 \"upgrade the microwave receiver\""
  echo "    bugs . \"make train flux capacitor\" #"
  echo ""
  echo "   View epic:"
  echo "    bugs <epic> - list epics issues"
  echo ""
  echo "   Branch for an issue or epic:"
  echo "    bugs branch TEST-1234 \"fix the flux capacitor\""
  echo "    bugs branch TEST-1234 \"fix the flux capacitor\"" --take --start
  echo "    bugs branch -ts TEST-1234 \"fix the flux capacitor\""
  echo ""
  echo "   Start (pause/stop/etc) an issue:"
  echo "    bugs start TEST-1234 \"started work\""
  echo "    bugs start TEST-1234"
  echo "    bugs pause TEST-1234 \"paused work\""
  echo "    bugs block TEST-1234 \"blocked by other work\""
  echo ""
  echo "    (Usage of '.' tries to use either the issue of the branch "
  echo "     or epic associated with the folder name via shortcut in .quarter)"
  echo ""
  echo " Setup:"
  echo " ------"
  echo "  Just run 'bugs' and to configure jira auth + epics"
  echo ""
  eche " Transitions:"
  echo " ------------"
  echo "   Jira projects limit issue state transitions. "
  echo "   For example, issues in TODO can only go to Ready. Only then can you click Started."
  echo ""
  echo "   We try to help by automating each transition when you want to 'start', 'pause', etc." 
  echo ""
  echo "   Add your steps to transitions file at ~/.bugs/transitions"
  echo ""
  echo "     start,Ready,Started  <- 'bugs start' first changes issue to Ready then Started"
  echo "     pause,Cancelled,Restarted  <- 'bugs pause' goes to Cancelled then Restarted"
  echo "     complete,Review,Done"
  echo "     cancel,Cancelled"
  echo "     block,Blocked"

}

# ----------------------------------------
# Shitty argument parsing
#  I should use getopts but I'm lazy

# Append any switches to the end of the args
#  e.g. bugs branch -ts TEST-1234 "fix the flux capacitor"
#  turn into: bugs branch TEST-1234 "fix the flux capacitor" -ts
SWITCH_ARGS=()
NEW_ARGS=()
SWITCHES=""

arg_rewrite_switches() {
  new_args=()
  args=("$@")
  for i in "${!args[@]}"; do
    if [[ "${args[$i]}" = "-"* ]]; then
      SWITCH_ARGS+=("${args[$i]}")
    else
      new_args+=("${args[$i]}")
    fi
  done
  new_args+=("${SWITCH_ARGS[@]}")

  # Squash switches to single string, taking first character
  #  e.g. -ta -s --foo -> tasf
  for i in "${!SWITCH_ARGS[@]}"; do
    if [[ "${SWITCH_ARGS[$i]}" = "-"* ]]; then
      SWITCHES+="${SWITCH_ARGS[$i]}"
    elif [[ "${SWITCH_ARGS[$i]}" = "--"* ]]; then
      this_arg="${SWITCH_ARGS[$i]//-/}"
      SWITCHES+="${this_arg:0:1}"
    fi
  done

  # Remove duplicates
  SWITCHES=$(echo "$SWITCHES" | grep -o "." | sort -u | tr -d "\n")

  # Set the args
  NEW_ARGS=("${new_args[@]}")
}

arg_rewrite_switches "$@"
set -- "${NEW_ARGS[@]}"

# Patch . in args with the current directory as if its an epic
# So if you have the current directory "search-bench" and there's an epic with
# that shortcut, then it will use that epic when you do:
#  bugs .
if [[ $2 == "." ]]; then
  prefer_epic=""
  # User explicitly wants an epic, dont use branch name
  if [[ $1 == "epic" ]]; then
    prefer_epic="epic"
  fi
  set -- $1 `best_ticket_for_folder $prefer_epic` "$3" "$4" "$5"
elif [[ $1 == "." ]]; then
  set -- `best_ticket_for_folder` "$2" "$3" "$4" "$5"
elif [[ $3 == "." ]]; then
  set -- "$1" "$2" `best_ticket_for_folder` "$4" "$5"
fi


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
elif [[ $1 == "block" ]]; then
  block_issue "$2" "$3"
elif [[ $1 == "unblock" ]]; then
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
elif [[ $1 == "create" ]]; then
  bug "$2" "$3"
elif [[ $1 == "branch" ]]; then
  branch "$2" "$3" "$SWITCHES"
elif [[ $1 == "help" ]]; then
  print_help
elif [[ $1 == "reset" ]]; then
  reset_quarter
elif [[ $1 == "take" ]]; then
  assign_to_me "$2"
elif [[ $1 != "" ]]; then
  if [[ $2 == "" ]]; then
    fuzzy_issue_open "$1"
  else
    bug "$1" "$2"
  fi
elif [[ $1 == "" ]]; then
  quarter
fi
