
all: tu58.bin

lbr: tu58.lbr

clean:
	rm -f tu58.lst
	rm -f tu58.bin
	rm -f tu58.lbr

tu58.bin: tu58.asm include/bios.inc include/kernel.inc
	asm02 -L -b tu58.asm
	rm -f tu58.build

tu58.lbr: tu58.bin
	rm -f tu58.lbr
	lbradd tu58.lbr tu58.bin

