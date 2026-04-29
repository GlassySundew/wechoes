package echoes.macro;

#if macro
import haxe.macro.CompilationServer;
import haxe.macro.Expr;
import haxe.macro.Printer;
import haxe.macro.Type;
import haxe.PosInfos;

using echoes.macro.MacroTools;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;
#end

var storageIdInc = 0;

final storageCache : Map<String, Int> = new Map();

function reserveStorageId( type : String ) : Int {

	if ( storageCache[type] == null )
		storageCache[type] = storageIdInc++;

	return storageCache[type];
}

#if macro
class ComponentStorageBuilder {

	public static inline final PREFIX : String = "ComponentStorage_";

	private static var registered : Bool = false;

	public static #if !debug inline #end function getComponentStorage(
		world : ExprOf<World>,
		componentComplexType : ComplexType
	) : Expr {
		if ( Context.defined( "display" ) || Sys.args().indexOf( "--no-output" ) >= 0 ) {
			return
				macro new echoes.ComponentStorage<$componentComplexType>(
					world,
					"For code completion only. If you see this at runtime, it's an error.",
					0
				);
		}

		var storageId = getComponentStorageId( componentComplexType );
		var componentComplexType = componentComplexType.followComplexType();
		final componentTypeName : String = new Printer().printComplexType( componentComplexType );

		var createStorage : Expr = macro new echoes.ComponentStorage<$componentComplexType>(
			world,
			$v{componentTypeName},
			$v{storageId}
		);

		final componentBaseType : BaseType = componentComplexType.toType().toBaseType();
		final meta : MetaAccess = componentBaseType != null ? componentBaseType.meta : null;
		if ( meta != null ) {
			switch ( meta.extract( ":echoes_storage" ) ) {
				case null, []:
				case x if ( componentBaseType.params.length > 0 ):
					Context.error( "@:echoes_storage doesn't work with type params, for type " + new Printer().printComplexType( componentComplexType ), Context.currentPos() );
				case [_.params => [customSingleton]]:
					createStorage = customSingleton;
				default:
			}
		}

		final result = macro @:pos( Context.currentPos() ) {
			var inst = $world.getStorage( $v{storageId} );

			if ( inst == null ) {
				inst = ${createStorage};
				$world.addStorage( $v{storageId}, inst );
			}

			inst;
		};

		return result;
	}

	public static function getComponentStorageId( componentComplexType : ComplexType ) : Int {
		componentComplexType = componentComplexType.followComplexType();

		final error : String = componentComplexType.getReservedComponentMessage();
		if ( error != null ) {
			Context.error( error, Context.currentPos() );
		}

		final storageTypeName : String = PREFIX + componentComplexType.toIdentifier();
		if ( storageCache.exists( storageTypeName ) ) {
			return storageCache[storageTypeName];
		}

		return storageCache[storageTypeName] = storageIdInc++;

		// final componentTypeName:String = new Printer().printComplexType(componentComplexType);
		// final storageTypePath:TypePath = { pack: [], name: storageTypeName };
		// var getInstance:Expr = macro new echoes.ComponentStorage<$componentComplexType>($v{ componentTypeName });

		// //If a custom singleton is defined, use that instead.
		// final componentBaseType:BaseType = componentComplexType.toType().toBaseType();
		// final meta:MetaAccess = componentBaseType != null ? componentBaseType.meta : null;
		// if(meta != null) {
		// 	switch(meta.extract(":echoes_storage")) {
		// 		case null, []:
		// 		case x if(componentBaseType.params.length > 0):
		// 			Context.error("@:echoes_storage doesn't work with type params, for type " + new Printer().printComplexType(componentComplexType), Context.currentPos());
		// 		case [_.params => [customSingleton]]:
		// 			getInstance = customSingleton;
		// 		default:
		// 	}
		// }

		// final def:TypeDefinition = macro class $storageTypeName {
		// 	// public static final instance:echoes.ComponentStorage<$componentComplexType> = $getInstance;
		// };

		// storageCache.set(storageTypeName, def);
		// if(!registered) {
		// 	registered = true;
		// 	Context.onTypeNotFound(storageCache.get);
		// }

		// Report.componentNames.push(componentTypeName);
		// Report.registerCallback();

		// return storageTypeName;
	}

	public static function invalidate() : Void {
		if ( !Context.defined( "display" ) && Sys.args().indexOf( "--no-output" ) < 0 ) {
			final filePath : String = ( ( ?infos : PosInfos ) -> infos.fileName )();
			CompilationServer.invalidateFiles( [filePath] );
		}
	}
}
#end
