# Terminus Plugin (Extension) System — Investigation Report

## Overview

Terminus uses the term **"extensions"** for its plugin system. Extensions are user-created data sources that fetch content, render it via Liquid templates, and push the result to device screens on a schedule. There are no hardcoded built-in plugins — the system is entirely dynamic, driven by user configuration through the UI.

---

## Existing Extensions

There are **no pre-shipped extensions** in the codebase. Instead, Terminus provides:

- A **Gallery** page (`/extensions/gallery`) that pulls recipe templates from the TRMNL Core API, which users can import as starting points.
- A full CRUD interface for creating extensions from scratch.

Extensions are created and stored in the database by end users. Any "existing" extensions are ones you or your users have created.

---

## Extension Types (Kinds)

Three types of extension are supported, controlled by the `kind` field:

| Kind | Data Source | Use Case |
|---|---|---|
| `poll` | HTTP endpoint (JSON, CSV, XML, plain text) | Live data — weather, stocks, RSS feeds, custom APIs |
| `image` | HTTP endpoint returning an image | Photo feeds, dynamic image displays |
| `static` | The `body` field on the extension record | Fixed content, announcements, manual data |

---

## How Extensions Work — Full Lifecycle

```
1. User creates extension (form)
         ↓
2. Validated via dry-validation contract
         ↓
3. Saved to database with model/device associations
         ↓
4. Cron job registered with Sidekiq-Scheduler
         ↓
5. "Build" button clicked (or cron fires)
         ↓
6. Jobs::Batches::Extension enqueues per-model or per-device jobs
         ↓
7. Jobs::Extensions::Screen renders for each target
    ├─ Fetches data via MultiFetcher (for poll/image)
    ├─ Parses response by MIME type
    ├─ Builds Liquid template context
    ├─ Renders HTML via Liquid
    └─ Creates/updates Screen record in database
         ↓
8. Device polls /api/display → receives rendered screen image
```

---

## Extension Data Model

Each extension record contains the following fields:

### Identity
| Field | Type | Description |
|---|---|---|
| `name` | string | Machine-readable identifier (used in cron job name) |
| `label` | string | Human-readable display name |
| `description` | string | Optional description |
| `kind` | string | `poll`, `image`, or `static` |
| `tags` | array | Metadata tags |

### HTTP Fetching
| Field | Type | Description |
|---|---|---|
| `verb` | string | HTTP method (`get`, `post`, etc.) |
| `uris` | array | One or more URLs to fetch (newline-delimited in the form) |
| `headers` | hash | Custom HTTP headers as JSON |
| `body` | hash | Request body as JSON (also the data source for `static` kind) |

### Rendering
| Field | Type | Description |
|---|---|---|
| `template` | string | Liquid template for HTML output |
| `data` | hash | Arbitrary static data available in template as `extension.data` |
| `fields` | array | User-defined fields with default values |

### Scheduling
| Field | Type | Description |
|---|---|---|
| `interval` | integer | How often to run |
| `unit` | string | `minute`, `hour`, `day`, `week`, `month`, `none` |
| `days` | array | Specific days (0–6 for weekly, 1–31 for monthly) |
| `last_day_of_month` | boolean | Run on last day of month |
| `start_at` | datetime | When the schedule begins |

### Associations
| Field | Type | Description |
|---|---|---|
| `model_ids` | array | Device model IDs to render for (generic rendering) |
| `device_ids` | array | Specific device IDs to render for (device-specific rendering) |

---

## Liquid Template System

Templates use [Liquid](https://shopify.github.io/liquid/) (Shopify's templating language), enhanced by the `trmnl-liquid` gem which adds custom filters.

### Available Template Variables

| Variable | Description |
|---|---|
| `source` | Fetched data for single-URI poll/image extensions |
| `source_1`, `source_2`, ... | Fetched data when multiple URIs are configured |
| `extension.data` | The extension's `data` hash |
| `extension.fields` | Field definitions |
| `extension.values` | Field default values as a flat key→value map |
| `extension.css_classes` | Responsive CSS classes for the target device model |
| `sensors` | Array of sensor readings from the associated device |

### Default Template Scaffold

```liquid
<div class="{{extension.css_classes}}">
  <div class="view view--full">
    <div class="layout layout--col">
      {{-- your content here --}}
    </div>
  </div>
</div>
```

### Parsed Data Formats

The parser converts HTTP responses based on MIME type:

| MIME Type | Result in `source` |
|---|---|
| `application/json` | Parsed JSON (object or array) |
| `text/csv` | Array of hashes (headers as keys) |
| `text/plain` | Array of words |
| `text/xml` / `application/xml` | Parsed XML hash |
| `application/rss+xml` / `application/atom+xml` | Parsed feed hash |
| `image/*` | Raw binary (for image kind) |

---

## Creating a New Plugin — Step-by-Step

### Step 1 — Navigate to Extensions

Go to `/extensions` in the Terminus UI and click **New Extension**.

### Step 2 — Fill in Core Details

- **Label**: A human-readable name shown in the UI (e.g. `GitHub Stars`)
- **Name**: A machine-readable slug used internally (e.g. `github_stars`) — no spaces, use underscores
- **Description**: Optional. Shown in the gallery.
- **Kind**: Choose `poll`, `image`, or `static`

### Step 3 — Configure Data Fetching (poll / image)

- **URI(s)**: One or more URLs, one per line. These are fetched in parallel.
- **Verb**: HTTP method (`get` for most APIs)
- **Headers**: JSON object for custom headers, e.g.:
  ```json
  {"Authorization": "Bearer your-token", "Accept": "application/json"}
  ```
- **Body**: JSON object for POST request bodies

### Step 4 — Write the Liquid Template

Use the `source` variable to access fetched data. Example for a JSON API returning `{"temperature": 22}`:

```liquid
<div class="{{extension.css_classes}}">
  <div class="view view--full">
    <div class="layout layout--col layout--justify-center layout--align-center">
      <span class="title">Temperature</span>
      <span class="value--xl">{{source.temperature}}°C</span>
    </div>
  </div>
</div>
```

For an array response, use a Liquid `for` loop:

```liquid
{% for item in source limit:5 %}
  <div class="item">{{item.title}}</div>
{% endfor %}
```

### Step 5 — Set a Schedule

- **Interval + Unit**: e.g. `15 minutes`, `1 hour`, `1 day`
- **Start At**: When the first run should fire
- Use `none` for unit if you only want manual builds

### Step 6 — Assign to Device Models or Devices

- **Build Matrix (Models)**: Renders one screen per selected model type, shared across all devices of that model
- **Specific Devices**: Renders one screen per device, allowing device-specific sensor data in the template

### Step 7 — Build and Preview

- Click **Preview** to render without saving a screen
- Click **Build** to enqueue rendering jobs and create screen records
- Use **Poll** to inspect the raw fetched data as JSON (useful for debugging templates)
- Use **Sensors** to inspect sensor readings available to the template

---

## Example Extensions You Could Implement

### Poll — Public JSON API

```
Label: "Open Library Search"
Kind: poll
URI: https://openlibrary.org/search.json?q=ruby+programming&limit=5
Verb: GET
Template:
  {% for book in source.docs limit:3 %}
    <div>{{book.title}} by {{book.author_name[0]}}</div>
  {% endfor %}
Interval: 1 hour
```

### Poll — Authenticated API

```
Label: "GitHub Notifications"
Kind: poll
URI: https://api.github.com/notifications
Verb: GET
Headers: {"Authorization": "Bearer ghp_your_token", "Accept": "application/vnd.github+json"}
Template:
  {% for n in source limit:5 %}
    <div>{{n.subject.title}}</div>
  {% endfor %}
Interval: 15 minutes
```

### Poll — Multiple URIs

```
Label: "Multi-City Weather"
Kind: poll
URIs:
  https://wttr.in/London?format=j1
  https://wttr.in/Tokyo?format=j1
Template:
  <div>London: {{source_1.current_condition[0].temp_C}}°C</div>
  <div>Tokyo: {{source_2.current_condition[0].temp_C}}°C</div>
Interval: 30 minutes
```

### Image — Dynamic Photo

```
Label: "NASA APOD"
Kind: image
URI: https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY
Verb: GET
Template:
  <img src="{{source.url}}" alt="{{source.title}}">
  <p>{{source.title}}</p>
Interval: 1 day
```

### Static — Announcement Board

```
Label: "Team Notice"
Kind: static
Body: {"message": "Meeting at 3pm", "author": "Leon"}
Template:
  <div class="{{extension.css_classes}}">
    <h1>{{source.message}}</h1>
    <p>— {{source.author}}</p>
  </div>
```

### Sensor-Aware Extension

```
Label: "Room CO₂"
Kind: static (or poll for thresholds)
Template:
  {% for sensor in sensors %}
    {% if sensor.kind == "co2" %}
      <div>CO₂: {{sensor.value}} {{sensor.unit}}</div>
    {% endif %}
  {% endfor %}
```

---

## Architecture — Key Files

| Path | Purpose |
|---|---|
| [app/aspects/extensions/](app/aspects/extensions/) | Core business logic |
| [app/aspects/extensions/fetcher.rb](app/aspects/extensions/fetcher.rb) | Single URI HTTP fetch |
| [app/aspects/extensions/multi_fetcher.rb](app/aspects/extensions/multi_fetcher.rb) | Multiple URI fetch coordinator |
| [app/aspects/extensions/parser.rb](app/aspects/extensions/parser.rb) | MIME-type-aware response parser |
| [app/aspects/extensions/renderer.rb](app/aspects/extensions/renderer.rb) | Delegates rendering by kind |
| [app/aspects/extensions/renderers/poll.rb](app/aspects/extensions/renderers/poll.rb) | Poll rendering pipeline |
| [app/aspects/extensions/renderers/image.rb](app/aspects/extensions/renderers/image.rb) | Image rendering pipeline |
| [app/aspects/extensions/renderers/static.rb](app/aspects/extensions/renderers/static.rb) | Static rendering pipeline |
| [app/aspects/extensions/contextualizer.rb](app/aspects/extensions/contextualizer.rb) | Builds Liquid template context |
| [app/aspects/extensions/screen_upserter.rb](app/aspects/extensions/screen_upserter.rb) | Creates/updates screen records |
| [app/aspects/extensions/capsule.rb](app/aspects/extensions/capsule.rb) | Success/failure container for fetched data |
| [app/jobs/extensions/screen.rb](app/jobs/extensions/screen.rb) | Per-model/device render job |
| [app/jobs/batches/extension.rb](app/jobs/batches/extension.rb) | Dispatches per-model/device jobs |
| [app/contracts/extensions/](app/contracts/extensions/) | Input validation contracts |
| [app/schemas/extensions/](app/schemas/extensions/) | Schema coercers (JSON→hash, lines→array, etc.) |
| [app/repositories/extension.rb](app/repositories/extension.rb) | Data access layer |
| [app/structs/extension.rb](app/structs/extension.rb) | Domain model with helper methods |
| [app/aspects/croner.rb](app/aspects/croner.rb) | Converts interval+unit to cron expression |
| [config/routes.rb](config/routes.rb) | Extension HTTP routes |

---

## Limitations & Constraints

- **No Ruby code execution**: Extensions are purely declarative (Liquid templates + HTTP fetch config). You cannot run arbitrary Ruby code in an extension.
- **MIME type determines parsing**: If an API doesn't return the correct `Content-Type` header, you can override it by setting an `Accept` header that Terminus will honour.
- **No webhooks**: Extensions are pull-based only — they poll on a schedule. There is no mechanism to push data into an extension from an external system.
- **Template scope**: Liquid templates only have access to the variables listed above. You cannot import external libraries or call additional HTTP endpoints from within a template.
- **Rate limiting**: The `Rack::Attack` middleware is active in production. Excessive polling could trigger rate limits.
- **Self-signed certificates**: If your API uses a self-signed cert, add its URL to `CERTIFICATE_URLS` in `.env` (see deployment guide).

---

## Future Extension Capabilities (Roadmap)

From `doc/extensions.adoc`, the planned roadmap includes:

- **Native extensions**: Built-in extensions shipped with Terminus (e.g. calendar, weather defaults)
- **Private extensions**: Extensions scoped to a specific user/account
- **Public extensions**: Shareable extensions between Terminus instances
- **Third-party plugins**: External plugin system (import/install from URL or registry)
- **Import/Export**: Ability to export an extension as a portable file and import it on another instance

These are not yet implemented. Currently all extensions are per-instance and not portable between installations.

---

## Adding a New Extension Kind (Code-Level)

If you want to add a fourth extension `kind` beyond `poll`, `image`, and `static`, you would need to touch the following files:

1. **[app/aspects/extensions/renderer.rb](app/aspects/extensions/renderer.rb)** — add a new `when` branch in the `call` method
2. **Create `app/aspects/extensions/renderers/your_kind.rb`** — implement the rendering pipeline
3. **[app/schemas/extensions/upsert.rb](app/schemas/extensions/upsert.rb)** — add the new kind to the `kind` validation rule
4. **[app/templates/extensions/](app/templates/extensions/)** — update any form templates that list available kinds
5. **Tests** — add specs under `spec/unit/terminus/aspects/extensions/renderers/` and feature specs

The existing three renderers are a good template to follow. Each renderer follows the same interface: receives an extension and context, returns `Success(content)` or `Failure(errors)`.
