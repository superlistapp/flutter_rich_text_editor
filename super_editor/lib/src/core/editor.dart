import 'dart:math';

import 'package:attributed_text/attributed_text.dart';
import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:uuid/uuid.dart';

import 'document.dart';
import 'document_composer.dart';

/// Editor for a document editing experience.
///
/// An [Editor] is the entry point for all mutations within a document editing experience.
/// Such changes might impact a [Document], [DocumentComposer], and any other relevant objects
/// or data structures associated with a document editing experience.
///
/// The following artifacts are involved with making changes to pieces of a document editing
/// experience:
///
///  - [EditRequest] - a desired change.
///  - [EditCommand] - mutates [Editable]s to achieve a change.
///  - [EditEvent] - describes a change that was made.
///  - [EditReaction] - (optionally) requests more changes after some original change.
///  - [EditListener] - is notified of all changes made by an [Editor].
class Editor implements RequestDispatcher {
  static const Uuid _uuid = Uuid();

  /// Service locator key to obtain a [Document] from [find], if a [Document]
  /// is available in the [EditContext].
  static const documentKey = "document";

  /// Service locator key to obtain a [DocumentComposer] from [find], if a
  /// [DocumentComposer] is available in the [EditContext].
  static const composerKey = "composer";

  /// Service locator key to obtain a [DocumentLayoutEditable] from [find], if
  /// a [DocumentLayoutEditable] is available in the [EditContext].
  static const layoutKey = "layout";

  /// Generates a new ID for a [DocumentNode].
  ///
  /// Each generated node ID is universally unique.
  static String createNodeId() => _uuid.v4();

  /// Constructs an [Editor] with:
  ///  - [editables], which contains all artifacts that will be mutated by [EditCommand]s, such
  ///    as a [Document] and [DocumentComposer].
  ///  - [requestHandlers], which map each [EditRequest] to an [EditCommand].
  ///  - [reactionPipeline], which contains all possible [EditReaction]s in the order that they will
  ///    react.
  ///  - [listeners], which contains an initial set of [EditListener]s.
  Editor({
    required Map<String, Editable> editables,
    List<EditRequestHandler>? requestHandlers,
    this.historyGroupingPolicy = neverMergePolicy,
    List<EditReaction>? reactionPipeline,
    List<EditListener>? listeners,
    this.isHistoryEnabled = false,
  })  : requestHandlers = requestHandlers ?? [],
        reactionPipeline = reactionPipeline ?? [],
        _changeListeners = listeners ?? [] {
    context = EditContext(editables);
    _commandExecutor = _DocumentEditorCommandExecutor(context);
  }

  void dispose() {
    reactionPipeline.clear();
    _changeListeners.clear();
  }

  /// Chain of Responsibility that maps a given [EditRequest] to an [EditCommand].
  final List<EditRequestHandler> requestHandlers;

  /// Service Locator that provides all resources that are relevant for document editing.
  late final EditContext context;

  /// Whether history tracking (and undo/redo) are enabled.
  ///
  /// When [isHistoryEnabled] is `false`, undo/redo is disabled, calling [undo] and [redo]
  /// will have no effect, and [history] and [future] are always empty.
  final bool isHistoryEnabled;

  /// Policies that determine when a new transaction of changes should be combined with the
  /// previous transaction, impacting what is undone by undo.
  final HistoryGroupingPolicy historyGroupingPolicy;

  /// Executes [EditCommand]s and collects a list of changes.
  late final _DocumentEditorCommandExecutor _commandExecutor;

  /// A list of editor transactions that were run previously, leading to the current
  /// state of the document, and other editables.
  List<CommandTransaction> get history => List.from(_history);
  final _history = <CommandTransaction>[];

  /// A list of editor transactions that were undone since the last time a change was
  /// made.
  ///
  /// As soon as a new change is made through the editor, the [future] list is cleared
  /// out, because the editor no longer knows if the [future] changes can be applied
  /// to the document and other editables.
  List<CommandTransaction> get future => List.from(_future);
  final _future = <CommandTransaction>[];

  /// A pipeline of objects that receive change-lists from command execution
  /// and get the first opportunity to spawn additional commands before the
  /// change list is dispatched to regular listeners.
  final List<EditReaction> reactionPipeline;

  /// Listeners that are notified of changes in the form of a change list
  /// after all pending [EditCommand]s are executed, and all members of
  /// the reaction pipeline are done reacting.
  final List<EditListener> _changeListeners;

  /// Adds a [listener], which is notified of each series of [EditEvent]s
  /// after a batch of [EditCommand]s complete.
  ///
  /// Listeners are held and called as a list because some listeners might need
  /// to be notified ahead of others. Generally, you should avoid that complexity,
  /// if possible, but sometimes its relevant. For example, by default, the
  /// [Document] is the highest priority listener that's registered with this
  /// [Editor]. That's because document structure is central to everything
  /// else, and therefore, we don't want other parts of the system being notified
  /// about changes, before the [Document], itself.
  void addListener(EditListener listener, {int? index}) {
    if (index != null) {
      _changeListeners.insert(index, listener);
    } else {
      _changeListeners.add(listener);
    }
  }

  /// Removes a [listener] from the set of change listeners.
  void removeListener(EditListener listener) {
    _changeListeners.remove(listener);
  }

  /// An accumulation of changes during the current execution stack.
  ///
  /// This list is tracked in local state to facilitate reactions. When Reaction 1 runs,
  /// it might submit another request, which adds more changes. When Reaction 2 runs, that
  /// reaction needs to know about the original change list, plus all changes caused by
  /// Reaction 1. This list lives across multiple request executions to make that possible.
  List<EditEvent>? _activeChangeList;

  /// Tracks the number of request executions that are in the process of running.
  int _activeCommandCount = 0;

  bool _isInTransaction = false;
  bool _isImplicitTransaction = false;
  CommandTransaction? _transaction;

  /// Whether the editor is currently running reactions for the current transaction.
  bool _isReacting = false;

  /// Starts a transaction that runs across multiple calls to [execute], until [endTransaction]
  /// is called.
  ///
  /// Typically, a transaction only includes the [EditRequest]s that are passed to a single
  /// call to [execute]. That's useful in the nominal case where editing code knows everything
  /// that needs to execute at one time. However, sometimes the later [EditRequest] within a
  /// single transaction can't be configured until the editing code inspects the [Document]
  /// after some earlier [EditRequest]. In this situation, the editing code needs to be able
  /// to run [execute] multiple times while having all [EditRequest]s still considered to be
  /// part of the same transaction.
  ///
  /// Does nothing if a transaction is already in-progress.
  void startTransaction() {
    if (_isInTransaction) {
      return;
    }

    editorEditsLog.info("Starting transaction");
    _isInTransaction = true;
    _activeChangeList = <EditEvent>[];
    _transaction = CommandTransaction([], clock.now());

    _onTransactionStart();
  }

  /// Ends a transaction that was started with a call to [startTransaction].
  ///
  /// Does nothing if a transaction is not in-progress.
  void endTransaction() {
    if (!_isInTransaction) {
      return;
    }

    if (_transaction!.commands.isNotEmpty && isHistoryEnabled) {
      if (_history.isEmpty) {
        // Add this transaction onto the history stack.
        _history.add(_transaction!);
      } else {
        final mergeChoice = historyGroupingPolicy.shouldMergeLatestTransaction(_transaction!, _history.last);
        switch (mergeChoice) {
          case TransactionMerge.noOpinion:
          case TransactionMerge.doNotMerge:
            // Don't alter the transaction history, just add the new transaction to the history.
            _history.add(_transaction!);
          case TransactionMerge.mergeOnTop:
            // Merge this transaction with the transaction just before it. This is used, for example,
            // to group repeated text input into a single undoable transaction.
            _history.last
              ..commands.addAll(_transaction!.commands)
              ..changes.addAll(_transaction!.changes)
              ..lastChangeTime = clock.now();
          case TransactionMerge.replacePrevious:
            // Replaces the most recent transaction with the new transaction. This is used, for example,
            // to throw away unnecessary history about selection and composing region changes, for which
            // only the most recent value is relevant.
            _history
              ..removeLast()
              ..add(_transaction!);
        }
      }
    }

    // Now that an atomic set of changes have completed, let the reactions followup
    // with more changes, such as auto-correction, tagging, etc.
    _reactToChanges();

    _isInTransaction = false;
    _isImplicitTransaction = false;
    _transaction = null;

    // Note: The transaction isn't fully considered over until after the reactions run.
    // This is because the reactions need access to the change list from the previous
    // transaction.
    _onTransactionEnd();

    editorEditsLog.info("Finished transaction");
  }

  /// Executes the given [requests].
  ///
  /// Any changes that result from the given [requests] are reported to listeners as a series
  /// of [EditEvent]s.
  @override
  void execute(List<EditRequest> requests) {
    if (requests.isEmpty) {
      // No changes were requested. Don't waste time starting and ending transactions, etc.
      editorEditsLog.warning("Tried to execute requests without providing any requests");
      return;
    }

    editorEditsLog.finer("Executing requests:");
    for (final request in requests) {
      editorEditsLog.finer(" - ${request.runtimeType}");
    }

    if (_activeCommandCount == 0 && !_isInTransaction) {
      // No transaction was explicitly requested, but all changes exist in a transaction.
      // Automatically start one, and then end the transaction after the current changes.
      _isImplicitTransaction = true;
      startTransaction();
    }

    _activeCommandCount += 1;

    final undoableCommands = <EditCommand>[];
    for (final request in requests) {
      // Execute the given request.
      final command = _findCommandForRequest(request);
      final commandChanges = _executeCommand(command);
      _activeChangeList!.addAll(commandChanges);

      if (command.historyBehavior == HistoryBehavior.undoable) {
        undoableCommands.add(command);
        _transaction!.changes.addAll(List.from(commandChanges));
      }
    }

    // Log the time at the end of the actions in this transaction.
    _transaction!.lastChangeTime = clock.now();

    if (undoableCommands.isNotEmpty) {
      _transaction!.commands.addAll(undoableCommands);
    }

    if (_activeCommandCount == 1 && _isImplicitTransaction && !_isReacting) {
      endTransaction();
    }

    _activeCommandCount -= 1;
  }

  EditCommand _findCommandForRequest(EditRequest request) {
    EditCommand? command;
    for (final handler in requestHandlers) {
      command = handler(this, request);
      if (command != null) {
        return command;
      }
    }

    throw Exception(
        "Could not handle EditorRequest. DocumentEditor doesn't have a handler that recognizes the request: $request");
  }

  List<EditEvent> _executeCommand(EditCommand command) {
    // Execute the given command, and any other commands that it spawns.
    _commandExecutor.executeCommand(command);

    // Collect all the changes from the executed commands.
    //
    // We make a copy of the change-list so that asynchronous listeners
    // don't lose the contents when we clear it.
    final changeList = _commandExecutor.copyChangeList();

    // TODO: we could run the reactions here. Do we give them all a single chance
    //       to respond? Or do we keep running them until there aren't any further
    //       changes?

    // Reset the command executor so that it's ready for the next command
    // that comes in.
    _commandExecutor.reset();

    return changeList;
  }

  void _onTransactionStart() {
    for (final editable in context._resources.values) {
      editable.onTransactionStart();
    }
  }

  void _onTransactionEnd() {
    for (final editable in context._resources.values) {
      editable.onTransactionEnd(_activeChangeList!);
    }

    _activeChangeList = null;
  }

  void _reactToChanges() {
    if (_activeChangeList!.isEmpty) {
      return;
    }

    _isReacting = true;

    // First, let reactions modify the content of the active transaction.
    for (final reaction in reactionPipeline) {
      // Note: we pass the active change list because reactions will cause more
      // changes to be added to that list.
      reaction.modifyContent(context, this, _activeChangeList!);
    }

    // Second, start a new transaction and let reactions add separate changes.
    // ignore: prefer_const_constructors
    _transaction = CommandTransaction([], clock.now());
    for (final reaction in reactionPipeline) {
      // Note: we pass the active change list because reactions will cause more
      // changes to be added to that list.
      reaction.react(context, this, _activeChangeList!);
    }

    if (_transaction!.commands.isNotEmpty && isHistoryEnabled) {
      _history.add(_transaction!);
    }

    // FIXME: try removing this notify listeners
    // Notify all listeners that care about changes, but won't spawn additional requests.
    _notifyListeners(List<EditEvent>.from(_activeChangeList!, growable: false));

    _isReacting = false;
  }

  void undo() {
    if (!isHistoryEnabled) {
      // History is disabled, therefore undo/redo are disabled.
      return;
    }

    editorEditsLog.info("Running undo");
    if (_history.isEmpty) {
      return;
    }

    editorEditsLog.finer("History before undo:");
    for (final transaction in _history) {
      editorEditsLog.finer(" - transaction");
      for (final command in transaction.commands) {
        editorEditsLog.finer("   - ${command.runtimeType}: ${command.describe()}");
      }
    }
    editorEditsLog.finer("---");

    // Move the latest command from the history to the future.
    final transactionToUndo = _history.removeLast();
    _future.add(transactionToUndo);
    editorEditsLog.finer("The commands being undone are:");
    for (final command in transactionToUndo.commands) {
      editorEditsLog.finer("  - ${command.runtimeType}: ${command.describe()}");
    }

    editorEditsLog.finer("Resetting all editables to their last checkpoint...");
    for (final editable in context._resources.values) {
      // Don't let editables notify listeners during undo.
      editable.onTransactionStart();

      // Revert all editables to the last snapshot.
      editable.reset();
    }

    // Replay all history except for the most recent command transaction.
    editorEditsLog.finer("Replaying all command history except for the most recent transaction...");
    final changeEvents = <EditEvent>[];
    for (final commandTransaction in _history) {
      for (final command in commandTransaction.commands) {
        // We re-run the commands without tracking changes and without running reactions
        // because any relevant reactions should have run the first time around, and already
        // submitted their commands.
        final commandChanges = _executeCommand(command);
        changeEvents.addAll(commandChanges);
      }
    }

    editorEditsLog.info("Finished undo");

    editorEditsLog.finer("Ending transaction on all editables");
    for (final editable in context._resources.values) {
      // Let editables start notifying listeners again.
      editable.onTransactionEnd(changeEvents);
    }

    // TODO: find out why this is needed. If it's not, remove it.
    _notifyListeners([]);
  }

  void redo() {
    if (!isHistoryEnabled) {
      // History is disabled, therefore undo/redo are disabled.
      return;
    }

    editorEditsLog.info("Running redo");
    if (_future.isEmpty) {
      return;
    }

    editorEditsLog.finer("Future transaction:");
    for (final command in _future.last.commands) {
      editorEditsLog.finer(" - ${command.runtimeType}");
    }

    for (final editable in context._resources.values) {
      // Don't let editables notify listeners during redo.
      editable.onTransactionStart();
    }

    final commandTransaction = _future.removeLast();
    final edits = <EditEvent>[];
    for (final command in commandTransaction.commands) {
      final commandEdits = _executeCommand(command);
      edits.addAll(commandEdits);
    }
    _history.add(commandTransaction);

    editorEditsLog.info("Finished redo");

    editorEditsLog.finer("Ending transaction on all editables");
    for (final editable in context._resources.values) {
      // Let editables start notifying listeners again.
      editable.onTransactionEnd(edits);
    }

    // TODO: find out why this is needed. If it's not, remove it.
    _notifyListeners([]);
  }

  void _notifyListeners(List<EditEvent> changeList) {
    for (final listener in _changeListeners) {
      // Note: we pass a given copy of the change list, because listeners should
      // never cause additional editor changes.
      listener.onEdit(changeList);
    }
  }
}

/// The merge policies that are used in the standard [Editor] construction.
const defaultMergePolicy = HistoryGroupingPolicyList(
  [
    mergeRepeatSelectionChangesPolicy,
    mergeRapidTextInputPolicy,
  ],
);

abstract interface class HistoryGroupingPolicy {
  TransactionMerge shouldMergeLatestTransaction(
    CommandTransaction newTransaction,
    CommandTransaction previousTransaction,
  );
}

enum TransactionMerge {
  noOpinion,
  doNotMerge,
  mergeOnTop,
  replacePrevious;

  static TransactionMerge chooseMoreConservative(TransactionMerge a, TransactionMerge b) {
    if (a == b) {
      // They're the same. It doesn't matter.
      return a;
    }

    switch (a) {
      case TransactionMerge.noOpinion:
        // No opinion has no particular conservative vs liberal metric. Return the other one.
        return b;
      case TransactionMerge.doNotMerge:
        // Explicitly not merging is the most conservative. Return this one.
        return a;
      case TransactionMerge.mergeOnTop:
        if (b == TransactionMerge.doNotMerge) {
          // doNotMerge is the only more conservative choice than merging on top.
          return b;
        }

        return a;
      case TransactionMerge.replacePrevious:
        if (b == TransactionMerge.noOpinion) {
          return a;
        }

        // replacePrevious is the lease conservative option. The other one always wins.
        return b;
    }
  }
}

/// A [HistoryGroupingPolicy] that defers to a list of other individual policies.
///
/// For most applications, an [Editor]'s transaction grouping policy should probably be
/// a [HistoryGroupingPolicyList] because most applications will want a number of different
/// heuristics that decide when to merge transactions.
///
/// You can change the way the list of policies make a decision by way of the [choice]
/// property. You can either merge transactions when *any* of the policies want to merge
/// ([HistoryGroupingPolicyListChoice.anyPass]), or you can merge transactions when *all*
/// of the policies want to merge ([HistoryGroupingPolicyListChoice.allPass]).
class HistoryGroupingPolicyList implements HistoryGroupingPolicy {
  const HistoryGroupingPolicyList(this.policies);

  final List<HistoryGroupingPolicy> policies;

  @override
  TransactionMerge shouldMergeLatestTransaction(
    CommandTransaction newTransaction,
    CommandTransaction previousTransaction,
  ) {
    TransactionMerge mostConservativeChoice = TransactionMerge.noOpinion;

    for (final policy in policies) {
      final newMergeChoice = policy.shouldMergeLatestTransaction(newTransaction, previousTransaction);
      if (newMergeChoice == TransactionMerge.doNotMerge) {
        // A policy has explicitly requested not to merge. Don't merge.
        return TransactionMerge.doNotMerge;
      }

      mostConservativeChoice = TransactionMerge.chooseMoreConservative(mostConservativeChoice, newMergeChoice);
    }

    return mostConservativeChoice;
  }
}

const neverMergePolicy = _NeverMergePolicy();

class _NeverMergePolicy implements HistoryGroupingPolicy {
  const _NeverMergePolicy();

  @override
  TransactionMerge shouldMergeLatestTransaction(
          CommandTransaction newTransaction, CommandTransaction previousTransaction) =>
      TransactionMerge.doNotMerge;
}

const mergeRepeatSelectionChangesPolicy = MergeRepeatSelectionChangesPolicy();

class MergeRepeatSelectionChangesPolicy implements HistoryGroupingPolicy {
  const MergeRepeatSelectionChangesPolicy();

  @override
  TransactionMerge shouldMergeLatestTransaction(
      CommandTransaction newTransaction, CommandTransaction previousTransaction) {
    final isNewTransactionAllSelectionAndComposing = newTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .isEmpty;

    if (!isNewTransactionAllSelectionAndComposing) {
      // The new transaction contains meaningful changes. Let other policies decide
      // what to do.
      return TransactionMerge.noOpinion;
    }

    final isPreviousTransactionAllSelectionAndComposing = previousTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .isEmpty;

    if (!isPreviousTransactionAllSelectionAndComposing) {
      // The previous transaction contains meaningful changes. Add the new selection/composing
      // changes on top so that they're undone with the previous content change.
      return TransactionMerge.mergeOnTop;
    }

    // The previous and new transactions are all selection and composing changes. We don't
    // care about this history. Replaces the previous transaction with the new transaction.
    return TransactionMerge.replacePrevious;
  }
}

/// A sane default configuration of a [MergeRapidTextInputPolicy].
///
/// To customize the merge time, create a [MergeRapidTextInputPolicy] with the desired merge time.
const mergeRapidTextInputPolicy = MergeRapidTextInputPolicy();

class MergeRapidTextInputPolicy implements HistoryGroupingPolicy {
  const MergeRapidTextInputPolicy([this._maxMergeTime = const Duration(milliseconds: 100)]);

  final Duration _maxMergeTime;

  @override
  TransactionMerge shouldMergeLatestTransaction(
      CommandTransaction newTransaction, CommandTransaction previousTransaction) {
    final newContentEvents = newTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .toList();
    if (newContentEvents.isEmpty) {
      return TransactionMerge.noOpinion;
    }
    final newTextInsertionEvents =
        newContentEvents.where((change) => change is DocumentEdit && change.change is TextInsertionEvent).toList();
    if (newTextInsertionEvents.length != newContentEvents.length) {
      // There were 1+ new content changes that weren't text input. Don't merge transactions.
      return TransactionMerge.noOpinion;
    }

    // At this point we know that all new content changes were text input.

    // Check that the previous transaction was also all text input.
    final previousContentEvents = previousTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .toList();
    if (previousContentEvents.isEmpty) {
      return TransactionMerge.noOpinion;
    }
    final previousTextInsertionEvents =
        previousContentEvents.where((change) => change is DocumentEdit && change.change is TextInsertionEvent).toList();
    if (previousTextInsertionEvents.length != previousContentEvents.length) {
      // There were 1+ new content changes that weren't text input. Don't merge transactions.
      return TransactionMerge.noOpinion;
    }

    if (newTransaction.firstChangeTime.difference(previousTransaction.lastChangeTime) > _maxMergeTime) {
      // The text insertions were far enough apart in time that we don't want to merge them.
      return TransactionMerge.noOpinion;
    }

    // The new and previous transactions were entirely text input. They happened quickly.
    // Merge them together.
    return TransactionMerge.mergeOnTop;
  }
}

class CommandTransaction {
  CommandTransaction(this.commands, this.firstChangeTime)
      : changes = <EditEvent>[],
        lastChangeTime = firstChangeTime;

  final List<EditCommand> commands;
  final List<EditEvent> changes;

  final DateTime firstChangeTime;
  DateTime lastChangeTime;
}

/// An implementation of [CommandExecutor], designed for [Editor].
class _DocumentEditorCommandExecutor implements CommandExecutor {
  _DocumentEditorCommandExecutor(this._context);

  final EditContext _context;

  final _commandsBeingProcessed = EditorCommandQueue();

  final _changeList = <EditEvent>[];
  List<EditEvent> copyChangeList() => List.from(_changeList);

  @override
  void executeCommand(EditCommand command) {
    _commandsBeingProcessed.append(command);

    // Run the given command, and any other commands that it spawns.
    while (_commandsBeingProcessed.hasCommands) {
      _commandsBeingProcessed.prepareForExecution();

      final command = _commandsBeingProcessed.activeCommand!;
      command.execute(_context, this);

      _commandsBeingProcessed.onCommandExecutionComplete();
    }
  }

  @override
  void prependCommand(EditCommand command) {
    _commandsBeingProcessed.prepend(command);
  }

  @override
  void appendCommand(EditCommand command) {
    _commandsBeingProcessed.append(command);
  }

  @override
  void logChanges(List<EditEvent> changes) {
    _changeList.addAll(changes);
  }

  void reset() {
    _changeList.clear();
  }
}

/// An artifact that might be mutated during a request to a [Editor].
abstract mixin class Editable {
  /// A [Editor] transaction just started, this [Editable] should avoid notifying
  /// any listeners of changes until the transaction ends.
  void onTransactionStart() {}

  /// A transaction that was previously started with [onTransactionStart] has now ended, this
  /// [Editable] should notify interested parties of changes.
  void onTransactionEnd(List<EditEvent> edits) {}

  // /// Creates and returns a snapshot of this [Editable]'s current state, or `null` if
  // /// this [Editable] is in its initial state.
  // ///
  // /// The returned snapshot must be a deep copy of any relevant information. It must not
  // /// hold any references to data outside the snapshot.
  // Object? createSnapshot();
  //
  // /// Updates the state of this [Editable] to match the given [snapshot].
  // void restoreSnapshot(Object snapshot);

  /// Resets this [Editable] to its initial state.
  void reset() {}
}

/// An object that processes [EditRequest]s.
abstract class RequestDispatcher {
  /// Pushes the given [requests] through a [Editor] pipeline.
  void execute(List<EditRequest> requests);
}

/// A command that alters something in a [Editor].
abstract class EditCommand {
  const EditCommand();

  /// Executes this command and logs all changes with the [executor].
  void execute(EditContext context, CommandExecutor executor);

  /// The desired "undo" behavior of this command.
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  String describe() => toString();
}

/// The way a command interacts with the history ledger, AKA "undo".
enum HistoryBehavior {
  /// The command can be undone and redone.
  ///
  /// For example: inserting text into a paragraph.
  undoable,

  /// The command has no impact on history.
  ///
  /// For example: entering and exiting interaction mode, (possibly) activating and
  /// deactivating bold/italics in the composer.
  nonHistorical,
}

/// All resources that are available when executing [EditCommand]s, such as a document,
/// composer, etc.
class EditContext {
  EditContext(this._resources);

  final Map<String, Editable> _resources;

  /// Finds an object of type [T] within this [EditContext], which is identified by the given [id].
  T find<T extends Editable>(String id) {
    if (!_resources.containsKey(id)) {
      editorLog.shout("Tried to find an editor resource for the ID '$id', but there's no resource with that ID.");
      throw Exception("Tried to find an editor resource for the ID '$id', but there's no resource with that ID.");
    }
    if (_resources[id] is! T) {
      editorLog.shout(
          "Tried to find an editor resource of type '$T' for ID '$id', but the resource with that ID is of type '${_resources[id].runtimeType}");
      throw Exception(
          "Tried to find an editor resource of type '$T' for ID '$id', but the resource with that ID is of type '${_resources[id].runtimeType}");
    }

    return _resources[id] as T;
  }

  /// Finds an object of type [T] within this [EditContext], which is identified by the given [id], or
  /// returns `null` if no such object is in this [EditContext].
  T? findMaybe<T extends Editable>(String id) {
    if (_resources[id] == null) {
      return null;
    }

    if (_resources[id] is! T) {
      editorLog.shout(
          "Tried to find an editor resource of type '$T' for ID '$id', but the resource with that ID is of type '${_resources[id].runtimeType}");
      throw Exception(
          "Tried to find an editor resource of type '$T' for ID '$id', but the resource with that ID is of type '${_resources[id].runtimeType}");
    }

    return _resources[id] as T;
  }

  /// Makes the given [editable] available as a resource under the given [id].
  void put(String id, Editable editable) => _resources[id] = editable;

  /// Removes any resource in this context with the given [id].
  void remove(String id) => _resources.remove(id);
}

/// Executes [EditCommand]s in the order in which they're queued.
///
/// Each [EditCommand] is given access to this [CommandExecutor] during
/// the command's execution. Each [EditCommand] is expected to [logChanges]
/// with the given [CommandExecutor].
abstract class CommandExecutor {
  /// Immediately executes the given [command].
  ///
  /// Client's can use this method to run an initial command, or to run
  /// a sub-command in the middle of an active command.
  void executeCommand(EditCommand command);

  /// Adds the given [command] to the beginning of the command queue, but
  /// after any set of commands that are currently executing.
  void prependCommand(EditCommand command);

  /// Adds the given [command] to the end of the command queue.
  void appendCommand(EditCommand command);

  /// Log a series of document changes that were just made by the active command.
  void logChanges(List<EditEvent> changes);
}

class EditorCommandQueue {
  /// A command that's in the process of being executed.
  EditCommand? _activeCommand;

  /// The command that's currently being executed, along with any commands
  /// that the active command adds during execution.
  final _activeCommandExpansionQueue = <EditCommand>[];

  /// All commands waiting to be executed after [_activeCommandExpansionQueue].
  final _commandBacklog = <EditCommand>[];

  bool get hasCommands => _commandBacklog.isNotEmpty;

  void prepareForExecution() {
    assert(_activeCommandExpansionQueue.isEmpty,
        "Tried to prepare for command execution but there are already commands in the active queue. Did you forget to call onCommandExecutionComplete?");

    // Set the active command to the next command in the backlog.
    _activeCommand = _commandBacklog.removeAt(0);
  }

  EditCommand? get activeCommand => _activeCommand;

  void expandActiveCommand(List<EditCommand> additionalCommands) {
    _activeCommandExpansionQueue.addAll(additionalCommands);
  }

  void onCommandExecutionComplete() {
    // Now that the active command is done, move any expansion commands
    // to the primary backlog.
    _commandBacklog.insertAll(0, _activeCommandExpansionQueue);
    _activeCommandExpansionQueue.clear();

    // Clear the active command, now that its complete.
    _activeCommand = null;
  }

  /// Prepends the given [command] at the front of the execution queue.
  void prepend(EditCommand command) {
    _commandBacklog.insert(0, command);
  }

  /// Appends the given [command] to the end of the execution queue.
  void append(EditCommand command) {
    _commandBacklog.add(command);
  }
}

/// Factory method that creates and returns an [EditCommand] that can handle
/// the given [EditRequest], or `null` if this handler doesn't apply to the given
/// [EditRequest].
typedef EditRequestHandler = EditCommand? Function(Editor editor, EditRequest request);

/// An action that a [Editor] should execute.
abstract class EditRequest {
  // Marker interface for all editor request types.
}

/// A change that took place within a [Editor].
abstract class EditEvent {
  const EditEvent();

  /// Describes this change in a human-readable way.
  String describe() => toString();
}

/// An [EditEvent] that altered a [Document].
///
/// The specific [Document] change is available in [change].
class DocumentEdit extends EditEvent {
  DocumentEdit(this.change);

  final DocumentChange change;

  @override
  String describe() => change.describe();

  @override
  String toString() => "DocumentEdit -> $change";

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DocumentEdit && runtimeType == other.runtimeType && change == other.change;

  @override
  int get hashCode => change.hashCode;
}

/// An object that's notified with a change list from one or more commands that were just
/// executed.
///
/// An [EditReaction] can use the given [reactionExecutor] to spawn additional [EditCommand]s
/// that should run in response to the [changeList].
abstract class EditReaction {
  const EditReaction();

  /// Executes additional [modifications] within the current editor transaction.
  ///
  /// If undo is run, the recent changes AND the [modifications] will be undone, together.
  /// This is useful, for example, for a reaction such as spell-check, whose reaction is
  /// tied directly to the content and shouldn't stand on its own.
  ///
  /// To execute actions that are undone on their own, use [react].
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {}

  /// Executes additional [actions] in a new standalone transaction.
  ///
  /// If undo is run, these changes will be undone, but the changes leading up to this
  /// call to [react] will not be undone by that undo call.
  ///
  /// To execute additional actions that are undone at the same time as the preceding
  /// changes, use [modifyContent].
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {}
}

/// An [EditReaction] that delegates its reaction to a given callback function.
class FunctionalEditReaction extends EditReaction {
  FunctionalEditReaction({
    Reaction? modifyContent,
    Reaction? react,
  })  : _modifyContent = modifyContent,
        _react = react,
        assert(modifyContent != null || react != null);

  final Reaction? _modifyContent;
  final Reaction? _react;

  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) =>
      _modifyContent?.call(editorContext, requestDispatcher, changeList);

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) =>
      _react?.call(editorContext, requestDispatcher, changeList);
}

typedef Reaction = void Function(
    EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList);

/// An object that's notified with a change list from one or more
/// commands that were just executed within a [Editor].
///
/// An [EditListener] can propagate secondary effects that are based on
/// editor changes. However, an [EditListener] shouldn't spawn additional
/// editor behaviors. This can result in infinite loops, back-and-forth changes,
/// and other undesirable effects. To spawn new [EditCommand]s based on a
/// [changeList], register an [EditReaction].
abstract class EditListener {
  void onEdit(List<EditEvent> changeList);
}

/// An [EditListener] that delegates to a callback function.
class FunctionalEditListener implements EditListener {
  FunctionalEditListener(this._onEdit);

  final void Function(List<EditEvent> changeList) _onEdit;

  @override
  void onEdit(List<EditEvent> changeList) => _onEdit(changeList);
}

/// Extensions that provide direct, type-safe access to [Editable]s that are
/// expected to exist in all [Editor]s.
///
/// This extension is similar to [StandardEditablesInContext], except this extension
/// operates on an [Editor] and the other operates on [EditContext]s. Both exist
/// for convenience.
extension StandardEditables on Editor {
  /// Finds and returns the [MutableDocument] within the [Editor].
  MutableDocument get document => context.find<MutableDocument>(Editor.documentKey);

  /// Finds and returns the [MutableDocument] within the [Editor], or `null` if no [MutableDocument]
  /// is in the [Editor].
  MutableDocument? get maybeDocument => context.findMaybe<MutableDocument>(Editor.documentKey);

  /// Finds and returns the [MutableDocumentComposer] within the [Editor].
  MutableDocumentComposer get composer => context.find<MutableDocumentComposer>(Editor.composerKey);

  /// Finds and returns the [MutableDocumentComposer] within the [Editor], or `null` if no
  /// [MutableDocumentComposer] is in the [Editor].
  MutableDocumentComposer? get maybeComposer => context.findMaybe<MutableDocumentComposer>(Editor.composerKey);
}

/// Extensions that provide direct, type-safe access to [Editable]s that are
/// expected to exist in all [EditContext]s.
///
/// This extension is similar to [StandardEditables], except this extension
/// operates on an [EditContext] and the other operates on [Editor]s. Both exist
/// for convenience.
extension StandardEditablesInContext on EditContext {
  /// Finds and returns the [MutableDocument] within the [EditContext].
  MutableDocument get document => find<MutableDocument>(Editor.documentKey);

  /// Finds and returns the [MutableDocument] within the [EditContext], or `null` if no [MutableDocument]
  /// is in the [EditContext].
  MutableDocument? get maybeDocument => findMaybe<MutableDocument>(Editor.documentKey);

  /// Finds and returns the [MutableDocumentComposer] within the [EditContext].
  MutableDocumentComposer get composer => find<MutableDocumentComposer>(Editor.composerKey);

  /// Finds and returns the [MutableDocumentComposer] within the [EditContext], or `null` if no
  /// [MutableDocumentComposer] is in the [EditContext].
  MutableDocumentComposer? get maybeComposer => findMaybe<MutableDocumentComposer>(Editor.composerKey);
}

/// An in-memory, mutable [Document].
class MutableDocument with Iterable<DocumentNode> implements Document, Editable {
  /// Creates an in-memory, mutable version of a [Document].
  ///
  /// Initializes the content of this [MutableDocument] with the given [nodes],
  /// if provided, or empty content otherwise.
  MutableDocument({
    List<DocumentNode>? nodes,
  }) : _nodes = nodes ?? [] {
    _refreshNodeIdCaches();

    _latestNodesSnapshot = List.from(_nodes);
  }

  /// Creates an [Document] with a single [ParagraphNode].
  ///
  /// Optionally, takes in a [nodeId] for the [ParagraphNode].
  factory MutableDocument.empty([String? nodeId]) {
    return MutableDocument(
      nodes: [
        ParagraphNode(
          id: nodeId ?? Editor.createNodeId(),
          text: AttributedText(),
        ),
      ],
    );
  }

  void dispose() {
    _listeners.clear();
  }

  late final List<DocumentNode> _latestNodesSnapshot;
  bool _didReset = false;

  final List<DocumentNode> _nodes;

  @override
  int get nodeCount => _nodes.length;

  @override
  bool get isEmpty => _nodes.isEmpty;

  /// Maps a node id to its index in the node list.
  final Map<String, int> _nodeIndicesById = {};

  /// Maps a node id to its node.
  final Map<String, DocumentNode> _nodesById = {};

  final _listeners = <DocumentChangeListener>[];

  @override
  Iterator<DocumentNode> get iterator => _nodes.iterator;

  @override
  DocumentNode? get firstOrNull => _nodes.firstOrNull;

  @override
  DocumentNode? get lastOrNull => _nodes.lastOrNull;

  @override
  DocumentNode? getNodeById(String nodeId) {
    return _nodesById[nodeId];
  }

  @override
  DocumentNode? getNodeAtPath(NodePath path) {
    return _nodesById[path.targetNodeId];
  }

  @override
  int getNodeIndexInParent(String nodeId) {
    final nodePath = getPathByNodeId(nodeId)!;
    if (nodePath.depth == 0) {
      // This is a root node. Return its index in the root list.
      return _nodes.indexWhere((node) => node.id == nodeId);
    }

    // This node has a parent. Find the parent and then find the child index.
    final parentNodeId = nodePath.atDepth(nodePath.depth - 1);
    final parentNode = getNodeById(parentNodeId)!;
    return (parentNode as CompositeDocumentNode).nodes.toList().indexWhere((node) => node.id == nodeId);
  }

  @override
  NodePath? getPathByNodeId(String nodeId) {
    // FIXME: Instead of crawling the tree every call, create a cache that takes
    //        a node ID as the key, and holds each node's path as the value.

    final queue = <(NodePath, List<DocumentNode>)>[
      (const NodePath([]), [..._nodes])
    ];
    while (queue.isNotEmpty) {
      final (parentNodePath, children) = queue.removeAt(0);

      for (final child in children) {
        if (child.id == nodeId) {
          // This `child` is the node we're searching for. It's path is its
          // parent path + itself.
          return parentNodePath.addSubPath(nodeId);
        }

        if (child is CompositeDocumentNode) {
          // This child might also have children. Add them to the visit queue.
          queue.add((parentNodePath.addSubPath(nodeId), [...child.nodes]));
        }
      }
    }

    // We never found the node.
    return null;
  }

  @override
  DocumentNode? getNodeAt(int index) {
    if (index < 0 || index >= _nodes.length) {
      return null;
    }

    return _nodes[index];
  }

  @override
  @Deprecated("Use getNodeIndexById() instead")
  int getNodeIndex(DocumentNode node) {
    final index = _nodeIndicesById[node.id] ?? -1;
    if (index < 0) {
      return -1;
    }

    if (_nodes[index] != node) {
      // We found a node by id, but it wasn't the node we expected. Therefore, we couldn't find the requested node.
      return -1;
    }

    return index;
  }

  @override
  int getNodeIndexById(String nodeId) {
    return _nodeIndicesById[nodeId] ?? -1;
  }

  @override
  DocumentNode? getNodeBefore(DocumentNode node) {
    return getNodeBeforeById(node.id);
  }

  @override
  DocumentNode? getNodeBeforeById(String nodeId) {
    final nodeIndex = getNodeIndexById(nodeId);
    return nodeIndex > 0 ? getNodeAt(nodeIndex - 1) : null;
  }

  @override
  DocumentNode? getNodeAfter(DocumentNode node) {
    return getNodeAfterById(node.id);
  }

  @override
  DocumentNode? getNodeAfterById(String nodeId) {
    final nodeIndex = getNodeIndexById(nodeId);
    return nodeIndex >= 0 && nodeIndex < _nodes.length - 1 ? getNodeAt(nodeIndex + 1) : null;
  }

  @override
  DocumentNode? getNode(DocumentPosition position) => getNodeById(position.documentPath.targetNodeId);

  @override
  List<DocumentNode> getNodesInside(DocumentPosition position1, DocumentPosition position2) {
    final node1 = getNode(position1);
    if (node1 == null) {
      throw Exception('No such position in document: $position1');
    }
    final index1 = getNodeIndexById(node1.id);

    final node2 = getNode(position2);
    if (node2 == null) {
      throw Exception('No such position in document: $position2');
    }
    final index2 = getNodeIndexById(node2.id);

    final from = min(index1, index2);
    final to = max(index1, index2);

    return _nodes.sublist(from, to + 1);
  }

  /// Inserts the given [node] into the [Document] at the given [index].
  void insertNodeAt(int index, DocumentNode node) {
    if (index <= _nodes.length) {
      _nodes.insert(index, node);
      _refreshNodeIdCaches();
    }
  }

  /// Inserts [newNode] immediately before the given [existingNode].
  void insertNodeBefore({
    required String existingNodeId,
    required DocumentNode newNode,
  }) {
    final nodeIndex = getNodeIndexById(existingNodeId);
    _nodes.insert(nodeIndex, newNode);
    _refreshNodeIdCaches();
  }

  /// Inserts [newNode] immediately after the given [existingNode].
  void insertNodeAfter({
    required String existingNodeId,
    required DocumentNode newNode,
  }) {
    final nodeIndex = getNodeIndexById(existingNodeId);
    if (nodeIndex >= 0 && nodeIndex < _nodes.length) {
      _nodes.insert(nodeIndex + 1, newNode);
      _refreshNodeIdCaches();
    }
  }

  /// Adds [node] to the end of the document.
  void add(DocumentNode node) {
    _nodes.insert(_nodes.length, node);

    // The node list changed, we need to update the map to consider the new indices.
    _refreshNodeIdCaches();
  }

  /// Deletes the node at the given [index].
  void deleteNodeAt(int index) {
    if (index >= 0 && index < _nodes.length) {
      _nodes.removeAt(index);
      _refreshNodeIdCaches();
    } else {
      editorDocLog.warning('Could not delete node. Index out of range: $index');
    }
  }

  /// Deletes the given [node] from the [Document].
  bool deleteNode(String nodeId) {
    bool isRemoved = false;

    final index = getNodeIndexById(nodeId);
    if (index < 0) {
      return false;
    }

    _nodes.removeAt(index);
    _refreshNodeIdCaches();

    return isRemoved;
  }

  /// Deletes all nodes from the [Document].
  void clear() {
    _nodes.clear();
    _refreshNodeIdCaches();
  }

  /// Moves a [DocumentNode] matching the given [nodeId] from its current index
  /// in the [Document] to the given [targetIndex].
  ///
  /// If none of the nodes in this document match [nodeId], throws an error.
  void moveNode({required String nodeId, required int targetIndex}) {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw Exception('Could not find node with nodeId: $nodeId');
    }

    if (_nodes.remove(node)) {
      _nodes.insert(targetIndex, node);
      _refreshNodeIdCaches();
    }
  }

  /// Replaces the given [oldNode] with the given [newNode]
  @Deprecated("Use replaceNodeById() instead")
  void replaceNode({
    required DocumentNode oldNode,
    required DocumentNode newNode,
  }) {
    final index = _nodes.indexOf(oldNode);

    if (index >= 0) {
      _nodes.removeAt(index);
      _nodes.insert(index, newNode);
      _refreshNodeIdCaches();
    } else {
      throw Exception('Could not find oldNode: ${oldNode.id}');
    }
  }

  /// Replaces the node with the given [nodeId] with the given [newNode].
  ///
  /// Throws an exception if no node exists with the given [nodeId].
  void replaceNodeById(
    String nodeId,
    DocumentNode newNode,
  ) {
    final index = getNodeIndexById(nodeId);

    if (index >= 0) {
      _nodes.removeAt(index);
      _nodes.insert(index, newNode);
      _refreshNodeIdCaches();
    } else {
      throw Exception('Could not find node with ID: $nodeId');
    }
  }

  /// Returns [true] if the content of the [other] [Document] is equivalent
  /// to the content of this [Document].
  ///
  /// Content equivalency compares types of content nodes, and the content
  /// within them, like the text of a paragraph, but ignores node IDs and
  /// ignores the runtime type of the [Document], itself.
  @override
  bool hasEquivalentContent(Document other) {
    if (_nodes.length != other.nodeCount) {
      return false;
    }
    if (isEmpty) {
      // Both documents are empty, and therefore are equivalent.
      return true;
    }

    DocumentNode? thisDocNode = first;
    DocumentNode? otherDocNode = other.first;

    while (thisDocNode != null && otherDocNode != null) {
      if (!thisDocNode.hasEquivalentContent(otherDocNode)) {
        return false;
      }

      thisDocNode = getNodeAfter(thisDocNode);
      otherDocNode = other.getNodeAfter(otherDocNode);
    }

    return true;
  }

  @override
  void addListener(DocumentChangeListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(DocumentChangeListener listener) {
    _listeners.remove(listener);
  }

  @override
  void onTransactionStart() {
    // no-op
  }

  @override
  void onTransactionEnd(List<EditEvent> edits) {
    final documentChanges = edits.whereType<DocumentEdit>().map((edit) => edit.change).toList();
    if (documentChanges.isEmpty && !_didReset) {
      return;
    }
    _didReset = false;

    final changeLog = DocumentChangeLog(documentChanges);
    for (final listener in _listeners) {
      listener(changeLog);
    }
  }

  @override
  void reset() {
    _nodes
      ..clear()
      ..addAll(_latestNodesSnapshot);
    _refreshNodeIdCaches();

    _didReset = true;
  }

  /// Updates all the maps which use the node id as the key.
  ///
  /// All the maps are cleared and re-populated.
  void _refreshNodeIdCaches() {
    _nodeIndicesById.clear();
    _nodesById.clear();
    for (int i = 0; i < _nodes.length; i++) {
      final node = _nodes[i];
      _nodeIndicesById[node.id] = i;
      _nodesById[node.id] = node;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutableDocument &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(_nodes, other._nodes);

  @override
  int get hashCode => _nodes.hashCode;
}
