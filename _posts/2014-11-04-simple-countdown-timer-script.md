---
title: Simple countdown timer script for Mac OS X
date: 2014-11-05 14:40
layout: post
---

I have read about Pomodoro technique and while I'm not sure if I'm following its rules strictly, I found that restricting spent time is effective for certain kinds of activity. In particular, it's good to restrict review time when learning something with [Spaced repetition technique](https://en.wikipedia.org/wiki/Spaced_repetition). Having a large number of items in the review backlog is overwhelming. By limiting amount of time spent on review session you are confident that you won't get tired and buried under a ton of questions. Time limit also helps you to stay focused and have a right mindset.

So I wanted a super simple timer that:

- allow me to specify an interval of time
- display a notification when the interval is about to expire / when time is up
- play sound

I was a bit surprised that Mac OS X doesn't have such a simple software. Well, the only thing I need is a system command to show notifications and quick googling revealed existence of AppleScript language and that it does have a "display notification" command. The full invocation looks like this:

    display notification "Text" with title "Title" sound name "Ping"

This command will show a notification along with sound alert. You can see available sounds in `/System/Library/Sounds` folder. Note that depending on system settings, notification may not be shown at all, check out Notification settings in System Preferences.

AppleScript itself is a scripting language aimed at automating repetitive tasks and even though I'm pretty sure I could have written the entire script in it, I didn't feel like learning yet another language useless outside of particular OS. You can run AppleScript programs with `osascript` bundled with Mac OS X:

    $ osascript -e 'display notification "Hello world"'

so it's not a problem to invoke this from Ruby script and implement the rest of the logic in Ruby. The script accepts time interval:

    $ ./timer.rb 1h 30m

This command starts a timer with the interval of 1 hour and 30 minutes and shows a notification twice:

- first, when 95% of time has elapsed, for the input above it will pop up when 4.5 minutes is remaining
- when time is up

Grab the sources [here](https://gist.github.com/redcapital/b8203ba7ed399a74af76).
