import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';

import 'definition.dart';

class _EnabledTransition<S, E> {
  final StateDefinition<S, E> source;
  final StateDefinition<S, E> target;
  final TransitionDefinition<S, E> definition;
  final E? event;

  const _EnabledTransition({
    required this.definition,
    required this.source,
    required this.target,
    required this.event,
  });
}

class StateMachineProcessor<S, E> {
  StateMachineProcessor({
    required StateMachineDefinition<S, E> definition,
  })  : _definition = definition,
        _activeStates = [] {
    _eventLoopFuture = _eventLoop(definition.initial);
  }

  final _streamController = StreamController<E>();

  final StateMachineDefinition<S, E> _definition;

  final List<S> _activeStates;

  final Queue<E?> _internalEventQueue = Queue();

  StateDefinition<S, E> get activeAtomicState =>
      _definition.getState(_activeStates.last);

  /// Actives states, where first is the root state and last the deepest in the state hierarchy
  UnmodifiableListView<S> get activeStates =>
      UnmodifiableListView(_activeStates);

  Future<Object?>? _eventLoopFuture;

  Future<Object?> get asFuture => _eventLoopFuture!;

  void addEvent(E event) {
    _streamController.add(event);
  }

  bool isInState(S id) => activeStates.contains(id);

  Future<void> dispose() async {
    _terminate();
    await _streamController.close();
  }

  Future<Object?> _eventLoop(S initial) async {
    await _enterInitialStateSet(initial);
    await for (final event in _streamController.stream) {
      try {
        await _processMacroStep(event);
      } catch (e) {
        await dispose();
        return e;
      }
    }
    return null;
  }

  Future<void> _enterInitialStateSet(S initial) async {
    final target = _definition.getState(_definition.initial);
    final set = _findEntrySet(target, null);
    for (final state in set) {
      _enterState(state);
    }
    await _processMacroStep(null);
  }

  Future<void> _processMacroStep(E? event) async {
    _internalEventQueue.add(event);
    while (_internalEventQueue.isNotEmpty) {
      final eventlessTransition = await _selectEventlessTransition();
      if (eventlessTransition != null) {
        _processMicroStep(eventlessTransition);
      } else {
        final internalEvent = _internalEventQueue.removeFirst();
        final _EnabledTransition? transition;
        if (internalEvent != null) {
          transition = await _selectEventTransition(internalEvent);
          if (transition != null) {
            _processMicroStep(transition);
          }
        }
      }
    }
  }

  FutureOr<_EnabledTransition?> _selectEventlessTransition() async {
    final def = activeAtomicState;
    final transitions = _findStateAndAncestorsTransitionDefinitions(def);
    if (transitions.isEmpty) return null;
    for (final t in transitions.whereType<EventlessTransitionDefinition>()) {
      final target = await t.evaluate();
      if (target != null) {
        return _EnabledTransition(
          definition: t,
          source: def,
          target: _definition.getState(target),
          event: null,
        );
      }
    }
    return null;
  }

  FutureOr<_EnabledTransition?> _selectEventTransition(E event) async {
    final def = activeAtomicState;
    final transitions = _findStateAndAncestorsTransitionDefinitions(def);
    if (transitions.isEmpty) return null;
    for (final t in transitions.whereType<EventTransitionDefinition>()) {
      final target = await t.evaluate(event);
      if (target != null) {
        return _EnabledTransition(
          definition: t,
          source: def,
          target: _definition.getState(target),
          event: event,
        );
      }
    }
    return null;
  }

  List<TransitionDefinition> _findStateAndAncestorsTransitionDefinitions(
      StateDefinition d) {
    return [
      ...?d.transitions,
      ...d.ancestors().fold(
        [],
        (previousValue, element) => [...previousValue, ...?element.transitions],
      ),
    ];
  }

  void _processMicroStep(_EnabledTransition transition) {
    final lcca = _findLeastCommonCompoundAncestor(transition);
    final exitSet = _findExitSet(activeAtomicState, lcca);
    final entrySet = _findEntrySet(transition.target, lcca);

    for (final exitingState in exitSet) {
      _exitState(exitingState);
    }

    _executeTransition(transition);

    for (final enteringState in entrySet) {
      _enterState(enteringState);
    }

    if (_internalEventQueue.isEmpty || _internalEventQueue.last != null) {
      _internalEventQueue.add(null);
    }
  }

  List<StateDefinition> _findExitSet(
    StateDefinition activeState,
    StateDefinition? lcca,
  ) {
    return [
      activeState,
      ...activeState.ancestors().takeWhile((id) => id != lcca)
    ];
  }

  /// Find the least common compound ancestor (lcca). return null if the lcca is ROOT
  StateDefinition? _findLeastCommonCompoundAncestor(
    _EnabledTransition transition,
  ) {
    final activeState = activeAtomicState;
    if (activeState.isRoot) return null;

    final target = _definition.getState(transition.target.id);

    if (target.isRoot) return null;
    final targetAncestors = target.ancestors();

    return activeState
        .ancestors()
        .firstWhereOrNull((id) => targetAncestors.contains(id));
  }

  /// returns entry set in entry order (ancestor first)
  /// target's default children are added to the set too, until entry set
  /// end-up with an atomic state
  List<StateDefinition> _findEntrySet(
    StateDefinition target,
    StateDefinition? lcca,
  ) {
    final entrySet = [
      ...target.ancestors().takeWhile((id) => id != lcca).toList().reversed,
      target,
    ];
    StateDefinition child = target;
    while (child is CompoundState) {
      child = child.defaultState;
      entrySet.add(child);
    }
    assert(entrySet.last is AtomicState);
    return entrySet;
  }

  void _terminate() {
    for (final state in activeStates.reversed) {
      _exitState(_definition.getState(state));
    }
  }

  void _exitState(StateDefinition definition) {
    _activeStates.remove(definition.id);
    definition.onExit?.call();
  }

  void _executeTransition(_EnabledTransition transition) {
    switch (transition.definition) {
      case final EventTransitionDefinition definition:
        definition.executeSideEffect(transition.event);
      case final EventlessTransitionDefinition definition:
        definition.executeSideEffect();
    }
  }

  void _enterState(StateDefinition definition) {
    _activeStates.add(definition.id);
    definition.onEnter?.call();
  }
}
