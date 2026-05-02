// There is proabably a more efficient way about this lol

int EN = 2;
int S0 = 3;
int S1 = 4;
int S2 = 5;
int S3 = 6;

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
void setup()
{
  // Open serial + set pins
  Serial.begin (9600);
  pinMode (EN, OUTPUT);
  pinMode (S0, OUTPUT);
  pinMode (S1, OUTPUT);
  pinMode (S2, OUTPUT);
  pinMode (S3, OUTPUT);
}

void loop() {
  
  for (int i = 0; i < 16; i++) {
    // Select input
    select_mux_pin(i);
    // Read from sensor
    int sensor_value = analogRead(A0);
    int sensor_value1 = analogRead(A1);
    // Read from A0 and place value into array for formatting
    sprintf(padded, "%6d%6d", sensor_value, sensor_value1); // ex "  123"
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