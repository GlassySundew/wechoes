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

	@:deprecated( "Use activeQueries instead." )
	public var activeViews( get, never ) : ReadOnlyArray<QueryBase>;
	private inline function get_activeViews() : ReadOnlyArray<QueryBase> return activeQueries;

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
		this._componentStorage[id] = componentStorage;
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

	@:deprecated( "Use getOrCreateQuery() instead." )
	public inline function getOrCreateView<T : QueryBase>( cl : Class<T> ) : T {
		return getOrCreateQuery( cl );
	}

	public function addQuery<T : QueryBase>( cl : Class<T>, query : T ) {
		final id : Int = untyped cl.__global_id__;

		if ( queryStorage[id] != null )
			trace( 'attaching an already existing query with id ${id}' );

		queryStorage[id] = query;
	}

	@:deprecated( "Use addQuery() instead." )
	public inline function addView<T : QueryBase>( cl : Class<T>, query : T ) : Void {
		addQuery( cl, query );
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

			final components = ( cast storage : ComponentStorage<Dynamic> ).storage;

			// Omit empty arrays. It isn't as easy to check if a map is empty, so
			// just include all of them.
			if ( #if( echoes_storage == "Map" ) true #else components.length > 0 #end ) {
				Reflect.setField( data, storage.componentType, components );
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

	@:deprecated( "Use getInactiveQuery() instead." )
	#if macro static #else macro #end
	public function getInactiveView(
		world : ExprOf<World>,
		componentTypes : Array<ExprOf<Class<Any>>>
	) : Expr {
		return World.getInactiveQuery( world, componentTypes );
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

	@:deprecated( "Use getQuery() instead." )
	#if macro static #else macro #end
	public function getView(
		world : ExprOf<World>,
		componentTypes : Array<ExprOf<Class<Any>>>
	) : Expr {
		return World.getQuery( world, componentTypes );
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
