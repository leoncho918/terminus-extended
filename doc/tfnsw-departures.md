# Extension: Transport for NSW Departure Times

A `poll` extension that fetches live and scheduled departure times from the TfNSW Trip Planner API and displays them on your TRMNL device. Supports all transport modes (train, metro, bus, light rail, ferry, coach) and is configurable per stop.

---

## Prerequisites

- A TfNSW Open Data Hub account and API key — register free at [opendata.transport.nsw.gov.au](https://opendata.transport.nsw.gov.au)
- Your stop ID (see below)

---

## Step 1 — Find your Stop ID

Stop IDs are numeric strings (typically 6–8 digits). Three ways to find yours:

**Option A — transportnsw.info**
Go to [transportnsw.info/stop](https://transportnsw.info/stop#/) and search for your stop. The stop ID appears in the page URL.

**Option B — Stop Finder API**
Make a GET request (you can paste this in a browser):
```
https://api.transport.nsw.gov.au/v1/tp/stop_finder?outputFormat=rapidJSON&type_sf=stop&name_sf=Central+Station&coordOutputFormat=EPSG%3A4326&TfNSWSF=true
```
Replace `Central+Station` with your stop name. The `id` field in the `locations` array is your stop ID.

**Option C — Google Maps**
Click the bus stop, train station, or ferry wharf pin on Google Maps — the stop ID appears in the info popup beneath the name.

> **Note:** Train stations have both a station-level ID (returns all platforms) and individual platform-level IDs. Use the station-level ID to see all departures, or a platform ID to show one direction only.

---

## Step 2 — Create the Extension

Go to `/extensions/new` in Terminus and fill in:

| Field | Value |
|---|---|
| **Label** | e.g. `Central Station Departures` |
| **Name** | e.g. `central_departures` |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | See below |
| **Headers** | See below |
| **Fields** | See below |
| **Template** | See Step 3 |

### URI

Replace `YOUR_STOP_ID` with your stop ID and optionally set `limit` to the maximum number of results to fetch:

```
https://api.transport.nsw.gov.au/v1/tp/departure_mon?outputFormat=rapidJSON&coordOutputFormat=EPSG%3A4326&mode=direct&type_dm=stop&name_dm=YOUR_STOP_ID&depArrMacro=dep&TfNSWDM=true&departureMonitorMacro=true&version=10.2.1.42&limit=10
```

To filter to a single transport mode, add `&motType=MODE_CODE` using one of the codes below:

| Code | Mode |
|---|---|
| `1` | Train |
| `2` | Metro |
| `4` | Light Rail |
| `5` | Bus |
| `7` | Coach |
| `9` | Ferry |

Example — buses only:
```
https://api.transport.nsw.gov.au/v1/tp/departure_mon?outputFormat=rapidJSON&coordOutputFormat=EPSG%3A4326&mode=direct&type_dm=stop&name_dm=YOUR_STOP_ID&depArrMacro=dep&TfNSWDM=true&departureMonitorMacro=true&version=10.2.1.42&limit=10&motType=5
```

### Headers

```json
{"Authorization": "apikey YOUR_API_KEY", "Accept": "application/json"}
```

### Fields

Paste this JSON into the **Fields** field. These are the values you can customise per extension instance:

```json
[
  {"keyname": "title", "default": "Departures"},
  {"keyname": "limit", "default": "5"}
]
```

- `title` — The heading shown on the display (e.g. your stop name)
- `limit` — How many departures to show on screen (independent of how many are fetched)

---

## Step 3 — Liquid Template

Paste the following into the **Template** field:

```liquid
<div class="{{extension.css_classes}}">
  <div class="view view--full">
    <div class="layout layout--col">

      <div class="title_bar">
        <span class="title">{{extension.values.title}}</span>
      </div>

      <ul class="list">
        {% assign max = extension.values.limit | plus: 0 %}
        {% for event in source.stopEvents limit: max %}

          {% assign planned = event.departureTimePlanned | slice: 11, 5 %}
          {% assign estimated = event.departureTimeEstimated | slice: 11, 5 %}
          {% assign product_class = event.transportation.product.class %}

          {% if product_class == 1 %}
            {% assign mode = "Train" %}
          {% elsif product_class == 2 %}
            {% assign mode = "Metro" %}
          {% elsif product_class == 4 %}
            {% assign mode = "Light Rail" %}
          {% elsif product_class == 5 %}
            {% assign mode = "Bus" %}
          {% elsif product_class == 7 %}
            {% assign mode = "Coach" %}
          {% elsif product_class == 9 %}
            {% assign mode = "Ferry" %}
          {% elsif product_class == 11 %}
            {% assign mode = "School Bus" %}
          {% else %}
            {% assign mode = event.transportation.product.name %}
          {% endif %}

          <li class="list__item">
            <span class="meta">{{mode}} · {{event.transportation.number}}</span>
            <span class="content">{{event.transportation.destination.name}}</span>
            <span class="meta">
              {% if estimated != "" and estimated != planned %}
                {{planned}} › {{estimated}}
              {% else %}
                {{planned}}
              {% endif %}
            </span>
          </li>

        {% endfor %}
      </ul>

    </div>
  </div>
</div>
```

### What the template does

- Extracts the `HH:MM` time from the departure timestamp using `slice: 11, 5`
- Maps the product class code to a human-readable transport mode label
- Shows the route number and destination for each departure
- If a real-time estimated time differs from the planned time, both are shown (`planned › estimated`) to indicate a delay
- Limits the displayed rows to `extension.values.limit`

---

## Step 4 — Set a Schedule and Build

1. Set the **Interval** to how often you want departures to refresh — every **5 minutes** is a reasonable balance between freshness and API usage
2. Assign it to your device model under **Build Matrix**
3. Click **Build** to render and push the screen

---

## Customising for Multiple Stops

The stop ID is baked into the URI, so each stop needs its own extension instance. Use the **Clone** button on an existing extension to copy all settings — then just update the URI with the new stop ID and change the `title` field value.

---

## Troubleshooting

**No departures shown**
Use the **Poll** button on the extension page to inspect the raw JSON Terminus is receiving. Check that `stopEvents` is present and not empty. If the array is empty, the stop ID may be wrong or there are no upcoming services.

**Times look wrong (off by 10–11 hours)**
The API returns times in UTC (`Z` suffix). The template extracts `HH:MM` by character position — if times appear in UTC rather than local AEST/AEDT, the API is not returning a timezone offset. In this case, add `+10` or `+11` hours to the displayed time mentally, or raise it as a note when testing. Most production TfNSW API responses include the local timezone offset, so times should display correctly.

**HTTP 401 error**
Your API key is missing or incorrect. Double-check the `Authorization` header format: it must be `apikey YOUR_KEY` (not `Bearer`).

**HTTP 403 error**
You've hit the rate limit (5 requests/second or 60,000/day on the free tier). Reduce your refresh interval.

**`departureTimeEstimated` never shows**
Real-time data is only available when `isRealtimeControlled` is `true` for a stop event. Some stops, routes, or times of day may not have real-time data — the template falls back to the planned time automatically.

---

## API Reference Summary

| Detail | Value |
|---|---|
| Base URL | `https://api.transport.nsw.gov.au/v1/tp/departure_mon` |
| Auth header | `Authorization: apikey YOUR_KEY` |
| Free daily quota | 60,000 requests |
| Burst rate limit | 5 requests/second |
| Response key | `stopEvents` array |
| Planned time field | `departureTimePlanned` (ISO 8601) |
| Estimated time field | `departureTimeEstimated` (ISO 8601, real-time only) |
| Route number field | `transportation.number` |
| Destination field | `transportation.destination.name` |
| Transport type field | `transportation.product.class` (integer code) |
