package echoes.macro;

#if macro
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;
import echoes.macro.ComponentStorageBuilder;
import echoes.macro.MacroTools;
import echoes.macro.internal.query.QueryNaming;
import echoes.macro.internal.query.QueryIterationEmitter;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import Lambda;

// using echoes.macro.ComponentStorageBuilder;
// using echoes.macro.MacroTools;
// using haxe.macro.ComplexTypeTools;
// using haxe.macro.Context;
// using Lambda;
class QueryBuilder {

	private static final queryCache : Map<String, { components : Array<ComplexType>, type : Type }> = new Map();

	private static var globalId = 0;

	public static inline function isQuery( name : String ) : Bool {
		return queryCache.exists( name );
	}

	/**
	 * Returns the canonical ordering of these components. (If such an ordering
	 * hasn't been defined, the given order will become canonical.)
	 */
	public static function getComponentOrder(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : Array<ComplexType> {

		final name : String = getQueryName( components, excludedComponents );
		if ( !queryCache.exists( name ) ) {
			createQueryType( components, excludedComponents );
		}

		return queryCache[name].components;
	}

	/**
	 * Returns the name of the `Query` class corresponding to the given
	 * components. Will return the same name regardless of component order.
	 * 
	 * Note: C++ compilation requires generating a .cpp file for each Haxe
	 * class, including queries. To avoid Windows's file length limit, query names
	 * will be limited to 80 characters in C++. To adjust this limit, use
	 * `-Dechoes_max_name_length=[number]`.
	 */
	public static function getQueryName(
		components : Array<ComplexType>,
		?exclComps : Array<ComplexType>
	) : String {
		return QueryNaming.getName( components, exclComps );
	}

	public static function build() : Type {

		switch ( Context.getLocalType() ) {
			case TInst( _, types ) if ( types != null && types.length > 0 ):
				return createQueryType( [for ( type in types )
					Context.toComplexType( MacroTools.followMono( type ) )] );
			default:
				Context.error( "Expected one or more type parameters.", Context.currentPos() );
				return null;
		}
	}

	public static function createQueryType(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : Type {

		// for ( comp in components ) trace( util.Macros.formatExpr( comp ) );
		final queryClassName : String = getQueryName( components, excludedComponents );

		if ( queryCache.exists( queryClassName ) ) {
			return queryCache[queryClassName].type;
		}

		// Check for duplicate components.
		components.map( MacroTools.followName ).sort( function ( a : String, b : String ) : Int {
			final diff : Int = MacroTools.compareStrings( a, b );
			if ( diff == 0 ) {
				Context.error( 'More than one component of type $a.', Context.currentPos() );
			}
			return diff;
		} );

		final queryTypePath : TypePath = { pack : [], name : queryClassName };
		final queryComplexType : ComplexType = TPath( queryTypePath );

		/**
		 * The function signature for any event listeners attached to this query.
		 * Includes `Entity` as the first argument, meaning that in a
		 * `Query<Hue, Saturation>`, listeners would need to have the signature
		 * `(Entity, Hue, Saturation) -> Void`.
		 */
		final callbackType : ComplexType = TFunction( [macro : echoes.Entity].concat( components ), macro : Void );

		/**
		 * The arguments required to dispatch an add or update event. In a
		 * `Query<Hue, Saturation>`, the callback should look like this:
		 * 
		 * ```haxe
		 * callback(entity, HueContainer.instance.get(entity),
		 *     SaturationContainer.instance.get(entity));
		 * ```
		 */
		final callbackArgs : Array<Expr> = [for ( component in components )
			macro ${ComponentStorageBuilder.getComponentStorage( macro world, component )}.get( entity )];

		/**
		 * The arguments required to dispatch a remove event. Unlike with
		 * `callbackArgs`, one of the components will already have been removed
		 * from storage. We have to check which one was removed and replace its
		 * value with `removedComponent`.
		 * 
		 * In a `Query<Hue, Saturation>`, the callback should look like this:
		 * 
		 * ```haxe
		 * callback(entity,
		 *     HueContainer.instance == removedComponentStorage
		 *         ? removedComponent : HueContainer.instance.get(entity),
		 *     SaturationContainer.instance == removedComponentStorage
		 *         ? removedComponent : SaturationContainer.instance.get(entity));
		 * ```
		 * 
		 * Note: these tests will be performed inside a `for` loop. While this
		 * may sound inefficient, in practice many (if not most) queries will only
		 * run the loop for 0-1 iterations.
		 */
		final removedCallbackArgs : Array<Expr> = [for ( component in components ) {
			final inst : Expr = macro ${ComponentStorageBuilder.getComponentStorage( macro world, component )};
			macro $inst == removedComponentStorage ? removedComponent : $inst.get( entity );
		}];

		// Pass `entity` as the first argument to both.
		callbackArgs.unshift( macro entity );
		removedCallbackArgs.unshift( macro entity );

		// trace(queryTypePath);

		final compExprs = [
			for ( component in components )
				macro ${ComponentStorageBuilder.getComponentStorage( macro world, component )}
		];

		final excludedCompExprs = //
			if ( excludedComponents != null )
				[
					for ( component in excludedComponents )
						macro ${ComponentStorageBuilder.getComponentStorage( macro world, component )}
				];
			else
				[];

		final def : TypeDefinition = macro class $queryClassName extends echoes.Query.QueryBase {
			@:noCompletion
			@:keep
			public static final __global_id__ : Int = $v{globalId++};

			public final onAdded = new echoes.utils.Signal<$callbackType>();

			public final onRemoved = new echoes.utils.Signal<$callbackType>();

			private function new( world : echoes.World ) {
				world.addQuery( $i{queryClassName}, this );

				super(
					world,
					$a{compExprs},
					$a{excludedCompExprs}
				);
			}

			private override function dispatchAddedCallback( entity : echoes.Entity ) : Void {
				var index : Int = entities.lastIndexOf( entity );
				for ( callback in onAdded ) {
					callback( $a{callbackArgs} );

					// If the callback removed the entity, stop. Cache the index
					// to save time in most cases. HashLink is known to return 0
					// when reading out of bounds, so it has to check length too.
					if ( ${Context.defined( "hl" ) ? macro index >= entities.length : macro false}
						|| entities[index] != entity ) {
						index = entities.lastIndexOf( entity );
						if ( index < 0 ) {
							break;
						}
					}
				}
			}

			private override function dispatchRemovedCallback(
				entity : echoes.Entity,
				?removedComponentStorage : echoes.ComponentStorage.DynamicComponentStorage,
				?removedComponent : Any
			) : Void {

				var exception : haxe.Exception = null;
				for ( callback in onRemoved ) {
					try {
						callback( $a{removedCallbackArgs} );
					} catch( e : haxe.Exception ) {
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

			public function iter( callback : $callbackType ) : Void {
				${
					{
						final args = [
							for ( i => component in components )
								{ name : "component" + i, type : component }
						];
						args.unshift( { name : "entity", type : macro : echoes.Entity } );
						forEachEntityInQuery(
							macro callback,
							args,
							excludedComponents,
							macro 0,
							macro world
						);
					}
				}
			}
		}

		Context.defineType( def );

		final queryType : Type = ComplexTypeTools.toType( queryComplexType );
		queryCache.set( queryClassName, { components : components, type : queryType } );

		Report.queryNames.push( queryClassName );

		return queryType;
	}

	public static function forEachEntityInQuery(
		func : Expr,
		args : Array<FunctionArg>,
		exclComps : Array<ComplexType>,
		getDeltaTime : Expr,
		worldExpr : ExprOf<World>
	) : Expr {
		return QueryIterationEmitter.emit( func, args, exclComps, getDeltaTime, worldExpr );
	}
}
#end
