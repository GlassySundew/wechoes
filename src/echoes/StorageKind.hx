package echoes;

/** Physical storage selected for a component type. */
enum abstract StorageKind(Int) from Int to Int {
	/** Dense, columnar storage owned by an archetype table. */
	var Table = 0;

	/** Entity-indexed sparse-set storage, intended for structurally volatile data. */
	var SparseSet = 1;
}
