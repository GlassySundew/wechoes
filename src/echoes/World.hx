package echoes;

import echoes.macro.MacroTools;
import echoes.macro.ComponentStorageBuilder;
import echoes.ComponentStorage.EntityComponents;
import echoes.View.ViewBase;
import echoes.ComponentStorage.DynamicComponentStorage;
import haxe.ds.ReadOnlyArray;
import haxe.Unserializer;
import haxe.Serializer;
#if macro
import haxe.macro.Expr;
import echoes.macro.ComponentStorageBuilder;
import echoes.macro.MacroTools;
import echoes.macro.ViewBuilder;
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
	 * All currently-active views.
	 */
	public var activeViews( get, never ) : ReadOnlyArray<ViewBase>;
	private inline function get_activeViews() : ReadOnlyArray<ViewBase> return _activeViews;

	public final activeSystems : SystemList;

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

	private final viewStorage : Array<ViewBase> = [];

	/**
	 * The index of each entity in `activeEntities`. For any active entity,
	 * `entity == activeEntities[activeEntityIndices[entity.id]]`.
	 */
	@:allow( echoes.Entity )
	private final activeEntityIndices : Array<Null<Int>> = [];

	@:allow( echoes.ViewBase )
	private final _activeViews : Array<ViewBase> = [];

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
		var i : Int = activeViews.length;
		while ( --i >= 0 ) {
			activeViews[i].reset();
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

	public function getOrCreateView<T : ViewBase>( cl : Class<T> ) : T {

		final id : Int = untyped cl.__global_id__;

		if ( viewStorage[id] == null ) {
			viewStorage[id] = Type.createInstance( cl, [this] );
		}

		return cast viewStorage[id];
	}

	public function addView<T : ViewBase>( cl : Class<T>, view : T ) {
		final id : Int = untyped cl.__global_id__;

		if ( viewStorage[id] != null )
			trace( 'attaching an already existing view with id ${id}' );

		viewStorage[id] = view;
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
	 * Gets an inactive `View` of the given components. The calling class should
	 * call `activate()` before attempting to use it.
	 * @see `getView()` to automatically activate the view.
	 */
	#if macro static #else macro #end
	public function getInactiveView(
		world : ExprOf<World>,
		componentTypes : ExprOf<Array<Class<Any>>>,
		?excludedComponents : ExprOf<Array<Class<Any>>>
	) : Expr {

		final componentComplexTypes : Array<ComplexType> = [];
		switch componentTypes.expr {
			case EArrayDecl( values ):
				for ( type in values ) {
					componentComplexTypes.push( MacroTools.parseClassExpr( type ) );
				}
			case _e:
				throw '$_e is not supported!';
		}

		final excludedComplexTypes : Array<ComplexType> = [];
		switch excludedComponents.expr {
			case EArrayDecl( values ):
				for ( type in values ) {
					excludedComplexTypes.push( MacroTools.parseClassExpr( type ) );
				}
			case EConst( CIdent( id ) ):
			case _e:
				throw '$_e is not supported!';
		}

		final viewName : String = ViewBuilder.getViewName( componentComplexTypes, excludedComplexTypes );
		ViewBuilder.createViewType( componentComplexTypes, excludedComplexTypes );

		return macro Std.downcast( $world.getOrCreateView( $i{viewName} ), $i{viewName} );
	}

	/**
	 * Gets an active `View` of the given components. The calling class should
	 * call `deactivate()` once done using it.
	 * 
	 * Sample usage:
	 * 
	 * ```haxe
	 * var view:View<A, B, C> = Echoes.getView(A, B, C);
	 * trace(view.entities.length);
	 * view.onAdded.push((entity:Entity, a:A, b:B, c:C) -> trace(a + b * c));
	 * ```
	 */
	#if macro static #else macro #end
	public function getView(
		world : ExprOf<World>,
		componentTypes : ExprOf<Array<Class<Any>>>,
		?excludedComponents : ExprOf<Array<Class<Any>>>
	) : Expr {
		final view : Expr = World.getInactiveView( world, componentTypes, excludedComponents );

		return macro {
			$view.activate();
			$view;
		};
	}
}

typedef AppStatistics = {
	var cachedEntities : Int;
	var entities : Int;
	var systems : Array<SystemDetails>;
	var views : Array<{
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
