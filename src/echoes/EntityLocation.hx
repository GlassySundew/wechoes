package echoes;

/**
 * World-owned physical location of an entity.
 *
 * This is deliberately separate from `Entity` / `EntityHandle`: structural
 * changes update this record without invalidating handles held by user code.
 */
class EntityLocation {
	public var archetypeId : Int;
	public var archetypeRow : Int;
	public var tableId : Int;
	public var tableRow : Int;

	public inline function new( archetypeId : Int, archetypeRow : Int, tableId : Int, tableRow : Int ) {
		this.archetypeId = archetypeId;
		this.archetypeRow = archetypeRow;
		this.tableId = tableId;
		this.tableRow = tableRow;
	}
}
