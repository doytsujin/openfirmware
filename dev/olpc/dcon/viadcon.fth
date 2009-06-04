\ See license at end of file
\ " dcon" device-name

\ DCON internal registers, accessed via I2C
\ 0 constant DCON_ID
\ 1 constant DCON_MODE
\ 2 constant DCON_HRES
\ 3 constant DCON_HTOTAL
\ 4 constant DCON_HSYNC_WIDTH
\ 5 constant DCON_VRES
\ 6 constant DCON_VTOTAL
\ 7 constant DCON_VSYNC_WIDTH
\ 8 constant DCON_TIMEOUT
\ 9 constant DCON_SCAN_INT
\ d# 10 constant DCON_BRIGHT

\ Mode register bits
\ h#    1 constant DM_PASSTHRU
\ h#    2 constant DM_SLEEP
\ h#    4 constant DM_SLEEP_AUTO
\ h#    8 constant DM_BL_ENABLE
\ h#   10 constant DM_BLANK
\ h#   20 constant DM_CSWIZZLE
\ h#   40 constant DM_COL_AA
\ h#   80 constant DM_MONO_LUMA
\ h#  100 constant DM_SCAN_INT
\ h#  200 constant DM_CLOCKDIV
\ h# 4000 constant DM_DEBUG
\ h# 8000 constant DM_SELFTEST

: dcon-load  ( -- )  h# 4c acpi-b@  h# 04 or  h# 4c acpi-b!  ;
: dcon-unload  ( -- )  h# 4c acpi-b@  h# 04 invert and  h# 4c acpi-b!  ;
: dcon-blnk?  ( -- flag )  h# 4a acpi-b@ 4 and 0<>  ;
: dcon-stat@  ( -- n )  h# 4b acpi-b@ 3 and  ;
: dcon-irq?  ( -- flag )  1 smb-reg@ h# 20 and 0<>  ;
: dcon-clr-irq  ( -- )  h# 20 1 smb-reg!  ;

\ DCONSTAT values:  0 SCANINT  1 SCANINT_DCON  2 DISPLAYLOAD  3 MISSED

1 value vga? \ VGA
0 value color? \ COLOUR

\ : gxfb!  ( l offset -- )  gxfb-dc-regs +  rl!  ;  \ Probably should be IO mapped

d# 905 value resumeline  \ Configurable; should be set from args

: wait-output  ( -- )
   \ Wait for up to a second for our output to coincide with DCON's
   d# 1000 0  do
      dcon-blnk?  0=  if  unloop exit  then
      1 ms
   loop
   ." Wait for VGA ready timed out" cr
;

: wait-dcon-mode  ( -- )
   d# 100 ms-factor *  tsc@ drop +  ( end-time )
   begin                            ( end-time )
      dcon-irq?  if
         dcon-stat@  dcon-clr-irq  2 =  if  \ DCONSTAT=10
            drop exit   
         then            
      then
      dup tsc@ drop - 0<            ( end-time reached? )
   until                            ( end-time )
   drop
   ." Timeout entering DCON mode" cr
;

: set-source ( vga? -- )
   dup vga? =  if  drop exit  then  ( source )
   dup to vga?                      ( source )
   if
\      unblank-display
      d# 50 ms
      wait-output
      dcon-load  \ Put the DCON in VGA-refreshed mode
      d# 25 us
\      display-on
   else
      dcon-unload  \ Put the DCON in self-refresh mode
      lock[ wait-dcon-mode ]unlock
\      display-off
   then
;

\ gx_configure_tft(info);

: try-dcon!  ( w reg# -- )
   ['] dcon!  catch  if  2drop  smb-stop 1 ms  smb-off  1 ms  smb-on  then
;

: mode!    ( mode -- )    1 dcon!  ;
: hres!    ( hres -- )    2 dcon!  ;  \ def: h#  458 d# 1200
: htotal!  ( htotal -- )  3 dcon!  ;  \ def: h#  4e8 d# 1256
: hsync!   ( sync -- )    4 dcon!  ;  \ def: h# 1808 d# 24,8
: vres!    ( vres -- )    5 dcon!  ;  \ def: h#  340 d# 900
: vtotal!  ( htotal -- )  6 dcon!  ;  \ def: h#  390 d# 912
: vsync!   ( sync -- )    7 dcon!  ;  \ def: h#  403 d# 4,3
: timeout! ( to -- )      8 dcon!  ;  \ def: h# ffff
: scanint! ( si -- )      9 dcon!  ;  \ def: h# 0000
: bright!  ( level -- ) d# 10 dcon! ; \ def: h# xxxF
: bright@  ( -- level ) d# 10 dcon@ ;
: brighter  ( -- )  bright@ 1+  h# f min  bright!  ;
: dimmer    ( -- )  bright@ 1-  0 max  bright!  ;

\ Color swizzle, AA, no passthrough, backlight
: set-color ( color? -- )
   dup to color?
   if  h# 69  else  h# 89  then  mode!
;

\ Setup so it can be called by execute-device-method
: dcon-off  ( -- )  smb-init  h# 12 ['] mode!  catch  if  drop  then  ;

: dcon2?  ( -- flag )
   0 ['] dcon@ catch  if  ( x )
      drop   smb-init     ( )
      0 ['] dcon@ catch  if  drop false exit  then
   then
   h# dc02 =
;

: dcon-setup  ( -- )
   \ Switch to OLPC mode
   h# c040  h# 3a dcon!   \ SDRAM Setup/Hold time.  Default of e040 fails
   h# 0000  h# 41 dcon!   \ Himax suggested this sequence (0 then 0101)

   h# 0101  h# 41 dcon!
   h# 0101  h# 42 dcon!

   h# 12 mode!
;
: dcon-enable  ( -- )
   dcon-setup
   true set-color
   h# f bright!
;

0 [if]
dconstat dconblnk or dconirq or  constant in-gpios  
dconload constant out-gpios

: dcon-gpio-init  ( -- )
   out-gpios in-gpios wljoin  OUT_EN gpio!
   in-gpios out-gpios wljoin  IN_EN  gpio!

   dconirq     >set  INV_EN gpio!

   dconirq dconblnk or             ( events )

\ Linux doesn't want me to turn these on
\   dup >set  EVNT_EN     gpio!
\   dup >set  IN_FLTR_EN  gpio!   \ Enable counter for GPIO7 (DCONIRQ)
\   dup >clr  EVNTCNT_EN  gpio!
\    d# 12     gpio-base h# f7 + rb!     \ GPIO_FE7_SEL
\    dup >clr  h# 44             gpio!   \ NEGEDGE_EN

\    0  gpio-base h# d8 +        rw!     \ GPIO_FLTR7_AMNT

   h# e0 gpio@  h# 0fff.ffff and  h# 2000.0000 or  h# e0 gpio!  \ p512 Map X
   h# e4 gpio@  h# fff0.ffff and  h# 0000.0000 or  h# e4 gpio!  \ p511 Map Y

[ifdef] dcon-interrupts
   h# 5140.0023 rdmsr  ( lo hi )  drop  ( lo )
   h# ff0f.fffff and  h# 0050.0000 or  0 wrmsrl  \ p 381 unrestricted Z
   0  h# 4d0  pc!  \ IRQs 0-7 edge sensitive
[then]

   ( events )
   dup >set  IN_EN  gpio!
   >set h# 4c gpio!   \ GPIOL_NEGEDGE_STS - clear detected edges

   dcon-load

   \ ['] dcon-interrupt 5 request_irq
;
[then]

0 value dcon-found?

d# 440 8 /  constant dcon-flag

: maybe-set-cmos  ( -- )  1  dcon-flag cmos!  ;

: panel
   smb-init
   0 dcon@ .

   0 9 cr   0 h# 70 h# 11 crt-mask
   0 h# 80 h# 17 crt-mask

   d# 1200 d# 900 d# 16 set-primary-mode

   60 60 9b crt-mask  \ Sync polarity - negative

   00 07 h# 79 crt-mask  \ Disable scaling

   30 30 h# 1e seq-mask  \ Power up DVP1 pads

   0c 0c h# 2a seq-mask  \ Power up LVDS pads
   80 80 h# f3 crt-mask  \ 18-bit TTL mode
   \ 1 01 h# 88 crt-mask  Something to do with LVDS; check
   \ set vclk
   \ VIASetOutputPath
   00 08 h# 6b crt-mask  \ Not simultaneous mode
\   DisableSecondDisplayChannel  XXX check me out

\ VIALCDPatchSkew
\ VIASetDisplayChannel  Seems to be lvds-specific

   40 40 h# 16 seq!  \ Check what is VIASR - is it really seq! ? - reserved bits, apparently control something about using crt and lcd at the same time

\ VIALoadLCDPatchRegs

   dcon-load
   dcon-enable  ( maybe-set-cmos )
   \ dcon-enable leaves mode set to 69 - 40:antialias, 20:swizzle, 8:backlight on, 1:passthru off
   set-fb
;

: panel2
   smb-init
   0 dcon@ .

   0 9 cr   0 h# 70 h# 11 crt-mask
   0 h# 80 h# 17 crt-mask

   f0 f0 h# 1b seq-mask  \ Secondary display clock on

   d# 1200 d# 900 d# 16 set-secondary-mode

\   60 60 9b crt-mask  \ Sync polarity - negative

   00 07 h# 79 crt-mask  \ Disable scaling
   00 37 h# a3 crt-mask  \ iga2 from S.L., start addr

   30 30 h# 1e seq-mask  \ Power up DVP1 pads

   0c 0c h# 2a seq-mask  \ Power up LVDS pads
   2b fb h# d2 crt-mask
   c0 c0 h# d4 crt-mask
   00 40 h# e8 crt-mask
   80 80 h# f3 crt-mask  \ 18-bit TTL mode
   0a h# f9 crt!
   0d h# fb crt!
   \ 1 01 h# 88 crt-mask  Something to do with LVDS; check
   \ set vclk
   \ VIASetOutputPath
   00 08 h# 6b crt-mask  \ Not simultaneous mode
\   DisableSecondDisplayChannel  XXX check me out

\ VIALCDPatchSkew
\ VIASetDisplayChannel  Seems to be lvds-specific

   40 40 h# 16 seq!  \ Check what is VIASR - is it really seq! ? - reserved bits, apparently control something about using crt and lcd at the same time

\ VIALoadLCDPatchRegs

   dcon-load
   dcon-enable  ( maybe-set-cmos )
   \ dcon-enable leaves mode set to 69 - 40:antialias, 20:swizzle, 8:backlight on, 1:passthru off
   d# 1200 depth 8 / * to /scanline
   set-fb
;

' panel2 is init-hook


\ LICENSE_BEGIN
\ Copyright (c) 2006 FirmWorks
\ 
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\ 
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\ 
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END
