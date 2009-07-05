module icyprog.debuginterface;

import std.compat;

import tango.util.container.LinkedList;

import icyprog.flash.base;

class DebugInterface {
	static DebugInterface[Object] interfaces;
	
	Flash[] flashList;

	this( ) {
		
	}
	
	static ~this( ) {
		interfaces = null; // delete our interface list so the DebugInterface's are GCd
	}
	
	public static void AddInstanceForReference( Object interfaceReference, DebugInterface iface ) {
		interfaces[interfaceReference] = iface;
	}
	
	public static DebugInterface GetInstanceByReference( Object interfaceReference ) {
		return interfaces[interfaceReference];
	}
	
	public static bool ContainsInstanceForReference( Object interfaceReference ) {
		if ( (interfaceReference in interfaces) )
			return true;
		return false;
	}
	
	public static DebugInterface[] GetInstancesForInterface( T )( ) {
		LinkedList!(DebugInterface) ifaces = new LinkedList!(DebugInterface);
		
		foreach ( di; interfaces ) {
			if ( cast(T)di !is null ) {
				ifaces.add( di );
			}
		}
		
		return ifaces.toArray( );
	}
	
	public string GetInterfaceName( ) {
		return this.toString( );
	}
}
