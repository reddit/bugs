# Bugs
(smarmy rabbit, avoids hard work)

[![Build Status](https://github.com/reddit/bugs/actions/workflows/test.yml/badge.svg)](https://github.com/reddit/bugs/actions/workflows/test.yml)

Keep your PM out of your hair. Command line tool for working with Jira Epics and their issues.

## Create your epics

Assumping you've created Epics (in Jira itself), run `bugs`. Running the first time will ask you about your epics and ask for a shorcut.

Bugs will prompt you for an epic, like `SOLR-2313` and let you enter a handy shortcut `relevance_work`

## Navigate epics

Now use `bugs` to help you navigate:

```
$> bugs relevance_work

KEY		STATUS	SUMMARY
SOLR-2374	Done	Fix crash in LTR plugin
SOLR-2409	Done	Fix issue with edismax query parser
SOLR-2377	To Do	Cleanup admin UI relevance section
```

## Add new issues

And add new issues for this epic as things come up

```
$> bugs create relevance_work "Solve for foobar in the UI"
```

We have a new task:

```
$> bugs relevance_work

KEY		STATUS	SUMMARY
SOLR-2374	Done	Fix crash in LTR plugin
SOLR-2409	Done	Fix issue with edismax query parser
SOLR-2377	To Do	Cleanup admin UI relevance section
SOLR-2410	To Do	Solve the foobar in the UI
```

## Update your issue progress

Bugs has shortcuts start / pause / block / etc to update issue status. You need to map these to your own Jira transitions (see below).

```
bugs start SOLR-2410	
```

Now the task is started:

```
$> bugs relevance_work

KEY		STATUS	SUMMARY
SOLR-2374	Done	Fix crash in LTR plugin
SOLR-2409	Done	Fix issue with edismax query parser
SOLR-2410	Started	Solve the foobar in the UI
SOLR-2377	To Do	Cleanup admin UI relevance section
```

Now you can give a handy report to your PM.

## Create branches for issues

You can start work on a branch with `bugs branch` and it'll help create a useful name for you.

```
>$ bugs branch SOLR-2410 "fix the frobinator UI"
On branch SOLR-2410/fix-the-frobinator-ui
```

### Open the issue associated with the current repo branch

```
bugs open .
```

### Open / list epic for current repo

If not on a bug branch, open any epic sharing a name with the current repo (ignoring -,\_, whitespace)

```
cd ~/src/sqs
bugs open .
```

Or just list the epic associated with search-bench

```
bugs .
```

```python
search-bench/>$ bugs .                                                                                                                      
KEY         STATUS      SUMMARY
SOLR-2444   Done        ML Model support for Frobinators
SOLR-2355   To Do       Improve performance of sampling
SOLR-2355   To Do       Design approval and review
```

And if you're on a bug branch, you can get this with `bugs epic .`

## Installation

### With brew

```
brew tap reddit/bugs
brew install bugs
```

Running `bugs` the first time will ask you for your jira host, username, and an [API Token](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/). As well as ask you for your epics.

### (Optionally) Configure transitions

You can ignore/use whichever transitions you need. Transition commands just execute the steps you do when you go to the Jira UI and move an issue around a board. See [moves/transitions](https://github.com/ankitpokhrel/jira-cli#movetransition).

To have transitions work, tell bugs how to execute issue transitions in the config file ~/.bugs/transitions.

```
start,Ready,Started
pause,Cancelled,Restarted
complete,Review,Done
cancel,Cancelled
block,Blocked
```

If you're not sure where to get these, just figure out what transitions you would use in the UI when going from a backlog to a "start", etc in your Jira project, and list those here after 'start'. Once you have this for one project, you can share around to your teammates.

### (Optionally) Add how you want epics displayed

To control epic display, create a file ~/.bugs/display controlling the epic metadata to show, the columns to show for the underlying issues, and the sort order of issues.

```
epic_display_fields=summary,duedate
epic_display_columns=key,status,summary,priority
epic_display_orderby=status
```

### Blow away jira credentials

If at any time you need to recreate jira credentials, simply remove the `.netrc` file in your home directory.

```
rm ~/.netrc
```

## Jira data model / project management assumptions

Bugs takes a strong opinion that within a time period (quarter, etc) we work towards larger "epics". Most stakeholders care about tracking epic progress, and keeping this up to date. When we work on issues / create issues / etc, we always place them within an epic.

80% of jira usage is about checking / managing progress on epics, tracking issues within epics, etc. And we can cut out most of the Jira crap if we just focus on this model of project management.

But if this isn't your use of Jira, then bugs may not be for you.
