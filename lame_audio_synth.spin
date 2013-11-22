{{
Audio Synthesizer
─────────────────────────────────────────────────
Version: 1.0
Copyright (c) 2011 LameStation.
See end of file for terms of use.

Authors: Brett Weir
─────────────────────────────────────────────────
}}


CON     FS      = 25000
        PERIOD1 = 3200         ' 'FS = 80MHz / PERIOD1'
        SAMPLES = 512
        PERVOICE = 1
        VOICES = 8
        OSCILLATORS = VOICES*PERVOICE
        REGPEROSC = 4

        OUTPUTPIN_LMONO = 27
        OUTPUTPIN_R = 27

      '  OUTPUTPIN_LMONO = 15
       ' OUTPUTPIN_R = 15

        'MIDIPIN = 25
        MIDIPIN = 23

        
        KEYBITS = $180
        HELDBIT = $80
        KEYONBIT = $100
        SUSPEDALBIT = $800000

        NOTEBITS = $7F
        'VELOCITYBITS = $7F00
        VOLUMEBITS = $FFFFFF

        ADSRBITS = $3000000 'new
        ATTACKBIT = $1000000
        SUSTAINBIT = $2000000

        'ADSR register
'       4bit      7bit       7bit       7bit       7bit
'       0000    0000000    0000000    0000000    0000000
'        W         R          S          D          A


        A_OFFSET = 0
        D_OFFSET = 7
        S_OFFSET = 14
        R_OFFSET = 21
        W_OFFSET = 28

        A_MASK = !($7F << A_OFFSET)
        D_MASK = !($7F << D_OFFSET)
        S_MASK = !($7F << S_OFFSET)
        R_MASK = !($7F << R_OFFSET)
        W_MASK = !($F << W_OFFSET)
        

'SONG PLAYER
        ENDOFSONG = 0
        TIMEWAIT = 1
        NOTEON = 2
        NOTEOFF = 3
        
        SONGS = 1
        SONGOFF = 255
        BAROFF = 254
        SNOP = 253
        SOFF = 252 

        BARRESOLUTION = 8
        MAXBARS = 16


'0 timestamp     amount (shift by 12)
'1 note on    note  channel
'2 note off   channel

        
        '0 - note (last 8 bits)
        '1 - target volume         
        '2 - phase inc
        '3 - phase acc

'NEW NOTE REGISTER

        'note registers
        ' $           ----------- 16 bits ----------
        ' $0000      0000000      0       0    0000000
        '            velocity   keyon    held  notenum




        'target volume register
        ' --- 6bits ---     2bit            --------- 24 bits ----------
        '    %0000_00       00             0000_0000 0000_0000 0000_0000
        '               ADSR state               current volume

        'phase inc and acc registers
        ' ----------------- 32 bits -------------
        ' %0000_0000 0000_0000 0000_0000 0000_0000       value to increment
        ' %0000_0000 0000_0000 0000_0000 0000_0000       accumulator
         



'CHANNEL PARAM REGISTER

        
        OSCREGS = OSCILLATORS*REGPEROSC
        OSCBITMASK = (OSCILLATORS-1) << 2
        INITVAL = 127


                




VAR

'ASM data structure (do not mess up)
long    parameter
long    outputlong

long    channelparam  'volume   'waveform LSB
long    channelADSR

long    oscRegister[OSCREGS]

byte    oscindexer
byte    oscindexcounter
byte    oscoffindexer

byte    channelbyte
byte    instrumentbyte

long    songcursor
long    seqcursor
byte    seqbyte 
byte    songbyte
long    repeatlong
long    repeatindex
long    repeatseqindex
long    songAddr
long    loopsongPtr
long    barAddr
byte    songchoice
byte    looping
byte    bar
byte    barinc   
byte    totalbars
byte    play


byte    songregister[MAXBARS*(1+BARRESOLUTION)]

long    barcursor
long    barshift
long    songlinecursor
long    linecursor
long    songbyteshift
long    loopptrshift

long    loadbarcursor
long    loadsongcursor
long    loadbarshift

long    PlayStack[40]
long    LoopingPlayStack[100]

PUB Start
    
  parameter := @sine
  channelparam := (INITVAL << 8)
  channelADSR := LONG[@instruments][0]
  songchoice := SONGOFF
  looping := 0  
  play := 0
  
  
  repeat oscindexer from 0 to OSCREGS-1 step REGPEROSC
      oscRegister[oscindexer] := 0
      oscRegister[oscindexer+1] := 0
      oscRegister[oscindexer+2] := 0
      oscRegister[oscindexer+3] := 0
  oscindexer := 0
  oscindexcounter := 0

  cognew(@oscmodule, @parameter)    'start assembly cog
  cognew(LoopingSongParser, @LoopingPlayStack)

PUB SetADSR(attackvar, decayvar, sustainvar, releasevar)
  channelADSR := (channelADSR & A_MASK) + (attackvar << A_OFFSET)
  channelADSR := (channelADSR & D_MASK) + (decayvar << D_OFFSET)
  channelADSR := (channelADSR & S_MASK) + (sustainvar << S_OFFSET)
  channelADSR := (channelADSR & R_MASK) + (releasevar << R_OFFSET)
  
PUB SetWaveform(waveformvar, volumevar)
  channelADSR := (channelADSR & W_MASK) + (waveformvar << W_OFFSET)
  channelparam := (channelparam & $FFFF00FF) + (volumevar << 8)

PUB LoadInstr(instrnum)
  channelADSR := LONG[@instruments][instrnum]
  
PUB PlaySound(channel, note)
  if note < 128 and channel < VOICES
     oscindexer := channel << 2
     oscRegister[oscindexer] &= !KEYBITS          
     oscRegister[oscindexer+1] &= !ADSRBITS
     oscRegister[oscindexer] := note + KEYBITS

PUB StopSound(channel)
  if channel < VOICES
     oscindexer := channel << 2          
     oscRegister[oscindexer] &= !KEYBITS 

PUB PlaySequence(songAddrvar)
     seqcursor := 0
     
     repeat while byte[songAddrvar][seqcursor] <> ENDOFSONG
        seqbyte := byte[songAddrvar][seqcursor]
        if seqbyte == TIMEWAIT
            repeatlong := byte[songAddrvar][seqcursor] << 13
            repeat repeatseqindex from 0 to repeatlong
            seqcursor += 2
     
        elseif seqbyte == NOTEON
            PlaySound(byte[songAddrvar][seqcursor+1],byte[songAddrvar][seqcursor+2])   
            seqcursor += 3
     
        elseif seqbyte == NOTEOFF
            StopSound(byte[songAddrvar][seqcursor+1])
            seqcursor += 2


PUB LoadSong(songBarAddrvar)

  totalbars := byte[songBarAddrvar][0]
  repeatlong := byte[songBarAddrvar][1] << 8
  loadsongcursor := 2
  loadbarshift := 0
    
           
  repeat bar from 0 to totalbars-1 
     repeat loadbarcursor from 0 to BARRESOLUTION
         linecursor := loadbarshift + loadbarcursor
         songregister[loadbarshift + loadbarcursor] := byte[songBarAddrvar][loadsongcursor]
         loadsongcursor++

     loadbarshift += constant(BARRESOLUTION+1)

  loopsongPtr := songBarAddrvar + loadsongcursor

PUB PlaySong
  play := 1

PUB StopSong
  play := 0
  StopAllSound
PUB StopAllSound
  repeat oscindexer from 0 to OSCREGS-1 step REGPEROSC
     oscRegister[oscindexer] &= !KEYBITS 
PRI LoopingSongParser

repeat

     if play == 1
        songcursor := 0
        barcursor := 0
           
        repeat while byte[loopsongPtr][songcursor] <> SONGOFF and play == 1  
         
           barcursor := songcursor
         
           repeat linecursor from 0 to constant(BARRESOLUTION-1)  
         
               songcursor := barcursor
               
               barshift := 0
               barinc := 0
               repeat while barinc < byte[loopsongPtr][songcursor]
                      barshift += constant(BARRESOLUTION+1)
                      barinc++
               

               repeat while byte[loopsongPtr][songcursor] <> BAROFF and play == 1  
                  songbyte := byte[loopsongPtr][songcursor]
                  
                  if songregister[barshift+1+linecursor] == SNOP

                  elseif songregister[barshift+1+linecursor] == SOFF
                      StopSound( songregister[barshift] )       
                  else
                      PlaySound( songregister[barshift] , songregister[barshift+1+linecursor] )  'channel, note

                      
                  songcursor += 1
                  repeat while barinc < byte[loopsongPtr][songcursor]
                      barshift += constant(BARRESOLUTION+1)
                      barinc++
              
               repeat repeatindex from 0 to repeatlong
              
           songcursor += 1

        StopAllSound     

DAT

instruments
'tubular bells
long    (127 + (12 << D_OFFSET) + (0 << S_OFFSET) + (0 << R_OFFSET) + (3 << W_OFFSET))
   
'jarn harpsichord
long    (127 + (41 << D_OFFSET) + (60 << S_OFFSET) + (0 << R_OFFSET) + (0 << W_OFFSET))

'super square
long    (10 + (127 << D_OFFSET) + (0 << S_OFFSET) + (0 << R_OFFSET) + (1 << W_OFFSET))

'attack but no release....
long    (127 + (12 << D_OFFSET) + (0 << S_OFFSET) + (0 << R_OFFSET) + (0 << W_OFFSET))



'quarter sine table
sine 
byte    0,1,3,4,6,7,9,10,12,13,15,17,18,20,21,23
byte    24,26,27,29,30,32,33,35,36,38,39,41,42,44,45,47
byte    48,50,51,52,54,55,57,58,59,61,62,63,65,66,67,69
byte    70,71,73,74,75,76,78,79,80,81,82,84,85,86,87,88
byte    89,90,91,93,94,95,96,97,98,99,100,101,102,102,103,104
byte    105,106,107,108,108,109,110,111,112,112,113,114,114,115,116,116
byte    117,117,118,119,119,120,120,121,121,121,122,122,123,123,123,124
byte    124,124,125,125,125,125,126,126,126,126,126,126,126,126,126,126

freqTable
long    1153, 1222, 1294, 1371, 1453, 1539, 1631, 1728
long    1830, 1939, 2055, 2177, 2306, 2444, 2589, 2743
long    2906, 3079, 3262, 3456, 3661, 3879, 4110, 4354
long    4613, 4888, 5178, 5486, 5812, 6158, 6524, 6912
long    7323, 7759, 8220, 8709, 9227, 9776, 10357, 10973
long    11625, 12317, 13049, 13825, 14647, 15518, 16441, 17419
long    18454, 19552, 20714, 21946, 23251, 24634, 26099, 27651
long    29295, 31037, 32882, 34838, 36909, 39104, 41429, 43893
long    46503, 49268, 52198, 55302, 58590, 62074, 65765, 69676
long    73819, 78209, 82859, 87786, 93007, 98537, 104396, 110604
long    117181, 124149, 131531, 139353, 147639, 156418, 165719, 175573
long    186014, 197075, 208793, 221209, 234363, 248299, 263063, 278706
long    295279, 312837, 331439, 351147, 372028, 394150, 417587, 442418
long    468726, 496598, 526127, 557412, 590558, 625674, 662878, 702295
long    744056, 788300, 835175, 884837, 937452, 993196, 1052254, 1114825
long    1181116, 1251348, 1325757, 1404591, 1488112, 1576600, 1670350, 1769674


DAT

                        org

oscmodule               mov       dira, diraval       'set APIN to output
                        mov       ctra, ctraval       'establish counter A mode and APIN
                        mov       frqa, #1            'set counter to increment 1 each cycle

                        mov       time, cnt           'record current time
                        add       time, period        'establish next period

'ESTABLISH COMMUNICATION LINK BETWEEN SPIN AND PASM              

                        'get address of sine table
                        mov       Addr, par
                        rdlong    tableAddr, Addr

              
              
                        'get address of frequency table
                        mov       freqAddr, tableAddr
                        add       freqAddr, #128

                        mov       organAddr, freqAddr
                        add       organAddr, fivetwelve

                        

                        'get address to write out to
                        mov       outputAddr, Addr
                        add       outputAddr, #4

                        'get address of channel parameters
                        mov       paramAddr, outputAddr
                        add       paramAddr, #4
                        mov       adsrAddr, paramAddr
                        add       adsrAddr, #4

                        'get address of oscillator registers
                        mov       oscAddr, adsrAddr
                        add       oscAddr, #4

 

'MAIN LOOP START       
mainloop                waitcnt   time, period        'wait until next period
                        neg       phsa, output         'back up phsa so that it trips "value cycles from now

                        'UPDATE CHANNEL PARAMETERS BEFORE ANYTHING ELSE 


                        rdlong    adsrtemp, adsrAddr
              
              
                        'attack
                        mov       attack, adsrtemp
                        and       attack, #$7F
                        'decay
                        shr       adsrtemp, doffset
                        mov       decay, adsrtemp
                        and       decay, #$7F
                        'sustain 
                        shl       adsrtemp, #3
                        mov       sustain, adsrtemp
                        and       sustain, bigsusmask
                        'release               
                        shr       adsrtemp, #17
                        mov       release, adsrtemp
                        and       release, #$7F  
                        
                        'waveform               
                        shr       adsrtemp, #7
                        mov       waveform, adsrtemp
                        and       waveform, #$F  


              

                        'INITIALIZE OSCILLATOR LOOP
                        mov       output, #0
                        mov       oscIndex, oscTotal
                        mov       oscPtr, oscAddr
              
oscloop                 'READ NOTE VALUE AND FIND FREQUENCY FROM LOOKUP
                        rdlong    noteAddrtemp, oscPtr

                        and       noteAddrtemp, keyonmask     nr, wz 'SET Z FLAG FOR LATER OPERATION, REMEMBER!!!

                        and       noteAddrtemp, #$7F
                        shl       noteAddrtemp, #2
                        add       noteAddrtemp, freqAddr
                        add       oscPtr, #4
                        




                        
                        'ADSR FILTER (or in this case, ADS filter?)
                        rdlong    voltemp, oscPtr
                        mov       vollongtemp, voltemp

                        'since Z flag still set from previous operation, no extra instructions needed
                        and       vollongtemp, ADSRmask
if_z                    mov       vollongtemp, #0
if_nz                   cmp       vollongtemp, #1               wc
if_nz_and_c             or        vollongtemp, attackmask



                            

                        and       vollongtemp, attackmask       nr, wz  'ATTACK  
if_nz                   mov       targetvol, sustainfull
if_nz                   jmp       #attackjump

                        and       vollongtemp, sustainmask      nr, wz  'CHECK IF SHOULD BE SUSTAINING
if_nz                   mov       targetvol, sustain
if_z                    mov       targetvol, #0
attackjump


                        and       voltemp, volmask
                        cmps      voltemp, targetvol        wc
if_c                    adds      voltemp, attack
if_nc                   subs      voltemp, decay
if_nc                   and       vollongtemp, attackmask        nr, wz
if_nc_and_nz            add       vollongtemp, attackmask

                      
                        cmps      voltemp, #0           wc
if_c                    mov       voltemp, #0

                        add       voltemp, vollongtemp
                        wrlong    voltemp, oscPtr

                        add       oscPtr, #4




              
                        'UPDATE PHASEINC OF OSC FROM FREQUENCY
                        rdlong    phaseinc, noteAddrtemp      
                        wrlong    phaseinc, oscPtr
                        add       noteAddrtemp, #4
                        add       oscPtr, #4

                        'ADD PHASEINC TO PHASEACC OF OSC          
                        rdlong    phase, oscPtr
                        add       phase, phaseinc
                        wrlong    phase, oscPtr
                        add       oscPtr, #4





              
'PHASE ACCUMULATOR
                        'shift and truncate phase to 512 samples
                        shr     phase, #12
                        and     phase, #$1FF


'WAVEFORM SELECTOR
        'jumps the program counter to the appropriate
        'waveform
                        cmp     waveform, #1            wc, wz
if_c                    jmp     #:rampwave
if_nc_and_z             jmp     #:squarewave
                        cmp     waveform, #3            wc, wz
if_c                    jmp     #:triwave
if_nc_and_z             jmp     #:sinewave
                        cmp     waveform, #5            wc, wz
if_c                    jmp     #:whitenoise
if_nc_and_z             jmp     #:screechwave 

 
'RAMP WAVE
        'if ramp wave, fit the truncated phase accumulator into
        'the proper 8-bit scaling and output as waveform
:rampwave               mov     osctemp, phase
                        subs    osctemp, #256
                        sar     osctemp, #1
                        jmp     #:oscOutput

  
'SQUARE WAVE
        'if square wave, compare truncated phase with 128
        '(half the height of 8 bits) and scale
:squarewave             cmp     phase, #256             wc
if_nc                   mov     osctemp, #0
if_c                    mov     osctemp, #256
                        subs    osctemp, #128   
                        jmp     #:oscOutput


'TRIANGLE WAVE
        'if triangle wave, double the amplitude of a square
        'wave and add truncated phase for first half, and
        'subtract truncated phase for second half of cycle
:triwave                cmp     phase, #256             wc
if_c                    mov     osctemp, phase
if_nc                   mov     osctemp, #511
if_nc                   subs    osctemp, phase
                        subs    osctemp, #128
                        jmp     #:oscOutput


'SINE WAVE
        'if sine wave, use truncated phase to read values
        'from sine table in main memory.  This requires
        'the most time to complete, with the exception
        'of noise generation
:sinewave               mov     Addrtemp, phase
                        and     Addrtemp, #$FF
                        cmp     Addrtemp, #128          wc
if_nc                   xor     Addrtemp, #$FF
                        and     Addrtemp, #$7F

                        shl     Addrtemp, #5
                        add     Addrtemp, sineAddr
                        rdword  osctemp, Addrtemp
                        shr     osctemp, #9

                        cmp     phase, #256             wc              
if_nc                   neg     osctemp, osctemp

                        jmp     #:oscOutput           



'ORGAN GENERATION
:screechwave            mov     Addrtemp, phase
                        add     Addrtemp, organAddr
                        rdbyte  osctemp, Addrtemp
                        subs    osctemp, #128

                        jmp     #:oscOutput         




'WHITE NOISE GENERATOR
        'pseudo-random number generator truncated to 8 bits.
:whitenoise             sar     rand, #1
                        mov     rand2, rand
                        and     rand2, #$FF
                        mov     rand3, rand2
                        shl     rand3, #2
                        xor     rand3, rand2
                        shl     rand3, #24
                        add     rand, rand3

                        mov     osctemp, rand
                        and     osctemp, #$FF



:oscOutput
'UNROLLED ADSR MULTIPLIER   (calculates proper volume of this oscillator's sample)
                        mov     multtemp, osctemp
                        mov     osctemp, #0
                        shr     voltemp, #13 'shift right 10 for sustain then 3 for multiplier
                        
                        and     voltemp, #%00001      nr, wz
if_nz                   add     osctemp, multtemp                             
                        shl     multtemp, #1
                        and     voltemp, #%00010      nr, wz
if_nz                   add     osctemp, multtemp
                        shl     multtemp, #1
                        and     voltemp, #%00100      nr, wz
if_nz                   add     osctemp, multtemp
                        shl     multtemp, #1
                        and     voltemp, #%01000      nr, wz
if_nz                   add     osctemp, multtemp
                        shl     multtemp, #1
                        and     voltemp, #%10000      nr, wz
if_nz                   add     osctemp, multtemp
                            
                        sar     osctemp, #3     '5-2





'ADDS OUTPUT OF THIS OSCILLATOR TO OUTPUT VALUE    
                        adds    output, osctemp
                        djnz    oscIndex, #oscloop


'FINAL VOLUME ADJUSTMENT AND OUTPUT TO SOUND              
                        adds    output, outputoffset


                        wrlong    output, outputAddr
      
'LOOP BACK FOR NEXT SAMPLE
                        jmp       #mainloop






diraval       long      |< OUTPUTPIN_LMONO               'APIN=0
ctraval       long      %00100 << 26 + OUTPUTPIN_LMONO   'NCO/PWM APIN=0
period        long      PERIOD1               '800kHz period (_clkfreq / period)
time          long      0

waveform      long      3     '0 = ramp    1 = square    2 = triangle    3 = sine    4 = pseudo-random noise    5 = sine perversion
volume        long      127

multarg       long      3
multtemp      long      2

attack        long      0
decay         long      0
sustain       long      127 << 10
sustainfull   long      127 << 10
release       long      0
adsrtemp      long      0
targetvol     long      0
volAddrtemp   long      0
voltemp       long      0
vollongtemp   long      0
volmask       long      VOLUMEBITS

keyonmask     long      KEYONBIT
heldmask      long      HELDBIT
ADSRmask      long      ADSRBITS
sustainmask   long      SUSTAINBIT
attackmask    long      ATTACKBIT
bigsusmask    long      $1FC00


aoffset       long      A_OFFSET
doffset       long      D_OFFSET
soffset       long      S_OFFSET
roffset       long      R_OFFSET
woffset       long      W_OFFSET

amask         long      !A_MASK
dmask         long      !D_MASK
smask         long      !S_MASK
rmask         long      !R_MASK
wmask         long      !W_MASK


fivetwelve    long      512

'variables for oscillator controller
oscPtr        long      0
oscIndex      long      0

phaseinc      long      0
phase         long      0
noteAddrtemp  long      0
notelongtemp  long      0

'oscillator data                                                                                      
oscAddr       long      0
oscTotalRegs  long      OSCREGS
oscTotal      long      OSCILLATORS

'volumeshift   long      1

osctemp       long      0
outputoffset  long      PERIOD1/2
output        long      0

Addr          long      0
Addrtemp      long      0
tableAddr     long      0
freqAddr      long      0
outputAddr    long      0
sineAddr      long      $E000
organAddr     long      0

paramAddr     long      0
adsrAddr      long      0

rand          long      203943
rand2         long      0
rand3         long      0
              fit 496


{{
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                           TERMS OF USE: MIT License                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this  │
│software and associated documentation files (the "Software"), to deal in the Software │ 
│without restriction, including without limitation the rights to use, copy, modify,    │
│merge, publish, distribute, sublicense, and/or sell copies of the Software, and to    │
│permit persons to whom the Software is furnished to do so, subject to the following   │
│conditions:                                                                           │
│                                                                                      │
│The above copyright notice and this permission notice shall be included in all copies │
│or substantial portions of the Software.                                              │
│                                                                                      │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,   │
│INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A         │
│PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT    │
│HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION     │
│OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE        │
│SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                                │
└──────────────────────────────────────────────────────────────────────────────────────┘
}}
