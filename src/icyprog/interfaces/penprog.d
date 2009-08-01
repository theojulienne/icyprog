module icyprog.interfaces.penprog;

import std.compat;
import std.stdio;

import usb.all;

import icyprog.protocols.jtag;
import icyprog.debuginterface;

class PenprogInterface : DebugInterface, IJTAG {
	const byte jtagCommandGetBoard = 0x01;
	const byte jtagCommandReset = 0x02;
	const byte jtagCommandJumpBootloader = 0x03;
	const byte jtagCommandFirmwareVersion = 0x04;

	const byte jtagCommandClockBit = 0x20;
	const byte jtagCommandClockBits = 0x21;
	
	
	const uint USBVendorId = 0x03EB;
	const uint USBProductId = 0x2018;
	
	const int jtagBulkIn = 0x83;
	const int jtagBulkOut = 0x04;
	
	const int jtagInterface = 2;
	
	USBDevice _device;
	
	this( ) {
		super( );
	}
	
	~this( ) {
	    writefln( "Releasing interface..." );
		_device.releaseInterface( jtagInterface );
		writefln( "Penprog interface released." );
	}
	
	void device( USBDevice dev ) {
		_device = dev;
		
		_device.open( );
		
		// set timeout
		// set configuration on win32
		
		// claim interface
		_device.claimInterface( jtagInterface );
	}
	
	USBDevice device( ) {
		return _device;
	}
	
	public static void DiscoverInterfaces( T )( uint vendorId, uint productId ) {
		//writefln( "Searching busses..." );
		foreach ( bus; USB.busses ) {
			//writefln( "Searching descriptors in bus %s...", bus );
			foreach ( dev; bus.devices ) {
				auto desc = dev.descriptor;
				//writefln( "%s~%s %s~%s", desc.idVendor, vendorId, desc.idProduct, productId );
				
				if ( desc.idVendor != vendorId || desc.idProduct != productId )
					continue;
				
				if ( !( DebugInterface.ContainsInstanceForReference( dev ) ) ) {
					PenprogInterface ppi = new T();
					ppi.device = dev;
				
					DebugInterface.AddInstanceForReference( dev, ppi );
				}
			}
		}
	}
	
	public void JTAGReset( bool systemReset, bool testReset ) {
		ubyte[32] bytes;
		int ret;
		
		bytes[0] = jtagCommandReset; // RESET
		bytes[1] = (systemReset ? 1 : 0);
		bytes[2] = (testReset ? 1 : 0);
		
		while ( (ret = device.bulkWrite( jtagBulkOut, bytes )) != bytes.length ) {
			writefln( "RST: USB Bulk Write failed (%s), retrying...", ret ); // loopies
			
			//System.Threading.Thread.Sleep( 100 );
		}
		
		while ( (ret = device.bulkRead( jtagBulkIn, bytes )) != bytes.length ) {
			writefln( "RST: USB Bulk Read failed (%s), retrying...", ret ); // loopies
			
			//System.Threading.Thread.Sleep( 100 );
		}
	}
	
	struct ClockBitsOutData {
		ubyte[30] data;
		
		void setBit( int bitNum, bool dataBit, bool tmsBit ) {
			int bitOffset = ((bitNum%4)*2);
			
			data[bitNum/4] &= ~(0x3 << bitOffset);
			
			if ( dataBit )
				data[bitNum/4] |= (1 << bitOffset);
			if ( tmsBit )
				data[bitNum/4] |= (2 << bitOffset);
		}
	}
	
	struct ClockBitsInData {
		ubyte[30] data;
		
		bool getBit( int bitNum ) {
			return ((data[bitNum/8] >> (bitNum%8)) & 0x1) != 0;
		}
	}
	
	void processChunk( TAPCommand cmd, TAPResponse response, int startIndex, int numBits ) {
		ClockBitsOutData outData;
		ubyte[32] usbMsg;
		int ret;
		
		// prepare our output data
		for ( int i = startIndex; i < startIndex+numBits; i++ ) {
			bool dataBit = cmd.GetBit(i);
			bool tmsBit = cmd.GetTMSBit(i);
			
			outData.setBit( i - startIndex, dataBit, tmsBit );
		}
		
		//writefln( "Chunk will contain %d bits, starting from [%d]", numBits, startIndex );
		
		// prepare our usb message
		usbMsg[0] = jtagCommandClockBits;
		usbMsg[1] = numBits;
		usbMsg[2..$] = outData.data;
		while ( (ret = device.bulkWrite( jtagBulkOut, usbMsg )) != usbMsg.length ) {
			writefln( "CHUNK: USB Bulk Write failed (%s), retrying...", ret ); // loopies
		}
		
		// read the response
		ubyte[32] readBytes;
		while ( (ret = device.bulkRead( jtagBulkIn, readBytes )) != readBytes.length ) {
			writefln( "USB Bulk Read failed (%s), retrying...", ret ); // loopies
			writefln( "%s", device.getError( ) );
		}
		
		//writefln( "read = %s", readBytes[1] );
		
		// set our response bits
		ClockBitsInData inData;
		inData.data[0..$] = readBytes[2..$];
		for ( int i = startIndex; i < startIndex+numBits; i++ ) {
			bool currBit = inData.getBit( i - startIndex );
			response.SetBit( i, currBit );
			//writefln( "[%d] %d", i, currBit );
		}
	}
	
	public TAPResponse JTAGCommand( TAPCommand cmd ) {
		TAPResponse response = null;
		uint numBytes = cmd.neededBytes( );
		ubyte[] responseBytes;
		responseBytes.length = numBytes;
		response = new TAPResponse( responseBytes );
		ubyte[2] bytes;
		
		//writefln( "writing %s bits", cmd.bitLength );
		
		// usb msg = 32 bytes, 2 instruction bytes, then 4 bits per byte
		// (because 2 physical bits per logical bit/clock)
		const int MaxBitsPerMessage = ((32-2) * 4);
		
		for ( int i = 0; i < cmd.bitLength; ) {
			int numBits = MaxBitsPerMessage;
			
			if ( i + numBits > cmd.bitLength )
				numBits = cmd.bitLength - i;
			
			processChunk( cmd, response, i, numBits );
			
			i += MaxBitsPerMessage;
		}
		
		/*
		for ( int i = 0; i < cmd.bitLength; i++ ) {
			bool dataBit = cmd.GetBit(i);
			bool tmsBit = cmd.GetTMSBit(i);
			
			ubyte outByte = 0;
			
			if ( dataBit )
				outByte |= 1;
			
			if ( tmsBit )
				outByte |= 2;
			
			int ret;
			
			bytes[0] = jtagCommandClockBit;
			bytes[1] = outByte;
			//writefln( "write = %s", bytes[1] );
			while ( (ret = device.bulkWrite( jtagBulkOut, bytes )) != bytes.length ) {
				writefln( "USB Bulk Write failed (%s), retrying...", ret ); // loopies
				//try {device.ClearHalt( jtagBulkOut );} catch {}
				
				//System.Threading.Thread.Sleep( 100 );
			}
			
			ubyte[32] readBytes;
			while ( (ret = device.bulkRead( jtagBulkIn, readBytes )) != readBytes.length ) {
				writefln( "USB Bulk Read failed (%s), retrying...", ret ); // loopies
				writefln( "%s", device.getError( ) );
				//try {device.ClearHalt( jtagBulkIn );} catch {}
				
				//System.Threading.Thread.Sleep( 100 );
			}
			
			//writefln( "read = %s", readBytes[1] );
			
			response.SetBit( i, (readBytes[1] != 0) );
		}
		*/
		
		return response;
	}
}
