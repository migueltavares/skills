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

JSON response for fetch requests, detected by the `X-Requested-With: fetch` header:

```php
function site_contact_wants_json(): bool
{
    return ($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') === 'fetch';
}

function site_contact_json_response(array $state): void
{
    header('Content-Type: application/json; charset=UTF-8');
    header('Cache-Control: no-store');
    echo json_encode([
        'status' => $state['status'],
        'message' => $state['message'],
        'errors' => (object)$state['errors'],
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
```

Sending with PHPMailer (`composer require phpmailer/phpmailer`):

```php
$mail = new \PHPMailer\PHPMailer\PHPMailer(true);
$mail->CharSet = 'UTF-8';
$mail->isSMTP();
$mail->Host = $host;                       // smtp.resend.com
$mail->Port = $port;                       // 465
$mail->SMTPAuth = true;
$mail->Username = $username;               // resend
$mail->Password = $password;               // API key from env
$mail->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS; // ENCRYPTION_STARTTLS for 587
$mail->setFrom($from, '<Product> Website');
$mail->addAddress($recipient);
$mail->addReplyTo($values['email'], $values['name']);
$mail->Subject = $email['subject'];
$mail->isHTML(true);
$mail->Body = $email['html'];
$mail->AltBody = $email['text'];
$mail->send();
```

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

```js
const contactForm = document.querySelector("[data-contact-form]");
const contactAlert = document.querySelector("[data-form-alert]");

if (contactForm && contactAlert && window.fetch && window.FormData) {
    const submitButton = contactForm.querySelector("button[type=\"submit\"]");
    const submitLabel = submitButton ? submitButton.textContent : "";

    const showAlert = (status, message) => {
        contactAlert.textContent = message;
        contactAlert.className = "form-alert form-alert-" + status;
        contactAlert.setAttribute("role", status === "success" ? "status" : "alert");
        contactAlert.hidden = false;
        // Scroll only when the alert sits under the fixed header or near the
        // bottom edge, where the cookie banner can cover it.
        const box = contactAlert.getBoundingClientRect();

        if (box.top < 90 || box.bottom > window.innerHeight - 140) {
            contactAlert.scrollIntoView({ block: "center", behavior: "smooth" });
        }
        contactAlert.focus({ preventScroll: true });
    };

    const clearFieldErrors = () => {
        contactForm.querySelectorAll(".f.has-error").forEach((field) => field.classList.remove("has-error"));
        contactForm.querySelectorAll(".field-error").forEach((error) => error.remove());
        contactForm.querySelectorAll("[aria-invalid]").forEach((input) => {
            input.removeAttribute("aria-invalid");
            input.removeAttribute("aria-describedby");
        });
    };

    const showFieldErrors = (errors) => {
        Object.keys(errors).forEach((name) => {
            const input = contactForm.querySelector("[name=\"" + name + "\"]");
            const field = input ? input.closest(".f") : null;

            if (!field) {
                return;
            }

            const error = document.createElement("small");
            error.className = "field-error";
            error.id = input.id + "-error";
            error.textContent = errors[name];
            field.classList.add("has-error");
            field.appendChild(error);
            input.setAttribute("aria-invalid", "true");
            input.setAttribute("aria-describedby", error.id);
        });
    };

    contactForm.addEventListener("submit", async (event) => {
        event.preventDefault();

        if (submitButton) {
            submitButton.disabled = true;
            submitButton.textContent = submitButton.dataset.sendingLabel || submitLabel;
        }

        let result = null;

        try {
            const response = await fetch(contactForm.action, {
                method: "POST",
                body: new FormData(contactForm),
                headers: { "X-Requested-With": "fetch", Accept: "application/json" },
            });
            result = await response.json();
        } catch (error) {
            result = null;
        }

        clearFieldErrors();

        if (result && result.status === "success") {
            contactForm.reset();
            showAlert("success", result.message);
        } else if (result && result.message) {
            showFieldErrors(result.errors || {});
            showAlert("error", result.message);
        } else {
            showAlert("error", contactForm.dataset.errorMessage || "");
        }

        // A Turnstile token works only once, so get a fresh one for the next try.
        if (window.turnstile) {
            window.turnstile.reset();
        }

        if (submitButton) {
            submitButton.disabled = false;
            submitButton.textContent = submitLabel;
        }
    });
}
```

CSS to add, adapted to the site's colours:

```css
.form-alert{margin:0 0 16px;padding:14px 16px;border-radius:12px;font-size:14.5px}
.form-alert-success{background:rgba(47,181,156,.14);border:1px solid rgba(47,181,156,.4);color:#bdf0e2}
.form-alert-error{background:rgba(240,138,138,.12);border:1px solid rgba(240,138,138,.4);color:#f8c4c4}
.form-alert:focus{outline:none}
.contact-form .f.has-error input,.contact-form .f.has-error textarea{border-color:#f08a8a}
.field-error{color:#f6a3a3;font-size:12.5px}
.btn:disabled{opacity:.65;cursor:wait}
```

## Testing locally

- Turnstile fails on `localhost` and `127.0.0.1` because the site key is limited to the real domain (error 110200). For local tests, use Cloudflare's test keys (site key `1x00000000000000000000AA`, secret `1x0000000000000000000000000000000AA`) or the insecure flag. Never commit either.
- To see the email without sending real mail, point SMTP at a local sink, such as a small Python `aiosmtpd` server or Mailpit, and open the captured message.
- Check: field errors on an empty submit, the success alert and form reset, no page reload, the Turnstile reset between attempts, the no-JS post (locally, with Turnstile skipped, it ends in the 303 redirect; in production it shows the Turnstile message), and an HTML email with a text part and the right Reply-To.
- After deploy, a quick production check that sends no email: `curl -s -X POST -H 'X-Requested-With: fetch' -d 'site_form=contact' https://<domain>/` should return JSON with status 422. Then ask the user to send one real test through the live form.
