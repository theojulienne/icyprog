module icyprog.main;

import std.compat;
import std.stdio;
import std.string;

import tango.io.device.File;
import tango.io.device.Conduit;
import tango.util.ArgParser;

import icyprog.protocols.jtag;
import icyprog.debuginterface;
import icyprog.interfaces.penguinoavr;
import icyprog.flash.avrflash;

import icyprog.chip;
import icyprog.board;
import icyprog.memory;

bool startswith( string haystack, string needle ) {
	return ( haystack[0..needle.length] == needle );
}

int main( string[] argv ) {
	
	Board.enumerateBoards( );
	scope(exit) Board.invalidateBoards( );
	
	string[] args = argv[1..$];
	
	string[string] uploadTargets;
	
	foreach ( arg; args ) {
		if ( arg.startswith( "--upload-" ) ) {
			string trail = arg[9..$];
			string[] parts = trail.split( "=" );
			
			if ( parts.length != 2 ) {
				throw new Exception( "Argument requires exactly 1 value: " ~ arg );
			}
			
			string destination = parts[0];
			string inputFilename = parts[1];
			
			if ( destination != "flash" ) {
				throw new Exception( "Unknown upload target: " ~ destination );
			}
			
			//writefln( "%s <- %s", destination, inputFilename );
			uploadTargets[destination] = inputFilename;
		} else {
			throw new Exception( "Unknown argument: " ~ arg );
		}
	}
	
	writefln( "Boards: %s", Board.boards.size );
	assert( Board.boards.size > 0 );
	writefln( "Assuming first board..." );
	Board board = Board.boards.get( 0 );
	Chip chip = board.chips["user"]; // FIXME: assuming "user" chip
	
	board.showInformation( );
	
	foreach ( uploadTarget, uploadFilename; uploadTargets ) {
		Memory targetMemory = chip.getMemory( uploadTarget );
		
		writefln( "" );
		writefln( "Target name: %s", uploadTarget );
		writefln( "Target size: %s bytes", targetMemory.memoryBytes );
		writefln( "Target page size: %s bytes", targetMemory.pageBytes );
		writefln( "Target pages: %s pages", targetMemory.numPages );
		writefln( "Source filename: %s", uploadFilename );
		
		File file = new File( uploadFilename );
		
		int sourceBytes = file.length;
		
		writefln( "" );
		writefln( "Erasing %s...", uploadTarget );
		targetMemory.erase( );
		
		void reportOperationProgress( uint bytesCompleted ) {
			if ( bytesCompleted > sourceBytes )
				bytesCompleted = sourceBytes;
			
			writef( "\r  [" );
			
			int progressLength = 65;
			int bytesPerChunk = sourceBytes / progressLength;
			
			for ( int i = 0; i < progressLength; i++ ) {
				
				if ( bytesCompleted > i * bytesPerChunk ) {
					writef( "#" );
				} else {
					writef( "." );
				}
				
			}
			
			float progressPercent = 0;
			
			if ( sourceBytes > 0 ) {
				progressPercent = (cast(float)bytesCompleted / cast(float)sourceBytes) * 100;
			}
			
			writef( "] %3.2f%%   (%d of %d bytes)", progressPercent, bytesCompleted, sourceBytes );
			fflush( stdout );
		}
		
		writefln( "\n" );
		writefln( "Writing %s...", uploadTarget );
		writef( " ~ starting ~ " );
		targetMemory.writeStream( file, &reportOperationProgress );
		
		writefln( "\n" );
		writefln( "Verifying %s...", uploadTarget );
		writef( " ~ starting ~ " );
		targetMemory.verifyStream( file, &reportOperationProgress );
		
		writefln( "\n" );
		
		targetMemory.finished( );
	}
	
	writefln( "" );
	
	/*
	PenguinoAVRInterface.DiscoverInterfaces( );
	
	DebugInterface[] ifaces = DebugInterface.GetInstancesForInterface!(PenguinoAVRInterface)();
	
	if ( ifaces.length > 0 ) {
		DebugInterface iface = ifaces[0];
		
		// typeof(IJTAG).IsAssignableFrom( iface.GetType( ) )
		IJTAG jtagiface = cast(IJTAG)iface;
		scope(exit) delete jtagiface; // destroy it, so interfaces are released
	
		writefln( "%s", iface.GetInterfaceName( ) );
	
		TAPStateMachine sm = new TAPStateMachine( jtagiface );
		
		jtagiface.JTAGReset( true, true );
	
		TAPResponse response;
	
		sm.GotoState( TAPState.ShiftIR );
		
		int i;
		// Send plenty of ones into the IR registers
		// That makes sure all devices are in BYPASS!
		for ( i = 0; i < 999; i++ ) {
			// send 1 bit at a time, value of "1", TMS low
			sm.SendCommand( TAPCommand.SendData( 1, 0x1, 0x00 ) );
		}
		sm.SendCommand( TAPCommand.SendData( 1, 0x1, 0x01 ) );
		
		// we are in Exit1-IR, go to Shift-DR
		sm.GotoState( TAPState.ShiftDR );
		
		// Send plenty of zeros into the DR registers to flush them
		for ( i = 0; i < 1000; i++ ) {
			// send 1 bit at a time, value of "0", TMS low
			sm.SendCommand( TAPCommand.SendData( 1, 0x00 ) );
		}
		
		// now send ones until we receive one back
		for ( i = 0; i < 1000; i++ ) {
			// send 1 bit at a time, value of "1", TMS low
			response = sm.SendCommand( TAPCommand.SendReceiveData( 1, 0x01 ) );
			
			if ( response.GetBit( 0 ) )
				break;
		}
		
		int numDevices = i;
		writefln( "There are %s device(s) in the JTAG chain\n", numDevices );
	
	
		// Read IDCODEs
		sm.GotoState( TAPState.TestLogicReset );
		sm.GotoState( TAPState.ShiftDR );
		for ( i=0; i < numDevices; i++ ) {
			response = sm.SendCommand( TAPCommand.ReceiveData( 32 ) );
			uint id = response.GetUInt32( );
			TAPDeviceIDRegister reg = TAPDeviceIDRegister.ForID( id );

			writefln( "[%s] IDCODE = %s: %s\n", i, id, reg );
		}
		
		
		// AVR_RESET
		sm.GotoState( TAPState.TestLogicReset );
		sm.ScanIR( 4, 0x0c );
		sm.ScanDR( 1, 0x01 );
		
		// PROG_ENABLE
		sm.ScanIR( 4, 0x04 );
		sm.ScanDR( 16, 0xa370 );
		
		// skip erase for now
		
		// PROG_COMMANDS
		sm.ScanIR( 4, 0x05 );
		sm.ScanDR( 15, 0x2308 ); // 9a. Enter Signature Byte Read
		
		sm.ScanDR( 15, 0x0300 ); // 9b. Load Address Byte 0x00
		sm.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = sm.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x1E ) {
			writefln( "Manufacturer: Atmel [0x1E]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
		
		sm.ScanDR( 15, 0x0301 ); // 9b. Load Address Byte 0x01
		sm.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = sm.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x95 ) {
			writefln( "Flash capacity: 32KB [0x95]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
		
		sm.ScanDR( 15, 0x0302 ); // 9b. Load Address Byte 0x02
		sm.ScanDR( 15, 0x3200 ); // 9c. Read Signature Byte
		response = sm.ScanDRRecv( 15, 0x3300 );
		if ( (cast(int)response.GetUInt16( ) & 0xFF) == 0x02 ) {
			writefln( "Part: ATMega32A [0x02]" );
		} else {
			throw new Exception( "I don't understand other parts, sorry!" );
		}
		
		writefln( "I've found an ATMega32A in the signature bytes! Woohoo!" );
		
		AVRFlash fl = new AVRFlash( sm, 32*1024 );
		
		fl.ChipErase( );
		
		//FileStream file = new FileStream( "prog.bin", FileMode.Open, FileAccess.Read );
		//BinaryReader br = new BinaryReader( file );
		File file = new File( "prog.bin" );
		
		int page = 0;
		int bytesRead = 1;
		while ( bytesRead > 0 ) {
			ubyte[] bytes;
			bytes.length = 0x80;
			int numBytes = file.read( bytes );
			
			if ( numBytes == IConduit.Eof )
				break;
			
			bytes.length = numBytes;
			
			writefln( "Writing %s bytes to page %s", bytes.length, page );
			fl.WritePage( page, bytes );
			bytesRead = bytes.length;
			page++;
		}
		
		writefln( "Done, seeking to 0..." );
		
		file.seek( 0, File.Anchor.Begin );
		
		page = 0;
		bytesRead = 1;
		while ( bytesRead > 0 ) {
			ubyte[] correctBytes;
			correctBytes.length = 0x80;
			int numBytes = file.read( correctBytes );
			
			ubyte[] verifyBytes = fl.ReadPage( page );
			
			if ( numBytes == IConduit.Eof )
				break;
			
			correctBytes.length = numBytes;
			
			writefln( "Reading %s bytes from page %s", correctBytes.length, page );
			
			for ( int j = 0; j < correctBytes.length; j++ ) {
				//writefln( "%s == %s", correctBytes[j], verifyBytes[j] );
				
				if ( correctBytes[j] != verifyBytes[j] ) {
					writefln( "Error with byte %s in page %s (expected %s, read %s)", j, page, correctBytes[j], verifyBytes[j] );
					throw new Exception( "Verify failed!" );
				}
			}
			
			bytesRead = correctBytes.length;
			
			page++;
		}
		
		file.close();
		
		//fl.WritePage( );
		
		// Internal RC Osc. 8Mhz
		// Low:  0xE4 = 0b11100100 
		// High: 0x99 = 0b10011001
		
		// External 16MHz Crystal
		// Low:  0xEF = 0b11101111
		// High: 0x89 = 0b10001001
		
		writefln( "ReadFuseL() = %s", fl.ReadFuseL( ) );
		fl.WriteFuseL( 0xEF );
		
		writefln( "ReadFuseH() = %s", fl.ReadFuseH( ) );
		fl.WriteFuseH( 0x89 );
		
		fl.LeaveProgMode( );
		
		jtagiface.JTAGReset( false, false );
		
		writefln( "Success!" );
	}
	*/
	return 0;
}