package;

import echoes.World;
import Components;
import echoes.ComponentStorage;
import echoes.Entity;
import echoes.System;
import echoes.SystemList;
import echoes.utils.ComponentTypes;
import echoes.utils.Signal;
import echoes.View;
import haxe.PosInfos;
import MethodCounter.assertTimesCalled;
import Systems;
import utest.Assert;
import utest.Test;

@:depends( BasicFunctionalityTest )
class AdvancedFunctionalityTest extends Test {

	private var count1 : Int = 0;

	private function listener1() : Void {
		count1++;
	}

	private function teardown() : Void {
		// Echoes.reset();
		MethodCounter.reset();
	}

	// Tests may be run in any order, but not in parallel.

	private function testComponentTypes() : Void {
		var world = new World();

		final types : ComponentTypes = new ComponentTypes();
		types.add( world, Bool );
		types.add( world, Bool );
		Assert.equals( 1, types.length );
		Assert.isTrue( types.containsComponentStorage( world.getComponentStorage( Bool ) ) );

		final stringStorage : DynamicComponentStorage = world.getComponentStorage( String );
		types.addComponentStorage( stringStorage );
		Assert.equals( 2, types.length );
		Assert.isTrue( types.contains( world, String ) );

		types.remove( world, Bool );
		Assert.isFalse( types.contains( world, Bool ) );
		Assert.isTrue( types.contains( world, String ) );

		types.removeComponentStorage( stringStorage );
		Assert.isFalse( types.contains( world, String ) );
	}

	private function testCustomStorage() : Void {
		var world = new World();

		Assert.isTrue( world.getComponentStorage( IntArray ) is IntArrayStorage );
		Assert.isFalse( world.getComponentStorage(( _ : Array<Int> ) ) is IntArrayStorage );
		Assert.isFalse( world.getComponentStorage( EagerIntArray ) is IntArrayStorage );
	}

	private function testDynamicViews() : Void {
		var world = new World();

		final componentStorage0 : ComponentStorage<Any> = new ComponentStorage<Any>( world, "component0" );
		final componentStorage1 : ComponentStorage<Any> = new ComponentStorage<Any>( world, "component1" );

		final view : DynamicView = new DynamicView( world, componentStorage0, componentStorage1 );
		view.activate();
		var added : String = "";
		view.onAdded.add( ( entity, components ) -> added += components.join( "" ) );
		var removed : String = "";
		view.onRemoved.add( ( entity, components ) -> removed += components.join( "" ) );

		final entity0 : Entity = new Entity( world );
		componentStorage0.add( entity0, "---", world );
		componentStorage0.remove( entity0, world );
		Assert.equals( "", added );
		Assert.equals( "", removed );

		componentStorage1.add( entity0, "b", world );
		componentStorage0.add( entity0, "a", world );
		Assert.equals( "ab", added );
		Assert.equals( "", removed );

		final entity1 : Entity = new Entity( world );
		entity1.add( world, "string" );
		componentStorage0.add( entity1, 0, world );
		componentStorage1.add( entity1, 1, world );
		Assert.equals( "ab01", added );
		Assert.equals( "", removed );

		var updated : String = "";
		view.iter( ( entity, components ) -> updated += components.join( "" ) );
		Assert.equals( "ab01", updated );

		componentStorage1.remove( entity1, world );
		componentStorage1.remove( entity0, world );
		Assert.equals( "ab01", added );
		Assert.equals( "01ab", removed );
	}

	private function testEntityTemplates() : Void {
		var world = new World();

		new NameSystem( world ).activate();
		new AppearanceSystem( world ).activate();

		final entity : Entity = new Entity( world );
		entity.add( world, ( "John" : Name ) );

		final namedEntity : NamedEntity = NamedEntity.applyTemplateTo( entity, world );
		Assert.equals( entity, namedEntity );
		Assert.equals( "John", namedEntity.getName( world ) );
		assertTimesCalled( 1, "NameSystem.nameAdded" );
		assertTimesCalled( 0, "NameSystem.nameRemoved" );

		namedEntity.setName( null, world );
		Assert.equals( null, namedEntity.getName( world ) );
		assertTimesCalled( 1, "NameSystem.nameAdded" );
		assertTimesCalled( 1, "NameSystem.nameRemoved" );

		final visualEntity : VisualEntity = VisualEntity.applyTemplateTo( namedEntity, world );
		Assert.equals( VisualEntity.DEFAULT_COLOR, visualEntity.getColor( world ) );
		assertTimesCalled( 1, "AppearanceSystem.colorAdded" );
		assertTimesCalled( 0, "AppearanceSystem.colorRemoved" );
		Assert.equals( VisualEntity.DEFAULT_SHAPE, ( visualEntity : Entity ).get( world, Shape ) );

		Assert.equals( NamedEntity.DEFAULT_NAME, new NamedEntity( world ).getName( world ) );
		Assert.notEquals( NamedEntity.DEFAULT_NAME, new NamedEntity( world, "not default" ).getName( world ) );
		assertTimesCalled( 3, "NameSystem.nameAdded" );
		assertTimesCalled( 1, "NameSystem.nameRemoved" );

		NameStringEntity.applyTemplateTo( visualEntity, world );
		Assert.equals( NameStringEntity.DEFAULT_NAME, namedEntity.getName( world ) );
		assertTimesCalled( 4, "NameSystem.nameAdded" );
		assertTimesCalled( 1, "NameSystem.nameRemoved" );

		NamedEntity.removeTemplateFrom( namedEntity, world );
		Assert.isNull( namedEntity.getName( world ) );
		Assert.notNull( namedEntity.get( world, String ) );
		assertTimesCalled( 2, "NameSystem.nameRemoved" );

		final nullEntity : Null<NamedEntity> = null;
		Assert.isNull( nullEntity );
		#if cpp
		Assert.notNull(( nullEntity : Null<Entity> ), "C++ code generation has improved, and a warning can be removed from EntityTemplateBuilder." );
		#else
		Assert.isNull(( nullEntity : Null<Entity> ) );
		#end
	}

	private function testFindSystem() : Void {
		final world = new World();

		final parent : SystemList = new SystemList( world );
		final child : SystemList = new SystemList( world );
		final name : NameSystem = new NameSystem( world );
		final appearance : AppearanceSystem = new AppearanceSystem( world );

		parent.add( child );
		parent.add( name );
		child.add( appearance );

		Assert.equals( name, parent.find( NameSystem ) );
		Assert.equals( appearance, parent.find( AppearanceSystem ) );

		Assert.equals( null, child.find( NameSystem ) );
		Assert.equals( appearance, child.find( AppearanceSystem ) );
	}

	private function testGenerics() : Void {
		final world = new World();

		final system : GenericSystem<String, Int> = new GenericSystem<String, Int>( world );
		system.activate();

		final entity : Entity = new Entity( world );
		entity.add( world, "STRING" );
		entity.add( world, 0 );
		switch ( system.record ) {
			case ["string0"]:
				Assert.pass();
			default:
				Assert.fail( "Incorrect record: " + system.record );
		}

		entity.add( world, 3 );
		switch ( system.record ) {
			case ["string0", "string3"]:
				Assert.pass();
			default:
				Assert.fail( "Incorrect record: " + system.record );
		}

		final system = new GenericSystem<Alias<Name>, String>( world );
		system.activate();

		entity.add( world, ( "NAME" : Alias<Name> ) );
		switch ( system.record ) {
			// Only the first component should be converted to lowercase.
			case ["nameSTRING"]:
				Assert.pass();
			default:
				Assert.fail( "Incorrect record: " + system.record );
		}
	}

	private function testGetComponentStorage() : Void {
		// `String` and `Array` are already fully-qualified, but `Bool` is short
		// for `StdTypes.Bool`.
		final world = new World();

		Assert.equals( "String", world.getComponentStorage( String ).componentType );
		Assert.equals( "Array<StdTypes.Bool>", world.getComponentStorage(( _ : Array<Bool> ) ).componentType );
		Assert.equals( "ComponentStorage<StdTypes.Bool>", Std.string( world.getComponentStorage( Bool ) ) );
		Assert.equals( "ReadOnlyArray<Bool>", world.getComponentStorage(( _ : haxe.ds.ReadOnlyArray<Bool> ) ).shortComponentType );

		final entity : Entity = new Entity( world );
		entity.add( world, ["xyz"] );
		switch ( world.getComponentStorage(( _ : Array<String> ) ).get( entity ) ) {
			case ["xyz"]:
				Assert.pass();
			case x:
				Assert.fail( 'Expected ["xyz"], got $x' );
		}
	}

	private function testExclude() : Void {

		final world = new World();

		final system = new ExcludeTestSystem( world );
		system.activate();

		assertTimesCalled( 0, "ExcludeTestSystem.addTest" );

		final entity : Entity = new Entity( world );
		entity.add( world, ( "John" : Name ) );

		assertTimesCalled( 1, "ExcludeTestSystem.addTest" );

		final entity2 : Entity = new Entity( world );
		entity2.add( world, ( 0xFFFFFF : Color ), ( "John" : Name ) );

		assertTimesCalled( 1, "ExcludeTestSystem.addTest" );

		world.update();

		assertTimesCalled( 1, "ExcludeTestSystem.updateTest" );

		entity2.remove( world, Color );

		world.update();

		assertTimesCalled( 3, "ExcludeTestSystem.updateTest" );

		entity2.add( world, ( 0xFFFFFF : Color ), );

		world.update();

		assertTimesCalled( 4, "ExcludeTestSystem.updateTest" );

		entity2.remove( world, Color );
		entity2.add( world, ( [] : Array<String> ) );

		world.update();

		assertTimesCalled( 5, "ExcludeTestSystem.updateTest" );

		var entity3 = new Entity( world );

		entity3.add( world, ( "John" : Name ), ( 0xFFFFFF : Color ) );

		entity3.remove( world, Name );

		// both of them are triggered by sequentially adding Name comp
		// and then Color which triggers Name component removal
		assertTimesCalled( 2, "ExcludeTestSystem.removeTest" );
	}

	@:access( echoes.System )
	private function testPriority() : Void {
		final world = new World();

		final list : SystemList = new SystemList( world );

		inline function assertListContents( contents : Array<System>, ?pos : PosInfos ) : Void {
			if ( Assert.equals( contents.length, list.length,
				'Expected ${contents.length} systems; got ${list.length}.', pos ) ) {
				for ( i in 0...contents.length ) {
					if ( contents[i] != list.systems[i] ) {
						Assert.fail( 'Expected $contents, got ${list.systems} (index $i differs).', pos );
						break;
					}
				}
			}
		}

		// Add systems from low to high priority.
		final high : HighPrioritySystem = new HighPrioritySystem();
		final middle : NameSystem = new NameSystem( world );
		final low : NameSystem = new NameSystem( world, -1 );

		list.add( low );
		list.add( middle );
		list.add( high );
		assertListContents( [high, middle, low] );

		// Next, add a system with children.
		final parent : UpdateOrderSystem = new UpdateOrderSystem( world );
		Assert.equals( 0, parent.priority );
		final positiveChild : System = Lambda.find( parent.__children__, child -> child.priority == 1 );
		Assert.notNull( positiveChild );
		final negativeChild : System = Lambda.find( parent.__children__, child -> child.priority == -1 );
		Assert.notNull( negativeChild );

		list.add( parent );
		assertListContents( [
			high, positiveChild, // 1
			middle, parent, // 0
			low, negativeChild //-1
		] );

		final updateOrder : Array<String> = [];
		new Entity( world, true ).add( world, updateOrder );
		list.__activate__();
		list.__update__( 1 );
		Assert.equals( "pre_update, update, update2, post_update", updateOrder.join( ", " ) );

		// Update the priority of existing systems. Setting `low` to -1 should
		// move it to the end of that bracket even though it already was -1.
		parent.priority = 2;
		middle.priority = -1;
		low.priority = -1;
		assertListContents( [
			parent, // 2
			high, positiveChild, // 1
			negativeChild, middle, low //-1
		] );

		updateOrder.resize( 0 );
		list.__update__( 1 );
		Assert.equals( "update, update2, pre_update, post_update", updateOrder.join( ", " ) );
	}

	private function testSerialization() : Void {
		var world = new World();

		var addNameCount : Int = 0;
		final named : View<Name> = world.getView( Name );
		named.onAdded.add( ( entity, name ) -> {
			addNameCount++;
		} );

		final entity0 : Entity = new Entity( world );
		final entity1 : Entity = new Entity( world );
		final entity2 : Entity = new Entity( world );

		entity0.add( world, ( "zero" : Name ) );
		entity0.add( world, ( 0xFFFFFF : Color ) );

		entity1.add( world, ( "one" : Name ) );
		entity1.add( world, ( 0.5 : Alias<Float> ) );
		entity1.add( world, ["red", "green", "blue"] );

		entity2.add( world, ( "two" : Name ) );
		entity2.add( world, ( 4 : Alias<Float> ) );

		Assert.equals( 3, addNameCount );
		Assert.equals( 3, named.entities.length );
		Assert.same( [0, 1, 2], @:privateAccess world.activeEntities );

		entity0.deactivate( world );
		#if echoes_stable_order
		entity1.deactivate();
		entity1.activate();
		#end
		Assert.same( [2, 1], @:privateAccess world.activeEntities );
		Assert.same( [null, 1, 0], @:privateAccess world.activeEntityIndices );

		// Bulk serialization

		final data : String = world.serialize();
		world.reset();

		addNameCount = 0;
		named.activate();
		named.onAdded.add( ( entity, name ) -> {
			addNameCount++;
		} );

		world.unserialize( data );

		Assert.same( [2, 1], @:privateAccess world.activeEntities );
		Assert.same( [null, 1, 0], @:privateAccess world.activeEntityIndices );
		Assert.isFalse( entity0.isActive( world ) );
		Assert.isTrue( entity1.isActive( world ) && entity2.isActive( world ) );

		Assert.equals( "zero", entity0.get( world, Name ) );
		Assert.equals( 0xFFFFFF, entity0.get( world, Color ) );

		Assert.equals( "one", entity1.get( world, Name ) );

		// Assert.equals(0.5, );
		Assert.same( ["red", "green", "blue"], entity1.get( world, ( _ : Array<String> ) ) );

		Assert.equals( "two", entity2.get( world, Name ) );
		Assert.equals( 4.0, entity2.get( world, ( _ : Alias<Float> ) ) );

		Assert.equals( 2, addNameCount );
		Assert.equals( 2, named.entities.length );
		entity0.activate( world );
		Assert.equals( 3, addNameCount );
		Assert.equals( 3, named.entities.length );

		// Single-component serialization

		entity2.remove( world, Name );
		final data : String = world.getComponentStorage( Name ).serialize();

		entity0.remove( world, Name );
		entity1.add( world, ( "entity1" : Name ) );
		entity2.add( world, ( "" : Name ) );

		addNameCount = 0;
		var removeNameCount : Int = 0;
		named.onRemoved.add( ( entity, name ) -> removeNameCount++ );
		world.getComponentStorage( Name ).unserialize( data, world );

		Assert.equals( 2, addNameCount );
		Assert.equals( 2, removeNameCount );
		Assert.equals( 2, named.entities.length );

		Assert.equals( "zero", entity0.get( world, Name ) );
		Assert.equals( "one", entity1.get( world, Name ) );
		Assert.isNull( entity2.get( world, Name ) );

		Assert.isTrue( entity0.getComponents( world ).contains( world, Name ) );
		Assert.isTrue( entity1.getComponents( world ).contains( world, Name ) );
		Assert.isFalse( entity2.getComponents( world ).contains( world, Name ) );
	}

	private function testSignals() : Void {
		count1 = 0;
		var count2 : Int = 0;

		#if( hl || cpp )
		Assert.equals( listener1, listener1 );
		#else
		// Each time you access an instance method, Haxe will (or used to) create
		// a new closure, meaning `listener1 != listener1`. The only reliable way
		// to compare methods is (or was) via `Reflect`.

		// >glassysundew: donno how to fix this :shrug:
		// Assert.notEquals(listener1, listener1, "Haxe changed how it handles instance methods.");
		#end
		Assert.isTrue( Reflect.compareMethods( listener1, listener1 ) );

		// However, local functions have always worked fine.
		function listener2() : Void {
			count2++;
		}
		Assert.equals( listener2, listener2 );
		Assert.isTrue( Reflect.compareMethods( listener2, listener2 ) );

		// Make a signal.
		final signal : Signal< () -> Void> = new Signal();

		signal.push( listener1 );
		Assert.isTrue( signal.contains( listener1 ) );

		signal.push( listener2 );
		Assert.isTrue( signal.contains( listener2 ) );

		// Dispatch it.
		signal.dispatch();
		Assert.equals( 1, count1 );
		Assert.equals( 1, count2 );

		// Remove a function and dispatch again.
		signal.remove( listener1 );
		Assert.isFalse( signal.contains( listener1 ) );

		signal.dispatch();
		Assert.equals( 1, count1 );
		Assert.equals( 2, count2 );
	}

	private function testTypeParameters() : Void {
		var world = new World();

		final entity : Entity = new Entity( world );

		entity.add( world, [1, 2, 3] );
		Assert.isFalse( entity.exists( world, IntArray ) ); // Regular typedef
		Assert.isTrue( entity.exists( world, EagerIntArray ) ); // @:eager typedef
		Assert.isTrue( entity.exists( world, ( _ : Array<Int> ) ), null );
	}

	private function testViews() : Void {
		// Make several entities with varying components.
		var world = new World();

		final nameEntity : Entity = new Entity( world ).add( world, ( "name1" : Name ) );
		final shapeEntity : Entity = new Entity( world ).add( world, CIRCLE );
		final colorNameEntity : Entity = new Entity( world ).add( world, ( 0x00FF00 : Color ), ( "name2" : Name ) );
		final colorShapeEntity : Entity = new Entity( world ).add( world, ( 0xFFFFFF : Color ), STAR );

		// Make some views; each should see a different selection of entities.
		final viewOfName : View<Name> = world.getView( Name );
		Assert.equals( 2, viewOfName.entities.length );
		Assert.isTrue( viewOfName.entities.contains( nameEntity ) );
		Assert.isTrue( viewOfName.entities.contains( colorNameEntity ) );

		final viewOfShape : View<Shape> = world.getView( Shape );
		Assert.equals( 2, viewOfShape.entities.length );
		Assert.isTrue( viewOfShape.entities.contains( shapeEntity ) );
		Assert.isTrue( viewOfShape.entities.contains( colorShapeEntity ) );

		// Test `iter()`.
		var joinedNames : String = "";
		viewOfName.iter( ( e : Entity, n : Name ) -> joinedNames += n );
		Assert.equals( "name1name2", joinedNames );

		// Remove a component.
		colorNameEntity.remove( world, Name );
		Assert.equals( 1, viewOfName.entities.length );
		Assert.isFalse( viewOfName.entities.contains( colorNameEntity ) );

		// Make a view that's linked to a system.
		final nameSystem : NameSystem = new NameSystem( world );
		final colorView : View<Color> = nameSystem.getLinkedView( Color );
		Assert.isFalse( colorView.active );
		Assert.equals( 0, colorView.entities.length );

		// Adding/removing the system should activate/deactivate the linked view.
		nameSystem.activate();
		Assert.isTrue( colorView.active );
		Assert.equals( 2, colorView.entities.length );
		Assert.isTrue( colorView.entities.contains( colorNameEntity ) );
		Assert.isTrue( colorView.entities.contains( colorShapeEntity ) );

		nameSystem.deactivate();
		Assert.isFalse( colorView.active );
		Assert.equals( 0, colorView.entities.length );
	}

	private function testViewSignals() : Void {
		var world = new World();

		final entity : Entity = new Entity( world );

		final viewOfShape : View<Shape> = world.getView( Shape );

		var signalDispatched : Bool = false;
		function listener( e : Entity, s : Shape ) : Void {
			Assert.equals( entity, e );
			Assert.equals( STAR, s );

			signalDispatched = true;
		}

		// Test onAdded.
		viewOfShape.onAdded.push( listener );

		entity.add( world, STAR );
		Assert.isTrue( signalDispatched );

		// Test onRemoved.
		viewOfShape.onRemoved.push( listener );
		signalDispatched = false;
		entity.removeAll( world );
		Assert.isTrue( signalDispatched );
	}
}

typedef Alias<T> = T;

@:echoes_storage( new AdvancedFunctionalityTest.IntArrayStorage( world ) )
typedef IntArray = Array<Int>;

@:echoes_storage( new AdvancedFunctionalityTest.IntArrayStorage( world ) ) // ignored
@:eager typedef EagerIntArray = Array<Int>;

class IntArrayStorage extends ComponentStorage<IntArray> {

	public function new( world ) {
		super( world, "IntArray");
	}
}
