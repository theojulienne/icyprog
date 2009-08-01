module icyprog.board;

import std.compat;
import std.string;
import std.stdio;

import tango.util.container.LinkedList;

import icyprog.debuginterface;
import icyprog.interfaces.penguinoavr;
import icyprog.protocols.jtag;
import icyprog.chip;

class Board {
	static LinkedList!(Board) boards;
	
	static void enumerateBoards( ) {
		boards = new LinkedList!(Board);
		
		// FIXME: this shouldn't be type-specific
		PenguinoAVRInterface.DiscoverInterfaces( );

		DebugInterface[] ifaces = DebugInterface.GetInstancesForInterface!(PenguinoAVRInterface)();
		
		foreach ( iface; ifaces ) {
			Board b = iface.createBoard( );
			if ( b.verifyParts( ) ) {
				b.enumerateChips( );
				boards.append( b );
			}
		}
	}
	
	static void invalidateBoards( ) {
		boards = null;
	}
	
	DebugInterface iface;
	IJTAG ijtag;
	TAPStateMachine sm;
	Chip[string] chips;
	
	private bool _systemReset = false;
	private bool _testReset = false;
	
	this( DebugInterface iface ) {
		this.iface = iface;
		this.ijtag = cast(IJTAG)iface;
		
		sm = new TAPStateMachine( cast(IJTAG)iface );
	}
	
	void systemReset( bool sr ) {
		assert( ijtag !is null );
		
		if ( _systemReset != sr ) {
			_systemReset = sr;
		
			ijtag.JTAGReset( _systemReset, _testReset );
			
			writefln( "reset: sys=%s test=%s", _systemReset, _testReset );
		}
	}
	
	void testReset( bool tr ) {
		assert( ijtag !is null );
		
		if ( _testReset != tr ) {
			_testReset = tr;
		
			ijtag.JTAGReset( _systemReset, _testReset );
			
			writefln( "reset: sys=%s test=%s", _systemReset, _testReset );
		}
	}
	
	public abstract bool verifyParts( ) {
		return false;
	}
	
	public abstract void enumerateChips( ) {
		
	}
	
	void showInformation( ) {
		this.testReset = true;
		scope(exit) this.testReset = false;
		
		foreach ( chip_name, chip; chips ) {
			writefln( "Chip '%s':", chip_name );
			chip.showInformation( );
		}
	}
}
