pragma solidity ^0.4.15;

/*

 */

import 'zeppelin-solidity/contracts/lifecycle/Destructible.sol';
import './Kernel.sol';
import './Dataset.sol';
import './Pandora.sol';
import './WorkerNode.sol';

contract CognitiveJob is Destructible {
    Kernel public kernel;
    Dataset public dataset;
    WorkerNode public workerNode;
    Pandora public pandora;
    bool public completed = false;

    event JobCompleted(bytes ipfsResults);

    function CognitiveJob(
        Pandora _pandora,
        Kernel _kernel,
        Dataset _dataset,
        WorkerNode _workerNode
    ) {
        pandora = _pandora;
        kernel = _kernel;
        dataset = _dataset;
        workerNode = _workerNode;
    }

    modifier onlyWorker() {
        require (msg.sender == workerNode);
        _;
    }

    function commitWork(bytes _ipfsResults) onlyWorker external {
        completed = true;
        pandora.finishCognitiveJob(this);

        JobCompleted(_ipfsResults);
    }
}