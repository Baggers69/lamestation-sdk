''
'' LameControl over serial line
''
''        Author: Marko Lukat
'' Last modified: 2014/05/28
''       Version: 0.2
''
CON
  J_U  = |< 12
  J_D  = |< 13
  J_L  = |< 14
  J_R  = |< 15
   
  SW_A = |< 25
  SW_B = |< 26
     
OBJ
  serial: "FullDuplexSerial"
  
VAR
  long  cog, controls, shadow, stack[32]

PUB null
'' This is not a top level object.

PRI monitor

  serial.start(31, 30, %0000, 115200)
  repeat
    case serial.rxtime(50) | $20
        "a": shadow |= SW_A
        "b": shadow |= SW_B
        "l": shadow |= J_L
        "r": shadow |= J_R
        "u": shadow |= J_U
        "d": shadow |= J_D
      other: shadow~
    
PUB Start

  return cog := cognew(monitor, @stack{0}) +1

PUB Update

  ifnot cog
    Start
  controls := shadow
  
PUB A

  return controls & SW_A
    
PUB B

  return controls & SW_B

PUB Left

  return controls & J_L      
    
PUB Right

  return controls & J_R

PUB Up

  return controls & J_U

PUB Down

  return controls & J_D

DAT