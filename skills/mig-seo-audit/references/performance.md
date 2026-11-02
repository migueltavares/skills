# PageSpeed

What moved a real landing page from 70 to 85 on mobile PageSpeed, and which warnings weren't worth chasing.

## Measure before changing

- PageSpeed Insights mobile uses Lantern, a simulation. On the earlier site it reported a 7.6 s LCP while a real trace showed 0.8 s. The simulation charges every script that starts before the LCP element, even async scripts that don't block it.
- Record a real trace with Chrome DevTools: Performance panel, 4x CPU slowdown, Slow 4G, reload. Note the LCP time and which element it is. Use the Chrome DevTools MCP performance tools if they're available.
- Mobile scores vary 5 to 10 points between runs. Compare medians of two or three runs, before and after.

## Fixes, in order of impact

1. **Load Google Analytics after the page.** Inject gtag.js on `window` load. The snippet is in `analytics-consent.md`.

2. **Load Turnstile lazily.** It's about 100 KB of script. Remove its `<script>` from the head and load it when the form gets close to the screen, or on the first focus inside the form:

    ```js
    const turnstile = document.querySelector("[data-turnstile-lazy]");

    if (turnstile) {
        let loaded = false;
        const loadTurnstile = () => {
            if (loaded) {
                return;
            }
            loaded = true;
            const script = document.createElement("script");
            script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js";
            script.async = true;
            document.head.appendChild(script);
        };

        turnstile.closest("form")?.addEventListener("focusin", loadTurnstile, { once: true });

        if ("IntersectionObserver" in window) {
            const observer = new IntersectionObserver((entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    observer.disconnect();
                    loadTurnstile();
                }
            }, { rootMargin: "600px 0px" });
            observer.observe(turnstile);
        } else {
            loadTurnstile();
        }
    }
    ```

    Implicit rendering picks up the `.cf-turnstile` div when the script arrives. No render call is needed.

3. **Right-size images.** The earlier site used a 667x667 favicon (29 KB) as the header logo. Make a 64px PNG for the header and the browser tab, and a 180px `apple-touch-icon`, for example with ImageMagick: `magick source.png -resize 64x64 -strip icon-64.png`. Give every `<img>` explicit `width` and `height`. Use WebP or AVIF for large images, and `loading="lazy"` for images below the fold. Never lazy-load the LCP image.

4. **Remove unused CSS.** Check every class and ID in the stylesheet against all templates and the JS, including classes that JS adds. Delete rules nothing uses, plus their media-query copies. Old designs leave the most behind.

5. **Cache-bust assets.** Version the CSS and JS URLs (`styles.css?v=<version>`) from one constant, and bump it on every change. Then the CDN and browsers can cache them for a long time.

6. **Fonts.** Load at most two families with only the weights in use, and use `display=swap`, so text shows straight away in a fallback font.

## Cloudflare

If the site is behind Cloudflare, ask the user to turn on the Speed settings. These matter most:

- **Cloudflare Fonts.** It rewrites Google Fonts to the site's own origin and inlines the `@font-face` rules in the HTML. The extra connection to Google disappears. With it on, a "No origins were preconnected" warning is expected and harmless, and preconnect tags to Google Fonts can go.
- **Brotli, HTTP/3 and Early Hints**, where offered.
- **Auto Minify** no longer exists in Cloudflare. On a small site, minifying would save 1 to 2 KB and wouldn't change the score, so a build step isn't worth adding.

Also ask the user to check Security > Bots, so AI search bots and Google's tag checker aren't challenged.

## Warnings to leave alone

- **Network dependency tree on font files.** With custom fonts, two font files after the HTML is the shortest chain possible. It's unscored. The only fix is dropping the fonts. Explain this and let the user decide.
- **Forced reflow under about 50 ms.** Too small to matter.
- **Unused JavaScript in third-party scripts** (gtag.js, Turnstile). Loading them late is the fix. Their contents can't be trimmed.

## Agentic browsing

Lighthouse's "Agentic browsing" score checks that agents can read and use the page. On the earlier site it was 2/3 because of an invalid `<dl>`. Fix the HTML it flags. The rules are in the "Agent readiness" section of `seo-aeo-checklist.md`.
