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
	
	public TAPResponse JTAGCommand( TAPCommand cmd ) {
		TAPResponse response = null;
		uint numBytes = cmd.neededBytes( );
		ubyte[] responseBytes;
		responseBytes.length = numBytes;
		response = new TAPResponse( responseBytes );
		ubyte[2] bytes;
		
		//writefln( "writing %s bits", cmd.bitLength );
		
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
		
		return response;
	}
}
