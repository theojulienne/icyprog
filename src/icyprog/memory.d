module icyprog.memory;

import tango.io.device.File;
import tango.io.device.Conduit;
import tango.io.stream.Buffered;

import std.stdio;

import icyprog.board;
import icyprog.chip;

class Memory {
	public uint memoryBytes = 0; // in bytes
	public uint pageBytes = 0; // in bytes
	public Chip chip = null;
	
	this( Chip c ) {
		chip = c;
	}
	
	uint numPages( ) {
		return memoryBytes / pageBytes;
	}
	
	abstract void erase( ) {
		
	}
	
	abstract void writePage( uint pageIndex, ubyte[] data ) {
		
	}
	
	abstract ubyte[] readPage( uint pageIndex ) {
		return null;
	}
	
	abstract void finished( ) {
		
	}
	
	typedef void delegate( uint bytesCompleted ) MemoryProgressDelegate;
	
	bool writeStream( InputStream src, MemoryProgressDelegate writeProgress=null ) {
		BufferedInput srcData = new BufferedInput( src );
		
		srcData.seek( 0, File.Anchor.Begin );
		
		ubyte[] pageBuf;
		pageBuf.length = pageBytes;
		int currPage = 0;
		size_t size_read;
		
		writeProgress( 0 );
		
		while ( (size_read = srcData.fill( pageBuf )) != IConduit.Eof ) {
			//writefln( "read position: %s (read %s bytes)", srcData.position, size_read );
			assert( currPage < numPages );
			
			writeProgress( currPage * pageBytes );
			
			pageBuf.length = size_read;
			writePage( currPage, pageBuf );
			
			currPage++;
		}
		
		writeProgress( currPage * pageBytes );
		
		return true;
	}
	
	bool verifyStream( InputStream src, MemoryProgressDelegate verifyProgress=null ) {
		BufferedInput srcData = new BufferedInput( src );
		
		srcData.seek( 0, File.Anchor.Begin );
		
		ubyte[] pageBuf, actualBuf;
		pageBuf.length = pageBytes;
		int currPage = 0;
		size_t size_read;
		
		verifyProgress( 0 );
		
		while ( (size_read = srcData.fill( pageBuf )) != IConduit.Eof ) {
			assert( currPage < numPages );
			
			verifyProgress( currPage * pageBytes );
			
			actualBuf = readPage( currPage );
			
			for ( int j = 0; j < size_read; j++ ) {
				//writefln( "%s == %s", correctBytes[j], verifyBytes[j] );
				
				if ( actualBuf[j] != pageBuf[j] ) {
					writefln( "Error with byte %s in page %s (expected %s, read %s)", j, currPage, pageBuf[j], actualBuf[j] );
					throw new Exception( "Verify failed!" );
				}
			}
			
			currPage++;
		}
		
		verifyProgress( currPage * pageBytes );
		
		return true;
	}
}
