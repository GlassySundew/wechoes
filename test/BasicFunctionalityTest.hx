package;

import echoes.World;
import Components;
import echoes.Entity;
import echoes.SystemList;
import echoes.utils.Clock;
import MethodCounter.assertTimesCalled;
import Systems;
import utest.Assert;
import utest.Test;

class BasicFunctionalityTest extends Test {
	private function teardown():Void {
		// Echoes.reset();
		MethodCounter.reset();
	}
	
	//Tests may be run in any order, but not in parallel.
	
	#if (echoes_storage != "Map")
	#if !eval
	//Test an array-specific edge case that potentially breaks every other test.
	//If this fails on any target, update `ComponentStorage.clear()`, then skip
	//this test on that target.
	private function testArrayBehavior():Void {
		final array:Array<Null<Int>> = [for(i in 0...5) i];
		Assert.equals(2, array[2]);
		Assert.isNull(array[6]);
		
		array.resize(0);
		Assert.isNull(array[2]);
		
		array[3] = 30;
		Assert.isNull(array[2]); //<- The only test likely to fail.
		Assert.equals(30, array[3]);
		Assert.isNull(array[4]);
	}
	#end
	#end
	
	private function testEntities():Void {
		var world = new World();
		
		//Make an inactive entity.
		final entity:Entity = new Entity(world, false);
		Assert.isFalse(entity.isActive(world));
		Assert.equals(0, world.activeEntities.length);
		Assert.equals(0, entity.id);
		
		//Activate it.
		entity.activate(world);
		Assert.isTrue(entity.isActive(world));
		Assert.isFalse(entity.isDestroyed(world));
		Assert.equals(1, world.activeEntities.length);
		
		//Add a component.
		entity.add(world, STAR);
		Assert.isTrue(entity.exists(world, Shape));
		
		//Deactivate the entity.
		entity.deactivate(world);
		Assert.isTrue(entity.exists(world, Shape));
		
		//Add and remove a component while inactive.
		entity.add(world, ("entity":Name));
		Assert.isTrue(entity.exists(world, Name));
		
		entity.remove(world, Name);
		Assert.isFalse(entity.exists(world, Name));
		
		//Destroy it.
		entity.destroy(world);
		Assert.isFalse(entity.exists(world, Shape));
		Assert.isTrue(entity.isDestroyed(world));
		Assert.equals(1, @:privateAccess world.entityIdPool.length);
		
		//Make a new entity (should use the same ID as the old).
		final newEntity:Entity = new Entity(world);
		Assert.equals(entity, newEntity);
		Assert.equals(0, @:privateAccess world.entityIdPool.length);
		Assert.equals(0, newEntity.id);
	}
	
	private function testComponents():Void {
		var world = new World();
		
		//Create the entity.
		final blackSquare:Entity = new Entity(world);
		Assert.isTrue(blackSquare.isActive(world));
		Assert.equals(0, Lambda.count(blackSquare.getComponents(world)));
		
		//Create some interchangeable components.
		final black:Color = 0x000000;
		final nearBlack:Color = 0x111111;
		final name:Name = "blackSquare";
		final shortName:Name = "blSq";
		
		//Add components.
		blackSquare.add(world, black);
		Assert.equals(black, blackSquare.get(world, Color));
		Assert.isFalse(blackSquare.exists(world, Int));
		
		blackSquare.add(world, 0xFFFFFF);
		Assert.notEquals(blackSquare.get(world, Color), blackSquare.get(world, Int));
		
		blackSquare.add(world, SQUARE);
		Assert.equals(SQUARE, blackSquare.get(world, Shape));
		
		blackSquare.add(world, name);
		Assert.equals(name, blackSquare.get(world, Name));
		Assert.isFalse(blackSquare.exists(world, String));
		
		//Overwrite existing components.
		blackSquare.add(world, nearBlack, shortName);
		Assert.equals(nearBlack, blackSquare.get(world, Color));
		Assert.equals(shortName, blackSquare.get(world, Name));
		
		//Don't overwrite existing components.
		blackSquare.addIfMissing( world, name, CIRCLE, "string" );

		Assert.equals(shortName, blackSquare.get(world, Name));
		Assert.equals(SQUARE, blackSquare.get(world, Shape));
		Assert.equals("string", blackSquare.get(world, String));
		
		//Remove components.
		blackSquare.remove( world, Shape, Name, String);
		Assert.isTrue(blackSquare.exists(world, Color));
		Assert.isFalse(blackSquare.exists(world, Shape));
		Assert.isFalse(blackSquare.exists(world, Name));
		
		blackSquare.remove(world, Shape);
		Assert.isTrue(blackSquare.exists(world, Color));
		Assert.isFalse(blackSquare.exists(world, Shape));
		
		blackSquare.removeAll(world);
		Assert.isFalse(blackSquare.exists(world, Color));
	}
	
	private function testInactiveEntities():Void {
		var world = new World();
		
		final inactive:Entity = new Entity(world, false);
		Assert.isFalse(inactive.isActive(world));
		Assert.equals(0, world.activeEntities.length);
		
		new AppearanceSystem(world).activate();
		
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//Add some components the system looks for.
		inactive.add(world, (0x0000FF:Color));
		
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//The system should notice when the entity's state changes.
		inactive.activate(world);

		assertTimesCalled(1, "AppearanceSystem.colorAdded");

		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		
		inactive.deactivate(world);
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
	}
	
	private function testAddAndRemoveEvents():Void {
		var world = new World();

		//Add a system.
		final appearanceSystem:AppearanceSystem = new AppearanceSystem(world);
		Assert.equals(0, world.activeSystems.length);
		
		appearanceSystem.activate();
		Assert.equals(1, world.activeSystems.length);
		assertTimesCalled(0, "AppearanceSystem.colorAdded");
		
		//Add a red line.
		Assert.equals(0, world.activeEntities.length);
		
		final redLine:Entity = new Entity(world);
		Assert.equals(1, world.activeEntities.length);
		
		redLine.add(world, (0xFF0000:Color), Shape.LINE);
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeAdded");
		assertTimesCalled(0, "AppearanceSystem.colorAndShapeRemoved");
		
		//Add a circle.
		final circle:Entity = new Entity(world);
		Assert.equals(2, world.activeEntities.length);
		
		circle.add(world, CIRCLE);
		assertTimesCalled(1, "AppearanceSystem.colorAdded");
		assertTimesCalled(2, "AppearanceSystem.shapeAdded");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeAdded");
		assertTimesCalled(0, "AppearanceSystem.colorAndShapeRemoved");
		
		//Create and activate a system AFTER adding the component.
		circle.add(world, ("circle":Name));
		assertTimesCalled(0, "NameSystem.nameAdded", "NameSystem doesn't exist but its method was still called.");
		
		final nameSystem:NameSystem = new NameSystem(world);
		
		redLine.add(world, ("redLine":Name));
		assertTimesCalled(0, "NameSystem.nameAdded", "NameSystem isn't active but its method was still called.");
		
		nameSystem.activate();
		assertTimesCalled(2, "NameSystem.nameAdded");
		assertTimesCalled(0, "NameSystem.nameRemoved");
		
		//Overwrite some components.
		redLine.add(world, ("darkRedLine":Name));
		assertTimesCalled(3, "NameSystem.nameAdded");
		assertTimesCalled(1, "NameSystem.nameRemoved");
		
		assertTimesCalled(2, "AppearanceSystem.shapeAdded");
		assertTimesCalled(0, "AppearanceSystem.shapeRemoved");
		circle.add(world, SQUARE);
		circle.add(world, CIRCLE);
		assertTimesCalled(4, "AppearanceSystem.shapeAdded");
		assertTimesCalled(0, "AppearanceSystem.shapeRemoved");
		
		//Deconstruct an entity.
		redLine.remove(world, Shape);
		assertTimesCalled(0, "AppearanceSystem.colorRemoved");
		assertTimesCalled(1, "AppearanceSystem.shapeRemoved");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeRemoved");
		
		redLine.remove(world, Color);
		assertTimesCalled(1, "AppearanceSystem.colorRemoved");
		assertTimesCalled(1, "AppearanceSystem.colorAndShapeRemoved");
		
		redLine.removeAll(world);
		assertTimesCalled(2, "NameSystem.nameRemoved");
		
		//Deactivate a system.
		nameSystem.deactivate();
		assertTimesCalled(2, "NameSystem.nameRemoved");
		
		//Destroy the remaining entity.
		assertTimesCalled(1, "AppearanceSystem.shapeRemoved");
		
		circle.destroy(world);
		assertTimesCalled(2, "NameSystem.nameRemoved");
		assertTimesCalled(2, "AppearanceSystem.shapeRemoved");
	}
	
	@:access(echoes.Echoes.lastUpdate)
	private function testUpdateEvents():Void {
		var world = new World();
		
		//Create a `TimeCountSystem` and use a custom `Clock`.
		final systems:SystemList = new SystemList(world, new OneSecondClock());
		systems.activate();
		
		final timeCountSystem:TimeCountSystem = new TimeCountSystem(world);
		Assert.equals(0.0, timeCountSystem.totalTime);
		
		systems.add(timeCountSystem);
		
		//Create some entities, but none with both color and shape.
		final green:Entity = new Entity(world).add(world, (0x00FF00:Color));
		Assert.equals(0.0, timeCountSystem.colorTime);
		
		final star:Entity = new Entity(world).add(world, STAR, ("Proxima Centauri":Name));
		Assert.equals(0.0, timeCountSystem.shapeTime);
		
		Assert.isNull(star.get(world, Color), star.get(world, Color) + " should be null. See ComponentStorage constructor for details.");
		
		//Run an update.
		world.update();
		// trace(world.activeSystems);
		Assert.equals(1.0, timeCountSystem.totalTime);
		Assert.equals(1.0, timeCountSystem.colorTime);
		Assert.equals(1.0, timeCountSystem.shapeTime);
		Assert.equals(0.0, timeCountSystem.colorAndShapeTime);
		
		//Give one entity both a color and shape.
		star.add(world, (0xFFFFFF:Color));

		//Simulate time passing without actually waiting for it.
		world.lastUpdate -= 0.001;
		
		//Run another few updates. (`colorTime` should now increment twice per
		//update, since now two entities have color.)
		world.update();
		Assert.equals(2.0, timeCountSystem.totalTime);
		Assert.equals(3.0, timeCountSystem.colorTime);
		Assert.equals(2.0, timeCountSystem.shapeTime);
		Assert.equals(1.0, timeCountSystem.colorAndShapeTime);
		
		world.lastUpdate -= 0.001;
		world.update();
		Assert.equals(3.0, timeCountSystem.totalTime);
		Assert.equals(5.0, timeCountSystem.colorTime);
		Assert.equals(3.0, timeCountSystem.shapeTime);
		Assert.equals(2.0, timeCountSystem.colorAndShapeTime);
	}
}

/**
 * A custom `Clock` that advances 1 second whenever `Echoes.update()` is called,
 * regardless of the real-world time elapsed.
 */
class OneSecondClock extends Clock {
	public override function addTime(time:Float):Void {
		super.addTime(1);
	}
}
