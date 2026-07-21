package echoes;

import echoes.Query.QueryBase;
import echoes.utils.ComponentTypes;
import echoes.utils.ReadOnlyData;
import haxe.Serializer;
import haxe.Unserializer;

/**
 * Typed facade over a component's physical storage.
 *
 * Table components live in the entity's current `Table`; sparse-set
 * components live here. The facade preserves the established `get`, `exists`,
 * `add`, and `remove` API while allowing physical storage to vary by type.
 */
class ComponentStorage<T> {
	private static final DOT_PATH : EReg = ~/(?:\w+\.)*(\w+)/g;

	public final componentType : String;
	@:allow( echoes.World )
	public var storageId( default, null ) : Int;
	public final storageKind : StorageKind;
	private final world : World;

	public var name( get, never ) : String;
	private inline function get_name() : String return 'ComponentStorage<$componentType>';

	public var shortComponentType( get, never ) : String;
	private inline function get_shortComponentType() : String return DOT_PATH.replace( componentType, "$1" );

	/** Queries structurally mentioning this component. Kept for transition observers. */
	public var relatedQueries( get, never ) : ReadOnlyArray<QueryBase>;
	private inline function get_relatedQueries() : ReadOnlyArray<QueryBase> return _relatedQueries;

	@:deprecated( "Use relatedQueries instead." )
	public var relatedViews( get, never ) : ReadOnlyArray<QueryBase>;
	private inline function get_relatedViews() : ReadOnlyArray<QueryBase> return relatedQueries;

	@:allow( echoes.DynamicComponentStorage )
	private final _relatedQueries : Array<QueryBase> = [];

	// Used only for StorageKind.SparseSet.
	private final sparse : Array<Null<Int>> = [];
	private final denseEntities : Array<Entity> = [];
	private final denseValues : Array<T> = [];
	private final ongoingRemovals : Array<Int> = [];

	public function new(
		world : World,
		componentType : String,
		?storageId : Int,
		?storageKind : StorageKind = StorageKind.Table
	) {
		this.world = world;
		this.componentType = componentType;
		this.storageId = storageId == null
			? echoes.macro.ComponentStorageBuilder.reserveStorageId( componentType )
			: storageId;
		this.storageKind = storageKind;
		world.addStorage( this.storageId, this );
	}

	public function add( entity : Entity, component : Null<T>, ?targetWorld : World ) : Void {
		final world = targetWorld == null ? this.world : targetWorld;
		if ( component == null ) {
			remove( entity, world );
			return;
		}
		if ( ongoingRemovals.contains( entity.id ) ) {
			throw 'Attempted to add $componentType to entity ${entity.id} while that component is being removed.';
		}

		if ( exists( entity ) ) {
			if ( get( entity ) != component ) {
				final oldValue = get( entity );
				if ( storageKind == StorageKind.Table ) {
					world.setTableComponent( entity, storageId, component );
				} else {
					denseValues[sparse[entity.id]] = component;
				}
				world.notifyComponentValueChanged( entity, cast this, oldValue, true );
			}
			return;
		}

		world.addComponent( entity, cast this, component );
	}

	public inline function exists( entity : Entity ) : Bool {
		if ( storageKind == StorageKind.SparseSet ) {
			final index = sparse[entity.id];
			return index != null && index >= 0 && index < denseEntities.length && denseEntities[index].id == entity.id;
		}
		return world.entityHasComponent( entity, storageId );
	}

	public inline function get( entity : Entity ) : Null<T> {
		if ( storageKind == StorageKind.SparseSet ) {
			final index = sparse[entity.id];
			return index == null ? null : denseValues[index];
		}
		return cast world.getTableComponent( entity, storageId );
	}

	/** Fast query fetch that bypasses the entity-location indirection for tables. */
	public inline function getAt( entity : Entity, tableId : Int, tableRow : Int ) : Null<T> {
		if ( storageKind == StorageKind.SparseSet ) return get( entity );
		return cast world.tables[tableId].get( storageId, tableRow );
	}

	public function remove( entity : Entity, ?targetWorld : World ) : Void {
		final world = targetWorld == null ? this.world : targetWorld;
		if ( exists( entity ) ) {
			ongoingRemovals.push( entity.id );
			try {
				world.removeComponent( entity, cast this );
			} catch ( error : Dynamic ) {
				ongoingRemovals.remove( entity.id );
				throw error;
			}
			ongoingRemovals.remove( entity.id );
		}
	}

	public function removeAll( ?targetWorld : World ) : Void {
		final world = targetWorld == null ? this.world : targetWorld;
		final entities = entitiesSnapshot();
		for ( entity in entities ) remove( entity, world );
	}

	/** Replacing data does not cause a structural move when the type is present. */
	public function replace( entity : Entity, component : Null<T>, ?targetWorld : World ) : Void {
		final world = targetWorld == null ? this.world : targetWorld;
		if ( component != null && exists( entity ) && get( entity ) != component ) {
			world.notifyComponentValueChanged( entity, cast this, get( entity ), false );
		}
		add( entity, component, world );
	}

	public function serialize() : String return Serializer.run( valuesByEntityId() );

	public function unserialize( data : String, ?targetWorld : World ) : Void {
		final world = targetWorld == null ? this.world : targetWorld;
		removeAll( world );
		unserializeFromData( Unserializer.run( data ), world );
	}

	@:allow( echoes.World )
	private function unserializeFromData( data : Dynamic, world : World ) : Void {
		if ( data == null ) return;
		if ( Std.isOfType( data, Array ) ) {
			final values : Array<Dynamic> = cast data;
			for ( id in 0...values.length ) if ( values[id] != null ) {
				world.ensureEntityRegistered( cast id );
				add( cast id, cast values[id], world );
			}
		} else {
			final values : Map<Int, Dynamic> = cast data;
			for ( id => value in values ) if ( value != null ) {
				world.ensureEntityRegistered( cast id );
				add( cast id, cast value, world );
			}
		}
	}

	@:noCompletion
	public function insertSparse( entity : Entity, value : Dynamic ) : Void {
		final row = denseEntities.length;
		sparse[entity.id] = row;
		denseEntities.push( entity );
		denseValues.push( cast value );
	}

	@:noCompletion
	public function removeSparse( entity : Entity ) : Dynamic {
		final row = sparse[entity.id];
		if ( row == null ) return null;
		final value : Dynamic = denseValues[row];
		final last = denseEntities.length - 1;
		if ( row != last ) {
			final swapped = denseEntities[last];
			denseEntities[row] = swapped;
			denseValues[row] = denseValues[last];
			sparse[swapped.id] = row;
		}
		denseEntities.pop();
		denseValues.pop();
		sparse[entity.id] = null;
		return value;
	}

	@:allow( echoes.World )
	private function clear() : Void {
		sparse.resize( 0 );
		denseEntities.resize( 0 );
		denseValues.resize( 0 );
		ongoingRemovals.resize( 0 );
	}

	@:allow( echoes.World )
	private function valuesByEntityId() : Array<Dynamic> {
		final result : Array<Dynamic> = [];
		for ( entity in entitiesSnapshot() ) result[entity.id] = get( entity );
		return result;
	}

	private function entitiesSnapshot() : Array<Entity> {
		if ( storageKind == StorageKind.SparseSet ) return denseEntities.copy();
		final result : Array<Entity> = [];
		for ( entity in world.allEntities() ) if ( entityHasThisComponent( entity ) ) result.push( entity );
		return result;
	}

	private inline function entityHasThisComponent( entity : Entity ) : Bool return world.entityHasComponent( entity, storageId );

	private inline function toString() : String return name;
}

@:forward( componentType, storageId, storageKind, exists, get, getAt, name, relatedQueries, relatedViews, remove, removeAll, shortComponentType, add )
abstract DynamicComponentStorage( ComponentStorage<Dynamic> ) to ComponentStorage<Any> {
	@:from private static inline function fromComponentStorage<T>( componentStorage : ComponentStorage<T> ) : DynamicComponentStorage return cast componentStorage;

	@:allow( echoes.QueryBase )
	private var _relatedQueries( get, never ) : Array<QueryBase>;
	private inline function get__relatedQueries() : Array<QueryBase> return this._relatedQueries;

	@:allow( echoes.World )
	private inline function insertSparse( entity : Entity, value : Dynamic ) : Void this.insertSparse( entity, value );
	@:allow( echoes.World )
	private inline function removeSparse( entity : Entity ) : Dynamic return this.removeSparse( entity );
}

/** Component types currently attached to an entity. */
@:forward( contains, containsComponentStorage, iterator, length ) @:forward.new
@:allow( echoes.ComponentStorage )
abstract EntityComponents( ComponentTypes ) from ComponentTypes {
	@:allow( echoes.World )
	private inline function addComponentStorage( storage : DynamicComponentStorage ) : Void this.addComponentStorage( storage );

	@:allow( echoes.Entity )
	private static inline function forEntity( entity : Entity, world : World ) : EntityComponents {
		if ( world.components[entity.id] == null ) world.components[entity.id] = new EntityComponents();
		return world.components[entity.id];
	}

	@:allow( echoes.Entity )
	private static function removeAll( entity : Entity, world : World ) : Void {
		final entityComponents = world.components[entity.id];
		if ( entityComponents == null ) return;
		final snapshot = [for ( storage in entityComponents ) storage];
		for ( storage in snapshot ) storage.remove( entity, world );
	}

	@:allow( echoes.World )
	private inline function removeComponentStorage( storage : DynamicComponentStorage ) : Bool return this.removeComponentStorage( storage );

	@:to private inline function toIterable() : Iterable<DynamicComponentStorage> return this;

	public inline function toMap( world : World ) : Map<String, Dynamic> {
		final entity : Entity = switch ( world.components.indexOf( cast this ) ) {
			case -1: throw "This EntityComponents instance was disposed.";
			case x: cast x;
		};
		return [for ( storage in this ) storage.componentType => storage.get( entity )];
	}
}
