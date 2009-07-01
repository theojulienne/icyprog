LIB=usbwrapper

all: lib$(LIB).a

lib$(LIB).a: $(LIB).o
	ar rcs lib$(LIB).a $(LIB).o

$(LIB).o: $(LIB).c
	gcc -g -c $(LIB).c -o $(LIB).o -I/sw/include