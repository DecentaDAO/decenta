// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/* solhint-disable */
contract TestNFT is ERC721URIStorage {
    using Counters for Counters.Counter;

    string internal _uri;

    Counters.Counter internal _tokenIds;

    constructor(string memory uri_) ERC721("TestNFT", "TestNFT") {
        _uri = uri_;
    }


    function mint() external returns (uint256) {
        uint256 newTokenId = _tokenIds.current();
        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _uri);
        _tokenIds.increment();
        return newTokenId;
    }


}