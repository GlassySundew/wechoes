package echoes.macro.internal.query;

#if macro
import echoes.World;
import echoes.macro.ComponentStorageBuilder;
import echoes.macro.MacroTools;
import haxe.macro.Expr;

/** Emits mutation-safe iteration for system listener functions. */
class QueryIterationEmitter {

	public static function emit(
		listener : Expr,
		arguments : Array<FunctionArg>,
		excludedComponents : Array<ComplexType>,
		deltaTime : Expr,
		world : ExprOf<World>
	) : Expr {
		final requiredComponents : Array<ComplexType> = [];
		final callArguments : Array<Expr> = [for ( argument in arguments ) {
			switch ( MacroTools.followComplexType( argument.type ) ) {
				case macro : StdTypes.Float:
					deltaTime;
				case macro : echoes.Entity:
					macro entity;
				case component:
					if ( !argument.opt && argument.value == null ) {
						requiredComponents.push( component );
					}
					macro ${ComponentStorageBuilder.getComponentStorage( world, component )}.get( entity );
			}
		}];

		final queryName = QueryNaming.getName( requiredComponents, excludedComponents );
		return macro {
			var i : Int = 0;
			final entities : haxe.ds.ReadOnlyArray<echoes.Entity> = $world.getOrCreateQuery( $i{queryName} ).entities;
			while ( i < entities.length ) {
				final entity : echoes.Entity = entities[i];
				$listener( $a{callArguments} );
				if ( entity == entities[i] || entities.contains( entity ) ) {
					i++;
				}
			}
		};
	}
}
#end
