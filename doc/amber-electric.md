# Extension: Amber Electric Live Prices

A `poll` extension that fetches live electricity prices, feed-in tariff prices, and forecasted prices from the Amber Electric API. Displays current buy/sell prices, price descriptor, upcoming interval forecasts, and spike warnings — including feed-in tariff spike prices.

---

## Prerequisites

- An active Amber Electric account
- An Amber API token — go to [app.amber.com.au/developers](https://app.amber.com.au/developers), enable Developer Mode, and generate a token (format: `psk_...`)
- Your site ID (see Step 1 below)

---

## Step 1 — Find Your Site ID

Your site ID is required for the price endpoint. It is a static value that does not change. Retrieve it once with a single API call:

```bash
curl -H "Authorization: Bearer psk_YOUR_TOKEN" https://api.amber.com.au/v1/sites
```

The response looks like:
```json
[
  {
    "id": "01J23BAP2SFA218BMV8A73Y9Z9",
    "nmi": "XXXXXXXXXX",
    "channels": [
      { "identifier": "E1", "type": "general" },
      { "identifier": "B1", "type": "feedIn" }
    ],
    "status": "active"
  }
]
```

Copy the `id` value — this is your site ID.

---

## Step 2 — Create the Extension

Go to `/extensions/new` in Terminus and fill in:

| Field | Value |
|---|---|
| **Label** | `Amber Electric` |
| **Name** | `amber_electric` |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | See below |
| **Headers** | See below |
| **Fields** | See below |
| **Template** | See Step 3 |

### URI

Replace `YOUR_SITE_ID` with the site ID from Step 1. The `next=8` parameter fetches 8 upcoming 30-minute intervals (4 hours of forecast):

```
https://api.amber.com.au/v1/sites/YOUR_SITE_ID/prices/current?next=8
```

### Headers

```json
{"Authorization": "Bearer psk_YOUR_TOKEN", "Accept": "application/json"}
```

### Fields

```json
[
  {"keyname": "forecasts", "default": "4"}
]
```

- `forecasts` — number of upcoming forecast intervals to show on screen (default 4 = 2 hours)

---

## Step 3 — Liquid Template

```liquid
{% comment %} Extract current and forecast intervals by channel {% endcomment %}
{% assign general_now = nil %}
{% assign feedin_now = nil %}
{% assign upcoming_spike = false %}
{% assign feedin_spike_price = nil %}

{% for interval in source %}
  {% if interval.type == "CurrentInterval" %}
    {% if interval.channelType == "general" %}
      {% assign general_now = interval %}
    {% elsif interval.channelType == "feedIn" %}
      {% assign feedin_now = interval %}
    {% endif %}
  {% endif %}
  {% if interval.type == "ForecastInterval" and interval.channelType == "general" %}
    {% if interval.spikeStatus == "spike" or interval.spikeStatus == "potential" %}
      {% assign upcoming_spike = true %}
    {% endif %}
  {% endif %}
  {% if interval.type == "ForecastInterval" and interval.channelType == "feedIn" %}
    {% if interval.descriptor == "spike" and feedin_spike_price == nil %}
      {% assign feedin_spike_price = interval.perKwh | abs | round: 1 %}
    {% endif %}
  {% endif %}
{% endfor %}

{% assign buy_price = general_now.perKwh | round: 1 %}
{% assign sell_price = feedin_now.perKwh | abs | round: 1 %}
{% assign descriptor = general_now.descriptor %}
{% assign spike_status = general_now.spikeStatus %}
{% assign max_forecasts = extension.values.forecasts | plus: 0 %}

<div class="{{extension.css_classes}}">
  <div class="view view--full">
    <div class="layout layout--col">

      <div class="title_bar">
        <span class="title">Amber Electric</span>
        {% if general_now.estimate %}<span class="label">est.</span>{% endif %}
      </div>

      {% comment %} Active spike banner {% endcomment %}
      {% if spike_status == "spike" %}
        <div class="layout layout--row layout--justify-center">
          <span class="title">!! PRICE SPIKE ACTIVE !!</span>
        </div>
      {% elsif spike_status == "potential" or upcoming_spike %}
        <div class="layout layout--row layout--justify-center">
          <span class="label">Warning: spike forecast ahead</span>
        </div>
      {% endif %}

      {% comment %} Current buy and sell prices {% endcomment %}
      <div class="layout layout--row layout--gap">

        <div class="layout layout--col layout--align-center">
          <span class="label">Buy</span>
          <span class="value">{{buy_price}}c</span>
          <span class="label">per kWh</span>
          <span class="label">{{descriptor}}</span>
        </div>

        <div class="layout layout--col layout--align-center">
          <span class="label">Sell</span>
          <span class="value">{{sell_price}}c</span>
          <span class="label">per kWh</span>
          {% if feedin_now.spikeStatus == "spike" %}
            <span class="label">Feed-in Spike!</span>
          {% endif %}
        </div>

      </div>

      {% comment %} Feed-in spike price alert {% endcomment %}
      {% if feedin_spike_price != nil %}
        <span class="label">Feed-in spike forecast: {{feedin_spike_price}}c/kWh</span>
      {% endif %}

      {% comment %} Renewables percentage {% endcomment %}
      <span class="label">{{general_now.renewables | round: 0}}% renewables</span>

      {% comment %} Forecast intervals — general channel only {% endcomment %}
      <div class="title_bar">
        <span class="label">Forecast</span>
      </div>

      <ul class="list">
        {% assign forecast_count = 0 %}
        {% for interval in source %}
          {% if interval.type == "ForecastInterval" and interval.channelType == "general" %}
            {% if forecast_count < max_forecasts %}
              {% assign forecast_count = forecast_count | plus: 1 %}
              {% assign f_time = interval.nemTime | slice: 11, 5 %}
              {% assign f_price = interval.perKwh | round: 1 %}
              <li class="list__item">
                <span class="meta">{{f_time}}</span>
                <span class="content">{{f_price}}c/kWh</span>
                <span class="meta">
                  {{interval.descriptor}}{% if interval.spikeStatus != "none" %} !!{% endif %}
                </span>
              </li>
            {% endif %}
          {% endif %}
        {% endfor %}
      </ul>

    </div>
  </div>
</div>
```

---

## What the Template Displays

| Section | Description |
|---|---|
| **Buy price** | Current retail consumption price in cents/kWh (GST-inclusive) |
| **Sell price** | Current feed-in tariff in cents/kWh (absolute value of the negative `perKwh` on the feed-in channel) |
| **Descriptor** | Price category: `extremelyLow`, `veryLow`, `low`, `neutral`, `high`, or `spike` |
| **est.** badge | Shown when the current price is still an estimate (locks in ~5 min before interval end) |
| **Spike active banner** | Shown prominently when `spikeStatus == "spike"` on the current interval |
| **Spike warning banner** | Shown when `spikeStatus == "potential"` or a spike is forecast in upcoming intervals |
| **Feed-in spike alert** | Shows the forecasted feed-in tariff spike price when one is coming — a good time to export |
| **Renewables %** | Percentage of grid power from renewable sources for the current interval |
| **Forecast list** | Next N intervals (configurable via the `forecasts` field) with time, price, and descriptor |

---

## Understanding the Data

### Price units

All prices from the API are in **cents per kWh, GST-inclusive**. What you see is what you pay (or earn).

- `28.45` → 28.45c/kWh = $0.2845/kWh
- A feed-in `perKwh` of `-13.58` → you earn 13.58c for every kWh you export

### Price descriptors

| Descriptor | Meaning |
|---|---|
| `extremelyLow` | Very cheap — great time to run appliances |
| `veryLow` | Below average |
| `low` | Slightly below average |
| `neutral` | Around the regulated benchmark (VMO/DMO) |
| `high` | Above average — consider reducing consumption |
| `spike` | Price spike — prices can reach up to ~$19/kWh |

### Spike status

| Value | Meaning |
|---|---|
| `none` | No spike |
| `potential` | Spike may occur during this interval |
| `spike` | Spike is currently active |

`potential` and `spike` can also appear on `ForecastInterval` objects, giving advance warning before a spike arrives. The template surfaces both.

### Feed-in tariff spikes

Because Amber passes through the live wholesale price for exports, feed-in tariffs spike at the same time as consumption prices. A feed-in spike is a valuable export opportunity — the template detects any upcoming feed-in spike in the forecast window and shows the price so you can plan to export (e.g. via a battery).

### Forecast times

The `nemTime` field on each forecast interval is in Australian Eastern time (`+10:00` or `+11:00` DST). The template extracts `HH:MM` using `slice: 11, 5`, which gives the correct local time.

---

## Schedule

Amber prices update every **30 minutes** on the half-hour. A refresh interval of **5 minutes** gives you timely updates while staying comfortably within the API rate limit of 50 requests per 5-minute window.

---

## Troubleshooting

**No data / blank screen**
Use the **Poll** button on the extension page to inspect the raw JSON. If the response is empty or an error, check your API token and site ID.

**`perKwh` shows as negative for buy price**
This should not happen on the `general` channel, but if it does, use `| abs` in the template.

**Spike warning never clears**
The `upcoming_spike` flag checks all forecast intervals. If a spike is forecast in the next 4 hours (8 intervals), the warning remains. Reduce `next=8` in the URI to a smaller window if you want a shorter lookahead.

**Feed-in spike price not shown**
Your site may not have a `feedIn` channel, or there is no spike forecast in the current window. Verify your site has a `B1`/feed-in channel in the `/sites` response.

**Token rejected (401)**
Amber API tokens are prefixed with `psk_`. Ensure the full token is in the Authorization header as `Bearer psk_your_token_here`.

---

## API Reference Summary

| Detail | Value |
|---|---|
| Base URL | `https://api.amber.com.au/v1` |
| Auth header | `Authorization: Bearer psk_YOUR_TOKEN` |
| Sites endpoint | `GET /v1/sites` |
| Prices endpoint | `GET /v1/sites/{siteId}/prices/current?next=N` |
| Rate limit | 50 requests per 5-minute window |
| Price unit | Cents per kWh, GST-inclusive |
| Interval length | 30 minutes |
| Feed-in channel | `channelType: "feedIn"` — `perKwh` is negative |
| Spike field | `spikeStatus`: `none`, `potential`, `spike` |
| Descriptor field | `descriptor`: `extremelyLow` → `spike` |
