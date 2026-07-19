package echoes.macro;

#if macro
#if echoes_report
import haxe.macro.Context;
import haxe.macro.Type;
#end

/**
 * Use `-Dechoes_report` to print all generated components and queries, in the
	 * order they were processed. Use `-Dechoes_report=sorted` to sort them.
 * in alphabetical order.
 */
class Report {

	@:allow( echoes.macro.ComponentStorageBuilder )
	private static final componentNames : Array<String> = [];

	@:allow( echoes.macro.QueryBuilder )
	private static final queryNames : Array<String> = [];

	private static var registered = false;

	public static function registerCallback() : Void {
		#if echoes_report
		if ( !registered ) {
			Context.onGenerate( function ( types : Array<Type> ) : Void {
				if ( Context.definedValue( "echoes_report" ) == "sorted" ) {
					componentNames.sort( MacroTools.compareStrings );
					queryNames.sort( MacroTools.compareStrings );
				}

				Sys.println( "ECHOES BUILD REPORT:\n"
					+ '    COMPONENTS [${componentNames.length}]:\n'
					+ "        " + componentNames.join( "\n        " ) + "\n"
					+ '    QUERIES [${queryNames.length}]:\n'
					+ "        " + queryNames.join( "\n        " ) );
			} );
			registered = true;
		}
		#end
	}
}
#end
