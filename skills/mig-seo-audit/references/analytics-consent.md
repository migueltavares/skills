# Cookie consent and Google Analytics

Google Analytics 4 with Google Consent Mode v2 and a small consent banner. The templates are plain HTML and JS. Port them to the project's templating. `G-XXXXXXXXXX` is the measurement ID from intake. `<site>_analytics` is the localStorage key: use a short site prefix, such as `example_analytics`.

## Choose the consent mode

Ask the user at intake. Recommend advanced mode.

- **Advanced mode (recommended).** gtag.js loads for every visitor, with `analytics_storage` set to `denied` until Accept. Before a choice, Google gets cookieless pings. Properties with enough daily traffic can use them to model the visitors who reject; smaller properties can't. No `_ga` cookies exist until Accept. Some EU data protection authorities consider those cookieless pings to need consent too, so tell the user this mode is less strict.
- **Strict mode.** gtag.js loads only after Accept, and nothing reaches Google before that. This is the safest option under EU rules. The GA "Test installation" button will always fail, because the checker never clicks Accept. GA also gets no data at all from visitors who reject.

## Head snippet (advanced mode)

Put it at the very top of `<head>`, before CSS, on every page, including legal pages and the 404 page. Render nothing if the ID doesn't match `^G-[A-Z0-9]+$`.

```html
<!-- Google tag (gtag.js) with Consent Mode -->
<script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    var siteAnalyticsConsent = 'denied';
    try { if (localStorage.getItem('<site>_analytics') === 'granted') { siteAnalyticsConsent = 'granted'; } } catch (e) {}
    gtag('consent', 'default', {analytics_storage: siteAnalyticsConsent, ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied'});
</script>
<script>
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
    window.addEventListener('load', function () {
        var tag = document.createElement('script');
        tag.async = true;
        tag.src = 'https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX';
        document.head.appendChild(tag);
    });
</script>
```

Why it's built this way:

- **The consent default runs first**, before any `config` call, so Google never sees an undeclared state. A returning visitor who accepted gets `granted` straight away, with no flash of a denied page view.
- **Ad signals stay denied for everyone.** Accept only grants `analytics_storage`. The site runs analytics only.
- **gtag.js is injected on `window` load.** PageSpeed counts every script that starts before the main content, even async ones, so loading gtag.js early lowered the mobile score. Calls made before the script arrives wait in `dataLayer`, so page views still register.
- **Side effect:** the GA "Test installation" button looks for the `<script src=".../gtag/js?id=...">` line in the page source. It isn't there, so the button may report "Google tag not detected". Tell the user to ignore it and verify with Realtime instead (see the end of this file).

For strict mode, drop the `window.addEventListener('load', ...)` block. Instead, inject gtag.js from the banner's Accept handler, and on page load when the stored choice is `granted`.

## Banner markup

Place it at the end of `<body>`, on every page. It starts hidden, and JS shows it when no choice is stored. Use the page language for the text.

```html
<div class="consent" role="region" aria-label="Cookie consent" data-consent hidden>
    <p>We use Google Analytics cookies to see how visitors use this site, only if you accept. <a href="/privacy-policy/">Privacy Policy</a></p>
    <div class="consent-actions">
        <button class="btn btn-ghost" type="button" data-consent-choice="denied">Reject</button>
        <button class="btn btn-primary" type="button" data-consent-choice="granted">Accept</button>
    </div>
</div>
```

Put a "Cookie settings" button in the footer of every page:

```html
<button class="footer-link" type="button" data-consent-open>Cookie settings</button>
```

Portuguese (PT-PT) copy: aria-label "Consentimento de cookies"; text "Usamos cookies do Google Analytics para perceber como os visitantes usam este site, apenas se aceitar."; link "Política de Privacidade"; buttons "Rejeitar" and "Aceitar"; footer "Definições de cookies".

Give Accept and Reject equal weight: the same size, both visible, no pre-ticked choices. Rejecting must be as easy as accepting.

## Banner CSS

Adapt the colours to the site. `--panel`, `--line-2`, `--ink`, `--ink-2` and `--mute` are the site's own variables.

```css
.consent{position:fixed;left:16px;right:16px;bottom:16px;z-index:50;max-width:720px;margin-inline:auto;display:flex;align-items:center;gap:16px 24px;flex-wrap:wrap;padding:16px 18px;border-radius:16px;background:var(--panel);border:1px solid var(--line-2);box-shadow:0 20px 50px -20px rgba(0,0,0,.8)}
.consent[hidden]{display:none}
.consent p{flex:1 1 320px;margin:0;font-size:14px;color:var(--ink-2)}
.consent a{color:var(--ink)}
.consent-actions{display:flex;gap:10px}
.consent .btn{height:40px;padding:0 18px;font-size:14px}
.footer-link{background:none;border:0;padding:0;font:inherit;font-size:13px;color:var(--mute);text-decoration:underline;cursor:pointer}
.footer-link:hover{color:var(--ink)}
```

Give outline or ghost buttons an explicit `background`. When they're `<a>` tags nobody notices a missing one, but the Reject `<button>` falls back to the browser's grey.

## Banner JS

```js
const consent = document.querySelector("[data-consent]");
const storageKey = "<site>_analytics";

const readChoice = () => {
    try {
        return window.localStorage.getItem(storageKey);
    } catch (error) {
        return null;
    }
};

const removeAnalyticsCookies = () => {
    const host = window.location.hostname;
    // GA sets its cookies on the highest domain it can, such as .example.com
    // for blog.example.com, so try the host and every parent domain.
    const parts = host.split(".");
    const domains = [host, ...parts.map((_, i) => `.${parts.slice(i).join(".")}`)];
    document.cookie.split(";").forEach((cookie) => {
        const name = cookie.split("=")[0].trim();
        if (name === "_ga" || name.startsWith("_ga_")) {
            domains.forEach((domain) => {
                document.cookie = `${name}=; Max-Age=0; path=/; domain=${domain}`;
            });
            document.cookie = `${name}=; Max-Age=0; path=/`;
        }
    });
};

if (consent) {
    if (readChoice() === null) {
        consent.hidden = false;
    }

    consent.querySelectorAll("[data-consent-choice]").forEach((button) => {
        button.addEventListener("click", () => {
            const choice = button.dataset.consentChoice;
            try {
                window.localStorage.setItem(storageKey, choice);
            } catch (error) {
                // Storage blocked: the choice applies to this page only.
            }
            consent.hidden = true;

            if (typeof window.gtag === "function") {
                window.gtag("consent", "update", {analytics_storage: choice === "granted" ? "granted" : "denied"});
            }

            if (choice === "denied") {
                removeAnalyticsCookies();
            }
        });
    });

    document.querySelectorAll("[data-consent-open]").forEach((link) => {
        link.addEventListener("click", () => {
            consent.hidden = false;
            consent.querySelector("[data-consent-choice=\"granted\"]")?.focus();
        });
    });
}
```

GA sets `_ga` cookies on the registrable domain (`.example.com`), so the cleanup clears the host, the dotted host and the bare domain.

## Privacy Policy text

Add this to the cookies section, in every language, and update "Last updated". Adjust it if the site uses strict mode.

> With your consent, <domain> uses Google Analytics, provided by Google Ireland Limited, to measure how visitors use the website: pages viewed, approximate location, device and browser type, and how the visit started. Google Analytics only sets cookies (names starting with _ga) after you click Accept in the cookie banner. Until then, and if you reject, it runs without cookies and sends Google limited, cookieless signals, such as that a page was viewed, which Google uses to estimate visits. Your choice is saved in your browser's local storage. You can change it at any time with the Cookie settings link at the bottom of every page.

PT-PT:

> Com o seu consentimento, o <domain> usa o Google Analytics, fornecido pela Google Ireland Limited, para medir a forma como os visitantes usam o website: páginas vistas, localização aproximada, tipo de dispositivo e browser, e a origem da visita. O Google Analytics só cria cookies (nomes começados por _ga) depois de clicar em Aceitar no aviso de cookies. Até lá, e se rejeitar, funciona sem cookies e envia à Google sinais limitados e sem cookies, como o facto de uma página ter sido vista, que a Google usa para estimar visitas. A sua escolha fica guardada no armazenamento local do browser. Pode alterá-la a qualquer momento na ligação Definições de cookies, no fundo de todas as páginas.

Also list any other cookies or storage the site uses, such as a language cookie or Cloudflare Turnstile on the contact form.

## What to tell the user

- **"Google tag not detected" in GA's Test installation.** This is expected. The checker reads the page source without clicking Accept, gtag.js is injected after load, and Cloudflare's bot protection may challenge the checker. It doesn't mean the tag is broken.
- **How to verify.** Open the site in a private window, click Accept, browse two or three pages, then open GA > Reports > Realtime. The visit shows within a minute. The stream status ("No data received") updates within 24 to 48 hours.
- **Lower numbers.** Reports show less than real traffic, because visitors who reject aren't counted. Behavioural modelling can fill part of the gap, but only on properties with enough daily traffic to qualify.
- **Data retention.** The default is 2 months. Set it to 14 months under Admin > Data collection and modification > Data retention for year-over-year comparisons.
- **Search Console link.** Optionally link the Search Console property to GA (Admin > Product links) to see search queries next to visits.
