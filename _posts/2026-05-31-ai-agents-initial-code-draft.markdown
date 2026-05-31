---
layout: post
title: "Let AI Agents Own the First Draft"
subtitle: "A practical path from ticket to pull request"
date: 2026-05-31 12:00 +0100
categories: ai engineering delivery
---

<section>

**Original source:** Stephen Walker, ["Accelerating Delivery: How AI Agents Can Own the Initial Code Draft"](https://8thlight.com/insights/accelerating-delivery-how-ai-agents-can-own-the-initial-code), 8th Light, May 5, 2026.

<span class="newthought">The most useful place</span> for coding agents may not be the glamorous end state where they autonomously run an engineering organization. It may be the much more ordinary gap between a well-described ticket and the first pull request.

That gap is expensive. A senior engineer reads the ticket, reconstructs product intent, locates the relevant architecture, remembers project conventions, creates a branch, writes boilerplate, runs tests, fixes predictable failures, and only then reaches the interesting part. The 8th Light article argues that this initial draft is exactly where agentic workflows can produce immediate value without demanding an all-or-nothing rewrite of the delivery process.

</section>

## Start with the ticket-to-PR path

The proposed interface is intentionally simple: a developer says something like `Let's work on FEAT-123`, and an agent workflow takes responsibility for turning that work item into a reviewable pull request.

That does **not** mean the agent owns production. It means the agent owns the first draft:

- understand the ticket;
- create a plan;
- make scoped code changes;
- write or update tests;
- run local quality checks;
- repair ordinary failures;
- open a pull request for a human reviewer.

This is a useful distinction. The risky question is, "Can AI replace the engineer?" The practical question is, "Can AI remove the blank-page and boilerplate costs before review begins?"[^first-draft]

[^first-draft]: The human still owns intent, judgment, approval, and merge authority. The agent accelerates preparation.

## The three constraints: safety, determinism, quality

The article frames the system around three constraints that make agentic delivery usable in real teams: **safety**, **determinism**, and **quality**.

### Safety means limited agency

An agent should behave like a specialized contributor, not a system administrator. Useful guardrails include:

- branch-level permissions;
- scoped scripts and hooks;
- clear file and command boundaries;
- mandatory human review before merge.

This reduces "agent drift," where a model makes unauthorized or hallucinated changes. The agent can be productive precisely because its world is constrained.

### Determinism wraps the probabilistic model

LLMs are probabilistic, so the workflow around them should not be. The article suggests a hierarchy of reliability:

1. hard-coded scripts and hooks for repetitive or sensitive behavior;
2. specialized agents with narrow responsibilities;
3. repository rules and memory for conventions, architectural norms, and known gotchas.

This is an important design pattern. Do not ask a model to remember what a script can enforce. Use the model for interpretation and synthesis; use deterministic tools for the parts that must be repeatable.

### Quality requires adversarial review

The first draft should not be a pile of generated code thrown over the wall. The article describes a multi-agent workflow where a planning agent proposes a plan, reviewer agents challenge that plan, coding agents implement it, and a final review agent checks the whole changeset.

That review stage matters. Without it, AI increases throughput by moving low-quality work downstream. With it, the human reviewer receives something closer to a junior engineer's prepared PR: imperfect, but structured, tested, and aligned with local conventions.

## Avoid one giant conversation

One failure mode for coding agents is context rot. As the conversation grows, logs, unrelated files, and partial reasoning dilute the model's attention.

The article's solution is orchestration: split the workflow into focused agents. One agent plans. Another implements. Another reviews. Another extracts lessons into project memory. Each agent receives a smaller and cleaner context window.

This resembles normal software design. We do not build reliable systems by putting every responsibility in one object; we separate responsibilities and define interfaces between them.

## Add stop-losses

Agent workflows need operational ceilings. Examples from the article include:

- skipping tests when the change is documentation-only;
- limiting the number of review-and-repair cycles;
- capping build-fix attempts;
- pausing for human help when the workflow stops making progress.

These limits are not signs of weakness. They are what make the system safe to run repeatedly. A useful agent should know when to stop spending tokens and ask for human judgment.

## The repository becomes shared memory

The most interesting claim is not merely that agents can open more pull requests. It is that every completed work item can improve the next one.

When an agent discovers a legacy integration quirk, a naming convention, or a test setup trap, that lesson can be written back into repository-level context. Future agents inherit the knowledge. The system becomes less like an individual's coding assistant and more like a shared engineering memory.

That is where the leverage appears: not in one impressive demo, but in compounding local knowledge.

## A realistic adoption model

The article's strongest point is its pragmatism. Teams do not need to begin with fully autonomous software delivery. They can start with a narrow, reviewable workflow:

1. choose a class of tickets with clear acceptance criteria;
2. restrict the agent to feature branches;
3. encode project rules in repository context;
4. require tests, linting, and typechecks;
5. cap repair loops;
6. route every PR through normal human review.

This makes the agent a first-draft engine. The developer's role shifts toward requirement clarification, architectural judgment, and final validation.

## The real goal

The goal is not to maximize generated code. The goal is to reduce the time between intent and a concrete artifact that can be reviewed.

A pull request is valuable because it turns abstraction into something inspectable. If agents can reliably produce that first inspectable artifact — safely, deterministically, and with quality gates — then they can accelerate delivery without removing human responsibility.

That is a modest claim compared with full autonomy. It is also much more useful.

</section>
