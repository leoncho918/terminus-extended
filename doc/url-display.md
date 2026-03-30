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

---

## Example: Bakery Pickup Display

A worked example using a bakery order system that displays today's pickup slots on a TRMNL e-ink screen.

### Endpoint

```
GET /api/pickup/trmnl-display
```

**Authentication:** API key is required. Generate one from **System Settings > TRMNL Display** in the bakery admin panel. Pass it as a query parameter or header:

- Query: `?key=YOUR_KEY`
- Header: `x-api-key: YOUR_KEY`

Returns `401` if no key has been generated or the provided key doesn't match.

### Response

```json
{
  "content": "<style>.pickup-grid{...}</style><div class=\"screen screen--og\"><div class=\"view view--full\"><div class=\"layout layout--col\">...</div></div></div>"
}
```

The `content` field contains TRMNL-native markup using the framework's CSS classes (`screen`, `view`, `layout`, `title_bar`, `title`, `label`, `meta`) with minimal custom CSS for the pickup slot grid. It renders a black-and-white grid of numbered pickup slots showing status (Active/Collected/Available), order counts, prices, and payment status.

### Extension config

| Field | Value |
|---|---|
| **Label** | `Bakery Pickups` |
| **Name** | `bakery_pickups` |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | `https://your-bakery-app.com/api/pickup/trmnl-display?key=your-key` |
| **Headers** | `{"Accept": "application/json"}` |

### Template

```liquid
{{source.content}}
```

### Schedule

Set to 15 minutes or shorter, depending on how frequently pickup status changes throughout the day.

---

## TRMNL Display API

This is the endpoint your TRMNL device polls to retrieve its current screen. It is separate from the extension system above — extensions produce screens, and this API serves them to the device.

### Request

```
GET /api/display
```

**Required Headers:**

| Header | Description |
|---|---|
| `ID` | The MAC address of your device |

**Optional Headers:**

| Header | Description |
|---|---|
| `ACCESS_TOKEN` | The device API key (empty string if not set) |
| `BATTERY_VOLTAGE` | Remaining battery level (float, usually 0.0–4.1) |
| `FW_VERSION` | Firmware version (e.g. `1.2.3`) |
| `HEIGHT` | Device screen height in pixels (e.g. `480`) |
| `WIDTH` | Device screen width in pixels (e.g. `800`) |
| `MODEL` | Generic device model name |
| `REFRESH_RATE` | Current refresh rate saved on the device |
| `RSSI` | WiFi signal strength (usually -100 to 100) |
| `USER_AGENT` | Device name (usually the ESP32 board name) |

**Example:**

```bash
curl "https://localhost:2443/api/display" \
     -H 'ID: AA:BB:CC:DD:EE:FF' \
     -H 'Content-Type: application/json'
```

### Response

```json
{
  "filename": "demo.bmp",
  "firmware_url": "http://localhost:2443/assets/firmware/1.4.8.bin",
  "firmware_version": "1.4.8",
  "image_url": "https://localhost:2443/assets/screens/A1B2C3D4E5F6/demo.bmp",
  "image_url_timeout": 0,
  "refresh_rate": 130,
  "reset_firmware": false,
  "special_function": "sleep",
  "update_firmware": false
}
```

| Field | Description |
|---|---|
| `image_url` | URL of the rendered screen image for the device to display |
| `refresh_rate` | Seconds until the device should poll again |
| `filename` | Name of the image file |
| `update_firmware` | Whether the device should update its firmware |
| `firmware_url` | URL to the firmware binary (if updating) |
| `firmware_version` | Target firmware version (if updating) |
| `reset_firmware` | Whether the device should reset |
| `special_function` | Special device function (e.g. `sleep`, or empty string) |
| `image_url_timeout` | Timeout for fetching the image URL (0 = default) |

### Behavior

- If the device MAC address is not found, the device is **auto-registered** and assigned a default name.
- If `ACCESS_TOKEN` is provided and does not match the device's stored API key, a `401` error is returned.
- If no playlist is assigned to the device, a default image is returned.
- The device's `lastSeen` timestamp is updated on every request.
