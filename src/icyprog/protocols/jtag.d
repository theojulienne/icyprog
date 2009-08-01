module icyprog.protocols.jtag;

import std.compat;
import std.string;
import std.stdio;

import tango.util.container.LinkedList;
import tango.core.BitArray;

struct _int_hax {
	union {
		uint ival;
		ubyte[4] bytes;
	}
}

struct _short_hax {
	union {
		ushort ival;
		ubyte[4] bytes;
	}
}

class BitConverter {
	static ubyte[] GetBytes( uint a ) {
		_int_hax i;
		i.ival = a;
		
		return i.bytes.dup;
	}
	
	static uint ToUInt32( ubyte[] bytes, int wtf ) {
		_int_hax i;
		i.bytes[0..4] = bytes;
		return i.ival;
	}
	
	static uint ToUInt16( ubyte[] bytes, int wtf ) {
		_short_hax i;
		i.bytes[0..2] = bytes;
		return i.ival;
	}
}


enum TAPPins {
	TCK=0,
	TMS=1,
	TDI=3,
}

enum TAPState {
	TestLogicReset=0,
	RunTestIdle=1,
	
	SelectDRScan=2,
	CaptureDR=3,
	ShiftDR=4,
	Exit1DR=5,
	PauseDR=6,
	Exit2DR=7,
	UpdateDR=8,
	
	SelectIRScan=9,
	CaptureIR=10,
	ShiftIR=11,
	Exit1IR=12,
	PauseIR=13,
	Exit2IR=14,
	UpdateIR=15,
	
	NumStates=16,
	
	Unknown=0xffff
}

class TAPStateTreeNode {
	public TAPState highTMS;
	public TAPState lowTMS;
	
	this( TAPState high, TAPState low ) {
		highTMS = high;
		lowTMS = low;
	}
}

static class TAPStateTree {
	static TAPStateTreeNode[TAPState] nodes;
	
	static this( ) {
		int states = TAPState.NumStates;
		
		//                            	            TMS=1                       TMS=0
		nodes[TAPState.TestLogicReset]	= new TAPStateTreeNode( TAPState.TestLogicReset,	TAPState.RunTestIdle );
		nodes[TAPState.RunTestIdle]	= new TAPStateTreeNode( TAPState.SelectDRScan,		TAPState.RunTestIdle );
		      
		nodes[TAPState.SelectDRScan]	= new TAPStateTreeNode( TAPState.SelectIRScan,		TAPState.CaptureDR );
		nodes[TAPState.CaptureDR]		= new TAPStateTreeNode( TAPState.Exit1DR,			TAPState.ShiftDR );
		nodes[TAPState.ShiftDR]		= new TAPStateTreeNode( TAPState.Exit1DR,			TAPState.ShiftDR );
		nodes[TAPState.Exit1DR]		= new TAPStateTreeNode( TAPState.UpdateDR,			TAPState.PauseDR );
		nodes[TAPState.PauseDR]		= new TAPStateTreeNode( TAPState.Exit2DR,			TAPState.PauseDR );
		nodes[TAPState.Exit2DR]		= new TAPStateTreeNode( TAPState.UpdateDR,			TAPState.ShiftDR );
		nodes[TAPState.UpdateDR]		= new TAPStateTreeNode( TAPState.SelectDRScan,		TAPState.RunTestIdle );
		      
		nodes[TAPState.SelectIRScan]	= new TAPStateTreeNode( TAPState.TestLogicReset,	TAPState.CaptureIR );
		nodes[TAPState.CaptureIR]		= new TAPStateTreeNode( TAPState.Exit1IR,			TAPState.ShiftIR );
		nodes[TAPState.ShiftIR]		= new TAPStateTreeNode( TAPState.Exit1IR,			TAPState.ShiftIR );
		nodes[TAPState.Exit1IR]		= new TAPStateTreeNode( TAPState.UpdateIR,			TAPState.PauseIR );
		nodes[TAPState.PauseIR]		= new TAPStateTreeNode( TAPState.Exit2IR,			TAPState.PauseIR );
		nodes[TAPState.Exit2IR]		= new TAPStateTreeNode( TAPState.UpdateIR,			TAPState.ShiftIR );
		nodes[TAPState.UpdateIR]		= new TAPStateTreeNode( TAPState.SelectDRScan,		TAPState.RunTestIdle );
	}
	
	struct SearchState {
		public TAPState[] path;
		
		static public SearchState ForState( TAPState state ) {
			SearchState ss;
			
			ss.path = new TAPState[1];
			ss.path[0] = state;
			
			return ss;
		}
		
		public SearchState Fork( TAPState to ) {
			SearchState ss;
			
			ss.path = new TAPState[path.length + 1];
			
			//Array.Copy( path, 0, ss.path, 0, path.length );
			ss.path[0..path.length] = path;
			ss.path[path.length] = to;
			
			return ss;
		}
		
		public TAPState currentState( ) {
			return path[path.length - 1];
		}
	}
	
	// returns (via path/length) the best TMS path from the state 'from' to the state 'to'.
	// the returned path is from LSB->MSB, that is, the first state change is in the LSB.
	static public void GetShortestStatePath( TAPState from, TAPState to, inout uint path, inout uint length ) {
		LinkedList!(SearchState) queue = new LinkedList!(SearchState)();
		
		queue.append( SearchState.ForState( from ) );
		
		while ( queue.size > 0 ) {
			SearchState ss = queue.removeHead( );
			
			TAPState currentState = ss.currentState;
			
			if ( currentState == to ) {
				path = 0x0;
				length = 0;
				
				// skip 'to', because we just need the transition, return the required TMS changes
				// (this uses the reverse order for convenience in shifting the changes in)
				for ( int i = ss.path.length - 2; i >= 0; i-- ) {
					TAPState state = ss.path[i];
					TAPStateTreeNode node = nodes[state];
					TAPState nextState = ss.path[i+1];
					
					path <<= 1;
					length++;
					
					// if the next state is the node's highTMS, set the bit
					if ( nextState == node.highTMS )
						path |= 1;
				}
				
				return;
			}
			
			queue.append( ss.Fork( nodes[currentState].highTMS ) );
			queue.append( ss.Fork( nodes[currentState].lowTMS ) );
		}
	}
	
	static public TAPState NextStateForTMS( TAPState current, bool tms ) {
		if ( tms )
			return nodes[current].highTMS;
		else
			return nodes[current].lowTMS;
	}
}

struct TAPDeviceIDRegister {
	public ubyte Version;
	public short PartNumber;
	public short ManufacturerID;
	
	public static TAPDeviceIDRegister ForID( uint id ) {
		TAPDeviceIDRegister reg;
		
		reg.Version = cast(byte)( (id >> 28) & 0xf );
		reg.PartNumber = cast(short)( (id >> 12) & 0xffff );
		reg.ManufacturerID = cast(short)( (id >> 1) & 0x7FF );
		
		assert( (id & 1) == 1, "Bit 0 of JTAG Device ID Register should be 1" );
		
		return reg;
	}
	
	public string toString( ) {
		return std.string.format( "TAPDeviceIDRegister<manu=0x%03x,part=0x%04x,ver=0x%01x>", ManufacturerID, PartNumber, Version );
	}
}

struct TAPCommand {
	public uint bitLength;
	
	public ubyte[] tmsBits;
	public ubyte[] dataBits;
	
	// shouldRead = 1: read bytes after sending
	// shouldWrite = 1: write bytes
	// shouldWrite = 0: dataBits are actually TMS transitions
	
	public enum Method {
		SendData = 0x1,		
		ReceiveData = 0x2,
		
		SendReceiveData = 0x3,
		
		SendTMS = 0x4,
	}
	
	public Method method;
	
	public static TAPCommand ClockTMS( uint bitLength, uint TMSBits ) {
		TAPCommand cmd;
		
		cmd.bitLength = bitLength;
		cmd.dataBits = BitConverter.GetBytes( 0 );
		cmd.tmsBits = BitConverter.GetBytes( TMSBits );
		cmd.method = Method.SendTMS;
		
		return cmd;
	}
	
	public static TAPCommand SendData( uint bitLength, uint dataBits ) {
		return SendData( bitLength, dataBits, 0, Method.SendData );
	}
	
	public static TAPCommand SendData( uint bitLength, ubyte[] dataBits ) {
		ubyte[] tmsBits = new ubyte[dataBits.length];
		return SendData( bitLength, dataBits, tmsBits, Method.SendData );
	}
	
	public static TAPCommand SendData( uint bitLength, uint dataBits, uint tmsBits ) {
		return SendData( bitLength, dataBits, tmsBits, Method.SendData | Method.SendTMS );
	}
	
	public static TAPCommand SendData( uint bitLength, ubyte[] dataBits, ubyte[] tmsBits ) {
		return SendData( bitLength, dataBits, tmsBits, Method.SendData | Method.SendTMS );
	}
	
	public static TAPCommand SendData( int bitLength, int dataBits, int tmsBits ) {
		return SendData( cast(uint)bitLength, cast(uint)dataBits, cast(uint)tmsBits, Method.SendData | Method.SendTMS );
	}
	
	public static TAPCommand SendData( uint bitLength, ubyte[] dataBits, ubyte[] tmsBits, Method m ) {
		TAPCommand cmd;
		
		cmd.bitLength = bitLength;
		cmd.tmsBits = tmsBits;
		cmd.dataBits = dataBits;
		cmd.method = m;
		
		return cmd;
	}
	
	public static TAPCommand SendData( uint bitLength, uint dataBits, uint tmsBits, Method m ) {
		return SendData( bitLength, BitConverter.GetBytes( dataBits ), BitConverter.GetBytes( tmsBits ), m );
	}
	
	public static TAPCommand SendReceiveData( uint bitLength, ubyte[] dataBits ) {
		TAPCommand cmd = SendData( bitLength, dataBits );
		cmd.method = Method.SendReceiveData;
		return cmd;
	}
	
	public static TAPCommand SendReceiveData( uint bitLength, uint dataBits ) {
		TAPCommand cmd = SendData( bitLength, dataBits );
		cmd.method = Method.SendReceiveData;
		return cmd;
	}
	
	public static TAPCommand SendReceiveData( uint bitLength, uint dataBits, uint tmsBits ) {
		TAPCommand cmd = SendData( bitLength, dataBits, tmsBits );
		cmd.method = Method.SendReceiveData | Method.SendTMS;
		return cmd;
	}
	
	public static TAPCommand SendReceiveData( int bitLength, int dataBits, int tmsBits ) {
		return SendReceiveData( cast(uint)bitLength, cast(uint)dataBits, cast(uint)tmsBits );
	}
	
	public static TAPCommand ReceiveData( uint bitLength ) {
		TAPCommand cmd;
		
		cmd.bitLength = bitLength;
		cmd.tmsBits = BitConverter.GetBytes( 0 );
		cmd.dataBits = BitConverter.GetBytes( 0 );
		cmd.method = Method.ReceiveData;
		
		return cmd;
	}
	
	public static bool GetBitFromBytes( ubyte[] bytes, int bit ) {
		int actualByte = bit / 8;
		int actualBit = bit % 8;
		return (bytes[actualByte] & (1 << actualBit)) != 0;
	}
	
	public static void SetBitFromBytes( ubyte[] bytes, int bit, bool val ) {
		int actualByte = bit / 8;
		int actualBit = bit % 8;
		
		ubyte bitVal = cast(byte)(1 << actualBit);
		
		if ( val )
			bytes[actualByte] |= bitVal;
		else
			bytes[actualByte] &= cast(byte)~bitVal;
	}
	
	public bool GetBit( int bit ) {
		return GetBitFromBytes( dataBits, bit );
	}
	
	public bool GetTMSBit( int bit ) {
		return GetBitFromBytes( tmsBits, bit );
	}
	
	public void SetBit( int bit, bool val ) {
		SetBitFromBytes( dataBits, bit, val );
	}
	
	public void SetTMSBit( int bit, bool val ) {
		if ( val == true ) {
			method |= Method.SendTMS;
		}
		SetBitFromBytes( tmsBits, bit, val );
	}
	
	public uint neededBytes( ) {
		uint byteCount = bitLength / 8;
		
		if ( (bitLength%8) > 0 )
			byteCount++;
		
		//writefln( "{0} bits need {1} bytes", bitLength, byteCount );
		
		return byteCount;
	}
	
	public static ubyte[] GetBitsForRange( ubyte[] bytes, int startIndex, int numBits ) {
		int byteCount = numBits / 8;
		
		if ( (numBits%8) > 0 )
			byteCount++;
		
		ubyte[] newBytes = new ubyte[byteCount];
		
		for ( int i = 0; i < byteCount; i++ ) {
			newBytes[i] = 0;
		}
		
		for ( int i = 0; i < numBits; i++ ) {
			if ( GetBitFromBytes( bytes, startIndex + i ) )
				newBytes[i/8] |= cast(byte)( 1 << (i%8) );
		}
		
		return newBytes;
	}
	
	public ubyte[] GetTMSBits( int startIndex, uint numBits ) {
		return GetBitsForRange( tmsBits, startIndex, cast(int)numBits );
	}
	
	public ubyte[] GetDataBits( int startIndex, uint numBits ) {
		return GetBitsForRange( dataBits, startIndex, cast(int)numBits );
	}
	
	// Splits a TAPCommand with double transitions (where both TMS and TDI change)
	// into multiple TAPCommands, each with only single transitions
	// (TMS or TDI stay stable the whole duration)
	public TAPCommand[] SplitByDoubleTransitions( ) {
		if ( (method & (Method.SendData | Method.SendTMS)) != (Method.SendData | Method.SendTMS) ) {
			// skip complex checking if TMS and TDI are not both being used
			TAPCommand[] tapCommands;
			tapCommands.length = 1;
			tapCommands[0] = *this;
			return tapCommands;
		}
		
		if ( bitLength == 1 ) {
			// skip complex checking if we're only 1 bit long
			TAPCommand[] tapCommands;
			tapCommands.length = 1;
			tapCommands[0] = *this;
			return tapCommands;
		}
		
		//writefln( "Preparing to split..." );
		
		LinkedList!(TAPCommand) cmdList = new LinkedList!(TAPCommand)();
		
		int currentBit = 0;
		bool transitionFound = false;
		bool transitionIsTMS = false;
		
		bool currentData, currentTMS;
		int tmpBit;
		
		while ( currentBit < bitLength ) {
			if ( !transitionFound ) {
				// find a transition by skipping ahead until 1 bit changes
				currentData = GetBit( currentBit );
				currentTMS = GetTMSBit( currentBit );
				
				tmpBit = currentBit + 1;
				while ( tmpBit < bitLength ) {
					if ( currentData != GetBit( tmpBit ) ) {
						// data bit changed first
						transitionFound = true;
						transitionIsTMS = false;
						
						break;
					} else if ( currentTMS != GetTMSBit( currentBit ) ) {
						// TMS bit changed first
						transitionFound = true;
						transitionIsTMS = true;
						
						break;
					}
					
					tmpBit++;
				}
			}
			
			// we now have found the first transition (defined by transitionIsTMS).. 
			// now do another scan, looking as far as we can until the OTHER value changes
			currentData = GetBit( currentBit );
			currentTMS = GetTMSBit( currentBit );
			
			tmpBit = currentBit + 1;
			while ( tmpBit < bitLength ) {
				if ( (transitionIsTMS && currentData != GetBit( tmpBit )) ||
				 	 ((!transitionIsTMS) && currentTMS != GetTMSBit( tmpBit )) ) {
					// double transition found at tmpBit
					
					//writefln( "Double transition found at {0}", tmpBit );
					
					TAPCommand cmd;
					cmd.bitLength = cast(uint)tmpBit - cast(uint)currentBit;
					cmd.tmsBits = GetTMSBits( currentBit, cmd.bitLength );
					cmd.dataBits = GetDataBits( currentBit, cmd.bitLength );
					cmd.method = method;
					cmdList.add( cmd );
					
					// continue from that bit
					transitionFound = false;
					currentBit = tmpBit;
					break;
				}
				
				tmpBit++;
			}
			
			if ( tmpBit == bitLength ) {
				TAPCommand cmd;
				cmd.bitLength = cast(uint)tmpBit - cast(uint)currentBit;
				cmd.tmsBits = GetTMSBits( currentBit, cmd.bitLength );
				cmd.dataBits = GetDataBits( currentBit, cmd.bitLength );
				cmd.method = method;
				cmdList.add( cmd );
				
				break;
			}
		}
		
		//writefln( "Split {0} bits into {1} parts", bitLength, cmdList.Count );
		
		return cmdList.toArray( );
	}
}

class TAPResponse {
	public ubyte[] data;
	
	this( ubyte[] inData ) {
		data = inData;
		//writefln( "{0} = inLength", inData.length );
	}
	
	public bool GetBit( int bit ) {
		return TAPCommand.GetBitFromBytes( data, bit );
	}
	
	public uint GetUInt32( ) {
		return BitConverter.ToUInt32( data, 0 );
	}
	
	public ubyte GetByte( uint index ) {
		return data[index];
	}
	
	public ushort GetUInt16( ) {
		//writefln( "{0} = length", data.length );
		return BitConverter.ToUInt16( data, 0 );
	}
	
	public void SetBit( int bit, bool val ) {
		TAPCommand.SetBitFromBytes( data, bit, val );
	}
}

class TAPStateMachine {
	IJTAG iface;
	TAPState currentState = TAPState.Unknown;
	
	this( IJTAG iface ) {
		this.iface = iface;
	}
	
	public TAPResponse SendCommand( TAPCommand cmd ) {
		TAPResponse ret = iface.JTAGCommand( cmd );
		
		// if we're in an unknown state, we'll remain there
		if ( currentState != TAPState.Unknown ) {
			for ( int i = 0; i < cmd.bitLength; i++ ) {
				currentState = TAPStateTree.NextStateForTMS( currentState, cmd.GetTMSBit( i ) );
			}
		}
		
		//writefln( "State: {0}", currentState );
		
		return ret;
	}
	
	public void GotoState( TAPState newState ) {
		if ( currentState == TAPState.Unknown ) {
			// when in an unknown state, start by returning to the reset state
			// by clocking 5 bits with TMS=1. Then set our state, because we know it.
			SendCommand( TAPCommand.ClockTMS( 5, 0x1F ) ); // 0x1F = 0b11111
			
			currentState = TAPState.TestLogicReset;
		}
		
		uint path=0, length=0;
		
		TAPStateTree.GetShortestStatePath( currentState, newState, path, length );
		SendCommand( TAPCommand.ClockTMS( length, path ) );
	}
	
	public void ScanIR( int bitLength, int dataBits ) {
		//writefln( "" );
		//writefln( "Scan IR ({0} {1})", bitLength, dataBits );
		GotoState( TAPState.ShiftIR ); // get to ShiftIR
		SendCommand( TAPCommand.SendData( bitLength, dataBits, 1<<(bitLength-1) ) ); // TMS on last bit only
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
	}
	
	public void ScanIR( int bitLength, ubyte[] dataBits ) {
		//writefln( "" );
		//writefln( "Scan IR ({0})", bitLength );
		GotoState( TAPState.ShiftIR ); // get to ShiftIR
		TAPCommand cmd = TAPCommand.SendData( cast(uint)bitLength, dataBits );
		cmd.SetTMSBit( bitLength-1, true ); // TMS on last bit only
		SendCommand( cmd );
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
	}
	
	public void ScanDR( int bitLength, int dataBits ) {
		//writefln( "" );
		//writefln( "Scan DR (%s %s)", bitLength, dataBits );
		GotoState( TAPState.ShiftDR ); // get to ShiftDR
		SendCommand( TAPCommand.SendData( bitLength, dataBits, 1<<(bitLength-1) ) ); // TMS on last bit only
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
	}
	
	public void ScanDR( int bitLength, ubyte[] dataBits ) {
		//writefln( "" );
		//writefln( "Scan DR ({0})", bitLength );
		GotoState( TAPState.ShiftDR ); // get to ShiftDR
		TAPCommand cmd = TAPCommand.SendData( cast(uint)bitLength, dataBits );
		cmd.SetTMSBit( bitLength-1, true ); // TMS on last bit only
		//writefln( "-------- START SCAN DR --------" );
		SendCommand( cmd );
		//writefln( "-------- END SCAN DR -------" );
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
	}
	
	public TAPResponse ScanIRRecv( int bitLength, int dataBits ) {
		//writefln( "" );
		//writefln( "Scan IR+recv ({0} {1})", bitLength, dataBits );
		GotoState( TAPState.ShiftIR ); // get to ShiftIR
		TAPResponse response = SendCommand( TAPCommand.SendReceiveData( bitLength, dataBits, 1<<(bitLength-1) ) ); // TMS on last bit only
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
		
		return response;
	}
	
	public TAPResponse ScanIRRecv( int bitLength, ubyte[] dataBits ) {
		//writefln( "" );
		//writefln( "Scan IR+recv ({0} {1})", bitLength, dataBits );
		GotoState( TAPState.ShiftIR ); // get to ShiftIR
		TAPCommand cmd = TAPCommand.SendReceiveData( cast(uint)bitLength, dataBits );
		cmd.SetTMSBit( bitLength-1, true ); // TMS on last bit only
		TAPResponse response = SendCommand( cmd );
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
		
		return response;
	}
	
	public TAPResponse ScanDRRecv( int bitLength, int dataBits ) {
		//writefln( "" );
		//writefln( "Scan DR+recv ({0} {1})", bitLength, dataBits );
		GotoState( TAPState.ShiftDR ); // get to ShiftDR
		TAPResponse response = SendCommand( TAPCommand.SendReceiveData( bitLength, dataBits, 1<<(bitLength-1) ) ); // TMS on last bit only
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
		
		return response;
	}
	
	public TAPResponse ScanDRRecv( int bitLength, ubyte[] dataBits ) {
		//writefln( "" );
		//writefln( "Scan DR+recv ({0} {1})", bitLength, dataBits );
		GotoState( TAPState.ShiftDR ); // get to ShiftDR
		TAPCommand cmd = TAPCommand.SendReceiveData( cast(uint)bitLength, dataBits );
		cmd.SetTMSBit( bitLength-1, true ); // TMS on last bit only
		TAPResponse response = SendCommand( cmd );
		GotoState( TAPState.RunTestIdle ); // return to RunTestIdle
		
		return response;
	}
}

interface IJTAG {
	void JTAGReset( bool systemReset, bool testReset );
	TAPResponse JTAGCommand( TAPCommand cmd );
}
