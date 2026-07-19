package echoes.macro.internal.query;

#if macro
import echoes.macro.MacroTools;
import haxe.crypto.Md5;
import haxe.macro.Context;
import haxe.macro.Expr.ComplexType;

/** Produces stable, target-safe names for generated query classes. */
class QueryNaming {

	public static function getName(
		components : Array<ComplexType>,
		?excludedComponents : Array<ComplexType>
	) : String {
		final qualifiedExcludes = excludedComponents == null ? "" : joinNames( excludedComponents );
		final hash : String = "_" + Md5.encode( joinNames( components ) + qualifiedExcludes ).substr( 0, 5 );

		final readableExcludes = excludedComponents == null ? "" : joinNames( excludedComponents, false );
		final name : String = "QueryOf_" + joinNames( components, false ) + "_exclude_" + readableExcludes + hash;

		if ( Context.defined( "cpp" ) ) {
			var maxLength : Null<Int> = Context.defined( "echoes_max_name_length" )
				? Std.parseInt( Context.definedValue( "echoes_max_name_length" ) )
				: 80;
			if ( maxLength == null ) {
				maxLength = 80;
			}
			if ( name.length > maxLength ) {
				return name.substr( 0, maxLength - hash.length ) + hash;
			}
		}

		return name;
	}

	private static function joinNames( types : Array<ComplexType>, ?qualified : Bool = true ) : String {
		final names : Array<String> = [for ( type in types ) MacroTools.toIdentifier( type, qualified )];
		names.sort( MacroTools.compareStrings );
		return names.join( "_" );
	}
}
#end
