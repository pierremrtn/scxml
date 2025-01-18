import 'dart:async';

import 'package:scxml/scxml.dart';
import 'package:test/test.dart';

void main() {
  group('State Creation and Structure', () {
    test('Create Atomic State', () {
      final state = AtomicState<String, String>(
        id: 'test',
        transitions: [],
        onEnter: () {},
        onExit: () {},
      );

      expect(state.id, equals('test'));
      expect(state.transitions, isEmpty);
      expect(state.ancestor, isNull);
      expect(state.isRoot, isTrue);
    });

    test('Create Compound State', () {
      final substate1 = AtomicState<String, String>(
        id: 'sub1',
        transitions: [],
      );

      final state = CompoundState<String, String>(
        id: 'compound',
        initial: "sub1",
        substates: [substate1],
        transitions: [],
      );

      expect(state.id, equals('compound'));
      expect(state.substates.length, equals(1));
      expect(state.initial, equals("sub1"));
      expect(substate1.ancestor, equals(state));
    });

    test('State Hierarchy', () {
      final child = AtomicState<String, String>(
        id: 'child',
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final parent = CompoundState<String, String>(
        id: 'parent',
        substates: [child],
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final grandparent = CompoundState<String, String>(
        id: 'grandparent',
        substates: [parent],
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      expect(child.ancestors(), equals([parent, grandparent]));
      expect(parent.ancestors(), equals([grandparent]));
      expect(grandparent.ancestors(), isEmpty);
    });

    test('State Flattening', () {
      final child1 = AtomicState<String, String>(
        id: 'child1',
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final child2 = AtomicState<String, String>(
        id: 'child2',
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final parent = CompoundState<String, String>(
        id: 'parent',
        substates: [child1, child2],
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final flattened = parent.flatten().toList();
      expect(flattened, equals([parent, child1, child2]));
    });

    test('Default State Selection', () {
      final child1 = AtomicState<String, String>(
        id: 'child1',
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final child2 = AtomicState<String, String>(
        id: 'child2',
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      final parentWithInitial = CompoundState<String, String>(
        id: 'parent',
        initial: "child2",
        substates: [child1, child2],
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      expect(parentWithInitial.defaultState, equals(child2));

      final parentWithoutInitial = CompoundState<String, String>(
        id: 'parent',
        initial: null,
        substates: [child1, child2],
        transitions: [],
        onEnter: null,
        onExit: null,
      );

      expect(parentWithoutInitial.defaultState, equals(child1));
    });
  });

  group('State Transitions', () {
    test('Basic Event Transition', () async {
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.on<String>((event) => event == 'go' ? 'B' : null);
        });
        builder.state('B');
        builder.initial = 'A';
      });

      expect(stateMachine.activeStates.last, equals('A'));
      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates.last, equals('B'));
    });

    test('Eventless Transition', () async {
      var condition = true;
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.when(() => condition ? 'B' : null);
        });
        builder.state('B');
        builder.initial = 'A';
      });

      expect(stateMachine.activeStates.last, equals('A'));
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates.last, equals('B'));
    });

    test('Inherited Transitions', () async {
      final stateMachine = StateMachine<String, String>((builder) {
        builder.initial = 'Child';
        builder.state('Parent', (parent) {
          parent.on<String>((event) => event == 'go' ? 'Target' : null);
          parent.state('Child');
        });
        builder.state('Target');
      });

      expect(stateMachine.activeStates, contains('Child'));
      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates.last, equals('Target'));
    });

    test('Compound State with Multiple Children', () async {
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('Parent', (parent) {
          parent.initial('Child1');
          parent.on<String>((event) => event == 'toChild2' ? 'Child2' : null);

          parent.state('Child1', (child) {
            child.on<String>((event) => event == 'toTarget' ? 'Target' : null);
          });
          parent.state('Child2', (child) {
            child.on<String>((event) => event == 'toTarget' ? 'Target' : null);
          });
        });
        builder.state('Target');
        builder.initial = 'Parent';
      });

      expect(stateMachine.activeStates, equals(['Parent', 'Child1']));

      // Test parent transition between children
      stateMachine.addEvent('toChild2');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Parent', 'Child2']));

      // Test child transition to external state
      stateMachine.addEvent('toTarget');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Target']));
    });

    test('Compound State internal Transition', () async {
      final stateMachine = StateMachine<String, String>(($) {
        $.state("parent", ($) {
          $.on<String>((e) => e);
          $.state("A");
          $.state("B");
        });
      });

      expect(stateMachine.activeStates, equals(['parent', 'A']));
      stateMachine.addEvent("B");
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['parent', 'B']));

      stateMachine.addEvent("A");
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['parent', 'A']));
    });

    test('Parent vs Child Transition Priority', () async {
      final transitionOrder = <String>[];

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('Parent', (parent) {
          parent.on<String>((event) {
            transitionOrder.add('parent handler');
            return event == 'test' ? 'Target' : null;
          });

          parent.state('Child', (child) {
            child.on<String>((event) {
              transitionOrder.add('child handler');
              return event == 'test' ? 'OtherTarget' : null;
            });
          });
        });
        builder.state('Target');
        builder.state('OtherTarget');
        builder.initial = 'Child';
      });

      stateMachine.addEvent('test');
      await Future.delayed(Duration.zero);

      // Child handler should be checked first
      expect(transitionOrder, equals(['child handler']));
      expect(stateMachine.activeStates.last, equals('OtherTarget'));
    });

    test('Complex State Navigation', () async {
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('GrandParent', (gp) {
          gp.initial('Parent1');

          gp.state('Parent1', (p1) {
            p1.initial('Child1');
            p1.on<String>((event) => event == 'toParent2' ? 'Parent2' : null);

            p1.state('Child1', (c) {
              c.on<String>((event) => event == 'toChild2' ? 'Child2' : null);
            });
            p1.state('Child2');
          });

          gp.state('Parent2', (p2) {
            p2.initial('Child3');
            p2.state('Child3');
            p2.state('Child4');
          });
        });
        builder.initial = 'GrandParent';
      });

      expect(stateMachine.activeStates,
          equals(['GrandParent', 'Parent1', 'Child1']));

      // Test transition within same parent
      stateMachine.addEvent('toChild2');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates,
          equals(['GrandParent', 'Parent1', 'Child2']));

      // Test transition to different parent (should enter default child)
      stateMachine.addEvent('toParent2');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates,
          equals(['GrandParent', 'Parent2', 'Child3']));
    });

    test('Transition with Conflicting Handlers', () async {
      final executedTransitions = <String>[];

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('Parent', (parent) {
          parent.on<String>((event) {
            executedTransitions.add('parent->target1');
            return event == 'move' ? 'Target1' : null;
          });

          parent.state('Child1', (c1) {
            c1.on<String>((event) {
              executedTransitions.add('child1->target2');
              return event == 'move' ? 'Target2' : null;
            });
          });

          parent.state('Child2', (c2) {
            c2.on<String>((event) {
              executedTransitions.add('child2->target3');
              return event == 'move' ? 'Target3' : null;
            });
          });
        });
        builder.state('Target1');
        builder.state('Target2');
        builder.state('Target3');
        builder.initial = 'Child1';
      });

      expect(stateMachine.activeStates, equals(['Parent', 'Child1']));

      // Child handler should take precedence
      stateMachine.addEvent('move');
      await Future.delayed(Duration.zero);
      expect(executedTransitions, equals(['child1->target2']));
      expect(stateMachine.activeStates, equals(['Target2']));
    });

    test('Multiple Transition Conditions', () async {
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('Parent', (parent) {
          parent.initial('Child1');

          parent.state('Child1', (c1) {
            c1.on<String>((event) => event == 'next' ? 'Child2' : null);
            c1.on<String>((event) => event == 'skip' ? 'Child3' : null);
            c1.on<String>((event) => event == 'exit' ? 'Target' : null);
          });

          parent.state('Child2', (c2) {
            c2.on<String>((event) => event == 'next' ? 'Child3' : null);
            c2.on<String>((event) => event == 'back' ? 'Child1' : null);
          });

          parent.state('Child3', (c3) {
            c3.on<String>((event) => event == 'back' ? 'Child2' : null);
          });
        });
        builder.state('Target');
        builder.initial = 'Parent';
      });

      expect(stateMachine.activeStates, equals(['Parent', 'Child1']));

      // Test sequential transitions
      stateMachine.addEvent('next');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Parent', 'Child2']));

      stateMachine.addEvent('next');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Parent', 'Child3']));

      // Test backwards navigation
      stateMachine.addEvent('back');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Parent', 'Child2']));

      // Test skip transition
      stateMachine.addEvent('back');
      await Future.delayed(Duration.zero);
      stateMachine.addEvent('skip');
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates, equals(['Parent', 'Child3']));
    });
  });

  group('Side Effects', () {
    test('Enter State Effect', () async {
      var enterCount = 0;
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.onEnter(() => enterCount++);
          b.on<String>((event) => event == 'go' ? 'B' : null);
        });
        builder.state('B');
        builder.initial = 'A';
      });

      expect(enterCount, equals(1));
      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(enterCount, equals(1));
    });

    test('Exit State Effect', () async {
      var exitCount = 0;
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.onExit(() => exitCount++);
          b.on<String>((event) => event == 'go' ? 'B' : null);
        });
        builder.state('B');
        builder.initial = 'A';
      });

      expect(exitCount, equals(0));
      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(exitCount, equals(1));
    });

    test('Transition Effect', () async {
      var transitionEffectCalled = false;
      var receivedEvent = '';

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.on<String>(
            (event) => event == 'go' ? 'B' : null,
            effect: (event) {
              transitionEffectCalled = true;
              receivedEvent = event;
            },
          );
        });
        builder.state('B');
        builder.initial = 'A';
      });

      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(transitionEffectCalled, isTrue);
      expect(receivedEvent, equals('go'));
    });

    test('Effect Order', () async {
      final effectOrder = <String>[];

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.onExit(() => effectOrder.add('exit A'));
          b.on<String>(
            (event) => event == 'go' ? 'B' : null,
            effect: (event) => effectOrder.add('transition'),
          );
        });
        builder.state('B', (b) {
          b.onEnter(() => effectOrder.add('enter B'));
        });
        builder.initial = 'A';
      });

      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);

      expect(effectOrder, equals(['exit A', 'transition', 'enter B']));
    });

    test('Async Effects', () async {
      final effectOrder = <String>[];
      final completer = Completer<void>();

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.on<String>(
            (event) => event == 'go' ? 'B' : null,
            effect: (event) async {
              effectOrder.add('start effect');
              await completer.future;
              effectOrder.add('end effect');
            },
          );
        });
        builder.state('B', (b) {
          b.onEnter(() => effectOrder.add('enter B'));
        });
        builder.initial = 'A';
      });

      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(effectOrder, equals(['start effect', 'enter B']));

      completer.complete();
      await Future.delayed(Duration.zero);
      expect(effectOrder, equals(['start effect', 'enter B', 'end effect']));
    });
  });

  group('Event Processing', () {
    test('Event Queue', () async {
      final stateSequence = <String>[];

      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.on<String>((event) {
            stateSequence.add('A -> B');
            return event == '1' ? 'B' : null;
          });
        });
        builder.state('B', (b) {
          b.on<String>((event) {
            stateSequence.add('B -> C');
            return event == '2' ? 'C' : null;
          });
        });
        builder.state('C');
        builder.initial = 'A';
      });

      stateMachine.addEvent('1');
      stateMachine.addEvent('2');
      await Future.delayed(Duration.zero);

      expect(stateSequence, equals(['A -> B', 'B -> C']));
      expect(stateMachine.activeStates.last, equals('C'));
    });

    test('Internal Events', () async {
      final effectOrder = <String>[];
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.when(
            () {
              effectOrder.add('eventless transition');
              return 'B';
            },
          );
        });
        builder.state('B', (b) {
          b.on<String>((event) {
            effectOrder.add('event transition');
            return event == 'go' ? 'C' : null;
          });
        });
        builder.state('C');
        builder.initial = 'A';
      });

      await Future.delayed(Duration.zero);
      expect(effectOrder, equals(['eventless transition']));

      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(effectOrder, equals(['eventless transition', 'event transition']));
    });

    test('Event Type Matching', () async {
      final stateMachine = StateMachine<String, num>(($) {
        $.state('parent', ($) {
          $.on<int>((event) => 'intState');
          $.on<double>((event) => 'doubleState');
          $.state('default');
          $.state('intState');
          $.state('doubleState');
        });
      });

      expect(stateMachine.activeStates.last, equals('default'));

      stateMachine.addEvent(1);
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates.last, equals('intState'));

      stateMachine.addEvent(2.0);
      await Future.delayed(Duration.zero);
      expect(stateMachine.activeStates.last, equals('doubleState'));
    });

    test('Null Event Handling', () async {
      final transitions = <String>[];
      final stateMachine = StateMachine<String, String>((builder) {
        builder.state('A', (b) {
          b.when(() {
            transitions.add('null transition');
            return 'B';
          });
        });
        builder.state('B', (b) {
          b.on<String>((event) {
            transitions.add('event transition');
            return event == 'go' ? 'C' : null;
          });
        });
        builder.state('C');
        builder.initial = 'A';
      });

      await Future.delayed(Duration.zero);
      expect(transitions, equals(['null transition']));

      stateMachine.addEvent('go');
      await Future.delayed(Duration.zero);
      expect(transitions, equals(['null transition', 'event transition']));
    });
  });

  // Add remaining test groups...
}
