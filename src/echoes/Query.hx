package echoes;

import echoes.ComponentStorage.DynamicComponentStorage;
import echoes.utils.ReadOnlyData;
import echoes.utils.Signal;
import haxe.Exception;

#if !macro
@:genericBuild( echoes.macro.QueryBuilder.build() )
#end
abstract class Query<Rest> extends QueryBase {}

/**
 * A structural query caches matching archetypes, not individual entities.
 * Entity lists are snapshots assembled on demand for API compatibility.
 */
abstract class QueryBase {
	private var activations : Int = 0;
	public var active( get, never ) : Bool;
	private inline function get_active() : Bool return activations > 0;

	public final componentStorages : ReadOnlyArray<DynamicComponentStorage>;
	public final excludeComponentStorage : ReadOnlyArray<DynamicComponentStorage>;
	public final requiredComponentIds : ReadOnlyArray<Int>;
	public final excludedComponentIds : ReadOnlyArray<Int>;

	private final matchingArchetypes : Array<Archetype> = [];
	public var archetypes( get, never ) : ReadOnlyArray<Archetype>;
	private inline function get_archetypes() : ReadOnlyArray<Archetype> return matchingArchetypes;
	private final _entities : Array<Entity> = [];

	public var entities( get, never ) : ReadOnlyArray<Entity>;
	private function get_entities() : ReadOnlyArray<Entity> {
		_entities.resize( 0 );
		if ( active ) {
			for ( archetype in matchingArchetypes ) {
				for ( row in archetype.entities ) {
					if ( row.entity.isActive( world ) ) _entities.push( row.entity );
				}
			}
		}
		return _entities;
	}

	final world : World;

	public function new(
		world : World,
		componentStorages : Array<DynamicComponentStorage>,
		?excludeComponentStorage : Array<DynamicComponentStorage>
	) {
		this.world = world;
		this.componentStorages = componentStorages;
		this.excludeComponentStorage = excludeComponentStorage ?? [];
		this.requiredComponentIds = [for ( storage in componentStorages ) storage.storageId];
		this.excludedComponentIds = [for ( storage in this.excludeComponentStorage ) storage.storageId];
	}

	public function activate() : Void {
		activations++;
		if ( activations != 1 ) return;
		world._activeQueries.push( this );
		for ( storage in componentStorages ) if ( !storage._relatedQueries.contains( this ) ) storage._relatedQueries.push( this );
		for ( storage in excludeComponentStorage ) if ( !storage._relatedQueries.contains( this ) ) storage._relatedQueries.push( this );
		matchingArchetypes.resize( 0 );
		for ( archetype in world.archetypes ) considerArchetype( archetype );
	}

	@:allow( echoes.World )
	private function considerArchetype( archetype : Archetype ) : Void {
		if ( archetype.matches( requiredComponentIds, excludedComponentIds ) && !matchingArchetypes.contains( archetype ) ) {
			matchingArchetypes.push( archetype );
		}
	}

	@:allow( echoes.World )
	private function onEntityTransition(
		entity : Entity,
		from : Archetype,
		to : Archetype,
		?removedComponentStorage : DynamicComponentStorage,
		?removedComponent : Any
	) : Void {
		if ( !active ) return;
		final matchedBefore = from.matches( requiredComponentIds, excludedComponentIds );
		final matchesNow = to.matches( requiredComponentIds, excludedComponentIds );
		if ( !matchedBefore && matchesNow ) {
			final current = world.getEntityLocation( entity );
			if ( current != null && world.archetypes[current.archetypeId].matches( requiredComponentIds, excludedComponentIds ) ) {
				dispatchAddedCallback( entity );
			}
		} else if ( matchedBefore && !matchesNow ) {
			dispatchRemovedCallback( entity, removedComponentStorage, removedComponent );
		}
	}

	@:allow( echoes.Entity )
	private function onEntityActiveChange( entity : Entity, becameActive : Bool ) : Void {
		if ( !active ) return;
		final location = world.getEntityLocation( entity );
		if ( location == null || !world.archetypes[location.archetypeId].matches( requiredComponentIds, excludedComponentIds ) ) return;
		if ( becameActive ) dispatchAddedCallback( entity ) else dispatchRemovedCallback( entity );
	}

	@:allow( echoes.World )
	private function onComponentValueChanged(
		entity : Entity,
		storage : DynamicComponentStorage,
		oldValue : Dynamic,
		addedPhase : Bool
	) : Void {
		if ( !active ) return;
		final location = world.getEntityLocation( entity );
		if ( location == null || !world.archetypes[location.archetypeId].matches( requiredComponentIds, excludedComponentIds ) ) return;
		if ( addedPhase ) dispatchAddedCallback( entity ) else dispatchRemovedCallback( entity, storage, oldValue );
	}

	public inline function deactivate() : Void {
		activations--;
		if ( activations <= 0 ) reset();
	}

	public function iterUntyped( callback : ( Entity, Any ) -> Void ) : Void {
		final snapshot = [for ( entity in entities ) entity];
		for ( entity in snapshot ) callback( entity, [for ( storage in componentStorages ) storage.get( entity )] );
	}

	private function dispatchAddedCallback( entity : Entity ) : Void {}

	private function dispatchRemovedCallback(
		entity : Entity,
		?removedComponentStorage : DynamicComponentStorage,
		?removedComponent : Any
	) : Void {}

	@:allow( echoes.World )
	private function reset() : Void {
		activations = 0;
		world._activeQueries.remove( this );
		matchingArchetypes.resize( 0 );
		_entities.resize( 0 );
		for ( storage in componentStorages ) storage._relatedQueries.remove( this );
		for ( storage in excludeComponentStorage ) storage._relatedQueries.remove( this );
	}

	public inline function toString() : String {
		return "Query<" + [for ( storage in componentStorages ) storage.componentType].join( ", " ) + ">";
	}
}

/** Runtime-typed structural query. */
class DynamicQuery extends QueryBase {
	public final onAdded : Signal<( Entity, Array<Any> ) -> Void> = new Signal();
	public final onRemoved : Signal<( Entity, Array<Any> ) -> Void> = new Signal();

	public function new(
		world : World,
		componentStorages : Array<DynamicComponentStorage>,
		?excludeComponentStorages : Array<DynamicComponentStorage>
	) {
		super( world, componentStorages, excludeComponentStorages );
	}

	private override function dispatchAddedCallback( entity : Entity ) : Void {
		for ( callback in onAdded ) callback( entity, [for ( storage in componentStorages ) storage.get( entity )] );
	}

	private override function dispatchRemovedCallback(
		entity : Entity,
		?removedComponentStorage : DynamicComponentStorage,
		?removedComponent : Any
	) : Void {
		var exception : Exception = null;
		for ( callback in onRemoved ) {
			try {
				callback( entity, [for ( storage in componentStorages )
					storage == removedComponentStorage ? removedComponent : storage.get( entity )] );
			} catch ( e : Exception ) {
				if ( exception == null ) exception = e;
			}
		}
		if ( exception != null ) throw exception;
	}

	private override function reset() : Void {
		super.reset();
		onAdded.clear();
		onRemoved.clear();
	}

	public inline function iter( callback : ( Entity, Array<Any> ) -> Void ) : Void iterUntyped( cast callback );
}
