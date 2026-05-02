/*
  ESP32 WiFi + MUX server
  - Tries STA (join existing WiFi) first
  - Falls back to SoftAP (ESP32 creates its own network)
  - Hosts /status, /c0-c3 and /mux-all JSON endpoints
  - Hosts a live dashboard at /
*/

#include <WiFi.h>
#include <WebServer.h>

// STA credentials (ESP32 tries this first)
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// SoftAP fallback credentials
const char* AP_SSID = "YOUR_SOFTAP_SSID";
const char* AP_PASSWORD = "YOUR_SOFTAP_PASSWORD";

WebServer server(80);

const int LED_PIN = 4; // External/status LED pin (kept separate from mux EN)
const int MUX_EN_PIN = 2;
const int MUX_S0_PIN = 12;
const int MUX_S1_PIN = 14;
const int MUX_S2_PIN = 27;
const int MUX_S3_PIN = 26;
const int MUX_SIG_PIN = 34; // ADC1 input, works with WiFi active

unsigned long lastBlinkMs = 0;
bool ledState = false;
bool staConnected = false;
bool apStarted = false;

String activeIP() {
  if (staConnected) return WiFi.localIP().toString();
  if (apStarted) return WiFi.softAPIP().toString();
  return "0.0.0.0";
}

void handleRoot() {
  const char* page = R"HTML(
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>ESP32 MUX Dashboard</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background:#111; color:#eee; }
    .card { background:#1b1b1b; border:1px solid #333; border-radius:10px; padding:14px; margin-bottom:14px; }
    .row { display:flex; gap:10px; flex-wrap:wrap; }
    .chip { background:#222; border:1px solid #3a3a3a; padding:8px 12px; border-radius:999px; }
    .grid { display:grid; grid-template-columns: repeat(4, minmax(100px, 1fr)); gap:8px; }
    .cell { background:#1f1f1f; border:1px solid #333; border-radius:8px; padding:8px; }
    .k { color:#9ecbff; font-size:12px; }
    .v { font-size:20px; font-weight:bold; }
    a { color:#9ecbff; }
  </style>
</head>
<body>
  <h2>ESP32 MUX Dashboard</h2>
  <div class="card">
    <div class="row" id="statusRow">
      <div class="chip">Loading status...</div>
    </div>
  </div>
  <div class="card">
    <div class="grid" id="muxGrid"></div>
  </div>
  <div class="card">
    Endpoints:
    <a href="/status" target="_blank">/status</a>,
    <a href="/c0-c3" target="_blank">/c0-c3</a>,
    <a href="/mux-all" target="_blank">/mux-all</a>
  </div>
  <script>
    function renderStatus(s) {
      const row = document.getElementById('statusRow');
      row.innerHTML = '';
      const items = [
        ['mode', s.mode],
        ['ssid', s.ssid],
        ['ip', s.ip],
        ['rssi', s.rssi],
        ['stations', s.stations]
      ];
      for (const [k, v] of items) {
        const d = document.createElement('div');
        d.className = 'chip';
        d.textContent = k + ': ' + v;
        row.appendChild(d);
      }
    }

    function renderMux(m) {
      const grid = document.getElementById('muxGrid');
      grid.innerHTML = '';
      for (let i = 0; i < 16; i++) {
        const key = 'c' + i;
        const cell = document.createElement('div');
        cell.className = 'cell';
        cell.innerHTML = '<div class="k">' + key.toUpperCase() + '</div><div class="v">' + (m[key] ?? '-') + '</div>';
        grid.appendChild(cell);
      }
    }

    async function tick() {
      try {
        const [sRes, mRes] = await Promise.all([fetch('/status'), fetch('/mux-all')]);
        renderStatus(await sRes.json());
        renderMux(await mRes.json());
      } catch (e) {}
    }
    tick();
    setInterval(tick, 500);
  </script>
</body>
</html>
  )HTML";
  server.send(200, "text/html", page);
}

void handleStatus() {
  String body = "{";
  body += "\"connected\":";
  body += (staConnected || apStarted) ? "true" : "false";
  body += ",\"mode\":\"";
  body += staConnected ? "sta" : (apStarted ? "ap" : "none");
  body += "\"";
  body += ",\"ssid\":\"";
  body += staConnected ? WiFi.SSID() : (apStarted ? String(AP_SSID) : "");
  body += "\"";
  body += ",\"ip\":\"" + activeIP() + "\"";
  body += ",\"rssi\":";
  body += staConnected ? String(WiFi.RSSI()) : String(0);
  body += ",\"stations\":";
  body += apStarted ? String(WiFi.softAPgetStationNum()) : String(0);
  body += "}";
  server.send(200, "application/json", body);
}

void selectMuxChannel(int channel) {
  if (channel < 0 || channel > 15) {
    digitalWrite(MUX_EN_PIN, HIGH); // disable mux on invalid input
    return;
  }

  digitalWrite(MUX_EN_PIN, LOW); // enable mux
  digitalWrite(MUX_S0_PIN, (channel & 0x01) ? HIGH : LOW);
  digitalWrite(MUX_S1_PIN, (channel & 0x02) ? HIGH : LOW);
  digitalWrite(MUX_S2_PIN, (channel & 0x04) ? HIGH : LOW);
  digitalWrite(MUX_S3_PIN, (channel & 0x08) ? HIGH : LOW);
}

int readMuxChannel(int channel) {
  selectMuxChannel(channel);
  delayMicroseconds(120); // settle time after channel switch
  return analogRead(MUX_SIG_PIN);
}

void handleC0ToC3() {
  int c0 = readMuxChannel(0);
  int c1 = readMuxChannel(1);
  int c2 = readMuxChannel(2);
  int c3 = readMuxChannel(3);

  char payload[96];
  snprintf(
    payload,
    sizeof(payload),
    "{\"c0\":%d,\"c1\":%d,\"c2\":%d,\"c3\":%d}",
    c0, c1, c2, c3
  );
  server.send(200, "application/json", payload);
}

void handleMuxAll() {
  String payload = "{";
  for (int i = 0; i < 16; i++) {
    payload += "\"c";
    payload += i;
    payload += "\":";
    payload += readMuxChannel(i);
    if (i < 15) payload += ",";
  }
  payload += "}";
  server.send(200, "application/json", payload);
}

void printWifiInfo() {
  Serial.println();
  Serial.println("=== WIFI STATUS ===");
  Serial.print("WiFi.status(): ");
  Serial.println(WiFi.status());
  Serial.print("Connected SSID: ");
  Serial.println(WiFi.SSID());
  Serial.print("Local IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("Gateway: ");
  Serial.println(WiFi.gatewayIP());
  Serial.print("Subnet: ");
  Serial.println(WiFi.subnetMask());
  Serial.print("DNS: ");
  Serial.println(WiFi.dnsIP());
  Serial.print("RSSI (dBm): ");
  Serial.println(WiFi.RSSI());
  Serial.println("===================");
}

bool connectWifi(unsigned long timeoutMs) {
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true, true);
  delay(300);

  Serial.print("Connecting to SSID: ");
  Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - t0) < timeoutMs) {
    Serial.print(".");
    delay(300);
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi CONNECTED");
    printWifiInfo();
    return true;
  }

  Serial.println("WiFi FAILED to connect within timeout");
  printWifiInfo();
  return false;
}

bool startSoftAP() {
  WiFi.mode(WIFI_AP);
  bool ok = WiFi.softAP(AP_SSID, AP_PASSWORD);
  if (ok) {
    Serial.println("SoftAP STARTED");
    Serial.print("AP SSID: ");
    Serial.println(AP_SSID);
    Serial.print("AP IP: ");
    Serial.println(WiFi.softAPIP());
  } else {
    Serial.println("SoftAP FAILED to start");
  }
  return ok;
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  pinMode(MUX_EN_PIN, OUTPUT);
  pinMode(MUX_S0_PIN, OUTPUT);
  pinMode(MUX_S1_PIN, OUTPUT);
  pinMode(MUX_S2_PIN, OUTPUT);
  pinMode(MUX_S3_PIN, OUTPUT);
  pinMode(MUX_SIG_PIN, INPUT);
  digitalWrite(MUX_EN_PIN, LOW);

  staConnected = connectWifi(20000);
  if (!staConnected) {
    apStarted = startSoftAP();
  }

  server.on("/", handleRoot);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/c0-c3", HTTP_GET, handleC0ToC3);
  server.on("/c0-c3/", HTTP_GET, handleC0ToC3);
  server.on("/mux-all", HTTP_GET, handleMuxAll);
  server.on("/mux-all/", HTTP_GET, handleMuxAll);
  server.begin();

  if (staConnected || apStarted) {
    Serial.println("HTTP server started.");
    Serial.print("Open in browser: http://");
    Serial.print(activeIP());
    Serial.println("/");
    Serial.print("Status JSON: http://");
    Serial.print(activeIP());
    Serial.println("/status");
    Serial.print("MUX quick JSON: http://");
    Serial.print(activeIP());
    Serial.println("/c0-c3");
  } else {
    Serial.println("HTTP server started, but no network is active.");
    Serial.println("Check STA credentials and AP configuration.");
  }
}

void loop() {
  server.handleClient();

  // LED behavior:
  // - STA connected OR AP started: solid ON
  // - No network active: blink
  if (staConnected || apStarted) {
    digitalWrite(LED_PIN, HIGH);
  } else {
    if (millis() - lastBlinkMs >= 250) {
      lastBlinkMs = millis();
      ledState = !ledState;
      digitalWrite(LED_PIN, ledState ? HIGH : LOW);
    }

  }
}

