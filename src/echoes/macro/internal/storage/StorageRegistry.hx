package echoes.macro.internal.storage;

/** Assigns process-local numeric IDs to component storage keys. */
class StorageRegistry {

	private static var nextId : Int = 0;
	private static final ids : Map<String, Int> = new Map();

	public static function reserve( key : String ) : Int {
		if ( !ids.exists( key ) ) {
			ids[key] = nextId++;
		}
		return ids[key];
	}
}
