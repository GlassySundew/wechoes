package echoes;

import haxe.ds.ReadOnlyArray;

/** Metadata and entity rows for one exact component set. */
class Archetype {
	public final id : Int;
	public final tableId : Int;
	public final componentIds : ReadOnlyArray<Int>;
	public final entities : Array<ArchetypeEntity> = [];

	private final componentMembership : Map<Int, Bool> = [];
	private final addTransitions : Map<Int, Int> = [];
	private final removeTransitions : Map<Int, Int> = [];

	public function new( id : Int, tableId : Int, componentIds : Array<Int> ) {
		this.id = id;
		this.tableId = tableId;
		this.componentIds = componentIds.copy();
		for ( componentId in componentIds ) {
			componentMembership[componentId] = true;
		}
	}

	public inline function hasComponent( componentId : Int ) : Bool {
		return componentMembership.exists( componentId );
	}

	public function matches( required : ReadOnlyArray<Int>, excluded : ReadOnlyArray<Int> ) : Bool {
		for ( componentId in required ) {
			if ( !componentMembership.exists( componentId ) ) return false;
		}
		for ( componentId in excluded ) {
			if ( componentMembership.exists( componentId ) ) return false;
		}
		return true;
	}

	public inline function append( entity : Entity, tableRow : Int ) : Int {
		final row = entities.length;
		entities.push( new ArchetypeEntity( entity, tableRow ) );
		return row;
	}

	public function swapRemove( row : Int ) : Null<ArchetypeEntity> {
		final last = entities.length - 1;
		if ( row < 0 || row > last ) return null;
		var swapped : Null<ArchetypeEntity> = null;
		if ( row != last ) {
			swapped = entities[last];
			entities[row] = swapped;
		}
		entities.pop();
		return swapped;
	}

	@:allow( echoes.World )
	private inline function getAddTransition( componentId : Int ) : Null<Int> return addTransitions[componentId];
	@:allow( echoes.World )
	private inline function setAddTransition( componentId : Int, archetypeId : Int ) : Void addTransitions[componentId] = archetypeId;
	@:allow( echoes.World )
	private inline function getRemoveTransition( componentId : Int ) : Null<Int> return removeTransitions[componentId];
	@:allow( echoes.World )
	private inline function setRemoveTransition( componentId : Int, archetypeId : Int ) : Void removeTransitions[componentId] = archetypeId;
}

class ArchetypeEntity {
	public final entity : Entity;
	public var tableRow : Int;

	public inline function new( entity : Entity, tableRow : Int ) {
		this.entity = entity;
		this.tableRow = tableRow;
	}
}
