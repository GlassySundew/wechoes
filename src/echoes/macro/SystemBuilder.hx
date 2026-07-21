package echoes.macro;

#if macro
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;
import echoes.World;
import echoes.macro.internal.system.ListenerSpec;
import echoes.macro.internal.system.SystemEmitter;
import echoes.macro.internal.system.SystemMetadata;

using echoes.macro.MacroTools;
using echoes.macro.QueryBuilder;
using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;
using Lambda;
using StringTools;

class SystemBuilder {

	private static final genericSystemCache : Map<String, ComplexType> = new Map();

	private static inline function notNull<T>( e : Null<T> ) : Bool {
		return e != null;
	}

	public static function build() : Array<Field> {
		return buildInternal( false );
	}

	private static function buildInternal( isGenericBuild : Bool ) : Array<Field> {
		var fields : Array<Field> = Context.getBuildFields();

		// Information gathering
		// =====================

		var substitutions : TypeSubstitutions = null;
		var nameWithParams : String;
		final classType : ClassType = switch ( Context.getLocalType() ) {
			case TInst( _.get() => inst, types ):
				nameWithParams = inst.name;

				if ( !isGenericBuild && inst.params.length > 0 ) {
					// Apply some default substitutions to improve completion.
					substitutions = new TypeSubstitutions( inst );
				} else if ( types.length > 0 ) {
					substitutions = new TypeSubstitutions( inst, types );
					nameWithParams += "<" + [for ( type in types )
						new Printer().printComplexType( type.toComplexType() )].join( ", " ) + ">";
				}

				inst;
			default:
				Context.warning( "SystemBuilder only acts on classes.", Context.currentPos() );
				return fields;
		};

		if ( Context.defined( "display" ) ) {
			return SystemMetadata.addDisplayReferences( fields, classType.meta.get() );
		}

		/**
		 * `classType`, plus all superclasses in order, including `System`.
		 */
		final parentTypes : Array<ClassType> = [classType];
		{
			var parentType : ClassType = classType;
			while ( parentType.superClass != null ) {
				parentType = parentType.superClass.t.get();
				parentTypes.push( parentType );
			}
			if ( parentTypes.length < 2 || parentType.name != "System"
				|| parentType.pack.length != 1 || parentType.pack[0] != "echoes" ) {
				Context.fatalError( '${classType.name} must extend echoes.System.', Context.currentPos() );
			}
		}

		// Non-generic builds may be skipped.
		if ( !isGenericBuild ) {
			for ( type in parentTypes ) {
				if ( type.meta.has( ":skipBuildMacro" ) ) {
					return fields;
				}
			}
		}

		// Type substitutions
		// ==================

		if ( substitutions != null ) {
			if ( !classType.meta.has( ":genericBuild" ) ) {
				Context.fatalError( "Systems with type parameters must be tagged `@:genericBuild(echoes.macro.SystemBuilder.genericBuild())`.", Context.currentPos() );
			}

			fields = fields.map( substitutions.substituteField );
		} else {
			if ( classType.meta.has( ":genericBuild" ) ) {
				Context.fatalError( "@:genericBuild requires type parameters.", Context.currentPos() );
			}
		}

		// Linked queries
		// ============

		/**
		 * Names of queries that should activate and deactivate with the system.
		 */
		final linkedQueries : Array<String> = [];

		// Variable initializers can't actually call `getLinkedQuery()`, so locate
		// and replace such calls.
		for ( field in fields ) {
			final expr : Expr = switch ( field.kind ) {
				case FVar( _, expr ), FProp( _, _, _, expr ) if ( expr != null ):
					expr;
				default:
					continue;
			};

			final params : Array<Expr> = switch ( expr.expr ) {
				case ECall(
					_.expr => EConst( CIdent( "getLinkedQuery" ) )
						| EField( _, "getLinkedQuery" ),
					params
				):
					params;
				default:
					continue;
			};

			// Get the inactive query for now.
			expr.expr = World.getInactiveQuery( macro world, params ).expr;

			final queryName : String = switch ( expr.expr ) {
				case EField( _.expr => EConst( CIdent( name ) ), "instance" ):
					name;
				default:
					throw "World.getInactiveQuery() returned an unexpected format. Please report this change.";
			};

			// Save the query to link later.
			if ( !linkedQueries.contains( queryName ) ) {
				linkedQueries.push( queryName );
			}
		}

		// Listener function priorities
		// ============================

		final knownPriorities : Map<String, Expr> = new Map();

		final updateListeners : Array<ListenerSpec> = fields.map(
			ListenerSpec.fromField.bind(
				_,
				SystemMetadata.UPDATED,
				knownPriorities
			)
		).filter( notNull );
		final addListeners : Array<ListenerSpec> = fields.map(
			ListenerSpec.fromField.bind(
				_,
				SystemMetadata.ADDED,
				knownPriorities
			)
		).filter( notNull );
		final removeListeners : Array<ListenerSpec> = fields.map(
			ListenerSpec.fromField.bind(
				_,
				SystemMetadata.REMOVED,
				knownPriorities
			)
		).filter( notNull );
		for ( listener in addListeners.concat( removeListeners ) ) {
			if ( listener.wrapperFunction == null ) {
				Context.error( "An @:add or @:remove listener must take at least one component. (Optional arguments don't count.)", listener.pos );
			}
		}

		/**
		 * Update listeners that have `@:priority` tags. Each group of these
		 * will be used to create a `ChildSystem`.
		 */
		final fixedPriorityUpdateListeners : Map<String, Array<ListenerSpec>> = new Map();
		for ( listener in updateListeners ) {
			if ( listener.priority != null ) {
				if ( !fixedPriorityUpdateListeners.exists( listener.priority ) ) {
					fixedPriorityUpdateListeners[listener.priority] = [];
				}

				fixedPriorityUpdateListeners[listener.priority].push( listener );
			}
		}

		final defaultPriority : Null<String> = SystemMetadata.getPriority( classType.meta.get(), knownPriorities );
		if ( defaultPriority != null ) {
			fields.pushFields( macro class DefaultPriority {
				private override function __getDefaultPriority__() : Int {
					return ${knownPriorities.get( defaultPriority )};
				}
			} );
		}

		return SystemEmitter.emit(
			fields,
			nameWithParams,
			parentTypes,
			linkedQueries,
			knownPriorities,
			fixedPriorityUpdateListeners,
			updateListeners,
			addListeners,
			removeListeners
		);
	}

	public static function genericBuild() : ComplexType {
		var classType : ClassType;
		var name : String;
		switch ( Context.getLocalType() ) {
			case TInst( _.get() => inst, args ):
				classType = inst;
				name = inst.name;

				TypeSubstitutions.applyDefaultTypeParams( classType, args );
				for ( i => arg in args ) {
					name += "_" + arg.toComplexType().toIdentifier( false );
				}
			default:
				return Context.fatalError( "SystemBuilder only acts on classes.", Context.currentPos() );
		}

		final qualifiedName : String = classType.pack.concat( [name] ).join( "." );
		if ( genericSystemCache.exists( qualifiedName ) ) {
			return genericSystemCache[qualifiedName];
		}

		if ( classType.superClass == null ) {
			return Context.fatalError( classType.name + " must extend System.", Context.currentPos() );
		}

		final superClass : ClassType = classType.superClass.t.get();
		final superClassModule : String = superClass.module.split( "." ).pop();
		final importsAndUsings : { imports : Array<ImportExpr>, usings : Array<TypePath> } = TypeSubstitutions.getCachedImports( classType );

		Context.defineModule( qualifiedName, [{
			pack : classType.pack,
			fields : buildInternal( true ),
			kind : TDClass( {
				pack : superClass.pack,
				name : superClassModule,
				sub : superClassModule != superClass.name ? superClass.name : null
			}, null, null, null, null ),
			pos : Context.currentPos(),
			name : name,
			meta : [{
				// In case the `@:autoBuild` macro runs on the output.
				name : ":skipBuildMacro",
				pos : Context.currentPos()
			}]
		}], importsAndUsings.imports, importsAndUsings.usings );

		final type : ComplexType = TPath( {
			pack : classType.pack,
			name : name
		} );
		genericSystemCache[qualifiedName] = type;
		return type;
	}
}

#end
