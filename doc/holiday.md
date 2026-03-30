# Holiday Countdown Extension

Convert the [custom-next-holiday](https://github.com/blueset/trmnl-recipes/tree/master/custom-next-holiday) TRMNL recipe into a Terminus `poll` extension.

The original recipe runs entirely in client-side JavaScript (Temporal API, js-yaml, Iconify), which won't execute during Terminus server-side rendering. The workaround is to build a small API endpoint that performs the holiday calculation and returns JSON for Terminus to render via a Liquid template.

---

## Step 1 — Build an API endpoint

Create an endpoint (in any language/framework) that calculates the next holiday and returns JSON:

```json
{
  "name": "Christmas",
  "days": 272,
  "icon": "🎄",
  "is_today": false
}
```

The endpoint should support the same date formats as the original recipe:

| Format | Example | Description |
|---|---|---|
| `YYYY-MM-DD` | `2038-01-19` | Specific date |
| `MM-DD` | `12-25` | Recurring yearly |
| `MMWn-D` | `05W1-1` | Nth weekday of month (e.g. 1st Monday of May) |
| `MMWnw-D` | `05Wn1-1` | Last Nth weekday of month (e.g. last Monday of May) |

Optional features from the original recipe:

- Calendar system suffix: `01-01[u-ca=hebrew]`
- Weekday rounding via a `round` field
- Multiple holidays evaluated to find the nearest upcoming one

---

## Step 2 — Create the extension in Terminus

Go to `/extensions/new` and fill in:

| Field | Value |
|---|---|
| **Label** | `Next Holiday` |
| **Name** | `next_holiday` |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | Your endpoint URL (e.g. `http://localhost:4000/api/holidays/next`) |
| **Headers** | `{"Accept": "application/json"}` |

---

## Step 3 — Write the Liquid template

```liquid
<div class="screen screen--og">
  <div class="view view--full">
    <div class="layout layout--col">
      <div class="title_bar">
        <span class="title">Next Holiday</span>
      </div>
      {% if source.is_today %}
        <span class="value--xxlarge">Today is</span>
        <span class="label">{{ source.name }}</span>
      {% elsif source.days == 1 %}
        <span class="value--xxlarge">Tomorrow</span>
        <span class="label">{{ source.name }}</span>
      {% else %}
        <span class="value--xxlarge">{{ source.days }}</span>
        <span class="label">days until {{ source.name }}</span>
      {% endif %}
    </div>
  </div>
</div>
```

### Extending with today + next holiday

If your endpoint returns both the current and next holiday:

```json
{
  "today": { "name": "Christmas" },
  "next": { "name": "New Year", "days": 7 }
}
```

You can handle both states:

```liquid
<div class="screen screen--og">
  <div class="view view--full">
    <div class="layout layout--col">
      <div class="title_bar">
        <span class="title">Next Holiday</span>
      </div>
      {% if source.today %}
        <span class="value--xxlarge">Today is</span>
        <span class="label">{{ source.today.name }}</span>
        {% if source.next %}
          <span class="description">Next: {{ source.next.name }} in {{ source.next.days }} days</span>
        {% endif %}
      {% elsif source.next %}
        {% if source.next.days == 1 %}
          <span class="value--xxlarge">Tomorrow</span>
          <span class="label">{{ source.next.name }}</span>
        {% else %}
          <span class="value--xxlarge">{{ source.next.days }}</span>
          <span class="label">days until {{ source.next.name }}</span>
        {% endif %}
      {% else %}
        <span class="label">No upcoming holidays</span>
      {% endif %}
    </div>
  </div>
</div>
```

---

## Step 4 — Set a schedule and build

1. Set the refresh interval to **24 hours** (the countdown only changes once per day).
2. Assign the extension to your device model under **Build Matrix**.
3. Click **Build** to render and push the screen.

---

## Original recipe reference

- **Repository:** [blueset/trmnl-recipes/custom-next-holiday](https://github.com/blueset/trmnl-recipes/tree/master/custom-next-holiday)
- **Strategy:** static (client-side JS) — not compatible with Terminus server-side rendering
- **Dependencies:** Temporal API polyfill, js-yaml, Iconify icons
- **Supported date formats:** absolute, monthly recurring, Nth weekday, last Nth weekday, alternative calendars
- **Display layouts:** full, half vertical, half horizontal, quadrant
