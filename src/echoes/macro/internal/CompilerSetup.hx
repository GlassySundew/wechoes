package echoes.macro.internal;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;

/** Initialization hooks used from Echoes HXML configurations. */
class CompilerSetup {

	public static function registerMetadataDescriptions() : Void {
		#if( haxe_ver >= 4.3 )
		final entityModule = Context.resolvePath( "echoes/Entity.hx" );
		final metadataFile = Path.normalize( Path.join( [Path.directory( entityModule ), "../../meta.json"] ) );
		Compiler.registerMetadataDescriptionFile( metadataFile, "echoes" );
		#end
	}
}
#end
