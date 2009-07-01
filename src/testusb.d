module testusb;

import std.compat;
import std.stdio;

import usb.all;

int main( string[] args ) {
	writefln( "Searching busses..." );
	
	foreach ( bus; USB.busses ) {
		writefln( "  Searching devices..." );
		
		foreach( dev; bus.devices ) {
			writefln( "    %s", dev );
			
			foreach ( cfg; dev.configurations ) {
				//writefln( "      %s", cfg );
			}
		}
	}
	
	return 0;
}
