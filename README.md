# Bugs
(smarmy rabbit, avoids hard work)

[![Build Status](https://github.com/reddit/bugs/actions/workflows/test.yml/badge.svg)](https://github.com/reddit/bugs/actions/workflows/test.yml)

Use Jira at arms length, but keep your PM out of your hair. Opinionated way to deal with Jira at the command line. (Scripts on top of [jira-cli](https://github.com/ankitpokhrel/jira-cli)).

Instead of working in the Jira UI, bugs simplifies your life. It treats Jira as a backend for managing tasks within Epics. Each Epic with a set of tasks that go from TODO -> In Progress -> Complete. It lets you create git branches on those Epics, get Epic status, and ensure your Epics in Jira reflect reality so your PM is happy.

## Epic status

Put your team's epics for this quarter (or period, or whatever) in `.quarter` in your home directory. It should look like:

```
SOLR-2313,relevance_work
SOLR-2314,ml_model
SOLR-2316,tools
SOLR-2319,test_bench
SOLR-2373,ui_filters
```

Here you have the epic name, and a shortcut - a name you choose to make it easier to remember the epic. Add duplicate rows if you want multiple shortcuts.

Now use `bugs` to help you navigate:

```
$> bugs relevance_work

KEY		STATUS	SUMMARY
SOLR-2374	Done	Fix crash in LTR plugin
SOLR-2409	Done	Fix issue with edismax query parser
SOLR-2377	To Do	Cleanup admin UI relevance section
```

And add new issues for this epic as things come up

```
$> bugs relevance_work "Solve for foobar in the UI"
```

Run `bugs help` for more info.

## Interact with current repo

Create a branch for a ticket

```
>$ bugs branch SOLR-1234 "fix the frobinator"
On branch SOLR-1234/fix-the-frobinator
```

Open the ticket associated with the current repo branch

```
bugs open .
```

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

## Jira Issue Transitions

Stakeholders usually just focus on a simple kanban views of work. TODO, In Progress, Done, Canceled, etc... Yet teams internally often have other complicated transitions. So bugs has a shortcut:

```
./bugs start TEST-1234
./bugs cancel TEST-5678 "duplicate of TEST-1234"
```

These are the verbs corresponding to work:

* start -> go from TODO to In Progress
* pause -> go back to TODO
* complete -> go to DONE
* cancel -> cancel the task entirely

To do this, we have to handle that Jira is strict about how issues get transitions. So we give bugs a little config file to know how to execute that transition. For example to start, we'll try to move the task first to "Ready" in Jira then to "Started". 

```
start,Ready,Started
pause,Cancelled,Restarted
complete,Review,Done
cancel,Cancelled
```

If you're not sure where to get these, just figure out what transitions you would use in the UI when performing a "start", etc in your Jira project, and list those here.

Place this file as `.transitions` in your home directory for transitions to work with your projects isuse states.

## Installation

### With brew

```
brew tap reddit/bugs
brew install bugs
```

### Config your API key

[Get an API key, put it somewhere safe](https://github.com/ankitpokhrel/jira-cli#cloud-server).

Put your key in ~/.netrc

```
machine your_jira_server.atlassian.net
login <YOUR JIRA EMAIL>
password <YOUR API KEY>
```

### Add epics list to ~/.quarter

cat "SOLR-1234,foo-the-bar" >> ~/.quarter

## Jira data model / project management assumptions

Bugs takes a strong opinion that within a time period (quarter, etc) we work towards larger "epics". Most stakeholders care about tracking epic progress, and keeping this up to date. When we work on issues / create issues / etc, we always place them within an epic.

80% of jira usage is about checking / managing progress on epics, tracking issues within epics, etc. And we can cut out most of the Jira crap if we just focus on this model of project management.

But if this isn't your use of Jira, then bugs may not be for you.
