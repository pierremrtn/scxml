# SCXML
Implementation of a StateMachine following SCXML standard.

This implementation is unopinionated about how the state machine is constructed, meaning you can provides your own API to construct states machines.

This package already provides a builder based API to define SM.


You can uses any type object for StateID and Event.
The state machine processor uses `operator==`and `hashcode` to select state during transition, so you must implement them properly in your state object.