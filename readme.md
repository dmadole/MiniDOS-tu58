# MiniDOS-tu58

This is an early preview of a TU58 disk driver for Mini/DOS. Although this is not a release at this point, it is functional and reliable.

This runs through the bit-bang serial port on an 1802/Mini or Pico/Elf at 38400 baud. This means you need a UART card to run your console through to use this.

If you don't have a TU58 then I can suggest this emulator which I have had good success with:

https://github.com/AK6DN/tu58em

A resonable command line for it would be something like:

tu58em -s 38400 -p 4 -w disk2.img -w disk3.img

Where "-p 4" designates to use COM4.

When the TU58 driver is loaded, it reinitializes the drive, and it will hang until it successfully does so. If you have a problem at this point, make sure your bit-band port and cable and port it's connected to all work well together. I suggest verifying that it works as a console. The TU58 drives start at //4 in this version.

On the 1802/Mini current firmware, there is a slight wrinkle which is that if a cable is plugged into the bit-bang console at boot time, it will use that port as the console. To work around this, only plug the TU58 cable in after the system is booted and has already chosen the UART port.

I will clean up and update this and produce a release version in the future with more features, including the ability to run on the Elf 2K as well.

