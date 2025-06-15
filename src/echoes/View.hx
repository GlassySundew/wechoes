package echoes;

import echoes.ComponentStorage;
import echoes.Entity;
import echoes.utils.ReadOnlyData;
import echoes.utils.Signal;
import haxe.Exception;

#if !macro
@:genericBuild( echoes.macro.ViewBuilder.build() )
#end
abstract class View<Rest> extends ViewBase {}

abstract class ViewBase {

	private var activations : Int = 0;
	public var active( get, never ) : Bool;
	private inline function get_active() : Bool return activations > 0;

	/**
	 * All `ComponentStorage` instances related to this view.
	 */
	public final componentStorage : ReadOnlyArray<DynamicComponentStorage>;
	public final excludeComponentStorage : ReadOnlyArray<DynamicComponentStorage>;

	@:allow( echoes.World )
	@:allow( echoes.ComponentStorage )
	private final _entities : Array<Entity> = [];

	/**
	 * All entities in this view.
	 */
	public var entities( get, never ) : ReadOnlyArray<Entity>;
	private inline function get_entities() : ReadOnlyArray<Entity> return _entities;

	final world : World;

	public inline function new(
		world : World,
		componentStorage : Array<DynamicComponentStorage>,
		?excludeComponentStorage : Array<DynamicComponentStorage>
	) {
		this.world = world;
		this.componentStorage = componentStorage;
		this.excludeComponentStorage = excludeComponentStorage ?? [];
	}

	public function activate() : Void {
		activations++;
		if ( activations == 1 ) {
			world._activeViews.push( this );
			for ( e in world.activeEntities ) {
				add( e );
			}
			for ( storage in componentStorage ) {
				storage._relatedViews.push( this );
			}
			for ( storage in this.excludeComponentStorage ) {
				storage._relatedViews.push( this );
			}
		}
	}

	@:allow( echoes.Entity ) @:allow( echoes.ComponentStorage )
	private inline function add( entity : Entity ) : Void {
		var filterFullfilled : Bool = true;
		for ( storage in excludeComponentStorage ) {
			if ( storage.exists( entity ) ) {
				filterFullfilled = false;
			}
		}
		if ( filterFullfilled ) {
			for ( storage in componentStorage ) {
				if ( !storage.exists( entity ) ) {
					filterFullfilled = false;
					break;
				}
			}
		}

		if ( filterFullfilled ) {

			if ( !entities.contains( entity ) ) {
				_entities.push( entity );
			}
			dispatchAddedCallback( entity );
		} else if ( entities.contains( entity ) ) {

			remove( entity );
		}
	}

	public inline function deactivate() : Void {
		activations--;
		if ( activations <= 0 ) {
			reset();
		}
	}

	public function iterUntyped( callback : ( Entity, Any ) -> Void ) : Void {
		var i : Int = 0;
		while ( i < entities.length ) {
			final entity : Entity = entities[i];
			callback( entity, [for ( storage in componentStorage ) storage.get( entity )] );

			if ( entity != entities[i] && !entities.contains( entity ) ) {
				// Entity was removed; don't increment.
			} else {
				i++;
			}
		}
	}

	private function dispatchAddedCallback( entity : Entity ) : Void {
		// Overridden by `ViewBuilder`.
	}

	private function dispatchRemovedCallback( entity : Entity, ?removedComponentStorage : DynamicComponentStorage, ?removedComponent : Any ) : Void {
		// Overridden by `ViewBuilder`.
	}

	@:allow( echoes.Entity ) @:allow( echoes.ComponentStorage )
	private inline function remove(
		entity : Entity,
		?removedComponentStorage : DynamicComponentStorage,
		?removedComponent : Any
	) : Void {

		// if (
		// 	removedComponentStorage != null
		// 	&& excludeComponentStorage.contains( removedComponentStorage ) //
		// ) {

		// 	dispatchRemovedCallback( entity, removedComponentStorage, removedComponent );
		// 	return;
		// }

		// Many applications will have a mix of short-lived and long-lived
		// entities. An entity being removed is more likely to be short-lived,
		// meaning it's near the end of the array.
		final index : Int = entities.lastIndexOf( entity );
		if ( index >= 0 ) {
			#if echoes_stable_order
			_entities.splice( index, 1 );
			#else
			_entities[index] = entities[entities.length - 1];
			_entities.pop();
			#end
			dispatchRemovedCallback( entity, removedComponentStorage, removedComponent );
		} else if ( removedComponentStorage != null ) {

			for ( exclude in excludeComponentStorage ) {

				if ( exclude == removedComponentStorage ) {

					add( entity );
				}
			}
		}
	}

	@:allow( echoes.World )
	private function reset() : Void {
		activations = 0;
		world._activeViews.remove( this );
		_entities.resize( 0 );

		for ( storage in componentStorage ) {
			storage._relatedViews.remove( this );
		}
		for ( storage in this.excludeComponentStorage ) {
			storage._relatedViews.remove( this );
		}
	}

	public inline function toString() : String {
		return "View<" + [for ( storage in componentStorage ) storage.componentType].join( ", " ) + ">";
	}
}

/**
 * A `View` that can be created at runtime.
 * 
 * Sample usage:
 * 
 * ```haxe
 * //Storage for a custom component type. Because `entity.add(x)` only works at
 * //compile time, you'll have to call `customComponent.add(entity, x)`.
 * public final customComponent:ComponentStorage<Any>;
 * 
 * //A view of `customComponent` and `String`; it'll dispatch events for any
 * //entity that has both components.
 * public final view:DynamicView;
 * 
 * public function new() {
 *     customComponent = new ComponentStorage<Any>("CustomComponent");
 *     
 *     view = new DynamicView(customComponent, Echoes.getComponentStorage(String));
 *     
 *     //Important: `DynamicView` doesn't activate itself.
 *     view.activate();
 *     
 *     //Add/remove listeners work normally, except the components are untyped.
 *     view.onAdded.add((entity:Entity, components:Array<Any>) -> trace('Entity $entity now has $components'));
 *     view.onRemoved.add((entity:Entity, components:Array<Any>) -> trace('Entity $entity no longer has all of $components'));
 * }
 * 
 * public function update(time:Float):Void {
 *     //Like with any other view, `iter()` doesn't allow for a time argument.
 *     //Here's one way to pass it in, but you could also simply leave it out.
 *     view.iter(updateEntity.bind(time));
 * }
 * 
 * private function updateEntity(time:Float, entity:Entity, components:Array<Any>):Void {
 *     trace('Updating entity $entity that has $components ($time seconds elapsed)')
 * }
 * ```
 */
class DynamicView extends ViewBase {

	public final onAdded : Signal< ( Entity, Array<Any> ) -> Void> = new Signal< ( Entity, Array<Any> ) -> Void>();
	public final onRemoved : Signal< ( Entity, Array<Any> ) -> Void> = new Signal< ( Entity, Array<Any> ) -> Void>();

	public inline function new(
		world : World,
		componentStorages : Array<DynamicComponentStorage>,
		?excludeComponentStorages : Array<DynamicComponentStorage>
	) {
		// #if debug
		// echoes.macro.MacroTools.checkWorld(world);
		// #end
		super( world, componentStorages, excludeComponentStorages );
	}

	private override function dispatchAddedCallback( entity : Entity ) : Void {
		var index : Int = entities.lastIndexOf( entity );
		for ( callback in onAdded ) {
			callback( entity, [for ( storage in componentStorage ) storage.get( entity )] );

			// If the callback removed the entity, stop. Cache the index to save
			// time in most cases. HashLink is known to return 0 when reading out
			// of bounds, so it has to check length too.
			if ( #if hl index >= entities.length || #end entities[index] != entity ) {
				index = entities.lastIndexOf( entity );
				if ( index < 0 ) {
					break;
				}
			}
		}
	}

	private override function dispatchRemovedCallback( entity : Entity, ?removedComponentStorage : DynamicComponentStorage, ?removedComponent : Any ) : Void {
		var exception : Exception = null;
		for ( callback in onRemoved ) {
			try {
				callback( entity, [for ( storage in componentStorage )
					storage == removedComponentStorage ? removedComponent : storage.get( entity )] );
			} catch( e : Exception ) {
				exception = e;
			}
		}

		if ( exception != null ) {
			throw exception;
		}
	}

	private override function reset() : Void {
		super.reset();
		onAdded.clear();
		onRemoved.clear();
	}
}
