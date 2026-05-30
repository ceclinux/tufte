---
layout: index
title: Home
---

Welcome to **{{ site.title }}**.

## Posts

{% for post in site.posts %}
- [{{ post.title }}]({{ post.url | relative_url }}) <span class="post-meta">{{ post.date | date: "%b %-d, %Y" }}</span>
{% else %}
- No posts yet.
{% endfor %}
