# frozen_string_literal: true

require "cgi"
require "json"
require "set"

# Add visible self-links to generated HTML headings.
# Pandoc creates stable ids for Markdown headings; this hook makes those ids
# discoverable/clickable. Headings produced by layouts get ids if missing.
#
# Pages with `giscus: true` in front matter also get a lazy-loaded Giscus
# discussion panel for every heading anchor, using the heading URL as the
# Giscus discussion term.
Jekyll::Hooks.register [:pages, :posts], :post_render do |document|
  next unless document.output_ext == ".html"
  next unless document.output

  giscus_config = document.site.config.fetch("giscus", {})
  giscus_enabled = document.data["giscus"] == true && giscus_config["enabled"] != false
  used_ids = Set.new(document.output.scan(/\sid=(['"])([^'"]+)\1/).map(&:last))

  slugify = lambda do |text|
    slug = CGI.unescapeHTML(text.gsub(/<[^>]+>/, ""))
              .downcase
              .gsub(/[^a-z0-9]+/, "-")
              .gsub(/\A-+|-+\z/, "")
    slug.empty? ? "heading" : slug
  end

  unique_id = lambda do |base|
    candidate = base
    suffix = 2
    while used_ids.include?(candidate)
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end
    used_ids.add(candidate)
    candidate
  end

  document.output = document.output.gsub(%r{<h([1-6])([^>]*)>(.*?)</h\1>}m) do |heading|
    level = Regexp.last_match(1)
    attrs = Regexp.last_match(2)
    inner_html = Regexp.last_match(3)

    next heading if inner_html.include?("header-anchor")

    id = if attrs =~ /\bid=(['"])([^'"]+)\1/
           Regexp.last_match(2)
         else
           unique_id.call(slugify.call(inner_html))
         end

    escaped_id = CGI.escapeHTML(id)
    attrs = attrs.sub(/\bid=(['"])([^'"]+)\1/, %(id="#{escaped_id}"))
    attrs = %(#{attrs} id="#{escaped_id}") unless attrs.include?(%(id="#{escaped_id}"))

    comments = ""
    comments_toggle = ""
    if giscus_enabled
      term = "#{document.url}##{id}"
      comments_id = "comments-#{escaped_id}"
      comments_toggle = %(<button class="section-comments-toggle" type="button" aria-expanded="false" aria-controls="#{comments_id}" title="Discuss this section">💬</button>)
      comments = <<~HTML
        <aside class="section-comments" id="#{comments_id}" hidden>
          <p class="section-comments-title">Discuss this section</p>
          <div class="giscus-section" data-giscus-term="#{CGI.escapeHTML(term)}"></div>
        </aside>
      HTML
    end

    %(<h#{level}#{attrs}>#{inner_html}<a class="header-anchor" href="##{escaped_id}" aria-label="Link to this heading">§</a>#{comments_toggle}</h#{level}>#{comments})
  end

  if giscus_enabled
    script_config = {
      repo: giscus_config.fetch("repo"),
      repoId: giscus_config.fetch("repo_id"),
      category: giscus_config.fetch("category"),
      categoryId: giscus_config.fetch("category_id"),
      theme: giscus_config.fetch("theme", "preferred_color_scheme"),
      lang: giscus_config.fetch("lang", "en")
    }

    giscus_script = <<~HTML
      <script>
        (function () {
          const config = #{JSON.generate(script_config)};
          const giscusOrigin = "https://giscus.app";
          const pageUrl = new URL(window.location.href);
          const giscusSession = pageUrl.searchParams.get("giscus") || "";
          let session = "";

          pageUrl.searchParams.delete("giscus");
          pageUrl.hash = "";
          const cleanPageUrl = pageUrl.toString();

          if (giscusSession) {
            session = giscusSession;
            localStorage.setItem("giscus-session", JSON.stringify(giscusSession));
            history.replaceState(undefined, document.title, cleanPageUrl);
          } else {
            try {
              session = JSON.parse(localStorage.getItem("giscus-session") || '""');
            } catch (_error) {
              localStorage.removeItem("giscus-session");
            }
          }

          function meta(name, openGraph) {
            const prefix = openGraph ? `meta[property="og:${name}"],` : "";
            const element = document.querySelector(`${prefix}meta[name="${name}"]`);
            return element ? element.content : "";
          }

          function loadGiscus(container) {
            if (!container || container.dataset.giscusLoaded) return;
            container.dataset.giscusLoaded = "true";

            const params = new URLSearchParams({
              origin: cleanPageUrl,
              session: session,
              theme: config.theme,
              reactionsEnabled: "1",
              emitMetadata: "0",
              inputPosition: "top",
              repo: config.repo,
              repoId: config.repoId,
              category: config.category,
              categoryId: config.categoryId,
              strict: "1",
              description: meta("description", true),
              backLink: meta("giscus:backlink") || cleanPageUrl,
              term: container.dataset.giscusTerm
            });

            const iframe = document.createElement("iframe");
            iframe.className = "giscus-frame giscus-frame--loading";
            iframe.title = "Comments";
            iframe.scrolling = "no";
            iframe.allow = "clipboard-write";
            iframe.src = `${giscusOrigin}/${config.lang}/widget?${params}`;
            iframe.style.opacity = "0";
            iframe.addEventListener("load", () => {
              iframe.style.removeProperty("opacity");
              iframe.classList.remove("giscus-frame--loading");
            });

            container.appendChild(iframe);
          }

          if (!document.getElementById("giscus-css")) {
            const link = document.createElement("link");
            link.id = "giscus-css";
            link.rel = "stylesheet";
            link.href = `${giscusOrigin}/default.css`;
            document.head.prepend(link);
          }

          window.addEventListener("message", (event) => {
            if (event.origin !== giscusOrigin) return;
            const payload = event.data;
            if (!payload || typeof payload !== "object" || !payload.giscus) return;

            if (payload.giscus.resizeHeight) {
              document.querySelectorAll(".giscus-frame").forEach((iframe) => {
                if (iframe.contentWindow === event.source) {
                  iframe.style.height = `${payload.giscus.resizeHeight}px`;
                }
              });
            }

            if (payload.giscus.signOut) {
              localStorage.removeItem("giscus-session");
            }
          });

          document.querySelectorAll(".section-comments-toggle").forEach((toggle) => {
            const panel = document.getElementById(toggle.getAttribute("aria-controls"));
            if (!panel) return;

            function showPanel() {
              panel.hidden = false;
              toggle.setAttribute("aria-expanded", "true");
              loadGiscus(panel.querySelector(".giscus-section"));
            }

            function hidePanel() {
              panel.hidden = true;
              toggle.setAttribute("aria-expanded", "false");
            }

            toggle.addEventListener("click", () => {
              if (panel.hidden) showPanel();
              else hidePanel();
            });

            if (window.location.hash === `#${panel.id}`) showPanel();
          });
        })();
      </script>
    HTML

    if document.output.include?("</body>")
      document.output = document.output.sub("</body>", "#{giscus_script}\n</body>")
    else
      document.output << giscus_script
    end
  end
end

# Open external links in a new tab while leaving same-page anchors alone.
Jekyll::Hooks.register [:pages, :posts], :post_render do |document|
  next unless document.output_ext == ".html"
  next unless document.output

  document.output = document.output.gsub(%r{<a\b[^>]*\bhref=(['"])https?://[^'"]+\1[^>]*>}i) do |tag|
    updated = tag.dup
    updated = updated.sub(/>\z/, ' target="_blank">') unless updated.match?(/\btarget=/i)

    if updated =~ /\brel=(['"])([^'"]*)\1/i
      quote = Regexp.last_match(1)
      rel_values = Regexp.last_match(2).split
      rel_values |= %w[noopener noreferrer]
      updated.sub(/\brel=(['"])([^'"]*)\1/i, %(rel=#{quote}#{rel_values.join(" ")}#{quote}))
    else
      updated.sub(/>\z/, ' rel="noopener noreferrer">')
    end
  end
end
