module icyprog.boards.penguinoavr;

import std.compat;
import std.stdio;

import tango.io.Stdout;

import icyprog.debuginterface;
import icyprog.board;
import icyprog.protocols.jtag;
import icyprog.chips.avr;
import icyprog.flash.avrflash;

class PenguinoAVRBoard : Board {
	this( DebugInterface iface ) {
		super( iface );
	}
	
	bool verifyParts( ) {
		this.testReset = true;
		scope(exit) this.testReset = false;
		
		sm.GotoState( TAPState.TestLogicReset );
		sm.GotoState( TAPState.ShiftDR );
		
		// should only be 1 part in a penguino avr
		TAPResponse response = sm.SendCommand( TAPCommand.ReceiveData( 32 ) );
		uint id = response.GetUInt32( );
		TAPDeviceIDRegister reg = TAPDeviceIDRegister.ForID( id );
		
		//writefln( "IDCODE = %s: %s\n", id, reg );
		Stdout.format( "IDCODE = {0}: {1}", id, reg.toString ).newline;
		
		if ( id != 0x8950203f ) {
			return false;
		}
		
		return true;
	}
	
	void enumerateChips( ) {
		auto chip = new AVRChip( this );
		
		// Penguino AVR contains an ATMega32A with 32KB flash
		chip.addMemory( "flash", new AVRFlash( chip, 32*1024 ) );
		
		chips["user"] = chip;
	}
}
