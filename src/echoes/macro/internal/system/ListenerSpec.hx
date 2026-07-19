package echoes.macro.internal.system;

#if macro
import echoes.World;
import echoes.macro.EntityTools;
import echoes.macro.MacroTools;
import echoes.macro.QueryBuilder;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Printer;

using echoes.macro.MacroTools;
using Lambda;

/**
 * An analyzed system listener plus the expressions needed to invoke it.
 * Keeping this outside `SystemBuilder` makes listener parsing independently
 * readable while preserving the generated code.
 */
class ListenerSpec {

	public final name : String;
	public final args : Array<FunctionArg>;
	public final pos : Position;
	public final priority : Null<String>;
	public final excludeComponents : Array<ComplexType>;

	private var componentCache : Null<Array<ComplexType>>;
	private var optionalComponentCache : Null<Array<ComplexType>>;
	private var queryNameCache : Null<String>;
	private var wrapperFunctionCache : Null<Field>;

	private function new(
		name : String,
		args : Array<FunctionArg>,
		pos : Position,
		priority : Null<String>,
		excludeComponents : Array<ComplexType>
	) {
		this.name = name;
		this.args = args;
		this.pos = pos;
		this.priority = priority;
		this.excludeComponents = excludeComponents;
	}

	public static function fromField(
		field : Field,
		listenerType : String,
		knownPriorities : Map<String, Expr>
	) : Null<ListenerSpec> {
		return switch ( field.kind ) {
			case FFun( func ) if ( SystemMetadata.find( field.meta, listenerType ) != null ):
				validateDistinctArgumentTypes( func.args, field.pos );

				final excluded : Array<ComplexType> = [];
				final excludeMeta = SystemMetadata.find( field.meta, SystemMetadata.EXCLUDE );
				if ( excludeMeta != null ) {
					for ( parameter in excludeMeta.params ) {
						excluded.push( MacroTools.parseClassExpr( parameter ) );
					}
				}

				new ListenerSpec(
					field.name,
					func.args,
					field.pos,
					SystemMetadata.getPriority( field.meta, knownPriorities ),
					excluded
				);
			default:
				null;
		};
	}

	private static function validateDistinctArgumentTypes( args : Array<FunctionArg>, pos : Position ) : Void {
		final argumentTypes : Array<String> = [
			for ( argument in args )
				if ( argument.type != null )
					new Printer().printComplexType( argument.type.followComplexType() )
				else
					Context.error( '${argument.name} requires a type.', pos )
		];

		for ( i in 0...argumentTypes.length ) {
			for ( j in 0...i ) {
				if ( argumentTypes[i] == argumentTypes[j] ) {
					Context.error( '${args[j].name} and ${args[i].name} both have type ${argumentTypes[i]}.', pos );
				}
			}
		}
	}

	public var components( get, never ) : Array<ComplexType>;
	private function get_components() : Array<ComplexType> {
		if ( componentCache == null ) {
			componentCache = [];
			for ( argument in args ) {
				switch ( argument.type.followComplexType() ) {
					case macro : StdTypes.Float, macro : echoes.Entity:
					case type if ( !argument.opt && argument.value == null ):
						componentCache.push( type );
					default:
				}
			}

			if ( componentCache.length > 0 ) {
				QueryBuilder.getComponentOrder( componentCache, excludeComponents );
			}
		}
		return componentCache;
	}

	public var optionalComponents( get, never ) : Array<ComplexType>;
	private function get_optionalComponents() : Array<ComplexType> {
		if ( optionalComponentCache == null ) {
			optionalComponentCache = [];
			for ( argument in args ) {
				switch ( argument.type.followComplexType() ) {
					case macro : StdTypes.Float, macro : echoes.Entity:
					case type if ( argument.opt || argument.value != null ):
						optionalComponentCache.push( type );
					default:
				}
			}
		}
		return optionalComponentCache;
	}

	public var query( get, never ) : Expr;
	private inline function get_query() : Expr {
		return macro world.getOrCreateQuery( $i{queryName} );
	}

	public var queryName( get, never ) : String;
	private function get_queryName() : String {
		if ( queryNameCache == null ) {
			queryNameCache = QueryBuilder.getQueryName( components, excludeComponents );
		}
		return queryNameCache;
	}

	public var wrapper( get, never ) : Expr;
	private inline function get_wrapper() : Expr {
		return macro $i{wrapperName};
	}

	public var wrapperName( get, never ) : String;
	private inline function get_wrapperName() : String {
		return '__${name}_bridge__';
	}

	public var wrapperFunction( get, never ) : Null<Field>;
	private function get_wrapperFunction() : Null<Field> {
		if ( wrapperFunctionCache == null ) {
			if ( components.length == 0 ) {
				return null;
			}

			final wrapperArguments : Array<FunctionArg> = [{
				name : "entity",
				type : macro : echoes.Entity
			}].concat( QueryBuilder.getComponentOrder( components, excludeComponents ).map( type -> {
				name : args.find( argument -> argument.type.followName() == type.followName() ).name,
				type : type
			} ) );

			for ( argument in wrapperArguments ) {
				if ( argument.name == null ) {
					Context.error( 'Could not locate an argument of type ${argument.type.followName()}. Please report this error, and include information about the type.', pos );
				}
			}

			wrapperFunctionCache = {
				name : wrapperName,
				kind : FFun( {
					args : wrapperArguments,
					ret : macro : Void,
					expr : call( macro entity, macro __dt__, macro world )
				} ),
				pos : pos
			};
		}
		return wrapperFunctionCache;
	}

	private function call( getEntity : Expr, getDeltaTime : Expr, worldExpr : ExprOf<World> ) : Expr {
		final callArguments : Array<Expr> = [for ( argument in args ) {
			switch ( argument.type.followComplexType() ) {
				case macro : StdTypes.Float:
					getDeltaTime;
				case macro : echoes.Entity:
					getEntity;
				default:
					if ( argument.opt || argument.value != null ) {
						EntityTools.get( getEntity, worldExpr, argument.type.followComplexType() );
					} else {
						macro $i{argument.name};
					}
			}
		}];

		return macro @:pos( pos ) $i{name}( $a{callArguments} );
	}

	public function callDuringUpdate( world : ExprOf<World> ) : Expr {
		if ( components.length > 0 ) {
			return QueryBuilder.forEachEntityInQuery(
				macro @:pos( pos ) $i{name},
				args,
				excludeComponents,
				macro __dt__,
				macro world
			);
		}

		if ( optionalComponents.length > 0 ) {
			return macro for ( entity in world.activeEntities )
				${call( macro entity, macro __dt__, macro world )};
		}

		for ( argument in args ) {
			if ( argument.type.followComplexType().match( macro : echoes.Entity ) ) {
				return macro for ( entity in world.activeEntities )
					${call( macro entity, macro __dt__, macro world )};
			}
		}

		return call(
			macro throw "Unable to select an entity because this function has no required components",
			macro __dt__,
			macro world
		);
	}
}
#end
