pragma solidity ^0.8.0;

contract Vote {
    struct Proposal {
        address creator;
        uint256 timeCreated;
        bytes content;
        bool active;
        address executor;
        uint256 upVotes;
        uint256 downVotes;
        uint256 end;
        uint256 fee;
        bool refundable;
    }
    mapping(bytes32 => Proposal) public proposals;
    bytes32[] public proposalIds;
    mapping(address => uint256[]) public usersProposals;

    mapping(address => mapping(bytes32 => bool)) public voted;

    mapping(address => mapping(bytes32 => bool)) public refunded;
    mapping(address => bool) public masterProposers;

    address owner;
    uint256 public thresholdMasterPorposer;

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }
    constructor() {
        owner = msg.sender;
    }

    function createProposal(
        bytes memory _content,
        address _executor,
        uint256 _end,
        uint256 _fee
    ) public {
        bytes32 id = keccak256(abi.encode(_content, _executor, _end, _fee));
        require(!proposals[id].active, "already created");

        Proposal memory proposal = Proposal({
            creator: msg.sender,
            timeCreated: block.timestamp,
            content: _content,
            active: true,
            executor: _executor,
            upVotes: 0,
            downVotes: 0,
            end: _end,
            fee: _fee,
            refundable: false
        });

        uint256 index = proposalIds.length;
        usersProposals[msg.sender].push(index);
        proposalIds.push(id);
        proposals[id] = proposal;
    }

    function getProposalContents() public view returns (bytes[] memory) {
        uint256[] memory props = usersProposals[msg.sender];
        bytes32 id;
        bytes[] memory contents = new bytes[](props.length);
        for (uint i = 0; i < props.length; ++i) {
            id = proposalIds[props[i]];
            contents[i] = proposals[id].content;
        }
        return contents;
    }

    function getProposalIds(
        address _proposer
    ) public view returns (bytes32[] memory) {
        uint256[] memory props = usersProposals[_proposer];
        bytes32[] memory ids = new bytes32[](props.length);
        for (uint i = 0; i < props.length; ++i) {
            ids[i] = proposalIds[props[i]];
        }
        return ids;
    }

    function setMasterProposer(address _proposer) public {
        bytes32[] memory ids = getProposalIds(_proposer);
        Proposal memory prop;
        uint256 numOfSuccessfulProposals;
        for (uint i = 0; i < ids.length; ++i) {
            prop = proposals[ids[i]];
            if (block.timestamp < prop.end) continue;
            if (prop.active == true) continue;
            if (prop.refundable == true) continue;
            numOfSuccessfulProposals++;
        }
        require(
            numOfSuccessfulProposals >= thresholdMasterPorposer,
            "not eligible"
        );

        masterProposers[_proposer] = true;
    }

    function vote(bytes32 _id, bool _vote) public payable {
        require(!voted[msg.sender][_id], "already voted");
        voted[msg.sender][_id] = true;

        Proposal storage prop = proposals[_id];
        require(prop.end > block.timestamp, "it is ended");
        require(prop.active, "not active");

        require(msg.value == prop.fee, "not enough paid");

        if (_vote) {
            prop.upVotes++;
        } else {
            prop.downVotes++;
        }
    }

    function execute(bytes32 _id, address _target) public {
        Proposal storage prop = proposals[_id];
        require(prop.end <= block.timestamp, "it is not ended");
        require(prop.active, "not active");
        prop.active = false;

        require(msg.sender == prop.executor, "not authorized");

        uint256 amount = (prop.upVotes + prop.downVotes) * prop.fee;

        if (prop.upVotes > prop.downVotes) {
            (bool success, ) = payable(_target).call{value: amount}(
                prop.content
            );
            require(success, "not successfull call");
        } else {
            prop.refundable = true;
        }
    }

    function refund(bytes32 _id) public {
        require(proposals[_id].refundable, "nonrefundable");
        require(voted[msg.sender][_id], "not voted");
        require(!refunded[msg.sender][_id], "already refunded");
        refunded[msg.sender][_id] = true;
        (bool success, ) = payable(msg.sender).call{value: proposals[_id].fee}(
            ""
        );
        require(success, "not successful");
    }

    function setThresholdMasterProposer(uint256 _threshold) public onlyOwner {
        thresholdMasterPorposer = _threshold;
    }
}
