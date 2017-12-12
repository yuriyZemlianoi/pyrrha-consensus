pragma solidity ^0.4.15;

import './INode.sol';
import '../pandora/IPandora.sol';
import '../jobs/IJob.sol';
import {StateMachineLib as SM} from '../libraries/StateMachineLib.sol';

/**
 * @title Worker Node Smart Contract
 * @author "Dr Maxim Orlovsky" <orlovsky@pandora.foundation>
 *
 * @dev # Worker Node Smart Contract
 *
 * Worker node contract accumulates funds/payments for performed cognitive work and contains inalienable reputation.
 * Note: In Pyrrha there is no mining. In the following versions all mined coins will be also assigned to the
 * `WorkerNode` contract
 *
 * Worker node acts as a state machine and each its function can be evoked only in some certain states. That's
 * why each function must have state machine-controlled function modifiers. Contract state is managed by
 * - Worker node code (second level of consensus)
 * - Main Pandora contract [Pandora.sol]
 * - Worker node contract itself
 */

contract WorkerNode is IWorkerNode /* final */ {
    /**
     * ## State Machine implementation
     */

    using SM for SM.StateMachine;

    /// @dev Structure holding the state of the contract
    SM.StateMachine internal stateMachine;

    event StateChanged(uint8 oldState, uint8 newState);

    /// @notice Returns current state of the contract state machine
    /// @dev Shortcut to receive current state from external contracts
    function currentState() public constant returns (
        uint8 /// Current state
    ) {
        return stateMachine.currentState;
    }

    /// @dev State transition function from StateMachineLib put into modifier form.
    /// **Important:** state transition happens _after_ the main code of the calling function.
    modifier transitionToState(
        uint8 _newState /// New state to transition into
    ) {
        uint8 oldState = stateMachine.currentState;
        stateMachine.transitionToState(_newState);
        _;
        stateMachine.currentState = _newState;
        StateChanged(oldState, stateMachine.currentState);
    }

    /// @dev State transition function from StateMachineLib put into modifier form.
    /// **Important:** state transition happens _before_ the main code of the calling function, and _after_ the
    /// execution contract is returned to the original state.
    modifier transitionThroughState(
        uint8 _transitionState /// Intermediary state to transition through
    ) {
        var initialState = stateMachine.currentState;
        stateMachine.transitionThroughState(_transitionState);
        StateChanged(initialState, stateMachine.currentState);
        _;
        stateMachine.currentState = initialState;
        StateChanged(_transitionState, stateMachine.currentState);
    }

    /// @dev Modifier requiring contract to be present in certain state; otherwise the exception is generated and the
    /// function does not execute
    modifier requireState(
        uint8 _requiredState /// Required state
    ) {
        require(stateMachine.currentState == _requiredState);
        _;
    }

    /// @dev Modifier requiring contract to be present in one of two certain states; otherwise an exception is
    /// generated and the function does not execute
    modifier requireStates2(
        uint8 _requiredState1, /// Required state, option 1
        uint8 _requiredState2 /// Required state, option 2
    ) {
        stateMachine.requireStates2(_requiredState1, _requiredState2);
        _;
    }

    /// @dev Modifier requiring contract to be preset in one of the active states (`Assigned`, `ReadyForDataValidation`,
    /// `ValidatingData`, `ReadyForComputing`, `Computing`); otherwise an exception is generated and the function
    /// does not execute
    modifier requireActiveStates() {
        require(stateMachine.currentState == Assigned ||
        stateMachine.currentState == ReadyForDataValidation ||
        stateMachine.currentState == ValidatingData ||
        stateMachine.currentState == ReadyForComputing ||
        stateMachine.currentState == Computing);
        _;
    }

    /// @dev Private method initializing state machine. Must be called only once from the contract constructor
    function _initStateMachine() private /* onlyOnce */ {
        // Creating table of possible state transitions
        var transitions = stateMachine.transitionTable;
        transitions[Uninitialized] = [Idle, Offline, InsufficientStake];
        transitions[Offline] = [InsufficientStake, Idle];
        transitions[Idle] = [Offline, InsufficientStake, UnderPenalty, Assigned, Destroyed];
        transitions[Assigned] = [Offline, InsufficientStake, UnderPenalty, ReadyForDataValidation];
        transitions[ReadyForDataValidation] = [ValidatingData, Offline, UnderPenalty, InsufficientStake, Idle];
        transitions[UnderPenalty] = [InsufficientStake, Idle];
        transitions[ValidatingData] = [Idle, UnderPenalty, ReadyForComputing];
        transitions[ReadyForComputing] = [Computing, Offline, UnderPenalty, InsufficientStake, Idle];
        transitions[Computing] = [UnderPenalty, Idle];

        // Initializing state machine via library code
        stateMachine.initStateMachine();

        // Going into initial state (Offline)
        stateMachine.currentState = Offline;
    }

    /**
     * ## Main implementation
     */

    /// ### Public variables


    /// @notice Reference to the main Pandora contract.
    /// @dev Required to check the validity of the method calls coming from the Pandora contract.
    /// Initialy set from the address supplied to the constructor and can't be changed after.
    IPandora public pandora;

    /// @notice Active cognitive job reference. Zero when there is no active cognitive job assigned or performed
    /// @dev Valid (non-zero) only for active states (see `activeStates` modified for the list of such states)
    ICognitiveJob public activeJob;

    /// @notice Current worker node reputation. Can be changed only by the main Pandora contract via special
    /// external function calls
    /// @dev Reputation can't be transferred or bought.
    uint256 public reputation;

    event WorkerDestroyed();

    /// ### Constructor and destructor

    function WorkerNode (
        IPandora _pandora /// Reference to the main Pandora contract that creates Worker Node
    )
    public {
        require(_pandora != address(0));
        pandora = _pandora;

        // Initial reputation is always zero
        reputation = 0;

        // There should be no active cognitive job upon contract creation
        activeJob = ICognitiveJob(0);

        // Initialize state machine (state transition table and initial state). Always must be performed at the very
        // end of contract constructor code.
        _initStateMachine();
    }

    function destroy()
    external
    onlyPandora {
        /// Call event before doing the actual contract suicide
        WorkerDestroyed();

        /// Suiciding
        selfdestruct(owner);
    }

    /// ### Function modifiers

    /// @dev Modifier for functions that can be called only by the main Pandora contract
    modifier onlyPandora() {
        require(pandora != address(0));
        require(msg.sender == address(pandora));
        _;
    }

    /// @dev Modifier for functions that can be called only by one of the active cognitive jobs performed under
    /// main Pandora contract. It includes jobs _not_ assigned to the worker node
    modifier onlyCognitiveJob() {
        require(pandora != address(0));
        ICognitiveJob sender = ICognitiveJob(msg.sender);
        require(pandora == sender.pandora());
        require(pandora.activeJobs(sender) == sender);
        _;
    }

    /// @dev Modifier for functions that can be called only by the cognitive job assigned or performed by the worker
    /// node in one of its active states
    modifier onlyActiveCognitiveJob() {
        require(msg.sender == address(activeJob));
        _;
    }

    /// ### External and public functions

    function alive(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(Offline)
        transitionToState(Idle)
    {
        // Nothing to do here
    }

    /// @notice Do not call
    /// @dev Assigns cognitive job to the worker. Can be called only by one of active cognitive jobs listed under
    /// the main Pandora contract
    function assignJob(
        /// @dev Cognitive job to be assigned
        ICognitiveJob _job
    ) external // Can't be called internally
        /// @dev Must be called only by one of active cognitive jobs listed under the main Pandora contract
        onlyCognitiveJob
        /// @dev Job can be assigned only to Idle workers
        requireState(Idle)
        /// @dev Successful completion must transition worker to an `Assigned` stage
        transitionToState(Assigned)
    {
        activeJob = _job;
    }

    function cancelJob(
        // No arguments
    ) external // Can't be called internally
        onlyActiveCognitiveJob
        requireActiveStates
        transitionToState(Idle)
    {
        activeJob = ICognitiveJob(0);
    }

    function acceptAssignment(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(Assigned)
        transitionToState(ReadyForDataValidation)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.gatheringWorkersResponse(true);
    }

    function declineAssignment(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(Assigned)
        transitionToState(Idle)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.gatheringWorkersResponse(false);
    }

    function processToDataValidation(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(ReadyForDataValidation)
        transitionToState(ValidatingData)
    {
        // All actual work is done by function modifiers
    }

    function acceptValidData(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(ValidatingData)
        transitionToState(ReadyForComputing)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.dataValidationResponse(IJobs.DataValidationResponse.Accept);
    }

    function declineValidData(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(ValidatingData)
        transitionToState(Idle)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.dataValidationResponse(IJobs.DataValidationResponse.Decline);
    }

    function reportInvalidData(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(ValidatingData)
        transitionToState(Idle)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.dataValidationResponse(IJobs.DataValidationResponse.Invalid);
    }

    function processToCognition(
        // No arguments
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(ReadyForComputing)
        transitionToState(Computing)
    {
        // All actual work is done by function modifiers
    }

    function provideResults(
        bytes _ipfsAddress
    ) external // Can't be called internally
        /* @fixme onlyOwner */
        requireState(Computing)
        transitionToState(Idle)
    {
        require(activeJob != ICognitiveJob(0));
        activeJob.completeWork(_ipfsAddress);
    }

    function increaseReputation(
        // No arguments
    ) external // Can't be called internally
        onlyPandora
    {
        reputation++;
    }

    function decreaseReputation(
    ) external // Can't be called internally
        onlyPandora
        transitionThroughState(UnderPenalty)
    {
        if (reputation == 0) {
            pandora.destroyWorkerNode(this);
        } else {
            reputation--;
        }
    }

    function resetReputation(
        // No arguments
    ) external // Can't be called internally
        // Only Pandora contract can put such penalty
        onlyPandora
        // State machine processes
        transitionThroughState(UnderPenalty)
    {
        reputation = 0;
    }

    function maxPenalty(
        // No arguments
    ) external // Can't be called internally
        // Only Pandora contract can put such penalty
        onlyPandora
        // State machine processes
        transitionThroughState(UnderPenalty)
    {
        reputation = 0;
    }

    /// @notice For internal use by main Pandora contract
    /// @dev Zeroes reputation and destroys node
    function deathPenalty(
    ) external // Can't be called internally
        // Only Pandora contract can put such penalty
        onlyPandora
        // State machine processes
        transitionThroughState(UnderPenalty)
    {
        // First, we put remove all reputation
        reputation = 0;

        // Use function from OpenZepplin Destructible contract
        pandora.destroyWorkerNode(this);
    }

    /// @notice Withdraws full balance to the owner account. Can be called only by the owner of the contract.
    function withdrawBalance(
        // No arguments
    ) external // Can't be called internally
        onlyOwner // Can be called only by the owner
        requireStates2(Idle, Offline)
    {
        /// @todo Handle stakes etc
        owner.transfer(this.balance);
    }
}