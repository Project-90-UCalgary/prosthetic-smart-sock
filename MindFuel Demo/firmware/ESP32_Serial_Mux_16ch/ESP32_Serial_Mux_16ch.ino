/*
  ESP32 16-channel MUX reader (Serial mode for MATLAB)
  - Reads CD74HC4067 channels c0..c15
  - Prints one line per frame: 16 × sprintf("%6d", adc) + LF (9600 baud)
  - Pin map matches ESP32_Wifi_Station_Test.ino in this demo package
*/

const int MUX_EN_PIN = 2;
const int MUX_S0_PIN = 12;
const int MUX_S1_PIN = 14;
const int MUX_S2_PIN = 27;
const int MUX_S3_PIN = 26;
const int MUX_SIG_PIN = 34; // ADC1 input

void selectMuxChannel(int channel) {
  if (channel < 0 || channel > 15) {
    digitalWrite(MUX_EN_PIN, HIGH);
    return;
  }
  digitalWrite(MUX_EN_PIN, LOW);
  digitalWrite(MUX_S0_PIN, (channel & 0x01) ? HIGH : LOW);
  digitalWrite(MUX_S1_PIN, (channel & 0x02) ? HIGH : LOW);
  digitalWrite(MUX_S2_PIN, (channel & 0x04) ? HIGH : LOW);
  digitalWrite(MUX_S3_PIN, (channel & 0x08) ? HIGH : LOW);
}

int readMuxChannel(int channel) {
  selectMuxChannel(channel);
  delayMicroseconds(120);
  return analogRead(MUX_SIG_PIN);
}

void setup() {
  Serial.begin(9600);
  pinMode(MUX_EN_PIN, OUTPUT);
  pinMode(MUX_S0_PIN, OUTPUT);
  pinMode(MUX_S1_PIN, OUTPUT);
  pinMode(MUX_S2_PIN, OUTPUT);
  pinMode(MUX_S3_PIN, OUTPUT);
  pinMode(MUX_SIG_PIN, INPUT);
  digitalWrite(MUX_EN_PIN, LOW);
}

void loop() {
  char padded[8];
  for (int i = 0; i < 16; i++) {
    int value = readMuxChannel(i);
    sprintf(padded, "%6d", value);
    Serial.print(padded);
  }
  Serial.println();
  delay(10);
}
