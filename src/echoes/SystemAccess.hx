package echoes;

/**
 * Conservative component-access description for scheduling systems.
 * Execution is still single-threaded; this data is the contract a future
 * scheduler can use to form non-conflicting batches.
 */
class SystemAccess {
	public inline function new() {}

	public final reads : Array<Int> = [];
	public final writes : Array<Int> = [];
	public var exclusive : Bool = false;

	/**
	 * Current systems may call immediate entity add/remove APIs. Until those
	 * writes are routed through a command buffer, this is a scheduling barrier.
	 */
	public var structuralChanges : Bool = true;

	public inline function addRead( componentId : Int ) : Void {
		if ( !reads.contains( componentId ) && !writes.contains( componentId ) ) reads.push( componentId );
	}

	public inline function addWrite( componentId : Int ) : Void {
		reads.remove( componentId );
		if ( !writes.contains( componentId ) ) writes.push( componentId );
	}

	public function conflictsWith( other : SystemAccess ) : Bool {
		if ( exclusive || other.exclusive || structuralChanges || other.structuralChanges ) return true;
		for ( componentId in writes ) {
			if ( other.writes.contains( componentId ) || other.reads.contains( componentId ) ) return true;
		}
		for ( componentId in reads ) {
			if ( other.writes.contains( componentId ) ) return true;
		}
		return false;
	}
}
