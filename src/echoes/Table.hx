package echoes;

import haxe.ds.ReadOnlyArray;

/** Dense structure-of-arrays storage shared by compatible archetypes. */
class Table {
	public final id : Int;
	public final componentIds : ReadOnlyArray<Int>;
	public final entities : Array<Entity> = [];

	private final columns : Map<Int, Array<Dynamic>> = [];

	public function new( id : Int, componentIds : Array<Int> ) {
		this.id = id;
		this.componentIds = componentIds.copy();
		for ( componentId in componentIds ) {
			columns[componentId] = [];
		}
	}

	public inline function hasComponent( componentId : Int ) : Bool {
		return columns.exists( componentId );
	}

	public inline function get( componentId : Int, row : Int ) : Dynamic {
		final column = columns[componentId];
		return column == null ? null : column[row];
	}

	public inline function set( componentId : Int, row : Int, value : Dynamic ) : Void {
		columns[componentId][row] = value;
	}

	/** Appends an entity and returns its new table row. */
	public function append( entity : Entity, values : Map<Int, Dynamic> ) : Int {
		final row = entities.length;
		entities.push( entity );
		for ( componentId in componentIds ) {
			columns[componentId].push( values[componentId] );
		}
		return row;
	}

	/**
	 * Swap-removes a row and returns the entity moved into the vacated row, if
	 * any. The caller owns location/archetype metadata updates.
	 */
	public function swapRemove( row : Int ) : Null<Entity> {
		final last = entities.length - 1;
		if ( row < 0 || row > last ) {
			return null;
		}

		var swapped : Null<Entity> = null;
		if ( row != last ) {
			swapped = entities[last];
			entities[row] = swapped;
			for ( componentId in componentIds ) {
				final column = columns[componentId];
				column[row] = column[last];
			}
		}

		entities.pop();
		for ( componentId in componentIds ) {
			columns[componentId].pop();
		}
		return swapped;
	}

	@:allow( echoes.World )
	private inline function clear() : Void {
		entities.resize( 0 );
		for ( column in columns ) {
			column.resize( 0 );
		}
	}
}
