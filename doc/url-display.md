# Displaying a Custom Webpage on a TRMNL Device

This guide explains how to display a webpage you control on a TRMNL device via a Terminus `poll` extension.

The approach is to have your webpage serve its pre-rendered TRMNL HTML as a JSON field, which Terminus fetches and passes directly to the device screen.

---

## Step 1 — Format your page's JSON response

Have your webpage serve a JSON response with the pre-rendered HTML as a field:

```json
{
  "content": "<div class=\"screen screen--og\"><div class=\"view view--full\">...</div></div>"
}
```

The `content` field should contain the full TRMNL-formatted HTML string. Most JSON serializers escape the HTML automatically — for example in Ruby:

```ruby
{ content: html_string }.to_json
```

---

## Step 2 — Create the extension in Terminus

Go to `/extensions/new` and fill in:

| Field | Value |
|---|---|
| **Label** | A human-readable name (e.g. `My Display`) |
| **Name** | A slug with no spaces (e.g. `my_display`) |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | Your webpage's URL |
| **Headers** | `{"Accept": "application/json"}` |

---

## Step 3 — Write the Liquid template

Since your page already produces TRMNL-formatted HTML, the template is a single line:

```liquid
{{source.content}}
```

Terminus fetches your JSON, reads the `content` field, and passes it straight through as the screen HTML.

---

## Step 4 — Set a schedule and build

1. Set a refresh interval appropriate for how often your page's content changes (e.g. every 15 minutes, hourly).
2. Assign the extension to your device model under the **Build Matrix** section.
3. Click **Build** to render and push the screen to your device.

---

## Notes

- Your JSON must be valid — double quotes inside the HTML string must be escaped as `\"`. Most serializers handle this automatically.
- If your URL requires authentication, add the relevant headers in the **Headers** field as a JSON object, e.g. `{"Authorization": "Bearer your-token", "Accept": "application/json"}`.
- Use the **Poll** button on the extension page to inspect the raw fetched data and verify Terminus is receiving the expected JSON before building.
- Use the **Preview** button to render the screen without saving it, useful for checking layout before committing.
