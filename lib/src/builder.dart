import 'dart:async';

import 'package:scxml/src/processor.dart';

import 'definition.dart';

typedef EventTransitionCallback<S, E> = FutureOr<S?> Function(E event);
typedef EventlessTransitionCallback<S, E> = FutureOr<S?> Function();

class _EventTransitionImpl<S, E, E2 extends E>
    extends EventTransitionDefinition<S, E> {
  _EventTransitionImpl(
    this.callback, {
    required super.effect,
  });

  final EventTransitionCallback<S, E2> callback;

  @override
  FutureOr<S?> evaluate(final E receivedEvent) async {
    if (receivedEvent is E2) {
      return await callback(receivedEvent);
    } else {
      return null;
    }
  }
}

class _EventlessTransitionImpl<S, E>
    extends EventlessTransitionDefinition<S, E> {
  _EventlessTransitionImpl(
    this.callback, {
    required super.effect,
  });

  final EventlessTransitionCallback<S, E> callback;

  @override
  FutureOr<S?> evaluate() async {
    return await callback();
  }
}

class StateDefinitionBuilder<S, E> with _SubStateBuilder<S, E> {
  final S _id;

  StateDefinitionBuilder(this._id);

  final List<TransitionDefinition<S, E>> _transitions = [];

  SideEffect? _onEnter;
  SideEffect? _onExit;
  S? _initial;

  void terminate() {
    throw 0;
  }

  void initial(S initial) {
    _initial = initial;
  }

  void onEnter(SideEffect effect) {
    _onEnter = effect;
  }

  void onExit(SideEffect effect) {
    _onExit = effect;
  }

  void on<E2 extends E>(
    EventTransitionCallback<S, E2> callback, {
    EventTransitionSideEffect<E2>? effect,
  }) {
    _transitions.add(
      _EventTransitionImpl<S, E, E2>(
        callback,
        effect: effect != null ? (event) => effect(event as E2) : null,
      ),
    );
  }

  void when(
    EventlessTransitionCallback<S, E> condition, {
    SideEffect? effect,
  }) {
    _transitions.add(
      _EventlessTransitionImpl<S, E>(
        condition,
        effect: effect,
      ),
    );
  }

  StateDefinition<S, E> build() {
    final builtTransitions = _transitions;
    if (_subStates.isNotEmpty) {
      return CompoundState(
        initial: _initial,
        substates: _subStates.map((e) => e.build()).toList(),
        transitions: builtTransitions,
        onEnter: _onEnter,
        onExit: _onExit,
        id: _id,
      );
    } else {
      return AtomicState(
        transitions: builtTransitions,
        onEnter: _onEnter,
        onExit: _onExit,
        id: _id,
      );
    }
  }
}

mixin _SubStateBuilder<S, E> {
  final List<StateDefinitionBuilder<S, E>> _subStates = [];

  void state(
    S s, [
    void Function(StateDefinitionBuilder<S, E> builder)? delegate,
  ]) {
    final builder = StateDefinitionBuilder<S, E>(s);
    delegate?.call(builder);
    _subStates.add(builder);
  }
}

typedef StateMachineFactory<S, E> = StateMachineProcessor<S, E> Function(
    {S? initial});

/// A function that return a StateMachine definition.
///
/// Typically implemented by StateMachineBuilder. This allow the state machine
/// to be unopinionated about it must be constructed
typedef StateMachineDefinitionFactory<S, E> = StateMachineDefinition<S, E>
    Function({S? initial});

class StateMachine<S, E> extends StateMachineProcessor<S, E> {
  factory StateMachine(
      void Function(StateMachineBuilder<S, E> builder) updates) {
    final builder = StateMachineBuilder<S, E>();
    updates(builder);
    return StateMachine._(builder.build());
  }

  static StateMachineFactory<S, E> factory<S, E>(
      void Function(StateMachineBuilder<S, E> builder) updates) {
    final builder = StateMachineBuilder<S, E>();
    updates(builder);
    final builderFactory = builder.factory();
    return ({S? initial}) => StateMachine._(builderFactory(initial: initial));
  }

  StateMachine._(StateMachineDefinition<S, E> definition)
      : super(definition: definition);
}

class StateMachineBuilder<S, E> with _SubStateBuilder<S, E> {
  StateMachineBuilder();

  S? initial;

  StateMachineDefinition<S, E> build() => StateMachineDefinition.flatten(
        initial: initial,
        [
          for (final state in _subStates) state.build(),
        ],
      );

  StateMachineDefinitionFactory<S, E> factory() =>
      ({S? initial}) => StateMachineDefinition<S, E>.flatten(
            initial: initial ?? this.initial,
            [
              for (final state in _subStates) state.build(),
            ],
          );
}
