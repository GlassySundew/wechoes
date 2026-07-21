package echoes.macro.internal.system;

#if macro
import haxe.macro.Expr;
import haxe.macro.Type;

using echoes.macro.MacroTools;
using Lambda;

/** Emits constructors, listener bridges, and lifecycle methods for a system. */
class SystemEmitter {

	public static function emit(
		fields : Array<Field>,
		nameWithParams : String,
		parentTypes : Array<ClassType>,
		linkedQueries : Array<String>,
		knownPriorities : Map<String, Expr>,
		fixedPriorityListeners : Map<String, Array<ListenerSpec>>,
		updateListeners : Array<ListenerSpec>,
		addListeners : Array<ListenerSpec>,
		removeListeners : Array<ListenerSpec>
	) : Array<Field> {
		addListenerBridges( fields, linkedQueries, updateListeners, addListeners, removeListeners );
		addConstructor( fields, linkedQueries, knownPriorities, fixedPriorityListeners );
		addOptionalFields( fields, nameWithParams );
		return lifecycleFields( parentTypes, linkedQueries, updateListeners, addListeners, removeListeners ).concat( fields );
	}

	private static function addConstructor(
		fields : Array<Field>,
		linkedQueries : Array<String>,
		knownPriorities : Map<String, Expr>,
		fixedPriorityListeners : Map<String, Array<ListenerSpec>>
	) : Void {
		final initialization : Array<Expr> = [for ( priority => listeners in fixedPriorityListeners ) {
			final body : Array<Expr> = [for ( listener in listeners ) listener.callDuringUpdate( macro world )];
			body.unshift( macro __dt__ = dt );
			macro __addListenersWithPriority__( ${knownPriorities[priority]}, function ( dt : Float ) $b{body} );
		}];
		for ( query in linkedQueries ) {
			initialization.push( macro __registerQueryAccess__( world.getOrCreateQuery( $i{query} ) ) );
		}
		initialization.push( macro if ( parent != null ) {
			for ( child in __children__ ) {
				parent.add( child );
			}
		} );

		switch ( fields.find( field -> field.name == "new" || field.name == "_new" ) ) {
			case null:
				fields.push(( macro class Constructor {
					public inline function new( world : echoes.World, ?priority : Int ) {
						super( world, priority );
						$b{initialization}
					}
				} ).fields[0] );
			case _.getFunctionBody() => body if ( body != null ):
				if ( !body.exists( expression -> expression.expr.match(
					ECall( _.expr => EConst( CIdent( "super" ) ), _ ) ) ) ) {
					body.push( macro super( world ) );
				}
				for ( expression in initialization ) {
					body.push( expression );
				}
			default:
		}
	}

	private static function addListenerBridges(
		fields : Array<Field>,
		linkedQueries : Array<String>,
		updateListeners : Array<ListenerSpec>,
		addListeners : Array<ListenerSpec>,
		removeListeners : Array<ListenerSpec>
	) : Void {
		for ( listener in addListeners.concat( removeListeners ) ) {
			if ( listener.components.length > 0 ) {
				if ( !fields.exists( field -> field.name == listener.wrapperName ) ) {
					fields.push( listener.wrapperFunction );
				}
				if ( !linkedQueries.contains( listener.queryName ) ) {
					linkedQueries.push( listener.queryName );
				}
			}
		}

		for ( listener in updateListeners ) {
			if ( listener.components.length > 0 && !linkedQueries.contains( listener.queryName ) ) {
				linkedQueries.push( listener.queryName );
			}
		}
	}

	private static function addOptionalFields( fields : Array<Field>, nameWithParams : String ) : Void {
		fields.pushFields( macro class OptionalFields {
			public override function toString() : String {
				return $v{nameWithParams};
			}
		} );
	}

	private static function lifecycleFields(
		parentTypes : Array<ClassType>,
		linkedQueries : Array<String>,
		updateListeners : Array<ListenerSpec>,
		addListeners : Array<ListenerSpec>,
		removeListeners : Array<ListenerSpec>
	) : Array<Field> {
		return ( macro class RequiredFields {
			private override function __activate__() : Void {
				if ( !active ) {
					$b{[for ( query in linkedQueries ) macro world.getOrCreateQuery( $i{query} ).activate()]}
					$b{addListeners.map( listener -> macro cast(
						( cast ${listener.query} ).onAdded,
						echoes.utils.Signal<Dynamic>
					).push( ${listener.wrapper} ) )}
					$b{removeListeners.map( listener -> macro cast(
						( cast ${listener.query} ).onRemoved,
						echoes.utils.Signal<Dynamic>
					).push( ${listener.wrapper} ) )}
					super.__activate__();
					$b{addListeners.map( listener -> listener.callDuringUpdate( macro world ) )}
				}
			}

			private override function __deactivate__() : Void {
				if ( active ) {
					$b{[for ( query in linkedQueries ) macro world.getOrCreateQuery( $i{query} ).deactivate()]}
					$b{addListeners.map( listener -> macro cast(
						( cast ${listener.query} ).onAdded,
						echoes.utils.Signal<Dynamic>
					).remove( ${listener.wrapper} ) )}
					$b{removeListeners.map( listener -> macro cast(
						( cast ${listener.query} ).onRemoved,
						echoes.utils.Signal<Dynamic>
					).remove( ${listener.wrapper} ) )}
					super.__deactivate__();
				}
			}

			private override function __update__( dt : Float ) : Void {
				#if echoes_profiling
				final __timestamp__ = Date.now().getTime();
				#end

				${parentTypes.length <= 2 ? macro __dt__ = dt : macro super.__update__( dt )}

				while ( deferredQueue.length > 0 ) {
					final cb = deferredQueue.pop();
					if ( cb == null ) {
						continue;
					}
					cb();
				}

				$b{[for ( listener in updateListeners ) if ( listener.priority == null )
					listener.callDuringUpdate( macro world )]}

				#if echoes_profiling
				this.__updateTime__ = Std.int( Date.now().getTime() - __timestamp__ );
				#end
			}
		} ).fields;
	}
}
#end
