module icyprog.avrflash;

import std.compat;
import std.stdio;

import tango.core.Thread;

import icyprog.flash.base;
import icyprog.protocols.jtag;

class AVRFlash : Flash {
	TAPStateMachine tapState;
	
	this( TAPStateMachine tapState, uint flashSize ) {
		this.flashSize = flashSize;
		
		this.tapState = tapState;
	}
	
	public void ProgEnable( ) {
		// AVR_RESET
		tapState.GotoState( TAPState.TestLogicReset );
		tapState.ScanIR( 4, 0xc );
		tapState.ScanDR( 1, 0x01 );
		
		// PROG_ENABLE
		tapState.ScanIR( 4, 0x4 );
		tapState.ScanDR( 16, 0xa370 );
	}
	
	public void ProgCommands( ) {
		// PROG_COMMANDS
		tapState.ScanIR( 4, 0x5 );
	}
	
	public void ChipErase( ) {
		ProgEnable( );
		ProgCommands( );
		
		tapState.ScanDR( 15, 0x2380 ); // Chip Erase
		tapState.ScanDR( 15, 0x3180 );
		tapState.ScanDR( 15, 0x3380 );
		tapState.ScanDR( 15, 0x3380 );
		
		Thread.sleep( 0.010 );
	}
	
	public void WritePage( int pageNum, ubyte[] page ) {
		ProgCommands( );
		
		ubyte[] realPage;
		realPage.length = 128;
		//Array.Copy( page, 0, realPage, 0, page.Length );
		realPage[0..page.length] = page;
		
		int address = pageNum * 0x40;
		
		tapState.ScanDR( 15, 0x2310 ); // 2a. Enter Flash Write
		tapState.ScanDR( 15, 0x0700 | ((address>>8)&0xff) ); // 2b. Load Address High Byte
		tapState.ScanDR( 15, 0x0300 | ((address)&0xff) ); // 2c. Load Address Low Byte
		
		tapState.ScanIR( 4, 0x6 ); // PROG_PAGELOAD
		writefln( "--------------- START DATA PAGE %s ---------------", pageNum );
		tapState.ScanDR( 1024, realPage ); // Load Data Page
		writefln( "--------------- END DATA PAGE ---------------" );
		
		ProgCommands( );
		
		tapState.ScanDR( 15, 0x3700 ); // Write Page
		tapState.ScanDR( 15, 0x3500 );
		tapState.ScanDR( 15, 0x3700 );
		tapState.ScanDR( 15, 0x3700 );
		
		Thread.sleep( 0.010 );
	}
	
	public ubyte[] ReadPage( int pageNum ) {
		ubyte[] dummyData; // dummy data
		dummyData.length = 129;
		
		ProgCommands( );
		
		int address = pageNum * 0x40;
		
		tapState.ScanDR( 15, 0x2302 ); // 2a. Enter Flash Write
		tapState.ScanDR( 15, 0x0700 | ((address>>8)&0xff) ); // 2b. Load Address High Byte
		tapState.ScanDR( 15, 0x0300 | ((address)&0xff) ); // 2c. Load Address Low Byte
		
		tapState.ScanIR( 4, 0x7 ); // PROG_PAGEREAD
		TAPResponse pageData = tapState.ScanDRRecv( 1032, dummyData ); // Load Data Page
		
		ubyte[] outData = pageData.data[1..$].dup;
		//Array.Copy( pageData.data, 1, outData, 0, 128 );
		
		return outData;
	}
	
	public void LeaveProgMode( ) {
		ProgCommands( );
		
		tapState.ScanDR( 15, 0x2300 ); // 11a. Load No Operation Command
		tapState.ScanDR( 15, 0x3300 );
		
		// PROG_ENABLE
		tapState.ScanIR( 4, 0x4 );
		tapState.ScanDR( 16, 0x0000 );
		
		// AVR_RESET
		tapState.ScanIR( 4, 0xc );
		tapState.ScanDR( 1, 0x00 );
	}
	
	// FIXME: this isn't a job the flash would be doing. Move this to Chip later.
	public ubyte ReadFuseL( ) {
		ProgCommands( );
		
		tapState.ScanDR( 15, 0x2304 ); // 8a. Enter Fuse/Lock Bit Read
		tapState.ScanDR( 15, 0x3200 ); // 8c. Read Fuse Low Byte
		TAPResponse response = tapState.ScanDRRecv( 15, 0x3300 );
		
		return cast(ubyte)(cast(int)response.GetUInt16( ) & 0xFF);
	}
	
	public void WriteFuseL( ubyte fuseValue ) {
		ProgCommands( );
		
		writefln( "fuseL=%s", fuseValue );
		
		tapState.ScanDR( 15, 0x2340 ); // 6a. Enter Fuse Write
		tapState.ScanDR( 15, 0x1300 | fuseValue ); // 6e. Load Data Low Byte
		tapState.ScanDR( 15, 0x3300 ); // 6f. Write Fuse Low byte 
		tapState.ScanDR( 15, 0x3100 );
		tapState.ScanDR( 15, 0x3300 );
		tapState.ScanDR( 15, 0x3300 );
		
		// FIXME: Should do "6g. Poll for Fuse Write complete" here
		
		Thread.sleep( 1 );
	}
	
	public ubyte ReadFuseH( ) {
		ProgCommands( );
		
		tapState.ScanDR( 15, 0x2304 ); // 8a. Enter Fuse/Lock Bit Read
		tapState.ScanDR( 15, 0x3E00 ); // 8b. Read Fuse High Byte
		TAPResponse response = tapState.ScanDRRecv( 15, 0x3F00 );
		
		return cast(ubyte)(cast(int)response.GetUInt16( ) & 0xFF);
	}
	
	public void WriteFuseH( ubyte fuseValue ) {
		ProgCommands( );
		
		writefln( "fuseH=%s", fuseValue );
		
		const ubyte JTAGEN = (1<<6);
		
		// we don't want JTAG disabled. ever, ever, ever. catch it, just in case :)
		assert( (fuseValue & JTAGEN) == 0, "I don't think you really want JTAG disabled." );
		// i dont even trust assert always being right. bricking sucks.
		if ( !((fuseValue & JTAGEN) == 0) ) {
			throw new Exception( "NO BRICKING" );
			return; // in case "on error resume next" is ever implemented in D.
		}
		
		tapState.ScanDR( 15, 0x2340 ); // 6a. Enter Fuse Write
		tapState.ScanDR( 15, 0x1300 | fuseValue ); // 6b. Load Data Low Byte
		tapState.ScanDR( 15, 0x3700 ); // 6c. Write Fuse High byte
		tapState.ScanDR( 15, 0x3500 );
		tapState.ScanDR( 15, 0x3700 );
		tapState.ScanDR( 15, 0x3700 );
		
		// FIXME: Should do "6d. Poll for Fuse Write complete" here
		
		Thread.sleep( 1 );
	}
}
