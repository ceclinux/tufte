---
layout: post
title: "Pixoo64 Ruby Client"
date: 2026-06-20
---

Original source: [Original post](<https://tenderlovemaking.com/2026/01/01/pixoo64-ruby-client/>)

I bought a [Pixoo64 LED Display](https://divoom.com/products/pixoo-64) to play around with, and I love it! It connects to WiFi and has an on-board HTTP API so you can program it. I made [a Ruby client for it](https://github.com/tenderlove/pixoo-rb) that even includes code to convert PNG files to the binary format the sign wants.

One cool thing is that the display can be configured to fetch data from a remote server, so I configured mine to fetch PM2.5 and CO2 data for my office.

Here’s what it’s looking like so far:

![LED sign that has a cat and PM2.5 data on it](/assets/images/imported/pixoo64-ruby-client/P1010032.jpeg)

Yes, this is how I discovered I need to open a window 😂
