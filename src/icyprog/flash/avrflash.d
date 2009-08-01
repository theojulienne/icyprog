module icyprog.flash.avrflash;

import std.compat;
import std.stdio;

import tango.core.Thread;

import icyprog.board;
import icyprog.chips.avr;
import icyprog.flash.base;
import icyprog.protocols.jtag;

class AVRFlash : Flash {
	TAPStateMachine tapState;
	
	AVRChip chip;
	
	this( AVRChip c, uint flashSize ) {
		super( c );
		
		chip = c;
		
		tapState = chip.board.sm;
		
		this.memoryBytes = flashSize;
		this.pageBytes = 128; // FIXME: always the same? 64 words, 128 bytes
		
		this.tapState = tapState;
	}
	
	public void erase( ) {
		chip.fullChipErase( );
	}
	
	public void writePage( uint pageIndex, ubyte[] data ) {
		chip.enterProgMode( );
		chip.enterProgCommands( );
		
		assert( data.length <= pageBytes );
		
		ubyte[] realPage;
		realPage.length = pageBytes;
		realPage[0..data.length] = data;
		
		int address = pageIndex * 0x40;
		
		tapState.ScanDR( 15, 0x2310 ); // 2a. Enter Flash Write
		tapState.ScanDR( 15, 0x0700 | ((address>>8)&0xff) ); // 2b. Load Address High Byte
		tapState.ScanDR( 15, 0x0300 | ((address)&0xff) ); // 2c. Load Address Low Byte
		
		tapState.ScanIR( 4, 0x6 ); // PROG_PAGELOAD
		//writefln( "--------------- START DATA PAGE %s ---------------", pageIndex );
		tapState.ScanDR( 1024, realPage ); // Load Data Page
		//writefln( "--------------- END DATA PAGE ---------------" );
		
		chip.enterProgCommands( );
		
		tapState.ScanDR( 15, 0x3700 ); // Write Page
		tapState.ScanDR( 15, 0x3500 );
		tapState.ScanDR( 15, 0x3700 );
		tapState.ScanDR( 15, 0x3700 );
		
		Thread.sleep( 0.010 );
	}
	
	public ubyte[] readPage( uint pageIndex ) {
		ubyte[] dummyData; // dummy data
		dummyData.length = pageBytes + 1; // AVR returns 1 extra byte at the start
		
		chip.enterProgMode( );
		chip.enterProgCommands( );
		
		int address = pageIndex * 0x40;
		
		tapState.ScanDR( 15, 0x2302 ); // 2a. Enter Flash Write
		tapState.ScanDR( 15, 0x0700 | ((address>>8)&0xff) ); // 2b. Load Address High Byte
		tapState.ScanDR( 15, 0x0300 | ((address)&0xff) ); // 2c. Load Address Low Byte
		
		tapState.ScanIR( 4, 0x7 ); // PROG_PAGEREAD
		uint numReceivedBits = dummyData.length * 8;
		TAPResponse pageData = tapState.ScanDRRecv( numReceivedBits, dummyData ); // Load Data Page
		
		ubyte[] outData = pageData.data[1..$].dup;
		
		return outData;
	}
	
	public void finished( ) {
		chip.exitProgMode( );
	}
}
