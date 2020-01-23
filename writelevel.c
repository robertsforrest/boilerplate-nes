#include<stdio.h>
#include<stdlib.h>
#include<string.h>

#define MAXCHR 1000
#define LVLBYTES 960
// usage: writelevel input.txt output.bin
int main(int argc, char **argv) {
	char str[MAXCHR];
	FILE *ptr = fopen(argv[2],"wb");
	FILE *read = fopen(argv[1],"r");

	while (fgets(str, MAXCHR, read)!=NULL) {
		// remove newline from line
		char* pos;
		if ((pos=strchr(str,'\n'))!=NULL) {
			*pos='\0';
		}

		// parse the string word by word
		char* tok = (char*)strtok(str," ");
		while (tok!=NULL) {
			// write data to binary file
			int hextok = (int)strtol(tok,NULL,16);
			fwrite(&hextok, 1, 1, ptr);
			//printf("%x\n", hextok);

			// increment token
			tok = strtok(NULL," ");

		}
	}
	
	fclose(read);
	fclose(ptr);
}
