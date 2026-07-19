package echoes.macro.internal.system;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Printer;

using StringTools;

/** Centralizes the permissive metadata syntax accepted by system macros. */
class SystemMetadata {

	public static inline final ADDED : String = "added";
	public static inline final REMOVED : String = "removed";
	public static inline final UPDATED : String = "updated";
	public static inline final EXCLUDE : String = "exclude";
	public static inline final PRIORITY : String = "priority";

	/**
	 * Finds the first metadata entry matching `searchTerm`. Leading colons and
	 * the `echoes_` prefix are ignored, and unambiguous prefixes are accepted.
	 */
	public static function find( metadata : Metadata, searchTerm : String ) : Null<MetadataEntry> {
		for ( entry in metadata ) {
			var name : String = entry.name;
			if ( name.startsWith( ":" ) ) {
				name = name.substr( 1 );
			}
			if ( name.startsWith( "echoes_" ) ) {
				name = name.substr( "echoes_".length );
			}

			if ( name.length > 0 && searchTerm.startsWith( name ) ) {
				if ( !entry.name.startsWith( ":" ) ) {
					Context.warning( '@${entry.name} is deprecated; use @:${entry.name} instead.'
						+ ( entry.name == "remove" ? " (@:remove does have a reserved meaning when applied to interfaces, but not here.)" : "" ),
						entry.pos );
				}
				return entry;
			}
		}

		return null;
	}

	/** Registers and returns the printed key for a listener priority. */
	public static function getPriority( metadata : Metadata, knownPriorities : Map<String, Expr> ) : Null<String> {
		final entry : MetadataEntry = find( metadata, PRIORITY );
		switch ( entry ) {
			case null:
			case _.params => [expr]:
				final key : String = new Printer().printExpr( expr );
				if ( !knownPriorities.exists( key ) ) {
					knownPriorities[key] = expr;
				}
				return key;
			default:
		}
		return null;
	}

	private static function addParameterReferences(
		metadata : Metadata,
		searchTerm : String,
		references : Map<String, Expr>
	) : Void {
		final entry : MetadataEntry = find( metadata, searchTerm );
		if ( entry != null ) {
			for ( expr in entry.params ) {
				references[new Printer().printExpr( expr )] = expr;
			}
		}
	}

	/** Keeps metadata expressions visible to Haxe's display/type-completion pass. */
	public static function addDisplayReferences( fields : Array<Field>, metadata : Metadata ) : Array<Field> {
		final referencesByKey : Map<String, Expr> = new Map();
		getPriority( metadata, referencesByKey );
		for ( field in fields ) {
			getPriority( field.meta, referencesByKey );
			addParameterReferences( field.meta, EXCLUDE, referencesByKey );
		}

		if ( referencesByKey.iterator().hasNext() ) {
			final references : Array<Expr> = [for ( expr in referencesByKey ) macro $expr];
			fields.push(( macro class DisplayPriorityReferences {
				@:noCompletion
				private function __echoes_display_meta_references__( ?priority : Int ) : Void {
					$b{references}
				}
			} ).fields[0] );
		}

		return fields;
	}
}
#end
