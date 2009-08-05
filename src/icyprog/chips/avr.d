module icyprog.chips.avr;

import std.compat;
import std.stdio;

import tango.core.Thread;

import icyprog.board;
import icyprog.chip;
import icyprog.protocols.jtag;

class AVRChip : Chip {
	bool _avrReset = false;
	bool _progEnable = false;
	
	this( Board b ) {
		super( b );
	}
	
	TAPStateMachine tapState( ) {
		return board.sm;
	}
	
	public void avrReset( bool val ) {
		if ( _avrReset == val ) {
			return;
		}
		
		_avrReset = val;
		
		tapState.GotoState( TAPState.TestLogicReset );
		tapState.ScanIR( 4, 0xc );
		
		if ( val ) {
			tapState.ScanDR( 1, 0x01 );
		} else {
			tapState.ScanDR( 1, 0x00 );
		}
	}
	
	public void progEnable( bool val ) {
		if ( _progEnable == val ) {
			return;
		}
		
		_progEnable = val;
		
		tapState.GotoState( TAPState.TestLogicReset );
		tapState.ScanIR( 4, 0x4 );
		
		if ( val ) {
			tapState.ScanDR( 16, 0xa370 );
		} else {
			tapState.ScanDR( 16, 0x0000 );
		}
	}
	
	public void enterProgMode( ) {
		// order is important
		this.avrReset = true;
		this.progEnable = true;
	}
	
	public void enterProgCommands( ) {
		// PROG_COMMANDS
		tapState.ScanIR( 4, 0x5 );
	}
	
	public void exitProgMode( ) {
		enterProgCommands( );
		
		tapState.ScanDR( 15, 0x2300 ); // 11a. Load No Operation Command
		tapState.ScanDR( 15, 0x3300 );
		
		// order is important
		this.progEnable = false;
		this.avrReset = false;
	}
	
	public ubyte ReadFuseL( ) {
		enterProgMode( );
		enterProgCommands( );
		
		tapState.ScanDR( 15, 0x2304 ); // 8a. Enter Fuse/Lock Bit Read
		tapState.ScanDR( 15, 0x3200 ); // 8c. Read Fuse Low Byte
		TAPResponse response = tapState.ScanDRRecv( 15, 0x3300 );
		
		return cast(ubyte)(cast(int)response.GetUInt16( ) & 0xFF);
	}
	
	public void WriteFuseL( ubyte fuseValue ) {
		enterProgMode( );
		enterProgCommands( );
		
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
		enterProgMode( );
		enterProgCommands( );
		
		tapState.ScanDR( 15, 0x2304 ); // 8a. Enter Fuse/Lock Bit Read
		tapState.ScanDR( 15, 0x3E00 ); // 8b. Read Fuse High Byte
		TAPResponse response = tapState.ScanDRRecv( 15, 0x3F00 );
		
		return cast(ubyte)(cast(int)response.GetUInt16( ) & 0xFF);
	}
	
	public void WriteFuseH( ubyte fuseValue ) {
		enterProgMode( );
		enterProgCommands( );
		
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
	
	void showInformation( ) {
		enterProgMode( );
		enterProgCommands( );
		scope(exit) exitProgMode( );
		
		TAPResponse response;
		
		tapState.ScanDR( 15, 0x2308 ); // 9a. Enter Signature Byte Read
		
		tapState.ScanDR( 15, 0x0300 ); // 9b. Load Address Byte 0x00
		tapState.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = tapState.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x1E ) {
			writefln( "Manufacturer: Atmel [0x1E]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
		
		tapState.ScanDR( 15, 0x0301 ); // 9b. Load Address Byte 0x01
		tapState.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = tapState.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x95 ) {
			writefln( "Flash capacity: 32KB [0x95]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
		
		tapState.ScanDR( 15, 0x0302 ); // 9b. Load Address Byte 0x02
		tapState.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = tapState.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x02 ) {
			writefln( "Part: ATMega32A [0x02]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
	}
	
	
	public void fullChipErase( ) {
		enterProgMode( );
		enterProgCommands( );
		scope(exit) exitProgMode( );
		
		tapState.ScanDR( 15, 0x2380 ); // Chip Erase
		tapState.ScanDR( 15, 0x3180 );
		tapState.ScanDR( 15, 0x3380 );
		tapState.ScanDR( 15, 0x3380 );
		
		Thread.sleep( 0.010 );
	}
}
