package echoes.macro;

#if macro
import echoes.World;
import haxe.macro.Expr;
import haxe.macro.Type;

/** Compatibility facade for the former View macro API. */
@:deprecated( "Use echoes.macro.QueryBuilder instead." )
class ViewBuilder {

	public static inline function isView( name : String ) : Bool {
		return QueryBuilder.isQuery( name );
	}

	public static function getComponentOrder(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : Array<ComplexType> {
		return QueryBuilder.getComponentOrder( components, excludedComponents );
	}

	public static function getViewName(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : String {
		return QueryBuilder.getQueryName( components, excludedComponents );
	}

	public static function build() : Type {
		return QueryBuilder.build();
	}

	public static function createViewType(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : Type {
		return QueryBuilder.createQueryType( components, excludedComponents );
	}

	public static function forEachEntityInView(
		listener : Expr,
		arguments : Array<FunctionArg>,
		excludedComponents : Array<ComplexType>,
		deltaTime : Expr,
		world : ExprOf<World>
	) : Expr {
		return QueryBuilder.forEachEntityInQuery(
			listener,
			arguments,
			excludedComponents,
			deltaTime,
			world
		);
	}
}
#end
