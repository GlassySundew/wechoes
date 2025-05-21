package;

import echoes.World;
import Components;
import Components.Color as ColorAlias;

import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.View;
import haxe.PosInfos;
import MethodCounter.assertTimesCalled;
import MethodCounter.IMethodCounter;
import Systems;
import utest.Assert;
import utest.Test;

@:depends(BasicFunctionalityTest)
class EdgeCaseTest extends Test {
	private function teardown():Void {
		// Echoes.reset();
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	private function testAllArgumentsOptional():Void {
		var world = new World();
		world.init();
		
		new OptionalListenerSystem(world).activate();
		world.update();
		assertTimesCalled(0, "OptionalListenerSystem.optionalNameUpdated");
		
		final entity:Entity = new Entity(world);
		entity.add(world, ("name":Name));
		world.update();
		assertTimesCalled(1, "OptionalListenerSystem.optionalNameUpdated");
		
		//When there are multiple entities, the function should be called for
		//each, whether or not they have `Name` components.
		new Entity(world);
		world.update();
		assertTimesCalled(3, "OptionalListenerSystem.optionalNameUpdated");
	}
	
	private function testChildSystems():Void {
		var world = new World();
		
		new NameSubsystem(world).activate();
		
		final entity:Entity = new Entity(world);
		entity.add(world, ("Name":Name));
		assertTimesCalled(0, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSubsystem.nameAdded");
		
		new NameSystem(world).activate();
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		assertTimesCalled(0, "NameSubsystem.nameRemoved");
		
		entity.add(world, ("Other Name":Name));
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(2, "NameSubsystem.nameAdded");
		
		//`nameRemoved` isn't overridden.
		assertTimesCalled(2, "NameSystem.nameRemoved");
		assertTimesCalled(0, "NameSubsystem.nameRemoved");
	}
	
	private function testComponentsExist():Void {
		var world = new World();

		new ComponentsExistSystem(world).activate();
		
		final entity:Entity = new Entity(world);
		entity.add(world, ("name":Name));
		entity.add(world, (0xFFFFFF:Color));
		entity.remove(world, Color);
		entity.remove(world, Name);
		
		entity.add(world, (0xFFFFFF:Color));
		entity.add(world, ("name":Name));
		entity.destroy(world);
		
		//The system's functions contain the important tests; all we need to do
		//here is make sure they were called.
		assertTimesCalled(2, "ComponentsExistSystem.nameAdded");
		assertTimesCalled(2, "ComponentsExistSystem.nameAndColorAdded");
		assertTimesCalled(2, "ComponentsExistSystem.nameOrColorRemoved");
		assertTimesCalled(2, "ComponentsExistSystem.nameRemoved");
	}
	
	@:access(echoes.Entity)
	private function testEntityIDSerialization():Void {
		var world = new World();

		final entity0:Entity = new Entity(world);
		final entity1:Entity = new Entity(world);
		final entity2:Entity = new Entity(world);
		
		entity1.destroy(world);
		Assert.equals(3, world.nextEntityId);
		Assert.same([1], world.entityIdPool);
		Assert.same([0, 2], world.activeEntities);
		
		final savedData:String = world.serialize();
		
		entity0.destroy(world);
		Assert.same([1, 0], world.entityIdPool);
		Assert.same([2], world.activeEntities);
		
		world.unserialize(savedData);
		Assert.equals(3, world.nextEntityId);
		Assert.same([1], world.entityIdPool);
		Assert.same([0, 2], world.activeEntities);
	}
	
	private function testEntityIndices():Void {
		var world = new World();

		inline function assertOrder(order:Array<Entity>, ?posInfos:PosInfos):Void {
			if(Assert.equals(order.length, world.activeEntities.length, posInfos)) {
				for(i in 0...order.length) {
					Assert.equals(order[i], world.activeEntities[i],
						'expected ${ order[i] } at index $i, got ${ world.activeEntities[i] }', posInfos);
				}
			}
		}
		
		final a:Entity = new Entity(world);
		final b:Entity = new Entity(world);
		final c:Entity = new Entity(world);
		final d:Entity = new Entity(world);
		
		#if echoes_stable_order
		
		assertOrder([a, b, c, d]);
		
		//Removing an entity should shift the rest, preserving order.
		a.deactivate();
		assertOrder([b, c, d]);
		
		a.activate();
		assertOrder([b, c, d, a]);
		
		d.deactivate();
		assertOrder([b, c, a]);
		
		b.deactivate();
		assertOrder([c, a]);
		
		a.deactivate();
		assertOrder([c]);
		
		#else
		
		assertOrder([a, b, c, d]);
		
		//Removing an entity should move the final entity, saving time.
		a.deactivate(world);
		assertOrder([d, b, c]);
		
		a.activate(world);
		assertOrder([d, b, c, a]);
		
		c.deactivate(world);
		assertOrder([d, b, a]);
		
		d.deactivate(world);
		assertOrder([a, b]);
		
		b.deactivate(world);
		assertOrder([a]);
		
		#end
	}
	
	private function testImportAs():Void {
		var world = new World();
		
		final entity:Entity = new Entity(world);
		
		Assert.notNull(world.getComponentStorage(ColorAlias));
		
		entity.add(world, (0x112233:ColorAlias));
		Assert.equals(0x112233, entity.get(world, Color));
		
		entity.remove(world, Color);
		Assert.isFalse(entity.exists(world, ColorAlias));
	}
	
	private function testNullComponents():Void {
		var world = new World();
		
		final entity:Entity = new Entity(world);
		
		entity.add(world, "Hello world.");
		Assert.isTrue(entity.exists(world, String));
		Assert.notNull(entity.get(world, String));
		
		entity.add(world, (null:String));
		Assert.isFalse(entity.exists(world, String));
		Assert.isNull(entity.get(world, String));
	}
	
	private function testRedundantOperations():Void {
		var world = new World();

		new AppearanceSystem(world).activate();
		
		final entity:Entity = new Entity(world, false);
		
		//Deactivate an inactive entity.
		Assert.isFalse(entity.isActive(world));
		
		entity.deactivate(world);
		Assert.isFalse(entity.isActive(world));
		
		//Activate the entity twice.
		entity.activate(world);
		entity.activate(world);
		Assert.isTrue(entity.isActive(world));
		Assert.equals(1, world.activeEntities.length);
		
		//Add a `Color` twice in a row.
		entity.add(world, (0x000000:Color));
		Assert.equals(0x000000, entity.get(world, Color));
		
		entity.add(world, (0xFFFFFF:Color));
		Assert.equals(0xFFFFFF, entity.get(world, Color));
		assertTimesCalled(2, "AppearanceSystem.colorAdded");
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		//Remove the `Color` twice in a row.
		entity.remove(world, Color);
		Assert.isNull(entity.get(world, Color));
		
		entity.remove(world, Color);
		Assert.isNull(entity.get(world, Color));
		assertTimesCalled(2, "AppearanceSystem.colorAdded");
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
		
		//Replace a `Name` with itself.
		new NameSystem(world).activate();
		entity.add(world, ("name":Name));
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		entity.add(world, ("name":Name));
		assertTimesCalled(1, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		entity.add(world, ("otherName":Name));
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
	}
	
	private function testRecursiveEvents():Void {
		var world = new World();
		
		final entity:Entity = new Entity(world);
		
		//Activate the system first so that it can process events first.
		new RecursiveEventSystem(world).activate();
		
		//Certain events should stop propagating after `RecursiveEventSystem`
		//gets to them. On some targets, this can happen when the entity ID is 0
		//and reading past the end of an int array returns 0 instead of null.
		world.getView( One, Two).onAdded.push((entity, one, two)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite One component being removed from entity ${ entity.id }.'));
		world.getView( Two, Three).onAdded.push((entity, two, three)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite Two component being removed from entity ${ entity.id }.'));
		world.getView( Brief, One).onAdded.push((entity, brief, one)
			-> Assert.fail('ComponentStorage.add() didn\'t stop iterating despite Brief component being removed from entity ${ entity.id }.'));
		world.getView( Brief).onAdded.push((entity, brief)
			-> Assert.fail('ViewBuilder.dispatchAddedCallback() didn\'t stop iterating despite Brief component being removed from entity ${ entity.id }.'));
		
		//However, `RecursiveEventSystem` shouldn't be able to interrupt
		//`onRemoved` events.
		var permanentRemoveFlags:Int = 0;
		world.getView(Permanent).onRemoved.push((entity, permanent)
			-> permanentRemoveFlags |= 1);
		world.getView(Permanent, One).onRemoved.push((entity, permanent, one)
			-> permanentRemoveFlags |= 2);
		
		//Test components that add/remove other components.
		entity.add(world, (1:One));
		entity.add(world, (2:Two));
		Assert.isFalse(entity.exists(world, One));
		Assert.isTrue(entity.exists(world, Two));
		
		entity.add(world, (3:Three));
		Assert.isTrue(entity.exists(world, One));
		Assert.isFalse(entity.exists(world, Two));
		Assert.isTrue(entity.exists(world, Three));
		
		entity.remove(world, Three);
		Assert.isFalse(entity.exists(world, One));
		Assert.isTrue(entity.exists(world, Two));
		Assert.isFalse(entity.exists(world, Three));
		
		entity.remove(world, Two);
		Assert.isTrue(entity.exists(world, One));
		Assert.isFalse(entity.exists(world, Two));
		Assert.isFalse(entity.exists(world, Three));
		
		//Don't remove `One`.
		
		//Test components that prevent themselves from being added/removed.
		entity.add(world, (0:Brief));
		Assert.isFalse(entity.exists(world, Brief));
		
		entity.add(world, (Math.POSITIVE_INFINITY:Permanent));
		Assert.isTrue(entity.exists(world, Permanent));
		
		//`RecursiveEventSystem` will attempt to undo `remove(Permanent)`, which
		//should throw an error. Afterwards, `Permanent` should remain gone, and
		//all listeners should have been called.
		Assert.raises(() -> entity.remove(world, Permanent));
		Assert.isFalse(entity.exists(world, Permanent));
		Assert.equals(1 | 2, permanentRemoveFlags);
		
		//`remove()` should only prevent adding `Permanent` while it's ongoing.
		entity.add(world, (80:Permanent));
		Assert.equals(80.0, entity.get(world, Permanent));
	}
	
	private function testRemoveDuringUpdate():Void {
		var world = new World();

		final system:RemoveStringSystem = new RemoveStringSystem(world);
		system.activate();
		
		final entity0:Entity = new Entity(world);
		final entity1:Entity = new Entity(world);
		final entity2:Entity = new Entity(world);
		
		entity0.add(world, "remove");
		entity1.add(world, "keep");
		Assert.equals(2, world.getView(String).entities.length);
		
		world.update();
		assertTimesCalled(2, "RemoveStringSystem.removeString");
		Assert.equals(1, world.getView(String).entities.length);
		
		entity0.add(world, "remove");
		entity1.add(world, "keep");
		entity2.add(world, "remove");
		MethodCounter.reset();
		world.update();
		assertTimesCalled(3, "RemoveStringSystem.removeString");
		Assert.equals(1, world.getView(String).entities.length);
		
		entity0.add(world, "remove");
		entity1.add(world, "keep");
		entity2.add(world, "remove");
		MethodCounter.reset();
		world.getView(String).iter(system.removeString);
		assertTimesCalled(3, "RemoveStringSystem.removeString");
		Assert.equals(1, world.getView(String).entities.length);
		
		final view:DynamicView = new DynamicView(world, world.getComponentStorage(Bool));
		view.activate();
		var count:Int = 0;
		entity0.add(world, false);
		entity1.add(world, true);
		entity2.add(world, true);
		view.iter((entity, components) -> {
			count++;
			if(components[0] == true) {
				entity.remove(world, Bool);
			}
		});
		Assert.equals(1, view.entities.length);
		Assert.equals(3, count);
	}
	
	private function testSystemLists():Void {
		var world = new World();
		
		final list0:SystemList = new SystemList(world);
		final list1:SystemList = new SystemList(world);
		final system:NameSystem = new NameSystem(world);
		
		list0.add(system);
		Assert.equals(list0, system.parent);
		
		list1.add(system);
		Assert.equals(list1, system.parent);
		Assert.equals(0, list0.length);
		Assert.equals(1, list1.length);
	}
	
	private function testTypeParsing():Void {
		var world = new World();

		final entity:Entity = new Entity(world);
		final infos:PosInfos = ((?infos:PosInfos) -> infos)();
		entity.add(world, infos);
		
		Assert.equals(infos, entity.get(world, PosInfos));
		Assert.equals(infos, entity.get(world, haxe.PosInfos));
		Assert.equals(infos, entity.get(world, infos));
	}
}

typedef One = Int;
typedef Two = Int;
typedef Three = Int;

typedef Brief = Float;
typedef Permanent = Float;

class ComponentsExistSystem extends System implements IMethodCounter {
	
	@:add private function nameAdded(name:Name, entity:Entity):Void {
		Assert.notNull(entity.get(world, Name));
		Assert.equals(name, entity.get(world, Name));
	}
	
	@:add private function nameAndColorAdded(name:Name, color:Color, entity:Entity):Void {
		Assert.notNull(entity.get(world, Name));
		Assert.equals(name, entity.get(world, Name));
		Assert.notNull(entity.get(world, Color));
		Assert.equals(color, entity.get(world, Color));
	}
	
	@:remove private function nameRemoved(name:Name, entity:Entity):Void {
		Assert.isNull(entity.get(world, Name));
		Assert.notNull(name);
	}
	
	@:remove private function nameOrColorRemoved(name:Name, color:Color, entity:Entity):Void {
		Assert.isFalse(entity.exists(world, Name) && entity.exists(world, Color));
		Assert.isTrue(entity.exists(world, Name) || entity.exists(world, Color));
		Assert.notNull(name);
		Assert.notNull(color);
	}
}

class NameSubsystem extends NameSystem {
	private override function nameAdded(name:Name):Void {}
}

class OptionalListenerSystem extends System implements IMethodCounter {
	@:update private function optionalNameUpdated(?name:Name):Void {}
	
	//These aren't allowed, and would throw compile errors, preventing the tests
	//from running at all.
	//@:add private function optionalNameAdded(?name:Name):Void {}
	//@:remove private function optionalNameRemoved(?name:Name):Void {}
}

class RecursiveEventSystem extends System implements IMethodCounter {
	@:add private function twoRemovesOne(two:Two, entity:Entity):Void {
		entity.remove(world, One);
	}
	
	@:add private function threeRemovesTwo(three:Three, entity:Entity):Void {
		entity.remove(world, Two);
	}
	
	@:remove private function removingThreeAddsTwo(three:Three, entity:Entity):Void {
		entity.add(world, (2:Two));
	}
	
	@:remove private function removingTwoAddsOne(two:Two, entity:Entity):Void {
		entity.add(world, (1:One));
	}
	
	@:add private function briefRemovesItself(brief:Brief, entity:Entity):Void {
		entity.remove(world, Brief);
	}
	
	@:remove private function permanentTriesToAddItself(permanent:Permanent, entity:Entity):Void {
		//This is not allowed, and should throw an error. If it was allowed, it
		//would keep the component around permanently, hence the name.
		entity.add(world, permanent);
	}
}

class RemoveStringSystem extends System implements IMethodCounter {
	@:update public function removeString(entity:Entity, string:String):Void {
		if(string == "remove") {
			entity.remove(world, String);
		}
	}
}
