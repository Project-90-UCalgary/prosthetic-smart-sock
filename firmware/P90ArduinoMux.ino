// ESP32 WiFi AP + HTTP server for MUX C0-C3
#include <WiFi.h>
#include <WebServer.h>

int EN = 2;
int S0 = 12;
int S1 = 14;
int S2 = 27;
int S3 = 26;
// With WiFi enabled on ESP32, ADC2 pins (like GPIO13) can read as zero.
// Use ADC1 for the mux signal input.
const int MUX_SIG_PIN = 34; // GPIO34 (ADC1, input-only)

// --- WiFi AP config (change as needed) ---
// Set these before flashing (do not commit real secrets to public repos).
const char* AP_SSID = "YOUR_AP_SSID";
const char* AP_PASSWORD = "YOUR_AP_PASSWORD";

WebServer server(80);
bool apStarted = false;
int lastStationCount = -1;
const int STATUS_LED_PIN = 2; // Built-in LED on many ESP32 boards

// Format to print
char padded[12];

// MUX select bits
void out0()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, LOW);
  digitalWrite (S2, LOW);
  digitalWrite (S3, LOW);
}
void out1()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, LOW);
  digitalWrite (S2, LOW);
  digitalWrite (S3, LOW);
}
void out2()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, LOW);
  digitalWrite (S3, LOW);
}
void out3()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, LOW);
  digitalWrite (S3, LOW);
}
void out4()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, LOW);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, LOW);
}
void out5()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, LOW);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, LOW);
}
void out6()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, LOW);
}
void out7()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, LOW);
}
void out8()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, LOW);
  digitalWrite (S2, LOW);
  digitalWrite (S3, HIGH);
}
void out9()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, LOW);
  digitalWrite (S2, LOW);
  digitalWrite (S3, HIGH);
}
void out10()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, LOW);
  digitalWrite (S3, HIGH);
}
void out11()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, LOW);
  digitalWrite (S3, HIGH);
}
void out12()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, LOW);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, HIGH);
}
void out13()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, LOW);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, HIGH);
}
void out14()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, LOW);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, HIGH);
}
void out15()
{
  digitalWrite (EN, LOW);
  digitalWrite (S0, HIGH);
  digitalWrite (S1, HIGH);
  digitalWrite (S2, HIGH);
  digitalWrite (S3, HIGH);
}
// Bypass mux
void bypass()
{
  digitalWrite (EN, HIGH);
}

void select_mux_pin(int i)
{
  switch (i) {
    case 0: 
      out0();
      break;
    case 1:
      out1();
      break;
    case 2:
      out2();
      break;
    case 3:
      out3();
      break;
    case 4:
      out4();
      break;
    case 5:
      out5();
      break;
    case 6:
      out6();
      break;
    case 7:
      out7();
      break;
    case 8:
      out8();
      break;
    case 9:
      out9();
      break;
    case 10:
      out10();
      break;
    case 11:
      out11();
      break;
    case 12:
      out12();
      break;
    case 13:
      out13();
      break;
    case 14:
      out14();
      break;
    case 15:
      out15();
      break;
    default:
      bypass();
      break;
  }
}

String readC0ToC3Json()
{
  int values[4];

  for (int i = 0; i < 4; i++) {
    select_mux_pin(i);        // select C0..C3
    delayMicroseconds(100);   // settle after switching channel
    values[i] = analogRead(MUX_SIG_PIN);
  }

  char payload[96];
  snprintf(
    payload,
    sizeof(payload),
    "{\"c0\":%d,\"c1\":%d,\"c2\":%d,\"c3\":%d}",
    values[0], values[1], values[2], values[3]
  );
  return String(payload);
}

void handleRoot()
{
  server.send(200, "text/plain", "P90 MUX AP online. Use /c0-c3 for JSON.");
}

void handleC0ToC3()
{
  server.send(200, "application/json", readC0ToC3Json());
}

void handleWifiStatus()
{
  int stations = WiFi.softAPgetStationNum();
  char payload[160];
  snprintf(
    payload,
    sizeof(payload),
    "{\"apStarted\":%s,\"ssid\":\"%s\",\"ip\":\"%s\",\"stations\":%d}",
    apStarted ? "true" : "false",
    AP_SSID,
    WiFi.softAPIP().toString().c_str(),
    stations
  );
  server.send(200, "application/json", payload);
}

void setup()
{
  // Open serial + set pins
  Serial.begin (9600);
  pinMode (STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);
  pinMode (EN, OUTPUT);
  pinMode (S0, OUTPUT);
  pinMode (S1, OUTPUT);
  pinMode (S2, OUTPUT);
  pinMode (S3, OUTPUT);

  // Start local AP so mLab script can connect directly
  WiFi.mode(WIFI_AP);
  apStarted = WiFi.softAP(AP_SSID, AP_PASSWORD);

  server.on("/", handleRoot);
  server.on("/c0-c3", HTTP_GET, handleC0ToC3);
  server.on("/wifi-status", HTTP_GET, handleWifiStatus);
  server.begin();

  if (apStarted) {
    digitalWrite(STATUS_LED_PIN, HIGH); // steady ON = AP started
    Serial.println("WiFi AP STARTED");
    Serial.print("AP SSID: ");
    Serial.println(AP_SSID);
    Serial.print("AP IP: ");
    Serial.println(WiFi.softAPIP());
    Serial.println("Open http://192.168.4.1/wifi-status to verify station connection.");
  } else {
    digitalWrite(STATUS_LED_PIN, LOW);
    Serial.println("WiFi AP FAILED TO START");
  }
}

void loop() {
  server.handleClient();

  // Blink LED when at least one client is connected to AP.
  int stations = WiFi.softAPgetStationNum();
  if (apStarted) {
    if (stations > 0) {
      digitalWrite(STATUS_LED_PIN, (millis() / 250) % 2);
    } else {
      digitalWrite(STATUS_LED_PIN, HIGH); // AP up, no clients
    }
  } else {
    digitalWrite(STATUS_LED_PIN, LOW);
  }

  if (stations != lastStationCount) {
    Serial.print("AP connected clients: ");
    Serial.println(stations);
    lastStationCount = stations;
  }
  
  for (int i = 0; i < 16; i++) {
    // Select input
    select_mux_pin(i);
    // Read from sensor
    int sensor_value = analogRead(MUX_SIG_PIN);
    // int sensor_value1 = analogRead(A1);
    // Read from A0 and place value into array for formatting
    sprintf(padded, "%6d", sensor_value); // ex "  123"
    //sprintf(padded, "%6d", sensor_value1);
    // Format
    if (i == 15) {
      Serial.println(padded); // new line
      break; // reset loop
    }
    else
      Serial.print(padded);
      
    // Timing (test and modify)
    delay(1); // 1ms
  }
}