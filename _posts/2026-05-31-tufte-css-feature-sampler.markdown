---
layout: post
title: Tufte CSS Feature Sampler
subtitle: A small post that exercises the theme
date: 2026-05-31 00:00 +0000
giscus: true
---

<section>

## Getting Started

<span class="newthought">This short article</span> is a compact sampler for the
Tufte CSS vocabulary: sections, headings, sidenotes, margin notes, figures,
full-width media, epigraphs, code, and image quilts. It is intentionally simple
so it can be used as a quick visual regression test.[^purpose]

[^purpose]: This numbered sidenote is generated from an ordinary Pandoc
    footnote. On wide screens it appears in the margin; on narrow screens it can
    be expanded inline.

Use regular Markdown for most prose. The theme supplies the Tufte typography,
column widths, and margin behavior.

### Sections and headings

Use `##` for major sections and `###` for lower-level headings. The site also
adds a visible anchor link to each heading, so sections can be shared directly.

> The commonality between science and art is in trying to see profoundly — to
> develop strategies of seeing and showing.
>
> <footer>Edward Tufte</footer>

</section>

<section>

## Text

Tufte pages often begin a section with a <span class="newthought">new thought</span>.
Inline code such as `margin-toggle`, `sidenote`, and `fullwidth` stays readable
without overpowering the surrounding prose.

<p class="sans">This paragraph uses the <code>sans</code> class. It is useful for
asides, UI-like notes, or a change in typographic voice.</p>

External links, such as [Tufte CSS](https://edwardtufte.github.io/tufte-css/),
open in a new tab on this site. Same-page heading anchors stay in the current
tab.[^links]

[^links]: {-} This is a margin note. The `{-}` marker asks `pandoc-sidenote` to
    render the note without a sidenote number.

</section>

<section>

## Epigraphs

<div class="epigraph">
<blockquote>
<p>The minimum we should hope for with any display technology is that it should
do no harm.</p>
<footer>Edward Tufte, <cite>Beautiful Evidence</cite></footer>
</blockquote>

<blockquote>
<p>Above all else show the data.</p>
<footer>Edward Tufte, <cite>The Visual Display of Quantitative Information</cite></footer>
</blockquote>
</div>

Epigraphs are grouped quotations. They work well at the beginning of an essay or
major section.

</section>

<section>

## Sidenotes and margin notes

A sidenote is for extra detail that should remain near the text it explains.[^side]
A margin note is similar, but unnumbered.[^margin]

[^side]: This is another numbered sidenote. It keeps the reader in the same
    visual neighborhood as the main sentence.

[^margin]: {-} This unnumbered margin note is useful for definitions, short
    warnings, or annotations that do not need a number.

</section>

<section>

## Figures

A regular figure stays in the main text column and can carry a margin note.

<figure>
<label for="mn-exports" class="margin-toggle">&#8853;</label>
<input type="checkbox" id="mn-exports" class="margin-toggle"/>
<span class="marginnote">A regular figure with a margin caption, using one of the
sample images fetched from the Tufte CSS demo.</span>
<img src="/tufte-md/img/exports-imports.png" alt="Exports and imports chart"/>
</figure>

Margin figures are good when the image supports a sentence rather than becoming
the center of attention.[^rhino]

[^rhino]: {-} ![A rhinoceros margin figure](/tufte-md/img/rhino.png) A compact
    margin figure can live inside a margin note.

When a graphic needs more room, use a full-width figure.

<figure class="fullwidth">
<img src="/tufte-md/img/napoleons-march.png" alt="Minard's map of Napoleon's march"/>
</figure>

</section>

<section>

## Responsive embeds

The `iframe-wrapper` helper keeps embedded media responsive.

<figure class="iframe-wrapper">
<iframe width="853" height="480" src="https://www.youtube.com/embed/YslQ2625TR4" title="Tufte-style embedded media" allowfullscreen></iframe>
</figure>

</section>

<section>

## Tables and code

A small table fits naturally in the main column.

| Feature | Markup | Result |
| --- | --- | --- |
| Sidenote | `[^note]` | Numbered margin note |
| Margin note | `[^note]: {-} ...` | Unnumbered margin note |
| Full figure | `<figure class="fullwidth">` | Wide visual |

Longer code examples use fenced code blocks:

```clojure
;; A tiny data transformation
(->> observations
     (filter :visible?)
     (map :value)
     (reduce +))
```

</section>

<section>

## ImageQuilts

ImageQuilts can be full-width when the texture matters.

<figure class="fullwidth">
<img src="/tufte-md/img/imagequilt-chinese-calligraphy.png" alt="Chinese calligraphy ImageQuilt"/>
</figure>

They can also remain in the main column.

<figure>
<img src="/tufte-md/img/imagequilt-animal-sounds.png" alt="Animal sounds ImageQuilt"/>
</figure>

</section>

<section>

## Epilogue

This post is not meant to be profound; it is a checklist. If the page renders
with balanced columns, sidenotes, margin notes, figures, code, anchors, external
links, and per-section discussions, the core Tufte CSS features are working.

</section>
