package echoes.macro.internal.generic;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr.ImportExpr;
import haxe.macro.Expr.TypePath;
import haxe.macro.Type.ClassType;

using echoes.macro.MacroTools;

/** Retains local imports/usings that Haxe hides during a generic build. */
class GenericImportCache {

	private static final cache : Map<String, GenericImports> = new Map();

	public static function get( classType : ClassType ) : Null<GenericImports> {
		return cache[key( classType )];
	}

	public static function capture( classType : ClassType ) : Void {
		final classKey = key( classType );
		if ( cache.exists( classKey ) || Context.getLocalModule() != classType.module ) {
			return;
		}

		cache[classKey] = {
			imports : Context.getLocalImports(),
			usings : [for ( reference in Context.getLocalUsing() ) if ( reference != null ) {
				final usingType : ClassType = reference.get();
				final parts : Array<String> = usingType.module.split( "." );
				if ( parts[parts.length - 1] != usingType.name ) {
					parts.push( usingType.name );
				}
				parts.makeTypePath();
			}]
		};
	}

	private static inline function key( classType : ClassType ) : String {
		return classType.pack.concat( [classType.name] ).join( "." );
	}
}

typedef GenericImports = {
	imports : Array<ImportExpr>,
	usings : Array<TypePath>
};
#end
