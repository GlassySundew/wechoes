package echoes;

import echoes.macro.MacroTools;
import echoes.macro.ComponentStorageBuilder;
import echoes.ComponentStorage.EntityComponents;
import echoes.Query.QueryBase;
import echoes.ComponentStorage.DynamicComponentStorage;
import haxe.ds.ReadOnlyArray;
import haxe.Unserializer;
import haxe.Serializer;
#if macro
import haxe.macro.Expr;
import echoes.macro.ComponentStorageBuilder;
import echoes.macro.MacroTools;
import echoes.macro.QueryBuilder;
#end

class World {

	/**
	 * All currently-active entities.
	 * 
	 * Note: to improve performance, this array is re-ordered whenever an entity
	 * is deactivated or destroyed. To suppress this behavior and keep the array
	 * in a consistent order, use `-D echoes_stable_order`.
	 */
	@:allow( echoes.Entity )
	private final _activeEntities : Array<Entity> = [];
	public var activeEntities( get, never ) : ReadOnlyArray<Entity>;
	private inline function get_activeEntities() : ReadOnlyArray<Entity> return _activeEntities;

	@:allow( echoes.ComponentStorage )
	private final _componentStorage : Array<ComponentStorage<Dynamic>> = [];
	public var componentStorage( get, never ) : Array<ComponentStorage<Dynamic>>;
	private inline function get_componentStorage() : Array<ComponentStorage<Dynamic>> return _componentStorage;

	/**
	 * All currently-active queries.
	 */
	public var activeQueries( get, never ) : ReadOnlyArray<QueryBase>;
	private inline function get_activeQueries() : ReadOnlyArray<QueryBase> return _activeQueries;

	public final activeSystems : SystemList;

	public final updateErrors : Array<SystemExecutionError> = [];

	public var hasUpdateErrors( get, never ) : Bool;
	private inline function get_hasUpdateErrors() : Bool return updateErrors.length > 0;

	/**
	 * A destroyed entity's ID will go in this pool, and will then be reassigned
	 * to the next entity to be created.
	 */
	public final entityIdPool : Array<Int> = [];

	public var lastUpdate : Float = haxe.Timer.stamp();

	/**
	 * The next entity ID that will be allocated, if `idPool` is empty.
	 */
	public var nextEntityId : Int = 0;

	public final components : Array<EntityComponents> = [];

	public final entityGens : Array<Null<Int>> = [];

	/** Physical entity locations, indexed by entity ID. */
	public final entityLocations : Array<Null<EntityLocation>> = [];

	/** Exact component-set metadata. Archetypes are stable for the world's lifetime. */
	public final archetypes : Array<Archetype> = [];

	/** Dense table-component storage. Multiple sparse-set archetypes may share a table. */
	public final tables : Array<Table> = [];

	private final archetypesByKey : Map<String, Int> = [];
	private final tablesByKey : Map<String, Int> = [];

	/** Incremented after every structural or active-state change. */
	@:allow( echoes.Entity )
	public var structureVersion( default, null ) : Int = 0;

	private final queryStorage : Array<QueryBase> = [];

	/**
	 * The index of each entity in `activeEntities`. For any active entity,
	 * `entity == activeEntities[activeEntityIndices[entity.id]]`.
	 */
	@:allow( echoes.Entity )
	private final activeEntityIndices : Array<Null<Int>> = [];

	@:allow( echoes.QueryBase )
	private final _activeQueries : Array<QueryBase> = [];

	private var updateTimer : haxe.Timer;

	final services : Map<String, Any> = [];

	public function new() {
		createEmptyStructure();
		activeSystems = new SystemList( this );
		activeSystems.__activate__();
		activeSystems.clock.maxTime = 1;
	}

	public function init( ?fps : Float = 60 ) {
		lastUpdate = haxe.Timer.stamp();

		if ( updateTimer != null ) {
			updateTimer.stop();
			updateTimer = null;
		}

		if ( fps > 0 ) {
			updateTimer = new haxe.Timer( Std.int( 1000 / fps ) );
			updateTimer.run = update;
		}
	}

	public function update() : Void {
		final startTime : Float = haxe.Timer.stamp();
		final dt : Float = startTime - lastUpdate;
		lastUpdate = startTime;
		__beginUpdate__();

		activeSystems.__update__( dt );

		#if echoes_profiling
		lastUpdateLength = Std.int(( haxe.Timer.stamp() - startTime ) * 1000 );
		#end
	}

	public function reset() : Void {
		activeEntityIndices.resize( 0 );
		_activeEntities.resize( 0 );
		activeSystems.removeAll();

		// Iterate backwards when removing items from arrays.
		var i : Int = activeQueries.length;
		while ( --i >= 0 ) {
			activeQueries[i].reset();
		}

		for ( storage in _componentStorage ) {
			if ( storage != null )
				storage.clear();
		}
		components.resize( 0 );
		entityLocations.resize( 0 );
		for ( table in tables ) table.clear();
		archetypes.resize( 0 );
		tables.resize( 0 );
		archetypesByKey.clear();
		tablesByKey.clear();
		createEmptyStructure();
		structureVersion++;

		entityIdPool.resize( 0 );
		nextEntityId = 0;

		init( 0 );
	}

	public inline function getGen( entity : Entity ) {
		return entityGens[entity.id];
	}

	public inline function isHandleValid( handle : ecs.Types.EntityHandle ) : Bool {

		return handle.gen == getGen( handle.ent );
	}
	
	public inline function makeHandle( entity : Entity ) : ecs.Types.EntityHandle {

		return { ent : entity, gen : getGen( entity ) };
	}

	public function getStorage( id : Int ) : ComponentStorage<Dynamic> {
		return this._componentStorage[id];
	}

	public function addStorage( id : Int, componentStorage : DynamicComponentStorage ) {
		final concrete : ComponentStorage<Dynamic> = cast componentStorage;
		if ( concrete.storageId != id ) {
			if ( _componentStorage[concrete.storageId] == concrete ) _componentStorage[concrete.storageId] = null;
			concrete.storageId = id;
		}
		this._componentStorage[id] = componentStorage;
	}

	private static inline function signatureKey( componentIds : Array<Int> ) : String {
		return componentIds.join( "," );
	}

	private function createEmptyStructure() : Void {
		final table = new Table( tables.length, [] );
		tables.push( table );
		tablesByKey[""] = table.id;
		final archetype = new Archetype( archetypes.length, table.id, [] );
		archetypes.push( archetype );
		archetypesByKey[""] = archetype.id;
	}

	@:allow( echoes.Entity )
	private function registerEntity( entity : Entity ) : Void {
		final archetype = archetypes[0];
		final table = tables[0];
		final tableRow = table.append( entity, [] );
		final archetypeRow = archetype.append( entity, tableRow );
		entityLocations[entity.id] = new EntityLocation( archetype.id, archetypeRow, table.id, tableRow );
		if ( components[entity.id] == null ) components[entity.id] = new EntityComponents();
		structureVersion++;
	}

	@:allow( echoes.ComponentStorage )
	private inline function ensureEntityRegistered( entity : Entity ) : Void {
		if ( entityLocations[entity.id] == null ) {
			if ( entityGens[entity.id] == null ) entityGens[entity.id] = 0;
			registerEntity( entity );
		}
	}

	public inline function getEntityLocation( entity : Entity ) : Null<EntityLocation> {
		return entityLocations[entity.id];
	}

	public inline function entityHasComponent( entity : Entity, componentId : Int ) : Bool {
		final location = entityLocations[entity.id];
		return location != null && archetypes[location.archetypeId].hasComponent( componentId );
	}

	public inline function getTableComponent( entity : Entity, componentId : Int ) : Dynamic {
		final location = entityLocations[entity.id];
		return location == null ? null : tables[location.tableId].get( componentId, location.tableRow );
	}

	public inline function setTableComponent( entity : Entity, componentId : Int, value : Dynamic ) : Void {
		final location = entityLocations[entity.id];
		if ( location != null ) tables[location.tableId].set( componentId, location.tableRow, value );
	}

	@:allow( echoes.ComponentStorage )
	private function notifyComponentValueChanged(
		entity : Entity,
		storage : DynamicComponentStorage,
		oldValue : Dynamic,
		addedPhase : Bool
	) : Void {
		if ( !entity.isActive( this ) ) return;
		for ( query in storage.relatedQueries ) query.onComponentValueChanged( entity, storage, oldValue, addedPhase );
	}

	public function allEntities() : Array<Entity> {
		final result : Array<Entity> = [];
		for ( id in 0...entityLocations.length ) if ( entityLocations[id] != null ) result.push( cast id );
		return result;
	}

	private function getOrCreateTable( componentIds : Array<Int> ) : Table {
		final key = signatureKey( componentIds );
		final existing = tablesByKey[key];
		if ( existing != null ) return tables[existing];
		final table = new Table( tables.length, componentIds );
		tables.push( table );
		tablesByKey[key] = table.id;
		return table;
	}

	private function getOrCreateArchetype( componentIds : Array<Int> ) : Archetype {
		componentIds.sort(( a, b ) -> a - b );
		final key = signatureKey( componentIds );
		final existing = archetypesByKey[key];
		if ( existing != null ) return archetypes[existing];

		final tableComponentIds = [for ( id in componentIds )
			if ( _componentStorage[id].storageKind == StorageKind.Table ) id];
		final table = getOrCreateTable( tableComponentIds );
		final archetype = new Archetype( archetypes.length, table.id, componentIds );
		archetypes.push( archetype );
		archetypesByKey[key] = archetype.id;
		for ( query in _activeQueries ) query.considerArchetype( archetype );
		return archetype;
	}

	private function transitionArchetype( source : Archetype, componentId : Int, adding : Bool ) : Archetype {
		final cached = adding ? source.getAddTransition( componentId ) : source.getRemoveTransition( componentId );
		if ( cached != null ) return archetypes[cached];

		final ids = [for ( id in source.componentIds ) id];
		if ( adding ) ids.push( componentId ) else ids.remove( componentId );
		final destination = getOrCreateArchetype( ids );
		if ( adding ) {
			source.setAddTransition( componentId, destination.id );
			destination.setRemoveTransition( componentId, source.id );
		} else {
			source.setRemoveTransition( componentId, destination.id );
			destination.setAddTransition( componentId, source.id );
		}
		return destination;
	}

	@:allow( echoes.ComponentStorage )
	private function addComponent( entity : Entity, storage : DynamicComponentStorage, value : Dynamic ) : Void {
		final location = entityLocations[entity.id];
		if ( location == null ) throw 'Cannot add ${storage.componentType} to destroyed entity ${entity.id}.';
		final source = archetypes[location.archetypeId];
		final destination = transitionArchetype( source, storage.storageId, true );
		moveEntity( entity, source, destination, storage, value, true );
	}

	@:allow( echoes.ComponentStorage )
	private function removeComponent( entity : Entity, storage : DynamicComponentStorage ) : Void {
		final location = entityLocations[entity.id];
		if ( location == null || !archetypes[location.archetypeId].hasComponent( storage.storageId ) ) return;
		final removed = storage.get( entity );
		final source = archetypes[location.archetypeId];
		final destination = transitionArchetype( source, storage.storageId, false );
		moveEntity( entity, source, destination, storage, removed, false );
	}

	private function moveEntity(
		entity : Entity,
		source : Archetype,
		destination : Archetype,
		changedStorage : DynamicComponentStorage,
		changedValue : Dynamic,
		adding : Bool
	) : Void {
		final location = entityLocations[entity.id];
		final sourceTable = tables[location.tableId];
		final destinationTable = tables[destination.tableId];
		var destinationTableRow = location.tableRow;

		if ( changedStorage.storageKind == StorageKind.SparseSet ) {
			if ( adding ) changedStorage.insertSparse( entity, changedValue ) else changedStorage.removeSparse( entity );
		} else {
			final values : Map<Int, Dynamic> = [];
			for ( componentId in destinationTable.componentIds ) {
				values[componentId] = componentId == changedStorage.storageId && adding
					? changedValue
					: sourceTable.get( componentId, location.tableRow );
			}
			destinationTableRow = destinationTable.append( entity, values );
		}

		final destinationArchetypeRow = destination.append( entity, destinationTableRow );
		final oldArchetypeRow = location.archetypeRow;
		final oldTableRow = location.tableRow;
		location.archetypeId = destination.id;
		location.archetypeRow = destinationArchetypeRow;
		location.tableId = destination.tableId;
		location.tableRow = destinationTableRow;

		final swappedArchetypeEntity = source.swapRemove( oldArchetypeRow );
		if ( swappedArchetypeEntity != null ) {
			entityLocations[swappedArchetypeEntity.entity.id].archetypeRow = oldArchetypeRow;
		}

		if ( changedStorage.storageKind == StorageKind.Table ) {
			final swappedTableEntity = sourceTable.swapRemove( oldTableRow );
			if ( swappedTableEntity != null ) {
				final swappedLocation = entityLocations[swappedTableEntity.id];
				swappedLocation.tableRow = oldTableRow;
				archetypes[swappedLocation.archetypeId].entities[swappedLocation.archetypeRow].tableRow = oldTableRow;
			}
		}

		var entityComponents = components[entity.id];
		if ( adding ) entityComponents.addComponentStorage( changedStorage ) else entityComponents.removeComponentStorage( changedStorage );
		structureVersion++;

		if ( entity.isActive( this ) ) {
			var exception : haxe.Exception = null;
			for ( query in changedStorage.relatedQueries ) {
				try {
					query.onEntityTransition(
						entity,
						source,
						destination,
						adding ? null : changedStorage,
						adding ? null : changedValue
					);
				} catch ( error : haxe.Exception ) {
					if ( exception == null ) exception = error;
				}
				if ( adding && !changedStorage.exists( entity ) ) break;
			}
			if ( exception != null ) throw exception;
		}
	}

	@:allow( echoes.Entity )
	private function releaseEntity( entity : Entity ) : Void {
		final location = entityLocations[entity.id];
		if ( location == null ) return;
		final archetype = archetypes[location.archetypeId];
		final table = tables[location.tableId];
		final swappedArchetypeEntity = archetype.swapRemove( location.archetypeRow );
		if ( swappedArchetypeEntity != null ) entityLocations[swappedArchetypeEntity.entity.id].archetypeRow = location.archetypeRow;
		final swappedTableEntity = table.swapRemove( location.tableRow );
		if ( swappedTableEntity != null ) {
			final swappedLocation = entityLocations[swappedTableEntity.id];
			swappedLocation.tableRow = location.tableRow;
			archetypes[swappedLocation.archetypeId].entities[swappedLocation.archetypeRow].tableRow = location.tableRow;
		}
		entityLocations[entity.id] = null;
		components[entity.id] = null;
		structureVersion++;
	}

	public macro function getService<T>( ethis : ExprOf<World>, type : ExprOf<Class<T>> ) : ExprOf<T> {
		var cl = MacroTools.parseClassExpr( type );

		return macro {@:privateAccess ( $ethis.services.get( $v{util.Macros.getTypeIdentifier( cl )} ) : $cl );};
	}

	public macro function setService<T>( ethis : ExprOf<World>, type : ExprOf<Class<T>>, value : ExprOf<T> ) : Expr {
		var cl = MacroTools.parseClassExpr( type );

		return macro {@:privateAccess $ethis.services.set( $v{util.Macros.getTypeIdentifier( cl )}, $value );};
	}

	public function getOrCreateQuery<T : QueryBase>( cl : Class<T> ) : T {

		final id : Int = untyped cl.__global_id__;

		if ( queryStorage[id] == null ) {
			queryStorage[id] = Type.createInstance( cl, [this] );
		}

		return cast queryStorage[id];
	}

	public function addQuery<T : QueryBase>( cl : Class<T>, query : T ) {
		final id : Int = untyped cl.__global_id__;

		if ( queryStorage[id] != null )
			trace( 'attaching an already existing query with id ${id}' );

		queryStorage[id] = query;
	}

	@:allow( echoes.SystemList )
	private inline function __beginUpdate__() : Void {
		updateErrors.resize( 0 );
	}

	@:allow( echoes.SystemList )
	private function __reportSystemError__(
		systemList : SystemList,
		system : System,
		error : haxe.Exception,
		dt : Float,
		step : Float
	) : Void {
		updateErrors.push( {
			systemName : Std.string( system ),
			systemListName : systemList.name,
			error : error,
			deltaTime : dt,
			step : step
		} );
	}

	// Serialization
	// =============

	public function serialize() : String {
		final data : Dynamic = {
			"world.activeEntities" : activeEntities,
			"echoes.Entity.idPool" : entityIdPool,
			"echoes.Entity.nextId" : nextEntityId
		};

		for ( storage in componentStorage ) {

			if ( storage == null )
				continue;

			final storedComponents = ( cast storage : ComponentStorage<Dynamic> ).valuesByEntityId();
			if ( storedComponents.length > 0 ) {
				Reflect.setField( data, storage.componentType, storedComponents );
			}
		}

		return Serializer.run( data );
	}

	/**
	 * Restores all entities and components recorded by `serialize()`,
	 * overwriting any existing entities or components.
	 * 
	 * Caution: serializing and unserializing are not well-tested. Use this at
	 * your own risk, and especially avoid unserializing if the component types
	 * could have changed. Even a minor change, such as changing `Int` to
	 * `Float`, can cause errors on some targets.
	 */
	public function unserialize( data : String ) : Void {
		for ( storage in _componentStorage ) {
			if ( storage != null )
				storage.removeAll( this );
		}

		activeEntityIndices.resize( 0 );
		_activeEntities.resize( 0 );

		final data : Dynamic = Unserializer.run( data );
		for ( entity in( Reflect.field( data, "world.activeEntities" ) : Array<Entity> ) ) {
			if ( entityLocations[entity.id] == null ) registerEntity( entity );
			activeEntityIndices[entity.id] = _activeEntities.length;
			_activeEntities.push( entity );
		}

		nextEntityId = Reflect.field( data, "echoes.Entity.nextId" );
		entityIdPool.resize( 0 );
		for ( id in( Reflect.field( data, "echoes.Entity.idPool" ) : Array<Int> ) ) {
			entityIdPool.push( id );
			entityGens[id]++;
		}

		for ( storage in componentStorage ) {
			if ( storage != null )
				( cast storage : ComponentStorage<Dynamic> )
					.unserializeFromData(
						Reflect.field( data, storage.componentType ),
						this
					);
		}
	}

	/**
	 * Returns the `ComponentStorage` singleton for the given component type.
	 * 
	 * Sample usage:
	 * 
	 * ```haxe
	 * var stringStorage:ComponentStorage<String> = Echoes.getComponentStorage(String);
	 * 
	 * if(stringStorage.exists(entity)) {
	 *     trace(stringStorage.get(entity));
	 * } else {
	 *     stringStorage.add(entity, "string");
	 * }
	 * ```
	 */
	public macro function getComponentStorage( ethis : ExprOf<World>, componentType : ExprOf<Class<Any>> ) : Expr {
		return ComponentStorageBuilder.getComponentStorage( ethis, MacroTools.parseClassExpr( componentType ) );
	}

	/**
	 * Gets an inactive `Query` of the given components. The calling class should
	 * call `activate()` before attempting to use it.
	 * @see `getQuery()` to automatically activate the query.
	 */
	#if macro static #else macro #end
	public function getInactiveQuery(
		world : ExprOf<World>,
		componentTypes : Array<ExprOf<Class<Any>>>
	) : Expr {
		final normalized = normalizeQueryArguments( componentTypes );
		final componentComplexTypes : Array<ComplexType> = [for ( type in normalized.components )
			MacroTools.parseClassExpr( type )];
		final excludedComplexTypes : Array<ComplexType> = [for ( type in normalized.excluded )
			MacroTools.parseClassExpr( type )];

		final queryName : String = QueryBuilder.getQueryName( componentComplexTypes, excludedComplexTypes );
		QueryBuilder.createQueryType( componentComplexTypes, excludedComplexTypes );

		return macro Std.downcast( $world.getOrCreateQuery( $i{queryName} ), $i{queryName} );
	}

	#if macro
	private static function normalizeQueryArguments( arguments : Array<Expr> ) : {
		components : Array<Expr>,
		excluded : Array<Expr>
	} {
		return switch ( arguments ) {
			case [{ expr : EArrayDecl( components ) }, { expr : EArrayDecl( excluded ) }]:
				{ components : components, excluded : excluded };
			case [{ expr : EArrayDecl( components ) }]:
				{ components : components, excluded : [] };
			default:
				{ components : arguments, excluded : [] };
		};
	}
	#end

	/**
	 * Gets an active `Query` of the given components. The calling class should
	 * call `deactivate()` once done using it.
	 * 
	 * Sample usage:
	 * 
	 * ```haxe
	 * var query:Query<A, B, C> = Echoes.getQuery(A, B, C);
	 * trace(query.entities.length);
	 * query.onAdded.push((entity:Entity, a:A, b:B, c:C) -> trace(a + b * c));
	 * ```
	 */
	#if macro static #else macro #end
	public function getQuery(
		world : ExprOf<World>,
		componentTypes : Array<ExprOf<Class<Any>>>
	) : Expr {
		final query : Expr = World.getInactiveQuery( world, componentTypes );

		return macro {
			$query.activate();
			$query;
		};
	}

}

typedef AppStatistics = {
	var cachedEntities : Int;
	var entities : Int;
	var systems : Array<SystemDetails>;
	var queries : Array<{
		var name : String;
		var entities : Int;
	}>;
};

typedef SystemDetails = {
	var name : String;
	@:optional var children : Array<SystemDetails>;
	#if echoes_profiling
	var deltaTime : Int;
	#end
};

typedef SystemExecutionError = {
	var systemName : String;
	var systemListName : String;
	var error : haxe.Exception;
	var deltaTime : Float;
	var step : Float;
};
