---
title: skadi - image viewer app
date: 2015-12-28 15:41
layout: post
---

Hey, it's been a while since I posted here, isn't it?

Anyway, I've been working on a lightweight image viewer app for OS X lately. I had only two simple requirements:

- lightweight, with minimal necessary UI controls and functionality
- ability to jump to a previous/next file in a directory

The builtin OS X viewer is kinda good, but doesn't fulfill the second bullet point. So I quickly hacked the minimal usable prototype in about two hours and later added some essential functionality like zooming and dragging. Using Qt5 along with QML made the development easy as pie.

If you too think that existing viewers are bloated and shitty you're welcome to try it out - [installation instructions](https://github.com/galymzhan/skadi)
