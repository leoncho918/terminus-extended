# Extension: Sigenergy Battery & Solar

A `poll` extension that displays live battery state of charge, solar production, grid import/export, and home consumption from your Sigenergy system.

Because the Sigenergy API uses OAuth2 (tokens expire hourly), Terminus cannot call it directly. The solution is a small local proxy server — added to your existing Python project — that handles authentication and exposes a simple JSON endpoint Terminus can poll.

---

## How It Works

```
TRMNL Device → Terminus → Local Proxy (Python) → Sigenergy Cloud API
```

Your existing `sigen.py` already handles auth and token refresh. The proxy just adds a single HTTP endpoint on top of it.

---

## Step 1 — Add the Proxy Server to Your Sigen Project

Create a new file `terminus_server.py` in your Sigen project directory (`C:\Users\leonc\Documents\Github\Sigen project\`):

```python
#!/usr/bin/env python3
"""
Terminus proxy server — exposes Sigenergy energy flow data as a simple
JSON endpoint for the TRMNL Terminus extension to poll.

Run alongside your existing Sigen project:
    python terminus_server.py
"""

import asyncio
import os
from aiohttp import web
from sigen import Sigen  # your existing Sigen class

# ── Configuration ─────────────────────────────────────────────────────────────
SIGEN_USERNAME   = os.getenv("SIGEN_USERNAME")
SIGEN_PASSWORD   = os.getenv("SIGEN_PASSWORD")
SIGEN_STATION_ID = os.getenv("SIGEN_STATION_ID")
SIGEN_REGION     = os.getenv("SIGEN_REGION", "aus")
PORT             = int(os.getenv("TERMINUS_PROXY_PORT", "8099"))
# ──────────────────────────────────────────────────────────────────────────────

sigen: Sigen = None


async def energy_handler(request: web.Request) -> web.Response:
    try:
        response = await sigen.get_energy_flow()
        data = response.get("data", {})

        battery_power = data.get("batteryPower", 0)
        grid_power    = data.get("buySellPower", 0)

        return web.json_response({
            "battery_soc":       data.get("batterySoc", 0),
            "battery_power":     round(battery_power, 2),
            "battery_charging":  battery_power > 0,
            "solar_power":       round(data.get("pvPower", 0), 2),
            "solar_daily_kwh":   round(data.get("pvDayNrg", 0), 1),
            "grid_power":        round(abs(grid_power), 2),
            "grid_exporting":    grid_power < 0,
            "home_load":         round(data.get("loadPower", 0), 2),
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=500)


async def main():
    global sigen
    sigen = Sigen(
        username=SIGEN_USERNAME,
        password=SIGEN_PASSWORD,
        station_id=SIGEN_STATION_ID,
        region=SIGEN_REGION,
    )

    app = web.Application()
    app.router.add_get("/energy", energy_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    print(f"Sigenergy proxy running → http://0.0.0.0:{PORT}/energy")
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
```

The response this serves looks like:

```json
{
  "battery_soc": 85,
  "battery_power": 2.1,
  "battery_charging": true,
  "solar_power": 5.2,
  "solar_daily_kwh": 15.6,
  "grid_power": 0.5,
  "grid_exporting": true,
  "home_load": 3.1
}
```

> **Note on `grid_power`:** The raw Sigenergy field (`buySellPower`) is negative when exporting and positive when importing. The proxy converts it to an absolute value and adds a separate `grid_exporting` boolean to keep the template simple.

---

## Step 2 — Run the Proxy

Set your credentials as environment variables (or hardcode them for now) and run:

```bash
export SIGEN_USERNAME="your@email.com"
export SIGEN_PASSWORD="yourpassword"
export SIGEN_STATION_ID="your_station_id"
export SIGEN_REGION="aus"

python terminus_server.py
```

Verify it works:

```bash
curl http://localhost:8099/energy
```

You should see the JSON response with live data.

### Running on Unraid

To run this permanently on your Unraid server, add it to your Sigen project's `compose.yml` (if you have one), or create a simple one:

```yaml
services:
  sigen-proxy:
    build: .
    environment:
      SIGEN_USERNAME: your@email.com
      SIGEN_PASSWORD: yourpassword
      SIGEN_STATION_ID: your_station_id
      SIGEN_REGION: aus
      TERMINUS_PROXY_PORT: 8099
    ports:
      - "8099:8099"
    restart: unless-stopped
```

Or run it directly via Unraid's User Scripts plugin on startup:

```bash
cd /path/to/sigen-project && python terminus_server.py &
```

---

## Step 3 — Create the Extension in Terminus

Go to `/extensions/new` and fill in:

| Field | Value |
|---|---|
| **Label** | `Sigenergy` |
| **Name** | `sigenergy` |
| **Kind** | `poll` |
| **Verb** | `GET` |
| **URI** | `http://YOUR_UNRAID_IP:8099/energy` |
| **Headers** | `{"Accept": "application/json"}` |
| **Fields** | See below |

### Fields

```json
[
  {"keyname": "title", "default": "Energy"},
  {"keyname": "low_soc_threshold", "default": "20"}
]
```

- `title` — heading shown on the display
- `low_soc_threshold` — battery % below which a low-battery warning is shown (default 20%)

---

## Step 4 — Liquid Template

```liquid
{% assign soc       = source.battery_soc %}
{% assign b_power   = source.battery_power %}
{% assign b_charge  = source.battery_charging %}
{% assign solar     = source.solar_power %}
{% assign solar_day = source.solar_daily_kwh %}
{% assign grid      = source.grid_power %}
{% assign exporting = source.grid_exporting %}
{% assign load      = source.home_load %}
{% assign low_soc   = extension.values.low_soc_threshold | plus: 0 %}

{% if b_charge %}
  {% assign batt_status = "Charging" %}
{% elsif b_power == 0 %}
  {% assign batt_status = "Idle" %}
{% else %}
  {% assign batt_status = "Discharging" %}
{% endif %}

{% if exporting %}
  {% assign grid_status = "Exporting" %}
{% elsif grid == 0 %}
  {% assign grid_status = "Balanced" %}
{% else %}
  {% assign grid_status = "Importing" %}
{% endif %}

<div class="{{extension.css_classes}}">
  <div class="view view--full">
    <div class="layout layout--col">

      <div class="title_bar">
        <span class="title">{{extension.values.title}}</span>
      </div>

      {% if soc < low_soc %}
        <div class="layout layout--row layout--justify-center">
          <span class="label">Low battery — {{soc}}%</span>
        </div>
      {% endif %}

      <div class="layout layout--row">

        <div class="layout layout--col layout--align-center">
          <span class="label">Battery</span>
          <span class="value">{{soc}}%</span>
          <span class="label">{{batt_status}}</span>
          <span class="meta">{{b_power}} kW</span>
        </div>

        <div class="layout layout--col layout--align-center">
          <span class="label">Solar</span>
          <span class="value">{{solar}} kW</span>
          <span class="meta">{{solar_day}} kWh today</span>
        </div>

      </div>

      <div class="layout layout--row">

        <div class="layout layout--col layout--align-center">
          <span class="label">Grid</span>
          <span class="value">{{grid_status}}</span>
          <span class="meta">{{grid}} kW</span>
        </div>

        <div class="layout layout--col layout--align-center">
          <span class="label">Home</span>
          <span class="value">{{load}} kW</span>
        </div>

      </div>

    </div>
  </div>
</div>
```

---

## What the Template Displays

| Section | Description |
|---|---|
| **Battery %** | Live state of charge from `batterySoc` |
| **Battery status** | Charging / Discharging / Idle based on `batteryPower` direction |
| **Battery power** | kW currently flowing in or out of the battery |
| **Solar** | Live PV generation in kW |
| **Solar daily** | kWh generated today (`pvDayNrg`) |
| **Grid status** | Exporting / Importing / Balanced |
| **Grid power** | kW currently flowing to/from the grid |
| **Home load** | Total home consumption in kW |
| **Low battery warning** | Shown when SOC drops below the configurable threshold |

---

## Schedule

The Sigenergy app polls energy flow every **15 seconds** internally. For a display, every **1–5 minutes** is more than sufficient and avoids overloading the cloud API.

---

## Troubleshooting

**`connection refused` on the URI**
The proxy server isn't running. Check it started correctly and the port matches what's in the Terminus extension URI.

**`error` field in the JSON response**
The proxy reached Sigenergy but the API call failed — usually a token issue. Check your credentials and that the station ID is correct. The existing `sigen.py` handles token refresh automatically as long as the proxy keeps running.

**Solar shows `0` at night**
Expected — `pvPower` is `0` when there is no generation. The template will display `0.0 kW` correctly.

**Battery power shows as negative**
The proxy returns `battery_power` as the raw `batteryPower` value from Sigenergy (positive = charging, negative = discharging). The template uses it directly. If you want to always show an absolute value, change `{{b_power}}` to `{{b_power | abs}}` in the template.

---

## Data Field Reference

| Field in JSON | Source in Sigenergy API | Unit | Notes |
|---|---|---|---|
| `battery_soc` | `batterySoc` | % | 0–100 |
| `battery_power` | `batteryPower` | kW | Positive = charging, negative = discharging |
| `battery_charging` | Derived | boolean | `true` when `batteryPower > 0` |
| `solar_power` | `pvPower` | kW | Real-time generation |
| `solar_daily_kwh` | `pvDayNrg` | kWh | Resets at midnight |
| `grid_power` | `abs(buySellPower)` | kW | Absolute value — see `grid_exporting` for direction |
| `grid_exporting` | Derived | boolean | `true` when `buySellPower < 0` |
| `home_load` | `loadPower` | kW | Total home consumption |

---

## Future Alternatives — Local Modbus TCP

> **Status:** Modbus TCP is not yet enabled on this SigenStor. Waiting on installer to enable it. Once done, this is the preferred approach over the cloud proxy above.

Sigenergy devices expose **Modbus TCP on port 502** directly on the local network. This is the cleanest integration path — no OAuth, no token refresh, works without internet.

### How to enable

In the MySigen app (requires installer-level access):
> System → Devices → SigenStor → Operation → Parameter Settings → ModBus Settings → enable **Local ModBus TCP**

Official instructions: [support.sigenergy.com — noticeId=1011](https://support.sigenergy.com/problem-details?noticeId=1011)

Verify it's active after enabling:
```bash
telnet YOUR_INVERTER_IP 502
```

### Key Modbus registers (slave ID 247, plant level)

| Metric | Register | Type | Scale | Unit | Notes |
|---|---|---|---|---|---|
| Battery SOC | `30014` | uint16 | ×0.1 | % | 0–100% |
| Solar / PV power | `30035` | int32 | ×0.001 | kW | Total plant PV |
| Battery power | `30037` | int32 | ×0.001 | kW | +ve = charging, −ve = discharging |
| Grid power | `30005` | int32 | ×0.001 | kW | +ve = importing, −ve = exporting |
| Battery SOH | `30087` | uint16 | ×0.1 | % | State of health |
| EMS work mode | `30003` | uint16 | — | — | 0=self-consumption, 1=AI, 2=TOU |
| On/off-grid status | `30009` | uint16 | — | — | 0=on-grid, 1=off-grid |

> **Home load** is not a dedicated register in current firmware. Derive it as:
> `home_load = solar_power + grid_power − battery_power`

### Replacement proxy server (pymodbus)

Once Modbus is enabled, replace `terminus_server.py` with this simpler version — no credentials, no token management:

```python
#!/usr/bin/env python3
"""
Terminus Modbus proxy — reads Sigenergy data locally via Modbus TCP.
Requires: pip install pymodbus aiohttp
"""

import asyncio
import os
import struct
from aiohttp import web
from pymodbus.client import AsyncModbusTcpClient

INVERTER_IP = os.getenv("INVERTER_IP", "192.168.1.x")
PORT        = int(os.getenv("TERMINUS_PROXY_PORT", "8099"))
SLAVE_ID    = 247  # plant-level data


def decode_int32(registers) -> float:
    """Combine two uint16 registers into a signed int32."""
    raw = struct.pack(">HH", registers[0], registers[1])
    return struct.unpack(">i", raw)[0]


async def read_energy(client: AsyncModbusTcpClient) -> dict:
    soc_r    = await client.read_input_registers(30014, count=1, slave=SLAVE_ID)
    solar_r  = await client.read_input_registers(30035, count=2, slave=SLAVE_ID)
    batt_r   = await client.read_input_registers(30037, count=2, slave=SLAVE_ID)
    grid_r   = await client.read_input_registers(30005, count=2, slave=SLAVE_ID)

    soc         = soc_r.registers[0] * 0.1
    solar_kw    = decode_int32(solar_r.registers) * 0.001
    battery_kw  = decode_int32(batt_r.registers) * 0.001
    grid_kw     = decode_int32(grid_r.registers) * 0.001
    home_load   = round(solar_kw + grid_kw - battery_kw, 2)

    return {
        "battery_soc":      round(soc, 1),
        "battery_power":    round(battery_kw, 2),
        "battery_charging": battery_kw > 0,
        "solar_power":      round(solar_kw, 2),
        "grid_power":       round(abs(grid_kw), 2),
        "grid_exporting":   grid_kw < 0,
        "home_load":        home_load,
    }


modbus_client: AsyncModbusTcpClient = None


async def energy_handler(request: web.Request) -> web.Response:
    try:
        data = await read_energy(modbus_client)
        return web.json_response(data)
    except Exception as e:
        return web.json_response({"error": str(e)}, status=500)


async def main():
    global modbus_client
    modbus_client = AsyncModbusTcpClient(INVERTER_IP, port=502)
    await modbus_client.connect()

    app = web.Application()
    app.router.add_get("/energy", energy_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    print(f"Sigenergy Modbus proxy running → http://0.0.0.0:{PORT}/energy")
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
```

The Terminus extension URI and Liquid template stay exactly the same — only the proxy changes.

---

### Option B — Home Assistant (if you run HA)

The [Sigenergy-Local-Modbus](https://github.com/TypQxQ/Sigenergy-Local-Modbus) HACS integration reads Modbus TCP and exposes 250+ entities in Home Assistant. If you run HA, Terminus can query the HA REST API instead of running a custom proxy:

```
http://YOUR_HA_IP:8123/api/states/sensor.sigenergy_battery_soc
```

Header required: `Authorization: Bearer YOUR_HA_LONG_LIVED_TOKEN`

This eliminates the need for any custom Python at all.

---

### Option C — sigenergy2mqtt (Docker)

[sigenergy2mqtt](https://github.com/seud0nym/sigenergy2mqtt) is a Docker container that reads Modbus TCP and publishes to an MQTT broker, with Home Assistant auto-discovery support. Useful if you want the data accessible to multiple systems at once.

---

### Official Modbus documentation

- Modbus Protocol V2.7 (May 2025 — most current): [sigenergy.com/uploads/…](https://www.sigenergy.com/uploads/us_download/1755488219226583.pdf)
- Modbus Protocol V1.7 (April 2024): [pdf.tritec.info/…](https://pdf.tritec.info/pdf/produkte/Sigenergy_Modbus_Protocol_20240409_EN.pdf)
