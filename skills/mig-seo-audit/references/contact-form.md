# Contact form with Resend

The contact form sends email through Resend, as HTML in a branded layout with a plain-text part. Cloudflare Turnstile and a honeypot field block spam. The form submits with `fetch()`, so the page doesn't reload, and still works without JavaScript.

The server code below is plain PHP with PHPMailer, the default for a PHP site with no framework. On another stack, keep the same behaviour and port the code. Laravel's mailer works with Resend's SMTP settings or Laravel's Resend transport. Node can use nodemailer with the same SMTP settings, or the `resend` SDK.

## Resend settings

Resend works over SMTP with any SMTP client:

| Setting | Value |
| --- | --- |
| Host | `smtp.resend.com` |
| Port | `465` |
| Encryption | `ssl` (implicit TLS). Port `587` with STARTTLS also works. |
| Username | `resend` |
| Password | the Resend API key |

- The From address must be on a domain verified in Resend. Mail from an unverified domain is rejected.
- Use a sending-only API key scoped to that domain.
- The receiving inbox (To) can be anywhere.
- Read everything from environment variables. The key never goes in code, docs, commits or logs.

Suggested env vars (prefix them with the site name):

```bash
SITE_CONTACT_TO=hello@example.com
SITE_CONTACT_FROM=website@example.com
SITE_SMTP_HOST=smtp.resend.com
SITE_SMTP_PORT=465
SITE_SMTP_USERNAME=resend
SITE_SMTP_PASSWORD=
SITE_SMTP_ENCRYPTION=ssl
SITE_TURNSTILE_SITE_KEY=
SITE_TURNSTILE_SECRET_KEY=
```

Ship a `.env.example` with these names and empty secrets, make sure `.env` is git-ignored, and document the variables in the README. If the host has no server-level env vars, load `.env` with a small parser and keep the file outside the web root, or block it with the hidden-file rules.

## Form markup

```html
<p class="form-alert" role="status" tabindex="-1" data-form-alert hidden></p>
<form class="contact-form" action="/#contact" method="post" novalidate
      data-contact-form data-error-message="Something went wrong. Please try again or email us at hello@example.com.">
    <input type="hidden" name="site_form" value="contact">

    <div class="f">
        <label for="contact-name">Name</label>
        <input id="contact-name" name="name" type="text" autocomplete="name" required>
    </div>
    <div class="f">
        <label for="contact-email">Email</label>
        <input id="contact-email" name="email" type="email" autocomplete="email" required>
    </div>
    <!-- Optional: company (autocomplete="organization"), phone (type="tel", autocomplete="tel"),
         a topic or plan <select>, message <textarea>. Mark optional fields "(optional)" in the label. -->

    <div class="contact-honeypot" aria-hidden="true">
        <label for="contact-website">Website</label>
        <input id="contact-website" name="website" type="text" tabindex="-1" autocomplete="off">
    </div>

    <div class="cf-turnstile" data-turnstile-lazy data-sitekey="SITE_KEY"></div>

    <button class="btn btn-primary" type="submit" data-sending-label="Sending...">Send</button>
</form>
```

- The alert sits above the form and is always in the DOM, hidden until there's a message. The server renders it filled in for the no-JS case.
- The honeypot is hidden with CSS that moves it off screen (`position:absolute; left:-9999px`), not with `display:none`. Bots that fill it get a generic error.
- If plan buttons on the page link to the form, make each one pre-select the matching option (`data-topic="starter"`, with a small JS click handler).
- The Turnstile `<script>` is not in the head. JS loads it lazily (see `performance.md`).

## Server handler

Run it at the top of the page that renders the form, before any output.

1. Act only when the request is POST and `site_form === 'contact'`.
2. Trim every field and cut it to a max length (name 120, email 180, company 180, phone 80, message 2000). Use `mb_*` functions.
3. If the honeypot `website` has a value, return the generic send error.
4. Validate. Name is required. Email must pass `filter_var(..., FILTER_VALIDATE_EMAIL)`. Check every field against its max length. Collect errors per field in `errors[field] = message`, in the page language.
5. If there are errors, respond with HTTP 422, status `error`, message "Please check the fields below."
6. Verify Turnstile: POST `secret`, `response` (from `cf-turnstile-response`) and `remoteip` to `https://challenges.cloudflare.com/turnstile/v0/siteverify`, with a 6-second timeout. If `success` isn't true, respond 422 with a message that asks the visitor to try again, or to email the site's address directly. Visitors without JavaScript can't pass Turnstile, so for them this message is the end of the path. For local testing only, allow an explicit `SITE_CONTACT_ALLOW_INSECURE=1` to skip it when no secret is set.
7. Send the email. If sending fails, log the exception message (never the credentials) and respond 500 with the generic send error.
8. On success, a fetch request gets status `success` and the success message. A plain form post gets a `303` redirect to `/?contact=sent#contact`, and that page renders the success alert.

A request with the `X-Requested-With: fetch` header gets JSON instead of a page: `{"status": "success" | "error", "message": "...", "errors": {"<field>": "<message>"}}`, with `Cache-Control: no-store`. Encode `errors` as an object even when it is empty, and keep accented characters unescaped.

Send with PHPMailer (`composer require phpmailer/phpmailer`), with exceptions on:

- SMTP with the settings above. Port 465 uses `ENCRYPTION_SMTPS`, and port 587 uses `ENCRYPTION_STARTTLS`.
- `CharSet` is `UTF-8`. From is the verified address with the name "<Product> Website".
- `isHTML(true)`, with the HTML in `Body` and the plain text in `AltBody`.
- Reply-To is the visitor, so hitting Reply in the mail app answers them.
- Strip CR and LF from any value that goes into a header (subject, names).
- If SMTP isn't configured, fall back to PHP `mail()` with the plain-text body, so the form still works on a bare host.

## The email

Build three things from the submitted values: `subject`, `text` and `html`.

- **Subject:** `New contact request: <name>, <company>`, or just the name when there's no company.
- **Intro line:** "Someone filled in the contact form on <domain>. Reply to this email to answer <name> directly."
- **Details:** Name, Email, Company, Phone, Plan or topic, Language (the page language the visitor used), Page (the URL). Use "-" for empty optional fields.
- **Labels are always in English** (or the owner's language), whatever language the visitor used. Show topic labels in that language too.
- **Plain text:** the heading, intro, one `Label: value` line per detail, then `Message:` and the message.
- **HTML:** fill `email-template.html` in this folder. HTML-escape every value and turn message newlines into `<br>`. The hidden preheader is the first 140 characters of the message.
- **No Reply button.** The mail app already has Reply, and Reply-To points at the visitor.

Render a sample to a file and show the user before committing.

## Submit without reloading

Add a submit handler to `[data-contact-form]`, only when `fetch` and `FormData` exist. Without them the plain form post still works.

1. Prevent the default submit, disable the button and show its `data-sending-label`.
2. POST `new FormData(form)` to the form's `action`, with the headers `X-Requested-With: fetch` and `Accept: application/json`.
3. Clear the previous field errors, then act on the JSON:
   - On `success`, reset the form and show the message in `[data-form-alert]` with the class `form-alert-success` and `role="status"`.
   - On an error with a message, show it with `form-alert-error` and `role="alert"`. For each entry in `errors`, add `has-error` to the field's `.f` wrapper, append a `<small class="field-error">` with an id, and set `aria-invalid` and `aria-describedby` on the input.
   - When the response isn't JSON or the request fails, show the form's `data-error-message`.
4. Move focus to the alert with `focus({ preventScroll: true })`. Scroll it to the centre only when it sits under the fixed header or near the bottom edge, where the cookie banner can cover it.
5. Call `window.turnstile.reset()` after every attempt, since a token works only once.
6. Enable the button again and restore its label.

Style the alert in both states, the field in error, the field error text and the disabled button, in the site's colours. Remove the focus outline from the alert, since it takes focus only from script.

## Testing locally

- Turnstile fails on `localhost` and `127.0.0.1` because the site key is limited to the real domain (error 110200). For local tests, use Cloudflare's test keys (site key `1x00000000000000000000AA`, secret `1x0000000000000000000000000000000AA`) or the insecure flag. Never commit either.
- To see the email without sending real mail, point SMTP at a local sink, such as a small Python `aiosmtpd` server or Mailpit, and open the captured message.
- Check: field errors on an empty submit, the success alert and form reset, no page reload, the Turnstile reset between attempts, the no-JS post (locally, with Turnstile skipped, it ends in the 303 redirect; in production it shows the Turnstile message), and an HTML email with a text part and the right Reply-To.
- After deploy, a quick production check that sends no email: `curl -s -X POST -H 'X-Requested-With: fetch' -d 'site_form=contact' https://<domain>/` should return JSON with status 422. Then ask the user to send one real test through the live form.
