
;  Copyright 2021, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; Include kernal API entry points

            #include include/bios.inc
            #include include/kernel.inc


          ; Define non-published API elements

d_ideread:  equ   0447h
d_idewrite: equ   044ah


          ; I/O pin definitions for the bit-bang serial routines. These are by
          ; default compatible with the 1802/Mini and Pico/Elf machines.

#define BRMK bn2
#define BRSP b2
#define SESP req
#define SEMK seq


          ; Packet usage for TU58 MSP protocol

#define TU_DATA %00001
#define TU_CTRL %00010
#define TU_INIT %00100
#define TU_BOOT %01000
#define TU_CONT %10000
#define TU_XOFF %10011

#define TU_READ  2
#define TU_WRITE 3


          ; Executable program header

            org   2000h - 6
            dw    start
            dw    end-start
            dw    start

start:      br    entry


          ; Build information

            db    4+80h                 ; month
            db    21                    ; day
            dw    2025                  ; year
            dw    0                     ; build

            db    'See github.com/dmadole/MiniDOS-tu58 for more info',0


          ; Check if hook points have already been patched and do not
          ; install if so, since we don't know what it is or what the
          ; impact might be of disconnecting it.

entry:      sep   scall
            dw    o_inmsg
            db    'TU58 Disk Driver Build 0 for Mini/DOS',13,10
            db    'Configured for 38.4 Kbps on EF2 and Q',13,10,0


          ; Check minimum needed kernel version 0.4.0 in order to have
          ; heap manager available.

chekvers:   ldi   high k_ver            ; pointer to installed kernel version
            phi   rd
            ldi   low k_ver
            plo   rd

            lda   rd                    ; if major is non-zero then good
            lbnz  getopts

            lda   rd                    ; if minor is 4 or more then good
            smi   4
            lbdf  getopts

            sep   scall                 ; quit with error message
            dw    o_inmsg
            db    'ERROR: Needs kernel version 0.4.0 or higher',13,10,0
            sep   sret


          ; Parse the command-line arguments to build a list of port select
          ; groups to search on for drives.

getopts:    lbr   loadmod


          ; Display a minimally-helpful message is something went wrong.

dousage:    sep   scall                 ; error if bad syntax
            dw    o_inmsg
            db    'USAGE: tu58 [-u unit] ...',13,10,0

            sep   sret


          ; Allocate a page-aligned block from the heap for storage of
          ; the persistent code module. Make it permanent so it will
          ; not get cleaned up at program exit.

loadmod:    ldi   (modend-module).1     ; length of module in rc
            phi   rc
            ldi   (modend-module).0
            plo   rc

            ldi   255                   ; page-aligned
            phi   r7
            ldi   4 ; +64               ; permanent and named
            plo   r7

            sep   scall                 ; request memory block
            dw    o_alloc
            lbnf  gotalloc

            sep   scall                 ; return with error
            dw    o_inmsg
            db    'ERROR: Could not allocate memeory from heap',13,10,0
            sep   sret

gotalloc:   ghi   rf                    ; Offset to adjust addresses with
            smi   module.1
            str   r2


          ; Copy common module code into the permanent heap block

            ldi   module.1              ; get source address
            phi   rb
            glo   rf
            plo   rb

copymod:    lda   rb                    ; copy code to destination address
            str   rf
            inc   rf
            dec   rc
            glo   rc
            lbnz  copymod
            ghi   rc
            lbnz  copymod


          ; Update kernel hooks to point to the copied module code

            ldi   high patchtbl         ; Get point to table of patch points
            phi   rd
            ldi   low patchtbl
            plo   rd

hookloop:   lda   rd                    ; a zero marks end of the table
            lbz   finished

            phi   rf                    ; get pointer to vector to hook
            lda   rd
            plo   rf

            inc   rf                    ; skip the lbr opcode

            lda   rd                    ; add offset to get copy address
            add                         ;  and update into vector
            str   rf
            inc   rf
            lda   rd
            str   rf

            lbr   hookloop              ; repeat for all


          ; All done, exit to operating system

finished:   ldi   txbreak.1
            phi   ra

initial:    ldi   txbreak               ; send a break condition on line
            plo   ra
            sep   ra

            nop                         ; send a single-byte init packet
            nop
            ldi   TU_INIT
            sep   ra

            nop                         ; then send a second init packet
            nop
            ldi   TU_INIT
            sep   ra

            ldi   rxstart               ; receive a character from tu58
            plo   ra
            sep   ra

            xri   TU_CONT                ; if not continue try reset again
            bnz   initial

            sep   sret


          ; Table giving addresses of jump vectors we need to update, along
          ; with offset from the start of the module to repoint those to.

patchtbl:   dw    d_ideread, turead
            dw    d_idewrite, tuwrite
            db    0


          ; Start the actual module code on a new page so that it forms
          ; a block of page-relocatable code that will be copied to himem.

            org   $ + 0ffh & 0ff00h

module: 



readerr:    smi   0
            sep   sret


turead:     ghi   r8
            ani   31
            smi   4
            lbnf  0ff3ch

            glo   r8                    ; error if block greater than 65535
            bnz   readerr


            glo   r9                    ; to use for checksum calculation
            stxd
            ghi   r9
            stxd

            glo   ra                    ; to use for subroutine pointer
            stxd
            ghi   ra
            stxd

            glo   rb                    ; to use for buffer pointer
            stxd
            ghi   rb
            stxd


         ;; Register RA is used to call subroutines via SEP, and RB is used as
         ;; a pointer into the header buffer. Both of these are in a separate
         ;; page of memory, so initialize the page part accordingly.

            ghi   r3                    ; subroutines and header buffer page
            adi   checksm.1-$.1
            phi   ra
            phi   rb


         ;; The command packet for a read operation is already pre-formed in
         ;; memory, we just need to populate the unit number and address.

            ldi   readpkt+2             ; pointer to unit number in packet
            plo   rb

            ldi   TU_READ               ; set operation code into packet
            str   rb

            inc   rb                    ; skip to unit number field
            inc   rb

            ghi   r8                    ; set disk unit number to packet
            ani   31
            smi   4
            str   rb

            ldi   readpkt+10            ; pointer to block number in packet
            plo   rb

            glo   r7                    ; set block in packet and checksum
            str   rb
            inc   rb
            ghi   r7
            str   rb




            ldi   checksm               ; set subroutine pointer to checksum
            plo   ra

            ldi   readpkt               ; pointer back to start of packet
            plo   rb

            lda   rb                    ; load first two bytes to checksum
            plo   r9
            lda   rb
            phi   r9

            plo   re                    ; count of the payload data bytes
            sex   rb
            sep   ra                    ; calculate checksum of payload bytes

            glo   r9                    ; store the checksum into the packet
            str   rb
            inc   rb
            ghi   r9
            str   rb




            ldi   txstart               ; point to transmit routine
            plo   ra

            ldi   readpkt               ; pointer back to start of packet
            plo   rb

            ldi   14                    ; total size of packet to send
            plo   re

loop:       dec   re                    ; decrement count and sent byte
            lda   rb
            sep   ra

            glo   re                    ; continue until all are sent
            bnz   loop




            ldi   rxstart               ; point to receive routine
            plo   ra

getrx:      sep   ra                    ; get packet type and save to buffer
            str   rb
            inc   rb

            xri   TU_DATA                ; get last if it is not a data packet
            bnz   endpkt

            sep   ra                    ; get length byte and save to buffer
            str   rb
            inc   rb

            plo   re                    ; length of data payload to receive

data:       dec   re                    ; decrement count and receive byte
            sep   ra

            str   rf                    ; store into the sector data buffer
            inc   rf

            glo   re                    ; continue until all data is received
            bnz   data

            sep   ra                    ; get checksum low byte
            str   rb
            inc   rb

            sep   ra                    ; get checksum high byte
            str   rb
            inc   rb

            br    getrx                 ; get next packet




endpkt:     sep   ra                    ; get length byte and save to buffer
            str   rb
            inc   rb

            plo   re                    ; length of data payload to receive
            inc   re
            inc   re

endrd:      sep   ra                    ; receive next byte into header buffer
            str   rb
            inc   rb

            dec   re                    ; continue until all received
            glo   re
            bnz   endrd


         ;; Check if the right amount of data was read. It should be four
         ;; packets of 128 data bytes each plus one 14 byte end packet.

            glo   rb                    ; check total non-data bytes received
            smi   readpkt+14+16+14
            bnz   error

         ;; Next check if each packet received is actually 128 bytes.

            ldi   readpkt+14            ; point to first packet received
            plo   rb

            br    checklen

lenloop:    lda   rb                    ; check that the length is 128 bytes
            smi   128
            bnz   error

            inc   rb                    ; skip the two checksum bytes for now
            inc   rb
           
checklen:   lda   rb                    ; get packet type and save a copy
            plo   r9

            smi   TU_DATA               ; continue until not a data packet
            bz    lenloop


         ;; Check if the end packet is valid, that is is a control packet
         ;; type and that the checksum of the packet is correct.

            ldi   checksm               ; pointer to checksum subroutine
            plo   ra

            glo   r9                    ; check if a control type packet
            smi   TU_CTRL
            bnz   error

            lda   rb                    ; get length, set checksum and count
            phi   r9

            plo   re
            sex   rb                    ; checksum then packet payload
            sep   ra

            glo   r9                    ; if checksum low mismatch then error
            sm
            inc   rb
            bnz   error

            ghi   r9                    ; if checksum high mismatch then error
            sm
            inc   rb
            bnz   error

         ;; Next verify that it is an end packet and that the read status was
         ;; success with no errors.

            ldi   readpkt+14+16+2
            plo   rb

            lda   rb                    ; if not an end packet then error
            smi   %01000000
            bnz   error

            ldn   rb                    ; check that read successful
            bnz   error



         ;; If the correct number of packets and bytes was recevied, and the
         ;; end packet is valid and indicates the read ws successful, then
         ;; finally check the data packet checksums.

            ghi   rf                    ; reset to start of the sector buffer
            smi   512.1
            phi   rf

            ldi   readpkt+14            ; point to first data packet header
            plo   rb

            br    chkdata               ; jump into loop to get started

chkloop:    lda   rb                    ; get length type, store to checksum
            phi   r9

            plo   re
            sex   rf                    ; checksum all the data bytes
            sep   ra

            sex   rb                    ; point back to header buffer

            glo   r9                    ; if checksum low mismatch then error
            sm
            irx
            bnz   error

            ghi   r9                    ; if checksum high mismatch then error
            sm
            irx
            bnz   error

chkdata:    lda   rb                    ; get packet type, store to checksum
            plo   r9

            smi   TU_DATA               ; if not data then process last
            bnz   chkloop




            shr                         ; clear df since successful

return:     sex   r2

            irx
            ldxa
            phi   rb
            ldxa
            plo   rb

            ldxa
            phi   ra
            ldxa
            plo   ra

            ldxa
            phi   r9
            ldx
            plo   r9

            sep   sret

error:      smi   0
            br    return




            org   $ + 0ffh & 0ff00h


writerr:    smi   0
            sep   sret


tuwrite:    ghi   r8
            ani   31
            smi   4
            lbnf  0ff39h

            glo   r8                    ; error if block greater than 65535
            bnz   writerr


            glo   r9                    ; to use for checksum calculation
            stxd
            ghi   r9
            stxd

            glo   ra                    ; to use for subroutine pointer
            stxd
            ghi   ra
            stxd

            glo   rb                    ; to use for buffer pointer
            stxd
            ghi   rb
            stxd

            glo   rf                    ; save so we can reset to start
            stxd
            ghi   rf
            stxd


         ;; Register RA is used to call subroutines via SEP, and RB is used as
         ;; a pointer into the header buffer. Both of these are in a separate
         ;; page of memory, so initialize the page part accordingly.

            ghi   r3                    ; subroutines and header buffer page
            adi   checksm.1-$.1
            phi   ra
            phi   rb

         ;; The command packet for a read operation is already pre-formed in
         ;; memory, we just need to populate the unit number and address.

            ldi   readpkt+2             ; pointer to unit number in packet
            plo   rb

            ldi   TU_WRITE
            str   rb
            inc   rb
            inc   rb

            ghi   r8                    ; insert unit number to packet
            ani   31
            smi   4
            str   rb

            ldi   readpkt+10            ; pointer to block number in packet
            plo   rb

            glo   r7                    ; set block in packet and checksum
            str   rb
            inc   rb

            ghi   r7
            str   rb
            inc   rb




            ldi   checksm               ; set subroutine pointer to checksum
            plo   ra

            ldi   readpkt               ; pointer back to start of packet
            plo   rb

            lda   rb                    ; load first two bytes to checksum
            plo   r9
            lda   rb
            phi   r9

            ldi   10                    ; count of the payload data bytes
            plo   re

            sex   rb                    ; calculate checksum of payload bytes
            sep   ra

            glo   r9                    ; store the checksum into the packet
            str   rb
            inc   rb

            ghi   r9
            str   rb
            inc   rb




            ldi   checksm
            plo   ra

wloop1:     ldi   TU_DATA
            str   rb
            inc   rb

            plo   r9

            ldi   128
            str   rb
            inc   rb

            phi   r9
            plo   re

            sex   rf
            sep   ra

            glo   r9
            str   rb
            inc   rb

            ghi   r9
            str   rb
            inc   rb

            glo   rb
            xri   readpkt+14+16
            bnz   wloop1


            inc   r2                    ; reset sector buffer pointer to start
            lda   r2
            phi   rf
            ldn   r2
            plo   rf



            ldi   txstart               ; point to transmit routine
            plo   ra

            ldi   readpkt
            plo   rb

            ldi   14                    ; total size of packet to send
            plo   re

loopw:      dec   re                    ; decrement count and sent byte
            lda   rb
            sep   ra

            glo   re                    ; continue until all are sent
            bnz   loopw



w3loop:     ldi   rxstart
            plo   ra

            sep   ra

            xri   TU_CONT
            bnz   wend



            ldi   txstart               ; point to transmit routine
            plo   ra

            lda   rb
            sep   ra

            lda   rb
            plo   re
            plo   re
            plo   re
            sep   ra

            glo   re
            glo   re

w2loop:     dec   re
            lda   rf
            sep   ra

            glo   re
            bnz   w2loop

            ldn   rb
            lda   rb
            sep   ra

            nop
            nop
            lda   rb
            sep   ra

            br    w3loop





wend:       xri   TU_CONT
            str   rb
            inc   rb

            sep   ra                    ; get length byte and save to buffer
            str   rb
            inc   rb

            ldi   12
            plo   re                    ; length of data payload to receive

endwr:      sep   ra                    ; receive next byte into header buffer
            str   rb
            inc   rb

            dec   re                    ; continue until all received
            glo   re
            bnz   endwr



            glo   rb                    ; check total non-data bytes received
            smi   readpkt+14+16+14
            bnz   werror

            ldi   readpkt+14+16         ; point to first packet received
            plo   rb



            ldi   checksm               ; pointer to checksum subroutine
            plo   ra

            lda   rb                    ; check if control packet for end
            plo   r9

            smi   TU_CTRL
            bnz   werror

            lda   rb                    ; get length of packet
            phi   r9
            plo   re

            smi   10                    ; if length if not 10 then error
            bnz   werror

            lda   rb                    ; check if an end packet
            smi   %01000000
            bnz   werror

            ldn   rb                    ; check that read successful
            dec   rb
            bnz   werror

            sex   rb                    ; checksum then packet payload
            sep   ra

            glo   r9                    ; if checksum low mismatch then error
            sm
            inc   rb
            bnz   werror

            ghi   r9                    ; if checksum high mismatch then error
            sm
            inc   rb
            bnz   werror


            adi   0
            br    wreturn

werror:     smi   0

wreturn:    inc   r2
            lda   r2
            phi   rb
            lda   r2
            plo   rb

            lda   r2
            phi   ra
            lda   r2
            plo   ra

            lda   r2
            phi   r9
            ldn   r2
            plo   r9

            sep   sret


            org   $ + 0ffh & 0ff00h

         ;; CHECKSM - Calculate a 16-bit checksum with "end-around carry".
         ;;
         ;; RX   - Pointer to block to be checksummed
         ;; RE.0 - Number of bytes to checksum
         ;; R9 -   Returns checksum
         ;;
         ;; This does not properly checksum blocks of an odd length, but that
         ;; is not a problem since an odd length itself indicates an error and
         ;; we will check for that separately.

checkrt:    sep   r3

checksm:    glo   re
            shr
            plo   re

sumloop:    glo   r9
            adc
            irx
            plo   r9

            ghi   r9
            adc
            irx
            phi   r9

            dec   re
            glo   re
            bnz   sumloop

            bnf   checkrt
            inc   r9
            br    checkrt




txbreak:    SESP                        ; assert space on line to break idle

            ldi   30                    ; delay for 122 machine cycles more
txdelay:    smi   1
            bnz   txdelay

            br    txstop                ; set line idle again and return


         ;; Send a character through the Q interface at 38,400 bps. Called via
         ;; SEP using any register; on entry, the character to send is in D.
         ;; The character is preserved on exit and copied to RE.0. The
         ;; register used to call will be reset to the entry point.
         ;;
         ;; To send back-to-back, call again 8 cycles after return, not
         ;; including the SEP itself. Less than this will result in a framing
         ;; error at the receiver. More is ok but will reduce the throughput.

txstop:     shr
            SEMK                        ; assert the stop bit and then return
            sep   r3

txstart:    SESP                        ; save, send start, shift in a one
            SESP
            smi   0

txspace:    shrc                        ; get next, exit if all, else send it
txmark:     bz    txlast
            lsdf

            SESP                        ; send space, loop to shift in a zero
            skp

            SEMK                        ; send mark, loop to shift in a zero
            bnf   txspace

            shr
            bnz   txmark

txlast:     br    txstop








         ;; Receive a character through EF interface at 38,400 bps. Called via
         ;; SEP using any register. On exit, D will contain the received
         ;; character and DF will be set. The register used to call will be
         ;; reset to the entry point.
         ;;
         ;; To receive back-to-back, call again 10 cycles after return, not
         ;; including the SEP itself. Less than this is ok. More will result in
         ;; dropped characters and loss of syncronization with the sender.

rxfinal:    sep   r3

rxstart:    BRMK  rxstart               ; entry point, wait for start bit

            ldi   %10000000             ; load stop bit then delay 6 cycles
            nop
            nop
            nop

rxloop:     shr                         ; get next bit, send mark if a one
            nop
            BRMK  rxmark
            br    rxspace

rxmark:     ori   %10000000
rxspace:    bdf   rxfinal               ; exit if last bit else get next bit
            br    rxloop




readpkt:    db    TU_CTRL,10            ; packet type, message bytes
            db    TU_READ,0             ; operation code, modifier flags
            db    0,0                   ; unit number, switches
            db    0,0                   ; sequence number
            db    0,2                   ; byte count
            db    0,0                   ; block number
            db    0,0                   ; checksum

            ds    4
            ds    4
            ds    4
            ds    4

            ds    14

modend:


end:      ; That's all folks!

