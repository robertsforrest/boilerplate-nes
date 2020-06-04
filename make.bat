writelevel background.txt background.bin
ca65 boilerplate.asm -o boilerplate.o --debug-info
ld65 boilerplate.o -o boilerplate.nes -t nes --dbgfile boilerplate.dbgfile
