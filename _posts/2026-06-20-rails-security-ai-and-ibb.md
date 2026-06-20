---
layout: post
title: "Rails Security, AI, and IBB"
date: 2026-06-20
---

Original source: [Original post](<https://tenderlovemaking.com/2026/05/06/rails-security-ai-and-ibb/>)

For quite a few years the Rails project has been working with the [Internet Bug Bounty](https://hackerone.com/ibb?type=team) (IBB). The IBB is an organization that awarded cash to security researchers that reported issues to OSS projects participating in the IBB. For quite a while I wasn’t certain about my feelings toward the program because I felt like cash rewards could incentivize low quality reports as well as encourage reporters to “haggle” about the severity of a particular bug (the IBB paid more when the bug was more severe). In the beginning that certainly was the case. We were fielding many low quality reports, and people were haggling over severity. But the program evolved, and despite the never-ending haggling, I felt it did more good (rewarding security researchers) than bad (forcing the security team to wade through low quality reports).

That is, until AI came along. Sometime in 2025 our team started getting inundated with low quality AI generated reports. I know for sure this wasn’t unique to just our team as well. Anyway, AI lowered the barrier to generate reports, so we were back in the era of wading through low quality reports. Only this time, the low quality reports were masquerading as high quality reports. AI made it easy to turn a bullshit problem into something that looked legit, and since there’s a possibility of money involved people tried to take advantage of the situation.

We even had a report where someone forgot to delete the AI generated output and just uploaded the report as-is with the following text:

```
## ✅ READY TO SUBMIT!

*All information prepared for professional Rails bug bounty submission.*

*Expected Outcome:*

Rails Team Response: 1-2 weeks
Fix Development: 2-8 weeks
Security Release: 8-12 weeks
IBB Bounty: $1,040-1,600 (80% of $1,300-2,000)

*Next Step:* Copy information above into HackerOne form and submit!
```

I enjoy using AI, but I really don’t like AI being used *on* me. But that’s not what this post is about.

Recently the IBB stopped accepting new submissions. In other words, they aren’t paying bounties to security researchers anymore. I don’t know for sure since I haven’t asked them directly, but I suspect this is due to so many projects being inundated with AI generated reports.

I think putting a stop to bounties makes sense for the time being. Of course the downside is that legitimate researchers are no longer incentivized to report bugs to OSS projects. Finally, the Rails team didn’t actually handle paying out any of the bounties. After we accept and release fixes, the IBB took care of the bounties and we had no visibility into that process. Since the IBB has stopped accepting new submissions and paying bounties, we’re now tasked with playing customer support for IBB as many reporters are now asking us “are we getting paid?”

I honestly don’t know what to make of this situation except that working in OSS security will always find new and interesting ways to suck. I don’t have any particular “call to action” for this post, but I hope that it gives people some kind of glimpse into how the tofu is made.

Anyway, have a good day, and remember: It’s always Friday somewhere!
