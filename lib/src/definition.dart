import 'dart:async';

import 'package:collection/collection.dart';

typedef SideEffect = void Function();

typedef EventTransitionSideEffect<Event> = FutureOr<void> Function(Event event);

sealed class TransitionDefinition<StateID, Event> {
  const TransitionDefinition();
}

abstract class EventTransitionDefinition<StateID, Event>
    extends TransitionDefinition<StateID, Event> {
  EventTransitionDefinition({this.effect});

  final EventTransitionSideEffect<Event>? effect;

  FutureOr<StateID?> evaluate(Event receivedEvent);

  void executeSideEffect(Event event) {
    effect?.call(event);
  }
}

abstract class EventlessTransitionDefinition<StateID, Event>
    extends TransitionDefinition<StateID, Event> {
  const EventlessTransitionDefinition({this.effect});

  FutureOr<StateID?> evaluate();
  final SideEffect? effect;

  void executeSideEffect() {
    effect?.call();
  }
}

sealed class StateDefinition<StateID, Event> {
  StateDefinition<StateID, Event>? ancestor;

  final List<TransitionDefinition<StateID, Event>>? transitions;

  final StateID id;

  final SideEffect? onEnter;

  final SideEffect? onExit;

  StateDefinition({
    required this.id,
    this.onEnter,
    this.onExit,
    this.transitions,
  });

  bool get isRoot => ancestor == null;

  /// Return state's ancestors, from nearest to furthest.
  ///
  /// Immediate ancestor will be the first element of the list,
  /// and the furthest ancestor the last. If this state as no ancestor (is a child of ROOT)
  /// Then this method return an empty list
  List<StateDefinition<StateID, Event>> ancestors() {
    if (ancestor == null) return [];
    return [
      ancestor!,
      ...ancestor!.ancestors(),
    ];
  }

  Iterable<StateDefinition<StateID, Event>> flatten();

  @override
  bool operator ==(Object other) =>
      other is StateDefinition<StateID, Event> && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A leaf state
class AtomicState<StateID, Event> extends StateDefinition<StateID, Event> {
  AtomicState({
    required super.id,
    super.transitions,
    super.onEnter,
    super.onExit,
  });

  @override
  Iterable<StateDefinition<StateID, Event>> flatten() => [this];
}

/// A State that have sub-states
class CompoundState<StateID, Event> extends StateDefinition<StateID, Event> {
  CompoundState({
    required super.id,
    required this.substates,
    this.initial,
    super.transitions,
    super.onEnter,
    super.onExit,
  }) {
    for (final s in substates) {
      s.ancestor = this;
    }
  }

  /// The child id to enter by default, if no id is provided, first child in definition order will be selected
  ///
  /// When entering a Compound state, the state machine will also enter one of its children until it reach a leaf state.
  /// By default, the state machine select the first child state in document definition order.
  /// You can change this behavior by specifying the default child state's id
  final StateID? initial;
  final List<StateDefinition<StateID, Event>> substates;

  StateDefinition<StateID, Event> get defaultState {
    assert(() {
      return initial == null ||
          substates.firstWhereOrNull((element) => element.id == initial) !=
              null;
    }(), "State $id: initial provided but no child with matching id found");
    return initial != null
        ? substates.firstWhere((element) => element.id == initial)
        : substates.first;
  }

  @override
  Iterable<StateDefinition<StateID, Event>> flatten() => substates.fold(
        [this],
        (prev, e) => [...prev, ...e.flatten()],
      );
}

class StateMachineDefinition<StateID, Event> {
  factory StateMachineDefinition.flatten(
    Iterable<StateDefinition<StateID, Event>> states, {
    StateID? initial,
  }) {
    final Iterable<StateDefinition<StateID, Event>> flattenedStates =
        states.fold(
      [],
      (previousValue, def) => [
        ...previousValue,
        ...def.flatten(),
      ],
    );
    final stateMap = {
      for (final d in flattenedStates) d.id: d,
    };
    return StateMachineDefinition.fromMap(
      stateMap: stateMap,
      initial: initial ?? states.first.id,
    );
  }

  StateMachineDefinition.fromMap({
    required this.initial,
    required Map<StateID, StateDefinition<StateID, Event>> stateMap,
  }) : _states = stateMap;

  final StateID initial;

  StateDefinition<StateID, Event> getState(StateID id) => _states[id]!;

  final Map<StateID, StateDefinition<StateID, Event>> _states;
}
