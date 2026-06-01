# frozen_string_literal: true

# Inject a small, persistent light/dark theme switcher into every generated page.
# Defaults to dark during local night hours (19:00–06:59) unless the visitor has
# chosen a preference.
Jekyll::Hooks.register [:pages, :posts], :post_render do |document|
  next unless document.output_ext == ".html"
  next unless document.output

  head_script = <<~HTML
    <meta name="color-scheme" content="light dark">
    <script>
      (function () {
        try {
          localStorage.removeItem("notes-theme");
          var savedTheme = localStorage.getItem("notes-theme-mode");
          var hour = new Date().getHours();
          var theme = savedTheme || ((hour >= 19 || hour < 7) ? "dark" : "light");
          document.documentElement.setAttribute("data-theme", theme);
        } catch (_error) {
          document.documentElement.setAttribute("data-theme", "light");
        }
      })();
    </script>
  HTML

  switcher = <<~HTML
    <button class="theme-switch" type="button" aria-label="Switch color theme" aria-live="polite">
      <span class="theme-switch__icon" aria-hidden="true"></span>
      <span class="theme-switch__label"></span>
    </button>
    <script>
      (function () {
        var STORAGE_KEY = "notes-theme-mode";
        var button = document.querySelector(".theme-switch");
        if (!button) return;

        function preferredTheme() {
          try {
            var savedTheme = localStorage.getItem(STORAGE_KEY);
            if (savedTheme === "dark" || savedTheme === "light") return savedTheme;
          } catch (_error) {}

          var hour = new Date().getHours();
          return (hour >= 19 || hour < 7) ? "dark" : "light";
        }

        function applyTheme(theme, persist) {
          document.documentElement.setAttribute("data-theme", theme);
          var nextTheme = theme === "dark" ? "light" : "dark";
          button.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
          button.setAttribute("aria-label", "Switch to " + nextTheme + " theme");
          button.querySelector(".theme-switch__icon").textContent = theme === "dark" ? "☼" : "☾";
          button.querySelector(".theme-switch__label").textContent = theme === "dark" ? "Light" : "Dark";
          button.title = "Switch to " + nextTheme + " theme";

          if (persist) {
            try { localStorage.setItem(STORAGE_KEY, theme); } catch (_error) {}
          }

          window.dispatchEvent(new CustomEvent("notes-theme-change", { detail: { theme: theme } }));
        }

        applyTheme(preferredTheme(), false);
        button.addEventListener("click", function () {
          var nextTheme = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
          applyTheme(nextTheme, true);
        });
      })();
    </script>
  HTML

  document.output = document.output.sub("</head>", "#{head_script}\n</head>") if document.output.include?("</head>")

  if document.output.include?("</body>")
    document.output = document.output.sub("</body>", "#{switcher}\n</body>")
  else
    document.output << switcher
  end
end
