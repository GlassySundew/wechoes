package echoes.macro;

#if macro

import haxe.macro.Expr;
import haxe.macro.Type;

import echoes.macro.ComponentStorageBuilder;
import echoes.macro.MacroTools;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
// using echoes.macro.ComponentStorageBuilder;
// using echoes.macro.MacroTools;
// using haxe.macro.ComplexTypeTools;
// using haxe.macro.Context;

/**
 * Entity manipulation functions. Mostly equivalent to the macros found in
 * `Entity`, except these are designed to be called by macros. The biggest
 * difference is that these take `ComplexType` instead of `ExprOf<Class<Any>>`,
 * because that's more convenient for macros.
 */
class EntityTools {
	/**
	 * Adds one or more components to the entity, dispatching an `@:add` event
	 * for each one. If the entity already has a component of the same type, the
	 * old component will be replaced.
	 * 
	 * If a component is replaced and its type is tagged `@:echoes_replace`,
	 * this will dispatch a `@:remove` event before dispatching `@:add`.
	 */
	public static function add(self:Expr, world:ExprOf<World>, components:Array<Expr>):ExprOf<echoes.Entity> {
		return macro @:pos( Context.currentPos() ) {
			final __entity__:echoes.Entity = $self;
			
			$b{ [for(component in components) {
				final type:Type = MacroTools.parseComponentType(component);
				
				final operation:String = switch(type) {
					case TEnum(_.get().meta => m, _),
						TInst(_.get().meta => m, _),
						TType(_.get().meta => m, _),
						TAbstract(_.get().meta => m, _)
						if(m.has(":echoes_replace")):
						"replace";
					default:
						"add";
				};
				
				final storage:Expr = ComponentStorageBuilder.getComponentStorage(world, Context.toComplexType(type));
				macro $storage.$operation(__entity__, $component, world);
			}] }
			
			__entity__;
		};
	}
	
	/**
	 * Adds one or more components to the entity, but only if those components
	 * don't already exist. If the entity already has a component of the same
	 * type, the old component will remain.
	 * 
	 * Any side-effects of creating a component will only occur if that
	 * component is added. For instance, `entity.addIfMissing(array.pop())` will
	 * only pop an item from `array` if that component was missing.
	 * @param components Components of `Any` type.
	 * @return The entity.
	 */
	public static function addIfMissing(self:Expr, world : ExprOf<World>, components:Array<Expr>):ExprOf<echoes.Entity> {
		return macro /* @:pos(Context.currentPos()) */ {
			final __entity__:echoes.Entity = $self;
			
			$b{ [for(component in components) {
				final type:Type = MacroTools.parseComponentType(component);
				
				final storage:Expr = ComponentStorageBuilder.getComponentStorage(world, Context.toComplexType(type));
				macro if(!$storage.exists(__entity__)) $storage.add(__entity__, $component, world);
			}] }
			
			__entity__;
		};
	}
	
	/**
	 * Removes one or more components from the entity.
	 * @param types The type(s) of the components to remove. _Not_ the
	 * components themselves!
	 * @return The entity.
	 */
	public static function remove(self:Expr, world : ExprOf<World>, types:Array<ComplexType>):ExprOf<echoes.Entity> {
		return macro @:pos(Context.currentPos()) {
			final __entity__:echoes.Entity = $self;
			
			$b{ [for(type in types) {
				final storage:Expr = ComponentStorageBuilder.getComponentStorage(world, type);
				macro $storage.remove(__entity__, world);
			}] }
			
			__entity__;
		};
	}
	
	/**
	 * Gets this entity's component of the given type, if this entity has a
	 * component of the given type.
	 * @param type The type of the component to get.
	 * @return The component, or `null` if the entity doesn't have it.
	 */
	public static function get<T>(self:Expr, world : ExprOf<World>, complexType:ComplexType):ExprOf<T> {
		final storage:Expr = ComponentStorageBuilder.getComponentStorage(world, complexType);
		return macro @:pos(Context.currentPos()) $storage.get($self);
	}
	
	/**
	 * Returns whether the entity has a component of the given type.
	 * @param type The type to check for.
	 */
	public static function exists(self:Expr, world:ExprOf<World>, complexType:ComplexType):ExprOf<Bool> {
		final storage:Expr = ComponentStorageBuilder.getComponentStorage(world, complexType);
		return macro @:pos(Context.currentPos()) $storage.exists($self);
	}
}

#end
