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
					macro ${ComponentStorageBuilder.getComponentStorage( world, component )}.getAt(
						entity,
						archetype.tableId,
						archetypeEntity.tableRow
					);
			}
		}];

		final queryName = QueryNaming.getName( requiredComponents, excludedComponents );
		return macro {
			final query = $world.getOrCreateQuery( $i{queryName} );
			final processed : Array<Bool> = [];
			for ( archetype in query.archetypes ) {
				var i : Int = 0;
				while ( i < archetype.entities.length ) {
					final archetypeEntity = archetype.entities[i];
					final entity : echoes.Entity = archetypeEntity.entity;
					if ( processed[entity.id] == true || !entity.isActive( $world ) ) {
						i++;
						continue;
					}
					processed[entity.id] = true;
					$listener( $a{callArguments} );
					if ( i < archetype.entities.length && archetype.entities[i] == archetypeEntity ) i++;
				}
			}
		};
	}
}
#end
